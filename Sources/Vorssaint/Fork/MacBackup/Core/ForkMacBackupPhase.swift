// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// Why the backup waits instead of running (plan §3.8).
enum ForkMacBackupWaitReason: String, Codable, CaseIterable {
    case power
    case lowBattery
    case lowPowerMode
    case noNetwork
    case limitedNetwork
    case peerOffline
    case meeting
    case notApproved
    case noDiskAccess
    case engineMissing
    case wrongRepository
    case localSpace
    case rulesNotApplied
    /// Another `kopia` writes to the same repository (KopiaUI, Bran…).
    case otherEngine

    func title(_ text: ForkMacBackupStrings) -> String {
        switch self {
        case .power: return text.waitPower
        case .lowBattery: return text.waitBattery
        case .lowPowerMode: return text.waitLowPower
        case .noNetwork: return text.waitNetwork
        case .limitedNetwork: return text.waitLimitedNetwork
        case .peerOffline: return text.waitPeer
        case .meeting: return text.waitMeeting
        case .notApproved: return text.waitApproval
        case .noDiskAccess: return text.waitDiskAccess
        case .engineMissing: return text.waitEngine
        case .wrongRepository: return text.wrongRepository
        case .localSpace: return text.waitLocalSpace
        case .rulesNotApplied: return text.waitRules
        case .otherEngine: return text.waitOtherEngine
        }
    }

    /// The slot it leaves in the ledger when a due date passes meanwhile.
    var missedReason: ForkMacBackupMissedReason? {
        switch self {
        case .power, .lowBattery: return .battery
        case .lowPowerMode: return .lowPower
        case .noNetwork: return .network
        case .limitedNetwork: return .limitedNetwork
        case .peerOffline: return .peerOffline
        case .meeting: return .meeting
        case .notApproved: return .notApproved
        case .noDiskAccess: return .noDiskAccess
        case .engineMissing: return .engineMissing
        case .wrongRepository: return .wrongRepository
        case .localSpace, .rulesNotApplied, .otherEngine: return nil
        }
    }

    /// A problem the person has to fix (orange), rather than a condition
    /// that passes on its own (calm).
    var needsAction: Bool {
        switch self {
        case .notApproved, .noDiskAccess, .engineMissing, .wrongRepository, .localSpace, .rulesNotApplied:
            return true
        case .power, .lowBattery, .lowPowerMode, .noNetwork, .limitedNetwork, .peerOffline, .meeting, .otherEngine:
            return false
        }
    }
}

/// How the last backup ended.
enum ForkMacBackupRunResult: Codable, Equatable {
    case complete
    /// `files`: real read errors, named in the proofs.
    case partial(files: Int)
    case failed(ForkMacBackupRunFailure)
    case nothingToDo
}

/// The state machine's state (plan §3.8), the same for the agent and the
/// app. Swift's own Codable shape (`{"ready":{"next":…}}`): adding a case is
/// compatible, renaming one is not.
enum ForkMacBackupPhase: Codable, Equatable {
    /// The feature is switched off.
    case off
    case notConfigured
    case ready(next: Date?)
    case waiting(reason: ForkMacBackupWaitReason, until: Date?)
    case checkingChain
    case preparing
    /// Kopia walks the files; its estimate is not stable yet: no percentage.
    case scanning
    case uploading
    /// Uploading under the slow-down limit (meeting, button, window).
    case slowed
    case paused(until: Date?)
    /// The manifest and its errors are being read.
    case concluding
    case finished(ForkMacBackupRunResult)
    case restoring
    case verifying
    case maintaining

    /// A backup between its start and its conclusion.
    var isBackingUp: Bool {
        switch self {
        case .checkingChain, .preparing, .scanning, .uploading, .slowed, .concluding: return true
        default: return false
        }
    }

    /// What the closed island may show (decision 2 of 22/10): a backup, a
    /// restore or a verification running, nothing else; never a delay or a
    /// problem.
    var showsInClosedIsland: Bool {
        isBackingUp || self == .restoring || self == .verifying
    }

    /// Whether a byte count can be turned into a percentage.
    var hasDeterminateProgress: Bool {
        switch self {
        case .uploading, .slowed, .restoring, .verifying: return true
        default: return false
        }
    }
}
