// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// The « Historique » calendar (plan §11.3): one row per day, one column
/// per stretch of hours, one mark per expected slot. Built from
/// `slots.jsonl` with the person's calendar: a day is a calendar day (23 or
/// 25 hours across a clock change), an hour is the clock's hour, never
/// « seconds since midnight ».
struct ForkMacBackupSlotsGrid: Equatable {
    /// What a cell shows (● ◐ ✕ ○z ○b ○r ○p ·).
    enum Mark: String, Equatable, CaseIterable {
        case done
        case partial
        case failed
        /// Nothing had changed: done, nothing sent.
        case nothingToDo
        case asleep
        case battery
        case network
        case paused
        /// Missed for another reason (not approved, no disk access…).
        case missed
        /// Later today.
        case upcoming
        /// No slot was expected there.
        case empty

        /// The symbol the legend and the cell share.
        var glyph: String {
            switch self {
            case .done, .nothingToDo: return "●"
            case .partial: return "◐"
            case .failed: return "✕"
            case .asleep: return "○z"
            case .battery: return "○b"
            case .network: return "○r"
            case .paused: return "○p"
            case .missed: return "○"
            case .upcoming: return "·"
            case .empty: return ""
            }
        }

        static func of(_ outcome: ForkMacBackupSlotRecord.Outcome) -> Mark {
            switch outcome {
            case .done: return .done
            case .partial: return .partial
            case .failed: return .failed
            case .nothingToDo: return .nothingToDo
            case .missed(let reason): return of(reason)
            }
        }

        static func of(_ reason: ForkMacBackupMissedReason) -> Mark {
            switch reason {
            case .asleep, .off: return .asleep
            case .battery, .lowPower: return .battery
            case .network, .limitedNetwork, .peerOffline: return .network
            case .paused, .meeting: return .paused
            case .notApproved, .noDiskAccess, .engineMissing, .notConfigured, .wrongRepository: return .missed
            }
        }

        /// A run happened in the slot (rather than a reason it did not).
        var ran: Bool { [.done, .partial, .failed, .nothingToDo].contains(self) }

        /// Of two marks in one cell, the one worth showing: a failure over a
        /// partial over a success; any run over a reason it was missed.
        fileprivate var weight: Int {
            switch self {
            case .failed: return 9
            case .partial: return 8
            case .done: return 7
            case .nothingToDo: return 6
            case .missed: return 5
            case .battery: return 4
            case .network: return 3
            case .paused: return 2
            case .asleep: return 1
            case .upcoming, .empty: return 0
            }
        }
    }

    struct Cell: Equatable, Identifiable {
        var column: Int
        var mark: Mark
        /// The slots of this cell, by due date.
        var slots: [ForkMacBackupSlotRecord]
        /// When a missed or late slot was caught up: the next run's start.
        var caughtUpAt: Date?

        var id: Int { column }
    }

    struct Row: Equatable, Identifiable {
        /// The day's start in the calendar.
        var day: Date
        var cells: [Cell]

        var id: Date { day }
    }

    /// Hours per column (1, 2, 3, 4, 6, 8, 12 or 24).
    var hoursPerColumn: Int
    /// Oldest day first, today last.
    var rows: [Row]

    var columnCount: Int { 24 / hoursPerColumn }

    /// The first hour of each column (0, 4, 8…).
    var columnHours: [Int] { (0..<columnCount).map { $0 * hoursPerColumn } }

    static let columnChoices = [1, 2, 3, 4, 6, 8, 12, 24]

    /// The narrowest column that holds about one slot: the median gap
    /// between due dates, rounded up to a divisor of 24.
    static func hoursPerColumn(for slots: [ForkMacBackupSlotRecord]) -> Int {
        let dues = slots.map(\.due).sorted()
        guard dues.count >= 2 else { return 4 }
        let gaps = zip(dues.dropFirst(), dues).map { $0.timeIntervalSince($1) }.filter { $0 > 60 }.sorted()
        guard !gaps.isEmpty else { return 4 }
        let median = gaps[gaps.count / 2] / 3_600
        return columnChoices.first { Double($0) >= median - 0.25 } ?? 24
    }

    /// The grid of the `days` days up to `now`'s day, from `slots`.
    static func build(slots: [ForkMacBackupSlotRecord], now: Date, days: Int = 30, calendar: Calendar,
                      hoursPerColumn forced: Int? = nil) -> ForkMacBackupSlotsGrid {
        let hours = forced.flatMap { columnChoices.contains($0) ? $0 : nil } ?? hoursPerColumn(for: slots)
        let columns = 24 / hours
        let today = calendar.startOfDay(for: now)
        let dayCount = max(1, days)
        var dayStarts: [Date] = []
        for back in stride(from: dayCount - 1, through: 0, by: -1) {
            if let day = calendar.date(byAdding: .day, value: -back, to: today) {
                dayStarts.append(calendar.startOfDay(for: day))
            }
        }
        let sorted = slots.sorted { $0.due < $1.due }
        var byKey: [Date: [Int: [ForkMacBackupSlotRecord]]] = [:]
        for slot in sorted {
            let day = calendar.startOfDay(for: slot.due)
            let column = min(columns - 1, calendar.component(.hour, from: slot.due) / hours)
            byKey[day, default: [:]][column, default: []].append(slot)
        }
        let nowColumn = min(columns - 1, calendar.component(.hour, from: now) / hours)
        let rows = dayStarts.map { day -> Row in
            let cells = (0..<columns).map { column -> Cell in
                let found = byKey[day]?[column] ?? []
                if found.isEmpty {
                    let later = day == today && column > nowColumn
                    return Cell(column: column, mark: later ? .upcoming : .empty, slots: [], caughtUpAt: nil)
                }
                let mark = found.map { Mark.of($0.outcome) }.max { $0.weight < $1.weight } ?? .empty
                return Cell(column: column, mark: mark, slots: found, caughtUpAt: caughtUp(found, in: sorted))
            }
            return Row(day: day, cells: cells)
        }
        return ForkMacBackupSlotsGrid(hoursPerColumn: hours, rows: rows)
    }

    /// When the cell's work was done after all: a late start of its own
    /// slot, else the first run that started after its last missed slot.
    static func caughtUp(_ cell: [ForkMacBackupSlotRecord], in sorted: [ForkMacBackupSlotRecord]) -> Date? {
        if let late = cell.first(where: { Mark.of($0.outcome).ran && $0.startedLate }) { return late.startedAt }
        guard let missed = cell.last(where: { !Mark.of($0.outcome).ran }) else { return nil }
        guard !cell.contains(where: { Mark.of($0.outcome).ran && $0.due >= missed.due }) else { return nil }
        return sorted.first { slot in
            guard let started = slot.startedAt, Mark.of(slot.outcome).ran else { return false }
            return started > missed.due
        }?.startedAt
    }
}

/// The timeline under the browser (plan §6.2): one dot per snapshot, or per
/// stretch of time when they are too close to tell apart.
enum ForkMacBackupTimelineZoom: String, CaseIterable, Equatable {
    case day
    case week
    case month

    /// The span the timeline shows.
    var span: DateComponents {
        switch self {
        case .day: return DateComponents(day: 1)
        case .week: return DateComponents(day: 7)
        case .month: return DateComponents(month: 1)
        }
    }

    /// The hours one dot gathers.
    var bucketHours: Int {
        switch self {
        case .day: return 1
        case .week: return 6
        case .month: return 24
        }
    }

    /// The hours between two ticks of the axis.
    var tickHours: Int {
        switch self {
        case .day: return 3
        case .week: return 24
        case .month: return 24 * 7
        }
    }

    var wider: ForkMacBackupTimelineZoom? {
        switch self {
        case .day: return .week
        case .week: return .month
        case .month: return nil
        }
    }

    var narrower: ForkMacBackupTimelineZoom? {
        switch self {
        case .day: return nil
        case .week: return .day
        case .month: return .week
        }
    }
}

struct ForkMacBackupTimeline: Equatable {
    /// A snapshot as the timeline needs it.
    struct Snapshot: Equatable {
        var manifestID: String
        var date: Date
        var level: ForkMacBackupProofLevel
        var isPartial: Bool
    }

    /// One dot.
    struct Point: Equatable, Identifiable {
        /// « <day>|<bucket> », stable while the zoom stays.
        var id: String
        /// 0…1 along the visible span, at its newest snapshot.
        var fraction: Double
        /// Newest first.
        var snapshots: [Snapshot]

        var newest: Snapshot { snapshots[0] }
        var level: ForkMacBackupProofLevel { newest.level }
        var isPartial: Bool { newest.isPartial }
        var count: Int { snapshots.count }
    }

    struct Tick: Equatable {
        var date: Date
        var fraction: Double
    }

    var start: Date
    var end: Date
    var points: [Point]
    var ticks: [Tick]

    /// The timeline of `snapshots` over the span of `zoom` ending at `end`.
    static func build(_ snapshots: [Snapshot], zoom: ForkMacBackupTimelineZoom, end: Date,
                      calendar: Calendar) -> ForkMacBackupTimeline {
        let start = calendar.date(byAdding: negated(zoom.span), to: end) ?? end.addingTimeInterval(-86_400)
        let length = max(1, end.timeIntervalSince(start))
        func fraction(_ date: Date) -> Double { min(1, max(0, date.timeIntervalSince(start) / length)) }

        var groups: [String: [Snapshot]] = [:]
        var order: [String] = []
        for snapshot in snapshots.sorted(by: { $0.date > $1.date }) where snapshot.date >= start && snapshot.date <= end {
            let key = bucketKey(snapshot.date, hours: zoom.bucketHours, calendar: calendar)
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(snapshot)
        }
        let points = order.compactMap { key -> Point? in
            guard let group = groups[key], let newest = group.first else { return nil }
            return Point(id: key, fraction: fraction(newest.date), snapshots: group)
        }.sorted { $0.fraction < $1.fraction }
        return ForkMacBackupTimeline(start: start, end: end, points: points,
                                     ticks: ticks(from: start, to: end, zoom: zoom, calendar: calendar).map {
                                         Tick(date: $0, fraction: fraction($0))
                                     })
    }

    /// The bucket of `date`: its calendar day and its stretch of `hours`.
    static func bucketKey(_ date: Date, hours: Int, calendar: Calendar) -> String {
        let day = calendar.startOfDay(for: date)
        let index = hours >= 24 ? 0 : calendar.component(.hour, from: date) / max(1, hours)
        return "\(Int64(day.timeIntervalSince1970))|\(index)"
    }

    /// The axis' marks: every few clock hours, every midnight, or every
    /// week's first day, as the calendar counts them.
    static func ticks(from start: Date, to end: Date, zoom: ForkMacBackupTimelineZoom, calendar: Calendar) -> [Date] {
        var result: [Date] = []
        switch zoom {
        case .day:
            var cursor = calendar.dateInterval(of: .hour, for: start)?.start ?? start
            while cursor <= end {
                if cursor >= start, calendar.component(.hour, from: cursor) % zoom.tickHours == 0,
                   result.last.map({ calendar.component(.hour, from: $0) != calendar.component(.hour, from: cursor) }) ?? true {
                    result.append(cursor)
                }
                guard let next = calendar.date(byAdding: .hour, value: 1, to: cursor), next > cursor else { break }
                cursor = next
            }
        case .week:
            var cursor = calendar.startOfDay(for: start)
            while cursor <= end {
                if cursor >= start { result.append(cursor) }
                guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
                cursor = calendar.startOfDay(for: next)
            }
        case .month:
            var cursor = calendar.dateInterval(of: .weekOfYear, for: start)?.start ?? start
            while cursor <= end {
                if cursor >= start { result.append(cursor) }
                guard let next = calendar.date(byAdding: .weekOfYear, value: 1, to: cursor), next > cursor else { break }
                cursor = next
            }
        }
        return result
    }

    /// The end of the span that shows `date`, never after `now`: `date`
    /// in the middle when it is outside the current span, else `end`.
    static func endShowing(_ date: Date, currentEnd: Date, zoom: ForkMacBackupTimelineZoom, now: Date,
                           calendar: Calendar) -> Date {
        let start = calendar.date(byAdding: negated(zoom.span), to: currentEnd) ?? currentEnd
        if date >= start && date <= currentEnd { return currentEnd }
        let length = currentEnd.timeIntervalSince(start)
        return min(now, date.addingTimeInterval(length / 2))
    }

    /// One span earlier (`direction` < 0) or later, never after `now`.
    static func shifted(end: Date, zoom: ForkMacBackupTimelineZoom, direction: Int, now: Date,
                        calendar: Calendar) -> Date {
        let span = direction < 0 ? negated(zoom.span) : zoom.span
        let moved = calendar.date(byAdding: span, to: end) ?? end
        return min(now, moved)
    }

    /// The snapshot before (`step` < 0) or after the one selected, in time.
    static func neighbor(of manifestID: String?, step: Int, in snapshots: [Snapshot]) -> Snapshot? {
        let ordered = snapshots.sorted { $0.date < $1.date }
        guard !ordered.isEmpty else { return nil }
        guard let manifestID, let index = ordered.firstIndex(where: { $0.manifestID == manifestID }) else {
            return ordered.last
        }
        let target = index + (step < 0 ? -1 : 1)
        return ordered.indices.contains(target) ? ordered[target] : nil
    }

    private static func negated(_ components: DateComponents) -> DateComponents {
        var result = DateComponents()
        result.day = components.day.map { -$0 }
        result.month = components.month.map { -$0 }
        return result
    }
}
