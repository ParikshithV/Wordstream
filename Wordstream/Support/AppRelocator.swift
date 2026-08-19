//
//  AppRelocator.swift
//  Wordstream
//

import AppKit
import Foundation
import os

/// Moves Wordstream into an Applications folder and relaunches it from there.
///
/// This exists because of how TCC identifies an app. Microphone, Accessibility
/// and Input Monitoring are granted to a bundle at a path; drag the bundle
/// somewhere else afterwards and macOS treats the copy as a stranger — the three
/// switches in System Settings still read as on, while the dictation key does
/// nothing. Someone who runs Wordstream out of their Downloads folder, grants
/// everything, and tidies up a week later has no way of connecting the two
/// events. Getting the app to its final home *before* onboarding asks for
/// anything is the only fix that doesn't rely on the user knowing this.
///
/// The whole thing is a file copy, a relaunch and a quit, which is what makes it
/// worth a button rather than a paragraph of instructions.
@MainActor
enum AppRelocator {
    private static let log = Logger(subsystem: "app.wordstream", category: "relocate")

    enum RelocationError: LocalizedError {
        case noWritableApplicationsFolder
        case copyFailed(String)
        case launchFailed(String)

        var errorDescription: String? {
            switch self {
            case .noWritableApplicationsFolder:
                "Neither /Applications nor your personal Applications folder can be written to."
            case let .copyFailed(reason):
                "The copy didn\u{2019}t finish: \(reason)"
            case let .launchFailed(reason):
                "The copy is in place, but reopening it failed: \(reason)"
            }
        }
    }

    // MARK: Where we are

    /// Whether this copy is already living where a permanent install lives.
    ///
    /// Both folders count: `/Applications` is the usual answer, and
    /// `~/Applications` is where a non-admin account installs. Either one is a
    /// stable path, which is the only property TCC cares about.
    static var isInstalled: Bool {
        let path = Bundle.main.bundleURL.resolvingSymlinksInPath().path
        return applicationsFolders.contains { path.hasPrefix($0.path + "/") }
    }

    /// Whether macOS is running this copy from a throwaway mirror of itself.
    ///
    /// Gatekeeper does this to a quarantined app opened straight out of a disk
    /// image or a download: the process runs from a read-only shadow under
    /// `/private/var/folders`, and the real bundle is somewhere we can't ask for
    /// — resolving it needs an SPI this app doesn't use. It changes two things.
    /// The original download can't be tidied away afterwards, and it's worth
    /// saying so rather than leaving a duplicate the user doesn't expect.
    static var isTranslocated: Bool {
        Bundle.main.bundleURL.path.contains("/AppTranslocation/")
    }

    /// Where the finished install will sit, for naming it before it exists.
    static var plannedDestination: URL? {
        writableApplicationsFolder?.appendingPathComponent(Bundle.main.bundleURL.lastPathComponent)
    }

    private static var applicationsFolders: [URL] {
        [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        ]
    }

    /// `/Applications` when this account may write there, the personal folder
    /// otherwise.
    ///
    /// Standard (non-admin) accounts can't write to `/Applications`, and for them
    /// `~/Applications` is a real install location rather than a consolation
    /// prize — stable path, same TCC identity, no password prompt. It is created
    /// if it doesn't exist yet, which on most Macs it won't.
    private static var writableApplicationsFolder: URL? {
        let fileManager = FileManager.default
        let shared = applicationsFolders[0]
        if fileManager.isWritableFile(atPath: shared.path) { return shared }

        let personal = applicationsFolders[1]
        if !fileManager.fileExists(atPath: personal.path) {
            try? fileManager.createDirectory(at: personal, withIntermediateDirectories: true)
        }
        return fileManager.isWritableFile(atPath: personal.path) ? personal : nil
    }

    /// Whether a different bundle is already sitting at the destination.
    ///
    /// Asked before anything is touched, so the caller can get permission to
    /// displace it instead of quietly overwriting someone's older install.
    static var destinationIsOccupied: Bool {
        guard let destination = plannedDestination else { return false }
        return FileManager.default.fileExists(atPath: destination.path)
    }

    // MARK: The move

    /// Copies this app into Applications, reopens it there and quits this copy.
    ///
    /// Ordered so that no step can lose the app. The copy lands first; the
    /// original is only trashed once a complete bundle exists at the
    /// destination; and this process is the last thing to go, after the
    /// replacement is confirmed on its way. A failure anywhere leaves a running
    /// app the user can carry on with.
    ///
    /// Callers must have settled `destinationIsOccupied` first — an existing
    /// bundle at the destination is moved to the Trash here without asking.
    static func moveToApplications() async throws {
        guard let folder = writableApplicationsFolder else {
            throw RelocationError.noWritableApplicationsFolder
        }

        let source = Bundle.main.bundleURL
        let destination = folder.appendingPathComponent(source.lastPathComponent)
        let fileManager = FileManager.default

        log.info("Relocating to \(destination.path, privacy: .public)")

        // An older install goes to the Trash rather than being deleted: this is
        // the one step that touches something the user already had, and it has
        // to be undoable.
        if fileManager.fileExists(atPath: destination.path) {
            try? await NSWorkspace.shared.recycle([destination])
        }

        do {
            try fileManager.copyItem(at: source, to: destination)
        } catch {
            throw RelocationError.copyFailed(error.localizedDescription)
        }

        // Copying preserves extended attributes, quarantine among them, and a
        // quarantined bundle is exactly what gets run from a read-only shadow
        // instead of its real path. Clearing the flag on the copy we just made
        // ourselves is the difference between this working once and the new
        // install being translocated in its turn.
        var writable = destination
        try? writable.setResourceValues({
            var values = URLResourceValues()
            values.quarantineProperties = nil
            return values
        }())

        // Tidy the copy that was just superseded — unless we're running from a
        // translocated mirror, in which case the real original is at a path this
        // process isn't allowed to know.
        if !isTranslocated {
            try? await NSWorkspace.shared.recycle([source])
        }

        // Relaunch from the new home. `createsNewApplicationInstance` is
        // required: without it macOS sees a running process with this bundle
        // identifier and simply activates the copy we are about to kill.
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        do {
            _ = try await NSWorkspace.shared.openApplication(at: destination, configuration: configuration)
        } catch {
            throw RelocationError.launchFailed(error.localizedDescription)
        }

        log.info("Relaunched from \(destination.path, privacy: .public); quitting this copy")
        NSApp.terminate(nil)
    }

    /// Opens the enclosing folder with this app selected, for anyone who would
    /// rather do the drag themselves — and the only thing left to offer when the
    /// copy fails.
    static func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }
}
