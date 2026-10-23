// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// The agent's bounds, in one place so they can be retuned once the real
/// cost is measured (plan §3.9.1, spike S4). Nothing else in the agent
/// hard-codes a duration or a threshold.
enum ForkMacBackupAgentTuning {
    // MARK: Automatic rhythm (§3.9.1)

    /// On AC: never closer than this after the last backup…
    static let autoMinInterval: TimeInterval = 3_600
    /// …and never further than this.
    static let autoMaxIntervalAC: TimeInterval = 4 * 3_600
    /// On battery: spaced up to this.
    static let autoMaxIntervalBattery: TimeInterval = 8 * 3_600
    /// The weighted changes that make a backup worth it on AC…
    static let autoNeedAC: Double = 5
    /// …and on battery (a bigger need).
    static let autoNeedBattery: Double = 50

    // MARK: Weights of a changed file (§5.5)

    /// Documents and Desktop.
    static let importantWeight: Double = 5
    static let ordinaryWeight: Double = 1
    /// `Library/`: noisy, cheap to lose.
    static let libraryWeight: Double = 0.1
    /// Folders of a home source that count as important.
    static let importantFolders = ["Documents", "Desktop"]
    /// Beyond this many distinct paths, the count goes on without remembering them.
    static let pendingPathCap = 50_000

    // MARK: Run

    /// No progress for this long: cancel with a checkpoint, then retry (§3.8).
    /// The person's `fork.macbackup.timeout.watchdogMinutes` replaces it.
    static let watchdog: TimeInterval = 10 * 60
    /// A cancel that does not end within this long is given up.
    static let cancelGrace: TimeInterval = 3 * 60
    /// Retries after a failure: 1, 5, 15, 60 min, then doubling up to 6 h.
    static let backoffSteps: [TimeInterval] = [60, 5 * 60, 15 * 60, 60 * 60]
    static let backoffCap: TimeInterval = 6 * 3_600
    /// A trigger that never shows an upload nor a new snapshot is a failure.
    static let startGrace: TimeInterval = 90
    /// How long `.finished` stays before the state rests on `.ready`.
    static let finishedDisplay: TimeInterval = 5 * 60
    /// The ETA appears once Kopia's estimate has held for this long.
    static let etaStableFor: TimeInterval = 30
    /// The estimate « holds » while it moves by less than this fraction.
    static let estimateTolerance = 0.01
    /// The rate is a sliding mean over this window.
    static let rateWindow: TimeInterval = 10
    /// A slot that starts later than this after its due date started late.
    static let lateAfter: TimeInterval = 5 * 60

    // MARK: Publishing (README §1)

    /// A lease younger than this means a view shows the live progress.
    static let leaseFreshness: TimeInterval = 15
    static let livePublishInterval: TimeInterval = 1
    static let quietPublishInterval: TimeInterval = 10
    /// Rewritten at least this often, so the app can tell a live agent.
    static let heartbeatInterval: TimeInterval = 5 * 60
    /// How often the engine is asked for progress while a snapshot runs.
    static let progressPollInterval: TimeInterval = 1

    // MARK: Conditions

    /// Rechecks of the conditions that send no notification.
    static let peerRecheck: TimeInterval = 5 * 60
    static let otherEngineRecheck: TimeInterval = 2 * 60
    static let localSpaceRecheck: TimeInterval = 15 * 60
    static let diskAccessRecheck: TimeInterval = 10 * 60
    /// Below this free space on the Mac, Kopia's cache could fill it.
    static let minimumLocalFreeBytes: Int64 = 5_000_000_000
    /// The update hold: the updater waits at most this long for a backup…
    static let updateWaitLimit: TimeInterval = 30 * 60
    /// …and a hold older than this is stale (the update failed or was dropped).
    static let updateHoldLifetime: TimeInterval = 20 * 60
    /// A source's full pre-scan walk (real size, sparse images, cloud-only
    /// files) is reused this long, kept up to date in between with the files
    /// FSEvents saw change (`ForkMacBackupPrescanPlan`). Measured 22/10 on a
    /// 2.4 M-file home folder: one walk takes 2.5 to 3.5 min and 2 min of CPU.
    static let prescanLifetime: TimeInterval = 24 * 3_600
    /// Past `prescanLifetime`, a Mac on battery keeps using it up to this
    /// age; on mains power it walks again.
    static let prescanBatteryLifetime: TimeInterval = 7 * 86_400
    /// `maintenance info` is read this often (Kopia's server runs it).
    static let maintenanceRecheck: TimeInterval = 6 * 3_600

    // MARK: Journals

    /// `runs.jsonl` and `slots.jsonl` keep this long…
    static let journalMaxAge: TimeInterval = 90 * 86_400
    /// …and at most this many lines.
    static let journalMaxLines = 5_000
    /// Rotation is checked once the file passes this size.
    static let journalRotateBytes = 2_000_000
    /// The cost line averages the last backups that sent something.
    static let costSamples = 20
    /// The battery slope before a run is measured over this window.
    static let batterySlopeWindow: TimeInterval = 30 * 60
}

/// Every `fork.macbackup.*` value the agent reads, decoded once per reload.
/// Pure: built from a lookup (`UserDefaults.object(forKey:)` in the agent, a
/// dictionary in the tests), defaults from `ForkMacBackupDefaults.registered`.
struct ForkMacBackupAgentSettings: Equatable {
    enum PowerMode: String, CaseIterable {
        case always
        case ac
        case threshold
    }

    enum NetworkMode: String, CaseIterable {
        case wait
        case slow
        case ignore
    }

    enum MeetingMode: String, CaseIterable {
        case pause
        case slow
        case none
    }

    enum KeepAwake: String, CaseIterable {
        case never
        case ac
        case always
    }

    /// `fork.macbackup.priority`: how hard a scheduled backup may use the Mac.
    enum Priority: String, CaseIterable {
        case low
        case normal
    }

    /// « 13:00 » as hour and minute.
    struct TimeOfDay: Equatable, Comparable {
        var hour: Int
        var minute: Int

        static func < (lhs: Self, rhs: Self) -> Bool { (lhs.hour, lhs.minute) < (rhs.hour, rhs.minute) }

        /// « 13:00,21:00 » → sorted, without duplicates; bad entries skipped.
        static func parseList(_ text: String) -> [TimeOfDay] {
            let parsed = text.split(separator: ",").compactMap { parse(String($0)) }
            return Array(Set(parsed.map { $0.hour * 60 + $0.minute })).sorted().map { TimeOfDay(hour: $0 / 60, minute: $0 % 60) }
        }

        static func parse(_ text: String) -> TimeOfDay? {
            let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":").map { Int($0) }
            guard parts.count == 2, let hour = parts[0], let minute = parts[1],
                  (0..<24).contains(hour), (0..<60).contains(minute) else { return nil }
            return TimeOfDay(hour: hour, minute: minute)
        }

        var storage: String { String(format: "%02d:%02d", hour, minute) }
    }

    /// « 09:00-19:00@5 »: a window of the day with a lower upload limit.
    struct ThrottleWindow: Equatable {
        var start: TimeOfDay
        var end: TimeOfDay
        var megabytesPerSecond: Double

        static func parse(_ text: String) -> ThrottleWindow? {
            let halves = text.split(separator: "@", maxSplits: 1).map(String.init)
            guard halves.count == 2, let limit = Double(halves[1].trimmingCharacters(in: .whitespaces)), limit > 0
            else { return nil }
            let bounds = halves[0].split(separator: "-", maxSplits: 1).map(String.init)
            guard bounds.count == 2, let start = TimeOfDay.parse(bounds[0]), let end = TimeOfDay.parse(bounds[1]),
                  start != end else { return nil }
            return ThrottleWindow(start: start, end: end, megabytesPerSecond: limit)
        }

        /// Whether `time` falls in the window; one that ends before it starts
        /// runs across midnight.
        func contains(_ time: TimeOfDay) -> Bool {
            start < end ? (start <= time && time < end) : (time >= start || time < end)
        }
    }

    var enabled: Bool
    var scheduleMode: ForkMacBackupScheduleMode
    var intervalHours: Int
    var times: [TimeOfDay]
    var catchUpDelay: TimeInterval
    var powerMode: PowerMode
    var minBatteryPercent: Int
    var forceAfter: TimeInterval
    var lowPowerWaits: Bool
    var limitedNetwork: NetworkMode
    var meetingMode: MeetingMode
    /// Bytes per second of « Ralentir ».
    var slowBytesPerSecond: Int64
    var throttleWindow: ThrottleWindow?
    var keepAwake: KeepAwake
    var earlyEnabled: Bool
    var earlyThreshold: Int
    var iCloud: ForkMacBackupICloudMode
    var retention: ForkMacBackupRetention
    var repository: ForkMacBackupRepository?
    var sources: [ForkMacBackupSource]
    var profile: ForkMacBackupProfile?
    var priority: Priority
    /// No progress for this long: the watchdog cancels and retries.
    var watchdog: TimeInterval
    /// The chain check (connect, repository status) gives up after this long.
    var repositoryTimeout: TimeInterval
    /// A Tailscale probe gives up after this long.
    var probeTimeout: TimeInterval

    /// A repository and at least one source.
    var isConfigured: Bool { repository != nil && !sources.isEmpty }

    /// The chain drawn: the profile's, else the default one.
    var chain: [ForkMacBackupChainNode] {
        if let profile, !profile.chain.isEmpty { return profile.chain }
        return repository.map(ForkMacBackupProfile.defaultChain(for:)) ?? []
    }

    var rhythm: ForkMacBackupPresentation.Rhythm {
        switch scheduleMode {
        case .auto: return .automatic(about: nil)
        case .interval: return .interval(hours: intervalHours)
        case .times: return .times(times.map(\.storage))
        case .both: return .both(hours: intervalHours, times: times.map(\.storage))
        }
    }

    init(lookup: (String) -> Any?) {
        let registered = ForkMacBackupDefaults.registered
        func value(_ key: String) -> Any? { lookup(key) ?? registered[key] }
        func bool(_ key: String) -> Bool {
            if let flag = value(key) as? Bool { return flag }
            if let number = value(key) as? NSNumber { return number.boolValue }
            return false
        }
        func int(_ key: String, _ range: ClosedRange<Int>, fallback: Int) -> Int {
            let raw: Int?
            if let number = value(key) as? Int {
                raw = number
            } else if let number = value(key) as? NSNumber {
                raw = number.intValue
            } else if let text = value(key) as? String {
                raw = Int(text)
            } else {
                raw = nil
            }
            guard let raw else { return fallback }
            return min(range.upperBound, max(range.lowerBound, raw))
        }
        func string(_ key: String) -> String { value(key) as? String ?? "" }
        func json<Value: Decodable>(_ type: Value.Type, _ key: String) -> Value? {
            let data: Data?
            if let raw = lookup(key) as? Data {
                data = raw
            } else if let raw = lookup(key) as? String {
                data = Data(raw.utf8)
            } else {
                data = nil
            }
            return data.flatMap { try? ForkMacBackupJSON.decoder.decode(type, from: $0) }
        }

        enabled = bool(ForkDefaultsKey.macBackupEnabled)
        scheduleMode = ForkMacBackupScheduleMode(rawValue: string(ForkDefaultsKey.macBackupScheduleMode)) ?? .fallback
        intervalHours = int(ForkDefaultsKey.macBackupIntervalHours, 1...48, fallback: 4)
        times = TimeOfDay.parseList(string(ForkDefaultsKey.macBackupTimes))
        catchUpDelay = TimeInterval(int(ForkDefaultsKey.macBackupCatchUpDelayMinutes, 0...120, fallback: 3) * 60)
        powerMode = PowerMode(rawValue: string(ForkDefaultsKey.macBackupPowerMode)) ?? .threshold
        minBatteryPercent = int(ForkDefaultsKey.macBackupPowerMinPercent, 0...100, fallback: 30)
        forceAfter = TimeInterval(int(ForkDefaultsKey.macBackupPowerForceAfterHours, 1...720, fallback: 24) * 3_600)
        lowPowerWaits = bool(ForkDefaultsKey.macBackupLowPowerWaits)
        limitedNetwork = NetworkMode(rawValue: string(ForkDefaultsKey.macBackupLimitedNetwork)) ?? .wait
        meetingMode = MeetingMode(rawValue: string(ForkDefaultsKey.macBackupMeetingMode)) ?? .slow
        slowBytesPerSecond = Int64(int(ForkDefaultsKey.macBackupSlowMBps, 1...1_000, fallback: 2)) * 1_000_000
        throttleWindow = ThrottleWindow.parse(string(ForkDefaultsKey.macBackupThrottleWindow))
        keepAwake = KeepAwake(rawValue: string(ForkDefaultsKey.macBackupKeepAwake)) ?? .ac
        earlyEnabled = bool(ForkDefaultsKey.macBackupEarlyEnabled)
        earlyThreshold = int(ForkDefaultsKey.macBackupEarlyThreshold, 1...1_000_000, fallback: 200)
        iCloud = ForkMacBackupICloudMode(rawValue: string(ForkDefaultsKey.macBackupICloudMode)) ?? .fallback
        retention = ForkMacBackupRetention.preset(
            ForkMacBackupRetention.Preset(rawValue: string(ForkDefaultsKey.macBackupRetentionPreset)) ?? .fallback,
            custom: string(ForkDefaultsKey.macBackupRetentionCustom))
        repository = json(ForkMacBackupRepository.self, ForkDefaultsKey.macBackupRepository)
        // The rules are the person's settings, not the copies kept with each
        // source: an imported settings backup restores these two keys only.
        let storedPresets = value(ForkDefaultsKey.macBackupPresets) as? String
        let storedRules = value(ForkDefaultsKey.macBackupRules) as? String
        sources = (json([ForkMacBackupSource].self, ForkDefaultsKey.macBackupSources) ?? []).map {
            $0.applying(presets: storedPresets, rules: storedRules)
        }
        profile = json(ForkMacBackupProfile.self, ForkDefaultsKey.macBackupProfile)
        priority = Priority(rawValue: string(ForkDefaultsKey.macBackupPriority)) ?? .low
        watchdog = TimeInterval(int(ForkDefaultsKey.macBackupWatchdogMinutes, 2...240, fallback: 10) * 60)
        repositoryTimeout = TimeInterval(int(ForkDefaultsKey.macBackupRepositoryTimeout, 10...600, fallback: 60))
        probeTimeout = TimeInterval(int(ForkDefaultsKey.macBackupProbeTimeout, 1...60, fallback: 5))
    }

    /// The engine's priority for a run: « Sauvegarder maintenant » and the
    /// other buttons run normal, the planner's runs as the person chose,
    /// except the very first backup (nothing protected yet, the setup just
    /// ended): it runs normal too, whoever started it.
    func enginePriority(for trigger: ForkMacBackupTrigger, firstBackup: Bool = false)
        -> ForkMacBackupKopiaInvocation.Priority {
        if firstBackup { return .normal }
        switch trigger {
        case .island, .settings, .commandBar, .window: return .normal
        case .scheduled, .catchUp, .early, .agent: return priority == .low ? .background : .utility
        }
    }

    /// The maximum interval of the Automatic rhythm for this power source.
    func autoMaxInterval(onAC: Bool) -> TimeInterval {
        onAC ? ForkMacBackupAgentTuning.autoMaxIntervalAC : ForkMacBackupAgentTuning.autoMaxIntervalBattery
    }
}
