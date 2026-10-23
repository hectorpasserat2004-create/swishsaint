// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// What the agent saw happen, in order: enough to say why a due date passed
/// without a backup (plan §3.9). « Asleep » comes from the sleep and wake
/// notifications, « off » from the boot time read at start, the rest from
/// the waits the planner announced.
struct ForkMacBackupSlotTimeline: Equatable {
    enum Event: Equatable {
        /// The agent (or the app's runner) started.
        case agentStarted
        /// Its last sign of life before a gap (the state file's date).
        case agentStopped
        /// The Mac started (`kern.boottime`).
        case booted
        case willSleep
        case didWake
        /// The planner held a slot for this reason.
        case waiting(ForkMacBackupMissedReason)
        /// The conditions cleared.
        case clear
        case paused
        case resumed
        /// A backup ran: a due date inside it is covered, not missed.
        case runStarted
        case runEnded
    }

    struct Entry: Equatable {
        var date: Date
        var event: Event
    }

    enum Attribution: Equatable {
        case missed(ForkMacBackupMissedReason)
        /// A backup was running: the slot is not missed.
        case covered
        /// Nothing known explains it: no record rather than a guessed cause.
        case unknown
    }

    private(set) var entries: [Entry] = []
    /// Entries older than this are forgotten (the oldest open slot is younger).
    static let memory: TimeInterval = 14 * 86_400
    static let maxEntries = 2_000

    init(entries: [Entry] = []) {
        self.entries = entries.sorted { $0.date < $1.date }
    }

    mutating func append(_ event: Event, at date: Date) {
        // Repeated waits for the same reason add nothing.
        if case .waiting = event, entries.last?.event == event { return }
        if let index = entries.lastIndex(where: { $0.date <= date }), index < entries.count - 1 {
            entries.insert(Entry(date: date, event: event), at: index + 1)
        } else if let first = entries.first, date < first.date {
            entries.insert(Entry(date: date, event: event), at: 0)
        } else {
            entries.append(Entry(date: date, event: event))
        }
        if entries.count > Self.maxEntries { entries.removeFirst(entries.count - Self.maxEntries) }
    }

    mutating func forget(before date: Date) {
        entries.removeAll { $0.date < date }
    }

    /// Why nothing ran at `due`.
    func attribute(_ due: Date) -> Attribution {
        var alive = true
        var asleep = false
        var paused = false
        var running = false
        var waiting: ForkMacBackupMissedReason?
        var stoppedAt: Date?
        for entry in entries where entry.date <= due {
            switch entry.event {
            case .agentStarted:
                alive = true
                asleep = false
                running = false
                stoppedAt = nil
            case .agentStopped:
                alive = false
                running = false
                stoppedAt = entry.date
            case .booted:
                break
            case .willSleep: asleep = true
            case .didWake: asleep = false
            case .waiting(let reason): waiting = reason
            case .clear: waiting = nil
            case .paused: paused = true
            case .resumed: paused = false
            case .runStarted: running = true
            case .runEnded: running = false
            }
        }
        if !alive {
            // A boot between the last sign of life and the next start: the
            // Mac was off (or nobody had logged in). None: the Mac ran without
            // the agent, which only happens when it is not allowed to run.
            let nextStart = entries.first { $0.date > due && $0.event == .agentStarted }?.date ?? .distantFuture
            let booted = entries.contains { entry in
                entry.event == .booted && entry.date > (stoppedAt ?? .distantPast) && entry.date <= nextStart
            }
            return .missed(booted ? .off : .notApproved)
        }
        if asleep { return .missed(.asleep) }
        if running { return .covered }
        if paused { return .missed(.paused) }
        if let waiting { return .missed(waiting) }
        return .unknown
    }
}

/// The slot being worked on and the last one written (`slots.jsonl`):
/// one record per due date, never two (plan §3.9).
struct ForkMacBackupSlotBook: Equatable {
    struct OpenSlot: Equatable {
        var due: Date
        var startedAt: Date?
        var runID: UUID?
        /// A run for it failed; retries keep it open.
        var failed: Bool
        /// The last reason a wait held it.
        var lastWait: ForkMacBackupMissedReason?
    }

    var lastClosedDue: Date?
    var open: OpenSlot?

    init(lastClosedDue: Date? = nil, open: OpenSlot? = nil) {
        self.lastClosedDue = lastClosedDue
        self.open = open
    }

    /// Opens the slot of `due` (nothing when it is already the open one).
    mutating func open(_ due: Date) {
        guard open?.due != due else { return }
        open = OpenSlot(due: due, startedAt: nil, runID: nil, failed: false, lastWait: nil)
    }

    mutating func waited(_ reason: ForkMacBackupMissedReason?) {
        guard let reason else { return }
        open?.lastWait = reason
    }

    mutating func runStarted(at date: Date, runID: UUID) {
        guard open != nil else { return }
        if open?.startedAt == nil { open?.startedAt = date }
        open?.runID = runID
    }

    /// A run of the open slot ended. A failure keeps it open for the retry;
    /// anything else closes it. Returns the record to append, if any.
    mutating func runEnded(_ result: ForkMacBackupRunResult?, runID: UUID, canceledByPerson: Bool) -> ForkMacBackupSlotRecord? {
        guard let slot = open, slot.runID == runID else { return nil }
        if canceledByPerson { return close(.missed(.paused)) }
        switch result {
        case .complete?: return close(.done)
        case .partial?: return close(.partial)
        case .nothingToDo?: return close(.nothingToDo)
        case .failed?:
            open?.failed = true
            return nil
        case nil:
            // Stopped by a pause, a meeting, the update…: still open.
            return nil
        }
    }

    /// Closes the open slot with `outcome`.
    mutating func close(_ outcome: ForkMacBackupSlotRecord.Outcome) -> ForkMacBackupSlotRecord? {
        guard let slot = open else { return nil }
        open = nil
        lastClosedDue = max(lastClosedDue ?? slot.due, slot.due)
        return ForkMacBackupSlotRecord(due: slot.due, outcome: outcome, startedAt: slot.startedAt, runID: slot.runID)
    }

    /// A slot with nothing to do, written at once.
    mutating func nothingToDo(_ due: Date) -> ForkMacBackupSlotRecord {
        if open?.due == due { open = nil }
        lastClosedDue = max(lastClosedDue ?? due, due)
        return ForkMacBackupSlotRecord(due: due, outcome: .nothingToDo)
    }

    /// Before each decision: the open slot whose successor is already due is
    /// closed (failed, or missed for the reason the timeline gives), and
    /// every due date passed since, but the last, is written missed. The
    /// last one is left to the planner: it is the slot to catch up.
    mutating func sweep(now: Date, lastBackup: Date?, settings: ForkMacBackupAgentSettings, onAC: Bool,
                        calendar: Calendar, timeline: ForkMacBackupSlotTimeline) -> [ForkMacBackupSlotRecord] {
        var records: [ForkMacBackupSlotRecord] = []
        if let slot = open {
            let successor = ForkMacBackupPlanner.dues(after: slot.due, through: now, settings: settings, onAC: onAC,
                                                      calendar: calendar, limit: 1).first
            if successor != nil {
                if slot.failed {
                    if let record = close(.failed) { records.append(record) }
                } else {
                    switch timeline.attribute(slot.due) {
                    case .missed(let reason):
                        if let record = close(.missed(reason)) { records.append(record) }
                    case .covered, .unknown:
                        if let reason = slot.lastWait {
                            if let record = close(.missed(reason)) { records.append(record) }
                        } else {
                            open = nil
                            lastClosedDue = max(lastClosedDue ?? slot.due, slot.due)
                        }
                    }
                }
            }
        }
        guard open == nil else { return records }
        let reference = [lastBackup, lastClosedDue].compactMap { $0 }.max()
        guard let reference else { return records }
        let passed = ForkMacBackupPlanner.dues(after: reference, through: now, settings: settings, onAC: onAC,
                                              calendar: calendar)
        for due in passed.dropLast() {
            lastClosedDue = due
            if case .missed(let reason) = timeline.attribute(due) {
                records.append(ForkMacBackupSlotRecord(due: due, outcome: .missed(reason)))
            }
        }
        return records
    }
}

/// `runs.jsonl` and `slots.jsonl`: append-only lines, trimmed by age and
/// count once the file grows (plan §3.5).
enum ForkMacBackupJournal {
    /// The lines to keep: younger than `maxAge`, the last `maxLines`, in order.
    static func trimmed<Value: Codable>(_ data: Data, as type: Value.Type, now: Date,
                                        maxAge: TimeInterval = ForkMacBackupAgentTuning.journalMaxAge,
                                        maxLines: Int = ForkMacBackupAgentTuning.journalMaxLines,
                                        date: (Value) -> Date) -> Data {
        let values = ForkMacBackupJSON.lines(type, from: data).filter { now.timeIntervalSince(date($0)) <= maxAge }
        var output = Data()
        for value in values.suffix(maxLines) {
            if let line = ForkMacBackupJSON.line(value) { output.append(line) }
        }
        return output
    }
}
