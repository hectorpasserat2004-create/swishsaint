// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// One distinct content of a file across snapshots (plan §6.2): « 14
/// versions, 3 different ». The same object ID is the same bytes, wherever
/// it appears in the list.
struct ForkMacBackupDistinctVersion: Equatable, Identifiable {
    /// The newest snapshot holding this content: the one restored.
    var newest: ForkMacBackupFileVersion
    /// The first snapshot that saved it.
    var firstSeen: Date
    var lastSeen: Date
    /// How many snapshots hold this content.
    var snapshotCount: Int

    var id: String { newest.objectID }

    /// The distinct contents of `versions`, newest content first. An empty
    /// object ID (a version Kopia did not name) never merges with another.
    static func distinct(_ versions: [ForkMacBackupFileVersion]) -> [ForkMacBackupDistinctVersion] {
        var byObject: [String: ForkMacBackupDistinctVersion] = [:]
        var order: [String] = []
        for (index, version) in versions.enumerated() {
            let key = version.objectID.isEmpty ? "#\(index)" : version.objectID
            if var known = byObject[key] {
                if version.snapshotTime > known.newest.snapshotTime { known.newest = version }
                known.firstSeen = min(known.firstSeen, version.snapshotTime)
                known.lastSeen = max(known.lastSeen, version.snapshotTime)
                known.snapshotCount += 1
                byObject[key] = known
            } else {
                byObject[key] = ForkMacBackupDistinctVersion(newest: version, firstSeen: version.snapshotTime,
                                                             lastSeen: version.snapshotTime, snapshotCount: 1)
                order.append(key)
            }
        }
        return order.compactMap { byObject[$0] }.sorted { lhs, rhs in
            lhs.lastSeen == rhs.lastSeen ? lhs.firstSeen > rhs.firstSeen : lhs.lastSeen > rhs.lastSeen
        }
    }
}

/// The checks before a restore starts (plan §6.3 step 3).
enum ForkMacBackupRestoreCheck {
    /// The margin kept on the destination: 10 % over what is restored.
    static let marginPercent: Int64 = 10

    enum Room: Equatable {
        case enough
        /// `missing`: bytes to free first.
        case short(missing: Int64)
        /// The volume did not say.
        case unknown
    }

    /// What has to be free on the destination: the size plus 10 %, rounded up.
    static func required(for bytes: Int64) -> Int64 {
        let size = max(0, bytes)
        let (margin, overflow) = size.multipliedReportingOverflow(by: marginPercent)
        guard !overflow else { return Int64.max }
        let extra = margin / 100 + (margin % 100 == 0 ? 0 : 1)
        let (total, overflowed) = size.addingReportingOverflow(extra)
        return overflowed ? Int64.max : total
    }

    static func room(needed bytes: Int64, available: Int64?) -> Room {
        guard let available, available >= 0 else { return .unknown }
        let required = required(for: bytes)
        return available >= required ? .enough : .short(missing: required - available)
    }

    /// Whether `destination` is inside one of `sources` (or is one): the
    /// restored files will be saved again by the next backup.
    static func isInsideSource(_ destination: String, sources: [String]) -> Bool {
        let path = normalized(destination)
        return sources.contains { source in
            let root = normalized(source)
            return path == root || path.hasPrefix(root == "/" ? "/" : root + "/")
        }
    }

    private static func normalized(_ path: String) -> String {
        let standard = (path as NSString).standardizingPath
        return standard.count > 1 && standard.hasSuffix("/") ? String(standard.dropLast()) : standard
    }
}
