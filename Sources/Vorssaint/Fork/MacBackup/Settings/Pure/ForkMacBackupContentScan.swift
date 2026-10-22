// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Darwin
import Foundation

/// One ignore rule, in Kopia's gitignore syntax, relative to a source's
/// root: `name` matches at any depth, `/name` only at the root, `a/b` from
/// the root too, a trailing `/` only folders, `*` and `?` as in the shell.
struct ForkMacBackupIgnoreRule: Equatable {
    let text: String
    let pattern: String
    let anchored: Bool
    let directoryOnly: Bool
    /// For an anchored rule: how many path components it spans.
    let depth: Int
    let crossesFolders: Bool

    init?(_ text: String) {
        var pattern = text.trimmingCharacters(in: .whitespaces)
        guard !pattern.isEmpty, !pattern.hasPrefix("#"), !pattern.hasPrefix("!") else { return nil }
        self.text = pattern
        directoryOnly = pattern.hasSuffix("/")
        while pattern.hasSuffix("/") { pattern.removeLast() }
        var anchored = false
        if pattern.hasPrefix("/") {
            anchored = true
            while pattern.hasPrefix("/") { pattern.removeFirst() }
        }
        if pattern.hasPrefix("**/") {
            pattern.removeFirst(3)
            anchored = false
        }
        if pattern.contains("/") { anchored = true }
        guard !pattern.isEmpty else { return nil }
        self.pattern = pattern
        self.anchored = anchored
        crossesFolders = pattern.contains("**")
        depth = pattern.split(separator: "/").count
    }

    /// `relativePath` has no leading slash; `name` is its last component.
    func matches(relativePath: String, name: String, depth pathDepth: Int, isDirectory: Bool) -> Bool {
        if directoryOnly && !isDirectory { return false }
        if anchored {
            if crossesFolders { return fnmatch(pattern, relativePath, 0) == 0 }
            guard pathDepth == depth else { return false }
            return fnmatch(pattern, relativePath, FNM_PATHNAME) == 0
        }
        return fnmatch(pattern, name, 0) == 0
    }
}

/// What « Aperçu » measured (plan §4.3): real sizes on disk only (decision 1
/// of 22/10), per preset and per free rule, whether on or off, so every
/// switch shows its own weight before it is touched.
struct ForkMacBackupContentPreview: Codable, Equatable {
    struct Group: Codable, Equatable {
        /// `preset:<raw value>`, `rule:<text>` or `icloud`.
        var id: String
        var bytes: Int64
        var files: Int64
        /// Folders or files the rule matched itself (not their contents).
        var matches: Int
        /// Up to five of them, `~/…`.
        var examples: [String]
    }

    /// A file that announces far more than it holds (Docker.raw, an `.ext4`).
    struct SparseFile: Codable, Equatable, Identifiable {
        var path: String
        var logicalBytes: Int64
        var allocatedBytes: Int64

        var id: String { path }
    }

    struct Folder: Codable, Equatable, Identifiable {
        var path: String
        var bytes: Int64

        var id: String { path }
    }

    static let formatVersion = 1

    var formatVersion: Int
    var sourcePaths: [String]
    var measuredAt: Date
    var duration: TimeInterval
    var includedBytes: Int64
    var includedFiles: Int64
    var excludedBytes: Int64
    var excludedFiles: Int64
    var groups: [Group]
    var sparse: [SparseFile]
    /// The biggest folders kept, first level, then second.
    var topFolders: [Folder]
    /// iCloud Drive files with no data on the Mac.
    var cloudOnlyFiles: Int64
    var cloudOnlyBytes: Int64
    var unreadable: Int
    /// False when it was stopped before the end.
    var complete: Bool

    static func presetID(_ preset: ForkMacBackupPreset) -> String { "preset:" + preset.rawValue }
    static func ruleID(_ rule: String) -> String { "rule:" + rule.trimmingCharacters(in: .whitespaces) }
    static let iCloudID = "icloud"

    func group(_ preset: ForkMacBackupPreset) -> Group? { groups.first { $0.id == Self.presetID(preset) } }
    func group(rule: String) -> Group? { groups.first { $0.id == Self.ruleID(rule) } }

    /// The files a sparse image announces beyond what it holds.
    var sparseAnnouncedBytes: Int64 { sparse.reduce(0) { $0 + $1.logicalBytes } }
    var sparseRealBytes: Int64 { sparse.reduce(0) { $0 + $1.allocatedBytes } }

    static func decode(_ data: Data) -> ForkMacBackupContentPreview? {
        guard let value = try? ForkMacBackupJSON.decoder.decode(Self.self, from: data),
              value.formatVersion <= formatVersion else { return nil }
        return value
    }
}

/// Walks the sources once and measures every rule (plan §4.3). Foundation
/// only, on the caller's queue (a utility one), cancellable.
enum ForkMacBackupContentScanner {
    struct Settings {
        var presets: [ForkMacBackupPreset]
        var customRules: [String]
        var iCloud: ForkMacBackupICloudMode
        /// Decision 1 of 22/10: ≥ 10 GB announced, less than half written.
        var sparseMinimum: Int64 = 10_000_000_000

        init(presets: [ForkMacBackupPreset], customRules: [String], iCloud: ForkMacBackupICloudMode,
             sparseMinimum: Int64 = 10_000_000_000) {
            self.presets = presets
            self.customRules = customRules
            self.iCloud = iCloud
            self.sparseMinimum = sparseMinimum
        }
    }

    struct Progress: Equatable {
        var files: Int64
        var bytes: Int64
        var path: String
    }

    /// A file is a sparse disk image when it announces at least `minimum`
    /// and holds less than half of it.
    static func isSparse(logical: Int64, allocated: Int64, minimum: Int64) -> Bool {
        logical >= minimum && allocated * 2 < logical
    }

    private struct Matcher {
        let id: String
        let rules: [ForkMacBackupIgnoreRule]
        let active: Bool
        let usesCacheTag: Bool
    }

    private struct Tally {
        var bytes: Int64 = 0
        var files: Int64 = 0
        var matches = 0
        var examples: [String] = []
    }

    static func scan(sources: [String], settings: Settings, home: String = NSHomeDirectory(), now: Date = Date(),
                     isCancelled: () -> Bool = { false },
                     progress: ((Progress) -> Void)? = nil) -> ForkMacBackupContentPreview {
        let started = Date()
        var matchers = ForkMacBackupPreset.allCases.map { preset in
            Matcher(id: ForkMacBackupContentPreview.presetID(preset),
                    rules: preset.patterns.compactMap(ForkMacBackupIgnoreRule.init),
                    active: settings.presets.contains(preset), usesCacheTag: preset == .cacheDirTag)
        }
        for rule in settings.customRules {
            guard let parsed = ForkMacBackupIgnoreRule(rule) else { continue }
            matchers.append(Matcher(id: ForkMacBackupContentPreview.ruleID(rule), rules: [parsed], active: true,
                                    usesCacheTag: false))
        }
        matchers.append(Matcher(id: ForkMacBackupContentPreview.iCloudID,
                                rules: [ForkMacBackupIgnoreRule("/Library/Mobile Documents/")].compactMap { $0 },
                                active: settings.iCloud == .exclude, usesCacheTag: false))
        let sparseID = ForkMacBackupContentPreview.presetID(.sparseDiskImages)
        let sparseActive = settings.presets.contains(.sparseDiskImages)

        var tallies: [String: Tally] = [:]
        var included: Int64 = 0
        var includedFiles: Int64 = 0
        var excluded: Int64 = 0
        var excludedFiles: Int64 = 0
        var sparse: [ForkMacBackupContentPreview.SparseFile] = []
        var firstLevel: [String: Int64] = [:]
        var secondLevel: [String: Int64] = [:]
        var cloudOnlyFiles: Int64 = 0
        var cloudOnlyBytes: Int64 = 0
        var unreadable = 0
        var seen: Int64 = 0
        var complete = true

        func display(_ path: String) -> String {
            path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
        }

        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey,
                                      .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey]
        outer: for source in sources {
            let root = URL(fileURLWithPath: source, isDirectory: true).standardizedFileURL
            let rootPath = root.path
            guard let enumerator = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: keys, options: [],
                errorHandler: { _, _ in
                    unreadable += 1
                    return true
                }) else { continue }
            // The groups each open folder level hands down to its contents.
            var inherited: [Set<String>] = [[]]
            for case let url as URL in enumerator {
                seen += 1
                if seen % 2_000 == 0 {
                    if isCancelled() {
                        complete = false
                        break outer
                    }
                    progress?(Progress(files: seen, bytes: included + excluded, path: url.path))
                }
                let level = enumerator.level
                guard level >= 1 else { continue }
                let path = url.path
                guard path.hasPrefix(rootPath + "/") else { continue }
                let relative = String(path.dropFirst(rootPath.count + 1))
                let name = url.lastPathComponent
                guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
                let isLink = values.isSymbolicLink ?? false
                let isDirectory = (values.isDirectory ?? false) && !isLink

                if inherited.count > level { inherited.removeLast(inherited.count - level) }
                var groups = inherited.last ?? []
                for matcher in matchers where !groups.contains(matcher.id) {
                    var hit = matcher.rules.contains {
                        $0.matches(relativePath: relative, name: name, depth: level, isDirectory: isDirectory)
                    }
                    if !hit, matcher.usesCacheTag, isDirectory {
                        hit = FileManager.default.fileExists(atPath: path + "/CACHEDIR.TAG")
                    }
                    guard hit else { continue }
                    groups.insert(matcher.id)
                    var tally = tallies[matcher.id] ?? Tally()
                    tally.matches += 1
                    if tally.examples.count < 5 { tally.examples.append(display(path)) }
                    tallies[matcher.id] = tally
                }
                if isDirectory {
                    while inherited.count <= level { inherited.append([]) }
                    inherited[level] = groups
                    continue
                }

                let allocated = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
                let logical = Int64(values.fileSize ?? 0)
                if !isLink, relative.hasPrefix("Library/Mobile Documents/"), isDataless(path) {
                    cloudOnlyFiles += 1
                    cloudOnlyBytes += logical
                }
                if !isLink, isSparse(logical: logical, allocated: allocated, minimum: settings.sparseMinimum) {
                    sparse.append(.init(path: display(path), logicalBytes: logical, allocatedBytes: allocated))
                    groups.insert(sparseID)
                    var tally = tallies[sparseID] ?? Tally()
                    tally.matches += 1
                    if tally.examples.count < 5 { tally.examples.append(display(path)) }
                    tallies[sparseID] = tally
                }
                for id in groups {
                    tallies[id, default: Tally()].bytes += allocated
                    tallies[id, default: Tally()].files += 1
                }
                let isExcluded = groups.contains { id in
                    id == sparseID ? sparseActive : (matchers.first { $0.id == id }?.active ?? false)
                }
                if isExcluded {
                    excluded += allocated
                    excludedFiles += 1
                } else {
                    included += allocated
                    includedFiles += 1
                    let components = relative.split(separator: "/", maxSplits: 2)
                    if components.count >= 2 {
                        firstLevel[display(rootPath + "/" + components[0]), default: 0] += allocated
                    }
                    if components.count >= 3 {
                        secondLevel[display(rootPath + "/" + components[0] + "/" + components[1]), default: 0] += allocated
                    }
                }
            }
        }

        let groups = tallies.map { id, tally in
            ForkMacBackupContentPreview.Group(id: id, bytes: tally.bytes, files: tally.files, matches: tally.matches,
                                              examples: tally.examples)
        }.sorted { $0.id < $1.id }
        func top(_ folders: [String: Int64], _ count: Int) -> [ForkMacBackupContentPreview.Folder] {
            folders.map { ForkMacBackupContentPreview.Folder(path: $0.key, bytes: $0.value) }
                .sorted { ($0.bytes, $1.path) > ($1.bytes, $0.path) }
                .prefix(count).map { $0 }
        }
        return ForkMacBackupContentPreview(
            formatVersion: ForkMacBackupContentPreview.formatVersion, sourcePaths: sources, measuredAt: now,
            duration: Date().timeIntervalSince(started), includedBytes: included, includedFiles: includedFiles,
            excludedBytes: excluded, excludedFiles: excludedFiles, groups: groups,
            sparse: sparse.sorted { $0.logicalBytes > $1.logicalBytes },
            topFolders: top(firstLevel, 8) + top(secondLevel, 8), cloudOnlyFiles: cloudOnlyFiles,
            cloudOnlyBytes: cloudOnlyBytes, unreadable: unreadable, complete: complete)
    }

    /// An iCloud file with no data on the Mac (`SF_DATALESS`).
    static func isDataless(_ path: String) -> Bool {
        var info = stat()
        guard lstat(path, &info) == 0 else { return false }
        return info.st_flags & 0x4000_0000 != 0
    }
}
