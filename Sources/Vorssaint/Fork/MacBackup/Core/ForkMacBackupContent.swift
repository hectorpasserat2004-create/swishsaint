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
    /// Any file ≥ 10 GB of which less than half is really written (decision
    /// 1 of 22/10). No fixed path: the agent finds them before each run with
    /// `totalFileAllocatedSize` and adds them to the run's rules.
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

/// One folder backed up, with its own rules. Machine state (absolute paths).
struct ForkMacBackupSource: Codable, Equatable, Identifiable {
    var path: String
    var presets: [ForkMacBackupPreset]
    /// Free rules, in Kopia's ignore syntax.
    var customRules: [String]

    var id: String { path }

    init(path: String, presets: [ForkMacBackupPreset] = ForkMacBackupPreset.defaultApplied, customRules: [String] = []) {
        self.path = path
        self.presets = ForkMacBackupPreset.normalized(presets)
        self.customRules = customRules
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
