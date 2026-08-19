//
//  TextInjector.swift
//  Wordstream
//

import AppKit
import ApplicationServices
import Carbon.HIToolbox
import os

/// Puts the finished text into whatever app the user was in.
@MainActor
final class TextInjector {
    private let log = Logger(subsystem: "app.wordstream", category: "inject")

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
    ///
    /// Asked several ways, because a single question was not enough. Two things
    /// vary independently: *which element* holds the selection, and *how* that
    /// element chooses to expose it.
    ///
    /// On the element: the system-wide focused element is the normal answer, but
    /// it reports whatever is focused right now — and Wordstream is an accessory
    /// app that may have just put a panel on screen. So the target app is also
    /// asked directly by pid, and the element captured at key-down is kept as a
    /// last resort.
    ///
    /// On the attribute: `kAXSelectedText` is the direct question and most native
    /// controls answer it. Plenty of others — web views, some Electron surfaces —
    /// leave it unset while still publishing the full value and the selected
    /// range, so the selection can be sliced out of those instead.
    func selectedText(in target: Target) -> String? {
        for element in selectionCandidates(for: target) {
            if let direct = copyString(element, kAXSelectedTextAttribute), !direct.isEmpty {
                return direct
            }
            if let sliced = slicedSelection(from: element), !sliced.isEmpty {
                return sliced
            }
        }
        logSelectionDiagnostics(for: target)
        return nil
    }

    /// Every element that might plausibly own the selection, best guess first.
    private func selectionCandidates(for target: Target) -> [AXUIElement] {
        var candidates: [AXUIElement] = []

        func add(_ element: AXUIElement?) {
            guard let element else { return }
            guard !candidates.contains(where: { CFEqual($0, element) }) else { return }
            candidates.append(element)
        }

        add(copyElement(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute))
        if let pid = target.app?.processIdentifier {
            add(copyElement(AXUIElementCreateApplication(pid), kAXFocusedUIElementAttribute))
        }
        add(target.focusedElement)

        return candidates
    }

    /// The selection sliced out of the element's whole value, for apps that
    /// publish a range but not the selected text itself.
    private func slicedSelection(from element: AXUIElement) -> String? {
        guard let whole = copyString(element, kAXValueAttribute),
              let range = copyRange(element, kAXSelectedTextRangeAttribute),
              range.length > 0
        else { return nil }

        // The range comes from another process and is in UTF-16 units, so it is
        // clamped rather than trusted — a stale one would crash the substring.
        let text = whole as NSString
        let location = min(max(0, range.location), text.length)
        let length = min(range.length, text.length - location)
        guard length > 0 else { return nil }
        return text.substring(with: NSRange(location: location, length: length))
    }

    // MARK: AX reading helpers

    private func copyString(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success
        else { return nil }
        return value as? String
    }

    private func copyRange(_ element: AXUIElement, _ attribute: String) -> NSRange? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value
        else { return nil }
        var range = CFRange()
        guard AXValueGetValue(unsafeBitCast(value, to: AXValue.self), .cfRange, &range)
        else { return nil }
        return NSRange(location: range.location, length: range.length)
    }

    private func copyElement(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value
        else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    /// Why no selection could be read, in the terms needed to act on it: which
    /// app, what each candidate element claims to be, and which of the relevant
    /// attributes it actually advertises. Without this the failure is
    /// indistinguishable from the user genuinely not having selected anything.
    private func logSelectionDiagnostics(for target: Target) {
        let app = target.app?.localizedName ?? "unknown"
        let candidates = selectionCandidates(for: target)
        guard !candidates.isEmpty else {
            log.info("No selection in \(app, privacy: .public): no focused element at all.")
            return
        }
        for (index, element) in candidates.enumerated() {
            var names: CFArray?
            AXUIElementCopyAttributeNames(element, &names)
            let attributes = (names as? [String]) ?? []
            let role = copyString(element, kAXRoleAttribute) ?? "none"
            log.info("""
            No selection in \(app, privacy: .public) [candidate \(index)]: \
            role=\(role, privacy: .public) \
            selectedText=\(attributes.contains(kAXSelectedTextAttribute)) \
            value=\(attributes.contains(kAXValueAttribute)) \
            range=\(attributes.contains(kAXSelectedTextRangeAttribute)) \
            all=[\(attributes.joined(separator: ","), privacy: .public)]
            """)
        }
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
    /// so we check whether the caret actually moved.
    ///
    /// The order of the checks is the load-bearing part. Everything that can
    /// answer "don't use this path" has to run *before* the write, because once
    /// the text is in the field, returning false no longer means "nothing
    /// happened" — the caller reads it as "fall back to paste" and the dictation
    /// lands twice.
    private func insertViaAccessibility(_ text: String, target: Target) -> Bool {
        guard let element = focusedElement(for: target) else { return false }

        // Verifiability is settled before anything is written. An element that
        // won't report a caret position gives no way to tell a real insertion
        // from the silent no-op above, and after the write that question can no
        // longer be answered by pasting — so an element we can't check is handed
        // to the paste path untouched.
        var rangeBefore: AnyObject?
        guard AXUIElementCopyAttributeValue(
            element, kAXSelectedTextRangeAttribute as CFString, &rangeBefore
        ) == .success, let rangeBefore else { return false }

        let status = AXUIElementSetAttributeValue(
            element, kAXSelectedTextAttribute as CFString, text as CFTypeRef
        )
        guard status == .success else { return false }

        // Past here the text is in the field, so failing to *confirm* it is
        // reported as success. The two failures are not symmetric: text that
        // never arrived is visible and the user can dictate again, while text
        // inserted twice corrupts the document quietly.
        var rangeAfter: AnyObject?
        guard AXUIElementCopyAttributeValue(
            element, kAXSelectedTextRangeAttribute as CFString, &rangeAfter
        ) == .success, let rangeAfter else { return true }

        var before = CFRange(), after = CFRange()
        guard AXValueGetValue(unsafeBitCast(rangeBefore, to: AXValue.self), .cfRange, &before),
              AXValueGetValue(unsafeBitCast(rangeAfter, to: AXValue.self), .cfRange, &after)
        else { return true }

        // The caret should have advanced by the length of what we inserted.
        return after.location > before.location
    }

    /// Reads the selection by copying it, for apps the Accessibility tree can't
    /// answer for.
    ///
    /// Electron and Chromium apps do not build an accessibility tree until they
    /// detect an assistive client, so in those `AXFocusedUIElement` returns
    /// nothing at all — there is no attribute to ask for differently. The usual
    /// remedy is to set `AXManualAccessibility` on the target app and force the
    /// tree into existence, but that imposes a permanent cost on someone else's
    /// process to serve a feature they may use once, and it cannot be undone.
    /// Copying asks the app in its own terms instead: any app that supports ⌘C
    /// can answer, which is all of them.
    ///
    /// The clipboard is snapshotted and restored exactly as the paste path does.
    func selectedTextByCopying() async -> String? {
        let pasteboard = NSPasteboard.general
        let saved = snapshotPasteboard(pasteboard)

        // Clearing first is what makes "nothing was selected" distinguishable
        // from "the copy hasn't landed yet". Without it a ⌘C that copied nothing
        // leaves the previous clipboard in place, and we would hand the user's
        // last copied text to the model as though they had selected it.
        let cleared = pasteboard.clearContents()

        postCommand(CGKeyCode(kVK_ANSI_C))

        // Polled rather than slept once, so a fast app doesn't wait out a slow
        // one's worst case. The ceiling is short because this sits between the
        // user pressing the key and being able to speak.
        var copied: String?
        for _ in 0..<20 {
            try? await Task.sleep(for: .milliseconds(15))
            guard pasteboard.changeCount != cleared else { continue }
            copied = pasteboard.string(forType: .string)
            break
        }

        restorePasteboard(pasteboard, from: saved)

        guard let copied, !copied.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return copied
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

        postCommand(CGKeyCode(kVK_ANSI_V))

        // The paste is asynchronous in the target app, so the clipboard has to
        // survive long enough for it to be read.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            self.restorePasteboard(pasteboard, from: saved)
        }
    }

    private func postCommand(_ key: CGKeyCode) {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }

        // Suppress the local keyboard's own state while we synthesise, so a
        // physically-held key can't combine with what we post.
        source.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )

        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)

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
