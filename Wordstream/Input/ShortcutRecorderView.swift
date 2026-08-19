//
//  ShortcutRecorderView.swift
//  Wordstream
//

import SwiftUI
import AppKit
import Carbon.HIToolbox

/// Click, press the key you want, done.
///
/// Recording has to handle two different kinds of binding. A **chord** (⌃⌥D)
/// finishes on `keyDown`. A **bare modifier hold** (right ⌥) never produces a
/// `keyDown` at all, so it is only recognisable once the key is *released* with
/// nothing else having been pressed in between — which is why the recorder waits
/// for the flags to clear before committing one.
struct ShortcutRecorderView: View {
    @Environment(\.theme) private var theme
    @Binding var shortcut: Shortcut?
    var allowsClearing: Bool = false

    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var pendingModifier: ModifierKey?

    var body: some View {
        HStack(spacing: Space.x2) {
            Button {
                isRecording ? stop() : start()
            } label: {
                Text(label)
                    .typeStyle(isRecording ? Typography.bodySm : Typography.bodySmMedium)
                    .foregroundStyle(isRecording ? theme.fgBrand : theme.fgPrimary)
                    .frame(minWidth: 150, minHeight: Layout.tapTarget)
                    .padding(.horizontal, Space.x3)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(isRecording ? theme.bgBrandSubtle : theme.bgSurfaceAlt)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(
                                isRecording ? theme.borderBrand : theme.borderDefault,
                                lineWidth: isRecording ? Layout.focusRingWidth : 1
                            )
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isRecording ? "Recording shortcut, press a key" : "Shortcut: \(label)")

            if allowsClearing, shortcut != nil, !isRecording {
                Button {
                    shortcut = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(theme.fgTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear shortcut")
            }
        }
        .onDisappear { stop() }
    }

    private var label: String {
        if isRecording { return "Press a key…" }
        return shortcut?.displayName ?? "Not set"
    }

    private func start() {
        isRecording = true
        pendingModifier = nil

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            switch event.type {
            case .keyDown:
                if event.keyCode == UInt16(kVK_Escape) {
                    stop()
                    return nil
                }
                let relevant: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
                let flags = event.modifierFlags.intersection(relevant)
                // A chord needs at least one modifier, or it would swallow every
                // ordinary keystroke system-wide once bound.
                guard !flags.isEmpty else { return nil }
                shortcut = .chord(
                    keyCode: Int64(event.keyCode),
                    modifiers: UInt64(cgFlags(from: flags).rawValue)
                )
                stop()
                return nil

            case .flagsChanged:
                guard let key = ModifierKey.allCases.first(where: { $0.keyCode == Int64(event.keyCode) })
                else { return nil }

                let isDown = (event.modifierFlags.rawValue & UInt(key.deviceMask)) != 0
                if isDown {
                    pendingModifier = key
                } else if pendingModifier == key {
                    // Released cleanly with no other key in between — a hold.
                    shortcut = .modifierHold(key)
                    stop()
                }
                return nil

            default:
                return event
            }
        }
    }

    private func stop() {
        isRecording = false
        pendingModifier = nil
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private func cgFlags(from flags: NSEvent.ModifierFlags) -> CGEventFlags {
        var result: CGEventFlags = []
        if flags.contains(.command) { result.insert(.maskCommand) }
        if flags.contains(.option) { result.insert(.maskAlternate) }
        if flags.contains(.control) { result.insert(.maskControl) }
        if flags.contains(.shift) { result.insert(.maskShift) }
        return result
    }
}
