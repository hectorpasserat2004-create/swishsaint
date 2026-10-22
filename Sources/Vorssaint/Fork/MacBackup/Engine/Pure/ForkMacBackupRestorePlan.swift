// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// What a restore does, decided before any byte moves (plan §6.3).
///
/// - Kopia is always asked for a FULL restore of `<snapshot>/<path>` (the
///   server's default is shallow: placeholders only, SPIKES §2.7), sparse
///   files kept sparse, owners skipped when asked, never atomic writes.
/// - « Into a folder apart »: each item lands in that folder under its own
///   name, never over something already there (« name 2 »).
/// - « Where they came from » with « replace all »: Kopia overwrites.
/// - « Keep both » and « replace if older » do not exist in Kopia: the
///   engine restores into a staging folder, then moves each file by the
///   rule (`decision`).
enum ForkMacBackupRestorePlan {
    /// `manifestID/relative/path`, as Kopia's restore takes a root: a path
    /// below a snapshot keeps the entry's own mode and date (a bare folder
    /// object would come back `dr-xr-xr-x` dated 1970, SPIKES §4).
    static func rootReference(manifestID: String, relativePath: String) -> String {
        let path = ForkMacBackupFailureList.normalize(relativePath)
        return path.isEmpty ? manifestID : manifestID + "/" + path
    }

    /// Kopia's restore depth limits: the whole tree, no placeholder.
    static let fullDepth = Int32.max

    /// How Kopia itself is asked to write.
    struct KopiaMode: Equatable {
        var overwrite: Bool
        var skipOwners: Bool
        var ignorePermissionErrors: Bool
    }

    /// `POST /api/v1/restore`'s body.
    static func apiRequest(root: String, target: String, mode: KopiaMode) -> [String: Any] {
        [
            "root": root,
            "fsOutput": [
                "targetPath": target,
                "overwriteFiles": mode.overwrite,
                "overwriteDirectories": true,
                "overwriteSymlinks": mode.overwrite,
                "ignorePermissionErrors": mode.ignorePermissionErrors,
                "writeFilesAtomically": false,
                "skipOwners": mode.skipOwners,
                "skipPermissions": false,
                "skipTimes": false,
                "writeSparseFiles": true,
            ] as [String: Any],
            "options": [
                "incremental": false,
                "deleteExtra": false,
                "ignoreErrors": false,
                "restoreDirEntryAtDepth": fullDepth,
                "minSizeForPlaceholder": fullDepth,
            ] as [String: Any],
        ]
    }

    // MARK: Destinations

    /// Where one item goes and how.
    struct Step: Equatable {
        enum Kind: Equatable {
            /// Kopia writes straight to `target`.
            case direct
            /// Kopia writes to a staging folder; the engine then merges into
            /// `target` by `rule`.
            case staged(ForkMacBackupRestoreRequest.Overwrite)
        }

        var item: ForkMacBackupRestoreRequest.Item
        var target: String
        var kind: Kind
        var overwrite: Bool
    }

    /// The steps of a request; `exists` tells whether a path is taken.
    /// Into a folder apart, each item lands at `<folder>/<name>`, beside
    /// what is already there under the « keep both » name (`word`:
    /// « restauré »), never over it nor over another item.
    static func steps(_ request: ForkMacBackupRestoreRequest, word: String, exists: (String) -> Bool) -> [Step] {
        var taken = Set<String>()
        return request.items.map { item in
            let relative = ForkMacBackupFailureList.normalize(item.relativePath)
            let name = relative.split(separator: "/").last.map(String.init) ?? displayName(request.sourcePath)
            switch request.destination {
            case .folder(let folder):
                let free = ForkMacBackupRestoreNaming.keepBothName(name, isDirectory: item.isDirectory, word: word) { candidate in
                    let path = (folder as NSString).appendingPathComponent(candidate)
                    return exists(path) || taken.contains(path)
                }
                let target = (folder as NSString).appendingPathComponent(free)
                taken.insert(target)
                return Step(item: item, target: target, kind: .direct, overwrite: false)
            case .original(let rule):
                let target = relative.isEmpty ? request.sourcePath
                    : (request.sourcePath as NSString).appendingPathComponent(relative)
                switch rule {
                case .replaceAll:
                    return Step(item: item, target: target, kind: .direct, overwrite: true)
                case .keepBoth, .replaceIfOlder:
                    return Step(item: item, target: target, kind: .staged(rule), overwrite: false)
                }
            }
        }
    }

    private static func displayName(_ path: String) -> String {
        let name = (path as NSString).lastPathComponent
        return name.isEmpty ? "Backup" : name
    }

    // MARK: Merging a staged restore

    /// What is known of one file on each side.
    struct FileFacts: Equatable {
        var size: Int64
        var modified: Date
    }

    enum Decision: Equatable {
        /// Nothing there: move the restored file in.
        case move
        /// Replace what is there.
        case replace
        /// Keep what is there, drop the restored copy.
        case keep
        /// Both stay: the restored one under `name`.
        case moveRenamed(String)
    }

    /// The rule for one file. `existing` nil: nothing at the target.
    /// « Replace if older » keeps a local file at least as recent as the
    /// backup's; « keep both » leaves an identical file alone (same size,
    /// same date to the second) and renames the restored copy otherwise.
    static func decision(rule: ForkMacBackupRestoreRequest.Overwrite, name: String, isDirectory: Bool = false,
                         restored: FileFacts, existing: FileFacts?, suffix: String,
                         isTaken: (String) -> Bool) -> Decision {
        guard let existing else { return .move }
        let sameDate = abs(existing.modified.timeIntervalSince(restored.modified)) < 1
        switch rule {
        case .replaceAll:
            return .replace
        case .replaceIfOlder:
            return existing.modified < restored.modified && !sameDate ? .replace : .keep
        case .keepBoth:
            if existing.size == restored.size && sameDate { return .keep }
            // The name is taken by the file kept: the restored one goes beside it.
            return .moveRenamed(ForkMacBackupRestoreNaming.keepBothName(name, isDirectory: isDirectory, word: suffix) {
                $0 == name || isTaken($0)
            })
        }
    }

    // MARK: Sample restore test

    /// `count` files of `candidates` picked at random by `generator`,
    /// spread over sizes: half from the smaller half, half from the larger
    /// (a sample of only tiny files proves little, plan §7.1).
    static func sample<Candidate, Generator: RandomNumberGenerator>(
        _ candidates: [Candidate], count: Int, size: (Candidate) -> Int64, using generator: inout Generator
    ) -> [Candidate] {
        guard count > 0, !candidates.isEmpty else { return [] }
        guard candidates.count > count else { return candidates.shuffled(using: &generator) }
        let sorted = candidates.sorted { size($0) < size($1) }
        let half = sorted.count / 2
        let small = Array(sorted[..<half]).shuffled(using: &generator)
        let large = Array(sorted[half...]).shuffled(using: &generator)
        let fromLarge = min(large.count, (count + 1) / 2)
        let fromSmall = min(small.count, count - fromLarge)
        var picked = Array(large.prefix(fromLarge)) + Array(small.prefix(fromSmall))
        if picked.count < count {
            picked += Array(large.dropFirst(fromLarge).prefix(count - picked.count))
        }
        return picked
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
