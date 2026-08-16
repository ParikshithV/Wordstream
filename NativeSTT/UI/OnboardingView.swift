//
//  OnboardingView.swift
//  NativeSTT
//

import SwiftUI

/// First run: grant three permissions, pick a model, done.
///
/// This screen is entitled to the system's one page-level gradient and
/// deliberately declines it — see `hero`. The only saturated colour in the whole
/// app is now the motif and the single primary action per step.
struct OnboardingView: View {
    @Environment(\.theme) private var theme
    var coordinator: DictationCoordinator
    var onFinish: () -> Void

    @State private var step: Step = .welcome
    @State private var prefs = Preferences.shared

    enum Step: Int, CaseIterable {
        case welcome, permissions, model, ready
    }

    var body: some View {
        VStack(spacing: 0) {
            hero
            content
        }
        .frame(width: 640, height: 620)
        .background(theme.bgCanvas)
    }

    // MARK: Hero

    /// A quiet hero on a plain surface.
    ///
    /// The design system allows one page-level gradient, and this is the only
    /// screen entitled to it — but a budget is a ceiling, not a quota. A
    /// full-bleed saturated ramp made this the loudest surface in an app whose
    /// entire job is to stay out of the way, and it forced white-on-pale
    /// contrast problems at the bottom of the ramp. Spending zero of the
    /// gradient budget is the more restrained reading of §1's "restraint reads
    /// as competence", and it leaves the motif as the single piece of colour —
    /// which is what §5 reserves the motif for in the first place.
    private var hero: some View {
        VStack(spacing: Space.x3) {
            LotusMotif(size: 72)
            Text("NativeSTT")
                .typeStyle(Typography.displayMd)
                .foregroundStyle(theme.fgPrimary)
            Text("Hold a key. Talk. Your words land where your cursor is.")
                .typeStyle(Typography.bodySm)
                .foregroundStyle(theme.fgTertiary)
            Spacer(minLength: 0)
        }
        .padding(.top, Space.x8)
        .padding(.horizontal, Space.x6)
        .frame(maxWidth: .infinity)
        .frame(height: 236)
        .background(theme.bgSurface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.borderSubtle).frame(height: 1)
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.x5) {
                switch step {
                case .welcome: welcome
                case .permissions: permissions
                case .model: model
                case .ready: ready
                }
            }
            .padding(Space.x6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: Space.x5) {
            SectionHeader(
                eyebrow: "Welcome",
                title: "Dictation that stays on your Mac",
                subtitle: "Speech is transcribed by OpenAI\u{2019}s Whisper model running locally on the Neural Engine. Nothing is uploaded unless you explicitly turn on the optional cloud cleanup later."
            )

            Button("Get started") { step = .permissions }
                .buttonStyle(GatewayButtonStyle(variant: .primary, size: .lg))
        }
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: Space.x5) {
            SectionHeader(
                eyebrow: "Step 1 of 2",
                title: "Three permissions",
                subtitle: "macOS asks for each separately. Without all three the dictation key silently does nothing."
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
                        detail: "To watch for your dictation key and place text in other apps.",
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

            Button("Continue") {
                coordinator.restartMonitoring()
                step = .model
            }
            .buttonStyle(GatewayButtonStyle(variant: .primary, size: .lg))
            .disabled(!coordinator.permissions.allGranted)

            if !coordinator.permissions.allGranted {
                Text("Grant all three to continue. Return to this window after each one — macOS doesn\u{2019}t announce the change, so the app re-checks whenever it comes forward.")
                    .typeStyle(Typography.caption)
                    .foregroundStyle(theme.fgTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var model: some View {
        VStack(alignment: .leading, spacing: Space.x5) {
            SectionHeader(
                eyebrow: "Step 2 of 2",
                title: "Choose a speech model",
                subtitle: "We\u{2019}ve already picked the one Argmax recommends for this Mac. Continue to accept it, or choose another."
            )

            GatewayCard {
                VStack(alignment: .leading, spacing: Space.x3) {
                    if coordinator.engine.availableModels.isEmpty {
                        HStack(spacing: Space.x3) {
                            ProgressView().controlSize(.small)
                            Text("Fetching the model list\u{2026}")
                                .typeStyle(Typography.bodySm)
                                .foregroundStyle(theme.fgTertiary)
                        }
                    } else {
                        Picker("", selection: $prefs.modelVariant) {
                            ForEach(coordinator.engine.availableModels, id: \.self) { variant in
                                Text(
                                    variant == coordinator.engine.recommendedModel
                                        ? "\(variant)  ·  Recommended for your Mac"
                                        : variant
                                ).tag(variant)
                            }
                        }
                        .labelsHidden()
                    }

                    if case let .downloading(progress) = coordinator.engine.state {
                        GatewayProgressBar(value: progress)
                        Text("Downloading — \(Int(progress * 100))%")
                            .typeStyle(Typography.caption)
                            .foregroundStyle(theme.fgTertiary)
                    } else if coordinator.engine.state == .loading {
                        Text("Loading into memory\u{2026}")
                            .typeStyle(Typography.caption)
                            .foregroundStyle(theme.fgTertiary)
                    }
                }
            }

            Button(coordinator.engine.state.isReady ? "Continue" : "Download and continue") {
                Task {
                    await coordinator.engine.prepare(variant: prefs.modelVariant)
                    if coordinator.engine.state.isReady { step = .ready }
                }
            }
            .buttonStyle(GatewayButtonStyle(variant: .primary, size: .lg))
            .disabled(prefs.modelVariant.isEmpty || coordinator.engine.state.isBusyLoading)
        }
        .task {
            await coordinator.engine.refreshCatalogue()
            if prefs.modelVariant.isEmpty, let recommended = coordinator.engine.recommendedModel {
                prefs.modelVariant = recommended
            }
        }
    }

    private var ready: some View {
        VStack(alignment: .leading, spacing: Space.x5) {
            SectionHeader(
                eyebrow: "Ready",
                title: "Hold \(prefs.dictationShortcut.displayName.replacingOccurrences(of: "Hold ", with: "")) and speak",
                subtitle: "Try it in any text field. Release the key and your words appear at the cursor. Press Escape while holding to cancel."
            )

            if let note = prefs.dictationShortcut.conflictNote {
                GatewayCard {
                    Text(note)
                        .typeStyle(Typography.caption)
                        .foregroundStyle(theme.fgSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button("Start using NativeSTT") {
                prefs.hasCompletedOnboarding = true
                onFinish()
            }
            .buttonStyle(GatewayButtonStyle(variant: .primary, size: .lg))
        }
    }
}

private extension WhisperEngine.State {
    var isBusyLoading: Bool {
        switch self {
        case .downloading, .loading: true
        default: false
        }
    }
}

