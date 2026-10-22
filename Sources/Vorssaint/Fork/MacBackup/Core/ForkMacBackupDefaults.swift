// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// Mac Backup's preference keys (plan §14, with Martial's decisions of
/// 22/10). Registered ones follow the person (settings backup): Bool, Int or
/// String only, the import ignores other types. Machine state is never
/// registered, so it never leaves this Mac.
extension ForkDefaultsKey {
    static let macBackupEnabled = "fork.macbackup.enabled"
    /// `ForkMacBackupScheduleMode`: auto, interval, times or both.
    static let macBackupScheduleMode = "fork.macbackup.schedule.mode"
    static let macBackupIntervalHours = "fork.macbackup.schedule.intervalHours"
    /// « 13:00,21:00 », 24-hour, shown in the person's clock.
    static let macBackupTimes = "fork.macbackup.schedule.times"
    /// Minutes after a wake or a login before a missed slot is caught up.
    static let macBackupCatchUpDelayMinutes = "fork.macbackup.schedule.catchUpDelayMinutes"
    /// `always`, `ac` or `threshold` (battery above `minPercent`).
    static let macBackupPowerMode = "fork.macbackup.power.mode"
    static let macBackupPowerMinPercent = "fork.macbackup.power.minPercent"
    /// Past this many hours late, the power and Low Power conditions give way.
    static let macBackupPowerForceAfterHours = "fork.macbackup.power.forceAfterHours"
    static let macBackupLowPowerWaits = "fork.macbackup.power.lowPowerWaits"
    /// A limited or expensive network: `wait`, `slow` or `ignore`.
    static let macBackupLimitedNetwork = "fork.macbackup.network.limited"
    /// During a recorded meeting: `pause`, `slow` or `none`.
    static let macBackupMeetingMode = "fork.macbackup.meeting.mode"
    /// The « Ralentir » limit, in MB/s.
    static let macBackupSlowMBps = "fork.macbackup.throttle.slowMBps"
    /// « 09:00-19:00@5 »: a window with a lower limit; empty: none.
    static let macBackupThrottleWindow = "fork.macbackup.throttle.window"
    /// `never`, `ac` or `always`.
    static let macBackupKeepAwake = "fork.macbackup.keepAwake"
    /// A backup ahead of the slot after many important changes.
    static let macBackupEarlyEnabled = "fork.macbackup.early.enabled"
    static let macBackupEarlyThreshold = "fork.macbackup.early.threshold"
    /// `ForkMacBackupICloudMode`.
    static let macBackupICloudMode = "fork.macbackup.icloud.mode"
    /// The presets applied to a new source (`ForkMacBackupPreset.storageValue`).
    static let macBackupPresets = "fork.macbackup.presets"
    /// Free rules applied to a new source, JSON array of strings; empty: none.
    static let macBackupRules = "fork.macbackup.rules"
    /// `ForkMacBackupRetention.Preset`.
    static let macBackupRetentionPreset = "fork.macbackup.retention.preset"
    /// « 10,48,30,8,12,3 », read when the preset is custom.
    static let macBackupRetentionCustom = "fork.macbackup.retention.custom"
    /// « refs:7d,files1:1d,restore50:30d ».
    static let macBackupVerifyPlan = "fork.macbackup.verify.plan"
    static let macBackupNotifyLateHours = "fork.macbackup.notify.lateHours"
    static let macBackupNotifyNASFreePercent = "fork.macbackup.notify.nasFreePercent"
    /// `ForkMacBackupCompactSetting`: running or never (decision 2 of 22/10).
    static let macBackupIslandCompact = "fork.macbackup.island.compact"
    /// `ForkMacBackupReading`: percent or remaining.
    static let macBackupIslandReading = "fork.macbackup.island.reading"
    static let macBackupIslandShowChain = "fork.macbackup.island.showChain"
    static let macBackupIslandShowPending = "fork.macbackup.island.showPending"
    /// The section's size: `compact` (180 pt) or `spacious` (264 pt).
    static let macBackupIslandSize = "fork.macbackup.island.size"

    /// `fork.macbackup.notify.<event>`: `ForkMacBackupNotifyChannel` per
    /// `ForkMacBackupNotifyEvent`.
    static func macBackupNotify(_ event: ForkMacBackupNotifyEvent) -> String {
        "fork.macbackup.notify.\(event.rawValue)"
    }

    // MARK: Machine state (never registered, never exported)

    /// `ForkMacBackupRepository`, JSON.
    static let macBackupRepository = "fork.macbackup.repository"
    /// `[ForkMacBackupSource]`, JSON (absolute paths).
    static let macBackupSources = "fork.macbackup.sources"
    /// `ForkMacBackupProfile`, JSON: the active profile (its chain is drawn).
    static let macBackupProfile = "fork.macbackup.profile"
    /// Infrastructure adapters (SSH aliases…), JSON, phase 3.
    static let macBackupAdapters = "fork.macbackup.adapters"
    /// The Kopia version installed and in use.
    static let macBackupEngineVersion = "fork.macbackup.engineVersion"
    /// The recovery kit: made on, remind on (seconds since 1970).
    static let macBackupKitCreatedAt = "fork.macbackup.kitCreatedAt"
    static let macBackupKitRemindAt = "fork.macbackup.kitRemindAt"
    static let macBackupBranImportedAt = "fork.macbackup.branImportedAt"
    /// The offers already made on this Mac (comma-separated names).
    static let macBackupOffered = "fork.macbackup.offered"
}

/// `fork.macbackup.schedule.mode`.
enum ForkMacBackupScheduleMode: String, CaseIterable {
    /// Paced by the measured cost and the changes (plan §3.9.1).
    case auto
    case interval
    case times
    case both

    static let fallback: ForkMacBackupScheduleMode = .auto
}

/// The events a notice or a notification can follow (plan §12).
enum ForkMacBackupNotifyEvent: String, CaseIterable {
    case start
    case complete
    case partial
    case failure
    case late
    case chainBroken
    case chainRestored
    case nasLow
    case verifyFailed
    case restoreDone
    case kitStale

    /// Decision 3 of 22/10: nothing outside the section by default, but the
    /// end-of-backup notice in the island.
    var defaultChannel: ForkMacBackupNotifyChannel {
        self == .complete ? .island : .none
    }
}

enum ForkMacBackupNotifyChannel: String, CaseIterable {
    case island
    case system
    case both
    case none
}

enum ForkMacBackupDefaults {
    /// Every setting that follows the person, with its default. Merged into
    /// `ForkDefaults.registered`.
    static let registered: [String: Any] = {
        var values: [String: Any] = [
            ForkDefaultsKey.macBackupEnabled: false,
            ForkDefaultsKey.macBackupScheduleMode: ForkMacBackupScheduleMode.fallback.rawValue,
            ForkDefaultsKey.macBackupIntervalHours: 4,
            ForkDefaultsKey.macBackupTimes: "13:00,21:00",
            ForkDefaultsKey.macBackupCatchUpDelayMinutes: 3,
            ForkDefaultsKey.macBackupPowerMode: "threshold",
            ForkDefaultsKey.macBackupPowerMinPercent: 30,
            ForkDefaultsKey.macBackupPowerForceAfterHours: 24,
            ForkDefaultsKey.macBackupLowPowerWaits: true,
            ForkDefaultsKey.macBackupLimitedNetwork: "wait",
            ForkDefaultsKey.macBackupMeetingMode: "slow",
            ForkDefaultsKey.macBackupSlowMBps: 2,
            ForkDefaultsKey.macBackupThrottleWindow: "",
            ForkDefaultsKey.macBackupKeepAwake: "ac",
            ForkDefaultsKey.macBackupEarlyEnabled: false,
            ForkDefaultsKey.macBackupEarlyThreshold: 200,
            ForkDefaultsKey.macBackupICloudMode: ForkMacBackupICloudMode.fallback.rawValue,
            ForkDefaultsKey.macBackupPresets: ForkMacBackupPreset.storageValue(ForkMacBackupPreset.defaultApplied),
            ForkDefaultsKey.macBackupRules: "",
            ForkDefaultsKey.macBackupRetentionPreset: ForkMacBackupRetention.Preset.fallback.rawValue,
            ForkDefaultsKey.macBackupRetentionCustom: ForkMacBackupRetention.balanced.storageValue,
            ForkDefaultsKey.macBackupVerifyPlan: "refs:7d,files1:1d,restore50:30d",
            ForkDefaultsKey.macBackupNotifyLateHours: 24,
            ForkDefaultsKey.macBackupNotifyNASFreePercent: 10,
            ForkDefaultsKey.macBackupIslandCompact: ForkMacBackupCompactSetting.fallback.rawValue,
            ForkDefaultsKey.macBackupIslandReading: ForkMacBackupReading.fallback.rawValue,
            ForkDefaultsKey.macBackupIslandShowChain: true,
            ForkDefaultsKey.macBackupIslandShowPending: true,
            ForkDefaultsKey.macBackupIslandSize: "compact",
        ]
        for event in ForkMacBackupNotifyEvent.allCases {
            values[ForkDefaultsKey.macBackupNotify(event)] = event.defaultChannel.rawValue
        }
        return values
    }()

    /// Machine state: never registered, never in the settings backup.
    static let machineKeys: [String] = [
        ForkDefaultsKey.macBackupRepository, ForkDefaultsKey.macBackupSources, ForkDefaultsKey.macBackupProfile,
        ForkDefaultsKey.macBackupAdapters, ForkDefaultsKey.macBackupEngineVersion,
        ForkDefaultsKey.macBackupKitCreatedAt, ForkDefaultsKey.macBackupKitRemindAt,
        ForkDefaultsKey.macBackupBranImportedAt, ForkDefaultsKey.macBackupOffered,
    ]
}
