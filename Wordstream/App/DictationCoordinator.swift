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
    /// What the current utterance is for. Set at key-down and read at release,
    /// so a binding changed mid-dictation can't reroute an in-flight one.
    private var trigger: HotkeyMonitor.Trigger = .dictation
    /// The text Command Mode is editing, read at key-down for the same reason
    /// `target` is.
    private var commandSelection: String?
    /// Resolves `commandSelection` when the Accessibility read came up empty and
    /// the slower copy-based read had to be used instead.
    private var commandSelectionTask: Task<String?, Never>?
    private var startedAt: Date?
    private var meterTimer: Timer?
    private var streamer: AudioStreamTranscriber?
    private var streamTask: Task<Void, Never>?

    /// Guards against a release arriving while the previous utterance is still
    /// being transcribed — without it, a fast double-dictation interleaves two
    /// pipelines writing to the same state.
    private var isFinishing = false

    // MARK: Wiring

    func configure(modelContext: ModelContext, overlay: OverlayController) {
        self.modelContext = modelContext
        self.overlay = overlay

        hotkeys.onPress = { [weak self] trigger in self?.begin(trigger) }
        hotkeys.onRelease = { [weak self] _ in self?.finish() }
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

    private func begin(_ trigger: HotkeyMonitor.Trigger) {
        guard !state.isBusy, !isFinishing else { return }
        guard engine.state.isReady else {
            log.warning("Hotkey pressed before a model was ready.")
            flash(.failed("No speech model is loaded yet."))
            return
        }

        // Captured now: by insertion time the user may well be somewhere else,
        // and the text belongs where they were pointing when they started.
        let target = TextInjector.Target.capture()

        commandSelection = nil
        commandSelectionTask = nil

        self.trigger = trigger
        self.target = target
        startedAt = Date()
        previewText = ""
        levels = []
        elapsed = 0
        state = .recording

        overlay?.show()
        startMeter()

        if trigger == .command { captureCommandSelection(in: target) }

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

    /// Resolves what Command Mode is going to edit.
    ///
    /// Read at the start of the utterance rather than at the end for the same
    /// reason `target` is: by the time the instruction has been spoken and
    /// transcribed, the selection may be a different one, or gone.
    ///
    /// Two routes, fast one first. The Accessibility read is synchronous and
    /// costs nothing when it works, which it does for native controls. When it
    /// comes back empty — Electron apps publish no accessibility tree at all
    /// until an assistive client asks for one — the copy-based read takes over,
    /// and that needs a round trip through the other app, so it cannot happen
    /// inside the key-down handler. Recording has already begun by then, which
    /// is fine: the user is still drawing breath.
    private func captureCommandSelection(in target: TextInjector.Target) {
        if let selection = injector.selectedText(in: target), !selection.isEmpty {
            commandSelection = selection
            return
        }

        commandSelectionTask = Task { [weak self] in
            guard let self else { return nil }
            let copied = await injector.selectedTextByCopying()
            commandSelection = copied

            // Abandon early rather than letting someone talk to a command that
            // was never going to run. This lands about 50ms in, so it reads as
            // the key press not taking rather than as a dictation being thrown
            // away.
            if copied == nil, state == .recording, trigger == .command {
                let app = target.app?.localizedName ?? "that app"
                log.info("Command mode: no selection in \(app, privacy: .public) by Accessibility or copy.")
                stopCapture()
                startedAt = nil
                flash(.failed("Couldn't read a selection in \(app)."))
            }
            return copied
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

            // In Command Mode what was just transcribed is the instruction, not
            // the text — the text is what the user had selected when they pressed
            // the key. A short utterance can outrun the copy-based read, so wait
            // for it here rather than treating "not yet" as "nothing selected".
            if trigger == .command, commandSelection == nil {
                _ = await commandSelectionTask?.value
            }

            // A command with no selection must not fall through to the dictation
            // branch. Releasing the key before the copy resolves outruns the early
            // abort in `captureCommandSelection`, and the instruction would then be
            // cleaned up and pasted as though the user had dictated it — so
            // "make this shorter" would type *Make this shorter.* into their
            // document, over the text they were pointing at.
            if trigger == .command, commandSelection == nil {
                let app = target?.app?.localizedName ?? "that app"
                log.info("Command mode reached the pipeline with no selection in \(app, privacy: .public).")
                flash(.failed("Couldn't read a selection in \(app)."))
                return
            }

            let result: EnhancementPipeline.Result
            if let selection = commandSelection {
                result = await pipeline.command(
                    instruction: output.text,
                    selection: selection,
                    preferred: prefs.enhancementTier,
                    context: context
                )
            } else {
                result = await pipeline.enhance(
                    raw: output.text,
                    preferred: prefs.enhancementTier,
                    context: context,
                    removeFillers: prefs.removeFillers,
                    spokenPunctuation: prefs.spokenPunctuation
                )
            }

            // Every Command Mode failure path returns the selection untouched,
            // so an unchanged result means nothing was applied. Say so instead of
            // replacing the selection with itself — that writes an entry onto the
            // user's undo stack and looks, from the outside, exactly like success.
            if let selection = commandSelection, result.text == selection {
                flash(.failed("Couldn't apply that to the selection."))
                return
            }

            state = .inserting
            if let target {
                injector.insert(result.text, into: target, mode: prefs.insertionMode)
            }

            persist(
                // For a command the "before" is the passage that was selected,
                // not the instruction that was spoken — that keeps History a
                // before/after of the text, which is what it is for. The
                // instruction itself is transient.
                raw: commandSelection ?? output.text,
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
        commandSelectionTask?.cancel()
        commandSelectionTask = nil
        commandSelection = nil
        trigger = .dictation
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
            trigger == .command
                ? .readyAndListening(eyebrow: "Command", headline: "Say what to do with the selection")
                : .readyAndListening(eyebrow: "Listening", headline: "Speak now")
        case .transcribing:
            .formingAResolution(eyebrow: "Transcribing", headline: "Working out what you said")
        case .enhancing:
            trigger == .command
                ? .formingAResolution(eyebrow: "Editing", headline: "Applying your instruction")
                : .formingAResolution(eyebrow: "Polishing", headline: "Tidying it up")
        case .inserting:
            .formingAResolution(eyebrow: "Inserting", headline: "Placing your text")
        case let .failed(message):
            .holdingSteady(eyebrow: "Problem", headline: message)
        }
    }
}
