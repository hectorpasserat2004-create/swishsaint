// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// The island's decisions about Mac Backup, apart from its views, so each
/// one is tested: when the closed island shows the backup and where among
/// its activities, what its wings read, what the section leads with, which
/// notice ends a run, when the mascot reacts, which card is offered, and
/// which Command Bar rows answer. Martial's decisions of 22/10 are enforced
/// here: the closed island only shows something running, never a delay or
/// a problem; notices only end a run or a restore.
enum ForkMacBackupIslandRules {
    // MARK: - The closed island

    /// How long the finished ring stays, turned into a checkmark, before the
    /// activity leaves and the end-of-run notice takes the island.
    static let finishHold: TimeInterval = 1.4

    /// Whether the closed island lists the backup among its activities:
    /// the feature on, the setting « while one runs », and a backup, a
    /// restore or a verification running (or just finished, for the ring's
    /// checkmark).
    static func showsActivity(enabled: Bool, setting: ForkMacBackupCompactSetting, phase: ForkMacBackupPhase,
                              finishing: Bool) -> Bool {
        guard enabled, setting == .running else { return false }
        return phase.showsInClosedIsland || finishing
    }

    /// The activities the person started and waits for come first (a
    /// meeting, a timer, a watched area, a download); the backup goes right
    /// after them, before the agents, the calendar, the music and Keep
    /// Awake, which often occupy the island.
    static func ordered(_ activities: [NotchCompactActivity], showing: Bool) -> [NotchCompactActivity] {
        var list = activities.filter { $0 != .macBackup }
        guard showing else { return list }
        let before: Set<NotchCompactActivity> = [.meeting, .timer, .watch, .downloads]
        let index = (list.lastIndex { before.contains($0) }).map { $0 + 1 } ?? 0
        list.insert(.macBackup, at: min(index, list.count))
        return list
    }

    /// The glyph inside the ring.
    enum Glyph: Equatable {
        case upload
        case download
        case verify
        case done

        var symbol: String {
            switch self {
            case .upload: return "arrow.up"
            case .download: return "arrow.down"
            case .verify: return "checkmark.shield"
            case .done: return "checkmark"
            }
        }
    }

    static func glyph(phase: ForkMacBackupPhase, finishing: Bool) -> Glyph {
        if finishing { return .done }
        switch phase {
        case .restoring: return .download
        case .verifying: return .verify
        default: return .upload
        }
    }

    /// The ring's share: full once finished, the real share while bytes
    /// move, nil (a turning arc) while nothing honest can be said.
    static func ringProgress(_ state: ForkMacBackupPresentation, finishing: Bool) -> Double? {
        finishing ? 1 : state.fraction
    }

    /// The right wing: the percentage or the time left, as chosen, never a
    /// guess (`ForkMacBackupPresentation.compactValue`).
    static func reading(_ state: ForkMacBackupPresentation, text: ForkMacBackupStrings, locale: Locale,
                        reading: ForkMacBackupReading, finishing: Bool) -> String {
        if finishing { return ForkMacBackupFormat.percent(1, locale: locale) }
        return state.compactValue(text, locale: locale, reading: reading)
    }

    /// Orange when something else than the person's « Ralentir » holds the
    /// backup back (a recorded meeting, the slow window).
    static func readingIsSlowed(_ state: ForkMacBackupPresentation) -> Bool {
        state.phase == .slowed && !state.slowDown
    }

    // MARK: - The section

    /// What the section leads with.
    enum Top: Equatable {
        case off
        case notConfigured
        case rest
        case running
        case waiting(ForkMacBackupWaitReason)
        case paused
        case partial(files: Int)
        case failed(ForkMacBackupRunFailure)
        case restoring
        case verifying
        case maintaining
    }

    static func top(_ phase: ForkMacBackupPhase) -> Top {
        switch phase {
        case .off: return .off
        case .notConfigured: return .notConfigured
        case .ready, .finished(.complete), .finished(.nothingToDo): return .rest
        case .waiting(let reason, _): return .waiting(reason)
        case .checkingChain, .preparing, .scanning, .uploading, .slowed, .concluding: return .running
        case .paused: return .paused
        case .finished(.partial(let files)): return .partial(files: files)
        case .finished(.failed(let failure)): return .failed(failure)
        case .restoring: return .restoring
        case .verifying: return .verifying
        case .maintaining: return .maintaining
        }
    }

    /// The one button beside the camera.
    enum Primary: Equatable {
        case backUpNow
        case backUpAnyway
        case pause
        case resume
        case none
    }

    static func primary(_ phase: ForkMacBackupPhase) -> Primary {
        switch phase {
        case .off, .notConfigured, .restoring, .verifying, .maintaining: return .none
        case .checkingChain, .preparing, .scanning, .uploading, .slowed, .concluding: return .pause
        case .paused: return .resume
        case .waiting: return .backUpAnyway
        case .ready, .finished: return .backUpNow
        }
    }

    /// The interval the rhythm keeps, for the ring at rest: the Automatic
    /// rhythm's measured one (a day while unmeasured), every N hours, or a
    /// day shared between fixed times.
    static func interval(of rhythm: ForkMacBackupPresentation.Rhythm) -> TimeInterval {
        let day: TimeInterval = 86_400
        switch rhythm {
        case .automatic(let about): return about.flatMap { $0 > 0 ? $0 : nil } ?? day
        case .interval(let hours): return TimeInterval(max(1, hours)) * 3_600
        case .times(let times): return day / Double(max(1, times.count))
        case .both(let hours, let times):
            return min(TimeInterval(max(1, hours)) * 3_600, day / Double(max(1, times.count)))
        }
    }

    /// The ring at rest: full right after a backup, empty at the next one
    /// due; nil with nothing protected yet.
    static func freshness(protectedSince: Date?, interval: TimeInterval, now: Date) -> Double? {
        guard let protectedSince, interval > 0 else { return nil }
        let age = max(0, now.timeIntervalSince(protectedSince))
        return min(1, max(0, 1 - age / interval))
    }

    /// The ring's colour at rest: sarcelle while on time, orange past twice
    /// the interval, red past the late threshold (`notify.lateHours`).
    static func freshnessTone(protectedSince: Date?, interval: TimeInterval, lateHours: Int,
                              now: Date) -> ForkMacBackupPresentation.Tone {
        guard let protectedSince else { return .calm }
        let age = now.timeIntervalSince(protectedSince)
        if lateHours > 0, age > TimeInterval(lateHours) * 3_600 { return .red }
        if interval > 0, age > 2 * interval { return .orange }
        return .teal
    }

    /// How many of the four proof dots are filled.
    static func proofDots(_ level: ForkMacBackupProofLevel?) -> Int {
        level.map { $0.rawValue + 1 } ?? 0
    }

    /// The pause menu's three choices.
    enum PauseChoice: CaseIterable {
        case oneHour
        case untilTomorrow
        case untilResumed
    }

    /// When the pause ends: in an hour, tomorrow at 8:00, or never (nil).
    static func pauseEnd(_ choice: PauseChoice, now: Date, calendar: Calendar = .current) -> Date? {
        switch choice {
        case .oneHour: return now.addingTimeInterval(3_600)
        case .untilTomorrow:
            let start = calendar.startOfDay(for: now)
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: start) else {
                return now.addingTimeInterval(86_400)
            }
            return calendar.date(bySettingHour: 8, minute: 0, second: 0, of: tomorrow) ?? tomorrow
        case .untilResumed: return nil
        }
    }

    /// « aujourd’hui 10:04 », « hier 19:14 », else « 16 oct., 19:14 », in
    /// the locale's own clock.
    static func when(_ date: Date, now: Date, locale: Locale, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now)
            || calendar.date(byAdding: .day, value: -1, to: now).map({ calendar.isDate(date, inSameDayAs: $0) }) == true {
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.timeZone = calendar.timeZone
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            formatter.doesRelativeDateFormatting = true
            return formatter.string(from: date)
        }
        return ForkMacBackupFormat.dayAndTime(date, locale: locale, timeZone: calendar.timeZone)
    }

    /// The section's height: compact (180 pt) unless « spacious » (264 pt).
    static func sectionHeight(_ stored: String?) -> Double {
        stored == "spacious" ? 264 : 180
    }

    // MARK: - The tile

    /// The tile's reading: « 42 % » while something runs, « il y a 2 h » at
    /// rest, nothing before the first backup.
    static func tileReading(_ state: ForkMacBackupPresentation, text: ForkMacBackupStrings, locale: Locale,
                            reading: ForkMacBackupReading, now: Date) -> String? {
        if state.phase.showsInClosedIsland { return state.compactValue(text, locale: locale, reading: reading) }
        switch state.phase {
        case .off, .notConfigured: return nil
        default: return state.lastBackup.map { ForkMacBackupFormat.relative($0.date, now: now, locale: locale) }
        }
    }

    /// The tile lights while something runs (white), or in red while the
    /// chain is broken: the tile is inside the island, where the state may
    /// show.
    static func tileAccent(_ state: ForkMacBackupPresentation) -> (active: Bool, alert: Bool) {
        let broken = state.hasBrokenNode || state.phase == .finished(.failed(.chainBroken))
        return (state.phase.showsInClosedIsland || broken, broken && !state.phase.showsInClosedIsland)
    }

    // MARK: - Notices

    /// A notice at the end of something, never in between.
    enum Notice: Equatable {
        case complete(sent: Int64?)
        case partial(files: Int)
        case failed(ForkMacBackupRunFailure)
        case restored(files: Int64?)

        var event: ForkMacBackupNotifyEvent {
            switch self {
            case .complete: return .complete
            case .partial: return .partial
            case .failed: return .failure
            case .restored: return .restoreDone
            }
        }

        var symbol: String {
            switch self {
            case .complete: return "checkmark.circle.fill"
            case .partial: return "exclamationmark.circle"
            case .failed: return "xmark.octagon"
            case .restored: return "arrow.down.circle.fill"
            }
        }
    }

    /// The result of a run that just ended: a backup phase before, a
    /// finished one now. Nothing for « nothing to do », nor for a state
    /// read at launch.
    static func endedRun(from old: ForkMacBackupPhase, to new: ForkMacBackupPhase) -> ForkMacBackupRunResult? {
        guard old.isBackingUp, case .finished(let result) = new else { return nil }
        if case .nothingToDo = result { return nil }
        return result
    }

    /// A restore just ended (the restore phase left for anything else).
    static func endedRestore(from old: ForkMacBackupPhase, to new: ForkMacBackupPhase) -> Bool {
        old == .restoring && new != .restoring
    }

    /// The notice a run's end deserves, if its event goes to the island.
    static func notice(for result: ForkMacBackupRunResult, sent: Int64?,
                       channel: (ForkMacBackupNotifyEvent) -> ForkMacBackupNotifyChannel) -> Notice? {
        let notice: Notice
        switch result {
        case .complete: notice = .complete(sent: sent)
        case .partial(let files): notice = .partial(files: files)
        case .failed(let failure):
            // Stopped by the person: nothing to tell them.
            guard failure != .canceled else { return nil }
            notice = .failed(failure)
        case .nothingToDo: return nil
        }
        return showsInIsland(channel(notice.event)) ? notice : nil
    }

    static func showsInIsland(_ channel: ForkMacBackupNotifyChannel) -> Bool {
        channel == .island || channel == .both
    }

    /// The stored channel; anything unknown reads as the event's default.
    static func channel(_ stored: String?, event: ForkMacBackupNotifyEvent) -> ForkMacBackupNotifyChannel {
        stored.flatMap(ForkMacBackupNotifyChannel.init(rawValue:)) ?? event.defaultChannel
    }

    /// The island's switch for one event: on keeps a system notification
    /// the person chose (both), off keeps it alone (system).
    static func channel(_ current: ForkMacBackupNotifyChannel, island: Bool) -> ForkMacBackupNotifyChannel {
        switch (current, island) {
        case (.island, true), (.both, true): return current
        case (.system, true): return .both
        case (.none, true): return .island
        case (.both, false): return .system
        case (.island, false): return .none
        case (.system, false), (.none, false): return current
        }
    }

    // MARK: - The mascot

    /// It cheers the first complete backup, and the one that ends a series
    /// of failures; a failure puzzles it.
    static func mascot(for result: ForkMacBackupRunResult, hadComplete: Bool,
                       failuresBefore: Int) -> NotchMascotReaction? {
        switch result {
        case .complete: return !hadComplete || failuresBefore >= 2 ? .celebrate : nil
        case .failed(let failure): return failure == .canceled ? nil : .confused
        case .partial, .nothingToDo: return nil
        }
    }

    /// The failures in a row after this result.
    static func failures(after result: ForkMacBackupRunResult, before: Int) -> Int {
        switch result {
        case .failed(.canceled), .nothingToDo: return before
        case .failed: return before + 1
        case .complete, .partial: return 0
        }
    }

    // MARK: - Cards

    static let offeredFirstBackup = "island.firstBackup"
    static let offeredBran = "island.bran"

    /// `fork.macbackup.offered`, comma-separated.
    static func offered(_ stored: String?) -> Set<String> {
        Set((stored ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    }

    static func adding(_ name: String, to stored: String?) -> String {
        (offered(stored).union([name])).sorted().joined(separator: ",")
    }

    /// The first backup is about to go and has a lot to send: offered once,
    /// so the person can choose what goes, or let it start plugged in.
    static func offersFirstBackup(_ state: ForkMacBackupPresentation, offered: Set<String>,
                                  heavyBytes: Int64 = 5_000_000_000) -> Bool {
        guard !offered.contains(offeredFirstBackup), !state.sources.isEmpty, state.lastBackup == nil else { return false }
        if let bytes = state.capacity.protectedBytes, bytes < heavyBytes { return false }
        switch state.phase {
        case .ready, .waiting(.power, _), .waiting(.lowBattery, _): return true
        default: return false
        }
    }

    /// Bran still backs this Mac up after its import: offered once.
    static func offersBranStop(_ state: ForkMacBackupPresentation, branImported: Bool, offered: Set<String>) -> Bool {
        guard branImported, !offered.contains(offeredBran) else { return false }
        if case .waiting(.otherEngine, _) = state.phase { return true }
        return false
    }

    // MARK: - Command Bar

    /// Why the rows cannot do their thing yet.
    enum BarTrouble: Equatable {
        /// The feature is off: Return opens its page.
        case featureOff
        /// On, not set up yet: Return opens its page.
        case notConfigured
        /// No Full Disk Access: the backup reads nothing worth having.
        case diskAccess
    }

    /// The rows the bar lists, from the state.
    struct BarRows: Equatable {
        var backUpNow: Bool
        var pause: Bool
        var resume: Bool
        var verify: Bool
        var trouble: BarTrouble?
    }

    static func barRows(enabled: Bool, phase: ForkMacBackupPhase, fullDiskAccess: Bool) -> BarRows {
        guard enabled else { return BarRows(backUpNow: true, pause: false, resume: false, verify: false, trouble: .featureOff) }
        if phase == .notConfigured || phase == .off {
            return BarRows(backUpNow: true, pause: false, resume: false, verify: false, trouble: .notConfigured)
        }
        var waitsForAccess = false
        if case .waiting(.noDiskAccess, _) = phase { waitsForAccess = true }
        let trouble: BarTrouble? = fullDiskAccess && !waitsForAccess ? nil : .diskAccess
        let paused: Bool
        if case .paused = phase { paused = true } else { paused = false }
        return BarRows(backUpNow: !phase.isBackingUp && !paused, pause: phase.isBackingUp, resume: paused,
                       verify: !phase.isBackingUp && phase != .verifying, trouble: trouble)
    }

    /// « Protégé il y a 2 h · Prochaine à 13:00 », the status row's answer.
    static func statusAnswer(_ state: ForkMacBackupPresentation, text: ForkMacBackupStrings, language: AppLanguage,
                             locale: Locale, now: Date) -> String {
        var parts = [state.headline(text, language: language, locale: locale, now: now)]
        if case .ready = state.phase, state.protectedSince != nil, let next = state.nextRun, next > now {
            parts.append(String(format: text.nextAt, ForkMacBackupFormat.time(next, locale: locale)))
        }
        return parts.joined(separator: " · ")
    }
}
