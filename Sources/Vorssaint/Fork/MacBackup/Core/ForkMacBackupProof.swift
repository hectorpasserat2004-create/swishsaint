// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// How far a snapshot is proven (plan §5.1), shown the same way everywhere:
/// four dots, filled up to the level reached.
enum ForkMacBackupProofLevel: Int, Codable, CaseIterable, Comparable {
    /// The manifest is in `snapshot list` now (read again, not only at the
    /// end of the run).
    case present = 0
    /// No read error (cloud-only files in `.local` mode do not count).
    case complete = 1
    /// Covered by a later successful `snapshot verify --verify-files-percent`.
    case contentVerified = 2
    /// A sample restore of it was compared byte for byte.
    case restoreTested = 3

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    func title(_ text: ForkMacBackupStrings) -> String {
        switch self {
        case .present: return text.proofPresent
        case .complete: return text.proofComplete
        case .contentVerified: return text.proofVerified
        case .restoreTested: return text.proofRestored
        }
    }
}

/// Why one file was not read (plan §5.3).
enum ForkMacBackupFailureCause: String, Codable, CaseIterable {
    /// An iCloud (or File Provider) file with no data on the Mac.
    case cloudOnly
    case permission
    /// Locked or changed while being read.
    case busy
    /// Gone between the listing and the read.
    case vanished
    case other

    func title(_ text: ForkMacBackupStrings) -> String {
        switch self {
        case .cloudOnly: return text.causeCloudOnly
        case .permission: return text.causePermission
        case .busy: return text.causeBusy
        case .vanished: return text.causeVanished
        case .other: return text.causeOther
        }
    }

    /// The button that fixes it; nil for a file gone on purpose.
    func remedy(_ text: ForkMacBackupStrings) -> String? {
        switch self {
        case .cloudOnly: return text.remedyCloudOnly
        case .permission: return text.remedyPermission
        case .busy: return text.remedyBusy
        case .vanished: return nil
        case .other: return text.remedyOther
        }
    }

    /// Whether it makes a snapshot partial. A cloud-only file in `.local`
    /// mode is listed apart, the snapshot stays complete.
    func countsAsError(iCloud: ForkMacBackupICloudMode) -> Bool {
        self != .cloudOnly || iCloud == .materialize
    }

    /// Classifies Kopia's error text for `path` (an `errors[].error` of a
    /// snapshot's `summ`, or `lastError` of the upload counters).
    static func classify(message: String, path: String = "") -> ForkMacBackupFailureCause {
        let text = message.lowercased()
        func has(_ needles: String...) -> Bool { needles.contains { text.contains($0) } }
        if has("resource deadlock avoided", "edeadlk", "dataless") {
            return .cloudOnly
        }
        // A File Provider read refused: "operation canceled" (ECANCELED)
        // for a file that is in the cloud only; elsewhere, an interrupted
        // read worth a retry.
        if has("operation canceled", "operation cancelled", "ecanceled") {
            return isCloudPath(path) || isCloudPath(text) ? .cloudOnly : .busy
        }
        if has("permission denied", "operation not permitted", "eacces", "eperm") {
            return .permission
        }
        if has("no such file or directory", "enoent", "file does not exist", "not a directory") {
            return .vanished
        }
        if has("resource busy", "ebusy", "text file busy", "resource temporarily unavailable", "eagain",
               "interrupted system call", "eintr", "file changed", "changed during", "modified during") {
            return .busy
        }
        return .other
    }

    /// iCloud Drive and the File Provider folders.
    static func isCloudPath(_ path: String) -> Bool {
        let lower = path.lowercased()
        return lower.contains("library/mobile documents") || lower.contains("library/cloudstorage")
            || lower.contains("com~apple~clouddocs")
    }
}

/// One file not read, named.
struct ForkMacBackupFailure: Codable, Equatable {
    var path: String
    var cause: ForkMacBackupFailureCause
    /// Kopia's text, for « Copier le diagnostic ».
    var message: String

    init(path: String, cause: ForkMacBackupFailureCause, message: String) {
        self.path = path
        self.cause = cause
        self.message = message
    }

    /// Classified from Kopia's own entry.
    init(path: String, message: String) {
        self.init(path: path, cause: .classify(message: message, path: path), message: message)
    }
}

/// What is proven about one snapshot (`proofs.json`, the window's
/// inspector). `bytes` is Kopia's own (logical) size; `realBytes` the size
/// on disk the agent's pre-scan measured for that run (decision 1 of
/// 22/10): every view shows `diskBytes`.
struct ForkMacBackupSnapshotProof: Codable, Equatable {
    var manifestID: String
    var sourcePath: String
    var startTime: Date?
    var endTime: Date
    var level: ForkMacBackupProofLevel
    var bytes: Int64
    /// Allocated bytes of what the run kept (`totalFileAllocatedSize`); nil
    /// when not measured (a snapshot of another Mac, an older one).
    var realBytes: Int64?
    var files: Int64
    /// Real read errors (they make it partial).
    var failures: [ForkMacBackupFailure]
    /// Cloud-only files listed apart (`.local` mode).
    var cloudOnly: [String]
    /// Errors Kopia counted but did not name (`summ.errors` stops at ten
    /// per folder): the agent completes the list in `errors/<manifest>.json`.
    var unnamedFailureCount: Int
    /// Kopia's `incomplete` reason (« canceled », « checkpoint »…).
    var incomplete: String?
    var verifiedAt: Date?
    /// The `--verify-files-percent` of that verification.
    var verifiedPercent: Double?
    var restoreTestedAt: Date?

    init(manifestID: String, sourcePath: String, startTime: Date? = nil, endTime: Date,
         level: ForkMacBackupProofLevel, bytes: Int64, files: Int64, failures: [ForkMacBackupFailure] = [],
         cloudOnly: [String] = [], unnamedFailureCount: Int = 0, incomplete: String? = nil, verifiedAt: Date? = nil,
         verifiedPercent: Double? = nil, restoreTestedAt: Date? = nil) {
        self.manifestID = manifestID
        self.sourcePath = sourcePath
        self.startTime = startTime
        self.endTime = endTime
        self.level = level
        self.bytes = bytes
        self.files = files
        self.failures = failures
        self.cloudOnly = cloudOnly
        self.unnamedFailureCount = unnamedFailureCount
        self.incomplete = incomplete
        self.verifiedAt = verifiedAt
        self.verifiedPercent = verifiedPercent
        self.restoreTestedAt = restoreTestedAt
    }

    var isPartial: Bool { !failures.isEmpty || unnamedFailureCount > 0 }

    /// The size to show: the real one when measured, else Kopia's.
    var diskBytes: Int64 { realBytes ?? bytes }

    /// Every file not read, named or not.
    var failureCount: Int { failures.count + unnamedFailureCount }

    /// The failures grouped by cause, causes in declaration order.
    var failuresByCause: [(cause: ForkMacBackupFailureCause, failures: [ForkMacBackupFailure])] {
        ForkMacBackupFailureCause.allCases.compactMap { cause in
            let matching = failures.filter { $0.cause == cause }
            return matching.isEmpty ? nil : (cause, matching)
        }
    }

    /// The proof of a snapshot found in `snapshot list`: present, complete
    /// when no real error remains. Never higher: verification and restore
    /// tests raise it afterwards.
    init(manifest: ForkMacBackupKopia.SnapshotManifest, iCloud: ForkMacBackupICloudMode) {
        let entries = manifest.rootEntry?.summ?.errors ?? []
        let classified = entries.map { ForkMacBackupFailure(path: $0.path ?? "", message: $0.error ?? "") }
        let real = classified.filter { $0.cause.countsAsError(iCloud: iCloud) }
        let cloud = classified.filter { !$0.cause.countsAsError(iCloud: iCloud) }.map(\.path)
        // `summ.errors` stops at ten per folder: the counts say whether more
        // failed than were named.
        // `snapshot create --json` writes no `stats`: the root summary's
        // counts stand in.
        let summary = manifest.rootEntry?.summ
        let counted = max(Int(manifest.errorCount),
                          Int((summary?.numFailed ?? 0) + (summary?.numIgnoredErrors ?? 0)))
        let unnamed = max(0, counted - classified.count)
        let complete = real.isEmpty && unnamed == 0 && manifest.incomplete == nil
        self.init(manifestID: manifest.id,
                  sourcePath: manifest.source?.path ?? "",
                  startTime: manifest.startDate,
                  endTime: manifest.endDate ?? manifest.startDate ?? .distantPast,
                  level: complete ? .complete : .present,
                  bytes: manifest.stats?.totalSize ?? manifest.rootEntry?.summ?.size ?? 0,
                  files: manifest.stats?.fileCount ?? manifest.rootEntry?.summ?.files ?? 0,
                  failures: real,
                  cloudOnly: cloud,
                  unnamedFailureCount: unnamed,
                  incomplete: manifest.incomplete)
    }
}
