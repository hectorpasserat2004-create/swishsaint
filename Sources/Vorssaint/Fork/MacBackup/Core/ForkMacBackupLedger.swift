// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// Why a whole run (not one file) failed or could not start: the cause a
/// banner names, with its remedy.
enum ForkMacBackupRunFailure: String, Codable, CaseIterable {
    /// A node of the chain is down (`ForkMacBackupPresentation.lastError.nodeID` says which).
    case chainBroken
    case wrongRepository
    /// Password or S3 key refused.
    case authentication
    case engineMissing
    /// Kopia or its server quit.
    case engineStopped
    /// No manifest found once the run ended.
    case noSnapshot
    /// The watchdog: 10 min without progress.
    case stalled
    case canceled
    case diskAccess
    case localSpace
    case other

    func title(_ text: ForkMacBackupStrings) -> String {
        switch self {
        case .chainBroken: return text.runChainBroken
        case .wrongRepository: return text.wrongRepository
        case .authentication: return text.runAuthentication
        case .engineMissing: return text.waitEngine
        case .engineStopped: return text.runEngineStopped
        case .noSnapshot: return text.runNoSnapshot
        case .stalled: return text.runStalled
        case .canceled: return text.runCanceled
        case .diskAccess: return text.waitDiskAccess
        case .localSpace: return text.waitLocalSpace
        case .other: return text.runOther
        }
    }

    /// What to do, as a sentence.
    func remedy(_ text: ForkMacBackupStrings) -> String {
        switch self {
        case .chainBroken: return text.fixChain
        case .wrongRepository: return text.fixWrongRepository
        case .authentication: return text.fixAuthentication
        case .engineMissing, .engineStopped: return text.fixEngine
        case .diskAccess: return text.fixDiskAccess
        case .localSpace: return text.fixSpace
        case .noSnapshot, .stalled, .canceled, .other: return text.fixRetry
        }
    }
}

/// What started an operation (history, plan §5.4).
enum ForkMacBackupTrigger: String, Codable, CaseIterable {
    case scheduled
    case catchUp
    /// Many important changes (`fork.macbackup.early.*`).
    case early
    case island
    case settings
    case commandBar
    case window
    case agent
}

/// Why a run stopped before its end.
enum ForkMacBackupStopReason: String, Codable, CaseIterable {
    case user
    case paused
    case meeting
    case sleep
    case appUpdate
    case watchdog
    case featureOff
    case agentQuit
}

/// One line of `runs.jsonl`: a backup, a verification, a restore or a
/// maintenance, with what it cost (the Automatic rhythm reads these).
struct ForkMacBackupRunRecord: Codable, Equatable, Identifiable {
    enum Kind: String, Codable, CaseIterable {
        case backup
        case verify
        case restore
        case maintenance
    }

    enum Outcome: String, Codable, CaseIterable {
        case complete
        case partial
        case failed
        case canceled
        case nothingToDo
    }

    var id: UUID
    var kind: Kind
    var trigger: ForkMacBackupTrigger
    var start: Date
    var end: Date?
    var bytesSent: Int64
    var bytesRead: Int64
    var cpuSeconds: Double
    /// Battery points lost beyond the 30 minutes' slope before; nil on AC.
    var batteryDrop: Double?
    var onBattery: Bool
    var proofs: [ForkMacBackupSnapshotProof]
    var outcome: Outcome
    var failure: ForkMacBackupRunFailure?
    var stopReason: ForkMacBackupStopReason?
    /// `verify`: its level.
    var verifyLevel: ForkMacBackupVerifyLevel?

    init(id: UUID = UUID(), kind: Kind, trigger: ForkMacBackupTrigger, start: Date, end: Date? = nil,
         bytesSent: Int64 = 0, bytesRead: Int64 = 0, cpuSeconds: Double = 0, batteryDrop: Double? = nil,
         onBattery: Bool = false, proofs: [ForkMacBackupSnapshotProof] = [], outcome: Outcome,
         failure: ForkMacBackupRunFailure? = nil, stopReason: ForkMacBackupStopReason? = nil,
         verifyLevel: ForkMacBackupVerifyLevel? = nil) {
        self.id = id
        self.kind = kind
        self.trigger = trigger
        self.start = start
        self.end = end
        self.bytesSent = bytesSent
        self.bytesRead = bytesRead
        self.cpuSeconds = cpuSeconds
        self.batteryDrop = batteryDrop
        self.onBattery = onBattery
        self.proofs = proofs
        self.outcome = outcome
        self.failure = failure
        self.stopReason = stopReason
        self.verifyLevel = verifyLevel
    }

    var duration: TimeInterval? { end.map { $0.timeIntervalSince(start) } }

    /// The end of the newest backup run that left a snapshot (complete or
    /// partial): the Automatic rhythm's minimum gap counts from it.
    static func lastProtectingEnd(_ runs: [ForkMacBackupRunRecord]) -> Date? {
        runs.filter { $0.kind == .backup && ($0.outcome == .complete || $0.outcome == .partial) }
            .compactMap { $0.end ?? $0.start }.max()
    }
}

/// Why an expected slot did not run (plan §3.9).
enum ForkMacBackupMissedReason: String, Codable, CaseIterable {
    case asleep
    case off
    case battery
    case lowPower
    case network
    case limitedNetwork
    case peerOffline
    case paused
    case meeting
    case notApproved
    case noDiskAccess
    case engineMissing
    case notConfigured
    case wrongRepository
}

/// One line of `slots.jsonl`: an expected due date and what became of it.
/// Never two slots for the same due date.
struct ForkMacBackupSlotRecord: Codable, Equatable {
    enum Outcome: Codable, Equatable {
        case done
        case partial
        case failed
        case nothingToDo
        case missed(ForkMacBackupMissedReason)
    }

    var due: Date
    var outcome: Outcome
    var startedAt: Date?
    var runID: UUID?

    init(due: Date, outcome: Outcome, startedAt: Date? = nil, runID: UUID? = nil) {
        self.due = due
        self.outcome = outcome
        self.startedAt = startedAt
        self.runID = runID
    }

    /// Started more than five minutes after its due date.
    var startedLate: Bool {
        guard let startedAt else { return false }
        return startedAt.timeIntervalSince(due) > 5 * 60
    }
}

/// One dated measure of `capacity.jsonl` (plan §7.4): each carries its date
/// and its source, an unknown one is never invented.
struct ForkMacBackupCapacitySample: Codable, Equatable {
    enum Kind: String, Codable, CaseIterable {
        /// What the last snapshot protects (real sizes, sparse images out).
        case real
        /// What one run sent.
        case sent
        /// The repository on the storage (`blob stats`).
        case physical
        /// Free on the NAS (an adapter).
        case nasFree
    }

    var kind: Kind
    var bytes: Int64
    var date: Date
    /// « snapshot », « run », « blobStats », « qnap »…
    var source: String
}
