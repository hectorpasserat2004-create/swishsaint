// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// The island's calendar with the video links and the CRM's appointments:
/// which link joins a call, which appointments show and when the CRM is
/// asked, how an appointment already in the calendar shows once, what the
/// closed island counts down to, and the texts.
enum ForkCalendarAppointmentsTests {
    static func run(_ suite: TestSuite) {
        links(suite)
        notLinks(suite)
        likeliest(suite)
        wrapped(suite)
        hostile(suite)
        join(suite)
        meetingLinks(suite)
        appointments(suite)
        reading(suite)
        privacy(suite)
        merge(suite)
        duplicates(suite)
        countdown(suite)
        texts(suite)
        setting(suite)
        mirror(suite)
    }

    // MARK: - Links

    private static func link(_ text: String) -> ForkCalendarVideoLink? { ForkCalendarVideoLink.first(in: text) }

    private static func links(_ suite: TestSuite) {
        let meet = link("Join with Google Meet: https://meet.google.com/abc-defg-hij?authuser=1\nOr dial: +33 1 23 45 67 89")
        suite.expect(meet?.provider == .meet && meet?.key == "meet:abc-defg-hij"
                        && meet?.url.absoluteString == "https://meet.google.com/abc-defg-hij?authuser=1",
                     "a Google Meet link in an invitation's notes is the call's, as written")
        let zoom = link("Join Zoom Meeting https://us02web.zoom.us/j/81234567890?pwd=AbC123.1 Meeting ID: 812 3456 7890")
        suite.expect(zoom?.provider == .zoom && zoom?.key == "zoom:81234567890"
                        && zoom?.url.absoluteString == "https://us02web.zoom.us/j/81234567890?pwd=AbC123.1",
                     "a Zoom link keeps its password; its meeting number names the call")
        let app = link("zoommtg://zoom.us/join?action=join&confno=81234567890&pwd=xyz")
        suite.expect(app?.provider == .zoom && app?.key == "zoom:81234567890", "a zoommtg:// link is a Zoom call")
        let personal = link("https://zoom.us/my/martial.room")
        suite.expect(personal?.provider == .zoom && personal?.key == "zoom:my/martial.room", "a Zoom personal room is one")
        let teams = link("""
            Microsoft Teams meeting
            Join on your computer: https://teams.microsoft.com/l/meetup-join/19%3ameeting_ZmE2%40thread.v2/0?context=%7b%22Tid%22%3a%22x%22%7d
            Learn more: https://aka.ms/JoinTeamsMeeting
            Meeting options: https://teams.microsoft.com/meetingOptions/?organizerId=x&tenantId=y
            """)
        suite.expect(teams?.provider == .teams && teams?.url.absoluteString.contains("/l/meetup-join/") == true,
                     "a Teams invitation's join link is the call, not its help or options links")
        suite.expect(link("https://teams.live.com/meet/9876543210?p=abc")?.provider == .teams, "a Teams personal meeting is one")
        suite.expect(link("https://acme.webex.com/meet/martial")?.provider == .webex
                        && link("https://acme.webex.com/acme/j.php?MTID=m1234abcd")?.key == "acme.webex.com/acme/j.php?mtid=m1234abcd",
                     "a Webex personal room and a Webex meeting are calls")
        suite.expect(link("https://whereby.com/acme-sales")?.provider == .whereby
                        && link("https://whereby.com/information/tos") == nil,
                     "a Whereby room is a call, its own pages are not")
        suite.expect(link("https://meet.jit.si/AcmeWeekly")?.provider == .jitsi, "a Jitsi room is a call")
        suite.expect(link("https://facetime.apple.com/join#v=1&p=AbCdEf&k=xyz")?.provider == .facetime,
                     "a FaceTime link is a call")
        suite.expect(link("<a href=\"https://zoom.us/j/123456789?pwd=a&amp;b=1\">Join</a>")?.url.absoluteString
                        == "https://zoom.us/j/123456789?pwd=a&b=1",
                     "a link inside HTML notes is read without its markup")
        suite.expect(link("(see https://meet.google.com/abc-defg-hij).")?.key == "meet:abc-defg-hij",
                     "the punctuation of a sentence around a link is not part of it")
        suite.expect(ForkCalendarVideoLink.Provider.allCases.allSatisfy { $0 == .other || ($0.name?.count ?? 99) <= 28 },
                     "each service's name fits the island")
    }

    private static func notLinks(_ suite: TestSuite) {
        let others = ["https://support.google.com/a/users/answer/9282720", "https://zoom.us/u/abcdef",
                      "https://zoom.us/download", "https://teams.microsoft.com/meetingOptions/?organizerId=x",
                      "https://aka.ms/JoinTeamsMeeting", "https://maps.apple.com/?q=Paris", "https://meet.google.com/",
                      "https://meet.google.com/landing", "https://www.webex.com/pricing", "tel:+33123456789",
                      "meet.google.com/abc-defg-hij", "https://evil.example/zoom.us/j/123456789",
                      "https://zoom.us.example.test/j/123456789", "https://calendar.google.com/calendar/event?eid=x"]
        let taken = others.filter { link($0) != nil }
        suite.expect(taken.isEmpty, "links that join no call are never one, nor a look-alike host: \(taken)")
        suite.expect(ForkCalendarVideoLink.find(url: nil, location: "Salle 4, 2e étage", notes: "Ordre du jour : budget") == nil,
                     "an event without a call link has none")
    }

    private static func likeliest(_ suite: TestSuite) {
        let found = ForkCalendarVideoLink.find(url: URL(string: "https://teams.microsoft.com/meet/123?p=x"),
                                               location: "https://zoom.us/j/123456789",
                                               notes: "https://meet.google.com/abc-defg-hij")
        suite.expect(found?.provider == .teams, "the event's address comes first")
        let placed = ForkCalendarVideoLink.find(url: URL(string: "https://example.com/agenda"),
                                                location: "https://zoom.us/j/123456789",
                                                notes: "Google Meet: https://meet.google.com/abc-defg-hij")
        suite.expect(placed?.provider == .zoom, "then its place, which the person wrote, before the notes a service added")
        let first = ForkCalendarVideoLink.find(url: nil, location: nil,
                                               notes: "Main: https://meet.google.com/abc-defg-hij backup https://zoom.us/j/123456789")
        suite.expect(first?.provider == .meet, "in notes, the first call link")
        let long = String(repeating: "x ", count: 15_000) + "https://meet.google.com/abc-defg-hij"
        suite.expect(link(long) == nil, "notes are searched in their first 20 000 characters only")
    }

    private static func wrapped(_ suite: TestSuite) {
        let safe = "https://eur01.safelinks.protection.outlook.com/?url=https%3A%2F%2Fzoom.us%2Fj%2F81234567890%3Fpwd%3Dabc&data=05%7C01"
        suite.expect(link(safe)?.url.absoluteString == "https://zoom.us/j/81234567890?pwd=abc",
                     "an Outlook safe link is read as the call link it wraps")
        let google = "https://www.google.com/url?q=https://meet.google.com/abc-defg-hij&sa=D&source=calendar"
        suite.expect(link(google)?.key == "meet:abc-defg-hij", "a Google redirect is read as the link it wraps")
        suite.expect(link("https://eur01.safelinks.protection.outlook.com/?url=https%3A%2F%2Fexample.com") == nil,
                     "a safe link to anything else is not a call")
    }

    /// The review's probe: look-alike hosts, user names, wrapped links of
    /// another kind, a service's own pages, a host's start link.
    private static func hostile(_ suite: TestSuite) {
        let refused = [
            "https://meet.google.com.evil.com/abc-defg-hij", "https://zoom.us@evil.com/j/123456789",
            "https://evil.com@zoom.us/j/123456789", "https://evil.com\\@zoom.us/j/123456789",
            "https://evilzoom.us/j/123456789", "https://zoom.us.evil.com/j/123456789",
            "https://teams.microsoft.com@evil.com/l/meetup-join/x", "https://evil.com#@teams.microsoft.com/l/meetup-join/x",
            "https://user:pw@teams.microsoft.com/l/meetup-join/19%3ax/0",
            "https://teams.microsoft.com.evil.com/l/meetup-join/x",
            "https://www.google.com/url?q=javascript:alert(1)//meet.google.com/abc-defg-hij",
            "https://www.google.com/url?q=file:///etc/passwd",
            "https://www.google.com/url?q=zoommtg://zoom.us/join?confno=123456789%26browser=evil",
            "https://www.google.com/url?q=zoommtg://evil.com/join?confno=123456789",
            "https://www.google.com/url?q=https://evil.com/meet.google.com/abc-defg-hij",
            "https://eur01.safelinks.protection.outlook.com/?url=vnc%3A%2F%2Fzoom.us%2Fj%2F123456789",
            "https://eur01.safelinks.protection.outlook.com/?url=smb%3A%2F%2Fzoom.us%2Fj%2F123456789",
            "https://eur01.safelinks.protection.outlook.com.evil.com/?url=https%3A%2F%2Fzoom.us%2Fj%2F123456789",
            "https://evil.com/?safelinks.protection.outlook.com&url=x",
            "zoommtg://evil.com/join?action=join&confno=123456789",
            "https://meet.google.com/landing?x=meet.google.com/abc-defg-hij",
            "https://help.webex.com/en-us/meet/article", "https://whereby.com/terms", "https://whereby.com/privacy",
            "https://8x8.vc/", "https://meet.jit.si/static/close.html", "https://facetime.apple.com/join",
            "https://zoom.us/j/123456789abc", "https://zoom.us/s/81234567890?zak=SECRET", "https://zoom.us/my/",
        ].filter { link($0) != nil }
        suite.expect(refused.isEmpty, "no look-alike, user name, foreign wrapped link, own page nor start link is a call: \(refused)")
        let rebuilt = link("zoomus://zoom.us/join?confno=123456789&browser=../../evil")
        suite.expect(rebuilt?.url.absoluteString == "zoommtg://zoom.us/join?action=join&confno=123456789",
                     "a Zoom app link is rebuilt with its meeting's fields only")
        suite.expect(link("HTTPS://MEET.GOOGLE.COM/ABC-DEFG-HIJ")?.key == "meet:abc-defg-hij"
                        && link("http://meet.google.com/abc-defg-hij")?.provider == .meet,
                     "a Meet link in capitals, or in plain HTTP, is still its call")
        suite.expect(link("https://teams.cloud.microsoft/l/meetup-join/19%3ameeting_x%40thread.v2/0")?.provider == .teams,
                     "Teams' new address is a call")
        suite.expect(link("https://zoom.us/j/123456789?pwd=abc.")?.url.absoluteString == "https://zoom.us/j/123456789?pwd=abc",
                     "a sentence's full stop is not part of the password")
        suite.expect(link("Lien:https://meet.google.com/abc-defg-hij")?.key == "meet:abc-defg-hij",
                     "a link glued to the word before it is read from its scheme")
        suite.expect(link("https://meet.google.com/abc-defg-hij\u{200B}")?.url.absoluteString == "https://meet.google.com/abc-defg-hij",
                     "an invisible character ends the link")
        suite.expect(link("https://zoom.us/my/x")?.key == "zoom:my/x" && link("https://meet.jit.si/AcmeWeekly")?.provider == .jitsi,
                     "a personal room and a Jitsi room are calls")
        let crm = ["http://evil.com/x", "javascript:alert(1)", "https://a@b.com", "data:text/html,hi",
                   "file:///Applications/Calculator.app", "https://x y.com", "http://meet.google.com/abc-defg-hij"]
            .filter { ForkCalendarVideoLink.meetingLink($0) != nil }
        suite.expect(crm.isEmpty, "a CRM's meeting link is HTTPS on a named host, without a user name: \(crm)")
        suite.expect(ForkCalendarVideoLink.meetingLink("https://meet.google.com.evil.com/abc-defg-hij")?.provider == .other,
                     "a look-alike Meet address from the CRM is never named Google Meet")
        suite.expect(ForkCalendarVideoLink.meetingLink("HTTPS://Example.com")?.provider == .other,
                     "an HTTPS meeting address of another service is still the CRM's link")
    }

    private static func join(_ suite: TestSuite) {
        let webinar = link("https://zoom.us/w/81234567890?tk=TOKEN&pwd=p")!
        suite.expect(ForkCalendarVideoLink.joinURL(webinar, zoomApp: true, teamsApp: false).absoluteString
                        == "zoommtg://zoom.us/join?action=join&confno=81234567890&pwd=p&tk=TOKEN",
                     "a Zoom webinar keeps its registration token when Zoom opens it")
        let zoom = link("https://us02web.zoom.us/j/81234567890?pwd=AbC123.1")!
        suite.expect(ForkCalendarVideoLink.joinURL(zoom, zoomApp: true, teamsApp: false).absoluteString
                        == "zoommtg://us02web.zoom.us/join?action=join&confno=81234567890&pwd=AbC123.1",
                     "Join opens Zoom itself when it is installed, with the password")
        suite.expect(ForkCalendarVideoLink.joinURL(zoom, zoomApp: false, teamsApp: true) == zoom.url,
                     "without the Zoom app, Join opens the link in the browser")
        let room = link("https://zoom.us/my/martial.room")!
        suite.expect(ForkCalendarVideoLink.joinURL(room, zoomApp: true, teamsApp: true) == room.url,
                     "a Zoom personal room opens as written")
        let teams = link("https://teams.microsoft.com/l/meetup-join/19%3ameeting_x%40thread.v2/0?context=%7b%7d")!
        suite.expect(ForkCalendarVideoLink.joinURL(teams, zoomApp: false, teamsApp: true).absoluteString
                        == "msteams:/l/meetup-join/19%3ameeting_x%40thread.v2/0?context=%7b%7d",
                     "Join opens Teams itself when it is installed")
        suite.expect(ForkCalendarVideoLink.joinURL(teams, zoomApp: true, teamsApp: false) == teams.url,
                     "without the Teams app, Join opens the link")
        let meet = link("https://meet.google.com/abc-defg-hij")!
        suite.expect(ForkCalendarVideoLink.joinURL(meet, zoomApp: true, teamsApp: true) == meet.url,
                     "a Meet link opens in the browser, as written")
    }

    private static func meetingLinks(_ suite: TestSuite) {
        suite.expect(ForkCalendarVideoLink.meetingLink("https://meet.google.com/abc-defg-hij")?.provider == .meet,
                     "a CRM appointment's Meet link is recognized")
        let cal = ForkCalendarVideoLink.meetingLink(" https://app.cal.com/video/AbCdEf123 ")
        suite.expect(cal?.provider == .other && cal?.url.absoluteString == "https://app.cal.com/video/AbCdEf123",
                     "the CRM's meeting link of another service is still the call")
        let refused = [nil, "", "tel:+33123456789", "Bureau de Paris", "javascript:alert(1)", "https://", "ftp://x.test/a"]
            .filter { ForkCalendarVideoLink.meetingLink($0) != nil }
        suite.expect(refused.isEmpty, "a CRM meeting field that is no web address is no link: \(refused)")
    }

    // MARK: - Appointments

    private static let now = ForkCastralContract.date("2026-10-20T08:00:00Z")!

    private static func booking(_ n: Int, start: TimeInterval, end: TimeInterval? = 1800, status: String? = "scheduled",
                                active: Bool? = true, company: String? = "ACME", attendee: String? = "Jérôme Dupont",
                                url: String? = nil) -> ForkCastralContract.Booking {
        var booking = ForkCastralContract.Booking(id: String(format: "00000000-0000-4000-8000-%012d", n))
        booking.startAt = now.addingTimeInterval(start)
        booking.endAt = end.map { now.addingTimeInterval(start + $0) }
        booking.status = status
        booking.isActive = active
        booking.attendeeName = attendee
        booking.meetingURL = url
        if let company { booking.company = .init(id: String(format: "11111111-0000-4000-8000-%012d", n), name: company) }
        return booking
    }

    private static func appointments(_ suite: TestSuite) {
        let read = ForkCalendarAppointmentsSupport.appointments([
            booking(1, start: 3600), booking(2, start: 7200, status: "cancelled"), booking(3, start: 7200, active: false),
            booking(4, start: 9000, status: "no_show"), booking(5, start: -7200), booking(6, start: -600),
            booking(7, start: 1800, end: nil, company: nil, url: "https://meet.google.com/abc-defg-hij"),
            booking(8, start: 5400, status: "rescheduled"),
        ], now: now)
        suite.expect(read.map { String($0.bookingID.suffix(1)) } == ["6", "7", "1", "8"],
                     "cancelled, missed and ended appointments are left out; one going on and a rescheduled one stay, by start")
        let named = read.first { $0.bookingID.hasSuffix("1") }
        suite.expect(named?.who == "ACME" && named?.attendee == "Jérôme Dupont" && named?.companyID != nil,
                     "an appointment is named after its company, with the person who booked")
        let person = read.first { $0.bookingID.hasSuffix("7") }
        suite.expect(person?.who == "Jérôme Dupont" && person?.attendee == nil && person?.link?.provider == .meet
                        && person?.end == now.addingTimeInterval(1800 + 3600),
                     "without a company, after the person; without an end, an hour long; its Meet link kept")
    }

    private static func reading(_ suite: TestSuite) {
        let window = ForkCalendarAppointmentsSupport.window(now: now)
        suite.expect(window.start == now.addingTimeInterval(-12 * 3600) && window.end == now.addingTimeInterval(14 * 86_400),
                     "the CRM is asked from 12 hours ago (one going on) to two weeks ahead")
        let due = ForkCalendarAppointmentsSupport.isDue
        suite.expect(due(nil, now, false) && !due(nil, now, true), "asked at the first look, never twice at once")
        suite.expect(!due(now.addingTimeInterval(-299), now, false) && due(now.addingTimeInterval(-300), now, false),
                     "then at most every five minutes")
        suite.expect(due(now.addingTimeInterval(60), now, false), "a clock set back asks again")
    }

    private static func privacy(_ suite: TestSuite) {
        let shows = ForkCalendarAppointmentsSupport.shows
        suite.expect(shows(true, true, true, true), "the CRM's appointments show with everything on")
        suite.expect(!shows(false, true, true, true) && !shows(true, false, true, true)
                        && !shows(true, true, false, true) && !shows(true, true, true, false),
                     "not with Meetings off, without a CRM, with the setting off, or with the island's calendar off")
        let hides = ForkCalendarAppointmentsSupport.hides
        suite.expect(!hides(false, true) && !hides(false, false),
                     "without a call, they show, the island in screenshots and videos or not (the official default)")
        suite.expect(hides(true, true),
                     "during a call detected or recorded, with the island in captures, they step aside: a shared screen never shows a prospect")
        suite.expect(!hides(true, false), "during a call with the island kept out of captures, they stay")
        let event = ForkCalendarAppointmentsSupport.event(
            ForkCalendarAppointmentsSupport.appointments([booking(1, start: 3600)], now: now)[0], mark: "CRM")
        suite.expect(event.countdownKey.isEmpty && event.calendarItemIdentifier.isEmpty && event.location.isEmpty,
                     "an appointment's event can never be chosen for a countdown, which would write it in the preferences")
    }

    // MARK: - Merge

    private static let week = DateInterval(start: now.addingTimeInterval(-8 * 3600), duration: 7 * 86_400)

    private static func calendarEvent(_ id: String, title: String, start: TimeInterval, length: TimeInterval = 1800,
                                      allDay: Bool = false) -> NotchCalendarEvent {
        NotchCalendarEvent(id: id, title: title, calendar: "Work", start: now.addingTimeInterval(start),
                           end: now.addingTimeInterval(start + length), allDay: allDay, location: "",
                           color: NotchCalendarColor(red: 1, green: 0, blue: 0), calendarItemIdentifier: "item-" + id,
                           countdownKey: "key-" + id)
    }

    private static func merged(_ events: [NotchCalendarEvent], _ bookings: [ForkCastralContract.Booking],
                               links: [String: String] = [:]) -> ForkCalendarAppointmentsSupport.Merged {
        ForkCalendarAppointmentsSupport.merge(events, links: links.compactMapValues(ForkCalendarVideoLink.first(in:)),
                                              appointments: ForkCalendarAppointmentsSupport.appointments(bookings, now: now),
                                              interval: week, mark: "CRM")
    }

    private static func merge(_ suite: TestSuite) {
        let standup = calendarEvent("a", title: "Standup", start: 1800)
        let result = merged([standup], [booking(1, start: 3600), booking(2, start: 30 * 86_400)])
        suite.expect(result.events.map(\.title) == ["Standup", "ACME"],
                     "an appointment only the CRM has joins the calendar's, by time; one past the interval does not")
        let crm = result.events[1]
        suite.expect(crm.id == "fork.crm:00000000-0000-4000-8000-000000000001" && crm.calendar == "CRM · Jérôme Dupont"
                        && crm.color == ForkCalendarAppointmentsSupport.tint && !crm.allDay,
                     "its card says CRM and who booked, in the CRM's own color")
        suite.expect(result.appointments[crm.id]?.who == "ACME" && result.appointments[standup.id] == nil,
                     "each appointment shown is known by its event's id; a calendar event of nobody's is not one")
        let alone = merged([standup], [])
        suite.expect(alone.events == [standup] && alone.appointments.isEmpty, "without appointments, the calendar is unchanged")
    }

    private static func duplicates(_ suite: TestSuite) {
        let call = calendarEvent("g", title: "Discovery call", start: 3900)
        let byLink = merged([call], [booking(1, start: 3600, url: "https://meet.google.com/abc-defg-hij")],
                            links: ["g": "https://meet.google.com/abc-defg-hij?authuser=0"])
        suite.expect(byLink.events.count == 1 && byLink.events[0].id == "g" && byLink.events[0].title == "Discovery call"
                        && byLink.events[0].calendar == "CRM · ACME" && byLink.events[0].countdownKey == "key-g"
                        && byLink.appointments["g"]?.who == "ACME",
                     "an appointment with the calendar event's Meet link shows once, as that event, marked as the CRM's")
        let later = calendarEvent("h", title: "Discovery call", start: 2 * 86_400)
        let personal = merged([later], [booking(1, start: 3600, url: "https://meet.google.com/abc-defg-hij")],
                              links: ["h": "https://meet.google.com/abc-defg-hij"])
        suite.expect(personal.events.count == 2,
                     "a personal room's link two days apart is another call: both show")
        let titled = calendarEvent("t", title: "Rendez-vous entre Martial et JEROME DUPONT", start: 3600)
        suite.expect(merged([titled], [booking(1, start: 3600)]).events.count == 1,
                     "the same start and its person's name in the title (case and accents aside) show once")
        let company = calendarEvent("c", title: "Démo Acme", start: 3600 + 30)
        suite.expect(merged([company], [booking(1, start: 3600)]).events.count == 1,
                     "the same minute and its company in the title show once")
        let other = calendarEvent("o", title: "Dentist", start: 3600)
        suite.expect(merged([other], [booking(1, start: 3600)]).events.count == 2,
                     "the same time but another title: both show")
        let moved = calendarEvent("m", title: "Démo Acme", start: 3600 + 600)
        suite.expect(merged([moved], [booking(1, start: 3600)]).events.count == 2,
                     "the same title at another time: both show")
        let day = calendarEvent("d", title: "ACME", start: 0, length: 86_400, allDay: true)
        suite.expect(merged([day], [booking(1, start: 0)]).events.count == 2, "an all-day event is never an appointment")
        let short = calendarEvent("w", title: "Call with Alice", start: 3600)
        suite.expect(merged([short], [booking(1, start: 3600, company: nil, attendee: "Ali")]).events.count == 2,
                     "a name is matched as whole words: Ali is not in Alice")
        suite.expect(byLink.originals["g"] == call, "the calendar's event is kept as it was, for a preview that hides the CRM")
        let pending = ForkCalendarAppointmentsSupport.merge(
            [call], links: [:], appointments: ForkCalendarAppointmentsSupport.appointments(
                [booking(1, start: 3600, url: "https://meet.google.com/abc-defg-hij"), booking(2, start: 9000)], now: now),
            interval: week, mark: "CRM", linksPending: true)
        suite.expect(pending.events.map(\.title) == ["Discovery call", "ACME"],
                     "while the calendar's links are being looked up, an appointment with a link waits; one without shows")
        let twice = merged([titled], [booking(1, start: 3600), booking(2, start: 3600, company: "Globex")])
        suite.expect(twice.events.count == 2 && twice.appointments.count == 2,
                     "a calendar event stands for one appointment only")
    }

    private static func countdown(_ suite: TestSuite) {
        let later = calendarEvent("a", title: "Standup", start: 50 * 60)
        let events = merged([later], [booking(1, start: 20 * 60)]).events
        let next = NotchCalendarSupport.countdown(events, now: now, starts: true, ends: false)
        suite.expect(next?.event.title == "ACME" && next?.ongoing == false,
                     "the closed island counts down to the next appointment, the CRM's when it comes first")
        suite.expect(NotchCalendarSupport.tileEvent(events, now: now)?.title == "ACME",
                     "and the Controls tile names it")
    }

    // MARK: - Texts and setting

    private static func fields(_ strings: ForkCalendarAppointmentsStrings) -> [(String, String)] {
        Mirror(reflecting: strings).children.compactMap { child in
            guard let label = child.label, let value = child.value as? String else { return nil }
            return (label, value)
        }
    }

    private static func texts(_ suite: TestSuite) {
        let languages = AppLanguage.allCases
        let all = languages.map(ForkCalendarAppointmentsStrings.strings)
        suite.expect(all.allSatisfy { fields($0).allSatisfy { !$0.1.isEmpty } }
                        && all.allSatisfy { Set(fields($0).map(\.0)) == Set(fields(.enUS).map(\.0)) },
                     "every text of the calendar's links and appointments exists in the fifteen languages")
        let english = Dictionary(uniqueKeysWithValues: fields(.enUS))
        var untranslated: [String] = []
        for language in languages where language != .enUS {
            for (label, value) in fields(.strings(language)) where value == english[label] && label != "crmMark" {
                untranslated.append("\(language.rawValue).\(label)")
            }
        }
        suite.expect(untranslated.isEmpty, "every text is translated: \(untranslated)")
        var tooLong: [String] = []
        for (language, strings) in zip(languages, all) {
            for said in [strings.crmMark, strings.join, strings.copyLink, strings.linkCopied, strings.videoCall]
                where said.count > 28 {
                tooLong.append("\(language.rawValue): \(said)")
            }
        }
        suite.expect(tooLong.isEmpty, "what the island shows fits in 28 characters: \(tooLong)")
        suite.expect(ForkCalendarAppointmentsStrings.strings(.fr).copyLink == "Copier le lien"
                        && ForkCalendarAppointmentsStrings.strings(.fr).join == "Rejoindre"
                        && ForkCalendarAppointmentsStrings.strings(.fr).linkCopied == "Lien copié",
                     "in French: Copier le lien, Rejoindre, Lien copié")
        suite.expect(all.allSatisfy { $0.settingCaptionFormat.components(separatedBy: "%@").count == 2
                                        && !$0.settingCaptionFormat.contains("%d") },
                     "the setting's caption takes the CRM's name, once")
        let french = fields(.fr).map(\.1)
        let loose = french.filter { text in
            text.contains("'") || text.contains("« ") || [":", ";", "!", "?", "»"].contains { text.contains(" " + $0) }
                || text.contains("5 minutes")
        }
        suite.expect(loose.isEmpty, "French texts use no-break spaces and typographic apostrophes: \(loose)")
        suite.expect(!all.flatMap { fields($0).map(\.1) }.contains { $0.contains("'") },
                     "no text uses a straight apostrophe")
    }

    /// The lines of a member opening with `opening` in a file, after `scope` when given.
    private static func block(_ path: String, _ opening: String, after scope: String? = nil) -> [String] {
        let lines = ((try? String(contentsOfFile: path, encoding: .utf8)) ?? "").components(separatedBy: "\n")
        let from = scope.flatMap { scope in lines.firstIndex { $0.hasPrefix(scope) } } ?? 0
        guard let start = lines[from...].firstIndex(of: opening),
              let end = lines[(start + 1)...].firstIndex(of: "    }") else { return [] }
        return Array(lines[start...end])
    }

    private static func card(_ path: String, after scope: String? = nil) -> [String] {
        block(path, "    private var card: some View {", after: scope)
    }

    private static func mirror(_ suite: TestSuite) {
        let official = card("Sources/Vorssaint/UI/Notch/NotchCalendarView.swift", after: "private struct NotchCalendarEventRow")
        let fork = card("Sources/Vorssaint/Fork/Notch/Calendar/ForkCalendarAppointmentRow.swift")
            .filter { !$0.contains("callLine(link)") }
        suite.expect(!official.isEmpty && official == fork,
                     "the card of an appointment with a link is the official card, line for line, plus the call's line: "
                        + "after an official change to NotchCalendarEventRow.card, copy it to ForkCalendarAppointmentRow")
        // The body: each official line, its "Open in Calendar" made the row's own title, in order; the
        // countdown's menu is the row's (`menuItems`).
        let officialBody = block("Sources/Vorssaint/UI/Notch/NotchCalendarView.swift", "    var body: some View {",
                                 after: "private struct NotchCalendarEventRow")
            .filter { !$0.contains("NotchCountdownChoice") }
            .map { $0.replacingOccurrences(of: "text.openCalendar", with: "openTitle") }
        var forkBody = block("Sources/Vorssaint/Fork/Notch/Calendar/ForkCalendarAppointmentRow.swift", "    var body: some View {",
                             after: "struct ForkCalendarAppointmentRow")[...]
        let inOrder = officialBody.allSatisfy { line in
            guard let found = forkBody.firstIndex(of: line) else { return false }
            forkBody = forkBody[(found + 1)...]
            return true
        }
        suite.expect(officialBody.count >= 5 && inOrder,
                     "the row's button is the official card's, with every one of its modifiers, in order")
    }

    private static func setting(_ suite: TestSuite) {
        let key = ForkDefaultsKey.meetingsIslandAppointments
        suite.expect(key.hasPrefix("fork.meetings.") && ForkDefaults.registered[key] as? Bool == true
                        && ForkDefaults.backupKeys.contains(key),
                     "the CRM's appointments show by default once a CRM is imported, and the choice follows the backup")
    }
}
