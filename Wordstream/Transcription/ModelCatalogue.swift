//
//  ModelCatalogue.swift
//  Wordstream
//

import Foundation

/// One offered speech model, described the way a person choosing one would think
/// about it.
///
/// WhisperKit's own identifiers — `openai_whisper-large-v3-v20240930_626MB` — are
/// build artefacts, not choices. Nothing in that string tells you whether it is
/// the right one for you, and the catalogue it comes from lists twenty-odd
/// near-duplicate variants that differ by quantisation and release date. This
/// type is the translation layer: a short name, the Whisper build it actually is,
/// the one sentence that decides the choice, and the download size.
struct SpeechModel: Identifiable, Hashable, Sendable {
    /// The WhisperKit variant this maps to. Never shown as the primary label.
    let variant: String
    let name: String
    /// The Whisper build underneath, spelled the way the model is known outside
    /// this app — "Whisper Small", "Whisper Large v3 Turbo". Shown next to `name`
    /// so the friendly label is a translation rather than a substitution: someone
    /// who knows Whisper can map our five names onto the real models, and someone
    /// comparing against another dictation app can tell what they are getting.
    let technicalName: String
    /// What you give up and what you get. Written as a trade, because it is one.
    let summary: String
    /// Approximate download size in bytes, for the size label.
    let bytes: Int64
    /// Roughly how long the first load takes on Apple silicon — the download is
    /// separate and visible; this is the wait after it, every cold launch, while
    /// the weights compile onto the Neural Engine. Ranking input, not a promise.
    let loadSeconds: Double
    /// Which Whisper model this is a build of — the grouping key for Advanced
    /// mode. Builds within a family differ in packaging, never in what the model
    /// knows.
    let family: String
    /// What sets this build apart from its siblings in the same family:
    /// "Compressed", "Turbo build · full precision". Inside a family this — not
    /// the name, which every sibling shares — is the thing being chosen between.
    /// Deliberately carries no size: `sizeText` states that once, on its own
    /// line, and two families' worth of "Compressed · 626 MB · 626 MB" is how
    /// this list got unreadable in the first place.
    let qualifier: String

    var id: String { variant }

    /// Empty when the size isn't known — see `ModelCatalogue.legacy(_:)`, where
    /// inventing a number would be worse than saying nothing.
    var sizeText: String {
        guard bytes > 0 else { return "" }
        return bytes.formatted(.byteCount(style: .file, allowedUnits: [.mb, .gb], spellsOutZero: false))
    }

    /// Approximate resident memory once loaded.
    ///
    /// Weights plus activations and decoder cache run to a bit under three times
    /// the weight file. This is what actually matters for the recommendation: the
    /// download is a one-off, but this is held for as long as Wordstream runs.
    var workingMemory: Int64 { Int64(Double(bytes) * 2.7) }
}

/// A Whisper model and the builds of it this Mac can run.
///
/// WhisperKit's catalogue is a flat list of two dozen identifiers in which the
/// same handful of models appear over and over: `large-v3`, `large-v3_947MB`,
/// `large-v3_turbo` and `large-v3_turbo_954MB` are one model in four wrappers.
/// Listed flat that reads as two dozen decisions when there are really six, and
/// the wrappers — which change load time and memory but not what the model
/// knows — sit at the same visual weight as the models themselves. Grouping puts
/// the decision back in its actual shape: choose the model, then choose how it is
/// packaged.
struct ModelFamily: Identifiable, Hashable, Sendable {
    let id: String
    /// How the model is known outside this app — "Whisper Large v3 Turbo".
    let name: String
    /// Whether this family is worth choosing at all, in one line. Several are
    /// not, and saying so is the whole point of showing the full catalogue with
    /// commentary rather than as a directory listing.
    let summary: String
    /// Builds of this model, lightest first.
    let variants: [SpeechModel]
}

/// The five models Wordstream offers, smallest first — plus the machinery to
/// describe and group any of the twenty-odd others for Advanced mode.
///
/// Deliberately five out of the twenty-plus WhisperKit supports. The excluded
/// ones are `.en`-only duplicates, superseded `large-v2` builds, and distil
/// variants that trade accuracy for a speed win the quantised large models
/// already provide. Offering them by default would turn a two-second decision
/// into a research project without making anyone's transcription better — but
/// they are all reachable through Advanced mode for anyone who wants one.
enum ModelCatalogue {
    static let all: [SpeechModel] = [
        SpeechModel(
            variant: "openai_whisper-tiny",
            name: "Instant",
            technicalName: "Whisper Tiny",
            summary: "Types almost as fast as you speak. Fumbles names, jargon and anything mumbled.",
            bytes: 78_000_000,
            loadSeconds: 2,
            family: "tiny",
            qualifier: "Full precision"
        ),
        SpeechModel(
            variant: "openai_whisper-base",
            name: "Quick",
            technicalName: "Whisper Base",
            summary: "Still very fast, noticeably steadier on ordinary sentences.",
            bytes: 148_000_000,
            loadSeconds: 3,
            family: "base",
            qualifier: "Full precision"
        ),
        SpeechModel(
            variant: "openai_whisper-small",
            name: "Balanced",
            technicalName: "Whisper Small",
            summary: "Handles accents and background noise well. The safe choice on an older Mac.",
            bytes: 483_000_000,
            loadSeconds: 8,
            family: "small",
            qualifier: "Full precision"
        ),
        SpeechModel(
            variant: "openai_whisper-large-v3-v20240930_626MB",
            name: "Sharp",
            technicalName: "Whisper Large v3 Turbo, compressed",
            summary: "Near-flagship accuracy, compressed to run comfortably on Apple silicon.",
            bytes: 626_000_000,
            loadSeconds: 18,
            family: "large-v3-turbo",
            qualifier: "Compressed"
        ),
        SpeechModel(
            variant: "openai_whisper-large-v3_947MB",
            name: "Exacting",
            technicalName: "Whisper Large v3, compressed",
            summary: "The most accurate option. Slowest to load and the heaviest on memory.",
            bytes: 947_000_000,
            loadSeconds: 30,
            family: "large-v3",
            qualifier: "Compressed"
        ),
    ]

    /// The offered models this Mac can actually run.
    ///
    /// An empty `supported` list means the catalogue hasn't loaded yet — offline,
    /// or still in flight — and everything is shown rather than nothing, because a
    /// blank list looks like breakage while a slightly optimistic one costs at
    /// worst one clear failure message.
    static func offered(supportedBy device: [String]) -> [SpeechModel] {
        guard !device.isEmpty else { return all }
        let supported = Set(device)
        let runnable = all.filter { supported.contains($0.variant) }
        return runnable.isEmpty ? all : runnable
    }

    /// Every variant WhisperKit lists for this Mac, grouped by the model it is a
    /// build of and ordered lightest family first — the Advanced-mode list.
    ///
    /// Curated models keep their friendly names within their family rather than
    /// reverting to build identifiers, so turning Advanced mode on adds builds
    /// around the ones already on screen instead of renaming them.
    static func families(supportedBy device: [String]) -> [ModelFamily] {
        let variants = device.isEmpty ? all.map(\.variant) : device
        let described = variants.map(describe)
        let byFamily = Dictionary(grouping: described, by: \.family)

        return byFamily
            .map { id, members in
                ModelFamily(
                    id: id,
                    name: familyName(id) ?? members.first?.technicalName ?? id,
                    summary: familySummary(id) ?? "Not one of the models Wordstream knows about — WhisperKit added it after this list was written.",
                    variants: members.sorted { ($0.bytes, $0.variant) < ($1.bytes, $1.variant) }
                )
            }
            .sorted { familyRank($0.id) < familyRank($1.id) }
    }

    static func model(for variant: String) -> SpeechModel? {
        all.first { $0.variant == variant }
    }

    /// The friendly name for a variant, when it has one. Used to badge the
    /// curated builds inside the Advanced list, so someone who arrived there
    /// looking for `Sharp` can still see which row it is.
    static func curatedName(for variant: String) -> String? {
        model(for: variant)?.name
    }

    /// The wait worth warning about, in one line, or nil when there is nothing to
    /// warn about.
    ///
    /// The full-precision large builds take upwards of a minute to compile onto
    /// the Neural Engine, every cold launch — the single fact most likely to make
    /// someone regret a choice from the Advanced list, and the one the download
    /// size gives no hint of.
    ///
    /// Pitched well above `patienceSeconds` rather than at it. That threshold is
    /// what a *recommendation* may impose, and warning on everything past it would
    /// mark two thirds of the Advanced list — including builds no worse than the
    /// `Exacting` we offer unflagged in the curated list. A warning on most rows
    /// distinguishes nothing, which is the failure mode this list already had.
    static func loadWarning(for model: SpeechModel) -> String? {
        guard model.loadSeconds > 35 else { return nil }
        let wait = model.loadSeconds >= 90
            ? "over a minute"
            : "about \(Int(model.loadSeconds / 10) * 10) seconds"
        return "Takes \(wait) to load on every cold launch, before the first dictation can start."
    }

    // MARK: Recommendation

    /// How much resident memory the speech model may take on this Mac, already
    /// net of what the clean-up model needs.
    ///
    /// A clean-up model always runs after transcription — either a local MLX model
    /// (~1 GB of weights in this process) or Apple Intelligence, whose system model
    /// lives outside this process but takes the same bite out of the machine. So
    /// the speech model never gets to plan as though it were alone, whichever tier
    /// is in use.
    ///
    /// A step function rather than a percentage, because the two are not the same
    /// shape: the clean-up reserve is close to fixed while the machine's memory
    /// is not, and a flat share of an 8 GB Mac leaves nothing after that reserve
    /// while a flat share of a 64 GB one would wave through models that are slow
    /// for reasons memory has nothing to do with.
    private static func speechMemoryBudget(physicalMemory: UInt64) -> Int64 {
        let gb = Double(physicalMemory) / 1_073_741_824
        return switch gb {
        case ..<12: 500_000_000    // 8 GB: the clean-up model is already the bigger tenant.
        case ..<20: 1_400_000_000  // 16 GB: room for Small, not for a large build.
        case ..<40: 2_500_000_000  // 24-32 GB: the compressed Large v3 Turbo fits comfortably.
        default: 4_000_000_000     // 64 GB+: memory stops being the binding constraint.
        }
    }

    /// The longest first-load wait a recommendation may impose. Past roughly this,
    /// the first dictation after a launch feels broken rather than slow, and no
    /// accuracy gain pays for that on a hotkey-driven tool. This — not memory — is
    /// what keeps the full Large v3 out of the recommendation on a 64 GB Mac.
    private static let patienceSeconds: Double = 20

    /// The model Wordstream recommends on this Mac.
    ///
    /// WhisperKit's own recommendation optimises for one thing — the largest model
    /// the chip can run — and that is the wrong target here. The speech model is
    /// resident for as long as the app is, it is reloaded on every cold launch
    /// before the first dictation can happen, and it shares the machine with the
    /// clean-up model that runs after every transcription. Recommending the
    /// heaviest runnable build buys accuracy most dictation never notices and pays
    /// for it in load time, resident memory, and a live preview that lags behind
    /// the voice.
    ///
    /// So: the largest offered model that fits both `speechMemoryBudget` and the
    /// patience ceiling for loading it, never above what WhisperKit says the chip
    /// supports. That lands on Quick at 8 GB, Balanced at 16 GB, and the
    /// compressed Large v3 Turbo — Sharp — from 24 GB up. Exacting is never
    /// recommended, only chosen: 30 seconds of cold load and 2.5 GB held for the
    /// session is a trade worth offering and not worth defaulting anyone into.
    static func recommended(
        for deviceVariant: String?,
        among offered: [SpeechModel],
        physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory
    ) -> SpeechModel? {
        guard !offered.isEmpty else { return nil }

        let budget = speechMemoryBudget(physicalMemory: physicalMemory)

        // Never recommend past what the chip is said to handle, even when there is
        // memory for it — a model the device can't run well is not a recommendation.
        let ceiling = deviceCeiling(for: deviceVariant, among: offered)
        let candidates = offered.filter { $0.bytes <= ceiling }

        let affordable = candidates.filter {
            $0.workingMemory <= budget && $0.loadSeconds <= patienceSeconds
        }
        // `offered` is ordered smallest-first, so the last affordable one is the
        // most accurate that fits. When nothing fits, the lightest is still the
        // right answer — recommending nothing would just leave the user guessing.
        return affordable.last ?? candidates.first ?? offered.first
    }

    /// Why this model and not a heavier one, in one line, for the recommended row.
    ///
    /// The badge alone invites the obvious suspicion — that we are recommending
    /// the small one to save ourselves work — so the reason is stated where the
    /// choice is made rather than buried in a support page.
    static func recommendationReason(
        for model: SpeechModel,
        among offered: [SpeechModel]
    ) -> String {
        let heavier = offered.contains { $0.bytes > model.bytes }
        guard heavier else {
            return "The most accurate model this Mac can run without slowing everything else down."
        }
        return "Loads in about \(Int(model.loadSeconds))s and leaves memory free for the clean-up model. Heavier models are more accurate, but you will feel them."
    }

    /// The heaviest offered model WhisperKit's per-device recommendation endorses,
    /// as a size in bytes.
    ///
    /// The recommendation is frequently a variant we don't offer — an M2 is told
    /// `openai_whisper-large-v3-v20240930` where we list the compressed build of
    /// the same model. Falling back on the model family keeps the ceiling
    /// meaningful instead of collapsing whenever the ids fail to match exactly.
    private static func deviceCeiling(for variant: String?, among offered: [SpeechModel]) -> Int64 {
        guard let variant else { return .max }
        if let exact = offered.first(where: { $0.variant == variant }) { return exact.bytes }

        let families = ["large-v3", "large-v2", "medium", "small", "base", "tiny"]
        guard let family = families.first(where: { variant.contains($0) }),
              let match = offered.last(where: { $0.variant.contains(family) })
        else { return .max }
        return match.bytes
    }

    // MARK: Families

    /// The Whisper models WhisperKit ships builds of, lightest first, each with
    /// the line that decides whether to look inside it at all.
    ///
    /// Ordered rather than looked up by name so the Advanced list reads like the
    /// curated one — a ladder from fastest to most accurate — instead of like a
    /// directory listing. Anything WhisperKit adds later sorts to the end rather
    /// than interleaving unpredictably.
    private static let familyOrder: [(id: String, name: String, summary: String)] = [
        ("tiny", "Whisper Tiny",
         "The fastest thing here and the least accurate. Fine for short, clearly spoken notes."),
        ("base", "Whisper Base",
         "Twice Tiny's size, noticeably steadier. Still fast enough to keep up with speech."),
        ("small", "Whisper Small",
         "Where accents and background noise stop being a problem. The safe choice on an older Mac."),
        ("medium", "Whisper Medium",
         "Superseded: Large v3 Turbo is more accurate than this and loads faster. Little reason to pick it."),
        ("large-v2", "Whisper Large v2",
         "The previous flagship. Large v3 beats it at the same size — kept for anyone who tuned around v2."),
        ("large-v3-turbo", "Whisper Large v3 Turbo",
         "Large v3's accuracy with a much smaller decoder. The best accuracy-per-second on Apple silicon."),
        ("large-v3", "Whisper Large v3",
         "The most accurate Whisper there is, and the slowest to load and heaviest on memory."),
        ("distil-large-v3", "Distil Whisper Large v3",
         "A distilled copy of Large v3: faster, a little less accurate, and English only."),
    ]

    private static func familyName(_ id: String) -> String? {
        familyOrder.first { $0.id == id }?.name
    }

    private static func familySummary(_ id: String) -> String? {
        familyOrder.first { $0.id == id }?.summary
    }

    private static func familyRank(_ id: String) -> Int {
        familyOrder.firstIndex { $0.id == id } ?? familyOrder.count
    }

    /// Which model a variant is a build of.
    ///
    /// Matched longest-first: `large-v3-v20240930` is the Turbo release and has to
    /// be caught before the `large-v3` it contains, or every Turbo build would
    /// file itself under the model it was derived from.
    private static func familyID(for variant: String) -> String {
        let stems = [
            ("large-v3-v20240930", "large-v3-turbo"),
            ("large-v3", "large-v3"),
            ("large-v2", "large-v2"),
            ("medium", "medium"),
            ("small", "small"),
            ("base", "base"),
            ("tiny", "tiny"),
        ]
        let base = stems.first { variant.contains($0.0) }?.1 ?? "other"
        return variant.contains("distil") ? "distil-" + base : base
    }

    /// Approximate full-precision weight size for a family, in bytes.
    ///
    /// WhisperKit spells the size out in the identifier only for quantised builds
    /// — `..._626MB` — so the full-precision rows would otherwise be the only ones
    /// in the list with no size at all, which is precisely backwards: they are the
    /// large ones. These are parameter count times two bytes per float16 weight,
    /// which lands within a few percent of the real download and is enough to
    /// choose by. Zero for anything unrecognised, so an unknown build says nothing
    /// rather than something wrong.
    private static func fullPrecisionBytes(family: String) -> Int64 {
        switch family {
        case "tiny": 78_000_000            // 39M parameters
        case "base": 148_000_000           // 74M
        case "small": 483_000_000          // 244M
        case "medium": 1_538_000_000       // 769M
        case "large-v2", "large-v3": 3_100_000_000  // 1550M
        case "large-v3-turbo": 1_618_000_000        // 809M
        case "distil-large-v3": 1_512_000_000       // 756M
        default: 0
        }
    }

    // MARK: Describing arbitrary variants

    /// A stand-in row for a variant the user already has that this list no longer
    /// offers.
    ///
    /// Installs from before the catalogue was narrowed are running models like
    /// `openai_whisper-large-v3-v20240930`, which is a perfectly good model and
    /// simply isn't one of the five. Silently remapping it to the nearest offered
    /// build would force a second several-hundred-megabyte download to end up
    /// somewhere no better, and omitting it would leave the list showing nothing
    /// in use while the app transcribes happily. So it gets a row of its own.
    static func legacy(_ variant: String) -> SpeechModel {
        let described = describe(variant)
        return SpeechModel(
            variant: variant,
            name: "Your current model",
            technicalName: described.technicalName,
            summary: "Chosen before this list was simplified. It still works — switch only if you want to.",
            bytes: described.bytes,
            loadSeconds: described.loadSeconds,
            family: described.family,
            qualifier: described.qualifier
        )
    }

    /// Turns any WhisperKit variant into something displayable.
    ///
    /// Advanced mode lists whatever the device catalogue returns, which changes
    /// with WhisperKit releases, so this parses the identifier rather than
    /// matching a table that would silently go stale. The parts that change how
    /// the model behaves come out on the axis each belongs to: the model itself
    /// becomes the family, and the packaging — quantisation, Turbo build,
    /// English-only — becomes the qualifier, which is what separates one row from
    /// its siblings once they are grouped.
    static func describe(_ variant: String) -> SpeechModel {
        if let curated = model(for: variant) { return curated }

        let family = familyID(for: variant)
        var core = variant
        var notes: [String] = []
        var qualifiers: [String] = []

        let distilled = core.contains("distil")
        for prefix in ["openai_whisper-", "distil-whisper_distil-", "distil-whisper_"]
        where core.hasPrefix(prefix) {
            core.removeFirst(prefix.count)
            break
        }

        // Trailing underscore-separated tags: a quantised size ("626MB"), "turbo",
        // or something a future release invents.
        var bytes: Int64 = 0
        let parts = core.split(separator: "_")
        core = String(parts.first ?? "")
        for tag in parts.dropFirst() {
            if let mb = megabytes(in: tag) {
                bytes = mb * 1_000_000
                notes.append("Compressed to \(mb) MB.")
                qualifiers.append("Compressed")
            } else if tag == "turbo" {
                // Kept even when the name already reads "Turbo" — the catalogue
                // lists `large-v3-v20240930` and `large-v3-v20240930_turbo` side by
                // side, and without this the two rows would be indistinguishable.
                notes.append("Turbo packaging — faster decoding.")
                qualifiers.insert("Turbo build", at: 0)
            } else {
                notes.append(String(tag))
                qualifiers.append(String(tag))
            }
        }

        // Kept in the name, not just the summary: `tiny` and `tiny.en` otherwise
        // render as two identical rows, and picking the wrong one leaves someone
        // dictating in French at a model that will not do it.
        var englishOnly = false
        if core.hasSuffix(".en") {
            core.removeLast(3)
            englishOnly = true
            notes.append("English only — it will not transcribe other languages.")
            qualifiers.insert("English only", at: 0)
        }
        if distilled {
            notes.append("Distilled — faster than the model it copies, a little less accurate.")
        }

        // No quantised tag means the full float16 download, whose size the
        // identifier never states.
        if bytes == 0 {
            bytes = fullPrecisionBytes(family: family)
            qualifiers.append("Full precision")
        }

        // `large-v3-v20240930` is the turbo release of large v3; the date is how
        // Argmax spells it and is meaningless to anyone else.
        var display = core.replacingOccurrences(of: "-v20240930", with: " Turbo")
        display = display.replacingOccurrences(of: "large-v", with: "Large v")
        display = display.prefix(1).uppercased() + display.dropFirst()
        var name = (distilled ? "Distil Whisper " : "Whisper ") + display
        if englishOnly { name += " (English)" }

        return SpeechModel(
            variant: variant,
            name: name,
            technicalName: name,
            summary: notes.isEmpty
                ? "Full-precision build, straight from the WhisperKit catalogue."
                : notes.joined(separator: " "),
            bytes: bytes,
            loadSeconds: estimatedLoadSeconds(bytes: bytes),
            family: family,
            qualifier: sentenceCased(qualifiers)
        )
    }

    /// Joins the qualifier parts with only the first capitalised — "Turbo build ·
    /// compressed", not "Turbo build · Compressed". Each part is written
    /// capitalised at the point it is added because any of them can come first.
    private static func sentenceCased(_ parts: [String]) -> String {
        parts.enumerated()
            .map { $0.offset == 0 ? $0.element : $0.element.prefix(1).lowercased() + $0.element.dropFirst() }
            .joined(separator: " · ")
    }

    private static func megabytes(in tag: Substring) -> Int64? {
        guard tag.hasSuffix("MB") else { return nil }
        return Int64(tag.dropLast(2))
    }

    /// Rough load time for a variant outside the curated five, where there is no
    /// observed figure to use. A fixed compile cost plus a rate — enough to rank
    /// and to warn, not enough to quote.
    private static func estimatedLoadSeconds(bytes: Int64) -> Double {
        guard bytes > 0 else { return 0 }
        return 1.5 + Double(bytes) / 32_000_000
    }
}
