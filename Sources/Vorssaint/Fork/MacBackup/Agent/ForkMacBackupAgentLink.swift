// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import AppKit
import Foundation
import notify
import ServiceManagement

/// The app's side of the agent (plan §3.3, §3.4): registers it
/// (`SMAppService.agent` when the release bundle carries its plist, a plain
/// LaunchAgent in a Developer build), unregisters it when the feature is
/// switched off, and publishes whether it may run. When it may not (not
/// approved yet, registration failed), the app runs the same runner while it
/// is open (`mode == .appWhileOpen`), and the Settings say so
/// (`ForkMacBackupAgentStrings.appOnly`).
///
/// Main thread. Nothing is registered, written or bootstrapped while the
/// feature is off: the only system calls then are reads, and only for what
/// exists (a bundled plist, a LaunchAgent file left by a Developer build).
final class ForkMacBackupAgentLink: ObservableObject {
    static let shared = ForkMacBackupAgentLink()

    enum Mode: Equatable {
        case off
        /// The background agent backs up, app open or not.
        case agent
        /// The app backs up, only while it is open.
        case appWhileOpen
    }

    @Published private(set) var registration: ForkMacBackupAgentRegistration = .notRegistered
    @Published private(set) var mode: Mode = .off

    private let bundleID = Bundle.main.bundleIdentifier ?? "swishsaint"
    private let work = DispatchQueue(label: "fork.macbackup.link", qos: .utility)
    private var appRunner: ForkMacBackupRunner?
    private var meetingToken: Int32?
    private var meetingObserver: NSObjectProtocol?
    private var activationObserver: NSObjectProtocol?
    private var recheckTimer: Timer?
    private var syncing = false
    private var syncAgain = false

    /// At launch: a hold the updater left behind is over (this is the new build).
    static func start() {
        if let paths = ForkMacBackupPaths(container: PrivateFileStore.containerURL) {
            try? FileManager.default.removeItem(at: ForkMacBackupAgentIPCSupport.updateHoldURL(paths))
        }
        shared.sync()
    }

    /// The feature's switch moved.
    static func sync() {
        shared.sync()
    }

    private var isEnabled: Bool { UserDefaults.standard.bool(forKey: ForkDefaultsKey.macBackupEnabled) }

    func sync() {
        if isEnabled {
            startMeetingBridge()
            observeActivation()
        } else {
            stopMeetingBridge()
            stopObserving()
        }
        refresh()
    }

    /// System Settings › General › Login Items, where the agent is allowed.
    func openApprovalSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    // MARK: Registration

    /// Registers or unregisters off the main thread (both can block), then
    /// publishes and picks who backs up.
    private func refresh() {
        guard !syncing else {
            syncAgain = true
            return
        }
        syncing = true
        let enabled = isEnabled
        let bundleID = self.bundleID
        work.async { [weak self] in
            let registration = enabled ? Self.register(bundleID: bundleID) : Self.unregister(bundleID: bundleID)
            DispatchQueue.main.async {
                guard let self else { return }
                self.syncing = false
                if self.registration != registration { self.registration = registration }
                self.chooseMode(enabled: enabled)
                if self.syncAgain {
                    self.syncAgain = false
                    self.refresh()
                }
            }
        }
    }

    private static var bundledPlist: URL {
        ForkMacBackupAgentPlist.bundledURL(appURL: Bundle.main.bundleURL, bundleID: Bundle.main.bundleIdentifier ?? "")
    }

    private static func register(bundleID: String) -> ForkMacBackupAgentRegistration {
        if FileManager.default.fileExists(atPath: bundledPlist.path) {
            let service = SMAppService.agent(plistName: ForkMacBackupAgentPlist.fileName(bundleID: bundleID))
            if service.status == .notRegistered || service.status == .notFound {
                do {
                    try service.register()
                } catch {
                    return service.status == .requiresApproval ? .requiresApproval : .failed
                }
            }
            return map(service.status)
        }
        return registerLegacy(bundleID: bundleID)
    }

    private static func map(_ status: SMAppService.Status) -> ForkMacBackupAgentRegistration {
        switch status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notRegistered: return .notRegistered
        case .notFound: return .failed
        @unknown default: return .failed
        }
    }

    private static func unregister(bundleID: String) -> ForkMacBackupAgentRegistration {
        if FileManager.default.fileExists(atPath: bundledPlist.path) {
            let service = SMAppService.agent(plistName: ForkMacBackupAgentPlist.fileName(bundleID: bundleID))
            if service.status == .enabled || service.status == .requiresApproval {
                try? service.unregister()
            }
        }
        let legacy = ForkMacBackupAgentPlist.legacyURL(home: URL(fileURLWithPath: NSHomeDirectory()), bundleID: bundleID)
        if FileManager.default.fileExists(atPath: legacy.path) {
            _ = launchctl(["bootout", "gui/\(getuid())/\(ForkMacBackupAgentPlist.label(bundleID: bundleID))"])
            try? FileManager.default.removeItem(at: legacy)
        }
        return .notRegistered
    }

    /// A Developer build carries no plist: a classic LaunchAgent in
    /// `~/Library/LaunchAgents`, bootstrapped in the GUI domain.
    private static func registerLegacy(bundleID: String) -> ForkMacBackupAgentRegistration {
        guard let executable = Bundle.main.executableURL?.path else { return .failed }
        let url = ForkMacBackupAgentPlist.legacyURL(home: URL(fileURLWithPath: NSHomeDirectory()), bundleID: bundleID)
        let plist = ForkMacBackupAgentPlist.legacy(bundleID: bundleID, executablePath: executable)
        let label = ForkMacBackupAgentPlist.label(bundleID: bundleID)
        let current = (try? Data(contentsOf: url)).flatMap {
            try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any]
        }
        let domain = "gui/\(getuid())"
        let loaded = launchctl(["print", "\(domain)/\(label)"])
        if current.map({ ForkMacBackupAgentPlist.same($0, plist) }) != true {
            guard let data = ForkMacBackupAgentPlist.data(plist) else { return .failed }
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard (try? data.write(to: url, options: .atomic)) != nil else { return .failed }
            if loaded { _ = launchctl(["bootout", "\(domain)/\(label)"]) }
            return launchctl(["bootstrap", domain, url.path]) ? .developmentFallback : .failed
        }
        if loaded { return .developmentFallback }
        return launchctl(["bootstrap", domain, url.path]) ? .developmentFallback : .failed
    }

    @discardableResult
    private static func launchctl(_ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    // MARK: Who backs up

    /// The agent when it may run; else the app, while it is open.
    private func chooseMode(enabled: Bool) {
        guard enabled else {
            stopAppRunner()
            if mode != .off { mode = .off }
            return
        }
        switch registration {
        case .enabled, .developmentFallback:
            stopAppRunner()
            if mode != .agent { mode = .agent }
        case .notRegistered, .requiresApproval, .failed:
            startAppRunner()
        }
        scheduleRecheck()
    }

    private func startAppRunner() {
        guard appRunner == nil, let paths = ForkMacBackupPaths(container: PrivateFileStore.containerURL) else {
            if appRunner != nil, mode != .appWhileOpen { mode = .appWhileOpen }
            return
        }
        let runner = ForkMacBackupRunner(host: .app, paths: paths, bundleID: bundleID)
        runner.onHandedOver = { [weak self] in
            DispatchQueue.main.async {
                self?.appRunner = nil
                if self?.mode != .agent { self?.mode = .agent }
            }
        }
        switch runner.start() {
        case .started:
            appRunner = runner
            if mode != .appWhileOpen { mode = .appWhileOpen }
        case .held(role: .agent?, _):
            // An agent runs after all (its status lagged): it backs up.
            if mode != .agent { mode = .agent }
        case .held, .failed:
            if mode != .appWhileOpen { mode = .appWhileOpen }
        }
    }

    private func stopAppRunner() {
        guard let runner = appRunner else { return }
        appRunner = nil
        // Cancels cleanly (a checkpoint), so the agent resumes where it stopped.
        runner.shutdown(.agentQuit) {}
    }

    /// While the app backs up for want of the agent, look again every
    /// minute and when the app comes forward (approval granted meanwhile).
    private func scheduleRecheck() {
        recheckTimer?.invalidate()
        recheckTimer = nil
        guard isEnabled, mode != .agent else { return }
        let timer = Timer(timeInterval: 60, repeats: false) { [weak self] _ in self?.refresh() }
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        recheckTimer = timer
    }

    private func observeActivation() {
        guard activationObserver == nil else { return }
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, self.mode != .agent else { return }
            self.refresh()
        }
    }

    private func stopObserving() {
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
        activationObserver = nil
        recheckTimer?.invalidate()
        recheckTimer = nil
    }

    // MARK: Meeting bridge

    /// The meeting tally lives in this process; the agent reads it as the
    /// notify state of `<bundle>.macbackup.meeting` (1 busy, 0 not).
    private func startMeetingBridge() {
        guard meetingToken == nil else { return }
        let name = ForkMacBackupAgentIPCSupport.Names(bundleID: bundleID).meeting
        var token: Int32 = 0
        guard notify_register_check(name, &token) == UInt32(NOTIFY_STATUS_OK) else { return }
        meetingToken = token
        publishMeeting()
        meetingObserver = NotificationCenter.default.addObserver(
            forName: ForkMeetingActivity.didChange, object: nil, queue: .main
        ) { [weak self] _ in
            self?.publishMeeting()
        }
    }

    private func publishMeeting() {
        guard let meetingToken else { return }
        notify_set_state(meetingToken, ForkMeetingActivity.isBusy ? 1 : 0)
        notify_post(ForkMacBackupAgentIPCSupport.Names(bundleID: bundleID).meeting)
    }

    private func stopMeetingBridge() {
        if let meetingObserver { NotificationCenter.default.removeObserver(meetingObserver) }
        meetingObserver = nil
        guard let token = meetingToken else { return }
        notify_set_state(token, 0)
        notify_post(ForkMacBackupAgentIPCSupport.Names(bundleID: bundleID).meeting)
        notify_cancel(token)
        meetingToken = nil
    }
}
