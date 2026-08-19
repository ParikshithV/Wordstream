//
//  MenuBarContentView.swift
//  Wordstream
//

import SwiftUI
import AppKit

struct MenuBarContentView: View {
    @Environment(\.theme) private var theme
    @Environment(\.openWindow) private var openWindow
    var coordinator: DictationCoordinator

    @State private var prefs = Preferences.shared
    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x3) {
            header

            if let transcript = coordinator.lastTranscript {
                lastDictation(transcript)
            }

            GatewayToggleRow(title: "Live preview while speaking", isOn: $prefs.livePreview)

            actions
        }
        .padding(Space.x4)
        .frame(width: 300)
        .background(theme.bgSurface)
    }

    private var header: some View {
        HStack(spacing: Space.x3) {
            AssistantStateMotif(state: coordinator.assistantState, scale: 0.9)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 1) {
                Text(coordinator.assistantState.eyebrow)
                    .typeStyle(Typography.label)
                    .foregroundStyle(theme.fgTertiary)
                Text(statusLine)
                    .typeStyle(Typography.bodySmMedium)
                    .foregroundStyle(theme.fgPrimary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
    }

    /// The transcript sits in its own card so it reads as content rather than as
    /// another row of controls.
    private func lastDictation(_ transcript: Transcript) -> some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            Text("Last dictation")
                .typeStyle(Typography.label)
                .foregroundStyle(theme.fgTertiary)
            Text(transcript.finalText)
                .typeStyle(Typography.bodySm)
                .foregroundStyle(theme.fgSecondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(transcript.finalText, forType: .string)
                withAnimation(Motion.standard(Motion.fast)) { didCopy = true }
            } label: {
                Label(
                    didCopy ? "Copied" : "Copy transcript",
                    systemImage: didCopy ? "checkmark" : "doc.on.doc"
                )
            }
            .buttonStyle(GatewayButtonStyle(variant: .secondary, size: .sm, fullWidth: true))
        }
        .padding(Space.x3)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(theme.bgSurfaceAlt)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(theme.borderSubtle, lineWidth: 1)
        )
        .onChange(of: transcript.finalText) { didCopy = false }
    }

    /// One list, one visual language: every option is an icon-led row of the same
    /// height, so the group scans as a menu instead of as stacked buttons.
    private var actions: some View {
        VStack(spacing: 0) {
            MenuActionRow(title: "History", icon: "clock.arrow.circlepath", opensWindow: true) {
                openWindow(id: "history")
            }
            MenuActionRow(title: "Settings", icon: "gearshape", opensWindow: true) {
                openWindow(id: "settings")
            }

            Divider()
                .overlay(theme.borderSubtle)
                .padding(.vertical, Space.x1)

            MenuActionRow(title: "Restart Wordstream", icon: "arrow.clockwise") {
                restart()
            }
            MenuActionRow(title: "Quit Wordstream", icon: "power", isDestructive: true) {
                NSApp.terminate(nil)
            }
        }
        .padding(Space.x1)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(theme.bgSurfaceAlt)
        )
    }

    /// Launch a second instance of this same bundle, then stand down once it is
    /// on its way — quitting first would leave nothing to hand off to if the
    /// launch fails.
    private func restart() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true

        NSWorkspace.shared.openApplication(
            at: Bundle.main.bundleURL,
            configuration: configuration
        ) { _, _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }

    private var statusLine: String {
        switch coordinator.engine.state {
        case .idle:
            "No model loaded"
        case let .downloading(progress):
            "Downloading model — \(Int(progress * 100))%"
        case .loading:
            "Loading model\u{2026}"
        case .failed:
            "Model failed to load"
        case .ready:
            coordinator.isMonitoring
                ? prefs.dictationShortcut.displayName
                : "Dictation key not connected"
        }
    }
}

// MARK: - Action row

/// A full-width menu option: fixed icon gutter, label, and a hover fill that
/// covers the whole row rather than only the text. Ghost buttons gave each
/// option its own centred pill, which read as three unrelated controls.
private struct MenuActionRow: View {
    @Environment(\.theme) private var theme

    var title: String
    var icon: String
    /// Rows that open a window get the ellipsis and a trailing chevron.
    var opensWindow: Bool = false
    var isDestructive: Bool = false
    var action: () -> Void

    @State private var isHovering = false
    @FocusState private var isFocused: Bool

    private var tint: Color { isDestructive ? theme.fgDanger : theme.fgPrimary }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.x3) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18)
                    .foregroundStyle(isDestructive ? theme.fgDanger : theme.fgSecondary)

                Text(opensWindow ? "\(title)\u{2026}" : title)
                    .typeStyle(Typography.bodySmMedium)
                    .foregroundStyle(tint)

                Spacer(minLength: Space.x2)

                if opensWindow {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(theme.fgTertiary)
                        .opacity(isHovering ? 1 : 0)
                }
            }
            .padding(.horizontal, Space.x2)
            .frame(height: 34)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(isHovering ? (isDestructive ? theme.fgDanger.opacity(0.12) : theme.bgSubtle) : .clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .gatewayFocusRing(isFocused, radius: Radius.sm)
        .onHover { hovering in
            withAnimation(Motion.standard(Motion.fast)) { isHovering = hovering }
        }
        .accessibilityLabel(title)
    }
}
