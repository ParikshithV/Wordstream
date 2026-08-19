//
//  OnboardingView.swift
//  Wordstream
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

    private var engine: WhisperEngine { coordinator.engine }

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
            MotifMarkView(size: 72)
            Text("Wordstream")
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

            // Said plainly on the first screen, because the download has already
            // begun by the time this is read. A transfer this size starting on
            // its own is fine; starting unannounced is not.
            Text(prefetchNote)
                .typeStyle(Typography.caption)
                .foregroundStyle(theme.fgTertiary)
                .fixedSize(horizontal: false, vertical: true)

            Button("Get started") { step = .permissions }
                .buttonStyle(GatewayButtonStyle(variant: .primary, size: .lg))
        }
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: Space.x5) {
            SectionHeader(
                eyebrow: "Step 1 of 2",
                title: "Three permissions",
                subtitle: permissionsSubtitle
            )

            GatewayCard {
                VStack(spacing: Space.x4) {
                    PermissionRow(
                        kind: .microphone,
                        title: "Microphone",
                        detail: "To hear you.",
                        permissions: coordinator.permissions
                    )
                    SettingDivider()
                    PermissionRow(
                        kind: .accessibility,
                        title: "Accessibility",
                        detail: "To watch for your dictation key and place text in other apps.",
                        permissions: coordinator.permissions,
                        onChange: { coordinator.restartMonitoring() }
                    )
                    SettingDivider()
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

    /// What this step says once it knows where it stands.
    ///
    /// The permissions can already be in place before this screen is ever
    /// reached — a reinstall keeps TCC grants, and a second run of onboarding
    /// finds everything switched on. Telling someone macOS is about to ask them
    /// three times, when it is going to ask them nothing, describes an app they
    /// aren't using.
    private var permissionsSubtitle: String {
        coordinator.permissions.allGranted
            ? "All three are already granted \u{2014} nothing to do here. They're listed so you can see what Wordstream holds, and you can revoke any of them in System Settings."
            : "macOS asks for each separately. Without all three the dictation key silently does nothing."
    }

    private var model: some View {
        VStack(alignment: .leading, spacing: Space.x5) {
            SectionHeader(
                eyebrow: "Step 2 of 2",
                title: "Your speech model",
                subtitle: modelSubtitle
            )

            GatewayCard {
                ModelPicker(
                    coordinator: coordinator,
                    allowsAdvanced: false,
                    collapsesToRecommendation: true
                )
            }

            // This step used to have no Continue button, because pressing
            // Download in a row was the action and the step advanced itself once
            // the model loaded. Neither is true now that the download starts on
            // its own: someone who accepts the recommendation presses nothing at
            // all, and by the time they arrive the model may already be loaded —
            // which under the old rule left the step with no way out of it.
            Button("Continue") { step = .ready }
                .buttonStyle(GatewayButtonStyle(variant: .primary, size: .lg))
                .disabled(!engine.state.isReady)

            if !engine.state.isReady {
                Text("Ready to continue once a model has finished loading \u{2014} until then there is nothing to transcribe with.")
                    .typeStyle(Typography.caption)
                    .foregroundStyle(theme.fgTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Saved to Application Support. Wordstream never asks for your Documents, Desktop or Downloads folders.")
                .typeStyle(Typography.caption)
                .foregroundStyle(theme.fgTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// What the model step says, given that its work is already done.
    ///
    /// The list underneath is one row — the model this Mac was matched with and
    /// how far its download has got — so the subtitle's job is to explain why
    /// there is nothing to choose, not to walk through a comparison. The trade
    /// between models only becomes worth describing once someone presses "Choose
    /// a different model", and it is described in the rows themselves there.
    private var modelSubtitle: String {
        engine.state.isReady
            ? "Already downloaded and ready \u{2014} nothing to choose. Bigger models hear you more accurately at the cost of load time and memory; you can swap below, or later in Settings."
            : "The one that suits this Mac started downloading when Wordstream opened. Nothing to do but let it finish \u{2014} or pick a different one below, which you can also do later in Settings."
    }

    /// What the welcome screen says about the download already running.
    ///
    /// Named where it can be, because "Sharp is downloading" is a far better
    /// sentence than "a model is downloading" — but the catalogue is a network
    /// fetch, so on the first second of first run the name genuinely isn't known
    /// yet and the vaguer line is the honest one.
    private var prefetchNote: String {
        guard let variant = engine.preparingVariant ?? engine.recommendedCuratedVariant,
              let model = ModelCatalogue.model(for: variant)
        else {
            return "The speech model best suited to this Mac is already downloading in the background."
        }
        return "\(model.name) \u{2014} the speech model best suited to this Mac \u{2014} is already downloading in the background. \(model.sizeText), once."
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

            Button("Start using Wordstream") {
                prefs.hasCompletedOnboarding = true
                onFinish()
            }
            .buttonStyle(GatewayButtonStyle(variant: .primary, size: .lg))
        }
    }
}

