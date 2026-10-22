// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// Kopia's ignore rules (gitignore syntax), read the way Kopia reads them,
/// to say which rule left a file out (plan §6.4). A leading « / » anchors a
/// rule at the source's root, a trailing « / » takes folders only, a rule
/// without an inner « / » matches a name at any depth, « ! » takes a file
/// back (never out of a folder already left out).
enum ForkMacBackupIgnoreRules {
    /// The rule that leaves `relativePath` out, or nil when it is kept.
    static func excludingRule(for relativePath: String, isDirectory: Bool, rules: [String]) -> String? {
        let parts = ForkMacBackupFolderPath.components(relativePath)
        guard !parts.isEmpty else { return nil }
        for depth in 1...parts.count {
            let candidate = Array(parts.prefix(depth))
            let candidateIsDirectory = depth < parts.count || isDirectory
            var excludedBy: String?
            for rule in rules {
                let trimmed = rule.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
                let negated = trimmed.hasPrefix("!")
                let body = negated ? String(trimmed.dropFirst()) : trimmed
                guard matches(body, components: candidate, isDirectory: candidateIsDirectory) else { continue }
                excludedBy = negated ? nil : trimmed
            }
            if let excludedBy { return excludedBy }
        }
        return nil
    }

    static func matches(_ rule: String, components: [String], isDirectory: Bool) -> Bool {
        var pattern = rule
        var directoryOnly = false
        if pattern.hasSuffix("/") {
            directoryOnly = true
            pattern.removeLast()
        }
        var anchored = false
        if pattern.hasPrefix("/") {
            anchored = true
            pattern.removeFirst()
        }
        if pattern.contains("/") { anchored = true }
        guard !pattern.isEmpty, !(directoryOnly && !isDirectory), let name = components.last else { return false }
        if anchored {
            let flags = pattern.contains("**") ? Int32(0) : FNM_PATHNAME
            return fnmatch(pattern, components.joined(separator: "/"), flags) == 0
        }
        return fnmatch(pattern, name, 0) == 0
    }
}

/// « Ce fichier est-il sauvegardé ? » (plan §6.4): the answer for a file
/// dropped on the window or picked in the Finder.
enum ForkMacBackupFileVerdict: Equatable {
    /// In the last snapshot of its source, as it is now.
    case backedUp(at: Date)
    /// In the last snapshot, changed on the Mac since.
    case modifiedSince(backedUpAt: Date, modified: Date?)
    /// Gone from the last snapshot: kept, not saved yet (a new file).
    case notYet(nextBackup: Date?)
    /// Left out by a rule of its source.
    case excluded(rule: String)
    /// In iCloud only, with the iCloud mode that does not download.
    case cloudOnly
    /// In none of the sources.
    case outsideSources
    /// No snapshot to look in (the engine is not reachable or none exists).
    case unknown

    /// Where the snapshot entry was found, if it was.
    struct Found: Equatable {
        var snapshotDate: Date
        var isDirectory: Bool
        var size: Int64?
        var modified: Date?
    }

    /// The deepest source that holds `path`.
    static func source(of path: String, in sources: [ForkMacBackupSource]) -> ForkMacBackupSource? {
        sources.filter { ForkMacBackupFolderPath.relative(path, to: $0.path) != nil }
            .max { $0.path.count < $1.path.count }
    }

    /// The answer, from what is known of the file and of its last snapshot.
    /// `lookedUp`: whether the snapshot could be read (false: `.unknown`
    /// unless a rule or iCloud already answers).
    static func decide(path: String, isDirectory: Bool, local: ForkMacBackupLocalStatus.LocalFacts?,
                       isCloudOnly: Bool, iCloud: ForkMacBackupICloudMode, sources: [ForkMacBackupSource],
                       found: Found?, lookedUp: Bool, nextBackup: Date?) -> ForkMacBackupFileVerdict {
        guard let source = source(of: path, in: sources),
              let relative = ForkMacBackupFolderPath.relative(path, to: source.path) else { return .outsideSources }
        if let rule = ForkMacBackupIgnoreRules.excludingRule(for: relative, isDirectory: isDirectory,
                                                              rules: source.ignoreRules) {
            return .excluded(rule: rule)
        }
        if let found {
            let status = ForkMacBackupLocalStatus.compare(isDirectory: found.isDirectory, size: found.size,
                                                          modified: found.modified, local: local)
            switch status {
            case .identical, .present, .unknown: return .backedUp(at: found.snapshotDate)
            case .modifiedSince, .deletedSince: return .modifiedSince(backedUpAt: found.snapshotDate, modified: local?.modified)
            }
        }
        if isCloudOnly && iCloud != .materialize { return .cloudOnly }
        return lookedUp ? .notYet(nextBackup: nextBackup) : .unknown
    }
}

/// The capacity measures of « Santé » (plan §7.4): each with its date and
/// its source, never one invented.
enum ForkMacBackupCapacitySupport {
    /// The samples of `kind` over the last `days` days, oldest first.
    static func series(_ samples: [ForkMacBackupCapacitySample], kind: ForkMacBackupCapacitySample.Kind, now: Date,
                       days: Int = 90) -> [ForkMacBackupCapacitySample] {
        let start = now.addingTimeInterval(-Double(days) * 86_400)
        return samples.filter { $0.kind == kind && $0.date >= start && $0.date <= now.addingTimeInterval(3_600) }
            .sorted { $0.date < $1.date }
    }

    /// The newest sample of `kind`; nil: « inconnu ».
    static func latest(_ samples: [ForkMacBackupCapacitySample], kind: ForkMacBackupCapacitySample.Kind)
        -> ForkMacBackupCapacitySample? {
        samples.filter { $0.kind == kind }.max { $0.date < $1.date }
    }

    /// Months until the free space is used at the repository's growth
    /// (least squares over `physical`); nil without two weeks of measures,
    /// without growth or without a known free space.
    static func monthsUntilFull(physical: [ForkMacBackupCapacitySample], free: Int64?) -> Double? {
        guard let free, free > 0, physical.count >= 3, let first = physical.first?.date,
              let last = physical.last?.date, last.timeIntervalSince(first) >= 14 * 86_400 else { return nil }
        let xs = physical.map { $0.date.timeIntervalSince(first) / 86_400 }
        let ys = physical.map { Double($0.bytes) }
        let meanX = xs.reduce(0, +) / Double(xs.count)
        let meanY = ys.reduce(0, +) / Double(ys.count)
        var covariance = 0.0
        var variance = 0.0
        for (x, y) in zip(xs, ys) {
            covariance += (x - meanX) * (y - meanY)
            variance += (x - meanX) * (x - meanX)
        }
        guard variance > 0 else { return nil }
        let bytesPerDay = covariance / variance
        guard bytesPerDay > 0 else { return nil }
        return Double(free) / bytesPerDay / 30.44
    }
}
