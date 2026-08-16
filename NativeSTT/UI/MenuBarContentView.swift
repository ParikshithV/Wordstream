//
//  MenuBarContentView.swift
//  NativeSTT
//

import SwiftUI
import AppKit

struct MenuBarContentView: View {
    @Environment(\.theme) private var theme
    @Environment(\.openWindow) private var openWindow
    var coordinator: DictationCoordinator

    @State private var prefs = Preferences.shared

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x3) {
            header

            Divider().overlay(theme.borderSubtle)

            if let transcript = coordinator.lastTranscript {
                VStack(alignment: .leading, spacing: Space.x1) {
                    Text("Last dictation")
                        .typeStyle(Typography.label)
                        .foregroundStyle(theme.fgTertiary)
                    Text(transcript.finalText)
                        .typeStyle(Typography.bodySm)
                        .foregroundStyle(theme.fgSecondary)
                        .lineLimit(3)
                }

                Button("Copy last transcript") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(transcript.finalText, forType: .string)
                }
                .buttonStyle(GatewayButtonStyle(variant: .secondary, size: .sm, fullWidth: true))

                Divider().overlay(theme.borderSubtle)
            }

            Toggle("Live preview while speaking", isOn: $prefs.livePreview)
                .toggleStyle(.switch)
                .typeStyle(Typography.bodySm)

            Divider().overlay(theme.borderSubtle)

            Button("History\u{2026}") { openWindow(id: "history") }
                .buttonStyle(GatewayButtonStyle(variant: .ghost, size: .sm, fullWidth: true))

            Button("Settings\u{2026}") { openWindow(id: "settings") }
                .buttonStyle(GatewayButtonStyle(variant: .ghost, size: .sm, fullWidth: true))

            Button("Quit NativeSTT") { NSApp.terminate(nil) }
                .buttonStyle(GatewayButtonStyle(variant: .ghost, size: .sm, fullWidth: true))
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
