//
//  FoundationModelEnhancer.swift
//  Wordstream
//

import Foundation
import FoundationModels

/// Cleanup on Apple's on-device model. The default tier: no download, no network,
/// no API key, and it is already resident.
/// Structured output rather than free text.
///
/// Asking for a plain string reliably produces "Here's the cleaned-up version:"
/// somewhere in the response, which then gets pasted into the user's document.
/// A guided schema removes the failure mode rather than trying to strip it
/// afterwards.
///
/// Named for what it is rather than for one of its two uses: the same field
/// carries a cleaned dictation in one mode and an edited passage in the other.
///
/// File-scoped rather than nested and private because `@Generable` expands into a
/// separate macro compilation unit, which cannot see a private nested type.
@Generable
struct ModelOutput {
    @Guide(description: "The resulting text, and nothing else. No preamble, no quotes, no commentary.")
    var text: String
}

final class FoundationModelEnhancer: TextEnhancer {

    var isAvailable: Bool {
        get async {
            if case .available = SystemLanguageModel.default.availability { return true }
            return false
        }
    }

    var unavailableReason: String? {
        get async {
            guard case let .unavailable(reason) = SystemLanguageModel.default.availability else {
                return nil
            }
            return switch reason {
            case .appleIntelligenceNotEnabled:
                "Apple Intelligence is turned off. Enable it in System Settings → Apple Intelligence & Siri, then reopen this pane."
            case .deviceNotEligible:
                "This Mac doesn't support Apple Intelligence. Use the local MLX model instead."
            case .modelNotReady:
                "Apple Intelligence is still downloading its model. This usually clears on its own."
            @unknown default:
                "Apple Intelligence isn't available right now."
            }
        }
    }

    func enhance(_ text: String, context: EnhancementContext) async throws -> String {
        guard await isAvailable else {
            throw EnhancementError.unavailable(await unavailableReason ?? "Apple Intelligence is unavailable.")
        }

        // A fresh session per utterance, deliberately. A persistent session would
        // accumulate previous dictations as context, and the model would start
        // "helpfully" continuing the last one.
        let session = LanguageModelSession(
            instructions: EnhancementPrompt.instructions(for: context)
        )

        let response = try await session.respond(
            to: EnhancementPrompt.userTurn(for: text, context: context),
            generating: ModelOutput.self,
            options: GenerationOptions(temperature: 0.1)
        )
        // The guided schema constrains the *shape* of the answer, not its
        // content: the model can still spend the field on a fragment of the
        // schema description it was given. Stripped here for the same reason the
        // MLX tier strips its preambles.
        return EnhancementPrompt.stripDecoration(response.content.text)
    }
}
