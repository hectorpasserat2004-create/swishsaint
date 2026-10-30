// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// What `launchctl print gui/<uid>/<label>` says of the agent's job: only
/// the job's own lines (one tab deep), never those of its nested blocks
/// (coalitions, environment), which repeat words like « state ».
///
/// Measured 23/10 on build 2340 after an in-app update: `job state = spawn
/// failed`, `last exit code = 78: EX_CONFIG`, properties `… | needs LWCR
/// update | has LWCR`. The launch constraint launchd recorded at
/// registration named the old binary; it refused every respawn of the new
/// one until the agent was registered again.
struct ForkMacBackupLaunchdJob: Equatable {
    /// `state = running`, `state = not running`, `state = spawn failed`…
    var state: String?
    /// `job state = …` (newer macOS), the same words.
    var jobState: String?
    /// `last exit code = 78: EX_CONFIG`; nil for « (never exited) ».
    var lastExitCode: Int32?
    var pid: Int32?
    var runs: Int?
    /// `properties = a | b | c`.
    var properties: [String]

    init(state: String? = nil, jobState: String? = nil, lastExitCode: Int32? = nil, pid: Int32? = nil,
         runs: Int? = nil, properties: [String] = []) {
        self.state = state
        self.jobState = jobState
        self.lastExitCode = lastExitCode
        self.pid = pid
        self.runs = runs
        self.properties = properties
    }

    /// Nil when the text is no job description (the job is not loaded:
    /// `launchctl` then prints « Could not find service … » and fails).
    static func parse(_ text: String) -> ForkMacBackupLaunchdJob? {
        var job = ForkMacBackupLaunchdJob()
        var sawAny = false
        for raw in text.split(separator: "\n", omittingEmptySubsequences: true) {
            // The job's own lines: exactly one tab before the key.
            guard raw.hasPrefix("\t"), !raw.hasPrefix("\t\t") else { continue }
            let line = raw.dropFirst()
            guard let range = line.range(of: " = ") else { continue }
            let key = line[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
            let value = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
            switch key {
            case "state": job.state = value; sawAny = true
            case "job state": job.jobState = value; sawAny = true
            case "pid": job.pid = Int32(value); sawAny = true
            case "runs": job.runs = Int(value); sawAny = true
            case "last exit code":
                let number = value.split(separator: ":").first.map(String.init) ?? value
                job.lastExitCode = Int32(number.trimmingCharacters(in: .whitespaces))
                sawAny = true
            case "properties":
                job.properties = value.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                sawAny = true
            default:
                continue
            }
        }
        return sawAny ? job : nil
    }

    var isRunning: Bool {
        if let pid, pid > 0 { return true }
        return state == "running" || jobState == "running"
    }

    /// launchd tried and could not start the program: a refused launch
    /// constraint (EX_CONFIG, « needs LWCR update »), a missing program.
    var spawnFailed: Bool {
        guard !isRunning else { return false }
        if state == "spawn failed" || jobState == "spawn failed" { return true }
        if properties.contains("needs LWCR update") { return true }
        return lastExitCode == 78
    }
}

/// What identifies the code launchd was told to run: the build and, when
/// readable, the main executable's cdhash. Kept at every registration in
/// `fork.macbackup.agent.registeredStamp` (this Mac only); a different one
/// at launch means the app was replaced since (an update), so the agent is
/// registered again before launchd refuses it.
enum ForkMacBackupAgentStamp {
    static func make(build: String?, cdhash: String?) -> String {
        let name = build.flatMap { $0.isEmpty ? nil : $0 } ?? "?"
        guard let cdhash, !cdhash.isEmpty else { return name }
        return name + "+" + cdhash
    }

    /// The build part of a stamp.
    static func build(of stamp: String) -> String {
        String(stamp.split(separator: "+", maxSplits: 1).first ?? Substring(stamp))
    }
}

/// How the background agent is doing, as the app sees it.
enum ForkMacBackupAgentLinkHealth: String, Equatable {
    /// Not looked at yet, or the feature is off.
    case unknown
    /// Registered and answering (its `state.json` is fresh), or nothing
    /// says otherwise.
    case running
    /// Registered again, waiting for the agent's first word (≤ 30 s).
    case repairing
    /// Registered, but macOS does not start it, even after one new
    /// registration: the person has to allow it again (Login Items) or
    /// switch the feature off and on.
    case stoppedBySystem
}

/// The decision behind the agent's re-registration (pure, tested): after an
/// update, or when launchd says it cannot start the program, unregister and
/// register again, ONCE per app launch and build.
enum ForkMacBackupAgentRepair {
    enum Reason: String, Equatable {
        /// The bundle changed since the agent was registered.
        case newBuild
        /// launchd failed to spawn it (launch constraint, missing program).
        case spawnFailed
        /// Registered as far as the app knows, yet launchd has no such job.
        case notLoaded
        /// The registration itself failed.
        case registrationFailed
    }

    enum Action: Equatable {
        case none
        /// Healthy and registered with this build: remember the stamp.
        case record
        case reregister(Reason)
        /// Unhealthy, and the one automatic attempt is spent.
        case giveUp
    }

    struct Input: Equatable {
        var enabled: Bool
        var registration: ForkMacBackupAgentRegistration
        /// The stamp kept at the last registration; nil before the first.
        var storedStamp: String?
        var currentStamp: String
        /// `launchctl print`; nil when the job is not loaded (or the print
        /// failed: `jobReadable` says which).
        var job: ForkMacBackupLaunchdJob?
        var jobReadable: Bool
        /// A `state.json` written moments ago by a live agent of this build.
        var heartbeatFresh: Bool
        /// Stamps already re-registered during this launch.
        var attempted: Set<String>
    }

    static func decide(_ input: Input) -> Action {
        guard input.enabled else { return .none }
        let reason: Reason?
        switch input.registration {
        case .requiresApproval, .notRegistered:
            // Only the person can allow it; nothing to repair.
            return .none
        case .failed:
            reason = .registrationFailed
        case .enabled, .developmentFallback:
            if input.heartbeatFresh {
                // It runs this build: whatever launchd recorded is right.
                return input.storedStamp == input.currentStamp ? .none : .record
            }
            if input.storedStamp != input.currentStamp {
                reason = .newBuild
            } else if let job = input.job, job.spawnFailed {
                reason = .spawnFailed
            } else if input.job == nil, input.jobReadable {
                reason = .notLoaded
            } else {
                reason = nil
            }
        }
        guard let reason else { return .none }
        return input.attempted.contains(input.currentStamp) ? .giveUp : .reregister(reason)
    }

    /// The agent answered after a registration: its `state.json` was
    /// written after `since` by a live process other than the app, of this
    /// build.
    static func heartbeat(writtenAt: Date?, agentPID: Int32?, agentBuild: String?, alive: Bool, appPID: Int32,
                          build: String?, since: Date) -> Bool {
        guard let writtenAt, writtenAt >= since, let agentPID, agentPID > 0, agentPID != appPID, alive else { return false }
        guard let build else { return true }
        return agentBuild == build
    }

    /// How long the app waits for that answer before it calls the agent
    /// stopped by macOS.
    static let answerTimeout: TimeInterval = 30
    /// Between `unregister` and `register`: launchd tears the job down.
    static let settleDelay: TimeInterval = 1.5
    /// A heartbeat older than this says nothing of the agent now (it
    /// writes every 5 min at the least, `heartbeatInterval`).
    static let heartbeatFreshness: TimeInterval = ForkMacBackupAgentTuning.heartbeatInterval + 60
}
