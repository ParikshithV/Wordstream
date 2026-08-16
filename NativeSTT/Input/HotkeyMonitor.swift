//
//  HotkeyMonitor.swift
//  NativeSTT
//

import AppKit
import CoreGraphics
import Carbon.HIToolbox
import os

/// Watches the whole system for the dictation key.
///
/// Three things here are load-bearing and easy to get wrong:
///
///  1. **The tap must pass events through.** It is created as a `.defaultTap` so it
///     *can* consume, but it only ever returns `nil` for an exact chord match.
///     Swallowing a bare modifier would break that key everywhere in macOS.
///
///  2. **macOS silently disables slow taps.** If the callback ever takes too long,
///     the system posts `.tapDisabledByTimeout` and stops delivering events — the
///     hotkey dies and never comes back. Re-enabling on that event is the fix, and
///     its absence is the classic "it worked until it didn't" bug in this category
///     of app.
///
///  3. **Presses are resolved from the physical key code plus the device-dependent
///     flag bit**, not the generic modifier mask. See `ModifierKey`.
///
/// The tap is attached to the main run loop, so the C callback lands on the main
/// thread and `MainActor.assumeIsolated` is genuinely safe rather than a wish.
@MainActor
final class HotkeyMonitor {
    private let log = Logger(subsystem: "app.nativestt", category: "hotkey")

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private var dictationShortcut: Shortcut = .rightOption
    private var commandShortcut: Shortcut?

    private var isDictationKeyDown = false
    private var lastPressAt: Date?
    private var handsFreeEnabled = true

    /// Set while a hands-free session is running, so the same key stops it.
    private(set) var isHandsFreeActive = false

    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    var onCancel: (() -> Void)?
    var onCommandMode: (() -> Void)?
    /// Fired when the tap is disabled and cannot be recovered — the UI needs to
    /// tell the user rather than appear to work.
    var onTapInvalidated: (() -> Void)?

    var isRunning: Bool { tap != nil }

    // MARK: Lifecycle

    func configure(dictation: Shortcut, commandMode: Shortcut?, handsFreeOnDoubleTap: Bool) {
        dictationShortcut = dictation
        commandShortcut = commandMode
        handsFreeEnabled = handsFreeOnDoubleTap
        // A modifier that is currently held under the old binding must not leak
        // into the new one.
        isDictationKeyDown = false
    }

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        guard AXIsProcessTrusted() else {
            log.error("Cannot install event tap: Accessibility permission not granted.")
            return false
        }

        let mask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: hotkeyTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            log.error("CGEvent.tapCreate returned nil.")
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.tap = tap
        self.runLoopSource = source
        log.info("Event tap installed.")
        return true
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        isDictationKeyDown = false
    }

    /// Re-installs the tap. Used after the user grants Accessibility, since the tap
    /// cannot be created before that.
    func restart() {
        stop()
        start()
    }

    func handsFreeDidStop() {
        isHandsFreeActive = false
    }

    // MARK: Event handling

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // Not optional. Without this the hotkey stops working permanently the
            // first time anything stalls the callback.
            if let tap {
                log.warning("Event tap disabled (\(String(describing: type))); re-enabling.")
                CGEvent.tapEnable(tap: tap, enable: true)
            } else {
                onTapInvalidated?()
            }
            return false

        case .flagsChanged:
            handleFlagsChanged(event)
            return false

        case .keyDown:
            return handleKeyDown(event)

        default:
            return false
        }
    }

    private func handleFlagsChanged(_ event: CGEvent) {
        guard case let .modifierHold(key) = dictationShortcut else { return }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard keyCode == key.keyCode else { return }

        let isDown = (event.flags.rawValue & key.deviceMask) != 0

        if isDown, !isDictationKeyDown {
            isDictationKeyDown = true
            handlePress()
        } else if !isDown, isDictationKeyDown {
            isDictationKeyDown = false
            handleRelease()
        }
    }

    private func handlePress() {
        let now = Date()

        if handsFreeEnabled, let last = lastPressAt, now.timeIntervalSince(last) < 0.4 {
            lastPressAt = nil
            if isHandsFreeActive {
                isHandsFreeActive = false
                onRelease?()
            } else {
                isHandsFreeActive = true
                onPress?()
            }
            return
        }

        lastPressAt = now
        if isHandsFreeActive { return }
        onPress?()
    }

    private func handleRelease() {
        // In hands-free the key is only a toggle, so a physical release means
        // nothing until the next double-tap.
        guard !isHandsFreeActive else { return }
        onRelease?()
    }

    /// Returns true when the event should be consumed.
    private func handleKeyDown(_ event: CGEvent) -> Bool {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        if keyCode == kVK_Escape {
            onCancel?()
            // Escape is passed through: the frontmost app may well want it too,
            // and cancelling dictation should not eat the user's keystroke.
            return false
        }

        let relevant: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
        let flags = event.flags.intersection(relevant).rawValue

        if case let .chord(code, modifiers) = dictationShortcut, keyCode == code, flags == modifiers {
            // A chord is a discrete trigger, so it toggles rather than holds.
            if isHandsFreeActive {
                isHandsFreeActive = false
                onRelease?()
            } else {
                isHandsFreeActive = true
                onPress?()
            }
            return true
        }

        if case let .chord(code, modifiers) = commandShortcut, keyCode == code, flags == modifiers {
            onCommandMode?()
            return true
        }

        return false
    }
}

/// C callback. Must be `nonisolated` to be usable as a function pointer; the tap is
/// attached to the main run loop, so hopping onto the main actor here is a fact
/// rather than an assumption.
private nonisolated func hotkeyTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()

    let consume = MainActor.assumeIsolated {
        monitor.handle(type: type, event: event)
    }
    return consume ? nil : Unmanaged.passUnretained(event)
}
