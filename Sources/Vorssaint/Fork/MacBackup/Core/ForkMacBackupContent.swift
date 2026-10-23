// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// A named, counted exclusion the person ticks (plan §4.2). On = excluded,
/// except where `isExclusion` is false. Raw values are stored (presets list
/// of `fork.macbackup.presets`, profiles, `Source.presets`): never rename one.
enum ForkMacBackupPreset: String, Codable, CaseIterable {
    case trash
    case caches
    /// Docker Desktop: `Docker.raw` announces ~1 TB, holds a few GB.
    case docker
    /// Apple Container: sparse `.ext4` images (the `kali` container).
    case appleContainer
    /// The recreatable sparse disk images (Docker Desktop's, Apple
    /// Container's) wherever they live; any other sparse image is backed
    /// up unless left out by name (`ForkMacBackupSparsePolicy`, fix of
    /// 23/10: a VM clone holds real data). No fixed path: the agent finds
    /// them before each run with `totalFileAllocatedSize`.
    case sparseDiskImages
    case virtualMachines
    /// `node_modules`, `.venv`… regenerable.
    case devFolders
    /// `build`, `dist`, `out`, `vendor`, `coverage`: may hold real work, so
    /// never on by default; offered with the list of real paths they touch.
    case genericBuildNames
    case cloudStorage
    /// Folders carrying a `CACHEDIR.TAG` (a Kopia policy flag, no pattern).
    case cacheDirTag
    case logs
    /// `.ssh`, `.gnupg`, keychains: in the backup unless ticked (a banner
    /// says the private keys are in it, encrypted on the Mac).
    case secrets

    /// Applied when nothing was chosen yet.
    var isDefault: Bool {
        switch self {
        case .trash, .caches, .docker, .appleContainer, .sparseDiskImages, .devFolders, .cloudStorage,
             .cacheDirTag, .logs:
            return true
        case .virtualMachines, .genericBuildNames, .secrets:
            return false
        }
    }

    /// Kopia ignore rules (gitignore syntax, relative to the source; a
    /// leading `/` anchors at the source's root, so the anchored ones only
    /// act on a home folder source). Empty for the two presets the agent
    /// computes (`sparseDiskImages`) or Kopia flags (`cacheDirTag`).
    var patterns: [String] {
        switch self {
        case .trash: return ["/.Trash/"]
        case .caches: return ["/Library/Caches/"]
        case .docker: return ["/Library/Containers/com.docker.docker/"]
        case .appleContainer: return ["/Library/Application Support/com.apple.container/"]
        case .sparseDiskImages: return []
        case .virtualMachines: return ["Virtual Machines.localized/", "Parallels/", "/Library/Containers/com.utmapp.UTM/"]
        case .devFolders:
            return ["node_modules/", ".venv/", "venv/", "__pycache__/", ".next/", ".turbo/", "target/",
                    "DerivedData/", "/Library/pnpm/"]
        case .genericBuildNames: return ["build/", "dist/", "out/", "vendor/", "coverage/"]
        case .cloudStorage: return ["/Library/CloudStorage/", "/Library/Application Support/FileProvider/"]
        case .cacheDirTag: return []
        case .logs: return ["*.log"]
        case .secrets: return ["/.ssh/", "/.gnupg/", "/Library/Keychains/"]
        }
    }

    /// The presets on by default, in declaration order.
    static var defaultApplied: [ForkMacBackupPreset] { allCases.filter(\.isDefault) }

    /// `fork.macbackup.presets`: raw values joined by commas.
    static func storageValue(_ presets: [ForkMacBackupPreset]) -> String {
        normalized(presets).map(\.rawValue).joined(separator: ",")
    }

    /// Reads `fork.macbackup.presets`; unknown names (a newer build) are
    /// skipped, an empty string means none.
    static func parse(_ value: String) -> [ForkMacBackupPreset] {
        normalized(value.split(separator: ",").compactMap {
            ForkMacBackupPreset(rawValue: $0.trimmingCharacters(in: .whitespaces))
        })
    }

    /// Without duplicates, in declaration order: two equal lists compare
    /// equal whatever order they were ticked in.
    static func normalized(_ presets: [ForkMacBackupPreset]) -> [ForkMacBackupPreset] {
        let set = Set(presets)
        return allCases.filter(set.contains)
    }
}

/// Which sparse disk images (≥ 10 GB announced, less than half written)
/// stay out of the backup. Only the recreatable ones are left out by the
/// `sparseDiskImages` preset: Docker Desktop's and Apple Container's, which
/// their apps rebuild. Any other one holds real data (a VM clone, a disk
/// image of a server): it is backed up unless the person leaves THAT file
/// out (`fork.macbackup.sparse.excluded`, absolute paths).
enum ForkMacBackupSparsePolicy {
    /// Docker Desktop (`Docker.raw`, `com.docker.docker`) or Apple
    /// Container (`com.apple.container`), wherever the image lives.
    static func isRecreatable(_ path: String) -> Bool {
        let parts = path.split(separator: "/").map(String.init)
        if parts.last == "Docker.raw" { return true }
        return parts.contains("com.docker.docker") || parts.contains("com.apple.container")
    }

    /// Whether the image at `relativePath` of `source` is left out.
    static func excludes(relativePath: String, source: ForkMacBackupSource, excluded: Set<String>) -> Bool {
        let absolute = absolutePath(relativePath, in: source.path)
        if excluded.contains(absolute) { return true }
        return source.presets.contains(.sparseDiskImages) && isRecreatable(absolute)
    }

    static func absolutePath(_ relativePath: String, in sourcePath: String) -> String {
        let root = ForkMacBackupSourcePath.normalized(sourcePath)
        let relative = relativePath.hasPrefix("/") ? String(relativePath.dropFirst()) : relativePath
        return ForkMacBackupSourcePath.normalized(root == "/" ? "/" + relative : root + "/" + relative)
    }

    /// `fork.macbackup.sparse.excluded`: a JSON array of absolute paths;
    /// empty or damaged: none.
    static func parse(_ stored: String?) -> [String] {
        guard let stored, !stored.isEmpty,
              let paths = try? JSONDecoder().decode([String].self, from: Data(stored.utf8)) else { return [] }
        return paths.map(ForkMacBackupSourcePath.normalized)
    }

    static func storageValue(_ paths: [String]) -> String {
        let unique = Array(Set(paths.map(ForkMacBackupSourcePath.normalized))).sorted()
        guard !unique.isEmpty, let data = try? JSONEncoder().encode(unique) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}

/// What happens to iCloud Drive files that are only in the cloud (plan §4.4).
enum ForkMacBackupICloudMode: String, Codable, CaseIterable {
    /// Files on the Mac only; the cloud-only ones are listed apart and do
    /// not make the snapshot partial.
    case local
    /// Downloads them first (`setiopolicy_np` before Kopia).
    case materialize
    /// Leaves iCloud Drive out.
    case exclude

    static let fallback: ForkMacBackupICloudMode = .local
}

/// Source paths in their ONE canonical form, the one Kopia records: absolute,
/// standardized (no « // », « . » or « .. »), no trailing « / » but for the
/// root itself. Every boundary goes through it (settings, Bran import,
/// pre-scan keys, proofs, capacity, Kopia's sources, FSEvents roots): a
/// source saved as « /Users/me/ » once made the planner miss every snapshot
/// Kopia recorded as « /Users/me » and back up in a loop (build 2331).
enum ForkMacBackupSourcePath {
    static func normalized(_ path: String) -> String {
        guard path.hasPrefix("/") else {
            var relative = path
            while relative.count > 1, relative.hasSuffix("/") { relative.removeLast() }
            return relative
        }
        var parts: [Substring] = []
        for part in path.split(separator: "/", omittingEmptySubsequences: true) {
            switch part {
            case ".": continue
            case "..": if !parts.isEmpty { parts.removeLast() }
            default: parts.append(part)
            }
        }
        return "/" + parts.joined(separator: "/")
    }

    /// Whether two paths name the same source.
    static func same(_ lhs: String, _ rhs: String) -> Bool {
        lhs == rhs || normalized(lhs) == normalized(rhs)
    }

    /// This Mac's sources in the repository, split: those of the current
    /// configuration, and the former ones (an old test, a folder removed),
    /// still browsable and restorable. Nothing configured: all are current.
    static func split(_ paths: [String], configured: [String]) -> (current: [String], former: [String]) {
        guard !configured.isEmpty else { return (paths, []) }
        let wanted = Set(configured.map(normalized))
        return (paths.filter { wanted.contains(normalized($0)) }, paths.filter { !wanted.contains(normalized($0)) })
    }
}

/// One folder backed up, with its own rules. Machine state (absolute paths,
/// always in `ForkMacBackupSourcePath` form, however they were stored).
struct ForkMacBackupSource: Codable, Equatable, Identifiable {
    var path: String {
        didSet { if path != oldValue { path = ForkMacBackupSourcePath.normalized(path) } }
    }
    var presets: [ForkMacBackupPreset]
    /// Free rules, in Kopia's ignore syntax.
    var customRules: [String]

    var id: String { path }

    init(path: String, presets: [ForkMacBackupPreset] = ForkMacBackupPreset.defaultApplied, customRules: [String] = []) {
        self.path = ForkMacBackupSourcePath.normalized(path)
        self.presets = ForkMacBackupPreset.normalized(presets)
        self.customRules = customRules
    }

    private enum CodingKeys: String, CodingKey {
        case path
        case presets
        case customRules
    }

    /// A stored source is read in canonical form (the migration of build
    /// 2331's « /Users/me/ »).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = ForkMacBackupSourcePath.normalized(try container.decode(String.self, forKey: .path))
        // Unknown presets (a newer build) are skipped, as in `fork.macbackup.presets`.
        let names = try container.decodeIfPresent([String].self, forKey: .presets)
        presets = names.map { ForkMacBackupPreset.normalized($0.compactMap(ForkMacBackupPreset.init(rawValue:))) }
            ?? ForkMacBackupPreset.defaultApplied
        customRules = try container.decodeIfPresent([String].self, forKey: .customRules) ?? []
    }

    /// `fork.macbackup.rules`: a JSON array of strings; empty or damaged: none.
    /// The one reader, for the Settings and for the agent.
    static func customRules(fromStored text: String?) -> [String] {
        guard let text, !text.isEmpty,
              let rules = try? JSONDecoder().decode([String].self, from: Data(text.utf8)) else { return [] }
        return rules.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// The source with the rules the person's settings give every source:
    /// `fork.macbackup.presets` and `fork.macbackup.rules`, the keys the
    /// Settings write and the settings import restores. The per-source
    /// copies in the machine state are only a cache of them.
    func applying(presets storedPresets: String?, rules storedRules: String?) -> ForkMacBackupSource {
        var source = self
        source.presets = ForkMacBackupPreset.parse(storedPresets ?? ForkMacBackupPreset.storageValue(ForkMacBackupPreset.defaultApplied))
        source.customRules = Self.customRules(fromStored: storedRules)
        return source
    }

    /// The source as people name it (« Dossier personnel », « Documents »).
    func displayName(_ text: ForkMacBackupStrings, home: String = NSHomeDirectory()) -> String {
        ForkMacBackupFormat.sourceName(path, text: text, home: home)
    }

    /// Every ignore rule of the source: its presets' patterns, then its own,
    /// without duplicates, in a stable order (what the policy must read back).
    var ignoreRules: [String] {
        var seen = Set<String>()
        var rules: [String] = []
        for rule in presets.flatMap(\.patterns) + customRules {
            let trimmed = rule.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
            rules.append(trimmed)
        }
        return rules
    }
}

/// How many snapshots Kopia keeps (plan §7.2), in `--keep-*` order.
struct ForkMacBackupRetention: Codable, Equatable {
    var latest: Int
    var hourly: Int
    var daily: Int
    var weekly: Int
    var monthly: Int
    var annual: Int

    enum Preset: String, Codable, CaseIterable {
        case balanced
        case economical
        case long
        case custom

        static let fallback: Preset = .balanced
    }

    static let balanced = ForkMacBackupRetention(latest: 10, hourly: 48, daily: 30, weekly: 8, monthly: 12, annual: 3)
    static let economical = ForkMacBackupRetention(latest: 5, hourly: 24, daily: 14, weekly: 4, monthly: 6, annual: 1)
    static let long = ForkMacBackupRetention(latest: 10, hourly: 48, daily: 60, weekly: 26, monthly: 36, annual: 10)

    static func preset(_ preset: Preset, custom: String) -> ForkMacBackupRetention {
        switch preset {
        case .balanced: return .balanced
        case .economical: return .economical
        case .long: return .long
        case .custom: return parse(custom) ?? .balanced
        }
    }

    /// `fork.macbackup.retention.custom`: « 10,48,30,8,12,3 ».
    var storageValue: String {
        [latest, hourly, daily, weekly, monthly, annual].map(String.init).joined(separator: ",")
    }

    /// Six non-negative numbers, else nil.
    static func parse(_ value: String) -> ForkMacBackupRetention? {
        let numbers = value.split(separator: ",").map { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard numbers.count == 6 else { return nil }
        let values = numbers.compactMap { $0 }
        guard values.count == 6, values.allSatisfy({ $0 >= 0 }) else { return nil }
        return ForkMacBackupRetention(latest: values[0], hourly: values[1], daily: values[2], weekly: values[3],
                                      monthly: values[4], annual: values[5])
    }
}

/// The policy one source must carry before a snapshot: written in one
/// command, read back (`policy show --json`) and compared with `==`; a
/// difference means no snapshot (`waiting(.rulesNotApplied)`).
struct ForkMacBackupPolicyRules: Codable, Equatable {
    /// Sorted: Kopia does not keep the order.
    var ignoreRules: [String]
    var ignoreCacheDirs: Bool
    /// Always true: our planner decides, never Kopia's scheduler.
    var manual: Bool
    var retention: ForkMacBackupRetention

    init(ignoreRules: [String], ignoreCacheDirs: Bool = true, manual: Bool = true,
         retention: ForkMacBackupRetention = .balanced) {
        self.ignoreRules = ignoreRules.sorted()
        self.ignoreCacheDirs = ignoreCacheDirs
        self.manual = manual
        self.retention = retention
    }

    /// What `source` asks for, plus the run's extra rules (sparse images,
    /// cloud-only files found just before).
    init(source: ForkMacBackupSource, extraRules: [String] = [], retention: ForkMacBackupRetention) {
        self.init(ignoreRules: Array(Set(source.ignoreRules + extraRules)),
                  ignoreCacheDirs: source.presets.contains(.cacheDirTag), manual: true, retention: retention)
    }
}
