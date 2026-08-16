//
//  Typography.swift
//  NativeSTT
//
//  Gateway's type scale, resolved for macOS.
//
//  The web build scales continuously with clamp(); React Native picks one of two
//  discrete buckets from the viewport width. A Mac window is always wider than the
//  768pt breakpoint, so this target is always the `expanded` bucket. Conveniently,
//  the sizes the floating overlay uses — bodySm, caption, label — are identical in
//  both buckets, so that surface is bucket-independent by construction.
//
//  Three rules from §3 that the API is shaped to enforce:
//    · the display serif is never used below 28pt and never above weight 400
//    · `label` is the system's only uppercase style — it is an eyebrow, never
//      reading text
//    · mono carries numerics, with tabular figures anywhere digits are compared
//      or animate in place (the recording timer, most of all)
//

import SwiftUI
import os

// MARK: - Families

enum FontFamily {
    static let display = "InstrumentSerif-Regular"
    static let sans = "PlusJakartaSans-Regular"
    static let sansMedium = "PlusJakartaSans-Medium"
    static let sansSemiBold = "PlusJakartaSans-SemiBold"
    static let sansBold = "PlusJakartaSans-Bold"
    static let mono = "JetBrainsMono-Regular"
    static let monoMedium = "JetBrainsMono-Medium"

    /// Every face the design system actually uses. Registration is verified
    /// against this list at launch, because a missing face degrades silently into
    /// the system font — which looks plausible and is easy to ship by accident.
    static let all = [
        display, sans, sansMedium, sansSemiBold, sansBold, mono, monoMedium,
    ]
}

// MARK: - Scale

struct TypeStyle {
    let font: Font
    /// SwiftUI has no line-height property, so the difference between the design's
    /// line height and its font size is applied as line spacing.
    let lineSpacing: CGFloat
    let tracking: CGFloat
    let uppercase: Bool

    fileprivate init(
        _ name: String,
        size: CGFloat,
        lineHeight: CGFloat,
        tracking: CGFloat = 0,
        relativeTo: Font.TextStyle,
        uppercase: Bool = false
    ) {
        self.font = .custom(name, size: size, relativeTo: relativeTo)
        self.lineSpacing = max(0, lineHeight - size)
        self.tracking = tracking
        self.uppercase = uppercase
    }
}

enum Typography {
    // Display — Instrument Serif, regular weight only, never below 28pt.
    static let displayXl = TypeStyle(FontFamily.display, size: 72, lineHeight: 76, tracking: -1.6, relativeTo: .largeTitle)
    static let displayLg = TypeStyle(FontFamily.display, size: 56, lineHeight: 60, tracking: -1.2, relativeTo: .largeTitle)
    static let displayMd = TypeStyle(FontFamily.display, size: 40, lineHeight: 46, tracking: -0.8, relativeTo: .title)

    // Headings — sans, semibold.
    static let headingLg = TypeStyle(FontFamily.sansSemiBold, size: 32, lineHeight: 38, tracking: -0.4, relativeTo: .title)
    static let headingMd = TypeStyle(FontFamily.sansSemiBold, size: 26, lineHeight: 32, tracking: -0.3, relativeTo: .title2)
    static let headingSm = TypeStyle(FontFamily.sansSemiBold, size: 20, lineHeight: 26, tracking: -0.1, relativeTo: .title3)

    // Body — sans, regular.
    static let bodyLg = TypeStyle(FontFamily.sans, size: 18, lineHeight: 29, relativeTo: .body)
    static let bodyMd = TypeStyle(FontFamily.sans, size: 16, lineHeight: 25, relativeTo: .body)
    static let bodySm = TypeStyle(FontFamily.sans, size: 14, lineHeight: 21, relativeTo: .callout)
    static let caption = TypeStyle(FontFamily.caption, size: 13, lineHeight: 19, relativeTo: .caption)

    /// Mono, uppercase, wide-tracked. The only uppercase style in the system, and
    /// it is an overline — never reading text.
    static let label = TypeStyle(FontFamily.mono, size: 12, lineHeight: 16, tracking: 0.7, relativeTo: .caption2, uppercase: true)

    /// Emphasised body, for the one word in a sentence that carries the state.
    static let bodyMdMedium = TypeStyle(FontFamily.sansMedium, size: 16, lineHeight: 25, relativeTo: .body)
    static let bodySmMedium = TypeStyle(FontFamily.sansMedium, size: 14, lineHeight: 21, relativeTo: .callout)

    /// Numerics. Tabular by definition — see `.typeStyle(_:)`, which turns on
    /// monospaced digits for every mono style so figures don't jitter as they
    /// change in place.
    static let mono13 = TypeStyle(FontFamily.mono, size: 13, lineHeight: 19, relativeTo: .caption)
    static let mono15 = TypeStyle(FontFamily.monoMedium, size: 15, lineHeight: 22, relativeTo: .body)
}

private extension FontFamily {
    /// Body copy at caption size still uses the sans face; only `label` and the
    /// numeric styles are mono.
    static let caption = sans
}

// MARK: - Application

private struct TypeStyleModifier: ViewModifier {
    let style: TypeStyle
    let isMono: Bool

    func body(content: Content) -> some View {
        content
            .font(isMono ? style.font.monospacedDigit() : style.font)
            .lineSpacing(style.lineSpacing)
            .tracking(style.tracking)
            .textCase(style.uppercase ? .uppercase : nil)
    }
}

extension View {
    func typeStyle(_ style: TypeStyle) -> some View {
        modifier(TypeStyleModifier(style: style, isMono: style.uppercase || style.tracking > 0.5))
    }

    /// Explicit tabular-figures variant, for the recording timer and any column of
    /// compared numbers.
    func typeStyleTabular(_ style: TypeStyle) -> some View {
        modifier(TypeStyleModifier(style: style, isMono: true))
    }
}

// MARK: - Registration

/// Registers the bundled OFL faces with CoreText at launch.
///
/// The fonts are registered in code rather than declared with
/// `ATSApplicationFontsPath` because a synchronized-folder target gives no
/// guarantee about whether `Resources/Fonts/*.ttf` lands in a `Fonts`
/// subdirectory of the bundle or flat alongside everything else. Scanning for the
/// files wherever they ended up is immune to that, and — more importantly — it
/// gives a real failure signal. AppKit has no synthetic bold: if
/// `PlusJakartaSans-SemiBold` fails to register, every semibold heading silently
/// falls back to the system font at regular weight and still looks fine at a
/// glance. That is exactly the bug worth being loud about.
enum FontRegistrar {
    private static let log = Logger(subsystem: "app.nativestt", category: "fonts")

    @discardableResult
    static func registerBundledFonts() -> [String] {
        var urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts") ?? []
        urls += Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []

        // De-duplicate: the two lookups can return the same file.
        var seen = Set<String>()
        let unique = urls.filter { seen.insert($0.lastPathComponent).inserted }

        for url in unique {
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                // Already-registered is benign — SwiftUI previews re-run this.
                let code = CFErrorGetCode(error?.takeUnretainedValue())
                if code != CTFontManagerError.alreadyRegistered.rawValue {
                    log.error("Failed to register \(url.lastPathComponent, privacy: .public): \(code)")
                }
            }
        }

        let missing = FontFamily.all.filter { NSFont(name: $0, size: 12) == nil }
        if missing.isEmpty {
            log.info("Registered \(unique.count) font files; all \(FontFamily.all.count) required faces resolve.")
        } else {
            log.error("MISSING FACES: \(missing.joined(separator: ", "), privacy: .public) — these will silently fall back to the system font.")
        }
        return missing
    }
}
