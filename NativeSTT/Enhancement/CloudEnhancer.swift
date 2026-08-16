//
//  CloudEnhancer.swift
//  NativeSTT
//

import Foundation

/// Optional cloud cleanup. Off by default.
///
/// This is the one tier that sends your speech off this Mac, so it is opt-in,
/// clearly labelled in Settings, and requires you to paste your own key. Raw
/// HTTP rather than an SDK because Anthropic ships no official Swift SDK —
/// URLSession against the documented wire format is the supported path here.
final class CloudEnhancer: TextEnhancer {
    enum Provider: String, CaseIterable, Sendable {
        case anthropic, openai

        var displayName: String {
            switch self {
            case .anthropic: "Anthropic (Claude)"
            case .openai: "OpenAI"
            }
        }

        var keychainAccount: String { "cloud.\(rawValue)" }

        var keyHint: String {
            switch self {
            case .anthropic: "Starts with sk-ant-"
            case .openai: "Starts with sk-"
            }
        }
    }

    private let provider: Provider
    private let session: URLSession

    init(provider: Provider = .anthropic) {
        self.provider = provider
        let config = URLSessionConfiguration.ephemeral
        // Bounded well under the pipeline's own timeout so a slow network
        // surfaces as a fallback rather than a hang.
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 12
        self.session = URLSession(configuration: config)
    }

    var isAvailable: Bool {
        get async { Keychain.has(provider.keychainAccount) }
    }

    var unavailableReason: String? {
        get async {
            Keychain.has(provider.keychainAccount)
                ? nil
                : "No \(provider.displayName) API key saved. Add one in Settings → AI."
        }
    }

    func enhance(_ text: String, context: EnhancementContext) async throws -> String {
        guard let key = Keychain.get(provider.keychainAccount), !key.isEmpty else {
            throw EnhancementError.unavailable("No \(provider.displayName) API key saved.")
        }

        return switch provider {
        case .anthropic: try await callAnthropic(text, context: context, key: key)
        case .openai: try await callOpenAI(text, context: context, key: key)
        }
    }

    // MARK: Anthropic

    /// Schema-constrained output, so the model cannot wrap the result in prose.
    private static let outputSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "text": [
                "type": "string",
                "description": "The cleaned dictation and nothing else.",
            ],
        ],
        "required": ["text"],
        "additionalProperties": false,
    ]

    private func callAnthropic(_ text: String, context: EnhancementContext, key: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        // Opens the `fallbacks` parameter below.
        request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")

        let body: [String: Any] = [
            "model": "claude-opus-5",
            "max_tokens": 2048,
            "system": EnhancementPrompt.instructions(for: context),
            "messages": [["role": "user", "content": text]],
            "output_config": [
                // Cleanup is a narrow, formulaic task; deep reasoning would only
                // buy latency on a path the user is waiting behind.
                "effort": "low",
                "format": ["type": "json_schema", "schema": Self.outputSchema],
            ],
            // Safety classifiers can decline a request outright. Without this the
            // call just stops; with it the API re-serves on a fallback model in
            // the same round trip.
            "fallbacks": "default",
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        try Self.checkStatus(response, data: data)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw EnhancementError.badResponse
        }

        // Check stop_reason before touching content: on a refusal the content
        // array is empty (pre-output) or partial (mid-stream), so indexing it
        // first is exactly how this breaks.
        if json["stop_reason"] as? String == "refusal" {
            throw EnhancementError.unavailable("The cloud model declined to process this text.")
        }

        guard let content = json["content"] as? [[String: Any]] else {
            throw EnhancementError.badResponse
        }
        let raw = content
            .filter { $0["type"] as? String == "text" }
            .compactMap { $0["text"] as? String }
            .joined()

        return try Self.unwrapSchemaText(raw)
    }

    // MARK: OpenAI

    private func callOpenAI(_ text: String, context: EnhancementContext, key: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "authorization")

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": EnhancementPrompt.instructions(for: context)],
                ["role": "user", "content": text],
            ],
            "response_format": [
                "type": "json_schema",
                "json_schema": [
                    "name": "cleaned_text",
                    "strict": true,
                    "schema": Self.outputSchema,
                ],
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        try Self.checkStatus(response, data: data)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let raw = message["content"] as? String
        else { throw EnhancementError.badResponse }

        return try Self.unwrapSchemaText(raw)
    }

    // MARK: Shared

    private static func checkStatus(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let detail = (try? JSONSerialization.jsonObject(with: data))
                .flatMap { ($0 as? [String: Any])?["error"] as? [String: Any] }
                .flatMap { $0["message"] as? String }
            throw EnhancementError.unavailable(detail ?? "Cloud request failed (HTTP \(http.statusCode)).")
        }
    }

    private static func unwrapSchemaText(_ raw: String) throws -> String {
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = object["text"] as? String
        else {
            // The schema should make this unreachable, but a bare string is
            // still usable — better than discarding a good result on a
            // formatting technicality.
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw EnhancementError.badResponse }
            return trimmed
        }
        return value
    }
}
