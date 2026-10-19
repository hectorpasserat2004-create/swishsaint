// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// Which appointment a recorded meeting belongs to. A sound attached to the
/// wrong one writes over someone else's report, so the rule says how sure
/// it is, and only a sure one goes on its own.
///
/// 1. **The meeting's own Google Meet code** (B2): the code `meeting.json`
///    keeps for this recording, never one an earlier offer left behind. A
///    meeting started by hand without a code never matches by code.
/// 2. **Its time**: the recording overlaps the appointment, give or take
///    15 minutes on each side (B6).
/// 3. **The closest start**, within two hours: a guess, offered first in
///    the choice, never sent on its own.
///
/// A cancelled appointment, or one the prospect missed, is never one; a
/// rescheduled one is (B1).
enum ForkCastralMatch {
    enum Rule: String, Equatable {
        case meetCode
        case overlap
        case closest
        /// Picked in the choice by the person.
        case chosen
    }

    struct Choice: Equatable {
        var booking: ForkCastralContract.Booking
        var rule: Rule
        /// The only one its rule found: with `meetCode` or `overlap`, sure
        /// enough to go on its own.
        var unique: Bool
    }

    static let overlapMargin: TimeInterval = 15 * 60
    static let closestWindow: TimeInterval = 2 * 3600
    /// An appointment without an end is taken as an hour long.
    static let assumedLength: TimeInterval = 3600
    /// The appointments asked around a meeting, for the match and the
    /// choice: wide enough for a meeting recorded late, still the server's
    /// "around then" and not its calendar.
    static let searchMargin: TimeInterval = 12 * 3600

    /// The window of `targets` around a meeting.
    static func window(startedAt: Date, endedAt: Date?) -> (from: Date, to: Date) {
        (startedAt.addingTimeInterval(-searchMargin), (endedAt ?? startedAt).addingTimeInterval(searchMargin))
    }

    static func choose(_ bookings: [ForkCastralContract.Booking], meetCode: String?, startedAt: Date,
                       endedAt: Date?) -> Choice? {
        let usable = bookings.filter { !$0.isBlocked && $0.startAt != nil }
        let end = max(endedAt ?? startedAt, startedAt)
        if let code = meetCode?.lowercased(), !code.isEmpty {
            let coded = usable.filter { $0.meetCode == code }
            // A personal Meet link serves many appointments: the time
            // tells them apart.
            if let best = best(coded, startedAt: startedAt, endedAt: end) {
                return Choice(booking: best, rule: .meetCode, unique: coded.count == 1 || overlapping(coded, startedAt, end).count == 1)
            }
        }
        let overlaps = overlapping(usable, startedAt, end)
        if let best = closest(overlaps, to: startedAt) {
            return Choice(booking: best, rule: .overlap, unique: overlaps.count == 1)
        }
        let near = usable.filter { abs($0.startAt!.timeIntervalSince(startedAt)) <= closestWindow }
        if let best = closest(near, to: startedAt) {
            return Choice(booking: best, rule: .closest, unique: false)
        }
        return nil
    }

    /// What the choice lists: the appointments that may take it, the
    /// closest to the meeting first.
    static func candidates(_ bookings: [ForkCastralContract.Booking], startedAt: Date) -> [ForkCastralContract.Booking] {
        bookings.filter { !$0.isBlocked && $0.startAt != nil }
            .sorted { abs($0.startAt!.timeIntervalSince(startedAt)) < abs($1.startAt!.timeIntervalSince(startedAt)) }
    }

    /// The offer's line (B7): the appointment of this call's code, when one.
    static func byCode(_ bookings: [ForkCastralContract.Booking], meetCode: String?, now: Date) -> ForkCastralContract.Booking? {
        guard let code = meetCode?.lowercased(), !code.isEmpty else { return nil }
        return closest(bookings.filter { !$0.isBlocked && $0.startAt != nil && $0.meetCode == code }, to: now)
    }

    private static func interval(_ booking: ForkCastralContract.Booking) -> (Date, Date)? {
        guard let start = booking.startAt else { return nil }
        let end = max(booking.endAt ?? start.addingTimeInterval(assumedLength), start)
        return (start.addingTimeInterval(-overlapMargin), end.addingTimeInterval(overlapMargin))
    }

    private static func overlapping(_ bookings: [ForkCastralContract.Booking], _ start: Date,
                                    _ end: Date) -> [ForkCastralContract.Booking] {
        bookings.filter { booking in
            guard let (from, to) = interval(booking) else { return false }
            return start <= to && end >= from
        }
    }

    private static func closest(_ bookings: [ForkCastralContract.Booking], to date: Date) -> ForkCastralContract.Booking? {
        bookings.min { abs($0.startAt!.timeIntervalSince(date)) < abs($1.startAt!.timeIntervalSince(date)) }
    }

    private static func best(_ bookings: [ForkCastralContract.Booking], startedAt: Date,
                             endedAt: Date) -> ForkCastralContract.Booking? {
        closest(overlapping(bookings, startedAt, endedAt), to: startedAt) ?? closest(bookings, to: startedAt)
    }

    // MARK: - On its own

    enum Verdict: Equatable {
        case send(Choice)
        /// Sent only once the person chose: several could match, or none
        /// surely, or the appointment has no company, or already a report.
        case needsChoice(ForkCastralFailure)
    }

    /// May the meeting go on its own to the appointment found? Only to a
    /// sure one, with a company, and without a report yet: a second report
    /// replaces the first in the CRM.
    static func automatic(_ choice: Choice?) -> Verdict {
        guard let choice else { return .needsChoice(.noBooking) }
        guard choice.unique, choice.rule == .meetCode || choice.rule == .overlap else {
            return .needsChoice(.uncertain)
        }
        guard choice.booking.company?.id != nil else { return .needsChoice(.orphan) }
        guard !choice.booking.hasReport else { return .needsChoice(.alreadyReported) }
        return .send(choice)
    }

    /// Recorded much less than the appointment lasted: the choice offers
    /// to say what was not recorded.
    static func suggestsComplement(recordedSeconds: Double?, booking: ForkCastralContract.Booking) -> Bool {
        guard let recorded = recordedSeconds, let start = booking.startAt, let end = booking.endAt, end > start else {
            return false
        }
        return recorded < end.timeIntervalSince(start) * 0.75
    }
}
