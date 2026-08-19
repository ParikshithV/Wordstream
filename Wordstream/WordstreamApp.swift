//
//  WordstreamApp.swift
//  Wordstream
//

import SwiftUI
import SwiftData
import AppKit

@main
struct WordstreamApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// The coordinator and container are created once, before any scene, and
    /// shared with the delegate — which needs them to install the overlay panel
    /// and start the event tap at launch, well before a window exists.
    private var coordinator: DictationCoordinator { AppState.shared.coordinator }
    private var container: ModelContainer { AppState.shared.container }

    var body: some Scene {
        MenuBarExtra {
            ThemedRoot(fillsBackground: true) {
                MenuBarContentView(coordinator: coordinator)
                    .modelContainer(container)
            }
        } label: {
            // A template image, so macOS tints it correctly for light, dark and
            // tinted menu bars.
            Image(nsImage: .gatewayMenuBarIcon())
        }
        .menuBarExtraStyle(.window)

        Window("Wordstream Settings", id: "settings") {
            ThemedRoot(fillsBackground: true) {
                SettingsView(coordinator: coordinator)
                    .modelContainer(container)
            }
        }
        .defaultSize(width: 900, height: 620)

        Window("Dictation History", id: "history") {
            ThemedRoot(fillsBackground: true) {
                HistoryView()
                    .modelContainer(container)
            }
        }
        .defaultSize(width: 720, height: 560)
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
