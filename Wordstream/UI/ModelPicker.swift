//
//  ModelPicker.swift
//  Wordstream
//

import SwiftUI

/// The speech-model chooser: one row per model, each with its own action.
///
/// This replaced a `Picker`, which was the wrong control for the job in two ways.
/// It hid the fact that choosing a model triggers a several-hundred-megabyte
/// download — selection in a menu reads as free — and it gave no way to back out
/// of one, so picking `Exacting` on a slow connection meant waiting it out before
/// anything else could be chosen. Rows make the download an explicit act with a
/// visible size, and put a Stop next to the progress bar of the one running.
///
/// Two lists, one control: five curated models by default, and every variant this
/// Mac supports behind Advanced mode. The default list is a recommendation; the
/// advanced one is a catalogue, and conflating them would make the common case
/// harder to serve the rare one.
///
/// The two are shaped differently on purpose. The curated list is five peers, so
/// it is five equal rows. The catalogue is not a list of two dozen models — it is
/// six or seven models in two dozen wrappers, and rendering it flat made every
/// wrapper look like a model and left several rows literally indistinguishable
/// from each other. So it is grouped: the model, then the builds of it, which is
/// the order the decision is actually made in.
struct ModelPicker: View {
    @Environment(\.theme) private var theme
    var coordinator: DictationCoordinator
    /// Off during onboarding. A first-run choice between five models is a decision
    /// someone can make in seconds; the same screen offering twenty-odd builds is
    /// a decision they postpone, and postponing this one leaves the app unable to
    /// transcribe at all.
    var allowsAdvanced: Bool = true
    /// Called after a model finishes loading, so onboarding can advance itself.
    var onReady: (() -> Void)?

    @State private var prefs = Preferences.shared

    private var engine: WhisperEngine { coordinator.engine }

    private var offered: [SpeechModel] {
        ModelCatalogue.offered(supportedBy: engine.availableModels)
    }

    /// What the list shows: the curated five, or every build the device supports,
    /// grouped by the model each is a build of.
    private var showsAll: Bool { allowsAdvanced && prefs.showAllSpeechModels }

    private var families: [ModelFamily] {
        ModelCatalogue.families(supportedBy: engine.availableModels)
    }

    /// The curated list, plus the current model when it isn't one of them.
    private var rows: [SpeechModel] {
        offered + (legacyRow.map { [$0] } ?? [])
    }

    /// The model in use when whichever list is showing doesn't contain it, so the
    /// model actually doing the transcribing is never missing from the list of
    /// models.
    private var legacyRow: SpeechModel? {
        let current = engine.loadedVariant ?? prefs.modelVariant
        let listed = showsAll
            ? families.contains { $0.variants.contains { $0.variant == current } }
            : offered.contains { $0.variant == current }
        guard !current.isEmpty, !listed else { return nil }
        return ModelCatalogue.legacy(current)
    }

    /// Always computed over the curated five: the recommendation is a judgement
    /// about what suits this Mac, and widening the list doesn't change it.
    private var recommended: SpeechModel? {
        ModelCatalogue.recommended(for: engine.recommendedModel, among: offered)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            if engine.availableModels.isEmpty {
                HStack(spacing: Space.x3) {
                    ProgressView().controlSize(.small)
                    Text("Checking which models run best on this Mac\u{2026}")
                        .typeStyle(Typography.bodySm)
                        .foregroundStyle(theme.fgTertiary)
                }
                .padding(.bottom, Space.x2)
            }

            if showsAll {
                ForEach(Array(families.enumerated()), id: \.element.id) { index, family in
                    if index > 0 {
                        SettingDivider()
                    }
                    section(for: family)
                }
                if let legacyRow {
                    SettingDivider()
                    row(for: legacyRow)
                }
            } else {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, model in
                    if index > 0 {
                        SettingDivider()
                    }
                    row(for: model)
                }
            }

            if allowsAdvanced {
                advancedToggle
            }

            if case let .failed(message) = engine.state {
                HStack(alignment: .top, spacing: Space.x2) {
                    Circle().fill(theme.fgDanger).frame(width: 5, height: 5).padding(.top, 6)
                    Text(message)
                        .typeStyle(Typography.caption)
                        .foregroundStyle(theme.fgSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, Space.x2)
            }
        }
        .task { await engine.refreshCatalogue() }
    }

    // MARK: Advanced mode

    /// A quiet text link under the list, not a switch above it.
    ///
    /// Weighting matters more here than discoverability: the five curated models
    /// are the answer for almost everyone, and a labelled switch at the top of the
    /// card reads as a decision to make before choosing — which is exactly the
    /// research project the short list exists to avoid. Someone who wants the full
    /// catalogue is looking for a way in and will find one word at the end of the
    /// list; someone who isn't should barely register it.
    private var advancedToggle: some View {
        VStack(alignment: .leading, spacing: Space.x1) {
            Button(showsAll ? "Show fewer" : "Show all models") {
                prefs.showAllSpeechModels.toggle()
            }
            .buttonStyle(GatewayButtonStyle(variant: .ghost, size: .sm))
            .padding(.horizontal, -Space.x3)  // Optically aligned with the rows.

            if showsAll {
                Text("Everything WhisperKit lists for this Mac, unfiltered — some builds are English-only, some are far slower for little gain.")
                    .typeStyle(Typography.caption)
                    .foregroundStyle(theme.fgTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, Space.x1)
    }

    // MARK: Family

    /// One Whisper model and the builds of it, as a headed group.
    ///
    /// The model gets the name and the one line that decides whether to look
    /// inside at all — including, for Medium and Large v2, that the answer is no.
    /// The builds under it are deliberately quieter: they are the same model, and
    /// what varies between them is packaging, so each says only what makes it
    /// different from its siblings rather than restating what they all are.
    @ViewBuilder
    private func section(for family: ModelFamily) -> some View {
        VStack(alignment: .leading, spacing: Space.x3) {
            VStack(alignment: .leading, spacing: Space.x1) {
                Text(family.name)
                    .typeStyle(Typography.bodySmMedium)
                    .foregroundStyle(theme.fgPrimary)

                Text(family.summary)
                    .typeStyle(Typography.caption)
                    .foregroundStyle(theme.fgSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: Space.x3) {
                ForEach(family.variants) { variant in
                    build(variant)
                }
            }
            // Indented so the builds read as belonging to the model above them
            // rather than as more models, which is the whole distinction the flat
            // list lost.
            .padding(.leading, Space.x3)
        }
        .padding(.vertical, Space.x3)
    }

    /// One build within a family: what makes it different, how big it is, and
    /// what it costs to load.
    @ViewBuilder
    private func build(_ model: SpeechModel) -> some View {
        let isPreparing = engine.preparingVariant == model.variant
        let isActive = engine.loadedVariant == model.variant && engine.state.isReady
        let isRecommended = model.id == recommended?.id

        VStack(alignment: .leading, spacing: Space.x2) {
            HStack(alignment: .top, spacing: Space.x4) {
                VStack(alignment: .leading, spacing: Space.x1) {
                    HStack(spacing: Space.x2) {
                        Text(model.qualifier.isEmpty ? "Standard build" : model.qualifier)
                            .typeStyle(Typography.bodySm)
                            .foregroundStyle(theme.fgPrimary)

                        // The friendly name, where one exists, so someone who came
                        // here looking for `Sharp` can still see which row it is.
                        if let curated = ModelCatalogue.curatedName(for: model.variant) {
                            GatewayBadge(text: curated, tone: .neutral)
                        }

                        if isActive {
                            GatewayBadge(text: "In use", tone: .success)
                        } else if isRecommended {
                            GatewayBadge(text: "Best for this Mac", tone: .brand)
                        }
                    }

                    if !sizeLine(for: model).isEmpty {
                        Text(sizeLine(for: model))
                            .typeStyle(Typography.caption)
                            .foregroundStyle(theme.fgTertiary)
                    }

                    // The cost the download size gives no hint of, and the one
                    // most likely to be regretted from this list.
                    if let warning = ModelCatalogue.loadWarning(for: model) {
                        Text(warning)
                            .typeStyle(Typography.caption)
                            .foregroundStyle(theme.fgWarning)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // The build identifier, shown here and only here — this is the
                    // list where the identifier is the thing being chosen.
                    Text(model.variant)
                        .typeStyle(Typography.mono13)
                        .foregroundStyle(theme.fgTertiary)
                        .textSelection(.enabled)
                }

                Spacer(minLength: Space.x2)

                action(for: model, isPreparing: isPreparing, isActive: isActive)
                    .fixedSize()
            }

            if isPreparing {
                progress
            }
        }
        .contextMenu {
            if engine.isDownloaded(model.variant), !isPreparing {
                Button("Remove download", role: .destructive) {
                    Task { await engine.delete(model.variant) }
                }
            }
        }
    }

    // MARK: Row

    @ViewBuilder
    private func row(for model: SpeechModel) -> some View {
        let isPreparing = engine.preparingVariant == model.variant
        let isActive = engine.loadedVariant == model.variant && engine.state.isReady
        let isRecommended = model.id == recommended?.id

        VStack(alignment: .leading, spacing: Space.x3) {
            HStack(alignment: .top, spacing: Space.x4) {
                VStack(alignment: .leading, spacing: Space.x1) {
                    HStack(spacing: Space.x2) {
                        Text(model.name)
                            .typeStyle(Typography.bodySmMedium)
                            .foregroundStyle(theme.fgPrimary)

                        // Only when it says something the name doesn't: in the
                        // advanced list most rows *are* their technical name, and
                        // printing it twice would be noise.
                        if model.technicalName != model.name {
                            Text(model.technicalName)
                                .typeStyle(Typography.caption)
                                .foregroundStyle(theme.fgTertiary)
                        }

                        if isActive {
                            GatewayBadge(text: "In use", tone: .success)
                        } else if isRecommended {
                            GatewayBadge(text: "Best for this Mac", tone: .brand)
                        }
                    }

                    Text(model.summary)
                        .typeStyle(Typography.caption)
                        .foregroundStyle(theme.fgSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if isRecommended {
                        Text(ModelCatalogue.recommendationReason(for: model, among: offered))
                            .typeStyle(Typography.caption)
                            .foregroundStyle(theme.fgBrand)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if !sizeLine(for: model).isEmpty {
                        Text(sizeLine(for: model))
                            .typeStyle(Typography.caption)
                            .foregroundStyle(theme.fgTertiary)
                    }
                }

                Spacer(minLength: Space.x2)

                action(for: model, isPreparing: isPreparing, isActive: isActive)
                    .fixedSize()
            }

            if isPreparing {
                progress
            }
        }
        .padding(.vertical, Space.x3)
        .contextMenu {
            // Secondary, because reclaiming disk is a rare want and a destructive
            // button sitting in every row would compete with the one that matters.
            if engine.isDownloaded(model.variant), !isPreparing {
                Button("Remove download", role: .destructive) {
                    Task { await engine.delete(model.variant) }
                }
            }
        }
    }

    private func sizeLine(for model: SpeechModel) -> String {
        let onDisk = engine.isDownloaded(model.variant)
        return switch (model.sizeText.isEmpty, onDisk) {
        case (true, true): "On this Mac"
        case (true, false): ""
        case (false, true): "\(model.sizeText) · on this Mac"
        case (false, false): model.sizeText
        }
    }

    @ViewBuilder
    private func action(for model: SpeechModel, isPreparing: Bool, isActive: Bool) -> some View {
        if isPreparing {
            Button("Stop") { engine.cancelPreparation() }
                .buttonStyle(GatewayButtonStyle(variant: .secondary, size: .sm))
        } else if isActive {
            EmptyView()
        } else {
            Button(engine.isDownloaded(model.variant) ? "Use" : "Download") {
                select(model)
            }
            .buttonStyle(
                GatewayButtonStyle(
                    variant: model.id == recommended?.id ? .primary : .secondary,
                    size: .sm
                )
            )
        }
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            GatewayProgressBar(value: progressValue)
            Text(progressLabel)
                .typeStyle(Typography.caption)
                .foregroundStyle(theme.fgTertiary)
        }
    }

    private var progressValue: Double {
        if case let .downloading(value) = engine.state { return value }
        return 1
    }

    private var progressLabel: String {
        switch engine.state {
        case let .downloading(value) where value > 0:
            "Downloading — \(Int(value * 100))%"
        case .downloading:
            "Starting download\u{2026}"
        default:
            "Loading into memory\u{2026}"
        }
    }

    private func select(_ model: SpeechModel) {
        // Recorded before the download finishes on purpose: this is the model the
        // user asked for, and a quit mid-download should resume it next launch
        // rather than silently reverting.
        prefs.modelVariant = model.variant
        Task {
            await engine.prepare(variant: model.variant)
            if engine.loadedVariant == model.variant, engine.state.isReady {
                onReady?()
            }
        }
    }
}
