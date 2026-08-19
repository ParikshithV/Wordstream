//
//  Transcript.swift
//  Wordstream
//

import Foundation
import SwiftData

/// One dictation.
///
/// `rawText` and `finalText` are both kept deliberately. Storing only the finished
/// text would make History a list of results; storing both makes it a before/after
/// of exactly what the cleanup layer did to your words — which is what you need in
/// order to tune the style presets, and to decide whether to trust the thing at all.
@Model
final class Transcript {
    var id: UUID = UUID()
    var createdAt: Date = Date()

    /// Straight out of Whisper, before any cleanup.
    var rawText: String = ""
    /// What was actually inserted.
    var finalText: String = ""

    var durationSeconds: Double = 0
    var wordCount: Int = 0

    /// Where it was inserted, for app-aware formatting and for History attribution.
    var appBundleID: String?
    var appName: String?

    var modelVariant: String = ""
    /// Which enhancement tier produced `finalText` — see `EnhancementTier`.
    var enhancementTier: String = ""

    init(
        rawText: String,
        finalText: String,
        durationSeconds: Double,
        appBundleID: String?,
        appName: String?,
        modelVariant: String,
        enhancementTier: String
    ) {
        self.id = UUID()
        self.createdAt = Date()
        self.rawText = rawText
        self.finalText = finalText
        self.durationSeconds = durationSeconds
        self.wordCount = finalText.split(whereSeparator: \.isWhitespace).count
        self.appBundleID = appBundleID
        self.appName = appName
        self.modelVariant = modelVariant
        self.enhancementTier = enhancementTier
    }

    /// True when the cleanup layer actually changed something worth showing.
    var wasEdited: Bool {
        rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            != finalText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// A term the dictionary should fix up, bias Whisper toward, or both.
@Model
final class DictionaryEntry {
    var id: UUID = UUID()
    var createdAt: Date = Date()

    /// What Whisper tends to produce.
    var spoken: String = ""
    /// What you actually want written.
    var written: String = ""

    /// Also feed this term to Whisper as decode-time context.
    ///
    /// Substituting after the fact can only fix what Whisper got close to.
    /// Seeding the term as a prompt token biases the decoder toward it in the
    /// first place, which is a much stronger lever for names and jargon.
    var isBiasTerm: Bool = true

    init(spoken: String, written: String, isBiasTerm: Bool = true) {
        self.id = UUID()
        self.createdAt = Date()
        self.spoken = spoken
        self.written = written
        self.isBiasTerm = isBiasTerm
    }
}
