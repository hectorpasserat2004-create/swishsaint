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

    /// How long the ring takes to fill (its `.smooth(0.3)`, and a breath)
    /// before it turns into the checkmark, within `finishHold`.
    static let fillHold: TimeInterval = 0.35

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

        /// The filled mark the capsule shows beside its meter.
        var capsuleSymbol: String {
            switch self {
            case .upload: return "arrow.up.circle.fill"
            case .download: return "arrow.down.circle.fill"
            case .verify: return "checkmark.shield.fill"
            case .done: return "checkmark.circle.fill"
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
    /// Every byte is sent while the run concludes: the ring stays full
    /// rather than turning again between the last percent and the checkmark.
    static func ringProgress(_ state: ForkMacBackupPresentation, finishing: Bool) -> Double? {
        finishing || state.phase == .concluding ? 1 : share(state)
    }

    /// How far the operation is: its bytes, or for a verification (which
    /// counts files, not bytes) the files checked.
    static func share(_ state: ForkMacBackupPresentation) -> Double? {
        if let fraction = state.fraction { return fraction }
        guard state.phase == .verifying, let progress = state.progress, let total = progress.filesTotal, total > 0 else {
            return nil
        }
        return min(1, max(0, Double(progress.files) / Double(total)))
    }

    /// The right wing: the percentage or the time left, as chosen
    /// (`ForkMacBackupPresentation.compactValue`); while no share is honest
    /// (scanning), the real bytes read so far; else an ellipsis, never a
    /// guess nor a word too long for the wing.
    static func reading(_ state: ForkMacBackupPresentation, text: ForkMacBackupStrings, locale: Locale,
                        reading: ForkMacBackupReading, finishing: Bool) -> String {
        if finishing || state.phase == .concluding { return ForkMacBackupFormat.percent(1, locale: locale) }
        if state.fraction != nil { return state.compactValue(text, locale: locale, reading: reading) }
        if let share = share(state) { return ForkMacBackupFormat.percent(share, locale: locale) }
        if let bytes = state.progress?.bytesDone, bytes > 0 { return ForkMacBackupFormat.bytes(bytes, locale: locale) }
        return "…"
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

    /// The section card's title where its ring already says the number:
    /// « Protégé » beside « 2 h », « Sauvegarde » around « 42 % », never the
    /// same figure twice. Nil: the state's own headline.
    static func heroTitle(_ state: ForkMacBackupPresentation, text: ForkMacBackupStrings) -> String? {
        switch state.phase {
        case .ready, .finished(.nothingToDo):
            return state.protectedSince == nil ? nil : text.protected
        case .uploading where state.fraction != nil: return bare(text.running)
        case .slowed where state.fraction != nil: return bare(text.slowed)
        default: return nil
        }
    }

    /// « Partielle · 3 fichiers » after its word: « 3 fichiers », the
    /// partial notice's detail, in the section's own words.
    static func count(_ phrase: String) -> String {
        guard let range = phrase.range(of: " · ") else { return phrase }
        return String(phrase[range.upperBound...])
    }

    /// « Sauvegarde · %@ » without its figure: « Sauvegarde ».
    static func bare(_ format: String) -> String {
        var words = format.replacingOccurrences(of: "%@", with: "")
        while let last = words.last, last == " " || last == "·" || last == "\u{00A0}" { words.removeLast() }
        return words
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

    /// The ring at rest: full right after a backup, empty when the next one
    /// is due (the planned one, else the rhythm's interval); nil with
    /// nothing protected yet.
    static func freshness(protectedSince: Date?, nextRun: Date? = nil, interval: TimeInterval,
                          now: Date) -> Double? {
        guard let protectedSince else { return nil }
        let planned = nextRun.map { $0.timeIntervalSince(protectedSince) }.flatMap { $0 > 0 ? $0 : nil }
        let span = planned ?? interval
        guard span > 0 else { return nil }
        let age = max(0, now.timeIntervalSince(protectedSince))
        return min(1, max(0, 1 - age / span))
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

    /// « aujourd’hui à 10:04 », « hier à 19:14 », else « 16 oct., 19:14 »,
    /// in the locale's own clock: the one way every Mac Backup screen says
    /// when (the island, the Settings page).
    static func when(_ date: Date, now: Date, locale: Locale, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now)
            || calendar.date(byAdding: .day, value: -1, to: now).map({ calendar.isDate(date, inSameDayAs: $0) }) == true {
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.timeZone = calendar.timeZone
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            formatter.doesRelativeDateFormatting = true
            // « Dernière : aujourd’hui à 10:04 », « Last: today at 10:04 ».
            formatter.formattingContext = .middleOfSentence
            return formatter.string(from: date)
        }
        return ForkMacBackupFormat.dayAndTime(date, locale: locale, timeZone: calendar.timeZone)
    }

    /// « Prochaine vers 14:04 » for the Automatic rhythm, which only aims
    /// at a time; « Prochaine à 14:00 » for set times or hours.
    static func nextLine(_ next: Date, rhythm: ForkMacBackupPresentation.Rhythm, shared: ForkMacBackupStrings,
                         around: String, locale: Locale) -> String {
        let time = ForkMacBackupFormat.time(next, locale: locale)
        if case .automatic = rhythm { return String(format: around, time) }
        return String(format: shared.nextAt, time)
    }

    /// The section's height: compact (180 pt) unless « spacious » (264 pt).
    static func sectionHeight(_ stored: String?) -> Double {
        stored == "spacious" ? 264 : 180
    }

    // MARK: - The tile

    /// The tile's reading: « 42 % » while something runs, as the closed
    /// island shows it; nothing otherwise: the state lives in the section the
    /// tile opens (decision 2 of 22/10), never a delay outside it.
    static func tileReading(_ state: ForkMacBackupPresentation, text: ForkMacBackupStrings, locale: Locale,
                            reading: ForkMacBackupReading, now: Date) -> String? {
        guard state.phase.showsInClosedIsland else { return nil }
        return self.reading(state, text: text, locale: locale, reading: reading, finishing: false)
    }

    /// The tile lights while something runs, like the timer's; never in red:
    /// a broken chain is told in the section only (decision 3 of 22/10).
    static func tileAccent(_ state: ForkMacBackupPresentation) -> (active: Bool, alert: Bool) {
        (state.phase.showsInClosedIsland, false)
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
            parts.append(nextLine(next, rhythm: state.rhythm, shared: text,
                                  around: ForkMacBackupSettingsStrings.strings(language).nextAround, locale: locale))
        }
        return parts.joined(separator: " · ")
    }
}
