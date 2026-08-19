//
//  Preferences.swift
//  Wordstream
//

import SwiftUI
import Observation

enum InsertionMode: String, CaseIterable, Codable {
    case paste, accessibility

    var displayName: String {
        switch self {
        case .paste: "Paste (recommended)"
        case .accessibility: "Accessibility API"
        }
    }

    var explanation: String {
        switch self {
        case .paste:
            "Copies the text, sends ⌘V, then restores your clipboard. Works everywhere, including Electron apps like VS Code and Slack."
        case .accessibility:
            "Writes directly into the focused field without touching the clipboard. Cleaner, but silently does nothing in some apps — it falls back to Paste when that happens."
        }
    }
}

enum EnhancementTier: String, CaseIterable, Codable {
    case auto, foundationModels, mlx, cloud, rulesOnly

    var displayName: String {
        switch self {
        case .auto: "Automatic"
        case .foundationModels: "Apple Intelligence"
        case .mlx: "Local model"
        case .cloud: "Cloud"
        case .rulesOnly: "Rules only"
        }
    }

    /// One line on what the tier is, in terms of where it runs and what it costs
    /// — the two things that actually decide this for someone.
    var summary: String {
        switch self {
        case .auto:
            "Uses the best engine set up on this Mac, and falls back on its own when one can't run."
        case .foundationModels:
            "Apple's on-device model. Nothing to download, nothing leaves your Mac."
        case .mlx:
            "A small model on this Mac's GPU. The local option when Apple Intelligence isn't available."
        case .cloud:
            "Sends the transcribed text to a provider you choose. Everything else stays on your Mac."
        case .rulesOnly:
            "No language model at all — punctuation, spacing and filler removal only."
        }
    }

    /// Whether choosing this tier also means configuring something: a download,
    /// an API key. Setup for these opens inside the row that selects them.
    var needsSetup: Bool {
        self == .mlx || self == .cloud
    }
}

enum EnhancementStyle: String, CaseIterable, Codable {
    case verbatim, cleanUp, polished, email, bullets

    var displayName: String {
        switch self {
        case .verbatim: "Verbatim"
        case .cleanUp: "Clean up"
        case .polished: "Polished"
        case .email: "Email"
        case .bullets: "Bullets"
        }
    }

    /// The same intent as `instruction`, said to the person choosing rather than
    /// to the model. The prompt text is precise because a model reads it; it is a
    /// poor label for the same reason.
    var summary: String {
        switch self {
        case .verbatim: "Only clear mistakes and end punctuation."
        case .cleanUp: "Filler and false starts out, your own words kept."
        case .polished: "Tightened into clear prose, same meaning."
        case .email: "Complete sentences, ready to send."
        case .bullets: "One idea per bullet."
        }
    }

    var instruction: String {
        switch self {
        case .verbatim:
            "Change as little as possible. Fix only clear transcription errors and add sentence-ending punctuation."
        case .cleanUp:
            "Remove filler words and false starts, apply the speaker's self-corrections, and fix punctuation and capitalisation. Keep the speaker's own words and tone."
        case .polished:
            "Tighten the phrasing into clear, well-formed prose while preserving the speaker's meaning and register."
        case .email:
            "Format as a short, well-punctuated email body in complete sentences. No greeting or sign-off unless the speaker dictated one."
        case .bullets:
            "Format as a concise bulleted list, one idea per bullet, using '- ' as the marker."
        }
    }
}

enum AppearanceMode: String, CaseIterable, Codable {
    case system, light, dark

    var displayName: String {
        switch self {
        case .system: "Match system"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

/// UserDefaults-backed settings.
///
/// `@Observable` over a plain defaults store rather than a pile of `@AppStorage`
/// properties, so non-View code (the coordinator, the hotkey monitor) can read
/// settings without pretending to be a View.
@Observable
@MainActor
final class Preferences {
    static let shared = Preferences()

    private let defaults = UserDefaults.standard

    private func get<T>(_ key: String, _ fallback: T) -> T {
        defaults.object(forKey: key) as? T ?? fallback
    }

    private func set<T>(_ key: String, _ value: T) {
        defaults.set(value, forKey: key)
    }

    // MARK: Shortcuts

    var dictationShortcut: Shortcut {
        didSet { store(dictationShortcut, "shortcut.dictation") }
    }

    var commandModeShortcut: Shortcut? {
        didSet { store(commandModeShortcut, "shortcut.commandMode") }
    }

    /// Double-tapping the dictation key toggles hands-free instead of requiring a hold.
    var handsFreeOnDoubleTap: Bool {
        didSet { set("handsFreeOnDoubleTap", handsFreeOnDoubleTap) }
    }

    // MARK: Transcription

    var modelVariant: String {
        didSet { set("modelVariant", modelVariant) }
    }

    /// `nil` means auto-detect, which is unreliable on a two-second utterance —
    /// hence the pinned default.
    var language: String {
        didSet { set("language", language) }
    }

    /// Lists every Whisper build this Mac supports instead of the five curated
    /// ones. Persisted rather than per-window state, because someone who wants the
    /// full catalogue wants it every time they open this panel, not once.
    var showAllSpeechModels: Bool {
        didSet { set("showAllSpeechModels", showAllSpeechModels) }
    }

    /// Runs WhisperKit's `AudioStreamTranscriber` during recording so the overlay
    /// can show text as you speak. Costs inference while you talk; the transcript
    /// that gets inserted always comes from the final pass either way.
    var livePreview: Bool {
        didSet { set("livePreview", livePreview) }
    }

    // MARK: Insertion

    var insertionMode: InsertionMode {
        didSet { set("insertionMode", insertionMode.rawValue) }
    }

    var playSounds: Bool {
        didSet { set("playSounds", playSounds) }
    }

    // MARK: Enhancement

    var enhancementTier: EnhancementTier {
        didSet { set("enhancementTier", enhancementTier.rawValue) }
    }

    var enhancementStyle: EnhancementStyle {
        didSet { set("enhancementStyle", enhancementStyle.rawValue) }
    }

    var removeFillers: Bool {
        didSet { set("removeFillers", removeFillers) }
    }

    var spokenPunctuation: Bool {
        didSet { set("spokenPunctuation", spokenPunctuation) }
    }

    var cloudProvider: String {
        didSet { set("cloudProvider", cloudProvider) }
    }

    var mlxModelID: String {
        didSet { set("mlxModelID", mlxModelID) }
    }

    // MARK: Appearance

    var palette: Palette {
        didSet { set("palette", palette.rawValue) }
    }

    var appearance: AppearanceMode {
        didSet {
            set("appearance", appearance.rawValue)
            applyAppKitAppearance()
        }
    }

    /// Keep AppKit chrome (popovers, pop-up buttons, fields, lists) on the same
    /// light/dark as the SwiftUI tokens. `preferredColorScheme` alone does not
    /// reach every hosted control in a menu-bar extra.
    func applyAppKitAppearance() {
        switch appearance {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    // MARK: Lifecycle

    var hasCompletedOnboarding: Bool {
        didSet { set("hasCompletedOnboarding", hasCompletedOnboarding) }
    }

    var launchAtLogin: Bool {
        didSet { set("launchAtLogin", launchAtLogin) }
    }

    private init() {
        let d = UserDefaults.standard
        dictationShortcut = Preferences.load(d, "shortcut.dictation") ?? .rightOption
        commandModeShortcut = Preferences.load(d, "shortcut.commandMode")
        handsFreeOnDoubleTap = d.object(forKey: "handsFreeOnDoubleTap") as? Bool ?? true
        modelVariant = d.string(forKey: "modelVariant") ?? ""
        language = d.string(forKey: "language") ?? "en"
        livePreview = d.object(forKey: "livePreview") as? Bool ?? true
        showAllSpeechModels = d.bool(forKey: "showAllSpeechModels")
        insertionMode = InsertionMode(rawValue: d.string(forKey: "insertionMode") ?? "") ?? .paste
        playSounds = d.object(forKey: "playSounds") as? Bool ?? true
        enhancementTier = EnhancementTier(rawValue: d.string(forKey: "enhancementTier") ?? "") ?? .auto
        enhancementStyle = EnhancementStyle(rawValue: d.string(forKey: "enhancementStyle") ?? "") ?? .cleanUp
        removeFillers = d.object(forKey: "removeFillers") as? Bool ?? true
        spokenPunctuation = d.object(forKey: "spokenPunctuation") as? Bool ?? true
        cloudProvider = d.string(forKey: "cloudProvider") ?? "anthropic"
        mlxModelID = d.string(forKey: "mlxModelID") ?? "mlx-community/gemma-3-1b-it-qat-4bit"
        palette = Palette(rawValue: d.string(forKey: "palette") ?? "") ?? .dawn
        appearance = AppearanceMode(rawValue: d.string(forKey: "appearance") ?? "") ?? .system
        hasCompletedOnboarding = d.bool(forKey: "hasCompletedOnboarding")
        launchAtLogin = d.bool(forKey: "launchAtLogin")
    }

    private func store<T: Codable>(_ value: T?, _ key: String) {
        guard let value, let data = try? JSONEncoder().encode(value) else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(data, forKey: key)
    }

    private static func load<T: Codable>(_ d: UserDefaults, _ key: String) -> T? {
        guard let data = d.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    /// Resolves the theme from the appearance preference plus the system setting.
    func theme(systemIsDark: Bool) -> Theme {
        let dark = switch appearance {
        case .system: systemIsDark
        case .light: false
        case .dark: true
        }
        return .resolve(palette: palette, dark: dark)
    }
}
