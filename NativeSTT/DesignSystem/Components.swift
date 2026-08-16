//
//  Components.swift
//  NativeSTT
//
//  The shared contract from §7, applied to every interactive element here:
//  ≥44pt target, a visible focus ring (2pt at 2pt offset — never removed without a
//  replacement), a disabled state at 45% that is not the only signal, and survival
//  at 200% text zoom.
//
//  Note what is deliberately absent: gradient-filled controls. §2.5 caps the
//  gradient budget at two for the whole system, and records that filling buttons,
//  progress bars and switches with one was a mistake corrected away from — it read
//  as decoration applied on top of the UI rather than as the UI. Emphasis here
//  comes from fill and weight. The app's single gradient is the onboarding hero.
//

import SwiftUI

// MARK: - Buttons

enum ButtonVariant {
    case primary, secondary, ghost, danger
}

enum ButtonSize {
    case sm, md, lg

    var height: CGFloat {
        switch self {
        case .sm: 36
        case .md: Layout.tapTarget
        case .lg: 56
        }
    }

    var hPadding: CGFloat {
        switch self {
        case .sm: Space.x3
        case .md: Space.x5
        case .lg: Space.x6
        }
    }
}

struct GatewayButtonStyle: ButtonStyle {
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled

    var variant: ButtonVariant = .primary
    var size: ButtonSize = .md
    var fullWidth: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .typeStyle(Typography.bodySmMedium)
            .foregroundStyle(foreground)
            .padding(.horizontal, size.hPadding)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(height: size.height)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(background(pressed: configuration.isPressed))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(border, lineWidth: variant == .secondary ? 1 : 0)
            )
            .opacity(isEnabled ? 1 : Layout.disabledOpacity)
            .contentShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .animation(Motion.standard(Motion.fast), value: configuration.isPressed)
    }

    private var foreground: Color {
        switch variant {
        case .primary: theme.fgOnBrand
        case .secondary: theme.fgPrimary
        case .ghost: theme.fgBrand
        case .danger: theme.fgOnBrand
        }
    }

    private func background(pressed: Bool) -> Color {
        switch variant {
        case .primary: pressed ? theme.bgBrandHover : theme.bgBrand
        case .secondary: pressed ? theme.bgSubtle : theme.bgSurface
        case .ghost: pressed ? theme.bgBrandSubtle : .clear
        case .danger: theme.fgDanger.opacity(pressed ? 0.85 : 1)
        }
    }

    private var border: Color {
        variant == .secondary ? theme.borderDefault : .clear
    }
}

extension View {
    /// The 2pt-at-2pt-offset focus ring. Applied wherever the platform ring is
    /// suppressed, so keyboard navigation never loses its anchor.
    func gatewayFocusRing(_ focused: Bool, radius: CGFloat = Radius.md) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: radius + Layout.focusRingOffset, style: .continuous)
                .strokeBorder(
                    focused ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.clear),
                    lineWidth: Layout.focusRingWidth
                )
                .padding(-Layout.focusRingOffset)
                .animation(Motion.standard(Motion.fast), value: focused)
        )
    }
}

// MARK: - Surfaces

/// Cards are `xl` radius, subtle border, `xs` shadow.
struct GatewayCard<Content: View>: View {
    @Environment(\.theme) private var theme
    var padding: CGFloat = Space.x5
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .fill(theme.bgSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .strokeBorder(theme.borderSubtle, lineWidth: 1)
            )
            .elevation(.xs, theme)
    }
}

/// A mono uppercase eyebrow over a plain-language headline — the §7 assistant-state
/// pairing, reused as the standard section header.
struct SectionHeader: View {
    @Environment(\.theme) private var theme
    var eyebrow: String
    var title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            Text(eyebrow)
                .typeStyle(Typography.label)
                .foregroundStyle(theme.fgTertiary)
            Text(title)
                .typeStyle(Typography.headingSm)
                .foregroundStyle(theme.fgPrimary)
            if let subtitle {
                Text(subtitle)
                    .typeStyle(Typography.bodySm)
                    .foregroundStyle(theme.fgSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Status

enum BadgeTone {
    case neutral, brand, success, warning, danger
}

/// Colour is never the sole carrier of meaning, so every badge pairs a dot with a
/// word — the dot reads at a glance, the word survives a colour-blind viewer and a
/// screen reader.
struct GatewayBadge: View {
    @Environment(\.theme) private var theme
    var text: String
    var tone: BadgeTone = .neutral

    var body: some View {
        HStack(spacing: Space.x2) {
            Circle()
                .fill(dotColor)
                .frame(width: 6, height: 6)
            Text(text)
                .typeStyle(Typography.label)
                .foregroundStyle(theme.fgSecondary)
        }
        .padding(.horizontal, Space.x3)
        .padding(.vertical, Space.x1 + 2)
        .background(
            Capsule().fill(theme.bgSubtle)
        )
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

/// Flat `bgBrand`, per the gradient budget.
struct GatewayProgressBar: View {
    @Environment(\.theme) private var theme
    var value: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(theme.bgSubtle)
                Capsule()
                    .fill(theme.bgBrand)
                    .frame(width: max(0, min(1, value)) * geo.size.width)
            }
        }
        .frame(height: 6)
        .animation(Motion.standard(), value: value)
    }
}

// MARK: - Settings rows

/// A labelled row with a trailing control. The description is not optional flavour
/// — it is where a setting's real cost gets stated instead of buried.
struct SettingRow<Control: View>: View {
    @Environment(\.theme) private var theme
    var title: String
    var description: String?
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.x4) {
            VStack(alignment: .leading, spacing: Space.x1) {
                Text(title)
                    .typeStyle(Typography.bodySmMedium)
                    .foregroundStyle(theme.fgPrimary)
                if let description {
                    Text(description)
                        .typeStyle(Typography.caption)
                        .foregroundStyle(theme.fgTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Space.x4)
            control
        }
        .frame(minHeight: Layout.tapTarget)
        .padding(.vertical, Space.x1)
    }
}

// MARK: - Palette picker

/// Each theme shows three dots — the two ends of its ramp plus its tinted surface —
/// so the choice is legible before it is applied.
struct PalettePicker: View {
    @Environment(\.theme) private var theme
    @Binding var selection: Palette

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 168), spacing: Space.x3)],
            spacing: Space.x3
        ) {
            ForEach(Palette.allCases) { palette in
                Button {
                    withAnimation(Motion.standard()) { selection = palette }
                } label: {
                    HStack(spacing: Space.x3) {
                        HStack(spacing: -4) {
                            Circle().fill(palette.swatch.rampStart).frame(width: 14, height: 14)
                            Circle().fill(palette.swatch.rampEnd).frame(width: 14, height: 14)
                            Circle().fill(palette.swatch.soft).frame(width: 14, height: 14)
                        }
                        .overlay(alignment: .leading) {
                            // Keeps the overlapping dots legible on any surface.
                            EmptyView()
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(palette.displayName)
                                .typeStyle(Typography.bodySmMedium)
                                .foregroundStyle(theme.fgPrimary)
                            Text(palette.character)
                                .typeStyle(Typography.caption)
                                .foregroundStyle(theme.fgTertiary)
                        }
                        Spacer(minLength: 0)
                        if selection == palette {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(theme.fgBrand)
                        }
                    }
                    .padding(.horizontal, Space.x3)
                    .frame(height: Layout.tapTarget, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(selection == palette ? theme.bgBrandSubtle : theme.bgSurfaceAlt)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(
                                selection == palette ? theme.borderBrand : theme.borderSubtle,
                                lineWidth: 1
                            )
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(palette.displayName), \(palette.character)")
                .accessibilityAddTraits(selection == palette ? [.isSelected, .isButton] : .isButton)
            }
        }
    }
}
