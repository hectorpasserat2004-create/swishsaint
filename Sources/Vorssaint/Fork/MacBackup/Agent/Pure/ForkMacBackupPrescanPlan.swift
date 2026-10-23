// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Darwin
import Foundation

/// What the last full walk of each source found (`MacBackup/prescan.json`,
/// machine state: never exported), so an agent that restarts, or a run a
/// few hours after the last one, does not walk the whole source again.
struct ForkMacBackupPrescanCache: Codable, Equatable {
    struct Entry: Codable, Equatable {
        /// When the full walk ended (an FSEvents refresh keeps it).
        var date: Date
        /// The source's rules and iCloud mode it was walked with.
        var fingerprint: String
        var sparseImages: [ForkMacBackupDiskUsage.SparseImage]
        /// Cloud-only entries, relative; a folder ends with « / ».
        var dataless: [String]
        /// What the cloud-only files announce (the download they would take).
        var datalessBytes: Int64
        /// Allocated bytes of what the source keeps, at the walk.
        var realBytes: Int64
        /// The FSEvents event at the start of the walk or of its last
        /// refresh: the next refresh needs every change since (nil: an
        /// older cache, walked again).
        var eventID: UInt64?

        init(date: Date, fingerprint: String, usage: ForkMacBackupDiskUsage, eventID: UInt64? = nil) {
            self.date = date
            self.fingerprint = fingerprint
            self.eventID = eventID
            sparseImages = usage.sparseImages
            dataless = usage.dataless
            datalessBytes = usage.datalessBytes
            realBytes = usage.allocatedBytes
        }

        var datalessFolders: Int { dataless.filter { $0.hasSuffix("/") }.count }
    }

    static let formatVersion = 1

    var formatVersion = Self.formatVersion
    /// By source path.
    var entries: [String: Entry] = [:]

    init(entries: [String: Entry] = [:]) {
        self.entries = entries
    }

    func encoded() -> Data? { try? ForkMacBackupJSON.encoder.encode(self) }

    /// A newer format is ignored (walked again), never misread. Keys are
    /// read in canonical form (build 2331 saved « /Users/me/ »).
    static func decode(_ data: Data) -> ForkMacBackupPrescanCache? {
        guard var cache = try? ForkMacBackupJSON.decoder.decode(ForkMacBackupPrescanCache.self, from: data),
              cache.formatVersion <= formatVersion else { return nil }
        var entries: [String: Entry] = [:]
        for (path, entry) in cache.entries {
            let key = ForkMacBackupSourcePath.normalized(path)
            if let kept = entries[key], kept.date >= entry.date { continue }
            entries[key] = entry
        }
        cache.entries = entries
        return cache
    }

    /// The entry of a source, whatever form its path takes.
    func entry(for path: String) -> Entry? {
        entries[ForkMacBackupSourcePath.normalized(path)]
    }
}

/// When the agent walks a source again before a run (plan §4.4, decision 1
/// of 22/10). A full walk is the only way to find a NEW sparse disk image
/// or cloud-only file anywhere, but it is heavy; in between, the files
/// FSEvents reported changed since the last run are looked at one by one
/// (an `lstat` each, no content read), which catches every image created
/// or grown and every file evicted, at the price of the changes only.
enum ForkMacBackupPrescanPlan {
    enum Choice: Equatable {
        case walk
        /// The cached walk, refreshed with the changed files.
        case reuse
    }

    /// One changed file as `lstat` sees it now; `exists` false: gone.
    struct Change: Equatable {
        var relativePath: String
        var exists: Bool
        var isRegularFile: Bool
        var logicalBytes: Int64
        var allocatedBytes: Int64
        var isDataless: Bool
    }

    /// What decides whether a cached walk still describes the source: its
    /// rules (the presets, sparse images included, and the free rules) and
    /// the iCloud mode.
    static func fingerprint(source: ForkMacBackupSource, iCloud: ForkMacBackupICloudMode) -> String {
        ([ForkMacBackupPreset.storageValue(source.presets), iCloud.rawValue] + source.customRules).joined(separator: "\n")
    }

    /// `changes`: the paths FSEvents saw change since the last run, nil when
    /// it could not count them (events dropped, too many): then only a walk
    /// is trusted.
    static func choose(cached: ForkMacBackupPrescanCache.Entry?, fingerprint: String, now: Date, onAC: Bool,
                       changesKnown: Bool) -> Choice {
        guard let cached, cached.fingerprint == fingerprint, changesKnown else { return .walk }
        let age = now.timeIntervalSince(cached.date)
        // A clock set back: the cache's age is unknown.
        guard age >= 0 else { return .walk }
        if age < ForkMacBackupAgentTuning.prescanLifetime { return .reuse }
        if !onAC && age < ForkMacBackupAgentTuning.prescanBatteryLifetime { return .reuse }
        return .walk
    }

    /// The absolute changed paths that lie in `source`, relative to it.
    static func relativeChanges(_ paths: [String], source: String) -> [String] {
        let root = ForkMacBackupSourcePath.normalized(source)
        let prefix = root == "/" ? "/" : root + "/"
        return paths.compactMap { $0.hasPrefix(prefix) ? String($0.dropFirst(prefix.count)) : nil }
            .filter { !$0.isEmpty }
    }

    /// The cached walk brought up to date with `changes`: a file that became
    /// a sparse image joins the list, one that stopped being one (filled,
    /// deleted) leaves it; with `collectDataless`, the same for cloud-only
    /// files (and their announced size). Paths the source's rules leave out
    /// are ignored. The walk's date and real size stay as measured.
    static func refreshed(_ entry: ForkMacBackupPrescanCache.Entry, changes: [Change],
                          matcher: ForkMacBackupIgnoreMatcher, collectDataless: Bool) -> ForkMacBackupPrescanCache.Entry {
        var entry = entry
        let changed = Set(changes.map(\.relativePath))
        entry.sparseImages.removeAll { changed.contains($0.relativePath) }
        var dataless = Set(entry.dataless)
        for change in changes {
            guard matcher.excludingRule(for: change.relativePath, isDirectory: false) == nil else {
                dataless.remove(change.relativePath)
                continue
            }
            let wasDataless = dataless.contains(change.relativePath)
            let isDataless = collectDataless && change.exists && change.isDataless
            if wasDataless && !isDataless {
                dataless.remove(change.relativePath)
                // Downloaded meanwhile (same announced size) or gone (size unknown).
                if change.exists { entry.datalessBytes = max(0, entry.datalessBytes - change.logicalBytes) }
            } else if isDataless && !wasDataless {
                dataless.insert(change.relativePath)
                entry.datalessBytes += change.logicalBytes
            }
            if change.exists, change.isRegularFile, !change.isDataless,
               ForkMacBackupContentScan.isSparseImage(logicalBytes: change.logicalBytes,
                                                      allocatedBytes: change.allocatedBytes) {
                entry.sparseImages.append(.init(relativePath: change.relativePath, logicalBytes: change.logicalBytes,
                                                allocatedBytes: change.allocatedBytes))
            }
        }
        entry.sparseImages.sort { $0.logicalBytes > $1.logicalBytes }
        entry.dataless = dataless.sorted()
        return entry
    }

    /// `lstat` of one changed path (metadata only, never its content).
    static func probe(_ relativePath: String, root: String) -> Change {
        let url = URL(fileURLWithPath: root, isDirectory: true).appendingPathComponent(relativePath, isDirectory: false)
        var info = stat()
        guard lstat(url.path, &info) == 0 else {
            return Change(relativePath: relativePath, exists: false, isRegularFile: false, logicalBytes: 0,
                          allocatedBytes: 0, isDataless: false)
        }
        let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
        let allocated = Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? Int(info.st_blocks) * 512)
        return Change(relativePath: relativePath, exists: true, isRegularFile: (info.st_mode & S_IFMT) == S_IFREG,
                      logicalBytes: Int64(info.st_size), allocatedBytes: allocated,
                      isDataless: ForkMacBackupContentScan.isDataless(flags: info.st_flags))
    }
}

/// « Tout télécharger avant » (plan §4.4): downloading the cloud-only files
/// before the snapshot must not fill the Mac. Refused, the run fails with
/// `localSpace` and says how much it would take; nothing is downloaded.
enum ForkMacBackupMaterializeCheck {
    /// The room kept free on top of the download: the agent's own floor, or
    /// a tenth of the download when that is more.
    static func margin(datalessBytes: Int64) -> Int64 {
        max(ForkMacBackupAgentTuning.minimumLocalFreeBytes, datalessBytes / 10)
    }

    /// nil: the download may go ahead. Otherwise the reason, for the run's
    /// error line (diagnostics, English). `freeBytes` nil: unknown, refused.
    /// A cloud-only FOLDER's content is unknown until listed: counted in
    /// the reason, not in the size.
    static func refusal(datalessBytes: Int64, datalessFolders: Int, freeBytes: Int64?) -> String? {
        guard datalessBytes > 0 || datalessFolders > 0 else { return nil }
        let needed = datalessBytes + margin(datalessBytes: datalessBytes)
        let folders = datalessFolders > 0 ? " and \(datalessFolders) cloud-only folder(s) of unknown size" : ""
        guard let freeBytes else {
            return "iCloud download refused: free space unknown (\(datalessBytes) bytes to download\(folders))"
        }
        guard freeBytes < needed else { return nil }
        return "iCloud download refused: \(datalessBytes) bytes to download\(folders) + \(needed - datalessBytes) "
            + "bytes margin, \(freeBytes) bytes free"
    }
}
