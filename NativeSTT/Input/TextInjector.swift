//
//  TextInjector.swift
//  NativeSTT
//

import AppKit
import ApplicationServices
import Carbon.HIToolbox
import os

/// Puts the finished text into whatever app the user was in.
@MainActor
final class TextInjector {
    private let log = Logger(subsystem: "app.nativestt", category: "inject")

    /// Where the dictation started. Captured at key-down, because focus can move
    /// while Whisper is running and the text belongs where the user was pointing
    /// when they started speaking, not wherever they ended up.
    struct Target {
        let app: NSRunningApplication?
        let focusedElement: AXUIElement?

        static func capture() -> Target {
            let app = NSWorkspace.shared.frontmostApplication
            var focused: AnyObject?
            let system = AXUIElementCreateSystemWide()
            AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused)
            return Target(
                app: app,
                focusedElement: focused.map { unsafeBitCast($0, to: AXUIElement.self) }
            )
        }
    }

    func insert(_ text: String, into target: Target, mode: InsertionMode) {
        guard !text.isEmpty else { return }

        reactivateIfNeeded(target)

        switch mode {
        case .accessibility:
            if insertViaAccessibility(text, target: target) { return }
            log.info("Accessibility insertion did not take; falling back to paste.")
            insertViaPaste(text)
        case .paste:
            insertViaPaste(text)
        }
    }

    /// Reads the current selection, for Command Mode.
    func selectedText(in target: Target) -> String? {
        guard let element = focusedElement(for: target) else { return nil }
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &value) == .success,
              let text = value as? String, !text.isEmpty
        else { return nil }
        return text
    }

    // MARK: Accessibility path

    private func focusedElement(for target: Target) -> AXUIElement? {
        var focused: AnyObject?
        let system = AXUIElementCreateSystemWide()
        if AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
           let focused {
            return unsafeBitCast(focused, to: AXUIElement.self)
        }
        return target.focusedElement
    }

    /// Writes directly into the focused field.
    ///
    /// Verified by read-back rather than by return code, because many apps —
    /// Electron and web views especially — return `.success` for this and then do
    /// nothing at all. A silent no-op that reports success is worse than an error,
    /// so we check whether the selection actually changed.
    private func insertViaAccessibility(_ text: String, target: Target) -> Bool {
        guard let element = focusedElement(for: target) else { return false }

        var rangeBefore: AnyObject?
        let hadRange = AXUIElementCopyAttributeValue(
            element, kAXSelectedTextRangeAttribute as CFString, &rangeBefore
        ) == .success

        let status = AXUIElementSetAttributeValue(
            element, kAXSelectedTextAttribute as CFString, text as CFTypeRef
        )
        guard status == .success else { return false }

        guard hadRange else { return false }

        var rangeAfter: AnyObject?
        guard AXUIElementCopyAttributeValue(
            element, kAXSelectedTextRangeAttribute as CFString, &rangeAfter
        ) == .success else { return false }

        var before = CFRange(), after = CFRange()
        guard let rb = rangeBefore, let ra = rangeAfter,
              AXValueGetValue(unsafeBitCast(rb, to: AXValue.self), .cfRange, &before),
              AXValueGetValue(unsafeBitCast(ra, to: AXValue.self), .cfRange, &after)
        else { return false }

        // The caret should have advanced by the length of what we inserted.
        return after.location > before.location
    }

    // MARK: Paste path

    /// Copies, sends ⌘V, restores the clipboard.
    ///
    /// The clipboard is saved and restored across every representation type, not
    /// just the string — otherwise dictating once would quietly destroy a copied
    /// image or a rich-text snippet.
    private func insertViaPaste(_ text: String) {
        let pasteboard = NSPasteboard.general
        let saved = snapshotPasteboard(pasteboard)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        postCommandV()

        // The paste is asynchronous in the target app, so the clipboard has to
        // survive long enough for it to be read.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            self.restorePasteboard(pasteboard, from: saved)
        }
    }

    private func postCommandV() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }

        // Suppress the local keyboard's own state while we synthesise, so a
        // physically-held key can't combine with what we post.
        source.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )

        let v = CGKeyCode(kVK_ANSI_V)
        let down = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: false)

        // Assigning flags rather than OR-ing them is the point. The user is very
        // often still holding the dictation modifier at this moment; if right ⌥ is
        // down and we merely add ⌘, the target app receives ⌥⌘V — "paste and match
        // style" in some apps, nothing at all in others.
        down?.flags = .maskCommand
        up?.flags = .maskCommand

        down?.post(tap: .cgAnnotatedSessionEventTap)
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }

    private func reactivateIfNeeded(_ target: Target) {
        guard let app = target.app, !app.isActive else { return }
        app.activate()
    }

    // MARK: Pasteboard snapshot

    private struct PasteboardSnapshot {
        let items: [[NSPasteboard.PasteboardType: Data]]
    }

    private func snapshotPasteboard(_ pasteboard: NSPasteboard) -> PasteboardSnapshot {
        let items = (pasteboard.pasteboardItems ?? []).map { item in
            var contents: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    contents[type] = data
                }
            }
            return contents
        }
        return PasteboardSnapshot(items: items)
    }

    private func restorePasteboard(_ pasteboard: NSPasteboard, from snapshot: PasteboardSnapshot) {
        pasteboard.clearContents()
        guard !snapshot.items.isEmpty else { return }
        let restored = snapshot.items.map { contents -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in contents {
                item.setData(data, forType: type)
            }
            return item
        }
        pasteboard.writeObjects(restored)
    }
}
