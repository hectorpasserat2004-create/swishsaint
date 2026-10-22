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

    /// The steps of a request; `exists` tells whether a path is taken (the
    /// folder-apart naming).
    static func steps(_ request: ForkMacBackupRestoreRequest, exists: (String) -> Bool) -> [Step] {
        var taken = Set<String>()
        return request.items.map { item in
            let relative = ForkMacBackupFailureList.normalize(item.relativePath)
            let name = relative.split(separator: "/").last.map(String.init) ?? displayName(request.sourcePath)
            switch request.destination {
            case .folder(let folder):
                var candidate = (folder as NSString).appendingPathComponent(name)
                var index = 2
                while exists(candidate) || taken.contains(candidate) {
                    candidate = (folder as NSString).appendingPathComponent(numbered(name, index))
                    index += 1
                }
                taken.insert(candidate)
                return Step(item: item, target: candidate, kind: .direct, overwrite: false)
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

    /// « report.pdf » → « report 2.pdf »; « Photos » → « Photos 2 ».
    static func numbered(_ name: String, _ index: Int) -> String {
        suffixed(name, " \(index)")
    }

    /// « report.pdf » + « (restauré) » → « report (restauré).pdf ».
    static func suffixed(_ name: String, _ suffix: String) -> String {
        let ns = name as NSString
        let ext = ns.pathExtension
        let base = ns.deletingPathExtension
        guard !ext.isEmpty, !base.isEmpty, !name.hasPrefix(".") || base.contains(".") else { return name + suffix }
        return base + suffix + "." + ext
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
    static func decision(rule: ForkMacBackupRestoreRequest.Overwrite, name: String, restored: FileFacts,
                         existing: FileFacts?, suffix: String, isTaken: (String) -> Bool) -> Decision {
        guard let existing else { return .move }
        let sameDate = abs(existing.modified.timeIntervalSince(restored.modified)) < 1
        switch rule {
        case .replaceAll:
            return .replace
        case .replaceIfOlder:
            return existing.modified < restored.modified && !sameDate ? .replace : .keep
        case .keepBoth:
            if existing.size == restored.size && sameDate { return .keep }
            var candidate = suffixed(name, " (\(suffix))")
            var index = 2
            while isTaken(candidate) {
                candidate = suffixed(name, " (\(suffix) \(index))")
                index += 1
            }
            return .moveRenamed(candidate)
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
