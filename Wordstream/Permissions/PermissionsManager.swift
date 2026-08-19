//
//  PermissionsManager.swift
//  Wordstream
//

import AppKit
import AVFoundation
import AVFAudio
import ApplicationServices
import IOKit.hid
import Observation
import os

/// The three grants this app cannot work without, and the state of each.
///
/// All three are checked rather than assumed, because each fails differently and
/// silently: without Microphone you record silence, without Accessibility the
/// event tap refuses to install, and without Input Monitoring the tap installs
/// but never delivers a key.
@Observable
@MainActor
final class PermissionsManager {
    enum Status: Equatable {
        case granted
        case denied
        case notDetermined

        var isGranted: Bool { self == .granted }
    }

    private(set) var microphone: Status = .notDetermined
    private(set) var accessibility: Status = .notDetermined
    private(set) var inputMonitoring: Status = .notDetermined

    var allGranted: Bool {
        microphone.isGranted && accessibility.isGranted && inputMonitoring.isGranted
    }

    init() {
        refresh()
    }

    private let log = Logger(subsystem: "app.wordstream", category: "permissions")

    func refresh() {
        // Read both microphone surfaces and take the more permissive answer.
        //
        // `AVCaptureDevice` is the documented macOS authorization API;
        // `AVAudioApplication` is the newer audio-session one that matches how
        // this app records. They can disagree, and reporting "denied" while the
        // other says "granted" would block a user who is in fact allowed to
        // record — so a grant on either counts, and only a genuine denial on
        // the capture surface is treated as denied.
        let capture = AVCaptureDevice.authorizationStatus(for: .audio)
        let audioApp = AVAudioApplication.shared.recordPermission

        if capture == .authorized || audioApp == .granted {
            microphone = .granted
        } else if capture == .notDetermined || audioApp == .undetermined {
            microphone = .notDetermined
        } else {
            microphone = .denied
        }

        accessibility = AXIsProcessTrusted() ? .granted : .denied

        inputMonitoring = switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
        case kIOHIDAccessTypeGranted: .granted
        case kIOHIDAccessTypeUnknown: .notDetermined
        default: .denied
        }
    }

    // MARK: Requests

    enum Kind {
        case microphone, accessibility, inputMonitoring
    }

    /// Asks for a permission for real.
    ///
    /// **This must run before the settings pane is any use.** macOS does not list
    /// an app under Microphone or Input Monitoring until the app has actually
    /// requested that permission at least once — so sending someone straight to
    /// System Settings shows them an empty list with nothing to switch on. Every
    /// path in the UI therefore requests first and only offers the pane
    /// afterwards, for the case where the answer was already "no".
    func request(_ kind: Kind) async {
        // Ask the system what it already knows before asking the user anything.
        //
        // A grant can arrive without this app being involved: a previous
        // install, a switch flipped in System Settings while this window sat
        // open, a management profile. Re-reading first means an
        // already-granted permission never enters the request path at all —
        // which for the microphone matters beyond tidiness, since that path
        // flips the activation policy and steals focus to host a prompt macOS
        // was never going to show.
        refresh()
        guard !status(kind).isGranted else { return }

        switch kind {
        case .microphone:
            logMicrophoneDiagnostics("before")

            // Become a regular app for the duration of the prompt.
            //
            // `LSUIElement` keeps Wordstream out of the Dock, which is right for
            // a menu-bar app — but an accessory process is not eligible to own
            // a TCC alert, so the microphone request is auto-denied in
            // milliseconds without anything ever being shown. That is exactly
            // the symptom this hit: undetermined → denied in 15ms, no dialog,
            // and no entry in System Settings to switch on.
            //
            // Accessibility and Input Monitoring are unaffected because they
            // prompt through a different mechanism, which is why those two
            // worked while this one silently failed.
            let previousPolicy = NSApp.activationPolicy()
            if previousPolicy != .regular {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
            }
            defer {
                if previousPolicy != .regular {
                    NSApp.setActivationPolicy(previousPolicy)
                }
            }

            // Ask on *both* surfaces. `AVCaptureDevice` is the documented macOS
            // microphone-authorization API; `AVAudioApplication` is the newer
            // audio-session one that matches how this app actually records.
            // They can disagree, and asking on only one has already cost two
            // rounds of this bug, so ask on both and let whichever is
            // authoritative here do the work.
            let captureGranted = await AVCaptureDevice.requestAccess(for: .audio)
            let audioAppGranted = await AVAudioApplication.requestRecordPermission()
            log.info("mic[request] capture=\(captureGranted) audioApp=\(audioAppGranted)")

            // If neither prompt produced a grant, touch the hardware — that is
            // what forces the TCC entry to exist, so the app is at least listed
            // in System Settings rather than absent from a pane the user is
            // being told to visit.
            if !captureGranted, !audioAppGranted { nudgeAudioInput() }

            logMicrophoneDiagnostics("after")

        case .accessibility:
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            _ = AXIsProcessTrustedWithOptions(options as CFDictionary)

        case .inputMonitoring:
            _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        }
        refresh()
    }

    /// Opens and immediately tears down a capture session on the default audio
    /// device, purely to make the TCC entry exist. Nothing is recorded or kept.
    ///
    /// An earlier version used `AVAudioEngine` and guarded on
    /// `inputFormat(forBus:).sampleRate > 0` — which is precisely wrong, because
    /// with no permission yet that sample rate *is* zero, so it returned before
    /// touching the hardware and the nudge never happened. Opening a capture
    /// session is the path macOS actually keys the microphone entry off.
    private func nudgeAudioInput() {
        guard let device = AVCaptureDevice.default(for: .audio) else {
            log.error("No default audio input device found.")
            return
        }
        let session = AVCaptureSession()
        guard let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input)
        else {
            log.info("Could not build an audio capture input — usually means the grant is still pending.")
            return
        }
        session.addInput(input)
        session.startRunning()
        session.stopRunning()
    }

    /// Both authorization APIs, side by side.
    ///
    /// They are genuinely different permissions surfaces and can disagree, so
    /// when the microphone misbehaves the first useful question is which one is
    /// saying what.
    private func logMicrophoneDiagnostics(_ label: String) {
        let capture = AVCaptureDevice.authorizationStatus(for: .audio).rawValue
        let audioApp = AVAudioApplication.shared.recordPermission.rawValue
        let hasDevice = AVCaptureDevice.default(for: .audio) != nil
        let usage = Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") != nil
        log.info("""
        mic[\(label, privacy: .public)] \
        AVCaptureDevice=\(capture) AVAudioApplication=\(audioApp) \
        defaultDevice=\(hasDevice) usageString=\(usage)
        """)
    }

    /// Whether macOS has already put this question to the user — the
    /// difference between "Allow" being able to do something and it being a
    /// dead button, because the system prompts exactly once.
    ///
    /// `.denied` only carries that meaning for the two APIs that report
    /// `.notDetermined` before the first request. Accessibility has no such
    /// state: `AXIsProcessTrusted()` is a bool, and an app that has never asked
    /// is indistinguishable from one that was refused. So it answers false and
    /// the UI falls back to remembering its own request.
    func hasBeenPrompted(_ kind: Kind) -> Bool {
        switch kind {
        case .microphone, .inputMonitoring: status(kind) == .denied
        case .accessibility: false
        }
    }

    func status(_ kind: Kind) -> Status {
        switch kind {
        case .microphone: microphone
        case .accessibility: accessibility
        case .inputMonitoring: inputMonitoring
        }
    }

    func pane(for kind: Kind) -> Pane {
        switch kind {
        case .microphone: .microphone
        case .accessibility: .accessibility
        case .inputMonitoring: .inputMonitoring
        }
    }

    // MARK: Settings deep links

    enum Pane: String {
        case microphone = "Privacy_Microphone"
        case accessibility = "Privacy_Accessibility"
        case inputMonitoring = "Privacy_ListenEvent"
    }

    func openSettings(_ pane: Pane) {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane.rawValue)")!
        NSWorkspace.shared.open(url)
    }

    /// Refreshes whenever the app comes forward, so returning from System
    /// Settings updates the UI without the user having to hunt for a refresh
    /// button. macOS sends no notification when a TCC grant changes.
    func observeActivation() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }
}
