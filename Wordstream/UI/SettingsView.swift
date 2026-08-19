//
//  SettingsView.swift
//  Wordstream
//

import SwiftUI
import SwiftData
import ServiceManagement

struct SettingsView: View {
    @Environment(\.theme) private var theme
    var coordinator: DictationCoordinator

    @State private var selection: Tab = .general

    enum Tab: String, CaseIterable, Identifiable {
        case general, models, shortcuts, dictionary, appearance, permissions
        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: "General"
            case .models: "Models"
            case .shortcuts: "Shortcuts"
            case .dictionary: "Dictionary"
            case .appearance: "Appearance"
            case .permissions: "Permissions"
            }
        }

        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .models: "cpu"
            case .shortcuts: "keyboard"
            case .dictionary: "character.book.closed"
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
                    .foregroundStyle(theme.fgPrimary)
                    .tag(tab)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(theme.bgSurface)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.x6) {
                    switch selection {
                    case .general: GeneralSettings(coordinator: coordinator)
                    case .models: ModelsSettings(coordinator: coordinator)
                    case .shortcuts: ShortcutSettings(coordinator: coordinator)
                    case .dictionary: DictionaryView()
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
                GatewayRadioGroup(
                    selection: $prefs.insertionMode,
                    options: InsertionMode.allCases.map { ($0, $0.displayName, nil) }
                )

                Text(prefs.insertionMode.explanation)
                    .typeStyle(Typography.caption)
                    .foregroundStyle(theme.fgTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Models

/// A section header bound to the card it introduces.
///
/// The tabs that predate this page space every header and card equally, which
/// reads fine at two sections and stops reading as a hierarchy at four.
private struct SettingsSection<Content: View>: View {
    var eyebrow: String
    var title: String
    var subtitle: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x4) {
            SectionHeader(eyebrow: eyebrow, title: title, subtitle: subtitle)
            GatewayCard { content }
        }
    }
}

/// Speech and cleanup on one page, in the order the audio passes through them.
///
/// These were two tabs — "Model" for Whisper, "AI" for the cleanup layer — which
/// split a single pipeline across two places and named the second one after a
/// technology rather than a job. Both are models; the useful distinction is what
/// each one does, so the page is the pipeline: what hears you, then what turns it
/// into writing.
///
/// The old AI tab also printed everything at once: a radio group of five tiers,
/// then a list repeating three of them with availability badges, then a local-model
/// card and a cloud card that were on screen whether or not either was in use.
/// Each engine's status now sits on the row that selects it, and its setup opens
/// under that row — so what is visible is what is being chosen.
private struct ModelsSettings: View {
    @Environment(\.theme) private var theme
    var coordinator: DictationCoordinator

    @State private var prefs = Preferences.shared
    @State private var status: [EnhancementTier: TierStatus] = [:]
    /// Which engine's setup is open, if any. Nil is the resting state: an engine
    /// that already works needs nothing shown.
    @State private var openSetup: EnhancementTier?
    @State private var apiKey = ""
    @State private var hasStoredKey = false
    /// Non-nil only while a download is running, so one value carries both the
    /// state and the progress.
    @State private var mlxProgress: Double?

    private let pipeline = EnhancementPipeline()

    struct TierStatus {
        var available: Bool
        var reason: String?
    }

    var body: some View {
        SectionHeader(
            eyebrow: "Models",
            title: "Speech in, writing out",
            subtitle: "Dictation runs through two models: one hears you, one turns what you said into text worth pasting. Both can run entirely on this Mac."
        )

        speech
        cleanup
        style
    }

    // MARK: Speech

    private var speech: some View {
        SettingsSection(
            eyebrow: "Step 1 · Speech",
            title: "What hears you",
            subtitle: "Whisper runs on this Mac. Nothing you dictate is uploaded during transcription."
        ) {
            VStack(alignment: .leading, spacing: Space.x4) {
                HStack {
                    speechBadge
                    Spacer()
                    if let rtf = coordinator.engine.realTimeFactor {
                        Text("\(rtf, format: .number.precision(.fractionLength(1)))× real time")
                            .typeStyleTabular(Typography.mono13)
                            .foregroundStyle(theme.fgTertiary)
                    }
                }

                if !coordinator.engine.canSustainLivePreview, prefs.livePreview {
                    InlineNote(
                        text: "This model runs close to real time here, so the live preview may lag behind your voice. A smaller model, or turning the preview off in General, will feel smoother.",
                        tone: .warning
                    )
                }

                ModelPicker(coordinator: coordinator)

                Divider().overlay(theme.borderSubtle)

                SettingRow(
                    title: "Spoken language",
                    description: "Pinning a language is far more reliable than auto-detection on short utterances."
                ) {
                    Picker("", selection: $prefs.language) {
                        ForEach(Self.languages, id: \.code) { language in
                            Text(language.name).tag(language.code)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 180)
                }
            }
        }
    }

    @ViewBuilder
    private var speechBadge: some View {
        switch coordinator.engine.state {
        case .idle: GatewayBadge(text: "Not loaded", tone: .neutral)
        case .downloading: GatewayBadge(text: "Downloading", tone: .brand)
        case .loading: GatewayBadge(text: "Loading", tone: .brand)
        case .ready: GatewayBadge(text: "Ready", tone: .success)
        case let .failed(message): GatewayBadge(text: message, tone: .danger)
        }
    }

    // MARK: Cleanup

    private var cleanup: some View {
        SettingsSection(
            eyebrow: "Step 2 · Cleanup",
            title: "What turns it into writing",
            subtitle: "Punctuation and filler cleanup always run. A language model on top of that applies the corrections you speak and fixes the sentences rules can't."
        ) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(EnhancementTier.allCases.enumerated()), id: \.element) { index, tier in
                    if index > 0 {
                        Divider().overlay(theme.borderSubtle)
                    }
                    tierRow(tier)
                }
            }
        }
        .task { await refresh() }
    }

    @ViewBuilder
    private func tierRow(_ tier: EnhancementTier) -> some View {
        let isSelected = prefs.enhancementTier == tier
        let state = status[tier]

        VStack(alignment: .leading, spacing: Space.x3) {
            // Two sibling buttons rather than one: selecting a tier and opening its
            // setup are separate acts, and a button nested inside a button's label
            // never receives the click.
            HStack(alignment: .top, spacing: Space.x3) {
                Button {
                    prefs.enhancementTier = tier
                    withAnimation(Motion.standard()) {
                        openSetup = tier.needsSetup && state?.available != true ? tier : nil
                    }
                } label: {
                    HStack(alignment: .top, spacing: Space.x3) {
                        radio(isSelected)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tier.displayName)
                                .typeStyle(Typography.bodySmMedium)
                                .foregroundStyle(theme.fgPrimary)
                            Text(tier.summary)
                                .typeStyle(Typography.caption)
                                .foregroundStyle(theme.fgSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            // What Automatic resolves to right now — the one thing
                            // the old page left the user to work out from a list of
                            // badges.
                            if tier == .auto, !status.isEmpty {
                                Text("Right now that is \(resolved.displayName).")
                                    .typeStyle(Typography.caption)
                                    .foregroundStyle(theme.fgBrand)
                            }
                            if let reason = state?.reason {
                                Text(reason)
                                    .typeStyle(Typography.caption)
                                    .foregroundStyle(theme.fgTertiary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)

                VStack(alignment: .trailing, spacing: Space.x1) {
                    if let state {
                        GatewayBadge(
                            text: state.available ? "Ready" : "Not set up",
                            tone: state.available ? .success : .neutral
                        )
                    }
                    if tier.needsSetup {
                        Button(setupButtonTitle(for: tier, available: state?.available == true)) {
                            withAnimation(Motion.standard()) {
                                openSetup = openSetup == tier ? nil : tier
                            }
                        }
                        .buttonStyle(GatewayButtonStyle(variant: .ghost, size: .sm))
                        .padding(.trailing, -Space.x3)  // Optically aligned with the badge.
                    }
                }
                .fixedSize()
            }

            if openSetup == tier {
                setup(for: tier)
            }
        }
        .padding(.vertical, Space.x3)
    }

    private func setupButtonTitle(for tier: EnhancementTier, available: Bool) -> String {
        if openSetup == tier { return "Done" }
        return available ? "Change" : "Set up"
    }

    private func radio(_ selected: Bool) -> some View {
        Circle()
            .strokeBorder(
                selected ? theme.borderBrand : theme.borderStrong,
                lineWidth: selected ? 5 : 1
            )
            .frame(width: 16, height: 16)
            .padding(.top, 3)
    }

    /// The tier Automatic would use, mirroring the pipeline's own order.
    private var resolved: EnhancementTier {
        [.foundationModels, .mlx, .cloud].first { status[$0]?.available == true } ?? .rulesOnly
    }

    // MARK: Engine setup

    @ViewBuilder
    private func setup(for tier: EnhancementTier) -> some View {
        Group {
            switch tier {
            case .mlx: mlxSetup
            case .cloud: cloudSetup
            default: EmptyView()
            }
        }
        .padding(Space.x4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(theme.bgSurfaceAlt)
        )
        .padding(.leading, Space.x6)  // Indented under the row it belongs to.
        .transition(.opacity)
    }

    private var mlxSetup: some View {
        VStack(alignment: .leading, spacing: Space.x3) {
            SettingRow(
                title: "Model",
                description: "Larger models read a little more naturally; smaller ones answer faster and hold less memory."
            ) {
                Picker("", selection: $prefs.mlxModelID) {
                    ForEach(MLXEnhancer.availableModels, id: \.id) { model in
                        Text("\(model.name)  ·  \(model.size)").tag(model.id)
                    }
                }
                .labelsHidden()
                .frame(width: 210)
            }

            if let progress = mlxProgress {
                GatewayProgressBar(value: progress)
                Text("Downloading — \(Int(progress * 100))%")
                    .typeStyle(Typography.caption)
                    .foregroundStyle(theme.fgTertiary)
            } else if MLXEnhancer(modelID: prefs.mlxModelID).isModelDownloaded {
                GatewayBadge(text: "Downloaded", tone: .success)
            } else {
                Button("Download") { downloadMLXModel() }
                    .buttonStyle(GatewayButtonStyle(variant: .secondary, size: .sm))
            }
        }
        .onChange(of: prefs.mlxModelID) { _, _ in
            Task { await refresh() }
        }
    }

    private var cloudSetup: some View {
        VStack(alignment: .leading, spacing: Space.x3) {
            SettingRow(title: "Provider", description: nil) {
                Picker("", selection: $prefs.cloudProvider) {
                    ForEach(CloudEnhancer.Provider.allCases, id: \.rawValue) { provider in
                        Text(provider.displayName).tag(provider.rawValue)
                    }
                }
                .labelsHidden()
                .frame(width: 210)
            }

            if hasStoredKey {
                HStack(spacing: Space.x3) {
                    GatewayBadge(text: "Key saved", tone: .success)
                    Text("In your Keychain, never in preferences.")
                        .typeStyle(Typography.caption)
                        .foregroundStyle(theme.fgTertiary)
                    Spacer(minLength: 0)
                    Button("Remove") { storeKey(nil) }
                        .buttonStyle(GatewayButtonStyle(variant: .ghost, size: .sm))
                }
            } else {
                HStack(spacing: Space.x2) {
                    SecureField("API key", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                        .frame(minHeight: Layout.tapTarget)
                    Button("Save") { storeKey(apiKey) }
                        .buttonStyle(GatewayButtonStyle(variant: .secondary, size: .sm))
                        .disabled(apiKey.isEmpty)
                }
                Text("Kept in your Keychain, never in preferences. \(provider.keyHint)")
                    .typeStyle(Typography.caption)
                    .foregroundStyle(theme.fgTertiary)
            }
        }
        .onChange(of: prefs.cloudProvider) { _, _ in
            apiKey = ""
            hasStoredKey = Keychain.has(provider.keychainAccount)
            Task { await refresh() }
        }
    }

    // MARK: Style

    private var style: some View {
        SettingsSection(
            eyebrow: "Style",
            title: "How much to change",
            subtitle: nil
        ) {
            VStack(alignment: .leading, spacing: Space.x3) {
                GatewayRadioGroup(
                    selection: $prefs.enhancementStyle,
                    options: EnhancementStyle.allCases.map { ($0, $0.displayName, $0.summary) }
                )

                Divider().overlay(theme.borderSubtle)

                SettingRow(
                    title: "Remove filler words",
                    description: "Drops standalone \u{201C}um\u{201D}, \u{201C}uh\u{201D}, \u{201C}er\u{201D}."
                ) {
                    Toggle("", isOn: $prefs.removeFillers).labelsHidden()
                }

                SettingRow(
                    title: "Spoken punctuation",
                    description: "Turns \u{201C}period\u{201D}, \u{201C}comma\u{201D}, \u{201C}new line\u{201D} into the punctuation itself."
                ) {
                    Toggle("", isOn: $prefs.spokenPunctuation).labelsHidden()
                }
            }
        }
    }

    // MARK: Actions

    private var provider: CloudEnhancer.Provider {
        CloudEnhancer.Provider(rawValue: prefs.cloudProvider) ?? .anthropic
    }

    private func storeKey(_ value: String?) {
        Keychain.set(value, for: provider.keychainAccount)
        apiKey = ""
        hasStoredKey = Keychain.has(provider.keychainAccount)
        Task { await refresh() }
    }

    private func downloadMLXModel() {
        mlxProgress = 0
        Task {
            let enhancer = MLXEnhancer(modelID: prefs.mlxModelID)
            try? await enhancer.download { value in
                Task { @MainActor in mlxProgress = value }
            }
            mlxProgress = nil
            await refresh()
        }
    }

    private func refresh() async {
        let entries = await pipeline.availability()
        status = Dictionary(
            uniqueKeysWithValues: entries.map { ($0.tier, TierStatus(available: $0.available, reason: $0.reason)) }
        )
        hasStoredKey = Keychain.has(provider.keychainAccount)
    }

    static let languages: [(code: String, name: String)] = [
        ("en", "English"), ("es", "Spanish"), ("fr", "French"), ("de", "German"),
        ("it", "Italian"), ("pt", "Portuguese"), ("nl", "Dutch"), ("hi", "Hindi"),
        ("ja", "Japanese"), ("ko", "Korean"), ("zh", "Chinese"), ("ru", "Russian"),
        ("ar", "Arabic"), ("tr", "Turkish"), ("pl", "Polish"),
    ]
}

/// A dot-and-text aside for a caveat that belongs next to a control rather than
/// under a heading.
private struct InlineNote: View {
    @Environment(\.theme) private var theme
    var text: String
    var tone: BadgeTone = .neutral

    var body: some View {
        HStack(alignment: .top, spacing: Space.x2) {
            Circle()
                .fill(dotColor)
                .frame(width: 5, height: 5)
                .padding(.top, 6)
            Text(text)
                .typeStyle(Typography.caption)
                .foregroundStyle(theme.fgSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var dotColor: Color {
        switch tone {
        case .neutral: theme.fgTertiary
        case .brand: theme.fgBrand
        case .success: theme.fgSuccess
        case .warning: theme.fgWarning
        case .danger: theme.fgDanger
        }
    }
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

// MARK: - Appearance

private struct AppearanceSettings: View {
    @State private var prefs = Preferences.shared

    var body: some View {
        SectionHeader(eyebrow: "Appearance", title: "Theme", subtitle: nil)

        GatewayCard {
            GatewayRadioGroup(
                selection: $prefs.appearance,
                options: AppearanceMode.allCases.map { ($0, $0.displayName, nil) }
            )
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
            title: "What Wordstream needs",
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
                    Text("This usually means Accessibility was granted after launch, or the app was rebuilt — macOS ties the grant to the app\u{2019}s code signature, so a rebuild can quietly invalidate it. If reconnecting doesn\u{2019}t help, remove Wordstream from the Accessibility list and add it back.")
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
