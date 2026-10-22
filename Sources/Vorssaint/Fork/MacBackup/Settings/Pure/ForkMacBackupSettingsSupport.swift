// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

// The Settings package's pure helpers: what its screens compute without a
// view, a disk or a process, so `fork/test.sh` tests them.

// MARK: - Times of day

/// « 13:00,21:00 » (`fork.macbackup.schedule.times`): minutes after
/// midnight, sorted, without duplicates.
enum ForkMacBackupTimes {
    static func parse(_ value: String) -> [Int] {
        let minutes = value.split(separator: ",").compactMap { minutesOfDay(String($0)) }
        return Array(Set(minutes)).sorted()
    }

    static func storageValue(_ minutes: [Int]) -> String {
        Array(Set(minutes.map { min(max($0, 0), 24 * 60 - 1) })).sorted().map(clock).joined(separator: ",")
    }

    /// « 09:05 » → 545; nil for anything else.
    static func minutesOfDay(_ text: String) -> Int? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0..<24).contains(hour), (0..<60).contains(minute) else { return nil }
        return hour * 60 + minute
    }

    /// 545 → « 09:05 ».
    static func clock(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }
}

/// « 09:00-19:00@5 » (`fork.macbackup.throttle.window`): a daily window with
/// a lower upload limit, in MB/s. Empty: none.
struct ForkMacBackupThrottleWindow: Equatable {
    var start: Int
    var end: Int
    var megabytesPerSecond: Int

    static let suggested = ForkMacBackupThrottleWindow(start: 9 * 60, end: 19 * 60, megabytesPerSecond: 5)

    static func parse(_ value: String) -> ForkMacBackupThrottleWindow? {
        let halves = value.split(separator: "@")
        guard halves.count == 2, let limit = Int(halves[1].trimmingCharacters(in: .whitespaces)), limit > 0 else {
            return nil
        }
        let bounds = halves[0].split(separator: "-")
        guard bounds.count == 2, let start = ForkMacBackupTimes.minutesOfDay(String(bounds[0])),
              let end = ForkMacBackupTimes.minutesOfDay(String(bounds[1])), start != end else { return nil }
        return ForkMacBackupThrottleWindow(start: start, end: end, megabytesPerSecond: limit)
    }

    var storageValue: String {
        "\(ForkMacBackupTimes.clock(start))-\(ForkMacBackupTimes.clock(end))@\(max(1, megabytesPerSecond))"
    }
}

// MARK: - Verification plan

/// « refs:7d,files1:1d,restore50:30d » (`fork.macbackup.verify.plan`): how
/// often each level runs (plan §7.1). A level left out never runs on its own.
struct ForkMacBackupVerifyPlan: Equatable {
    enum Level: String, CaseIterable {
        case references
        case contentSample
        case restoreTest

        var storagePrefix: String {
            switch self {
            case .references: return "refs"
            case .contentSample: return "files"
            case .restoreTest: return "restore"
            }
        }

        static func order(_ level: Level) -> Int { allCases.firstIndex(of: level) ?? 0 }
    }

    struct Entry: Equatable {
        var level: Level
        /// `files<percent>`, `restore<count>`; nil for `refs`.
        var amount: Double?
        /// Hours between two runs.
        var everyHours: Int

        var verifyLevel: ForkMacBackupVerifyLevel {
            switch level {
            case .references: return .references
            case .contentSample: return .contentSample(percent: amount ?? 1)
            case .restoreTest: return .restoreTest(files: Int(amount ?? 50))
            }
        }
    }

    var entries: [Entry]

    static let fallback = ForkMacBackupVerifyPlan.parse("refs:7d,files1:1d,restore50:30d")

    func entry(_ level: Level) -> Entry? { entries.first { $0.level == level } }

    /// Sets, or with nil removes, one level's period.
    mutating func set(_ level: Level, everyHours: Int?) {
        let existing = entry(level)
        entries.removeAll { $0.level == level }
        if let everyHours, everyHours > 0 {
            let amount = existing?.amount ?? (level == .contentSample ? 1 : (level == .restoreTest ? 50 : nil))
            entries.append(Entry(level: level, amount: amount, everyHours: everyHours))
        }
        entries.sort { Level.order($0.level) < Level.order($1.level) }
    }

    static func parse(_ value: String) -> ForkMacBackupVerifyPlan {
        var entries: [Entry] = []
        for item in value.split(separator: ",") {
            let pair = item.split(separator: ":")
            guard pair.count == 2, let hours = Self.hours(String(pair[1])) else { continue }
            let name = String(pair[0]).trimmingCharacters(in: .whitespaces)
            for level in Level.allCases where name.hasPrefix(level.storagePrefix) {
                let rest = name.dropFirst(level.storagePrefix.count)
                let amount = rest.isEmpty ? nil : Double(rest)
                guard rest.isEmpty || amount != nil, !entries.contains(where: { $0.level == level }) else { continue }
                entries.append(Entry(level: level, amount: level == .references ? nil : amount, everyHours: hours))
            }
        }
        return ForkMacBackupVerifyPlan(entries: entries.sorted { Level.order($0.level) < Level.order($1.level) })
    }

    var storageValue: String {
        entries.map { entry in
            var name = entry.level.storagePrefix
            if let amount = entry.amount, entry.level != .references {
                name += amount == amount.rounded() ? String(Int(amount)) : String(amount)
            }
            let period = entry.everyHours % 24 == 0 ? "\(entry.everyHours / 24)d" : "\(entry.everyHours)h"
            return "\(name):\(period)"
        }.joined(separator: ",")
    }

    /// « 7d » → 168, « 12h » → 12.
    static func hours(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let unit = trimmed.last, let value = Int(trimmed.dropLast()), value > 0 else { return nil }
        switch unit {
        case "d": return value * 24
        case "h": return value
        default: return nil
        }
    }
}

// MARK: - Notifications

/// One event's channel as the page's matrix shows it: two switches, island
/// and system; neither is « Rien ».
extension ForkMacBackupNotifyChannel {
    var island: Bool { self == .island || self == .both }
    var system: Bool { self == .system || self == .both }

    init(island: Bool, system: Bool) {
        switch (island, system) {
        case (true, true): self = .both
        case (true, false): self = .island
        case (false, true): self = .system
        case (false, false): self = .none
        }
    }
}

// MARK: - Setup

/// The five steps of « Mise en route » (plan §11.1), in order.
enum ForkMacBackupSetupStep: String, CaseIterable, Identifiable {
    case engine
    case diskAccess
    case background
    case repository
    case kit

    var id: String { rawValue }
}

struct ForkMacBackupSetupState: Equatable {
    var done: Set<ForkMacBackupSetupStep>

    init(engine: ForkMacBackupEngineInstallState, fullDiskAccess: Bool, registration: ForkMacBackupAgentRegistration,
         repository: ForkMacBackupRepository?, kitCreatedAt: Date?) {
        var done = Set<ForkMacBackupSetupStep>()
        if case .installed = engine { done.insert(.engine) }
        if fullDiskAccess { done.insert(.diskAccess) }
        if registration == .enabled || registration == .developmentFallback { done.insert(.background) }
        if let repository, repository.expectedUniqueID?.isEmpty == false { done.insert(.repository) }
        if kitCreatedAt != nil { done.insert(.kit) }
        self.done = done
    }

    /// The first step still to do: it gets the prominent button.
    var current: ForkMacBackupSetupStep? { ForkMacBackupSetupStep.allCases.first { !done.contains($0) } }

    /// The four steps a backup needs; the kit can wait (« Plus tard »).
    var isReady: Bool { done.isSuperset(of: [.engine, .diskAccess, .background, .repository]) }

    var count: Int { done.count }
}

// MARK: - The chain as drawn

/// A profile node with its last measure, ready to draw (« Ma chaîne »).
struct ForkMacBackupChainDisplayNode: Equatable, Identifiable {
    var node: ForkMacBackupChainNode
    var state: ForkMacBackupPresentation.NodeState
    var latencyMs: Int?
    var checkedAt: Date?
    /// Beyond a broken node nothing can be checked: drawn grey.
    var isBeyondBreak: Bool
    /// The link drawn before this node is dashed: this node is the break.
    var linkBeforeBroken: Bool

    var id: String { node.id }
}

enum ForkMacBackupChainDisplay {
    /// The profile's nodes, in its order, each with its measure (matched by
    /// id); after the first broken node the rest is unknown.
    static func nodes(_ chain: [ForkMacBackupChainNode],
                      statuses: [ForkMacBackupPresentation.ChainStatus]) -> [ForkMacBackupChainDisplayNode] {
        var brokenSeen = false
        return chain.map { node in
            let status = statuses.first { $0.id == node.id }
            var state = status?.state ?? .unknown
            let beyond = brokenSeen
            if beyond { state = .unknown }
            let isBreak = !beyond && state == .broken
            if isBreak { brokenSeen = true }
            return ForkMacBackupChainDisplayNode(node: node, state: state, latencyMs: beyond ? nil : status?.latencyMs,
                                                 checkedAt: status?.checkedAt, isBeyondBreak: beyond,
                                                 linkBeforeBroken: isBreak)
        }
    }

    /// The chain the page draws: the active profile's when its repository is
    /// the one connected, else the default one of the repository.
    static func chain(profile: ForkMacBackupProfile?, repository: ForkMacBackupRepository?) -> [ForkMacBackupChainNode] {
        if let profile, !profile.chain.isEmpty,
           repository == nil || profile.repository.key == repository?.key {
            return profile.chain
        }
        if let repository { return ForkMacBackupProfile.defaultChain(for: repository) }
        return profile?.chain ?? []
    }
}

// MARK: - Machines in a repository

/// One Kopia identity found in a repository, with its snapshots (wizard,
/// step 3: « whyteduke@macbook-pro · 29 snapshots »).
struct ForkMacBackupRepositoryMachine: Equatable, Identifiable {
    var identity: ForkMacBackupRepository.Identity
    var snapshots: Int
    var latest: Date?

    var id: String { identity.description }

    static func machines(in manifests: [ForkMacBackupKopia.SnapshotManifest]) -> [ForkMacBackupRepositoryMachine] {
        var found: [String: ForkMacBackupRepositoryMachine] = [:]
        for manifest in manifests {
            guard let user = manifest.source?.userName, let host = manifest.source?.host,
                  !user.isEmpty, !host.isEmpty else { continue }
            let identity = ForkMacBackupRepository.Identity(userName: user, hostName: host)
            var machine = found[identity.description] ?? ForkMacBackupRepositoryMachine(identity: identity, snapshots: 0)
            machine.snapshots += 1
            if let date = manifest.startDate, machine.latest.map({ date > $0 }) ?? true { machine.latest = date }
            found[identity.description] = machine
        }
        return found.values.sorted {
            ($0.latest ?? .distantPast, $0.id) > ($1.latest ?? .distantPast, $1.id)
        }
    }

    /// The identity to continue by default: the one of this Mac's name.
    static func suggested(_ machines: [ForkMacBackupRepositoryMachine], localHost: String, localUser: String)
        -> ForkMacBackupRepository.Identity? {
        let host = localHost.lowercased()
        if let same = machines.first(where: { $0.identity.hostName.lowercased() == host
                                                && $0.identity.userName == localUser }) {
            return same.identity
        }
        return machines.first { $0.identity.hostName.lowercased() == host }?.identity
    }
}

// MARK: - Local identity

enum ForkMacBackupLocalIdentity {
    /// Kopia's own default host name: the short host name, lower case,
    /// dots and spaces as dashes (« MacBook Pro de Whyte » → « macbook-pro-de-whyte »).
    static func hostName(from name: String) -> String {
        let short = name.split(separator: ".").first.map(String.init) ?? name
        let allowed = short.lowercased().map { character -> Character in
            character.isLetter || character.isNumber || character == "-" ? character : "-"
        }
        var text = String(allowed)
        while text.contains("--") { text = text.replacingOccurrences(of: "--", with: "-") }
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return text.isEmpty ? "mac" : text
    }
}

// MARK: - Profiles

enum ForkMacBackupProfileFile {
    /// A profile as written to disk: readable, stable, no secret by type.
    static func encode(_ profile: ForkMacBackupProfile) -> Data? {
        let encoder = ForkMacBackupJSON.encoder
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        return try? encoder.encode(profile)
    }

    /// The JSON keys no profile may ever carry.
    static let forbiddenKeys = ["password", "secret", "secretAccessKey", "repositoryPassword", "passphrase",
                                "s3SecretAccessKey", "token"]

    /// Whether `data` holds anything that looks like a secret's key.
    static func containsSecretField(_ data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return false }
        func walk(_ value: Any) -> Bool {
            if let dictionary = value as? [String: Any] {
                for (key, child) in dictionary {
                    let lower = key.lowercased()
                    if forbiddenKeys.contains(where: { lower.contains($0.lowercased()) }) { return true }
                    if walk(child) { return true }
                }
            } else if let array = value as? [Any] {
                return array.contains(where: walk)
            }
            return false
        }
        return walk(object)
    }

    /// The known profiles, the active one first, by name.
    static func merged(_ known: [ForkMacBackupProfile], adding profile: ForkMacBackupProfile) -> [ForkMacBackupProfile] {
        [profile] + known.filter { $0.name != profile.name }
    }
}

// MARK: - Screens

/// The Options sheet's tabs.
enum ForkMacBackupOptionsTab: String, CaseIterable, Identifiable {
    case retention
    case verifications
    case notifications
    case advanced

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .retention: return "archivebox.fill"
        case .verifications: return "checkmark.shield.fill"
        case .notifications: return "bell.badge.fill"
        case .advanced: return "gearshape.2.fill"
        }
    }
}

/// The wizard's steps (plan §11.2), then the kit.
enum ForkMacBackupWizardStep: Int, CaseIterable, Identifiable {
    case start
    case server
    case repository
    case identity
    case kit

    var id: Int { rawValue }
}
