//
//  AppDelegate.swift
//  NativeSTT
//

import AppKit
import SwiftUI
import SwiftData
import os

/// Owns the pieces that don't fit the SwiftUI scene model: font registration, the
/// non-activating overlay panel, the event tap's lifecycle, and the first-run
/// window.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let log = Logger(subsystem: "app.nativestt", category: "app")
    private let overlay = OverlayController()
    private var onboardingWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // LSUIElement already keeps us out of the Dock; setting it explicitly
        // also covers running a build that somehow lacks the Info.plist key.
        NSApp.setActivationPolicy(.accessory)

        let missingFaces = FontRegistrar.registerBundledFonts()
        if !missingFaces.isEmpty {
            log.error("Design system fonts missing: \(missingFaces.joined(separator: ", "), privacy: .public)")
        }

        let coordinator = AppState.shared.coordinator

        overlay.install(
            content: OverlayView(coordinator: coordinator)
                .environment(\.theme, Preferences.shared.theme(systemIsDark: isSystemDark))
        )

        coordinator.configure(
            modelContext: AppState.shared.container.mainContext,
            overlay: overlay
        )

        // Attempt the tap as soon as Accessibility is trusted, rather than
        // waiting for all three permissions.
        //
        // Creating the tap is itself what registers this app under Input
        // Monitoring in System Settings — so gating it on Input Monitoring
        // already being granted is a deadlock: the app never appears in the
        // list the user is being asked to switch it on in.
        if coordinator.permissions.accessibility.isGranted {
            coordinator.startMonitoring()
        }

        Task { await coordinator.prepareModel() }

        if !Preferences.shared.hasCompletedOnboarding {
            showOnboarding(coordinator: coordinator)
        }
    }

    /// A menu-bar app outlives its windows.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: Onboarding

    /// Built as a plain `NSWindow` rather than a SwiftUI `Window` scene, because
    /// the delegate has no access to `openWindow` and first-run has to appear
    /// without the user going looking for it.
    private func showOnboarding(coordinator: DictationCoordinator) {
        let view = OnboardingView(coordinator: coordinator) { [weak self] in
            self?.onboardingWindow?.close()
            self?.onboardingWindow = nil
        }
        .environment(\.theme, Preferences.shared.theme(systemIsDark: isSystemDark))
        .modelContainer(AppState.shared.container)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 620),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to NativeSTT"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view)
        window.center()

        onboardingWindow = window

        // The one moment an accessory app should come forward on its own —
        // otherwise first run opens behind everything and looks like nothing
        // happened.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private var isSystemDark: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
}
