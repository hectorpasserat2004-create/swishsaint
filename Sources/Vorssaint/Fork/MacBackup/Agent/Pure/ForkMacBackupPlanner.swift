// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// What the Mac looks like right now, as the agent's watchers see it. Pure
/// value: the planner reads it, the tests build it.
struct ForkMacBackupConditions: Equatable {
    enum Network: Equatable {
        case unknown
        case none
        /// Satisfied; `limited` when expensive (tethering) or constrained (Low Data Mode).
        case available(limited: Bool)
    }

    var onAC = true
    /// 0…100; nil without a battery.
    var batteryPercent: Int?
    var lowPowerMode = false
    var network: Network = .unknown
    /// nil: no peer to watch, or Tailscale could not be asked.
    var peerOnline: Bool?
    var meetingBusy = false
    var engineAvailable = true
    var wrongRepository = false
    /// false only when access is known to be refused.
    var diskAccess = true
    var localSpaceLow = false
    /// Another Kopia writes to the same repository.
    var otherEngine = false
    /// The updater is about to replace the app.
    var updateHold = false

    init(onAC: Bool = true, batteryPercent: Int? = nil, lowPowerMode: Bool = false, network: Network = .unknown,
         peerOnline: Bool? = nil, meetingBusy: Bool = false, engineAvailable: Bool = true,
         wrongRepository: Bool = false, diskAccess: Bool = true, localSpaceLow: Bool = false,
         otherEngine: Bool = false, updateHold: Bool = false) {
        self.onAC = onAC
        self.batteryPercent = batteryPercent
        self.lowPowerMode = lowPowerMode
        self.network = network
        self.peerOnline = peerOnline
        self.meetingBusy = meetingBusy
        self.engineAvailable = engineAvailable
        self.wrongRepository = wrongRepository
        self.diskAccess = diskAccess
        self.localSpaceLow = localSpaceLow
        self.otherEngine = otherEngine
        self.updateHold = updateHold
    }
}

/// The weighted count of changes not protected yet (§5.5); nil in the
/// planner when FSEvents could not count them.
struct ForkMacBackupPendingSummary: Equatable {
    var total: Int
    var important: Int
    var weighted: Double

    static let none = ForkMacBackupPendingSummary(total: 0, important: 0, weighted: 0)
}

/// When to back up (plan §3.9, §3.9.1). Pure: the clock, the calendar, the
/// settings and the conditions are passed in, so the tests pin a time zone
/// (DST included) and never assume a 24-hour clock.
enum ForkMacBackupPlanner {
    struct Input {
        var now: Date
        var calendar: Calendar
        var settings: ForkMacBackupAgentSettings
        var conditions: ForkMacBackupConditions
        /// The end of the last backup that left a snapshot (complete or partial).
        var lastBackup: Date?
        /// The due date of the last slot already written to the ledger.
        var lastClosedDue: Date?
        /// The slot being worked on, when one is open: its due date stays put.
        var openSlotDue: Date?
        var pending: ForkMacBackupPendingSummary?
        /// After a failure: no new attempt before this.
        var retryAt: Date?
        /// A run stopped by a pause or a meeting, resumed as soon as allowed.
        var interrupted: ForkMacBackupTrigger?
        /// The last wake or the agent's start: a due date before it was missed asleep or off.
        var wokeAt: Date?
        /// « Sauvegarder maintenant »: runs past the conditions that pass on their own.
        var manual: ForkMacBackupTrigger?

        init(now: Date, calendar: Calendar, settings: ForkMacBackupAgentSettings,
             conditions: ForkMacBackupConditions = ForkMacBackupConditions(), lastBackup: Date? = nil,
             lastClosedDue: Date? = nil, openSlotDue: Date? = nil, pending: ForkMacBackupPendingSummary? = nil,
             retryAt: Date? = nil, interrupted: ForkMacBackupTrigger? = nil, wokeAt: Date? = nil,
             manual: ForkMacBackupTrigger? = nil) {
            self.now = now
            self.calendar = calendar
            self.settings = settings
            self.conditions = conditions
            self.lastBackup = lastBackup
            self.lastClosedDue = lastClosedDue
            self.openSlotDue = openSlotDue
            self.pending = pending
            self.retryAt = retryAt
            self.interrupted = interrupted
            self.wokeAt = wokeAt
            self.manual = manual
        }
    }

    enum Decision: Equatable {
        case off
        case notConfigured
        /// Back up now; `due` is the slot it fills (nil for a run outside the schedule).
        case run(trigger: ForkMacBackupTrigger, due: Date?)
        /// A slot is due but a condition holds it. `recheck`: when to look
        /// again without a notification; `forcedAt`: when the soft
        /// conditions give way.
        case wait(reason: ForkMacBackupWaitReason, due: Date?, recheck: Date?, forcedAt: Date?)
        /// Nothing due before `next`.
        case idle(next: Date?)
        /// Automatic and nothing changed: the slot is written « nothing to do ».
        case nothingToDo(due: Date, next: Date?)
    }

    // MARK: Decision

    static func decide(_ input: Input) -> Decision {
        let settings = input.settings
        let now = input.now
        guard settings.enabled else { return .off }
        guard settings.isConfigured else { return .notConfigured }
        // The updater is about to replace the app: nothing starts meanwhile.
        if input.conditions.updateHold { return .idle(next: nil) }

        // « Sauvegarder maintenant » and a resumed run: outside the schedule.
        if let manual = input.manual {
            if let reason = blockingReason(input, forced: true, manual: true) {
                return .wait(reason: reason, due: input.openSlotDue, recheck: recheck(reason, now: now), forcedAt: nil)
            }
            return .run(trigger: manual, due: input.openSlotDue)
        }
        if let interrupted = input.interrupted {
            if let reason = blockingReason(input, forced: false, manual: false) {
                return .wait(reason: reason, due: input.openSlotDue, recheck: recheck(reason, now: now), forcedAt: nil)
            }
            return .run(trigger: interrupted, due: input.openSlotDue)
        }

        // What cannot work or would harm holds every slot, retries included.
        if let reason = blockingReason(input, forced: true, manual: true) {
            return .wait(reason: reason, due: input.openSlotDue, recheck: recheck(reason, now: now), forcedAt: nil)
        }
        // A failure waits for its retry.
        if let retryAt = input.retryAt, retryAt > now {
            return .idle(next: retryAt)
        }

        let due = input.openSlotDue ?? currentDue(input)
        let early = earlyTrigger(input)
        guard let due else { return .idle(next: nil) }

        if due > now {
            if let early {
                if let reason = blockingReason(input, forced: false, manual: false) {
                    return .wait(reason: reason, due: nil, recheck: recheck(reason, now: now), forcedAt: nil)
                }
                return .run(trigger: early, due: nil)
            }
            return .idle(next: due)
        }

        // Due. Caught up after a wake, once the network had time to come back.
        var trigger: ForkMacBackupTrigger = .scheduled
        if let woke = input.wokeAt, woke > due {
            let catchUp = woke.addingTimeInterval(settings.catchUpDelay)
            if now < catchUp { return .idle(next: catchUp) }
            trigger = .catchUp
        }
        if settings.scheduleMode == .auto, let pending = input.pending, pending.total == 0, input.lastBackup != nil {
            return .nothingToDo(due: due, next: due.addingTimeInterval(settings.autoMaxInterval(onAC: input.conditions.onAC)))
        }
        let forcedAt = due.addingTimeInterval(settings.forceAfter)
        let forced = now >= forcedAt
        if let reason = blockingReason(input, forced: forced, manual: false) {
            let softReason = isSoft(reason)
            return .wait(reason: reason, due: due, recheck: recheck(reason, now: now),
                         forcedAt: softReason && !forced ? forcedAt : nil)
        }
        return .run(trigger: trigger, due: due)
    }

    /// The trigger of a backup ahead of its slot: Automatic once the
    /// weighted changes reach the need, or the « sauvegarde anticipée »
    /// option of the manual rhythms. nil otherwise.
    static func earlyTrigger(_ input: Input) -> ForkMacBackupTrigger? {
        guard let pending = input.pending else { return nil }
        let sinceLast = input.lastBackup.map { input.now.timeIntervalSince($0) } ?? .infinity
        guard sinceLast >= ForkMacBackupAgentTuning.autoMinInterval else { return nil }
        switch input.settings.scheduleMode {
        case .auto:
            let need = input.conditions.onAC ? ForkMacBackupAgentTuning.autoNeedAC : ForkMacBackupAgentTuning.autoNeedBattery
            return pending.weighted >= need ? .scheduled : nil
        case .interval, .times, .both:
            guard input.settings.earlyEnabled else { return nil }
            return pending.important >= input.settings.earlyThreshold ? .early : nil
        }
    }

    // MARK: Due dates

    /// The slot due now or next: the first due date after the last slot
    /// written and after the last backup. nil: never (no time set).
    static func currentDue(_ input: Input) -> Date? {
        let settings = input.settings
        let reference = [input.lastBackup, input.lastClosedDue].compactMap { $0 }.max()
        switch settings.scheduleMode {
        case .auto:
            guard let reference else { return input.now }
            return reference.addingTimeInterval(settings.autoMaxInterval(onAC: input.conditions.onAC))
        case .interval:
            guard let reference else { return input.now }
            return intervalDue(after: reference, hours: settings.intervalHours)
        case .times:
            return timesDue(after: reference ?? input.now.addingTimeInterval(-1), times: settings.times,
                            calendar: input.calendar)
        case .both:
            let interval = reference.map { intervalDue(after: $0, hours: settings.intervalHours) } ?? input.now
            let times = timesDue(after: reference ?? input.now.addingTimeInterval(-1), times: settings.times,
                                 calendar: input.calendar)
            return [interval, times].compactMap { $0 }.min()
        }
    }

    /// Every due date strictly after `start` up to `end` included, in the
    /// schedule's own rhythm (the ledger's missed slots after a long sleep).
    /// Bounded, a month of hourly slots at most.
    static func dues(after start: Date, through end: Date, settings: ForkMacBackupAgentSettings, onAC: Bool,
                     calendar: Calendar, limit: Int = 744) -> [Date] {
        var dates: [Date] = []
        var cursor = start
        while dates.count < limit {
            let next: Date?
            switch settings.scheduleMode {
            case .auto: next = cursor.addingTimeInterval(settings.autoMaxInterval(onAC: onAC))
            case .interval: next = intervalDue(after: cursor, hours: settings.intervalHours)
            case .times: next = timesDue(after: cursor, times: settings.times, calendar: calendar)
            case .both:
                next = [intervalDue(after: cursor, hours: settings.intervalHours),
                        timesDue(after: cursor, times: settings.times, calendar: calendar)].compactMap { $0 }.min()
            }
            guard let next, next <= end, next > cursor else { break }
            dates.append(next)
            cursor = next
        }
        return dates
    }

    /// An interval counts elapsed time: a DST change does not stretch it.
    static func intervalDue(after reference: Date, hours: Int) -> Date {
        reference.addingTimeInterval(TimeInterval(max(1, hours)) * 3_600)
    }

    /// The first `times` occurrence strictly after `reference`, in the
    /// calendar's time zone. A time skipped by a DST jump (02:30 on the
    /// spring-forward night) happens at the first instant after the gap; a
    /// time repeated by the fall-back night happens once, the first time.
    static func timesDue(after reference: Date, times: [ForkMacBackupAgentSettings.TimeOfDay],
                         calendar: Calendar) -> Date? {
        guard !times.isEmpty else { return nil }
        let startOfDay = calendar.startOfDay(for: reference)
        for dayOffset in 0...2 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: startOfDay) else { continue }
            for time in times.sorted() {
                var components = calendar.dateComponents([.year, .month, .day], from: day)
                components.hour = time.hour
                components.minute = time.minute
                components.second = 0
                guard let date = calendar.date(from: components) else { continue }
                // `date(from:)` picks the first of two repeated instants and moves a
                // skipped one forward by the gap: both are what a person expects.
                if date > reference { return date }
            }
        }
        return nil
    }

    // MARK: Conditions

    /// Why a run may not start now, the gravest first; nil: it may.
    /// `forced`: past `forceAfter` late, the power conditions give way.
    /// `manual`: the person asked, only what cannot work or would harm holds it.
    static func blockingReason(_ input: Input, forced: Bool, manual: Bool) -> ForkMacBackupWaitReason? {
        let conditions = input.conditions
        let settings = input.settings
        if !conditions.engineAvailable { return .engineMissing }
        if conditions.wrongRepository { return .wrongRepository }
        if conditions.otherEngine { return .otherEngine }
        if conditions.localSpaceLow { return .localSpace }
        if manual { return nil }
        if !conditions.diskAccess { return .noDiskAccess }
        if conditions.network == .none { return .noNetwork }
        if conditions.peerOnline == false { return .peerOffline }
        if conditions.meetingBusy && settings.meetingMode == .pause { return .meeting }
        if case .available(limited: true) = conditions.network, settings.limitedNetwork == .wait { return .limitedNetwork }
        guard !forced else { return nil }
        if !conditions.onAC {
            switch settings.powerMode {
            case .always:
                break
            case .ac:
                return .power
            case .threshold:
                if let percent = conditions.batteryPercent, percent < settings.minBatteryPercent { return .lowBattery }
            }
        }
        if conditions.lowPowerMode && settings.lowPowerWaits { return .lowPowerMode }
        return nil
    }

    /// The conditions that give way after `forceAfter` hours late.
    static func isSoft(_ reason: ForkMacBackupWaitReason) -> Bool {
        reason == .power || reason == .lowBattery || reason == .lowPowerMode
    }

    /// When to look again at a condition that posts no notification.
    static func recheck(_ reason: ForkMacBackupWaitReason, now: Date) -> Date? {
        let delay: TimeInterval?
        switch reason {
        case .peerOffline: delay = ForkMacBackupAgentTuning.peerRecheck
        case .otherEngine: delay = ForkMacBackupAgentTuning.otherEngineRecheck
        case .localSpace: delay = ForkMacBackupAgentTuning.localSpaceRecheck
        case .noDiskAccess: delay = ForkMacBackupAgentTuning.diskAccessRecheck
        case .power, .lowBattery, .lowPowerMode, .noNetwork, .limitedNetwork, .meeting, .notApproved,
             .engineMissing, .wrongRepository, .rulesNotApplied:
            delay = nil
        }
        return delay.map { now.addingTimeInterval($0) }
    }

    // MARK: Live limits

    /// The upload limit in bytes per second while a backup runs; nil: none.
    /// The lowest of the manual « Ralentir », a meeting (slow mode), a
    /// limited network (slow mode) and the throttle window.
    static func uploadLimit(settings: ForkMacBackupAgentSettings, conditions: ForkMacBackupConditions,
                            slowDown: Bool, now: Date, calendar: Calendar) -> Int64? {
        var limits: [Int64] = []
        if slowDown { limits.append(settings.slowBytesPerSecond) }
        if conditions.meetingBusy && settings.meetingMode == .slow { limits.append(settings.slowBytesPerSecond) }
        if case .available(limited: true) = conditions.network, settings.limitedNetwork == .slow {
            limits.append(settings.slowBytesPerSecond)
        }
        if let window = settings.throttleWindow {
            let parts = calendar.dateComponents([.hour, .minute], from: now)
            let time = ForkMacBackupAgentSettings.TimeOfDay(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
            if window.contains(time) { limits.append(Int64(window.megabytesPerSecond * 1_000_000)) }
        }
        return limits.min()
    }

    /// Whether the idle-sleep assertion is held during a run.
    static func keepsAwake(_ policy: ForkMacBackupAgentSettings.KeepAwake, onAC: Bool) -> Bool {
        switch policy {
        case .never: return false
        case .ac: return onAC
        case .always: return true
        }
    }

    /// The meeting asks the run in progress to stop (pause mode).
    static func meetingStopsRun(settings: ForkMacBackupAgentSettings, conditions: ForkMacBackupConditions) -> Bool {
        conditions.meetingBusy && settings.meetingMode == .pause
    }
}
