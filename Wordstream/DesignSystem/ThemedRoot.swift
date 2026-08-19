//
//  ThemedRoot.swift
//  Wordstream
//

import SwiftUI

/// Resolves the theme from the *live* system appearance and injects it.
///
/// This has to be a `View`, not a computed property on the `App`. `@Environment`
/// read at `App` scope is not reliably populated — `colorScheme` there reports
/// light regardless of the system setting, so the app was drawing light
/// backgrounds under a dark system while SwiftUI's own default label colours
/// followed the real appearance. Anything not explicitly coloured came out
/// light-on-light and vanished.
///
/// Reading `colorScheme` inside a View fixes that and makes appearance changes
/// live. `preferredColorScheme` keeps AppKit controls (pickers, fields, lists)
/// on the same light/dark as the tokens. The base `foregroundStyle` means a
/// control whose label colour we don't set explicitly inherits a theme colour
/// rather than a system default that may be for the opposite appearance.
struct ThemedRoot<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var prefs = Preferences.shared

    /// Paint `bgCanvas` behind the content. Windows want this; the overlay
    /// panel is transparent around the pill and must not.
    var fillsBackground: Bool = false

    @ViewBuilder var content: Content

    private var theme: Theme {
        prefs.theme(systemIsDark: colorScheme == .dark)
    }

    private var forcedColorScheme: ColorScheme? {
        switch prefs.appearance {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var body: some View {
        content
            .environment(\.theme, theme)
            .foregroundStyle(theme.fgPrimary)
            .tint(theme.fgBrand)
            .preferredColorScheme(forcedColorScheme)
            .background(fillsBackground ? theme.bgCanvas : Color.clear)
    }
}

/// A radio group the design system actually controls.
///
/// `Picker(.radioGroup)` renders its option labels with AppKit's own colours,
/// which cannot be themed — under a mismatched appearance they render as
/// near-invisible ghost text. Owning the row means the label colour, hit target
/// and selected state all come from tokens.
struct GatewayRadioGroup<Value: Hashable>: View {
    @Environment(\.theme) private var theme

    @Binding var selection: Value
    var options: [(value: Value, label: String, detail: String?)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(options, id: \.value) { option in
                Button {
                    selection = option.value
                } label: {
                    HStack(alignment: .top, spacing: Space.x3) {
                        ZStack {
                            Circle()
                                .strokeBorder(
                                    selection == option.value ? theme.borderBrand : theme.borderStrong,
                                    lineWidth: selection == option.value ? 5 : 1
                                )
                                .frame(width: 16, height: 16)
                        }
                        .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(option.label)
                                .typeStyle(Typography.bodySm)
                                .foregroundStyle(theme.fgPrimary)
                            if let detail = option.detail {
                                Text(detail)
                                    .typeStyle(Typography.caption)
                                    .foregroundStyle(theme.fgTertiary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: Layout.tapTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == option.value ? [.isSelected, .isButton] : .isButton)
            }
        }
    }
}

/// A labelled switch whose label is ours.
///
/// `Toggle("text", isOn:)` hands its label to AppKit, which in a menu-bar
/// popover dropped it entirely. Building the row explicitly guarantees the
/// label exists and is themed.
struct GatewayToggleRow: View {
    @Environment(\.theme) private var theme

    var title: String
    var detail: String?
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.x4) {
            VStack(alignment: .leading, spacing: Space.x1) {
                Text(title)
                    .typeStyle(Typography.bodySmMedium)
                    .foregroundStyle(theme.fgPrimary)
                if let detail {
                    Text(detail)
                        .typeStyle(Typography.caption)
                        .foregroundStyle(theme.fgTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Space.x4)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .frame(minHeight: Layout.tapTarget)
        .padding(.vertical, Space.x1)
    }
}
