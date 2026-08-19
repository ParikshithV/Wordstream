//
//  PermissionRow.swift
//  Wordstream
//

import SwiftUI

/// One permission, with the only interaction order that actually works.
///
/// The primary button always **requests** — never just opens System Settings.
/// macOS doesn't list an app under Microphone or Input Monitoring until that app
/// has asked for the permission at least once, so an "Open Settings" shortcut
/// offered first drops the user into a pane where the app they're looking for
/// isn't there. Once the request has happened the app is listed, and the pane
/// link becomes useful — which is why it only appears afterwards.
struct PermissionRow: View {
    @Environment(\.theme) private var theme

    var kind: PermissionsManager.Kind
    var title: String
    var detail: String
    var permissions: PermissionsManager
    /// Called after a request resolves, so callers can (re)start the event tap.
    var onChange: () -> Void = {}

    @State private var didRequest = false

    private var status: PermissionsManager.Status { permissions.status(kind) }

    var body: some View {
        HStack(alignment: .top, spacing: Space.x4) {
            Image(systemName: status.isGranted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(status.isGranted ? theme.fgSuccess : theme.fgTertiary)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: Space.x1) {
                Text(title)
                    .typeStyle(Typography.bodySmMedium)
                    .foregroundStyle(theme.fgPrimary)
                Text(detail)
                    .typeStyle(Typography.caption)
                    .foregroundStyle(theme.fgTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                if didRequest, !status.isGranted {
                    // Colour is never the sole carrier of meaning, and it also
                    // shouldn't be the loudest thing on screen. A small dot
                    // marks this as a caution; the words do the work.
                    HStack(alignment: .top, spacing: Space.x2) {
                        Circle()
                            .fill(theme.fgWarning)
                            .frame(width: 5, height: 5)
                            .padding(.top, 6)
                        Text("macOS only prompts once. Wordstream is now listed in System Settings — switch it on there, then come back to this window.")
                            .typeStyle(Typography.caption)
                            .foregroundStyle(theme.fgSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Spacer(minLength: Space.x4)

            if status.isGranted {
                GatewayBadge(text: "Granted", tone: .success)
            } else {
                VStack(alignment: .trailing, spacing: Space.x2) {
                    Button("Allow") {
                        Task {
                            await permissions.request(kind)
                            didRequest = true
                            onChange()
                        }
                    }
                    .buttonStyle(GatewayButtonStyle(variant: .primary, size: .sm))

                    if didRequest {
                        Button("Open Settings") {
                            permissions.openSettings(permissions.pane(for: kind))
                        }
                        .buttonStyle(GatewayButtonStyle(variant: .ghost, size: .sm))
                    }
                }
            }
        }
        .frame(minHeight: Layout.tapTarget)
    }
}
