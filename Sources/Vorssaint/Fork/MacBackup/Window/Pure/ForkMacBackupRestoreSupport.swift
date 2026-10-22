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

/// Where a restore goes and under which names (plan §6.3). Pure: the file
/// system is asked through closures, so the rules are tested alone.
enum ForkMacBackupRestoreNaming {
    /// « Restauré — 22 oct. 2026 à 10.04 »: a Finder name, so no « : »
    /// (the Finder shows it as « / ») and no « / ».
    static func folderName(prefix: String, date: Date, locale: Locale, timeZone: TimeZone = .autoupdatingCurrent) -> String {
        var style = Date.FormatStyle(date: .abbreviated, time: .shortened, locale: locale)
        style.timeZone = timeZone
        return finderSafe(prefix + " — " + date.formatted(style))
    }

    /// A name the Finder and the file system both take.
    static func finderSafe(_ name: String) -> String {
        var text = name.replacingOccurrences(of: ":", with: ".").replacingOccurrences(of: "/", with: "-")
        // Narrow and thin no-break spaces of some locales' clocks stay
        // readable as plain spaces in a file name.
        text = text.replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{2009}", with: " ")
        while text.hasPrefix(".") { text.removeFirst() }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "-" : String(trimmed.prefix(240))
    }

    /// `base`, else « base 2 », « base 3 »… the first that `exists` says is free.
    static func uniqueFolder(_ base: String, exists: (String) -> Bool) -> String {
        guard exists(base) else { return base }
        var number = 2
        while exists("\(base) \(number)") { number += 1 }
        return "\(base) \(number)"
    }

    /// « Keep both »: « rapport.pdf » becomes « rapport (restauré).pdf »,
    /// then « rapport (restauré 2).pdf »… A folder, a name without
    /// extension or a dot file keeps its whole name before the suffix.
    static func keepBothName(_ name: String, isDirectory: Bool, word: String, exists: (String) -> Bool) -> String {
        guard exists(name) else { return name }
        let (stem, ext) = split(name, isDirectory: isDirectory)
        func candidate(_ number: Int) -> String {
            let tag = number == 1 ? "(\(word))" : "(\(word) \(number))"
            return ext.isEmpty ? "\(stem) \(tag)" : "\(stem) \(tag).\(ext)"
        }
        var number = 1
        while exists(candidate(number)) { number += 1 }
        return candidate(number)
    }

    /// The name and its last extension; none for a folder, a dot file or
    /// a name ending with a dot.
    static func split(_ name: String, isDirectory: Bool) -> (stem: String, ext: String) {
        guard !isDirectory, let dot = name.lastIndex(of: "."), dot != name.startIndex,
              name.index(after: dot) != name.endIndex else { return (name, "") }
        let ext = String(name[name.index(after: dot)...])
        guard !ext.contains(" ") else { return (name, "") }
        return (String(name[..<dot]), ext)
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
