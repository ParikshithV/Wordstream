//
//  OverlayPanel.swift
//  Wordstream
//

import AppKit
import SwiftUI

/// The floating pill shown while dictating.
///
/// **The two `canBecome*` overrides are the whole ballgame.** If this panel takes
/// key focus, the text field the user was typing into loses its insertion point,
/// and the paste at the end lands nowhere — the single most common way a
/// dictation overlay breaks. `.nonactivatingPanel` alone is not enough; the
/// overrides are what actually guarantee it.
final class OverlayPanel: NSPanel {
    init(content: NSView) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 64),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .statusBar
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false // Liquid Glass draws the system shadow
        ignoresMouseEvents = true
        isMovable = false
        contentView = content
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Owns the panel's lifecycle and placement.
@MainActor
final class OverlayController {
    private var panel: OverlayPanel?
    private var hosting: NSHostingView<AnyView>?
    private var glass: NSGlassEffectView?

    func install(content: some View) {
        let hosting = NSHostingView(rootView: AnyView(content))

        // Apple's Liquid Glass for a floating HUD: regular (text must stay
        // legible) and pill corners. The panel ignores the mouse, so the
        // default non-interactive glass is the right variant.
        let glass = NSGlassEffectView(frame: NSRect(x: 0, y: 0, width: 380, height: 64))
        glass.style = .regular
        glass.cornerRadius = 32
        glass.contentView = hosting

        let panel = OverlayPanel(content: glass)
        self.hosting = hosting
        self.glass = glass
        self.panel = panel

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reposition() }
        }
    }

    func show() {
        guard let panel else { return }
        reposition()
        // orderFrontRegardless, not makeKeyAndOrderFront — the panel must appear
        // without the app activating and pulling focus off the target field.
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    /// Bottom-centre of whichever screen the pointer is on, so on a multi-display
    /// setup it appears where the user is actually working.
    private func reposition() {
        guard let panel else { return }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }

        let size = panel.frame.size
        panel.setFrameOrigin(
            NSPoint(
                x: frame.midX - size.width / 2,
                y: frame.minY + 120
            )
        )
    }

    /// Grows the panel when the live preview needs more than one line.
    func resize(height: CGFloat) {
        guard let panel, let hosting else { return }
        let clamped = max(64, min(160, height))
        guard abs(panel.frame.height - clamped) > 1 else { return }
        var frame = panel.frame
        frame.origin.y -= clamped - frame.height
        frame.size.height = clamped
        panel.setFrame(frame, display: true)
        glass?.frame = NSRect(x: 0, y: 0, width: frame.width, height: clamped)
        glass?.cornerRadius = clamped / 2
        hosting.frame = NSRect(x: 0, y: 0, width: frame.width, height: clamped)
    }
}
