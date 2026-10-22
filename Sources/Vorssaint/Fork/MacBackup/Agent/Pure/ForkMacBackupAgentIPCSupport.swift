// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// The agent's side of the IPC rules (README §1, plan §3.4), pure.
enum ForkMacBackupAgentIPCSupport {
    // MARK: Live progress lease

    /// Whether a view shows the live progress: the app renews
    /// `run/viewer.lease` every 5 s while one does.
    static func leaseIsFresh(modifiedAt: Date?, now: Date) -> Bool {
        guard let modifiedAt else { return false }
        let age = now.timeIntervalSince(modifiedAt)
        // A date in the future (clock change) counts as fresh for its freshness span only.
        return age <= ForkMacBackupAgentTuning.leaseFreshness && age >= -ForkMacBackupAgentTuning.leaseFreshness
    }

    /// How often the state is rewritten while an operation runs: each
    /// second while the lease is fresh, every ten seconds otherwise.
    static func publishInterval(leaseModifiedAt: Date?, now: Date) -> TimeInterval {
        leaseIsFresh(modifiedAt: leaseModifiedAt, now: now)
            ? ForkMacBackupAgentTuning.livePublishInterval
            : ForkMacBackupAgentTuning.quietPublishInterval
    }

    /// Whether to write `state.json` now. A change of anything but the live
    /// figures and the date is written at once; the figures follow the
    /// cadence; an unchanged state is rewritten only as a heartbeat.
    static func shouldPublish(_ new: ForkMacBackupPresentation, last: ForkMacBackupPresentation?, lastWrittenAt: Date?,
                              leaseModifiedAt: Date?, now: Date, force: Bool = false) -> Bool {
        guard !force, let last, let lastWrittenAt else { return true }
        let elapsed = now.timeIntervalSince(lastWrittenAt)
        if elapsed < 0 { return true }
        var a = new
        var b = last
        a.updatedAt = .distantPast
        b.updatedAt = .distantPast
        let figuresOnly: Bool = {
            a.progress = nil
            b.progress = nil
            return a == b
        }()
        if !figuresOnly { return true }
        if new.progress != last.progress {
            return elapsed >= publishInterval(leaseModifiedAt: leaseModifiedAt, now: now) - 0.05
        }
        return elapsed >= ForkMacBackupAgentTuning.heartbeatInterval
    }

    // MARK: Commands

    /// The command files to run, oldest first, and the names to delete
    /// (every file read: run, stale or unreadable). A command older than
    /// `ForkMacBackupCommandFile.maxAge` is never replayed.
    static func inbox(_ files: [(name: String, data: Data?)], now: Date)
        -> (run: [ForkMacBackupCommandFile], delete: [String]) {
        var commands: [ForkMacBackupCommandFile] = []
        var delete: [String] = []
        var seen = Set<UUID>()
        for file in files where file.name.hasSuffix(".json") {
            delete.append(file.name)
            guard let data = file.data, let command = ForkMacBackupCommandFile.decode(data),
                  command.isFresh(now: now), seen.insert(command.id).inserted else { continue }
            commands.append(command)
        }
        commands.sort { ($0.issuedAt, $0.id.uuidString) < ($1.issuedAt, $1.id.uuidString) }
        return (commands, delete)
    }

    // MARK: Update hold

    /// `run/update.hold`: written by the app's updater before it replaces
    /// the app; while fresh, no backup starts, and the cancel it sends is
    /// recorded as stopped for the update.
    static func updateHoldIsFresh(modifiedAt: Date?, now: Date) -> Bool {
        guard let modifiedAt else { return false }
        let age = now.timeIntervalSince(modifiedAt)
        return age >= -60 && age <= ForkMacBackupAgentTuning.updateHoldLifetime
    }

    static func updateHoldURL(_ paths: ForkMacBackupPaths) -> URL {
        paths.run.appendingPathComponent("update.hold", isDirectory: false)
    }

    // MARK: Darwin notifications of the agent

    /// The names the agent adds to `ForkMacBackupNotify` (same bundle-derived
    /// base, so the Developer build and the release never hear each other).
    struct Names: Equatable {
        /// The app's meeting tally, as a notify state (1 busy, 0 not).
        let meeting: String
        /// A new agent waits for the app's runner to hand the lock over.
        let handover: String

        init(bundleID: String) {
            let base = bundleID + ".macbackup"
            meeting = base + ".meeting"
            handover = base + ".handover"
        }
    }
}

/// The single instance (plan §3.3): `flock` on `run/agent.lock`. The holder
/// writes who it is, so a starting agent can tell the app's runner (which
/// hands over) from another agent (it then leaves).
final class ForkMacBackupAgentLock {
    enum Role: String {
        case agent
        case app
    }

    enum Outcome: Equatable {
        case acquired
        /// Held by another process; its role and pid when readable.
        case held(role: Role?, pid: Int32?)
        case failed
    }

    let url: URL
    private var descriptor: Int32 = -1

    init(url: URL) {
        self.url = url
    }

    deinit {
        release()
    }

    var isHeld: Bool { descriptor >= 0 }

    /// Takes the lock without waiting.
    func acquire(role: Role, pid: Int32 = getpid()) -> Outcome {
        guard descriptor < 0 else { return .acquired }
        let fd = open(url.path, O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
        guard fd >= 0 else { return .failed }
        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            let holder = Self.parse(Self.read(fd))
            close(fd)
            return .held(role: holder.role, pid: holder.pid)
        }
        descriptor = fd
        let text = "\(role.rawValue) \(pid)\n"
        _ = ftruncate(fd, 0)
        _ = text.withCString { pwrite(fd, $0, strlen($0), 0) }
        return .acquired
    }

    func release() {
        guard descriptor >= 0 else { return }
        _ = ftruncate(descriptor, 0)
        flock(descriptor, LOCK_UN)
        close(descriptor)
        descriptor = -1
    }

    /// « agent 1234 » → its role and pid.
    static func parse(_ text: String) -> (role: Role?, pid: Int32?) {
        let parts = text.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init)
        guard parts.count >= 2 else { return (parts.first.flatMap(Role.init(rawValue:)), nil) }
        return (Role(rawValue: parts[0]), Int32(parts[1]))
    }

    private static func read(_ fd: Int32) -> String {
        var buffer = [UInt8](repeating: 0, count: 64)
        let count = pread(fd, &buffer, buffer.count, 0)
        guard count > 0 else { return "" }
        return String(decoding: buffer.prefix(count), as: UTF8.self)
    }
}
