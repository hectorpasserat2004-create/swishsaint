// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import AppKit
import Combine
import EventKit

/// The island's calendar with each appointment's video link, and the CRM's
/// appointments among the calendar's (seams `notch-calendar-crm`,
/// `notch-calendar-crm2`, `notch-calendar-crm3`).
///
/// - **The links**: with the Meetings feature on only (anyone else keeps
///   the official calendar as it is), each event the official calendar
///   reads is looked up once, on a utility serial queue that keeps its own
///   EventKit store, while the island shows its calendar; only the link
///   found leaves the queue, never the notes, and nothing is written.
/// - **The CRM**: only with the Meetings feature on and a CRM imported,
///   and its setting on (`ForkCalendarAppointmentsSupport.shows`); set
///   aside while a call is detected or a meeting records, if the island
///   shows in screenshots and videos (`hides`). Read with the CRM export's
///   own client and token, when the island shows its calendar and at most
///   every five minutes: no timer, nothing asked otherwise. Kept in memory
///   only; a CRM out of reach, or a token refused, leaves the calendar alone,
///   without a word.
/// - Each official read hands its events to `merged`, which adds the
///   appointments and marks those found in the calendar; the closed
///   island's countdown and the Controls tile then count them too.
///
/// Main thread, but the reading.
final class ForkCalendarAppointments: ObservableObject {
    static let shared = ForkCalendarAppointments()

    /// Each calendar event's video link, by the event's id.
    @Published private(set) var links: [String: ForkCalendarVideoLink] = [:]
    /// The CRM appointment behind each event of the merged list, by its id.
    @Published private(set) var appointments: [String: ForkCalendarAppointment] = [:]
    /// Each calendar event found as an appointment, as the calendar has it.
    @Published private(set) var originals: [String: NotchCalendarEvent] = [:]
    /// The event whose link was just copied, for a moment.
    @Published private(set) var copied: String?
    /// A call is going on while a CRM can show: the Settings window's
    /// preview of the calendar leaves the appointments out.
    @Published private(set) var calling = false
    /// The CRM's name and addresses, as its last read gave them (no token).
    private(set) var profile: ForkCastralProfile?

    // What the recipe harness alone replaces; the app keeps these.
    var defaults: UserDefaults = .standard
    var exports: () -> ForkMeetingExports = { .shared }
    /// The island shows its calendar page now.
    var isShowing: () -> Bool = { NotchService.shared.expanded && NotchService.shared.selected == .calendar }
    /// A new official read, for what the CRM or the lookups just found.
    var refreshCalendar: () -> Void = { NotchCalendarService.shared.refresh() }
    /// A call is detected or offered, or a meeting starts or records.
    var inCall: () -> Bool = {
        let meetings = ForkMeetingService.shared
        return meetings.isRecording || meetings.isStarting || meetings.detectedMeeting != nil
    }
    /// Follows the Meetings service's calls; the harness tells `callChanged` itself.
    var followsCalls = true
    /// The links of an interval's events, on `queue`; `nil`: EventKit.
    var readLinks: ((DateInterval) -> [String: ForkCalendarVideoLink])?
    var pasteboard: NSPasteboard = .general

    /// The appointments of the last read, all of them.
    private var read: [ForkCalendarAppointment] = []
    private var readAt: Date?
    private var reading = false
    /// Bumped when what may show changes: an answer of before is dropped.
    private var generation = 0
    /// What `shows` was last decided on, to notice a change.
    private var gate: String?
    /// Whether the appointments last stepped aside for a call.
    private var hidden = false
    /// The Meetings service's calls, followed once a CRM can show.
    private var calls: AnyCancellable?
    /// The events already looked up for a link, by id.
    private var looked = Set<String>()
    private var looking = false
    /// The CRM answered during a lookup: one official read once both are
    /// in, so an appointment never shows twice for a moment.
    private var readAfterLookup = false
    /// What waits while a lookup runs.
    private var waiting: (events: [NotchCalendarEvent], interval: DateInterval)?
    private var copiedReset: DispatchWorkItem?
    private var observers: [NSObjectProtocol] = []
    private let queue = DispatchQueue(label: "fork.calendar.links", qos: .utility)
    /// Queue only.
    private var store: EKEventStore?

    /// At launch (`ForkBootstrap.start`): follows what decides whether the
    /// CRM shows, and the calendar's own changes. Nothing is read here.
    static func start() {
        shared.observe()
    }

    private func observe() {
        guard observers.isEmpty else { return }
        gate = gateKey()
        if gate != nil { followCalls() }
        observers.append(NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            self?.preferencesChanged()
        })
        observers.append(NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: nil,
                                                                queue: .main) { [weak self] _ in
            // An event edited may have a new link: looked up again at the
            // next read, which this change starts.
            self?.looked = []
        })
    }

    /// No CRM read nor lookup under way, for the recipe harness.
    var isIdle: Bool { !reading && !looking }

    // MARK: - What shows

    /// The Meetings feature, which the links and the CRM both belong to.
    private var meetingsOn: Bool { defaults.bool(forKey: ForkDefaultsKey.meetingsEnabled) }

    /// Whether the island's calendar shows the CRM's appointments now.
    var showsCRM: Bool {
        guard defaults.bool(forKey: ForkDefaultsKey.meetingsEnabled),
              defaults.bool(forKey: ForkDefaultsKey.meetingsIslandAppointments) else { return false }
        return ForkCalendarAppointmentsSupport.shows(
            meetings: true, hasCRM: exports().castralConfig != nil, wanted: true,
            calendar: NotchCalendarSupport.isEnabled(in: defaults))
    }

    /// Whether the appointments step aside now (`ForkCalendarAppointmentsSupport.hides`).
    var hidesCRM: Bool {
        ForkCalendarAppointmentsSupport.hides(inCall: inCall(), inCaptures: NotchSupport.showsInCaptures(in: defaults))
    }

    /// The CRM exporter shown, or nothing: what the appointments read belong to.
    private func gateKey() -> String? {
        showsCRM ? exports().castralConfig?.id : nil
    }

    private func preferencesChanged() {
        if !meetingsOn { forgetLinks() }
        let key = gateKey()
        if key != nil { followCalls() }
        let inCall = key != nil && self.inCall()
        if calling != inCall { calling = inCall }
        let hides = key != nil && hidesCRM
        guard key != gate || hides != hidden else { return }
        if key != gate { forget() }
        gate = key
        hidden = hides
        if NotchCalendarSupport.isEnabled(in: defaults) { refreshCalendar() }
    }

    /// A call's start or end may set the appointments aside or bring them
    /// back: the Meetings service is followed once a CRM can show (never
    /// for anyone without one).
    private func followCalls() {
        guard followsCalls, calls == nil else { return }
        let meetings = ForkMeetingService.shared
        calls = Publishers.CombineLatest3(meetings.$isRecording, meetings.$isStarting,
                                          meetings.$detectedMeeting.map { $0 != nil })
            .map { $0 || $1 || $2 }
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.callChanged() }
    }

    /// A call began or ended (the recipe harness calls it too).
    func callChanged() {
        preferencesChanged()
    }

    /// Drops every appointment read, and any answer on its way.
    private func forget() {
        generation += 1
        reading = false
        readAfterLookup = false
        read = []
        readAt = nil
        profile = nil
        if !appointments.isEmpty { appointments = [:] }
        if !originals.isEmpty { originals = [:] }
    }

    /// The Meetings feature off: the links go, with the EventKit store.
    private func forgetLinks() {
        guard !links.isEmpty || !looked.isEmpty || looking else { return }
        looked = []
        waiting = nil
        if !links.isEmpty { links = [:] }
        queue.async { [weak self] in self?.store = nil }
    }

    // MARK: - The official read (seam `notch-calendar-crm`)

    /// The calendar's events for `interval`, ordered, with the CRM's
    /// appointments of that interval. Starts the lookups and the CRM's read
    /// this display needs.
    func merged(_ events: [NotchCalendarEvent], interval: DateInterval) -> [NotchCalendarEvent] {
        let showing = isShowing()
        let crm = showsCRM
        let key = gateKey()
        if key != gate {
            // Inside the official read: no new read from here.
            gate = key
            forget()
        }
        if key != nil { followCalls() }
        let meetings = meetingsOn
        if !meetings { forgetLinks() }
        let inCall = crm && self.inCall()
        if calling != inCall { calling = inCall }
        hidden = crm && hidesCRM
        if meetings, showing || (crm && !read.isEmpty) { lookUp(events, interval: interval) }
        if crm, !hidden, showing { readIfDue() }
        guard crm, !hidden, !read.isEmpty else {
            if !appointments.isEmpty { appointments = [:] }
            if !originals.isEmpty { originals = [:] }
            return events
        }
        let merged = ForkCalendarAppointmentsSupport.merge(events, links: links, appointments: read, interval: interval,
                                                           mark: ForkCalendarAppointmentsStrings.current.crmMark,
                                                           linksPending: looking)
        // What waited for the links shows at the read their lookup starts.
        if looking { readAfterLookup = true }
        if appointments != merged.appointments { appointments = merged.appointments }
        if originals != merged.originals { originals = merged.originals }
        return merged.events
    }

    /// The link of an event of the list: its own as the calendar writes it
    /// (a Meet link keeps the account it opens with), else its appointment's.
    func link(for event: NotchCalendarEvent) -> ForkCalendarVideoLink? {
        links[event.id] ?? appointments[event.id]?.link
    }

    /// Whether the fork draws this event's row: it has a link, or is the CRM's.
    func decorates(_ event: NotchCalendarEvent) -> Bool {
        appointments[event.id] != nil || links[event.id] != nil
    }

    // MARK: - The CRM

    private func readIfDue() {
        let exports = self.exports()
        guard ForkCalendarAppointmentsSupport.isDue(lastRead: readAt, now: Date(), reading: reading),
              let config = exports.castralConfig, !exports.listChanged else { return }
        reading = true
        let job = generation
        let exporter = exports.castralExporter(config, request: nil)
        let window = ForkCalendarAppointmentsSupport.window(now: Date())
        DispatchQueue.global(qos: .utility).async { [weak self] in
            // Out of reach, refused or unreadable: nothing, without a word.
            let answer: (ForkCastralProfile, [ForkCastralContract.Booking])? = {
                guard let client = try? exporter.credentials(),
                      case let .success(bookings)? = try? ForkMeetingExports.blocking({
                          await client.targets(from: window.start, to: window.end)
                      }) else { return nil }
                return (client.profile, bookings)
            }()
            DispatchQueue.main.async { [weak self] in
                guard let self, job == generation else { return }
                reading = false
                readAt = Date()
                let before = read
                profile = answer?.0 ?? profile
                read = answer.map { ForkCalendarAppointmentsSupport.appointments($0.1, now: Date()) } ?? []
                guard read != before else { return }
                if looking { readAfterLookup = true } else { refreshCalendar() }
            }
        }
    }

    // MARK: - The links

    private func lookUp(_ events: [NotchCalendarEvent], interval: DateInterval) {
        let wanted = events.filter {
            !$0.allDay && !$0.id.hasPrefix(ForkCalendarAppointmentsSupport.eventPrefix) && !looked.contains($0.id)
        }
        guard !wanted.isEmpty, readLinks != nil || EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return }
        guard !looking else {
            waiting = (events, interval)
            return
        }
        looking = true
        let reader = readLinks
        queue.async { [weak self] in
            let found = reader?(interval) ?? self?.eventKitLinks(interval) ?? [:]
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                looking = false
                // The Meetings feature turned off meanwhile: nothing is kept.
                guard meetingsOn else { return forgetLinks() }
                let ids = Set(wanted.map(\.id))
                var next = links.filter { !ids.contains($0.key) || found[$0.key] != nil }
                next.merge(found) { $1 }
                // A month of events at most: the lookups of earlier months go.
                if next.count > 600 { next = found }
                looked.formUnion(ids)
                if looked.count > 3000 { looked = ids }
                let changed = next != links
                if changed { links = next }
                if (changed && !read.isEmpty) || readAfterLookup {
                    readAfterLookup = false
                    refreshCalendar()
                }
                if let waiting {
                    self.waiting = nil
                    lookUp(waiting.events, interval: waiting.interval)
                }
            }
        }
    }

    /// Queue only. The link of each event of the interval, by the id the
    /// official reader gives it.
    private func eventKitLinks(_ interval: DateInterval) -> [String: ForkCalendarVideoLink] {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return [:] }
        let store = self.store ?? EKEventStore()
        self.store = store
        let predicate = store.predicateForEvents(withStart: interval.start, end: interval.end, calendars: nil)
        var found: [String: ForkCalendarVideoLink] = [:]
        for event in store.events(matching: predicate) where event.status != .canceled && !event.isAllDay {
            guard let identifier = event.eventIdentifier, let start = event.startDate,
                  let link = ForkCalendarVideoLink.find(url: event.url, location: event.location, notes: event.notes) else {
                continue
            }
            found[identifier + ":" + String(start.timeIntervalSinceReferenceDate)] = link
        }
        return found
    }

    // MARK: - Actions

    /// Join: the call's app when it is on this Mac, else the link; the
    /// island folds first, as for any window it opens.
    func join(_ event: NotchCalendarEvent) {
        guard let link = link(for: event) else { return }
        let workspace = NSWorkspace.shared
        let zoomApp = URL(string: "zoommtg://zoom.us").flatMap(workspace.urlForApplication(toOpen:)) != nil
        let teamsApp = URL(string: "msteams:").flatMap(workspace.urlForApplication(toOpen:)) != nil
        let url = ForkCalendarVideoLink.joinURL(link, zoomApp: zoomApp, teamsApp: teamsApp)
        NotchService.shared.perform {
            if !workspace.open(url), url != link.url { workspace.open(link.url) }
        }
    }

    /// Copy Link: the link as written, said for a moment on the row and to
    /// VoiceOver.
    func copy(_ event: NotchCalendarEvent) {
        guard let link = link(for: event) else { return }
        pasteboard.clearContents()
        pasteboard.setString(link.url.absoluteString, forType: .string)
        copied = event.id
        copiedReset?.cancel()
        let reset = DispatchWorkItem { [weak self] in self?.copied = nil }
        copiedReset = reset
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: reset)
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: ForkCalendarAppointmentsStrings.current.linkCopied,
                                        .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    /// The CRM's page of the appointment: its company's record, else the
    /// CRM itself; always on the profile's own origin.
    func crmURL(for event: NotchCalendarEvent) -> URL? {
        guard let appointment = appointments[event.id], let profile else { return nil }
        return appointment.companyID.flatMap(profile.dashboardURL(companyID:)) ?? profile.baseURL
    }

    /// "Open in <CRM>", or `nil` without a CRM read.
    func crmName(_ text: ForkMeetingStrings) -> String? {
        profile.map { text.castralOpen($0.displayName) }
    }

    func openCRM(_ event: NotchCalendarEvent) {
        guard let url = crmURL(for: event) else { return }
        NotchService.shared.perform { NSWorkspace.shared.open(url) }
    }

    /// Calendar itself, on the event, as the official card does.
    func openCalendar(_ event: NotchCalendarEvent) {
        guard let application = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        if let url = NotchCalendarSupport.eventURL(event) {
            NSWorkspace.shared.open([url], withApplicationAt: application, configuration: configuration)
        } else {
            NSWorkspace.shared.openApplication(at: application, configuration: configuration)
        }
    }
}
