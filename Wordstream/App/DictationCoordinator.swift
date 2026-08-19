//
//  DictationCoordinator.swift
//  Wordstream
//

import AppKit
import Observation
import SwiftData
import WhisperKit
import os

/// The state machine that turns a held key into text in someone else's app.
@Observable
@MainActor
final class DictationCoordinator {
    enum State: Equatable {
        case idle
        case recording
        case transcribing
        case enhancing
        case inserting
        case failed(String)

        var isBusy: Bool {
            switch self {
            case .idle, .failed: false
            default: true
            }
        }
    }

    private let log = Logger(subsystem: "app.wordstream", category: "dictation")

    private(set) var state: State = .idle
    /// Live transcript while speaking. Display only — thrown away at release.
    private(set) var previewText: String = ""
    /// Amplitude buffer driving the §7 waveform.
    private(set) var levels: [Float] = []
    private(set) var elapsed: TimeInterval = 0
    private(set) var lastTranscript: Transcript?

    let engine = WhisperEngine()
    let permissions = PermissionsManager()
    private let hotkeys = HotkeyMonitor()
    private let injector = TextInjector()
    private let pipeline = EnhancementPipeline()
    private let prefs = Preferences.shared

    private var modelContext: ModelContext?
    private var overlay: OverlayController?

    private var target: TextInjector.Target?
    private var startedAt: Date?
    private var meterTimer: Timer?
    private var streamer: AudioStreamTranscriber?
    private var streamTask: Task<Void, Never>?

    /// Guards against a release arriving while the previous utterance is still
    /// being transcribed — without it, a fast double-dictation interleaves two
    /// pipelines writing to the same state.
    private var isFinishing = false

    var isHandsFreeActive: Bool { hotkeys.isHandsFreeActive }

    // MARK: Wiring

    func configure(modelContext: ModelContext, overlay: OverlayController) {
        self.modelContext = modelContext
        self.overlay = overlay

        hotkeys.onPress = { [weak self] in self?.begin() }
        hotkeys.onRelease = { [weak self] in self?.finish() }
        hotkeys.onCancel = { [weak self] in self?.cancel() }
        permissions.observeActivation()

        applyShortcuts()
    }

    func applyShortcuts() {
        hotkeys.configure(
            dictation: prefs.dictationShortcut,
            commandMode: prefs.commandModeShortcut,
            handsFreeOnDoubleTap: prefs.handsFreeOnDoubleTap
        )
    }

    @discardableResult
    func startMonitoring() -> Bool {
        hotkeys.start()
    }

    func restartMonitoring() {
        hotkeys.restart()
    }

    var isMonitoring: Bool { hotkeys.isRunning }

    /// Loads the model the user already chose.
    ///
    /// Deliberately does nothing when none has been chosen. It used to fall back
    /// to the per-device recommendation and download it, which meant first launch
    /// started a several-hundred-megabyte transfer during the welcome screen —
    /// before the user had been told a download was coming, and racing the model
    /// step they were about to be shown. Onboarding now starts that download
    /// explicitly, from the row the user presses.
    func prepareModel() async {
        await engine.refreshCatalogue()
        let variant = prefs.modelVariant
        guard !variant.isEmpty else { return }
        await engine.prepare(variant: variant)
    }

    // MARK: Recording

    private func begin() {
        guard !state.isBusy, !isFinishing else { return }
        guard engine.state.isReady else {
            log.warning("Hotkey pressed before a model was ready.")
            flash(.failed("No speech model is loaded yet."))
            return
        }

        // Captured now: by insertion time the user may well be somewhere else,
        // and the text belongs where they were pointing when they started.
        target = TextInjector.Target.capture()
        startedAt = Date()
        previewText = ""
        levels = []
        elapsed = 0
        state = .recording

        overlay?.show()
        startMeter()

        if prefs.livePreview {
            startLivePreview()
        } else if let processor = engine.audioProcessor {
            do {
                try processor.startRecordingLive(inputDeviceID: nil, callback: nil)
            } catch {
                fail("Couldn't start the microphone: \(error.localizedDescription)")
            }
        }
    }

    private func startLivePreview() {
        guard let streamer = engine.makeStreamTranscriber(
            language: prefs.language,
            onState: { [weak self] newState in
                Task { @MainActor [weak self] in
                    self?.previewText = newState.previewText
                }
            }
        ) else {
            // Preview couldn't be built; fall back to plain recording rather
            // than failing the dictation.
            try? engine.audioProcessor?.startRecordingLive(inputDeviceID: nil, callback: nil)
            return
        }

        self.streamer = streamer
        streamTask = Task {
            do {
                try await streamer.startStreamTranscription()
            } catch is CancellationError {
                // Expected on release.
            } catch {
                self.log.warning("Live preview stopped: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func startMeter() {
        meterTimer?.invalidate()
        // 30fps, matching the §7 waveform spec.
        meterTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let processor = self.engine.audioProcessor else { return }
                self.levels = Array(processor.relativeEnergy.suffix(48))
                if let startedAt = self.startedAt {
                    self.elapsed = Date().timeIntervalSince(startedAt)
                }
            }
        }
    }

    private func stopCapture() {
        meterTimer?.invalidate()
        meterTimer = nil
        streamTask?.cancel()
        streamTask = nil
        if let streamer {
            Task { await streamer.stopStreamTranscription() }
        }
        streamer = nil
        engine.audioProcessor?.stopRecording()
    }

    // MARK: Finish

    private func finish() {
        guard state == .recording, !isFinishing else { return }
        isFinishing = true

        // Stop the preview before the final pass so it isn't competing for the
        // Neural Engine with the transcription the user is actually waiting on.
        stopCapture()

        let samples = Array(engine.audioProcessor?.audioSamples ?? [])
        let duration = startedAt.map { Date().timeIntervalSince($0) } ?? 0
        let captured = target
        startedAt = nil

        guard duration >= 0.35, hasSpeech(samples) else {
            // A stray key tap shouldn't produce a spinner or an empty paste.
            log.info("Discarded \(String(format: "%.2f", duration))s of audio (\(samples.count) samples) with no speech.")
            reset()
            return
        }

        Task { await runPipeline(samples: samples, duration: duration, target: captured) }
    }

    /// Rejects an empty capture without rejecting quiet speech.
    ///
    /// This was `EnergyVAD()`, whose 0.02 RMS threshold is *absolute*. A normal
    /// speaking voice into a built-in mic lands nearer 0.005, so real dictation
    /// was being thrown away — visibly, since the live preview had already
    /// transcribed the very words this gate then declared silent. (The preview
    /// never agreed because `AudioStreamTranscriber` measures energy relative to
    /// the room, not against a fixed number.)
    ///
    /// The replacement asks only whether the loudest 100ms of the capture rises
    /// above microphone self-noise — roughly an order of magnitude below speech,
    /// and an order of magnitude above a silent room. Deliberately permissive:
    /// this gate exists so a stray key tap skips the spinner, and everything
    /// past it is adjudicated properly by Whisper's own `noSpeechThreshold` and
    /// the empty-output check in `runPipeline`. A loud room with no speech gets
    /// through, and that is the right trade — the cost is a wasted transcribe,
    /// where the cost of the old behaviour was losing what the user said.
    private func hasSpeech(_ samples: [Float]) -> Bool {
        let frame = WhisperKit.sampleRate / 10
        guard samples.count >= frame else { return false }

        var peak: Float = 0
        for start in stride(from: 0, through: samples.count - frame, by: frame) {
            let energy = AudioProcessor.calculateAverageEnergy(
                of: Array(samples[start..<start + frame])
            )
            peak = max(peak, energy)
        }

        return peak > 0.0015
    }

    private func runPipeline(samples: [Float], duration: TimeInterval, target: TextInjector.Target?) async {
        state = .transcribing

        let dictionary = loadDictionary()

        do {
            let output = try await engine.transcribe(
                samples: samples,
                language: prefs.language,
                biasTerms: dictionary.filter(\.isBiasTerm).map(\.written)
            )

            guard !output.text.isEmpty else {
                log.info("Transcription came back empty.")
                reset()
                return
            }

            state = .enhancing
            let context = EnhancementContext(
                appName: target?.app?.localizedName,
                appBundleID: target?.app?.bundleIdentifier,
                style: prefs.enhancementStyle,
                dictionary: dictionary.map { ($0.spoken, $0.written) }
            )

            let result = await pipeline.enhance(
                raw: output.text,
                preferred: prefs.enhancementTier,
                context: context,
                removeFillers: prefs.removeFillers,
                spokenPunctuation: prefs.spokenPunctuation
            )

            state = .inserting
            if let target {
                injector.insert(result.text, into: target, mode: prefs.insertionMode)
            }

            persist(
                raw: output.text,
                final: result.text,
                tier: result.tier,
                duration: duration,
                target: target
            )

            if prefs.playSounds { NSSound(named: "Tink")?.play() }
            reset()
        } catch {
            fail(error.localizedDescription)
        }
    }

    private func cancel() {
        guard state == .recording else { return }
        // Nothing has been typed into the target app yet, so cancelling really
        // is free — this is the payoff for transcribing on release.
        stopCapture()
        startedAt = nil
        log.info("Dictation cancelled.")
        reset()
    }

    // MARK: State helpers

    private func reset() {
        isFinishing = false
        hotkeys.handsFreeDidStop()
        previewText = ""
        levels = []
        elapsed = 0
        state = .idle
        overlay?.hide()
    }

    private func fail(_ message: String) {
        log.error("\(message, privacy: .public)")
        flash(.failed(message))
    }

    private func flash(_ newState: State) {
        isFinishing = false
        state = newState
        overlay?.show()
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            if case .failed = self.state { self.reset() }
        }
    }

    // MARK: Persistence

    private func loadDictionary() -> [DictionaryEntry] {
        guard let modelContext else { return [] }
        let descriptor = FetchDescriptor<DictionaryEntry>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func persist(
        raw: String,
        final: String,
        tier: EnhancementTier,
        duration: TimeInterval,
        target: TextInjector.Target?
    ) {
        guard let modelContext else { return }
        let transcript = Transcript(
            rawText: raw,
            finalText: final,
            durationSeconds: duration,
            appBundleID: target?.app?.bundleIdentifier,
            appName: target?.app?.localizedName,
            modelVariant: engine.loadedVariant ?? "",
            enhancementTier: tier.rawValue
        )
        modelContext.insert(transcript)
        lastTranscript = transcript
        try? modelContext.save()
    }

    // MARK: Assistant state

    /// Maps the dictation state onto the design system's three assistant states,
    /// so the motif's scale carries the machine's status instead of the copy
    /// having to shout it.
    var assistantState: AssistantState {
        switch state {
        case .idle:
            .readyAndListening(eyebrow: "Ready", headline: "Hold to dictate")
        case .recording:
            .readyAndListening(eyebrow: "Listening", headline: "Speak now")
        case .transcribing:
            .formingAResolution(eyebrow: "Transcribing", headline: "Working out what you said")
        case .enhancing:
            .formingAResolution(eyebrow: "Polishing", headline: "Tidying it up")
        case .inserting:
            .formingAResolution(eyebrow: "Inserting", headline: "Placing your text")
        case let .failed(message):
            .holdingSteady(eyebrow: "Problem", headline: message)
        }
    }
}
