// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// Kopia has no « versions » command (plan §6.2): the engine walks the same
/// path in each snapshot of a source and keeps the DISTINCT contents, by
/// object ID. Unchanged folders keep their object ID across snapshots, so a
/// cache of folder listings by object ID makes the walk cheap.
enum ForkMacBackupVersionsPlan {
    /// `a/b/c.txt` → `["a", "b", "c.txt"]`; « » or « . » → `[]` (the root).
    static func components(_ relativePath: String) -> [String] {
        ForkMacBackupFailureList.normalize(relativePath).split(separator: "/").map(String.init)
    }

    /// The entry named `name` in a folder listing.
    static func entry(named name: String, in directory: ForkMacBackupKopia.DirectoryManifest) -> ForkMacBackupKopia.DirEntry? {
        directory.entries.first { $0.name == name }
    }

    /// One snapshot's finding for the path: its entry there, or nil when the
    /// path did not exist in it.
    struct Found: Equatable {
        var manifest: ForkMacBackupKopia.SnapshotManifest
        var entry: ForkMacBackupKopia.DirEntry?
    }

    /// The distinct versions, newest first: a snapshot whose entry has the
    /// object ID of a newer one is the same version, kept once under its
    /// NEWEST snapshot (the most recent proof it was still there).
    static func distinct(_ found: [Found]) -> [ForkMacBackupFileVersion] {
        let ordered = found.sorted { ($0.manifest.startDate ?? .distantPast) > ($1.manifest.startDate ?? .distantPast) }
        var seen = Set<String>()
        var versions: [ForkMacBackupFileVersion] = []
        for item in ordered {
            guard let entry = item.entry, let oid = entry.obj, !oid.isEmpty, seen.insert(oid).inserted else { continue }
            versions.append(ForkMacBackupFileVersion(manifestID: item.manifest.id,
                                                     snapshotTime: item.manifest.startDate ?? .distantPast,
                                                     objectID: oid,
                                                     size: entry.totalSize ?? 0,
                                                     modified: entry.modified))
        }
        return versions
    }

    /// The manifests of one source worth walking: complete ones, the path's
    /// own source (Kopia also lists a parent source's, SPIKES §4).
    static func manifests(of sourcePath: String,
                          in manifests: [ForkMacBackupKopia.SnapshotManifest]) -> [ForkMacBackupKopia.SnapshotManifest] {
        manifests.filter { $0.source?.path == sourcePath && $0.incomplete == nil && $0.rootEntry?.obj != nil }
    }
}

/// The server's snapshot list (`GET /api/v1/snapshots`) in the shape of the
/// CLI's manifests, so both engines hand the same type.
enum ForkMacBackupSnapshotMapping {
    static func manifest(_ snapshot: ForkMacBackupKopia.APISnapshot,
                         source: ForkMacBackupKopia.SourceInfo) -> ForkMacBackupKopia.SnapshotManifest? {
        var root: [String: Any] = ["type": "d", "name": (source.path.map { ($0 as NSString).lastPathComponent }) ?? ""]
        if let rootID = snapshot.rootID { root["obj"] = rootID }
        if let summary = snapshot.summary {
            var summ: [String: Any] = [:]
            if let size = summary.size { summ["size"] = size }
            if let files = summary.files { summ["files"] = files }
            if let dirs = summary.dirs { summ["dirs"] = dirs }
            if let failed = summary.numFailed { summ["numFailed"] = failed }
            if let ignored = summary.numIgnoredErrors { summ["numIgnoredErrors"] = ignored }
            if let maxTime = summary.maxTime { summ["maxTime"] = maxTime }
            summ["errors"] = summary.errors.map { error -> [String: String] in
                var item: [String: String] = [:]
                if let path = error.path { item["path"] = path }
                if let text = error.error { item["error"] = text }
                return item
            }
            root["summ"] = summ
        }
        var object: [String: Any] = ["id": snapshot.id, "rootEntry": root]
        var sourceObject: [String: Any] = [:]
        if let host = source.host { sourceObject["host"] = host }
        if let user = source.userName { sourceObject["userName"] = user }
        if let path = source.path { sourceObject["path"] = path }
        object["source"] = sourceObject
        if let text = snapshot.description { object["description"] = text }
        if let start = snapshot.startTime { object["startTime"] = start }
        if let end = snapshot.endTime { object["endTime"] = end }
        if let reason = snapshot.incompleteReason, !reason.isEmpty { object["incomplete"] = reason }
        if let size = snapshot.summary?.size {
            object["stats"] = ["totalSize": size, "fileCount": snapshot.summary?.files ?? 0,
                               "errorCount": snapshot.summary?.numFailed ?? 0] as [String: Any]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
        return ForkMacBackupKopia.decode(ForkMacBackupKopia.SnapshotManifest.self, from: data)
    }
}
