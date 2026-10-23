// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// « Modifications non protégées » (plan §5.5): which changed paths count,
/// how much, and how many. Pure: the FSEvents stream feeds it paths; the
/// file contents are never read.
enum ForkMacBackupPendingChanges {
    enum Weight: Hashable {
        /// Documents and Desktop of a home folder.
        case important
        case ordinary
        /// `Library/`: counted, weighs little.
        case library

        var value: Double {
            switch self {
            case .important: return ForkMacBackupAgentTuning.importantWeight
            case .ordinary: return ForkMacBackupAgentTuning.ordinaryWeight
            case .library: return ForkMacBackupAgentTuning.libraryWeight
            }
        }
    }

    /// One Kopia ignore rule (gitignore syntax, relative to the source):
    /// a leading `/` or a middle `/` anchors it at the source's root, a
    /// trailing `/` names a folder and all it holds, `*` and `?` match
    /// within one name.
    struct Rule: Equatable {
        var components: [String]
        var anchored: Bool

        init?(_ pattern: String) {
            var text = pattern.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty, !text.hasPrefix("#"), !text.hasPrefix("!") else { return nil }
            if text.hasSuffix("/") { text.removeLast() }
            let leading = text.hasPrefix("/")
            components = text.split(separator: "/").map(String.init)
            guard !components.isEmpty else { return nil }
            anchored = leading || components.count > 1
        }

        func matches(_ relative: [String]) -> Bool {
            guard relative.count >= components.count else { return false }
            if anchored { return Self.prefixMatches(components, Array(relative.prefix(components.count))) }
            for start in 0...(relative.count - components.count) {
                let window = Array(relative[start..<(start + components.count)])
                if Self.prefixMatches(components, window) { return true }
            }
            return false
        }

        private static func prefixMatches(_ patterns: [String], _ names: [String]) -> Bool {
            zip(patterns, names).allSatisfy { pattern, name in
                if !pattern.contains("*") && !pattern.contains("?") && !pattern.contains("[") { return pattern == name }
                return fnmatch(pattern, name, 0) == 0
            }
        }
    }

    /// What one source's events are matched against.
    struct Filter: Equatable {
        var sourcePath: String
        var rules: [Rule]
        var home: String
        /// Paths never counted: the feature's own folder, the Kopia cache.
        var ignoredPrefixes: [String]

        init(source: ForkMacBackupSource, extraRules: [String] = [], home: String, ignoredPrefixes: [String] = []) {
            sourcePath = Self.normalized(source.path)
            rules = (source.ignoreRules + extraRules).compactMap(Rule.init)
            self.home = Self.normalized(home)
            self.ignoredPrefixes = ignoredPrefixes.map(Self.normalized)
        }

        /// nil: not counted (outside the source, excluded, or noise).
        func weight(of path: String) -> Weight? {
            let path = Self.normalized(path)
            guard path == sourcePath || path.hasPrefix(sourcePath + "/") else { return nil }
            if ignoredPrefixes.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) { return nil }
            let relative = path == sourcePath ? [] : path.dropFirst(sourcePath.count + 1).split(separator: "/").map(String.init)
            if relative.last == ".DS_Store" { return nil }
            if rules.contains(where: { $0.matches(relative) }) { return nil }
            guard path.hasPrefix(home + "/") else { return .ordinary }
            let fromHome = path.dropFirst(home.count + 1)
            if ForkMacBackupAgentTuning.importantFolders.contains(where: { fromHome == $0 || fromHome.hasPrefix($0 + "/") }) {
                return .important
            }
            if fromHome == "Library" || fromHome.hasPrefix("Library/") { return .library }
            return .ordinary
        }

        static func normalized(_ path: String) -> String {
            var path = path
            while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
            return path
        }
    }

    /// The distinct changed paths, each with the last event that touched
    /// it, so a complete snapshot clears only what it saw.
    struct Tally: Equatable {
        struct Entry: Equatable {
            var weight: Weight
            var eventID: UInt64
        }

        private(set) var entries: [String: Entry] = [:]
        /// Past the cap, changes are counted without their path.
        private(set) var overflow: [Weight: Int] = [:]
        /// The event from which `entries` holds EVERY changed path (the
        /// pre-scan's refresh needs the whole list since its last walk or
        /// refresh); nil: from nowhere yet. Moves forward at each loss:
        /// dropped events, a path past the cap, a clear, a reset.
        private(set) var pathsKnownSince: UInt64?

        mutating func add(_ path: String, weight: Weight, eventID: UInt64) {
            if entries[path] != nil || entries.count < ForkMacBackupAgentTuning.pendingPathCap {
                entries[path] = Entry(weight: weight, eventID: eventID)
            } else {
                overflow[weight, default: 0] += 1
                lostPaths(at: eventID)
            }
        }

        /// A complete snapshot that started at `eventID` protects every
        /// change up to it.
        mutating func reset(upTo eventID: UInt64) {
            entries = entries.filter { $0.value.eventID > eventID }
            overflow = [:]
            if let known = pathsKnownSince { pathsKnownSince = max(known, eventID) }
        }

        /// Everything forgotten; `eventID`: the event the list starts again from.
        mutating func clear(from eventID: UInt64? = nil) {
            entries = [:]
            overflow = [:]
            pathsKnownSince = eventID
        }

        /// Paths were missed up to `eventID` (events dropped, the cap).
        mutating func lostPaths(at eventID: UInt64) {
            pathsKnownSince = max(pathsKnownSince ?? eventID, eventID)
        }

        /// Every path changed after `eventID` (and those changed a little
        /// before: FSEvents delivers late, a superset costs an `lstat` each),
        /// or nil when the list may miss one (a loss since then, no start yet).
        func changedPaths(since eventID: UInt64) -> [String]? {
            guard let known = pathsKnownSince, known <= eventID else { return nil }
            return entries.keys.sorted()
        }

        /// Changes counted without their path (past `pendingPathCap`).
        var overflowCount: Int { overflow.values.reduce(0, +) }

        var summary: ForkMacBackupPendingSummary {
            var counts: [Weight: Int] = overflow
            for entry in entries.values { counts[entry.weight, default: 0] += 1 }
            let total = counts.values.reduce(0, +)
            let weighted = counts.reduce(0.0) { $0 + Double($1.value) * $1.key.value }
            return ForkMacBackupPendingSummary(total: total, important: counts[.important] ?? 0, weighted: weighted)
        }
    }

    /// `MacBackup/pending.json`: where the count starts. FSEvents keeps its
    /// history on disk, so the stream replays from here after a restart.
    struct File: Codable, Equatable {
        static let formatVersion = 1

        var formatVersion: Int
        /// The event at the start of the last complete snapshot.
        var sinceEventID: UInt64?
        var since: Date?
        /// The last summary, for display while the replay runs.
        var total: Int?
        var important: Int?
        var updatedAt: Date

        init(sinceEventID: UInt64?, since: Date?, total: Int? = nil, important: Int? = nil, updatedAt: Date) {
            formatVersion = Self.formatVersion
            self.sinceEventID = sinceEventID
            self.since = since
            self.total = total
            self.important = important
            self.updatedAt = updatedAt
        }

        static func decode(_ data: Data) -> File? {
            guard let file = try? ForkMacBackupJSON.decoder.decode(File.self, from: data),
                  file.formatVersion <= formatVersion else { return nil }
            return file
        }
    }

    /// The event ID to replay from: the saved one when it is still in the
    /// system's history (not past the current ID, which a reset of the
    /// event database would make it), else nil (count from now, unknown
    /// until the next complete snapshot).
    static func replayStart(saved: UInt64?, current: UInt64) -> UInt64? {
        guard let saved, saved > 0, saved <= current else { return nil }
        return saved
    }
}
