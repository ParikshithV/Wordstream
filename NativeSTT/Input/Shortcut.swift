//
//  Shortcut.swift
//  NativeSTT
//

import Foundation
import CoreGraphics
import Carbon.HIToolbox

/// A physical modifier key, identified by its own key code rather than by the
/// generic modifier flag it sets.
///
/// This distinction is the whole reason the type exists. macOS reports both Option
/// keys as `.maskAlternate`, so a flag test alone cannot tell left from right — and
/// worse, if you hold left Option and then tap right Option, the generic flag never
/// clears, so a naive implementation reads the right-Option release as a second
/// press and the dictation never stops.
///
/// The device-dependent bits in the low byte of `CGEventFlags` do distinguish them,
/// so each key carries its own mask and presses are resolved against that.
enum ModifierKey: String, Codable, CaseIterable, Hashable, Sendable {
    case leftCommand, rightCommand
    case leftShift, rightShift
    case leftOption, rightOption
    case leftControl, rightControl
    case fn

    var keyCode: Int64 {
        switch self {
        case .leftCommand: 55
        case .rightCommand: 54
        case .leftShift: 56
        case .rightShift: 60
        case .leftOption: 58
        case .rightOption: 61
        case .leftControl: 59
        case .rightControl: 62
        case .fn: 63
        }
    }

    /// Device-dependent flag bits (`NX_DEVICE*KEYMASK`). Fn has no side, so it
    /// falls back to the generic secondary-fn mask.
    var deviceMask: UInt64 {
        switch self {
        case .leftControl: 0x0000_0001
        case .leftShift: 0x0000_0002
        case .rightShift: 0x0000_0004
        case .leftCommand: 0x0000_0008
        case .rightCommand: 0x0000_0010
        case .leftOption: 0x0000_0020
        case .rightOption: 0x0000_0040
        case .rightControl: 0x0000_2000
        case .fn: UInt64(CGEventFlags.maskSecondaryFn.rawValue)
        }
    }

    var displayName: String {
        switch self {
        case .leftCommand: "Left ⌘"
        case .rightCommand: "Right ⌘"
        case .leftShift: "Left ⇧"
        case .rightShift: "Right ⇧"
        case .leftOption: "Left ⌥"
        case .rightOption: "Right ⌥"
        case .leftControl: "Left ⌃"
        case .rightControl: "Right ⌃"
        case .fn: "Fn / 🌐"
        }
    }

    /// The Fn key is the one binding that needs the user to change a system
    /// setting, because macOS keeps its own handler on it regardless of ours.
    var systemConflictNote: String? {
        switch self {
        case .fn:
            "macOS also uses 🌐 for the emoji picker or its own dictation. Set System Settings → Keyboard → \"Press 🌐 to\" to \"Do Nothing\" so it doesn't fire alongside NativeSTT."
        case .leftCommand, .rightCommand:
            "Command is used in almost every app shortcut. Holding it to dictate will interfere with ⌘C, ⌘V and friends."
        default:
            nil
        }
    }
}

/// Either a modifier held down on its own, or a conventional key chord.
enum Shortcut: Codable, Equatable, Hashable, Sendable {
    /// Hold the key to dictate, release to stop. The default interaction.
    case modifierHold(ModifierKey)
    /// A conventional chord such as ⌃⌥D. Consumed rather than passed through.
    case chord(keyCode: Int64, modifiers: UInt64)

    static let rightOption = Shortcut.modifierHold(.rightOption)

    var displayName: String {
        switch self {
        case let .modifierHold(key):
            "Hold \(key.displayName)"
        case let .chord(keyCode, modifiers):
            Shortcut.describeChord(keyCode: keyCode, modifiers: modifiers)
        }
    }

    var conflictNote: String? {
        switch self {
        case let .modifierHold(key): key.systemConflictNote
        case .chord: nil
        }
    }

    private static func describeChord(keyCode: Int64, modifiers: UInt64) -> String {
        var parts = ""
        let flags = CGEventFlags(rawValue: modifiers)
        if flags.contains(.maskControl) { parts += "⌃" }
        if flags.contains(.maskAlternate) { parts += "⌥" }
        if flags.contains(.maskShift) { parts += "⇧" }
        if flags.contains(.maskCommand) { parts += "⌘" }
        return parts + (keyName(for: keyCode) ?? "Key \(keyCode)")
    }

    static func keyName(for keyCode: Int64) -> String? {
        switch Int(keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "Return"
        case kVK_Escape: return "Escape"
        case kVK_Tab: return "Tab"
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_Z: return "Z"
        default: break
        }

        // Ask the active keyboard layout rather than hard-coding a table, so the
        // label matches what is physically printed on the user's keyboard.
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data

        var deadKeyState: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)

        let status = data.withUnsafeBytes { raw -> OSStatus in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else {
                return OSStatus(paramErr)
            }
            return UCKeyTranslate(
                layout,
                UInt16(keyCode),
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                chars.count,
                &length,
                &chars
            )
        }

        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }
}
