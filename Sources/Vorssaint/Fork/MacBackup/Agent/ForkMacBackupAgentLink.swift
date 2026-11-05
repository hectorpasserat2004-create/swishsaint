// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import AppKit
import Foundation
import notify
import Security
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
    /// Whether macOS really runs the agent it says is registered (Health's
    /// « Agent et moteur »): after an update launchd can keep a launch
    /// constraint naming the old binary and refuse the new one.
    @Published private(set) var health: ForkMacBackupAgentLinkHealth = .unknown

    private let bundleID = Bundle.main.bundleIdentifier ?? "swishsaint"
    private let work = DispatchQueue(label: "fork.macbackup.link", qos: .utility)
    private var appRunner: ForkMacBackupRunner?
    private var meetingToken: Int32?
    private var meetingObserver: NSObjectProtocol?
    private var activationObserver: NSObjectProtocol?
    private var recheckTimer: Timer?
    private var syncing = false
    private var syncAgain = false
    /// Stamps re-registered automatically during this launch: one attempt
    /// per launch and build, never a loop.
    private var repairAttempted: Set<String> = []
    private var repairCheck: Timer?
    private var repairStartedAt: Date?
    private var lastLook: Date?

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
        lastLook = Date()
        let enabled = isEnabled
        let bundleID = self.bundleID
        let attempted = repairAttempted
        let repairing = health == .repairing
        work.async { [weak self] in
            let outcome: Outcome
            if enabled {
                outcome = Self.ensure(bundleID: bundleID, attempted: attempted, repairing: repairing)
            } else {
                outcome = Outcome(registration: Self.unregister(bundleID: bundleID), health: .unknown)
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.syncing = false
                if self.registration != outcome.registration { self.registration = outcome.registration }
                if let stamp = outcome.attempted {
                    self.repairAttempted.insert(stamp)
                    self.awaitAgent(since: outcome.attemptedAt ?? Date())
                } else if outcome.health != .repairing {
                    // Still `.repairing`: the wait for the agent's answer goes on.
                    self.stopAwaiting()
                    if self.health != outcome.health { self.health = outcome.health }
                }
                self.chooseMode(enabled: enabled)
                if self.syncAgain {
                    self.syncAgain = false
                    self.refresh()
                }
            }
        }
    }

    /// What a pass on the work queue found and did.
    private struct Outcome {
        var registration: ForkMacBackupAgentRegistration
        var health: ForkMacBackupAgentLinkHealth
        /// The stamp just registered again, if any.
        var attempted: String?
        var attemptedAt: Date?
    }

    /// Registers, then makes sure macOS really runs that registration: after
    /// an update (another stamp) or a spawn launchd refused, unregister and
    /// register again, once per launch and build
    /// (`ForkMacBackupAgentRepair.decide`).
    private static func ensure(bundleID: String, attempted: Set<String>, repairing: Bool) -> Outcome {
        var registeredNow = false
        let registration = register(bundleID: bundleID, registeredNow: &registeredNow)
        let stamp = currentStamp()
        if registeredNow {
            // A registration made now names this code: nothing to repair.
            UserDefaults.standard.set(stamp, forKey: ForkDefaultsKey.macBackupAgentStamp)
        }
        let label = ForkMacBackupAgentPlist.label(bundleID: bundleID)
        let job = registration == .requiresApproval || registration == .notRegistered
            ? (parsed: nil, readable: false) : readJob(label: label)
        let fresh = heartbeat(since: Date().addingTimeInterval(-ForkMacBackupAgentRepair.heartbeatFreshness))
        let input = ForkMacBackupAgentRepair.Input(
            enabled: true, registration: registration,
            storedStamp: UserDefaults.standard.string(forKey: ForkDefaultsKey.macBackupAgentStamp),
            currentStamp: stamp, job: job.parsed, jobReadable: job.readable, heartbeatFresh: fresh,
            attempted: attempted)
        switch ForkMacBackupAgentRepair.decide(input) {
        case .none:
            switch registration {
            case .enabled, .developmentFallback:
                // Waiting for its first word after a new registration: the
                // timer (`awaitAgent`) decides.
                return Outcome(registration: registration, health: repairing && !fresh ? .repairing : .running)
            case .notRegistered, .requiresApproval, .failed:
                return Outcome(registration: registration, health: .unknown)
            }
        case .record:
            UserDefaults.standard.set(stamp, forKey: ForkDefaultsKey.macBackupAgentStamp)
            return Outcome(registration: registration, health: .running)
        case .giveUp:
            return Outcome(registration: registration, health: repairing ? .repairing : .stoppedBySystem)
        case .reregister:
            let started = Date()
            _ = unregister(bundleID: bundleID)
            Thread.sleep(forTimeInterval: ForkMacBackupAgentRepair.settleDelay)
            var again = false
            let registrationAgain = register(bundleID: bundleID, registeredNow: &again)
            if again {
                UserDefaults.standard.set(stamp, forKey: ForkDefaultsKey.macBackupAgentStamp)
            }
            return Outcome(registration: registrationAgain, health: .repairing, attempted: stamp, attemptedAt: started)
        }
    }

    /// This build and the main executable's cdhash: what launchd's launch
    /// constraint for the agent names.
    private static func currentStamp() -> String {
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        var cdhash: String?
        var code: SecCode?
        var staticCode: SecStaticCode?
        var info: CFDictionary?
        if SecCodeCopySelf([], &code) == errSecSuccess, let code,
           SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
           SecCodeCopySigningInformation(staticCode, [], &info) == errSecSuccess,
           let unique = (info as? [String: Any])?[kSecCodeInfoUnique as String] as? Data {
            cdhash = unique.map { String(format: "%02x", $0) }.joined()
        }
        return ForkMacBackupAgentStamp.make(build: build, cdhash: cdhash)
    }

    /// `launchctl print gui/<uid>/<label>`, read only, 3 s at most.
    /// `readable` false when launchctl could not be asked at all.
    private static func readJob(label: String) -> (parsed: ForkMacBackupLaunchdJob?, readable: Bool) {
        let result = BoundedProcessRunner.run("/bin/launchctl", ["print", "gui/\(getuid())/\(label)"],
                                              timeout: 3, maxOutputBytes: 256 * 1024)
        guard !result.timedOut else { return (nil, false) }
        let text = String(decoding: result.output, as: UTF8.self)
        if result.status == 0, let job = ForkMacBackupLaunchdJob.parse(text) { return (job, true) }
        // « Could not find service »: launchd has no such job.
        return (nil, result.status != 0)
    }

    /// A live agent of this build wrote `state.json` after `since`.
    private static func heartbeat(since: Date) -> Bool {
        guard let paths = ForkMacBackupPaths(container: PrivateFileStore.containerURL),
              let data = try? Data(contentsOf: paths.state),
              let file = ForkMacBackupStateFile.decode(data) else { return false }
        let alive = file.agentPID.map { $0 > 0 && kill($0, 0) == 0 } ?? false
        return ForkMacBackupAgentRepair.heartbeat(
            writtenAt: file.writtenAt, agentPID: file.agentPID, agentBuild: file.agentBuild, alive: alive,
            appPID: getpid(), build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String, since: since)
    }

    /// After a new registration: the agent's first `state.json` within
    /// 30 s, or it is stopped by macOS (the app backs up meanwhile).
    private func awaitAgent(since: Date) {
        stopAwaiting()
        repairStartedAt = since
        if health != .repairing { health = .repairing }
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.checkAgentAnswer() }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        repairCheck = timer
    }

    private func checkAgentAnswer() {
        guard let since = repairStartedAt else { return stopAwaiting() }
        let timedOut = Date().timeIntervalSince(since) >= ForkMacBackupAgentRepair.answerTimeout
        work.async { [weak self] in
            let answered = Self.heartbeat(since: since)
            DispatchQueue.main.async {
                guard let self, self.repairStartedAt == since else { return }
                guard answered || timedOut else { return }
                self.stopAwaiting()
                let health: ForkMacBackupAgentLinkHealth = answered ? .running : .stoppedBySystem
                if self.health != health { self.health = health }
                self.chooseMode(enabled: self.isEnabled)
            }
        }
    }

    private func stopAwaiting() {
        repairCheck?.invalidate()
        repairCheck = nil
        repairStartedAt = nil
    }

    private static var bundledPlist: URL {
        ForkMacBackupAgentPlist.bundledURL(appURL: Bundle.main.bundleURL, bundleID: Bundle.main.bundleIdentifier ?? "")
    }

    /// `registeredNow`: this call registered it (or bootstrapped it), so
    /// launchd knows this very code.
    private static func register(bundleID: String, registeredNow: inout Bool) -> ForkMacBackupAgentRegistration {
        if FileManager.default.fileExists(atPath: bundledPlist.path) {
            let service = SMAppService.agent(plistName: ForkMacBackupAgentPlist.fileName(bundleID: bundleID))
            if service.status == .notRegistered || service.status == .notFound {
                do {
                    try service.register()
                    registeredNow = true
                } catch {
                    if service.status == .requiresApproval {
                        registeredNow = true
                        return .requiresApproval
                    }
                    return .failed
                }
            }
            return map(service.status)
        }
        return registerLegacy(bundleID: bundleID, registeredNow: &registeredNow)
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
    private static func registerLegacy(bundleID: String, registeredNow: inout Bool) -> ForkMacBackupAgentRegistration {
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
            registeredNow = launchctl(["bootstrap", domain, url.path])
            return registeredNow ? .developmentFallback : .failed
        }
        if loaded { return .developmentFallback }
        registeredNow = launchctl(["bootstrap", domain, url.path])
        return registeredNow ? .developmentFallback : .failed
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
        case .enabled where health != .stoppedBySystem, .developmentFallback where health != .stoppedBySystem:
            // Also while it is registered again (`.repairing`): the agent
            // gets its chance before the app backs up in its place.
            stopAppRunner()
            if mode != .agent { mode = .agent }
        case .enabled, .developmentFallback, .notRegistered, .requiresApproval, .failed:
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
            guard let self else { return }
            // In agent mode, a look every 5 min at most: launchd may have
            // stopped it meanwhile.
            if self.mode == .agent, self.health != .repairing,
               let lastLook = self.lastLook, Date().timeIntervalSince(lastLook) < 5 * 60 { return }
            self.refresh()
        }
    }

    private func stopObserving() {
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
        activationObserver = nil
        recheckTimer?.invalidate()
        recheckTimer = nil
        stopAwaiting()
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
