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
    @State private var isRelocating = false
    @State private var relocationError: String?
    @State private var showsReplaceConfirmation = false

    private var engine: WhisperEngine { coordinator.engine }

    enum Step: Int, CaseIterable {
        case welcome, permissions, model, ready
    }

    var body: some View {
        // One scroll view over the whole page rather than one over the step
        // below a pinned hero. The hero was holding 236pt of a 620pt window —
        // more than a third of it — to say three things that don't change
        // between steps, while the step that does change scrolled inside what
        // was left. Letting the masthead leave with the rest gives every step
        // the full window, and the steps that fit still show it.
        ScrollView {
            VStack(spacing: 0) {
                hero
                content
            }
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
    ///
    /// Laid out as a lockup rather than a centred column, and left-aligned to
    /// the same margin as the step below it. Stacked and centred it cost the
    /// height of a whole card to introduce an app the user has already opened;
    /// on one line it costs about a third of that and reads as the masthead it
    /// is rather than as a splash screen the step has to get past.
    private var hero: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            HStack(spacing: Space.x3) {
                MotifMarkView(size: 40)
                Text("Wordstream")
                    .typeStyle(Typography.displayMd)
                    .foregroundStyle(theme.fgPrimary)
            }
            Text("Hold a key. Talk. Your words land where your cursor is.")
                .typeStyle(Typography.bodySm)
                .foregroundStyle(theme.fgTertiary)
        }
        .padding(.vertical, Space.x5)
        .padding(.horizontal, Space.x6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.bgSurface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.borderSubtle).frame(height: 1)
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
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

            if !AppRelocator.isInstalled { relocationCard }

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
                .disabled(!canLeaveModelStep)

            if !canLeaveModelStep {
                Text("Ready to continue once the model has finished downloading \u{2014} until then there is nothing to transcribe with.")
                    .typeStyle(Typography.caption)
                    .foregroundStyle(theme.fgTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// When this step will let go.
    ///
    /// The download is the part that needs the user's patience; the load that
    /// follows it needs nothing from anyone and takes a handful of seconds it
    /// can just as well spend behind the last screen. Holding the step until
    /// `.ready` made people watch a bar that had already filled, so a model
    /// whose files are all on disk is enough to move on — the last step says so
    /// if the load is still running when it's reached.
    private var canLeaveModelStep: Bool {
        engine.state.isReady || engine.state.isLoading
    }

    /// What the model step says, given that its work is already done.
    ///
    /// The list underneath is one row — the model this Mac was matched with and
    /// how far its download has got — so the subtitle's job is to explain why
    /// there is nothing to choose, not to walk through a comparison. The trade
    /// between models only becomes worth describing once someone presses "Choose
    /// a different model", and it is described in the rows themselves there.
    private var modelSubtitle: String {
        if engine.state.isReady {
            return "Already downloaded and ready \u{2014} nothing to choose. Bigger models hear you more accurately at the cost of load time and memory; you can swap below, or later in Settings."
        }
        if engine.state.isLoading {
            return "Downloaded already \u{2014} it is being loaded into memory now, which finishes on its own whether or not this window is open. Carry on, or pick a different model below."
        }
        return "The one that suits this Mac started downloading when Wordstream opened. Nothing to do but let it finish \u{2014} or pick a different one below, which you can also do later in Settings."
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

    // MARK: Install location

    /// Offered before the permissions step, not after it.
    ///
    /// The order is the whole point: TCC ties the three grants to the bundle's
    /// path, so an app moved *after* onboarding keeps three switches that read
    /// as on and a dictation key that does nothing. Doing the move first costs
    /// one click here and saves an unexplainable failure later. The card
    /// disappears entirely once the app lives in an Applications folder, which
    /// is the state most people will already be in.
    ///
    /// The button is secondary rather than primary despite being the more
    /// consequential action on this screen — "Get started" is the step's one
    /// primary, and two saturated buttons in a column read as a choice between
    /// equals rather than as an aside and a way forward.
    private var relocationCard: some View {
        GatewayCard {
            VStack(alignment: .leading, spacing: Space.x3) {
                Text("Move Wordstream to Applications first")
                    .typeStyle(Typography.bodySmMedium)
                    .foregroundStyle(theme.fgPrimary)

                Text(relocationExplanation)
                    .typeStyle(Typography.caption)
                    .foregroundStyle(theme.fgSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: Space.x3) {
                    Button(isRelocating ? "Moving\u{2026}" : "Move to Applications") {
                        if AppRelocator.destinationIsOccupied {
                            showsReplaceConfirmation = true
                        } else {
                            relocate()
                        }
                    }
                    .buttonStyle(GatewayButtonStyle(variant: .secondary, size: .md))
                    .disabled(isRelocating)

                    Button("Show in Finder") { AppRelocator.revealInFinder() }
                        .buttonStyle(GatewayButtonStyle(variant: .ghost, size: .md))
                        .disabled(isRelocating)
                }

                if let error = relocationError {
                    Text("\(error) You can drag it across yourself instead \u{2014} use Show in Finder, then reopen Wordstream from Applications.")
                        .typeStyle(Typography.caption)
                        .foregroundStyle(theme.fgTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .alert("Replace the copy already in Applications?", isPresented: $showsReplaceConfirmation) {
            Button("Replace") { relocate() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The existing Wordstream there goes to the Trash, so you can put it back if this was a mistake.")
        }
    }

    /// What the card says, given what it can and can't tidy up afterwards.
    ///
    /// A translocated copy — one opened straight from a download or a disk image
    /// — runs from a read-only mirror, and the real download is at a path this
    /// process can't ask for. The move still works; the original just stays
    /// where it is, and promising otherwise would leave someone hunting for a
    /// duplicate that was never removed.
    private var relocationExplanation: String {
        let base = "This copy isn\u{2019}t in your Applications folder yet. Move it now, before granting permissions \u{2014} macOS ties those to where the app sits, so moving it later means granting all three again."
        return AppRelocator.isTranslocated
            ? base + " Wordstream will reopen from Applications; the copy you downloaded stays where it is, and you can delete it."
            : base + " One click copies it across, reopens it there and puts this copy in the Trash."
    }

    private func relocate() {
        relocationError = nil
        isRelocating = true
        Task {
            do {
                // On success this never returns to us — the replacement is
                // already launching and this process terminates inside the call.
                try await AppRelocator.moveToApplications()
            } catch {
                relocationError = error.localizedDescription
            }
            isRelocating = false
        }
    }

    private var ready: some View {
        VStack(alignment: .leading, spacing: Space.x5) {
            SectionHeader(
                eyebrow: "Ready",
                title: "Hold \(prefs.dictationShortcut.displayName.replacingOccurrences(of: "Hold ", with: "")) and speak",
                subtitle: "Try it in any text field. Release the key and your words appear at the cursor. Press Escape while holding to cancel."
            )

            // Reachable now with the model still loading, which is a few
            // seconds of a dictation key that flashes "no model" rather than
            // transcribing. Cheaper to say so than to let someone conclude the
            // key doesn't work.
            if engine.state.isLoading {
                HStack(spacing: Space.x3) {
                    ProgressView().controlSize(.small)
                    Text("Your model is still loading into memory \u{2014} the key starts working the moment it lands.")
                        .typeStyle(Typography.caption)
                        .foregroundStyle(theme.fgTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

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

