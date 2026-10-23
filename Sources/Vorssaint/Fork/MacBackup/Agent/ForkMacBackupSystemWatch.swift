// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Darwin
import Foundation
import IOKit
import IOKit.ps
import IOKit.pwr_mgt
import Network
import notify

/// The Mac's conditions as the planner needs them (plan §3.9): power and
/// Low Power Mode, the network, sleep and wake, the meeting the app
/// records. Everything is dispatch-based and AppKit-free, so it works the
/// same in the headless agent (no NSApplication, no run loop) and in the
/// app. Every callback lands on `queue`; `stop()` cancels each observer.
final class ForkMacBackupSystemWatch {
    /// A condition changed.
    var onChange: (() -> Void)?
    var onWillSleep: (() -> Void)?
    var onDidWake: (() -> Void)?

    private(set) var onAC = true
    private(set) var batteryPercent: Int?
    private(set) var lowPowerMode = false
    private(set) var network: ForkMacBackupConditions.Network = .unknown
    private(set) var meetingBusy = false
    /// The battery readings of the last two hours (the cost of a run).
    private(set) var batterySamples: [ForkMacBackupBatterySample] = []

    private let queue: DispatchQueue
    private let names: ForkMacBackupAgentIPCSupport.Names
    private var started = false
    private var pathMonitor: NWPathMonitor?
    private var notifyTokens: [Int32] = []
    private var meetingToken: Int32?
    private var lowPowerObserver: NSObjectProtocol?
    private var rootPort: io_connect_t = 0
    private var powerPort: IONotificationPortRef?
    private var powerNotifier: io_object_t = 0

    init(queue: DispatchQueue, bundleID: String) {
        self.queue = queue
        names = ForkMacBackupAgentIPCSupport.Names(bundleID: bundleID)
    }

    deinit {
        stopObservers()
    }

    /// On `queue`.
    func start() {
        guard !started else { return }
        started = true
        readPower()
        lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

        // Power source and battery level: IOPS posts Darwin notifications.
        for name in [kIOPSNotifyPowerSource, kIOPSNotifyAnyPowerSource] {
            var token: Int32 = 0
            if notify_register_dispatch(name, &token, queue, { [weak self] _ in self?.powerChanged() })
                == UInt32(NOTIFY_STATUS_OK) {
                notifyTokens.append(token)
            }
        }
        lowPowerObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name.NSProcessInfoPowerStateDidChange, object: nil, queue: nil
        ) { [weak self] _ in
            self?.queue.async { self?.lowPowerChanged() }
        }

        // The meeting tally lives in the app: it mirrors it as a notify state.
        var token: Int32 = 0
        if notify_register_dispatch(names.meeting, &token, queue, { [weak self] token in
            self?.meetingChanged(token: token)
        }) == UInt32(NOTIFY_STATUS_OK) {
            meetingToken = token
            meetingBusy = Self.state(of: token) == 1
        }

        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in self?.pathChanged(path) }
        monitor.start(queue: queue)
        pathMonitor = monitor

        registerForSleep()
    }

    /// On `queue`.
    func stop() {
        guard started else { return }
        started = false
        stopObservers()
    }

    private func stopObservers() {
        for token in notifyTokens { notify_cancel(token) }
        notifyTokens = []
        if let meetingToken { notify_cancel(meetingToken) }
        meetingToken = nil
        if let lowPowerObserver { NotificationCenter.default.removeObserver(lowPowerObserver) }
        lowPowerObserver = nil
        pathMonitor?.cancel()
        pathMonitor = nil
        if powerNotifier != 0 {
            IODeregisterForSystemPower(&powerNotifier)
            powerNotifier = 0
        }
        if rootPort != 0 {
            IOServiceClose(rootPort)
            rootPort = 0
        }
        if let powerPort {
            IONotificationPortDestroy(powerPort)
            self.powerPort = nil
        }
    }

    // MARK: Power

    private func powerChanged() {
        let before = (onAC, batteryPercent)
        readPower()
        if before.0 != onAC || before.1 != batteryPercent { onChange?() }
    }

    private func lowPowerChanged() {
        let now = ProcessInfo.processInfo.isLowPowerModeEnabled
        guard now != lowPowerMode else { return }
        lowPowerMode = now
        onChange?()
    }

    /// Reads the providing source and the internal battery's level.
    func readPower(now: Date = Date()) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return }
        if let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String? {
            onAC = type != kIOPSBatteryPowerValue
        }
        var percent: Int?
        if let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] {
            for source in list {
                guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                      description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                      let current = description[kIOPSCurrentCapacityKey] as? Int,
                      let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
                percent = Int((Double(current) / Double(maximum) * 100).rounded())
            }
        }
        batteryPercent = percent
        if let percent {
            batterySamples.append(ForkMacBackupBatterySample(date: now, percent: Double(percent), onAC: onAC))
            batterySamples.removeAll { now.timeIntervalSince($0.date) > 2 * 3_600 }
        }
    }

    // MARK: Network

    private func pathChanged(_ path: NWPath) {
        let value: ForkMacBackupConditions.Network = path.status == .satisfied
            ? .available(limited: path.isExpensive || path.isConstrained)
            : .none
        guard value != network else { return }
        network = value
        onChange?()
    }

    // MARK: Meeting

    private func meetingChanged(token: Int32) {
        let busy = Self.state(of: token) == 1
        guard busy != meetingBusy else { return }
        meetingBusy = busy
        onChange?()
    }

    private static func state(of token: Int32) -> UInt64 {
        var state: UInt64 = 0
        notify_get_state(token, &state)
        return state
    }

    // MARK: Sleep and wake

    // `iokit_common_msg` macros do not reach Swift: their values.
    private static let canSystemSleep: UInt32 = 0xE000_0270
    private static let systemWillSleep: UInt32 = 0xE000_0280
    private static let systemHasPoweredOn: UInt32 = 0xE000_0300

    /// `IORegisterForSystemPower` on a dispatch queue: no run loop, no
    /// NSWorkspace (AppKit), so it works headless (checked on macOS 27).
    private func registerForSleep() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        var port: IONotificationPortRef?
        var notifier: io_object_t = 0
        let root = IORegisterForSystemPower(context, &port, { refcon, _, message, argument in
            guard let refcon else { return }
            Unmanaged<ForkMacBackupSystemWatch>.fromOpaque(refcon).takeUnretainedValue()
                .powerMessage(message, argument: argument)
        }, &notifier)
        guard root != 0, let port else { return }
        rootPort = root
        powerPort = port
        powerNotifier = notifier
        IONotificationPortSetDispatchQueue(port, queue)
    }

    private func powerMessage(_ message: UInt32, argument: UnsafeMutableRawPointer?) {
        switch message {
        case Self.canSystemSleep:
            // Idle sleep is not vetoed here: the run's assertion does that.
            IOAllowPowerChange(rootPort, Int(bitPattern: argument))
        case Self.systemWillSleep:
            onWillSleep?()
            IOAllowPowerChange(rootPort, Int(bitPattern: argument))
        case Self.systemHasPoweredOn:
            readPower()
            onDidWake?()
        default:
            break
        }
    }

    // MARK: Probes (on demand, bounded)

    /// `kern.boottime`.
    static func bootTime() -> Date? {
        var time = timeval()
        var size = MemoryLayout<timeval>.size
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        guard sysctl(&mib, 2, &time, &size, nil, 0) == 0, time.tv_sec > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(time.tv_sec) + TimeInterval(time.tv_usec) / 1_000_000)
    }

    /// false only when Full Disk Access is known to be refused: the TCC
    /// database exists and cannot be read. Anything unclear never blocks a
    /// backup (a refused file would show as a named failure anyway).
    static func diskAccessKnownRefused(home: String = NSHomeDirectory()) -> Bool {
        let database = (home as NSString).appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db")
        guard FileManager.default.fileExists(atPath: database) else { return false }
        let descriptor = open(database, O_RDONLY)
        if descriptor >= 0 {
            close(descriptor)
            return false
        }
        return errno == EPERM || errno == EACCES
    }

    /// Kopia's cache could fill the Mac: below the floor, wait.
    static func localSpaceLow(at url: URL) -> Bool {
        guard let free = freeBytes(at: url) else { return false }
        return free < ForkMacBackupAgentTuning.minimumLocalFreeBytes
    }

    /// The room left for files the person keeps (purgeable space counted),
    /// on `url`'s volume; nil when macOS does not say.
    static func freeBytes(at url: URL) -> Int64? {
        guard let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]) else { return nil }
        return values.volumeAvailableCapacityForImportantUsage
    }

    /// Runs `tailscale status --json` (5 s at most) off the queue and hands
    /// whether `peer` is online back on `queue`; nil without Tailscale.
    func probePeer(_ peer: ForkMacBackupRepository.Peer, timeout: TimeInterval, completion: @escaping (Bool?) -> Void) {
        let queue = self.queue
        DispatchQueue.global(qos: .utility).async {
            let command = ForkMacBackupTailscale.command { FileManager.default.isExecutableFile(atPath: $0) }
            let status = command.flatMap { Self.run($0.path, $0.arguments, environment: $0.environment, timeout: timeout) }
                .flatMap(ForkMacBackupTailscale.decode)
            let online = command == nil ? nil : ForkMacBackupTailscale.peerOnline(peer, status: status)
            queue.async { completion(online) }
        }
    }

    /// A child process's standard output, killed after `timeout`.
    static func run(_ path: String, _ arguments: [String], environment: [String: String] = [:],
                    timeout: TimeInterval) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        var env = ProcessInfo.processInfo.environment
        for (key, value) in environment { env[key] = value }
        process.environment = env
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let killer = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: killer)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        killer.cancel()
        return process.terminationStatus == 0 ? data : nil
    }
}

/// The other Kopia processes on this Mac (plan §3.11), read from the
/// process table: path, arguments and environment (`KERN_PROCARGS2`).
enum ForkMacBackupProcesses {
    struct Info {
        var pid: pid_t
        var path: String
        var arguments: [String]
        var environment: [String: String]
    }

    /// Whether another Kopia writes to `repository`. Ours are left out: our
    /// children, and any that uses a config inside our own folder.
    static func otherEngineWrites(to repository: ForkMacBackupRepository, ourRoot: URL,
                                  home: String = NSHomeDirectory()) -> Bool {
        let me = getpid()
        for pid in allPIDs() where pid != me {
            guard let path = executablePath(pid), (path as NSString).lastPathComponent == "kopia",
                  parent(of: pid) != me, let info = arguments(of: pid, path: path),
                  ForkMacBackupOtherEngine.isWriter(executable: path, arguments: info.arguments) else { continue }
            let config = ForkMacBackupOtherEngine.configPath(arguments: info.arguments, environment: info.environment,
                                                             home: home)
            if config.hasPrefix(ourRoot.path + "/") { continue }
            // Read-only look at its config, a few kilobytes of JSON.
            guard let handle = FileHandle(forReadingAtPath: config) else { continue }
            let data = (try? handle.read(upToCount: 1_000_000)) ?? nil
            try? handle.close()
            if let data, ForkMacBackupOtherEngine.sameRepository(configData: data, as: repository) { return true }
        }
        return false
    }

    static func allPIDs() -> [pid_t] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 64)
        let filled = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard filled > 0 else { return [] }
        return Array(pids.prefix(Int(filled))).filter { $0 > 0 }
    }

    static func executablePath(_ pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }

    static func parent(of pid: pid_t) -> pid_t? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return pid_t(info.pbi_ppid)
    }

    /// `KERN_PROCARGS2`: argc, the exec path, argv, then the environment.
    static func arguments(of pid: pid_t, path: String) -> Info? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }
        let argc = buffer.withUnsafeBytes { $0.load(as: Int32.self) }
        var index = MemoryLayout<Int32>.size
        // Skip the exec path and its padding.
        while index < size && buffer[index] != 0 { index += 1 }
        while index < size && buffer[index] == 0 { index += 1 }
        var strings: [String] = []
        var start = index
        while index < size {
            if buffer[index] == 0 {
                if index > start { strings.append(String(decoding: buffer[start..<index], as: UTF8.self)) }
                start = index + 1
            }
            index += 1
        }
        let argumentCount = min(Int(argc), strings.count)
        var environment: [String: String] = [:]
        for entry in strings.dropFirst(argumentCount) {
            guard let equal = entry.firstIndex(of: "=") else { continue }
            environment[String(entry[..<equal])] = String(entry[entry.index(after: equal)...])
        }
        return Info(pid: pid, path: path, arguments: Array(strings.prefix(argumentCount)), environment: environment)
    }
}

/// The idle-sleep assertion during a backup (plan §3.9): it keeps the Mac
/// awake while idle, not with the lid closed nor on a critical battery.
/// Released on every path, the deinit included.
final class ForkMacBackupKeepAwake {
    private var assertion: IOPMAssertionID = 0
    private(set) var isHeld = false

    deinit {
        set(false, reason: "")
    }

    func set(_ on: Bool, reason: String) {
        if on, !isHeld {
            var id: IOPMAssertionID = 0
            let result = IOPMAssertionCreateWithName(kIOPMAssertPreventUserIdleSystemSleep as CFString,
                                                     IOPMAssertionLevel(kIOPMAssertionLevelOn), reason as CFString, &id)
            if result == kIOReturnSuccess {
                assertion = id
                isHeld = true
            }
        } else if !on, isHeld {
            IOPMAssertionRelease(assertion)
            assertion = 0
            isHeld = false
        }
    }
}

/// What a run cost the Mac, read on the Kopia server's own process (plan
/// §3.9.1): CPU time and bytes read from the disk, as a difference between
/// the start and the end of the run.
enum ForkMacBackupCostMeter {
    struct Reading: Equatable {
        var cpuSeconds: Double
        var bytesRead: Int64
    }

    static func read(pid: pid_t) -> Reading? {
        guard pid > 0 else { return nil }
        var info = rusage_info_v4()
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        guard status == 0 else { return nil }
        // The CPU times are in Mach absolute units.
        var base = mach_timebase_info_data_t()
        mach_timebase_info(&base)
        let ticks = Double(info.ri_user_time + info.ri_system_time)
        let nanoseconds = base.denom == 0 ? ticks : ticks * Double(base.numer) / Double(base.denom)
        return Reading(cpuSeconds: nanoseconds / 1_000_000_000, bytesRead: Int64(clamping: info.ri_diskio_bytesread))
    }

    /// The end minus the start; nil when the process changed in between.
    static func difference(start: Reading?, end: Reading?) -> Reading? {
        guard let start, let end, end.cpuSeconds >= start.cpuSeconds, end.bytesRead >= start.bytesRead else { return nil }
        return Reading(cpuSeconds: end.cpuSeconds - start.cpuSeconds, bytesRead: end.bytesRead - start.bytesRead)
    }
}
