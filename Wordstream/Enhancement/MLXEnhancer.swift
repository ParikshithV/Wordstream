//
//  MLXEnhancer.swift
//  Wordstream
//

import Foundation
import os

#if canImport(MLXLLM)
import MLXLLM
import MLXLMCommon
import MLXHuggingFace
// `#huggingFaceLoadModelContainer` is a freestanding macro: it expands inline
// into *this* file and references `HuggingFace.HubClient` and `Tokenizers`
// directly. That is why mlx-swift-lm doesn't depend on them itself — the
// consuming app supplies them, and they must be imported at the use site or the
// expansion won't compile.
import HuggingFace
import Tokenizers
#endif

/// Local LLM cleanup, for when Apple Intelligence isn't available.
///
/// This is the tier that keeps the AI cleanup working on a Mac where Apple
/// Intelligence is switched off or the hardware isn't eligible — without which
/// those users would drop straight to rule-based cleanup.
///
/// Cleaning up dictated text is narrow and formulaic, so it doesn't need a large
/// model: the default is Gemma 3 1B, quantization-aware-trained at 4-bit
/// (~0.7 GB), which holds up far better at that size than a naively-quantized
/// model would. The download is opt-in and on demand, exactly like Whisper's.
///
/// A useful property of this pairing: **MLX runs on the GPU while WhisperKit runs
/// on the Neural Engine**, so the cleanup pass doesn't contend with transcription
/// for the same silicon.
///
/// The whole file is written against `canImport(MLXLLM)` so the app builds and
/// runs correctly both before and after the MLX package is added — with the
/// dependency absent, this tier simply reports itself unavailable and the
/// pipeline falls through to the next one.
final class MLXEnhancer: TextEnhancer {
    private let log = Logger(subsystem: "app.wordstream", category: "mlx")

    /// Where the model cache lives, so Settings can show its size and offer to
    /// remove it.
    static var cacheDirectory: URL {
        URL.homeDirectory
            .appending(path: ".cache/huggingface/hub", directoryHint: .isDirectory)
    }

    static let defaultModelID = "mlx-community/gemma-3-1b-it-qat-4bit"

    /// Curated shortlist. All instruct-tuned and 4-bit, since the task is
    /// rewriting rather than reasoning.
    static let availableModels: [(id: String, name: String, size: String)] = [
        ("mlx-community/gemma-3-1b-it-qat-4bit", "Gemma 3 1B (QAT)", "~0.7 GB"),
        ("mlx-community/Qwen2.5-1.5B-Instruct-4bit", "Qwen 2.5 1.5B", "~0.9 GB"),
        ("mlx-community/Llama-3.2-3B-Instruct-4bit", "Llama 3.2 3B", "~1.8 GB"),
    ]

    private let modelID: String

    init(modelID: String = MLXEnhancer.defaultModelID) {
        self.modelID = modelID
    }

    #if canImport(MLXLLM)

    /// Loaded once and kept warm — reloading weights per dictation would cost
    /// several seconds every time.
    private actor ModelHolder {
        private var container: ModelContainer?
        private var loadedID: String?

        func container(
            for id: String,
            progress: (@Sendable (Double) -> Void)? = nil
        ) async throws -> ModelContainer {
            if let container, loadedID == id {
                progress?(1)
                return container
            }
            let configuration = ModelConfiguration(id: id)
            let loaded = try await #huggingFaceLoadModelContainer(
                configuration: configuration,
                progressHandler: { p in progress?(p.fractionCompleted) }
            )
            container = loaded
            loadedID = id
            return loaded
        }
    }

    private static let holder = ModelHolder()

    var isAvailable: Bool {
        get async { isModelDownloaded }
    }

    var unavailableReason: String? {
        get async {
            isModelDownloaded ? nil : "The weights haven't been downloaded yet."
        }
    }

    func enhance(_ text: String, context: EnhancementContext) async throws -> String {
        let container = try await Self.holder.container(for: modelID)
        // `instructions` puts the prompt contract in the model's system role
        // rather than concatenating it into the user turn, which small models
        // are much more likely to echo back as part of the answer.
        let session = ChatSession(
            container,
            instructions: EnhancementPrompt.instructions(for: context)
        )
        let response = try await session.respond(to: text)
        return Self.stripPreamble(response)
    }

    /// Downloads the weights, reporting progress so Settings isn't a dead spinner
    /// for the better part of a gigabyte.
    func download(progress: @escaping @Sendable (Double) -> Void) async throws {
        _ = try await Self.holder.container(for: modelID, progress: progress)
    }

    #else

    var isAvailable: Bool { get async { false } }

    var unavailableReason: String? {
        get async { "This build doesn't include the local MLX model support." }
    }

    func enhance(_ text: String, context: EnhancementContext) async throws -> String {
        throw EnhancementError.unavailable("Local MLX model support isn't compiled into this build.")
    }

    func download(progress: @escaping @Sendable (Double) -> Void) async throws {
        throw EnhancementError.unavailable("Local MLX model support isn't compiled into this build.")
    }

    #endif

    /// Whether the weights are already on disk, so Settings can distinguish
    /// "not set up" from "downloading" without starting a download to find out.
    var isModelDownloaded: Bool {
        let folder = modelID.replacingOccurrences(of: "/", with: "--")
        let path = Self.cacheDirectory.appending(path: "models--\(folder)")
        return FileManager.default.fileExists(atPath: path.path)
    }

    /// Small local models like to open with "Sure, here's the cleaned text:".
    /// Foundation Models solves this with a guided schema; MLX has no equivalent,
    /// so the preamble is stripped here instead.
    private static func stripPreamble(_ response: String) -> String {
        var text = response.trimmingCharacters(in: .whitespacesAndNewlines)

        let markers = [
            "here's the cleaned text:", "here is the cleaned text:",
            "cleaned text:", "cleaned-up text:", "output:", "result:",
        ]
        let lowered = text.lowercased()
        for marker in markers where lowered.hasPrefix(marker) {
            text = String(text.dropFirst(marker.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            break
        }

        // Some models fence the answer even when nothing asked them to.
        if text.hasPrefix("```") {
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            let inner = lines.dropFirst().prefix { !$0.hasPrefix("```") }
            text = inner.joined(separator: "\n")
        }

        if text.count > 1, text.hasPrefix("\""), text.hasSuffix("\"") {
            text = String(text.dropFirst().dropLast())
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
