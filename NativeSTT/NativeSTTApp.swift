//
//  NativeSTTApp.swift
//  NativeSTT
//

import SwiftUI
import SwiftData
import AppKit

@main
struct NativeSTTApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.colorScheme) private var colorScheme

    @State private var prefs = Preferences.shared

    /// The coordinator and container are created once, before any scene, and
    /// shared with the delegate — which needs them to install the overlay panel
    /// and start the event tap at launch, well before a window exists.
    private var coordinator: DictationCoordinator { AppState.shared.coordinator }
    private var container: ModelContainer { AppState.shared.container }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(coordinator: coordinator)
                .environment(\.theme, theme)
                .modelContainer(container)
        } label: {
            // A template image, so macOS tints it correctly for light, dark and
            // tinted menu bars.
            Image(nsImage: .gatewayMenuBarIcon())
        }
        .menuBarExtraStyle(.window)

        Window("NativeSTT Settings", id: "settings") {
            SettingsView(coordinator: coordinator)
                .environment(\.theme, theme)
                .modelContainer(container)
        }
        .defaultSize(width: 900, height: 620)

        Window("Dictation History", id: "history") {
            HistoryView()
                .environment(\.theme, theme)
                .modelContainer(container)
        }
        .defaultSize(width: 720, height: 560)
    }

    private var theme: Theme {
        prefs.theme(systemIsDark: colorScheme == .dark)
    }
}

/// Shared, launch-time state.
///
/// SwiftUI creates scenes lazily, but the event tap, the overlay panel and the
/// model load all have to be running before the user's first keypress — which
/// may well come before any window has ever opened. So these live here rather
/// than in a `@State` on the `App`.
@MainActor
final class AppState {
    static let shared = AppState()

    let coordinator = DictationCoordinator()
    let container: ModelContainer

    private init() {
        let schema = Schema([Transcript.self, DictionaryEntry.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            container = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }
}
