//
//  SettingsView.swift
//  NativeSTT
//

import SwiftUI
import SwiftData
import ServiceManagement

struct SettingsView: View {
    @Environment(\.theme) private var theme
    var coordinator: DictationCoordinator

    @State private var selection: Tab = .general

    enum Tab: String, CaseIterable, Identifiable {
        case general, model, shortcuts, dictionary, ai, appearance, permissions
        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: "General"
            case .model: "Model"
            case .shortcuts: "Shortcuts"
            case .dictionary: "Dictionary"
            case .ai: "AI"
            case .appearance: "Appearance"
            case .permissions: "Permissions"
            }
        }

        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .model: "waveform"
            case .shortcuts: "keyboard"
            case .dictionary: "character.book.closed"
            case .ai: "sparkles"
            case .appearance: "paintpalette"
            case .permissions: "lock.shield"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(Tab.allCases, selection: $selection) { tab in
                Label(tab.title, systemImage: tab.symbol)
                    .typeStyle(Typography.bodySm)
                    .tag(tab)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.x6) {
                    switch selection {
                    case .general: GeneralSettings(coordinator: coordinator)
                    case .model: ModelSettings(coordinator: coordinator)
                    case .shortcuts: ShortcutSettings(coordinator: coordinator)
                    case .dictionary: DictionaryView()
                    case .ai: AISettings()
                    case .appearance: AppearanceSettings()
                    case .permissions: PermissionsSettings(coordinator: coordinator)
                    }
                }
                .padding(Space.x8)
                .frame(maxWidth: 720, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.bgCanvas)
        }
        .frame(minWidth: 860, minHeight: 580)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @Environment(\.theme) private var theme
    var coordinator: DictationCoordinator
    @State private var prefs = Preferences.shared
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        SectionHeader(
            eyebrow: "General",
            title: "How dictation behaves",
            subtitle: nil
        )

        GatewayCard {
            VStack(spacing: Space.x2) {
                SettingRow(
                    title: "Live preview while speaking",
                    description: "Shows a running transcript in the overlay as you talk. This runs the speech model continuously while you hold the key, so it uses noticeably more power than leaving it off. The text that gets inserted always comes from a separate, higher-quality pass after you release — turning this off costs you nothing but the on-screen feedback."
                ) {
                    Toggle("", isOn: $prefs.livePreview).labelsHidden()
                }

                Divider().overlay(theme.borderSubtle)

                SettingRow(
                    title: "Hands-free on double-tap",
                    description: "Double-tap the dictation key to start without holding it. Double-tap again to stop."
                ) {
                    Toggle("", isOn: $prefs.handsFreeOnDoubleTap)
                        .labelsHidden()
                        .onChange(of: prefs.handsFreeOnDoubleTap) { _, _ in coordinator.applyShortcuts() }
                }

                Divider().overlay(theme.borderSubtle)

                SettingRow(
                    title: "Sound when text is inserted",
                    description: nil
                ) {
                    Toggle("", isOn: $prefs.playSounds).labelsHidden()
                }

                Divider().overlay(theme.borderSubtle)

                SettingRow(
                    title: "Launch at login",
                    description: nil
                ) {
                    Toggle("", isOn: $launchAtLogin)
                        .labelsHidden()
                        .onChange(of: launchAtLogin) { _, enabled in
                            try? enabled
                                ? SMAppService.mainApp.register()
                                : SMAppService.mainApp.unregister()
                        }
                }
            }
        }

        SectionHeader(
            eyebrow: "Insertion",
            title: "How text reaches your app",
            subtitle: nil
        )

        GatewayCard {
            VStack(alignment: .leading, spacing: Space.x3) {
                Picker("", selection: $prefs.insertionMode) {
                    ForEach(InsertionMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.radioGroup)

                Text(prefs.insertionMode.explanation)
                    .typeStyle(Typography.caption)
                    .foregroundStyle(theme.fgTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Model

private struct ModelSettings: View {
    @Environment(\.theme) private var theme
    var coordinator: DictationCoordinator
    @State private var prefs = Preferences.shared

    var body: some View {
        SectionHeader(
            eyebrow: "Speech model",
            title: "Whisper runs entirely on this Mac",
            subtitle: "Nothing you dictate is uploaded during transcription."
        )

        GatewayCard {
            VStack(alignment: .leading, spacing: Space.x4) {
                HStack {
                    stateBadge
                    Spacer()
                    if let rtf = coordinator.engine.realTimeFactor {
                        Text("\(rtf, format: .number.precision(.fractionLength(1)))× real time")
                            .typeStyleTabular(Typography.mono13)
                            .foregroundStyle(theme.fgTertiary)
                    }
                }

                if case let .downloading(progress) = coordinator.engine.state {
                    GatewayProgressBar(value: progress)
                    Text("Downloading — \(Int(progress * 100))%")
                        .typeStyle(Typography.caption)
                        .foregroundStyle(theme.fgTertiary)
                }

                if !coordinator.engine.canSustainLivePreview, prefs.livePreview {
                    HStack(alignment: .top, spacing: Space.x2) {
                        Circle().fill(theme.fgWarning).frame(width: 5, height: 5).padding(.top, 6)
                        Text("This model runs close to real time here, so the live preview may lag behind your voice. A smaller model or turning the preview off in General will feel smoother.")
                            .typeStyle(Typography.caption)
                            .foregroundStyle(theme.fgSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Picker("", selection: $prefs.modelVariant) {
                    ForEach(coordinator.engine.availableModels, id: \.self) { model in
                        Text(label(for: model)).tag(model)
                    }
                }
                .labelsHidden()
                .onChange(of: prefs.modelVariant) { _, variant in
                    Task { await coordinator.engine.prepare(variant: variant) }
                }
            }
        }

        SectionHeader(eyebrow: "Language", title: "Spoken language", subtitle: "Pinning a language is far more reliable than auto-detection on short utterances.")

        GatewayCard {
            Picker("", selection: $prefs.language) {
                ForEach(Self.languages, id: \.code) { language in
                    Text(language.name).tag(language.code)
                }
            }
            .labelsHidden()
        }
    }

    private func label(for model: String) -> String {
        model == coordinator.engine.recommendedModel
            ? "\(model)  ·  Recommended for your Mac"
            : model
    }

    @ViewBuilder
    private var stateBadge: some View {
        switch coordinator.engine.state {
        case .idle: GatewayBadge(text: "Not loaded", tone: .neutral)
        case .downloading: GatewayBadge(text: "Downloading", tone: .brand)
        case .loading: GatewayBadge(text: "Loading", tone: .brand)
        case .ready: GatewayBadge(text: "Ready", tone: .success)
        case let .failed(message): GatewayBadge(text: message, tone: .danger)
        }
    }

    static let languages: [(code: String, name: String)] = [
        ("en", "English"), ("es", "Spanish"), ("fr", "French"), ("de", "German"),
        ("it", "Italian"), ("pt", "Portuguese"), ("nl", "Dutch"), ("hi", "Hindi"),
        ("ja", "Japanese"), ("ko", "Korean"), ("zh", "Chinese"), ("ru", "Russian"),
        ("ar", "Arabic"), ("tr", "Turkish"), ("pl", "Polish"),
    ]
}

// MARK: - Shortcuts

private struct ShortcutSettings: View {
    @Environment(\.theme) private var theme
    var coordinator: DictationCoordinator
    @State private var prefs = Preferences.shared

    var body: some View {
        SectionHeader(
            eyebrow: "Shortcuts",
            title: "Your dictation key",
            subtitle: "Hold to dictate, release to insert. Press Escape while recording to cancel."
        )

        GatewayCard {
            VStack(alignment: .leading, spacing: Space.x4) {
                SettingRow(title: "Dictation", description: nil) {
                    ShortcutRecorderView(shortcut: dictationBinding)
                }

                if let note = prefs.dictationShortcut.conflictNote {
                    HStack(alignment: .top, spacing: Space.x2) {
                        Circle().fill(theme.fgWarning).frame(width: 5, height: 5).padding(.top, 6)
                        Text(note)
                            .typeStyle(Typography.caption)
                            .foregroundStyle(theme.fgSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(Space.x3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .fill(theme.bgSubtle)
                    )
                }

                Divider().overlay(theme.borderSubtle)

                SettingRow(
                    title: "Command mode",
                    description: "Select text anywhere, then hold this key and say what to do with it."
                ) {
                    ShortcutRecorderView(shortcut: $prefs.commandModeShortcut, allowsClearing: true)
                }
            }
        }
        .onChange(of: prefs.dictationShortcut) { _, _ in coordinator.applyShortcuts() }
        .onChange(of: prefs.commandModeShortcut) { _, _ in coordinator.applyShortcuts() }
    }

    private var dictationBinding: Binding<Shortcut?> {
        Binding(
            get: { prefs.dictationShortcut },
            set: { if let new = $0 { prefs.dictationShortcut = new } }
        )
    }
}

// MARK: - AI

private struct AISettings: View {
    @Environment(\.theme) private var theme
    @State private var prefs = Preferences.shared
    @State private var availability: [(tier: EnhancementTier, available: Bool, reason: String?)] = []
    @State private var apiKey: String = ""
    @State private var keySaved = false
    @State private var mlxDownloading = false
    @State private var mlxProgress: Double = 0

    private let pipeline = EnhancementPipeline()

    var body: some View {
        SectionHeader(
            eyebrow: "Cleanup",
            title: "Turning speech into writing",
            subtitle: "Rule-based cleanup always runs. A language model on top of it removes filler words, applies your self-corrections, and fixes punctuation."
        )

        GatewayCard {
            VStack(alignment: .leading, spacing: Space.x4) {
                Picker("", selection: $prefs.enhancementTier) {
                    ForEach(EnhancementTier.allCases, id: \.self) { tier in
                        Text(tier.displayName).tag(tier)
                    }
                }
                .labelsHidden()
                .pickerStyle(.radioGroup)

                ForEach(availability, id: \.tier) { entry in
                    HStack(alignment: .top, spacing: Space.x3) {
                        GatewayBadge(
                            text: entry.available ? "Available" : "Unavailable",
                            tone: entry.available ? .success : .neutral
                        )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.tier.displayName)
                                .typeStyle(Typography.bodySmMedium)
                                .foregroundStyle(theme.fgPrimary)
                            if let reason = entry.reason {
                                Text(reason)
                                    .typeStyle(Typography.caption)
                                    .foregroundStyle(theme.fgTertiary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }

        SectionHeader(eyebrow: "Style", title: "How much to change", subtitle: nil)

        GatewayCard {
            VStack(alignment: .leading, spacing: Space.x3) {
                Picker("", selection: $prefs.enhancementStyle) {
                    ForEach(EnhancementStyle.allCases, id: \.self) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)

                Text(prefs.enhancementStyle.instruction)
                    .typeStyle(Typography.caption)
                    .foregroundStyle(theme.fgTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider().overlay(theme.borderSubtle)

                SettingRow(title: "Remove filler words", description: "Drops standalone \u{201C}um\u{201D}, \u{201C}uh\u{201D}, \u{201C}er\u{201D}.") {
                    Toggle("", isOn: $prefs.removeFillers).labelsHidden()
                }

                SettingRow(title: "Spoken punctuation", description: "Turns \u{201C}period\u{201D}, \u{201C}comma\u{201D}, \u{201C}new line\u{201D} into the punctuation itself.") {
                    Toggle("", isOn: $prefs.spokenPunctuation).labelsHidden()
                }
            }
        }

        SectionHeader(
            eyebrow: "Local model",
            title: "Cleanup without Apple Intelligence",
            subtitle: "A small language model that runs on this Mac\u{2019}s GPU. Use it if Apple Intelligence is off or unsupported — it keeps the cleanup local rather than falling back to plain rules."
        )

        GatewayCard {
            VStack(alignment: .leading, spacing: Space.x3) {
                Picker("", selection: $prefs.mlxModelID) {
                    ForEach(MLXEnhancer.availableModels, id: \.id) { model in
                        Text("\(model.name)  ·  \(model.size)").tag(model.id)
                    }
                }
                .labelsHidden()

                if mlxDownloading {
                    GatewayProgressBar(value: mlxProgress)
                    Text("Downloading — \(Int(mlxProgress * 100))%")
                        .typeStyle(Typography.caption)
                        .foregroundStyle(theme.fgTertiary)
                } else if MLXEnhancer(modelID: prefs.mlxModelID).isModelDownloaded {
                    GatewayBadge(text: "Downloaded", tone: .success)
                } else {
                    Button("Download model") {
                        mlxDownloading = true
                        mlxProgress = 0
                        Task {
                            let enhancer = MLXEnhancer(modelID: prefs.mlxModelID)
                            try? await enhancer.download { value in
                                Task { @MainActor in mlxProgress = value }
                            }
                            mlxDownloading = false
                            availability = await pipeline.availability()
                        }
                    }
                    .buttonStyle(GatewayButtonStyle(variant: .secondary, size: .md))
                }
            }
        }

        SectionHeader(
            eyebrow: "Cloud",
            title: "Optional cloud cleanup",
            subtitle: "Off unless you add a key. When this tier runs, the transcribed text is sent to the provider you choose — everything else in this app stays on your Mac."
        )

        GatewayCard {
            VStack(alignment: .leading, spacing: Space.x3) {
                Picker("", selection: $prefs.cloudProvider) {
                    ForEach(CloudEnhancer.Provider.allCases, id: \.rawValue) { provider in
                        Text(provider.displayName).tag(provider.rawValue)
                    }
                }
                .labelsHidden()

                HStack(spacing: Space.x2) {
                    SecureField("API key", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                        .frame(minHeight: Layout.tapTarget)

                    Button("Save") {
                        let provider = CloudEnhancer.Provider(rawValue: prefs.cloudProvider) ?? .anthropic
                        Keychain.set(apiKey, for: provider.keychainAccount)
                        apiKey = ""
                        keySaved = true
                        Task { availability = await pipeline.availability() }
                    }
                    .buttonStyle(GatewayButtonStyle(variant: .secondary, size: .md))
                    .disabled(apiKey.isEmpty)
                }

                Text(keySaved
                     ? "Saved to your Keychain."
                     : "Stored in your Keychain, never in preferences. \((CloudEnhancer.Provider(rawValue: prefs.cloudProvider) ?? .anthropic).keyHint)")
                    .typeStyle(Typography.caption)
                    .foregroundStyle(keySaved ? theme.fgSuccess : theme.fgTertiary)
            }
        }
        .task { availability = await pipeline.availability() }
    }
}

// MARK: - Appearance

private struct AppearanceSettings: View {
    @State private var prefs = Preferences.shared

    var body: some View {
        SectionHeader(eyebrow: "Appearance", title: "Theme", subtitle: nil)

        GatewayCard {
            Picker("", selection: $prefs.appearance) {
                ForEach(AppearanceMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
        }

        SectionHeader(
            eyebrow: "Palette",
            title: "Colour",
            subtitle: "Each swatch shows both ends of that theme\u{2019}s ramp plus its tinted surface."
        )

        PalettePicker(selection: $prefs.palette)
    }
}

// MARK: - Permissions

private struct PermissionsSettings: View {
    @Environment(\.theme) private var theme
    var coordinator: DictationCoordinator

    var body: some View {
        SectionHeader(
            eyebrow: "Permissions",
            title: "What NativeSTT needs",
            subtitle: "All three are required. Each one fails silently on its own, so the app checks them rather than assuming."
        )

        GatewayCard {
            VStack(spacing: Space.x4) {
                PermissionRow(
                    kind: .microphone,
                    title: "Microphone",
                    detail: "To hear you.",
                    permissions: coordinator.permissions
                )
                Divider().overlay(theme.borderSubtle)
                PermissionRow(
                    kind: .accessibility,
                    title: "Accessibility",
                    detail: "To watch for your dictation key and to place text in other apps.",
                    permissions: coordinator.permissions,
                    onChange: { coordinator.restartMonitoring() }
                )
                Divider().overlay(theme.borderSubtle)
                PermissionRow(
                    kind: .inputMonitoring,
                    title: "Input Monitoring",
                    detail: "To detect the key while another app is in front.",
                    permissions: coordinator.permissions,
                    onChange: { coordinator.restartMonitoring() }
                )
            }
        }

        if !coordinator.isMonitoring {
            GatewayCard {
                VStack(alignment: .leading, spacing: Space.x3) {
                    Text("The dictation key isn\u{2019}t being watched")
                        .typeStyle(Typography.bodySmMedium)
                        .foregroundStyle(theme.fgPrimary)
                    Text("This usually means Accessibility was granted after launch, or the app was rebuilt — macOS ties the grant to the app\u{2019}s code signature, so a rebuild can quietly invalidate it. If reconnecting doesn\u{2019}t help, remove NativeSTT from the Accessibility list and add it back.")
                        .typeStyle(Typography.caption)
                        .foregroundStyle(theme.fgSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Reconnect") { coordinator.restartMonitoring() }
                        .buttonStyle(GatewayButtonStyle(variant: .primary, size: .md))
                }
            }
        }
    }
}
