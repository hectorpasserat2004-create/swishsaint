// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// One appointment of the CRM, as the island's calendar shows it. Read in
/// memory only, when the calendar is on screen; never written anywhere.
struct ForkCalendarAppointment: Equatable, Sendable {
    let bookingID: String
    let start: Date
    let end: Date
    /// Who it is with: the company, else the person who booked.
    let who: String?
    /// The person who booked, when a company names the appointment.
    let attendee: String?
    let companyID: String?
    let link: ForkCalendarVideoLink?
}

/// The rules of the CRM's appointments in the island's calendar (seam
/// `notch-calendar-crm`): when they are read, which of them show, how each
/// becomes a calendar event, and how one already in the calendar is
/// recognized so it shows once.
enum ForkCalendarAppointmentsSupport {
    /// The CRM is asked at most this often, and only while the island
    /// shows its calendar.
    static let refreshInterval: TimeInterval = 5 * 60
    /// The appointments asked: those begun in the last 12 hours (one still
    /// going on) up to two weeks ahead, the reach of the agenda's weeks.
    static let lookBack: TimeInterval = 12 * 3600
    static let lookAhead: TimeInterval = 14 * 86_400
    /// An appointment without an end is taken as an hour long.
    static let assumedLength: TimeInterval = 3600
    /// The calendar event of an appointment starts at the same minute.
    static let sameStart: TimeInterval = 60
    /// A shared link (a personal Meet room) names the same call only this
    /// close to its start.
    static let linkReach: TimeInterval = 3600
    /// The ids of the events made from appointments; never a calendar's.
    static let eventPrefix = "fork.crm:"
    /// The appointments' own color in the calendar, apart from the person's
    /// calendars: a soft violet.
    static let tint = NotchCalendarColor(red: 0.69, green: 0.52, blue: 1)

    /// The `targets` window around now.
    static func window(now: Date) -> DateInterval {
        DateInterval(start: now.addingTimeInterval(-lookBack), end: now.addingTimeInterval(lookAhead))
    }

    /// Whether the CRM is asked now: never twice at once, and at most every
    /// five minutes (a clock set back asks again).
    static func isDue(lastRead: Date?, now: Date, reading: Bool) -> Bool {
        guard !reading else { return false }
        guard let lastRead else { return true }
        return now.timeIntervalSince(lastRead) >= refreshInterval || now < lastRead
    }

    /// Whether the island's calendar has the CRM's appointments: the
    /// Meetings feature on with a CRM imported, the setting on, the island's
    /// calendar on.
    static func shows(meetings: Bool, hasCRM: Bool, wanted: Bool, calendar: Bool) -> Bool {
        meetings && hasCRM && wanted && calendar
    }

    /// Whether they step aside for now: while a call is detected or offered,
    /// or a meeting records (when a screen is likely shared), with the
    /// island visible in screenshots and videos (the official setting): a
    /// prospect's name never goes out with a shared screen.
    static func hides(inCall: Bool, inCaptures: Bool) -> Bool {
        inCall && inCaptures
    }

    /// The appointments to show: not cancelled nor missed, with a start,
    /// still going on or ahead.
    static func appointments(_ bookings: [ForkCastralContract.Booking], now: Date) -> [ForkCalendarAppointment] {
        bookings.compactMap { booking in
            guard !booking.isBlocked, let start = booking.startAt else { return nil }
            let end = max(booking.endAt ?? start.addingTimeInterval(assumedLength), start.addingTimeInterval(60))
            guard end > now else { return nil }
            let company = booking.company?.name
            let attendee = booking.attendeeName
            return ForkCalendarAppointment(bookingID: booking.id, start: start, end: end, who: company ?? attendee,
                                           attendee: company == nil ? nil : attendee, companyID: booking.company?.id,
                                           link: ForkCalendarVideoLink.meetingLink(booking.meetingURL))
        }
        .sorted { $0.start != $1.start ? $0.start < $1.start : $0.bookingID < $1.bookingID }
    }

    /// The line under an appointment's time, where a calendar's name goes:
    /// "CRM · Jane Doe", or "CRM" alone.
    static func calendarLine(mark: String, detail: String?) -> String {
        guard let detail = detail?.trimmingCharacters(in: .whitespacesAndNewlines), !detail.isEmpty else { return mark }
        return mark + " · " + detail
    }

    /// An appointment found nowhere in the calendar, as an event of it: the
    /// company (else the person) for its title, the CRM's mark and the
    /// person under its time. No countdown key: choosing it would write the
    /// appointment's id in the preferences.
    static func event(_ appointment: ForkCalendarAppointment, mark: String) -> NotchCalendarEvent {
        NotchCalendarEvent(id: eventPrefix + appointment.bookingID, title: appointment.who ?? "",
                           calendar: calendarLine(mark: mark, detail: appointment.attendee),
                           start: appointment.start, end: appointment.end, allDay: false, location: "", color: tint)
    }

    struct Merged: Equatable {
        /// The calendar's events with the appointments, in the calendar's order.
        var events: [NotchCalendarEvent]
        /// The appointment behind each event of the list, by the event's id:
        /// its own, or the calendar's event it was found as.
        var appointments: [String: ForkCalendarAppointment]
    }

    /// The calendar read for `interval`, with the appointments of that
    /// interval. An appointment already in the calendar (the same call
    /// link close to its start, or the same start and its name in the
    /// title) shows once, as the calendar's event, marked as the CRM's.
    static func merge(_ events: [NotchCalendarEvent], links: [String: ForkCalendarVideoLink],
                      appointments: [ForkCalendarAppointment], interval: DateInterval, mark: String) -> Merged {
        var merged = Merged(events: events, appointments: [:])
        var taken = Set<String>()
        for appointment in appointments where appointment.start < interval.end && appointment.end > interval.start {
            let index = match(appointment, in: merged.events, links: links, taken: taken)
            if let index {
                let found = merged.events[index]
                taken.insert(found.id)
                merged.events[index] = marked(found, mark: mark, appointment: appointment)
                merged.appointments[found.id] = appointment
            } else {
                let event = event(appointment, mark: mark)
                merged.events.append(event)
                merged.appointments[event.id] = appointment
            }
        }
        merged.events = NotchCalendarSupport.ordered(merged.events)
        return merged
    }

    /// The calendar's event of the appointment: by its call link first, the
    /// closest start; else by the same start and its name in the title.
    private static func match(_ appointment: ForkCalendarAppointment, in events: [NotchCalendarEvent],
                              links: [String: ForkCalendarVideoLink], taken: Set<String>) -> Int? {
        let candidates = events.indices.filter {
            !events[$0].allDay && !events[$0].id.hasPrefix(eventPrefix) && !taken.contains(events[$0].id)
        }
        func distance(_ index: Int) -> TimeInterval { abs(events[index].start.timeIntervalSince(appointment.start)) }
        if let key = appointment.link?.key {
            let linked = candidates.filter { links[events[$0].id]?.key == key && distance($0) <= linkReach }
            if let best = linked.min(by: { distance($0) < distance($1) }) { return best }
        }
        let names = [appointment.who, appointment.attendee].compactMap { $0.map(folded) }.filter { $0.count >= 3 }
        return candidates.first { index in
            guard distance(index) < sameStart else { return false }
            let title = folded(events[index].title)
            return names.contains { title == $0 || title.contains($0) }
        }
    }

    private static func marked(_ event: NotchCalendarEvent, mark: String,
                               appointment: ForkCalendarAppointment) -> NotchCalendarEvent {
        NotchCalendarEvent(id: event.id, title: event.title, calendar: calendarLine(mark: mark, detail: appointment.who),
                           start: event.start, end: event.end, allDay: event.allDay, location: event.location,
                           color: event.color, calendarItemIdentifier: event.calendarItemIdentifier,
                           recurring: event.recurring, countdownKey: event.countdownKey)
    }

    /// Without case, accents nor extra spaces, for comparing names.
    static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
