//
//  WhisperEngine.swift
//  Wordstream
//

import Foundation
import Observation
import WhisperKit
import os

/// Owns the Whisper model: catalogue, download, load, and the one authoritative
/// transcription pass.
///
/// A single loaded `WhisperKit` instance serves both the live preview and the final
/// pass. The preview's `AudioStreamTranscriber` is built from this instance's own
/// encoder, decoder, tokenizer and audio processor, so turning the preview on costs
/// inference time but not a second copy of the model in memory.
@Observable
@MainActor
final class WhisperEngine {
    enum State: Equatable {
        case idle
        case downloading(Double)
        case loading
        case ready
        case failed(String)

        var isReady: Bool { self == .ready }
    }

    private let log = Logger(subsystem: "app.wordstream", category: "whisper")

    private(set) var state: State = .idle
    private(set) var loadedVariant: String?

    /// The variant the current download/load is for, so the UI can show progress
    /// against the row the user actually pressed rather than against the list as
    /// a whole.
    private(set) var preparingVariant: String?

    /// Variants already on disk. Recomputed rather than remembered in
    /// preferences, because the folder is the only thing that can't go stale —
    /// the user may have deleted it, or restored a Mac without it.
    private(set) var downloadedVariants: Set<String> = []

    /// Catalogue for the onboarding picker.
    private(set) var availableModels: [String] = []
    /// What Argmax recommends for *this* Mac. Pre-selected so choosing a model is
    /// never a blocking step.
    private(set) var recommendedModel: String?

    /// Measured after load: seconds of audio processed per second of wall clock.
    /// Above ~1 the model can keep up with live preview on this machine — which is
    /// worth measuring rather than guessing from the model's name.
    private(set) var realTimeFactor: Double?

    private var kit: WhisperKit?
    private var prepareTask: Task<Void, Never>?

    var audioProcessor: (any AudioProcessing)? { kit?.audioProcessor }

    /// Where Whisper models live on disk.
    ///
    /// This must be passed to *every* WhisperKit entry point that takes a
    /// `downloadBase`, not just the download itself. The parameter is optional
    /// everywhere and defaults to `~/Documents/huggingface`, so any call that
    /// omits it writes there — and on macOS 14+ the first write makes the system
    /// throw up a "Wordstream would like to access files in your Documents
    /// folder" prompt in the middle of onboarding: an alarming ask from a
    /// dictation app, unexplained, and one a refusal leaves permanently broken.
    ///
    /// The catalogue fetch is the easy one to miss, because it downloads a few
    /// kilobytes of `config.json` rather than a model and so doesn't look like a
    /// download at all. It was enough to create `~/Documents/huggingface` and
    /// trigger the prompt on the welcome screen.
    ///
    /// Application Support is the correct location for app-managed data anyway
    /// and carries no TCC gate, so the prompt simply never happens.
    static let modelStorage: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL.homeDirectory.appending(path: "Library/Application Support", directoryHint: .isDirectory)
        let folder = base.appending(path: "Wordstream/Models", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }()

    // MARK: Catalogue

    func refreshCatalogue() async {
        refreshDownloadedVariants()
        let support = await WhisperKit.recommendedRemoteModels(downloadBase: Self.modelStorage)
        recommendedModel = support.default
        availableModels = support.supported.filter { !support.disabled.contains($0) }
        if availableModels.isEmpty { availableModels = [support.default] }
        log.info("Catalogue: \(self.availableModels.count) models, recommended \(support.default, privacy: .public)")
    }

    /// The curated model this Mac should get, or nil until the catalogue is known.
    ///
    /// Mapped through `ModelCatalogue` rather than used raw, so the variant that
    /// downloads by itself is the same row the picker badges "Best for this Mac".
    /// Argmax's own recommendation is one input to that judgement, not the answer.
    var recommendedCuratedVariant: String? {
        ModelCatalogue.recommended(
            for: recommendedModel,
            among: ModelCatalogue.offered(supportedBy: availableModels)
        )?.variant
    }

    // MARK: Load

    /// Downloads and loads a variant, replacing any preparation already running.
    ///
    /// Serialised through a single task so that choosing a second model while the
    /// first is still downloading cancels the first rather than racing it — two
    /// concurrent `WhisperKit` loads would fight over memory and leave
    /// `loadedVariant` describing whichever happened to finish last.
    func prepare(variant: String) async {
        guard loadedVariant != variant || !state.isReady else { return }

        prepareTask?.cancel()
        _ = await prepareTask?.value

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.runPrepare(variant: variant)
        }
        prepareTask = task
        await task.value
        if prepareTask == task { prepareTask = nil }
    }

    /// Stops an in-flight download or load and returns to whatever was true before.
    ///
    /// Partial data is left on disk on purpose: the Hub client resumes from it, so
    /// stopping a 947MB download to pick a smaller model and later changing your
    /// mind doesn't start from zero.
    func cancelPreparation() {
        guard prepareTask != nil else { return }
        prepareTask?.cancel()
        prepareTask = nil
        preparingVariant = nil
        state = loadedVariant == nil ? .idle : .ready
        log.info("Preparation cancelled")
    }

    var isPreparing: Bool { prepareTask != nil }

    private func runPrepare(variant: String) async {
        preparingVariant = variant
        defer {
            if preparingVariant == variant { preparingVariant = nil }
        }

        // A variant already on disk goes straight to loading: the download call
        // below returns immediately for it, so announcing a download would be a
        // claim the user can see is false — the wait they're watching is the
        // load, not a transfer.
        refreshDownloadedVariants()
        state = isDownloaded(variant) ? .loading : .downloading(0)
        loadedVariant = nil
        kit = nil

        do {
            // Downloading explicitly rather than letting `WhisperKit.init` do it,
            // because only the standalone downloader reports progress. Letting init
            // handle it means several hundred megabytes arrive behind a spinner
            // with no indication of how long is left. This returns immediately when
            // the model is already on disk.
            let folder = try await WhisperKit.download(
                variant: variant,
                downloadBase: Self.modelStorage
            ) { [weak self] progress in
                Task { @MainActor [weak self] in
                    guard let self, self.preparingVariant == variant else { return }
                    // Guarded so a stray callback for an on-disk model can't push
                    // the UI back from "loading" to "downloading".
                    guard case .downloading = self.state else { return }
                    self.state = .downloading(progress.fractionCompleted)
                }
            }

            state = .loading

            let config = WhisperKitConfig(
                model: variant,
                downloadBase: Self.modelStorage,
                modelFolder: folder.path,
                verbose: false,
                logLevel: .error,
                prewarm: true,
                load: true,
                download: false
            )

            refreshDownloadedVariants()
            try Task.checkCancellation()

            let kit = try await WhisperKit(config)
            try Task.checkCancellation()

            self.kit = kit
            loadedVariant = variant
            state = .ready
            log.info("Loaded \(variant, privacy: .public)")
            await measureRealTimeFactor()
        } catch is CancellationError {
            // `cancelPreparation` already restored the state; overwriting it here
            // would surface "cancelled" to the user as a failure.
            return
        } catch {
            guard !Task.isCancelled else { return }
            let message = error.localizedDescription
            log.error("Failed to prepare \(variant, privacy: .public): \(message, privacy: .public)")
            state = .failed(message)
        }
    }

    // MARK: On-disk models

    /// Where the Hub client puts this repo's variants under `modelStorage`.
    private static var repoFolder: URL {
        modelStorage.appending(
            path: "models/argmaxinc/whisperkit-coreml", directoryHint: .isDirectory
        )
    }

    /// Where a variant lands under `modelStorage`, mirroring the Hub client's
    /// `downloadBase/models/<repo>/<variant>` layout.
    private static func folder(for variant: String) -> URL {
        repoFolder.appending(path: variant, directoryHint: .isDirectory)
    }

    func isDownloaded(_ variant: String) -> Bool {
        downloadedVariants.contains(variant)
    }

    /// Scans the repo folder rather than testing the offered variants one by one,
    /// so variants chosen before the catalogue was narrowed still report honestly
    /// as being on disk instead of appearing to have vanished.
    func refreshDownloadedVariants() {
        let folders = (try? FileManager.default.contentsOfDirectory(
            at: Self.repoFolder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        )) ?? []

        downloadedVariants = Set(
            folders.filter { folder in
                // A folder alone isn't enough — an interrupted download leaves one
                // behind, and calling that "Downloaded" would offer the user a
                // model that fails to load.
                let contents = try? FileManager.default.contentsOfDirectory(atPath: folder.path)
                return contents?.isEmpty == false
            }.map(\.lastPathComponent)
        )
    }

    /// Removes a downloaded model, unloading it first if it is the live one.
    func delete(_ variant: String) async {
        if loadedVariant == variant { await unload() }
        try? FileManager.default.removeItem(at: Self.folder(for: variant))
        refreshDownloadedVariants()
        log.info("Deleted \(variant, privacy: .public)")
    }

    /// Removes every downloaded variant, not just the ones currently offered.
    ///
    /// Scoped to this app's own `modelStorage` folder, so it can safely take the
    /// whole repo directory rather than walking it — nothing else writes there.
    func deleteAllDownloads() async {
        await unload()
        try? FileManager.default.removeItem(at: Self.repoFolder)
        refreshDownloadedVariants()
        log.info("Deleted all downloaded speech models")
    }

    func unload() async {
        await kit?.unloadModels()
        kit = nil
        loadedVariant = nil
        state = .idle
        realTimeFactor = nil
    }

    /// One warm-up pass over synthetic silence, purely to learn how fast this model
    /// runs on this Mac. It also gets the first real dictation off the cold path.
    private func measureRealTimeFactor() async {
        guard let kit else { return }
        let seconds = 3.0
        let samples = [Float](repeating: 0, count: Int(seconds * 16_000))
        let started = Date()
        _ = try? await kit.transcribe(
            audioArray: samples,
            decodeOptions: DecodingOptions(
                verbose: false, task: .transcribe, language: "en",
                temperatureFallbackCount: 0, withoutTimestamps: true
            )
        )
        let elapsed = Date().timeIntervalSince(started)
        guard elapsed > 0 else { return }
        realTimeFactor = seconds / elapsed
        log.info("Real-time factor: \(self.realTimeFactor ?? 0, format: .fixed(precision: 1))x")
    }

    /// Whether the loaded model can plausibly keep up with the live preview here.
    var canSustainLivePreview: Bool {
        guard let realTimeFactor else { return true }
        return realTimeFactor >= 1.5
    }

    // MARK: Transcribe

    struct TranscriptionOutput {
        let text: String
    }

    /// The authoritative pass, over the complete recording.
    ///
    /// Options are tuned for dictation rather than for transcribing media: language
    /// is pinned because auto-detection is unreliable on a two-second utterance,
    /// timestamps are off because nothing here needs them, and temperature fallback
    /// stays on because a garbled retry is much worse than 200ms of extra latency.
    func transcribe(
        samples: [Float],
        language: String,
        biasTerms: [String]
    ) async throws -> TranscriptionOutput {
        guard let kit else { throw EngineError.notLoaded }

        let options = DecodingOptions(
            verbose: false,
            task: .transcribe,
            language: language,
            temperature: 0,
            temperatureFallbackCount: 2,
            usePrefillPrompt: true,
            detectLanguage: false,
            skipSpecialTokens: true,
            withoutTimestamps: true,
            wordTimestamps: false,
            promptTokens: promptTokens(for: biasTerms),
            suppressBlank: true,
            compressionRatioThreshold: 2.4,
            logProbThreshold: -1.0,
            noSpeechThreshold: 0.6,
            chunkingStrategy: .vad
        )

        let results = try await kit.transcribe(audioArray: samples, decodeOptions: options)
        let text = results.map(\.text).joined(separator: " ")
        return TranscriptionOutput(text: text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Turns dictionary bias terms into decoder conditioning.
    ///
    /// This is the strong half of the personal dictionary. Substituting after the
    /// fact can only repair what Whisper already got close to; seeding the terms as
    /// prompt tokens biases the decoder toward them while it is still choosing, and
    /// that is what actually fixes names, jargon and product spellings.
    private func promptTokens(for terms: [String]) -> [Int]? {
        guard !terms.isEmpty, let tokenizer = kit?.tokenizer else { return nil }
        let prompt = terms.joined(separator: ", ")
        let tokens = tokenizer.encode(text: " \(prompt)")
        // Whisper's prompt window is limited; an over-long dictionary crowds out
        // the audio context and makes transcription worse, not better.
        return Array(tokens.prefix(180))
    }

    // MARK: Live preview

    /// Builds the preview streamer over the already-loaded model.
    ///
    /// Returns nil when nothing is loaded, so the caller falls back to recording
    /// without a preview rather than failing the dictation.
    func makeStreamTranscriber(
        language: String,
        onState: @escaping @Sendable (AudioStreamTranscriber.State) -> Void
    ) -> AudioStreamTranscriber? {
        guard let kit, let tokenizer = kit.tokenizer else { return nil }

        // Deliberately cheap: greedy, no fallbacks, no timestamps. This text is
        // shown and then thrown away, so speed matters and quality does not.
        let options = DecodingOptions(
            verbose: false,
            task: .transcribe,
            language: language,
            temperature: 0,
            temperatureFallbackCount: 0,
            usePrefillPrompt: true,
            detectLanguage: false,
            skipSpecialTokens: true,
            withoutTimestamps: true,
            wordTimestamps: false,
            suppressBlank: true,
            compressionRatioThreshold: 2.4,
            logProbThreshold: -1.0,
            noSpeechThreshold: 0.6
        )

        return AudioStreamTranscriber(
            audioEncoder: kit.audioEncoder,
            featureExtractor: kit.featureExtractor,
            segmentSeeker: kit.segmentSeeker,
            textDecoder: kit.textDecoder,
            tokenizer: tokenizer,
            audioProcessor: kit.audioProcessor,
            decodingOptions: options,
            useVAD: true
        ) { _, newState in
            onState(newState)
        }
    }

    enum EngineError: LocalizedError {
        case notLoaded

        var errorDescription: String? {
            switch self {
            case .notLoaded: "No speech model is loaded yet."
            }
        }
    }
}

extension AudioStreamTranscriber.State {
    /// What the overlay shows while you speak.
    ///
    /// Confirmed *and* unconfirmed segments are both rendered, plus the in-flight
    /// decode. `AudioStreamTranscriber` only promotes text into `confirmedSegments`
    /// once there are more than `requiredSegmentsForConfirmation` of them, so a
    /// short dictation would otherwise display nothing at all until you stopped.
    /// Since this is a preview and not a commitment, showing the raw running
    /// hypothesis — and letting it revise itself — is the correct behaviour.
    var previewText: String {
        var parts = confirmedSegments.map(\.text)
        parts += unconfirmedSegments.map(\.text)
        let joined = parts.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let live = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        // The library uses this string as a placeholder; it is not transcript text.
        guard live != "Waiting for speech..." , !live.isEmpty else { return joined }
        return joined.isEmpty ? live : joined + " " + live
    }
}
