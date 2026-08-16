//
//  Tokens.swift
//  NativeSTT
//
//  The Gateway design system, ported to SwiftUI. Mirrors tokens/tokens.css and
//  tokens/tokens.ts from the Gateway repo — if you change one, change all three.
//
//  Gateway organises colour in three layers, and the whole point is that components
//  may only touch layer 3:
//
//      1. PALETTE   the swappable pastel theme          — nobody, directly
//      2. PRIMITIVE neutrals, status hues               — nobody, directly
//      3. SEMANTIC  bg-*, fg-*, border-*, focus-ring    — components, only these
//
//  On web that rule is a convention. Here it is enforced by the compiler: layers 1
//  and 2 are `private` to this file, so the only way out of them is through `Theme`.
//  A view in any other file cannot reach a raw hex value even by accident, which is
//  exactly what keeps the palette switch and the dark theme token swaps rather than
//  rewrites.
//

import SwiftUI

// MARK: - Hex

private extension Color {
    /// Layer-1/2 construction only. Deliberately private: raw hex must not be
    /// reachable from anywhere a component can see.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

// MARK: - Layer 1: Palette

private struct PaletteValues {
    let primary: Color
    let primaryDeep: Color
    let primaryLite: Color
    let soft: Color
    let softDark: Color
    let accent: Color
    let accentSoft: Color
    let mid: Color
}

/// The six pastel themes. Every `primary` clears 4.5:1 against white, so it can
/// carry white text as a fill in any theme — that constraint is what makes the
/// system honestly themeable rather than decorative. `accent` is the warm terminus
/// of the ramp and is decorative only; it must never carry small text.
enum Palette: String, CaseIterable, Identifiable, Codable, Sendable {
    case dawn, grove, blush, lagoon, lilac, clay

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .dawn: "Dawn"
        case .grove: "Grove"
        case .blush: "Blush"
        case .lagoon: "Lagoon"
        case .lilac: "Lilac"
        case .clay: "Clay"
        }
    }

    /// The ramp described in one phrase, as the Gateway docs table does.
    var character: String {
        switch self {
        case .dawn: "Indigo → peach"
        case .grove: "Sage → wheat"
        case .blush: "Dusty rose → apricot"
        case .lagoon: "Deep teal → sand"
        case .lilac: "Lilac → butter"
        case .clay: "Terracotta → sky"
        }
    }

    fileprivate var values: PaletteValues {
        switch self {
        case .dawn:
            PaletteValues(primary: Color(hex: 0x3A39CE), primaryDeep: Color(hex: 0x2A27B8),
                          primaryLite: Color(hex: 0xB6C2F9), soft: Color(hex: 0xEEF0FF),
                          softDark: Color(hex: 0x22224A), accent: Color(hex: 0xE8853F),
                          accentSoft: Color(hex: 0xF9C8B2), mid: Color(hex: 0x9180CD))
        case .grove:
            PaletteValues(primary: Color(hex: 0x3F6B46), primaryDeep: Color(hex: 0x2F5335),
                          primaryLite: Color(hex: 0xA9CBAE), soft: Color(hex: 0xEDF3EC),
                          softDark: Color(hex: 0x1E2E20), accent: Color(hex: 0xD9A441),
                          accentSoft: Color(hex: 0xF0DCA8), mid: Color(hex: 0x8FAE7E))
        case .blush:
            PaletteValues(primary: Color(hex: 0xA8446B), primaryDeep: Color(hex: 0x87304F),
                          primaryLite: Color(hex: 0xEFB3C6), soft: Color(hex: 0xFBEDF1),
                          softDark: Color(hex: 0x331B24), accent: Color(hex: 0xE58B62),
                          accentSoft: Color(hex: 0xF6C9AE), mid: Color(hex: 0xCE7C88))
        case .lagoon:
            PaletteValues(primary: Color(hex: 0x2C6E75), primaryDeep: Color(hex: 0x1F5359),
                          primaryLite: Color(hex: 0xA5CFD2), soft: Color(hex: 0xE6F1F2),
                          softDark: Color(hex: 0x142E31), accent: Color(hex: 0xDFA469),
                          accentSoft: Color(hex: 0xF2DBBE), mid: Color(hex: 0x7FB0AE))
        case .lilac:
            PaletteValues(primary: Color(hex: 0x6B4C9A), primaryDeep: Color(hex: 0x523878),
                          primaryLite: Color(hex: 0xC9B4E8), soft: Color(hex: 0xF2EDFA),
                          softDark: Color(hex: 0x241B33), accent: Color(hex: 0xD9A93F),
                          accentSoft: Color(hex: 0xF1DCA6), mid: Color(hex: 0xA98BC8))
        case .clay:
            PaletteValues(primary: Color(hex: 0xA85436), primaryDeep: Color(hex: 0x853F27),
                          primaryLite: Color(hex: 0xEDAF93), soft: Color(hex: 0xFAEDE7),
                          softDark: Color(hex: 0x33190F), accent: Color(hex: 0x5E8CA6),
                          accentSoft: Color(hex: 0xB9D2DF), mid: Color(hex: 0xC98B6B))
        }
    }

    /// The three dots the §7 palette picker shows: both ends of the ramp plus the
    /// tinted surface, so the choice is legible before it is applied. This is the
    /// one narrow, deliberate window onto layer 1 — the picker genuinely cannot do
    /// its job without it.
    var swatch: (rampStart: Color, rampEnd: Color, soft: Color) {
        (values.primaryDeep, values.accent, values.soft)
    }
}

// MARK: - Layer 2: Primitives

/// Warm-leaning, anchored on a warm near-black. Pure #000 against a warm accent
/// reads as a hole; #151312 reads as ink. Identical across all palettes.
private enum Neutral {
    static let n0 = Color(hex: 0xFFFFFF)
    static let n25 = Color(hex: 0xFAFAFA)
    static let n50 = Color(hex: 0xF1F1F1)
    static let n100 = Color(hex: 0xE8E8E8)
    static let n200 = Color(hex: 0xD6D6D6)
    static let n300 = Color(hex: 0xB4B4B4)
    static let n400 = Color(hex: 0x8C8C8C)
    static let n500 = Color(hex: 0x6B6B6B)
    static let n700 = Color(hex: 0x3D3D3D)
    static let n900 = Color(hex: 0x1F1F1F)
    static let n950 = Color(hex: 0x151312)
}

private enum StatusHue {
    static let success = Color(hex: 0x2F855A)
    static let warning = Color(hex: 0xB7791F)
    static let danger = Color(hex: 0xC53030)
}

// MARK: - Layer 3: Semantic

/// Everything a view is allowed to colour with. Both the palette switch and the
/// dark theme are a swap of this one struct.
struct Theme: Equatable {
    var palette: Palette
    var isDark: Bool

    // Backgrounds
    var bgCanvas: Color
    var bgSurface: Color
    var bgSurfaceAlt: Color
    var bgInverse: Color
    var bgSubtle: Color
    var bgBrand: Color
    var bgBrandHover: Color
    var bgBrandSubtle: Color
    var bgAccent: Color

    // Foregrounds
    var fgPrimary: Color
    var fgSecondary: Color
    var fgTertiary: Color
    var fgDisabled: Color
    var fgInverse: Color
    var fgBrand: Color
    var fgOnBrand: Color
    var fgOnSubtle: Color

    // Status, surfaced here rather than as raw primitives so components still
    // only ever touch layer 3.
    var fgSuccess: Color
    var fgWarning: Color
    var fgDanger: Color

    // Borders
    var borderSubtle: Color
    var borderDefault: Color
    var borderStrong: Color
    var borderBrand: Color

    var focusRing: Color

    /// Shadow ink. Dark theme deepens opacity rather than adding spread — a
    /// light-theme shadow simply disappears on a dark canvas.
    var shadowColor: Color
    var shadowScale: Double

    /// The motif's material: lit from above, light at the top edge and saturated at
    /// the bottom, sampled from the active palette's ramp. A flat brand-coloured
    /// motif is a bug (§5), which is why this is a ramp and not `bgBrand`.
    var motifStops: [Color]

    /// The single page-level hero gradient. The system's entire gradient budget is
    /// two, and the other one is the docs ramp specimen, which this app has no use
    /// for — so in practice this is the only gradient in the product.
    var heroStops: [Gradient.Stop]

    static func light(_ palette: Palette) -> Theme {
        let c = palette.values
        return Theme(
            palette: palette, isDark: false,
            bgCanvas: Neutral.n50, bgSurface: Neutral.n0, bgSurfaceAlt: Neutral.n25,
            bgInverse: Neutral.n950, bgSubtle: Neutral.n100,
            bgBrand: c.primary, bgBrandHover: c.primaryDeep, bgBrandSubtle: c.soft,
            bgAccent: c.accent,
            fgPrimary: Neutral.n900, fgSecondary: Neutral.n700, fgTertiary: Neutral.n500,
            fgDisabled: Neutral.n400, fgInverse: Neutral.n0,
            fgBrand: c.primary, fgOnBrand: Neutral.n0, fgOnSubtle: c.primaryDeep,
            fgSuccess: StatusHue.success, fgWarning: StatusHue.warning, fgDanger: StatusHue.danger,
            borderSubtle: Neutral.n100, borderDefault: Neutral.n200,
            borderStrong: Neutral.n300, borderBrand: c.primary,
            focusRing: c.primary,
            shadowColor: Neutral.n950, shadowScale: 1.0,
            motifStops: [c.soft, c.mid, c.primary],
            heroStops: [
                .init(color: c.primaryDeep, location: 0),
                .init(color: c.primary, location: 0.38),
                .init(color: c.mid, location: 0.68),
                .init(color: c.accentSoft, location: 1),
            ]
        )
    }

    static func dark(_ palette: Palette) -> Theme {
        let c = palette.values
        return Theme(
            palette: palette, isDark: true,
            bgCanvas: Neutral.n950, bgSurface: Color(hex: 0x1C1A19), bgSurfaceAlt: Color(hex: 0x232120),
            bgInverse: Neutral.n0, bgSubtle: Color(hex: 0x2A2827),
            bgBrand: c.primary, bgBrandHover: c.primaryDeep, bgBrandSubtle: c.softDark,
            bgAccent: c.accent,
            fgPrimary: Color(hex: 0xF5F4F3), fgSecondary: Color(hex: 0xC9C6C4),
            fgTertiary: Color(hex: 0x94908D), fgDisabled: Color(hex: 0x6B6764),
            fgInverse: Neutral.n950,
            fgBrand: c.primaryLite, fgOnBrand: Neutral.n0, fgOnSubtle: c.primaryLite,
            fgSuccess: StatusHue.success, fgWarning: StatusHue.warning, fgDanger: StatusHue.danger,
            borderSubtle: Color(hex: 0x2E2B2A), borderDefault: Color(hex: 0x3D3937),
            borderStrong: Color(hex: 0x55504D), borderBrand: c.primaryLite,
            focusRing: c.primaryLite,
            shadowColor: .black, shadowScale: 5.5,
            motifStops: [c.primaryLite, c.mid, c.primaryDeep],
            heroStops: [
                .init(color: c.primaryDeep, location: 0),
                .init(color: c.primary, location: 0.38),
                .init(color: c.mid, location: 0.68),
                .init(color: c.accentSoft, location: 1),
            ]
        )
    }

    static func resolve(palette: Palette, dark: Bool) -> Theme {
        dark ? .dark(palette) : .light(palette)
    }
}

// MARK: - Space, radius, elevation, motion
//
// Palette-independent, so these need no layer discipline.

/// Base unit 4. Nothing off-scale.
enum Space {
    static let x1: CGFloat = 4
    static let x2: CGFloat = 8
    static let x3: CGFloat = 12
    static let x4: CGFloat = 16
    static let x5: CGFloat = 20
    static let x6: CGFloat = 24
    static let x8: CGFloat = 32
    static let x10: CGFloat = 40
    static let x12: CGFloat = 48
    static let x16: CGFloat = 64
    static let x20: CGFloat = 80
    static let x24: CGFloat = 96
}

/// Generous by design — soft corners echo the cusped geometry of the motif.
/// Buttons, chips and inputs are pill or `md`; cards are `xl`.
enum Radius {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let pill: CGFloat = 999
}

/// Low-contrast and warm-tinted. CSS blur is roughly twice SwiftUI's shadow
/// radius, so the values are halved on the way across.
enum Elevation {
    case xs, sm, md, lg

    var radius: CGFloat {
        switch self {
        case .xs: 1
        case .sm: 3
        case .md: 9
        case .lg: 20
        }
    }

    var y: CGFloat {
        switch self {
        case .xs: 1
        case .sm: 2
        case .md: 6
        case .lg: 14
        }
    }

    var opacity: Double {
        switch self {
        case .xs: 0.06
        case .sm: 0.07
        case .md: 0.09
        case .lg: 0.12
        }
    }
}

extension View {
    func elevation(_ level: Elevation, _ theme: Theme) -> some View {
        shadow(
            color: theme.shadowColor.opacity(level.opacity * theme.shadowScale),
            radius: level.radius,
            x: 0,
            y: level.y
        )
    }
}

/// `pulse` is the brand's signature cadence — the loader, the "thinking" motif and
/// any breathing state all share it, so the product reads as one metronome.
enum Motion {
    static let easeStandard = SwiftUI.Animation.timingCurve(0.4, 0, 0.2, 1)
    static let easeEntrance = SwiftUI.Animation.timingCurve(0.16, 1, 0.3, 1)

    static let fast: Double = 0.14
    static let normal: Double = 0.24
    static let slow: Double = 0.42
    static let pulse: Double = 2.0

    static func standard(_ duration: Double = normal) -> SwiftUI.Animation {
        .timingCurve(0.4, 0, 0.2, 1, duration: duration)
    }

    static func entrance(_ duration: Double = normal) -> SwiftUI.Animation {
        .timingCurve(0.16, 1, 0.3, 1, duration: duration)
    }

    /// Every animation needs a reduced-motion fallback: the pulse becomes a static
    /// mark, the waveform freezes, entrances become instant.
    @MainActor static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
}

/// The shared interactive contract: ≥44pt targets, everywhere.
enum Layout {
    static let tapTarget: CGFloat = 44
    static let focusRingWidth: CGFloat = 2
    static let focusRingOffset: CGFloat = 2
    static let disabledOpacity: Double = 0.45
}

// MARK: - Environment

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme.light(.dawn)
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}
