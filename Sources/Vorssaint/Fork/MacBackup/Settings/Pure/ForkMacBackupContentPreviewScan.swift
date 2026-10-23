// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

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

    /// A file that announces far more than it holds (Docker.raw, an `.ext4`,
    /// a VM clone).
    struct SparseFile: Codable, Equatable, Identifiable {
        /// For display, `~/…`.
        var path: String
        var logicalBytes: Int64
        var allocatedBytes: Int64
        /// The real path, the key of « Laisser de côté » (nil in an older cache).
        var absolutePath: String?
        /// Docker Desktop's or Apple Container's: left out with the preset.
        var recreatable: Bool?

        var id: String { path }
        var isRecreatable: Bool { recreatable ?? ForkMacBackupSparsePolicy.isRecreatable(absolutePath ?? path) }

        init(path: String, logicalBytes: Int64, allocatedBytes: Int64, absolutePath: String? = nil,
             recreatable: Bool? = nil) {
            self.path = path
            self.logicalBytes = logicalBytes
            self.allocatedBytes = allocatedBytes
            self.absolutePath = absolutePath
            self.recreatable = recreatable
        }
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
    /// One sparse image that is not recreatable: kept unless left out by name.
    static func sparseID(_ absolutePath: String) -> String { "sparse:" + absolutePath }
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

/// « Aperçu »: walks the sources once with the engine's walker
/// (`ForkMacBackupContentScan.walk`, real sizes, cloud-only folders never
/// entered) and measures EVERY rule, on or off, with the engine's rule
/// matcher and sparse-image test. Foundation only, on the caller's queue
/// (a utility one), cancellable.
enum ForkMacBackupContentScanner {
    struct Settings {
        var presets: [ForkMacBackupPreset]
        var customRules: [String]
        var iCloud: ForkMacBackupICloudMode
        /// Sparse images left out by name (absolute paths).
        var sparseExcluded: Set<String>
        /// Decision 1 of 22/10: ≥ 10 GB announced, less than half written
        /// (smaller in the tests only).
        var sparseMinimum: Int64

        init(presets: [ForkMacBackupPreset], customRules: [String], iCloud: ForkMacBackupICloudMode,
             sparseExcluded: Set<String> = [],
             sparseMinimum: Int64 = ForkMacBackupContentScan.sparseMinimumLogicalBytes) {
            self.presets = presets
            self.customRules = customRules
            self.iCloud = iCloud
            self.sparseExcluded = sparseExcluded
            self.sparseMinimum = sparseMinimum
        }
    }

    struct Progress: Equatable {
        var files: Int64
        var bytes: Int64
        var path: String
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

        // The walker hands resolved paths (/var → /private/var): both
        // spellings of the home are recognised.
        let homes = Set([home, ForkMacBackupContentScan.realPath(home)])
        func display(_ path: String) -> String {
            for candidate in homes where path.hasPrefix(candidate + "/") { return "~" + path.dropFirst(candidate.count) }
            return path
        }

        for source in sources {
            let root = URL(fileURLWithPath: source, isDirectory: true).standardizedFileURL
            let rootPath = root.path
            // The groups each open folder level hands down to its contents.
            var inherited: [Set<String>] = [[]]
            let walked = ForkMacBackupContentScan.walk(root: root, isCanceled: {
                seen += 1
                guard seen % 2_000 == 0 else { return false }
                return isCancelled()
            }) { entry in
                if seen % 2_000 == 0 { progress?(Progress(files: seen, bytes: included + excluded, path: entry.url.path)) }
                let level = entry.depth
                guard level >= 1 else { return .enter }
                if inherited.count > level { inherited.removeLast(inherited.count - level) }
                var groups = inherited.last ?? []
                for matcher in matchers where !groups.contains(matcher.id) {
                    var hit = matcher.rules.contains {
                        $0.matches(relativePath: entry.relativePath, name: entry.name, depth: level, isDirectory: entry.isDirectory)
                    }
                    if !hit, matcher.usesCacheTag, entry.isDirectory {
                        hit = FileManager.default.fileExists(atPath: entry.url.path + "/CACHEDIR.TAG")
                    }
                    guard hit else { continue }
                    groups.insert(matcher.id)
                    var tally = tallies[matcher.id] ?? Tally()
                    tally.matches += 1
                    if tally.examples.count < 5 { tally.examples.append(display(rootPath + "/" + entry.relativePath)) }
                    tallies[matcher.id] = tally
                }
                if entry.isDirectory {
                    while inherited.count <= level { inherited.append([]) }
                    inherited[level] = groups
                    return .enter
                }

                let allocated = entry.allocatedBytes
                let logical = entry.logicalBytes
                if !entry.isSymbolicLink, entry.relativePath.hasPrefix("Library/Mobile Documents/"), entry.isDataless {
                    cloudOnlyFiles += 1
                    cloudOnlyBytes += logical
                }
                if entry.isRegularFile, logical >= settings.sparseMinimum, allocated * 2 < logical {
                    // Only Docker's and Apple Container's go with the preset;
                    // any other one is real data, kept unless left out by name.
                    let absolute = ForkMacBackupSparsePolicy.absolutePath(entry.relativePath, in: source)
                    let recreatable = ForkMacBackupSparsePolicy.isRecreatable(absolute)
                    sparse.append(.init(path: display(rootPath + "/" + entry.relativePath), logicalBytes: logical,
                                        allocatedBytes: allocated, absolutePath: absolute, recreatable: recreatable))
                    let id = recreatable ? sparseID : ForkMacBackupContentPreview.sparseID(absolute)
                    groups.insert(id)
                    var tally = tallies[id] ?? Tally()
                    tally.matches += 1
                    if tally.examples.count < 5 { tally.examples.append(display(rootPath + "/" + entry.relativePath)) }
                    tallies[id] = tally
                }
                for id in groups {
                    tallies[id, default: Tally()].bytes += allocated
                    tallies[id, default: Tally()].files += 1
                }
                let isExcluded = groups.contains { id in
                    if id == sparseID { return sparseActive }
                    if id.hasPrefix("sparse:") { return settings.sparseExcluded.contains(String(id.dropFirst(7))) }
                    return matchers.first { $0.id == id }?.active ?? false
                }
                if isExcluded {
                    excluded += allocated
                    excludedFiles += 1
                } else {
                    included += allocated
                    includedFiles += 1
                    let components = entry.relativePath.split(separator: "/", maxSplits: 2)
                    if components.count >= 2 {
                        firstLevel[display(rootPath + "/" + components[0]), default: 0] += allocated
                    }
                    if components.count >= 3 {
                        secondLevel[display(rootPath + "/" + components[0] + "/" + components[1]), default: 0] += allocated
                    }
                }
                return .enter
            }
            unreadable += Int(walked.unreadable)
            if walked.canceled {
                complete = false
                break
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
}
