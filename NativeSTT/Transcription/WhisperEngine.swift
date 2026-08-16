//
//  WhisperEngine.swift
//  NativeSTT
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

    private let log = Logger(subsystem: "app.nativestt", category: "whisper")

    private(set) var state: State = .idle
    private(set) var loadedVariant: String?

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

    var audioProcessor: (any AudioProcessing)? { kit?.audioProcessor }

    // MARK: Catalogue

    func refreshCatalogue() async {
        let support = await WhisperKit.recommendedRemoteModels()
        recommendedModel = support.default
        availableModels = support.supported.filter { !support.disabled.contains($0) }
        if availableModels.isEmpty { availableModels = [support.default] }
        log.info("Catalogue: \(self.availableModels.count) models, recommended \(support.default, privacy: .public)")
    }

    // MARK: Load

    func prepare(variant: String) async {
        guard loadedVariant != variant || !state.isReady else { return }

        state = .downloading(0)
        loadedVariant = nil
        kit = nil

        do {
            // Downloading explicitly rather than letting `WhisperKit.init` do it,
            // because only the standalone downloader reports progress. Letting init
            // handle it means several hundred megabytes arrive behind a spinner
            // with no indication of how long is left. This returns immediately when
            // the model is already on disk.
            let folder = try await WhisperKit.download(variant: variant) { [weak self] progress in
                Task { @MainActor [weak self] in
                    self?.state = .downloading(progress.fractionCompleted)
                }
            }

            state = .loading

            let config = WhisperKitConfig(
                model: variant,
                modelFolder: folder.path,
                verbose: false,
                logLevel: .error,
                prewarm: true,
                load: true,
                download: false
            )

            let kit = try await WhisperKit(config)
            self.kit = kit
            loadedVariant = variant
            state = .ready
            log.info("Loaded \(variant, privacy: .public)")
            await measureRealTimeFactor()
        } catch {
            let message = error.localizedDescription
            log.error("Failed to prepare \(variant, privacy: .public): \(message, privacy: .public)")
            state = .failed(message)
        }
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
        let language: String
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
        return TranscriptionOutput(
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            language: results.first?.language ?? language
        )
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
