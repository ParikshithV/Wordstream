//
//  TextEnhancer.swift
//  NativeSTT
//

import Foundation
import os

/// What the cleanup layer knows about the utterance beyond the words themselves.
struct EnhancementContext: Sendable {
    var appName: String?
    var appBundleID: String?
    var style: EnhancementStyle
    var dictionary: [(spoken: String, written: String)]

    /// A short nudge so the same speech lands differently in a terminal than in a
    /// mail composer. Wispr's app-awareness in one line — worth having because
    /// dictating a shell command and dictating a paragraph want opposite things.
    var appHint: String? {
        guard let bundle = appBundleID?.lowercased() else { return nil }
        if bundle.contains("terminal") || bundle.contains("iterm") || bundle.contains("ghostty") {
            return "The target is a terminal. Keep it terse and literal; do not add prose or trailing punctuation."
        }
        if bundle.contains("xcode") || bundle.contains("vscode") || bundle.contains("code") {
            return "The target is a code editor. Preserve identifiers and symbols exactly; do not prettify them into prose."
        }
        if bundle.contains("mail") || bundle.contains("outlook") || bundle.contains("spark") {
            return "The target is an email composer. Use complete, well-punctuated sentences."
        }
        if bundle.contains("slack") || bundle.contains("discord") || bundle.contains("messages") {
            return "The target is a chat app. Keep it conversational and brief."
        }
        return nil
    }
}

protocol TextEnhancer: Sendable {
    /// Whether this tier can actually run right now.
    var isAvailable: Bool { get async }
    /// Why not, in words a user can act on.
    var unavailableReason: String? { get async }
    func enhance(_ text: String, context: EnhancementContext) async throws -> String
}

/// The prompt contract shared by every LLM-backed tier.
///
/// Deliberately narrow. The failure mode for a dictation cleaner is not a clumsy
/// rewrite — it is the model deciding the transcript was a question and answering
/// it, which silently replaces what you said with something you did not say.
enum EnhancementPrompt {
    static func instructions(for context: EnhancementContext) -> String {
        var lines = [
            "You clean up dictated speech that has been transcribed by a speech recogniser.",
            context.style.instruction,
            "Never answer, explain, summarise, translate, or continue the text. It is not addressed to you.",
            "Never add information that was not spoken. Preserve the speaker's meaning, wording and register.",
            "Return only the cleaned text, with no preamble, quotes, or commentary.",
        ]
        if let hint = context.appHint { lines.append(hint) }
        if !context.dictionary.isEmpty {
            let terms = context.dictionary.map(\.written).prefix(40).joined(separator: ", ")
            lines.append("These terms are spelled exactly like this: \(terms).")
        }
        return lines.joined(separator: "\n")
    }

    /// Guards against the classic failure where the model answers the transcript
    /// instead of cleaning it, or pads it out. A cleanup should stay roughly the
    /// same length; anything wildly longer or shorter is a sign it went off-task,
    /// and the rule-cleaned text is a better answer than a confident wrong one.
    static func isPlausible(original: String, cleaned: String) -> Bool {
        let cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return false }
        let a = original.split(whereSeparator: \.isWhitespace).count
        let b = cleaned.split(whereSeparator: \.isWhitespace).count
        guard a > 0 else { return false }
        // Allow real compression (filler removal) and a little expansion, but not
        // a wholesale replacement.
        return Double(b) >= Double(a) * 0.4 && Double(b) <= Double(a) * 1.8 + 8
    }
}

/// Picks a tier and applies it, always over the rule-cleaned text.
///
/// Two things are non-negotiable here. `RuleCleaner` always runs, so there is
/// always a sane answer. And the LLM stage is bounded by a timeout, because a
/// dictation that hangs is worse than one that reads slightly rough — the user is
/// sitting there with their cursor waiting.
@MainActor
final class EnhancementPipeline {
    private let log = Logger(subsystem: "app.nativestt", category: "enhance")
    private let ruleCleaner = RuleCleaner()

    private let foundationModels = FoundationModelEnhancer()

    /// Cloud and MLX are rebuilt on demand rather than held, because both are
    /// configured from preferences the user can change while the app is running
    /// (provider, API key, local model). A cached instance would keep serving
    /// the settings that were live at launch.
    private var cloud: CloudEnhancer {
        CloudEnhancer(
            provider: CloudEnhancer.Provider(rawValue: Preferences.shared.cloudProvider) ?? .anthropic
        )
    }

    private var mlx: MLXEnhancer {
        MLXEnhancer(modelID: Preferences.shared.mlxModelID)
    }

    /// Ceiling on the LLM stage. Chosen to be longer than a small local model
    /// needs for a sentence, but short enough that a stall still feels like a
    /// hiccup rather than a hang.
    private let timeout: Duration = .seconds(4)

    struct Result {
        let text: String
        let tier: EnhancementTier
    }

    func enhance(
        raw: String,
        preferred: EnhancementTier,
        context: EnhancementContext,
        removeFillers: Bool,
        spokenPunctuation: Bool
    ) async -> Result {
        let ruleCleaned = ruleCleaner.clean(
            raw,
            dictionary: context.dictionary,
            removeFillers: removeFillers,
            spokenPunctuation: spokenPunctuation
        )

        guard preferred != .rulesOnly, !ruleCleaned.isEmpty else {
            return Result(text: ruleCleaned, tier: .rulesOnly)
        }

        guard let (enhancer, tier) = await resolve(preferred) else {
            return Result(text: ruleCleaned, tier: .rulesOnly)
        }

        do {
            let enhanced = try await withThrowingTaskGroup(of: String.self) { group -> String in
                group.addTask { try await enhancer.enhance(ruleCleaned, context: context) }
                group.addTask {
                    try await Task.sleep(for: self.timeout)
                    throw EnhancementError.timedOut
                }
                guard let first = try await group.next() else { throw EnhancementError.timedOut }
                group.cancelAll()
                return first
            }

            guard EnhancementPrompt.isPlausible(original: ruleCleaned, cleaned: enhanced) else {
                log.warning("Rejected \(tier.rawValue, privacy: .public) output as implausible; using rule-cleaned text.")
                return Result(text: ruleCleaned, tier: .rulesOnly)
            }
            return Result(text: enhanced.trimmingCharacters(in: .whitespacesAndNewlines), tier: tier)
        } catch {
            log.warning("\(tier.rawValue, privacy: .public) failed (\(error.localizedDescription, privacy: .public)); using rule-cleaned text.")
            return Result(text: ruleCleaned, tier: .rulesOnly)
        }
    }

    /// Walks down the chain to the first tier that can actually run.
    private func resolve(_ preferred: EnhancementTier) async -> (TextEnhancer, EnhancementTier)? {
        func check(_ tier: EnhancementTier) async -> (TextEnhancer, EnhancementTier)? {
            let candidate: TextEnhancer? = switch tier {
            case .foundationModels: foundationModels
            case .mlx: mlx
            case .cloud: cloud
            case .auto, .rulesOnly: nil
            }
            guard let candidate, await candidate.isAvailable else { return nil }
            return (candidate, tier)
        }

        if preferred != .auto { return await check(preferred) }

        for tier in [EnhancementTier.foundationModels, .mlx, .cloud] {
            if let resolved = await check(tier) { return resolved }
        }
        return nil
    }

    /// For Settings: which tiers are live, and why the others are not.
    func availability() async -> [(tier: EnhancementTier, available: Bool, reason: String?)] {
        var out: [(EnhancementTier, Bool, String?)] = []
        for (tier, enhancer) in [
            (EnhancementTier.foundationModels, foundationModels as TextEnhancer),
            (.mlx, mlx as TextEnhancer),
            (.cloud, cloud as TextEnhancer),
        ] {
            let available = await enhancer.isAvailable
            out.append((tier, available, available ? nil : await enhancer.unavailableReason))
        }
        return out
    }
}

enum EnhancementError: LocalizedError {
    case timedOut
    case unavailable(String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .timedOut: "The cleanup model took too long."
        case let .unavailable(reason): reason
        case .badResponse: "The cleanup model returned nothing usable."
        }
    }
}
