//
//  AppReset.swift
//  Wordstream
//

import AppKit
import Foundation
import ServiceManagement
import SwiftData
import os

/// Puts Wordstream back to the state it was in before it was ever run.
///
/// The app writes to four places, and nothing else knows about all four: settings
/// go to `UserDefaults`, dictations and dictionary terms to a SwiftData store, API
/// keys to the Keychain, and model weights to two folders on disk — one this app
/// owns, one shared with every other Hugging Face client on the Mac. A user who
/// wants to start over cannot reasonably be asked to find those themselves, and
/// deleting the app leaves all four behind.
///
/// Order matters here. Live state is torn down before the data under it goes away
/// — otherwise the engine holds a model whose files have been deleted and the menu
/// bar holds a `Transcript` that no longer exists — and preferences are written
/// before the app quits.
///
/// It ends by quitting rather than by reopening the welcome screen in place. A
/// reset leaves a running process holding an event tap for a shortcut that no
/// longer applies, an unloaded engine, and windows describing settings that are
/// gone; relaunching is what actually returns the app to first run, and the launch
/// path already does the whole of it — welcome screen, model prefetch, permission
/// checks — rather than an in-session imitation of it.
///
/// What this deliberately cannot do is give back the three system permissions.
/// Microphone, Accessibility and Input Monitoring are TCC grants: only the user can
/// revoke them, in System Settings. `Scope.summary` says so rather than letting
/// "resets everything" quietly overpromise.
@MainActor
enum AppReset {
    private static let log = Logger(subsystem: "app.wordstream", category: "reset")

    /// How much to remove.
    ///
    /// Downloaded weights are separated out because they are the one part of a
    /// reset that costs something real to undo: a gigabyte or more over the
    /// network before the app can transcribe again. Everything else is recreated
    /// instantly.
    enum Scope: String, CaseIterable, Identifiable {
        /// Settings, history, dictionary and API keys. Models stay on disk.
        case settingsAndData
        /// The above, plus every downloaded speech and cleanup model.
        case everything

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .settingsAndData: "Settings and data"
            case .everything: "Everything, including models"
            }
        }

        var summary: String {
            switch self {
            case .settingsAndData:
                "Settings, dictation history, dictionary terms, saved API keys and the login item. Downloaded models stay, so dictation works again as soon as you finish setup."
            case .everything:
                "Everything above, plus the speech and cleanup models on disk — a gigabyte or more to download again. macOS permissions aren\u{2019}t included either way; those can only be withdrawn in System Settings."
            }
        }

        var deletesModels: Bool { self == .everything }
    }

    /// Wipes the app back to first run and quits.
    ///
    /// Every step is best-effort and independent: a Keychain item that refuses to
    /// delete, or a model folder that is already gone, must not leave the rest of
    /// the reset half-done.
    static func perform(
        _ scope: Scope,
        coordinator: DictationCoordinator,
        container: ModelContainer
    ) async {
        log.info("Resetting: \(scope.rawValue, privacy: .public)")

        // 1. Live state first. Unloading the speech model here also covers the
        //    case where its files are about to be deleted underneath it.
        coordinator.forgetLastTranscript()
        await coordinator.engine.unload()

        // 2. Stored dictations and dictionary terms.
        clearStore(container)

        // 3. API keys — every provider, not just the selected one, since a key
        //    for the other provider is just as much the user's credential.
        for provider in CloudEnhancer.Provider.allCases {
            Keychain.set(nil, for: provider.keychainAccount)
        }

        // 4. Weights, if asked for.
        if scope.deletesModels {
            await coordinator.engine.deleteAllDownloads()
            await MLXEnhancer.deleteDownloadedModels()
        }

        // 5. The login item, which lives in launchd rather than in preferences
        //    and so would otherwise survive. The async overload is the one that
        //    waits for the daemon to actually drop the registration, which is
        //    what we want before the welcome screen offers to add it back.
        try? await SMAppService.mainApp.unregister()

        // 6. Preferences, including `hasCompletedOnboarding` — which is what makes
        //    the next launch open the welcome screen. `applyShortcuts` keeps the
        //    running process coherent in case termination is refused below.
        Preferences.shared.reset()
        coordinator.applyShortcuts()

        log.info("Reset complete; quitting")

        // 7. Quit. Forced explicitly rather than trusting AppKit's own flush on
        //    the way out: everything above is worthless if the defaults written a
        //    moment ago don't survive the process, and this is the one code path
        //    where losing them brings the app back with exactly the settings the
        //    user asked to be rid of.
        UserDefaults.standard.synchronize()
        NSApp.terminate(nil)
    }

    /// Empties both models out of the SwiftData store.
    ///
    /// Object by object rather than `delete(model:)`. The typed batch delete is
    /// the faster call and the obvious one to reach for, but it does not reliably
    /// tell an open `@Query` that its rows are gone — and the History window and
    /// the Dictionary tab are both `@Query`s that may well be on screen when this
    /// runs, so the cheaper call is the one that leaves deleted transcripts
    /// visibly listed. Deleting through the context is what those views observe.
    /// A personal dictation history is thousands of small objects at the very
    /// most; this is not the expensive part of a reset.
    private static func clearStore(_ container: ModelContainer) {
        let context = container.mainContext
        do {
            for transcript in try context.fetch(FetchDescriptor<Transcript>()) {
                context.delete(transcript)
            }
            for entry in try context.fetch(FetchDescriptor<DictionaryEntry>()) {
                context.delete(entry)
            }
            try context.save()
        } catch {
            log.error("Couldn't empty the store: \(error.localizedDescription, privacy: .public)")
        }
    }
}
