// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// The offer that never blocks: "Later ▾" plans a start the call ending
/// takes away, ✕ says once where the meeting can still be recorded from,
/// and the closed island keeps the call at hand while it is offered.
enum ForkMeetingW2FTests {
    static func run(_ suite: TestSuite) {
        schedule(suite)
        due(suite)
        cancelled(suite)
        callEnds(suite)
        locked(suite)
        nudgeKeepsThePlan(suite)
        keptMinutes(suite)
        notOffered(suite)
        later(suite)
        folded(suite)
        timing(suite)
        booking(suite)
        island(suite)
        texts(suite)
    }

    private static let t0 = Date(timeIntervalSinceReferenceDate: 810_000_000)
    private static let meetA = ForkMeetingIdentity("meet:abc-defg-hij")

    private static func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    private static func candidate() -> ForkMeetingCandidate {
        ForkMeetingCandidate(identity: meetA, provider: "meet", providerName: "Google Meet", providerShortName: "Meet",
                             titleName: "Point hebdo", meetCode: "abc-defg-hij", calendarTitle: nil,
                             appBundle: "com.google.Chrome", pid: 100, windowID: 1, windowBundle: "com.google.Chrome",
                             defaultSound: .app, policy: .ask, silenced: false, bornAt: t0, alwaysProof: .meetCode)
    }

    private static func request(blocked: Bool = false) -> ForkMeetingStartRequest {
        let facts = ForkMeetingStartFacts(freeBytes: blocked ? 0 : 50_000_000_000, screenRecordingAllowed: true,
                                          microphoneAllowed: true, officialRecorderBusy: false)
        let settings = ForkMeetingCaptureSettings(target: .window, systemAudio: .app, microphone: "meeting",
                                                  quality: .standard)
        return ForkMeetingStartRequest(settings: settings, facts: facts)
    }

    private static func offering(blocked: Bool = false) -> ForkMeetingMachine {
        var machine = ForkMeetingMachine()
        machine.handle(.candidates([candidate()], request(blocked: blocked)), now: at(0))
        return machine
    }

    private static func offer(_ machine: ForkMeetingMachine) -> ForkMeetingOffer? {
        guard case let .offering(offer) = machine.phase else { return nil }
        return offer
    }

    // MARK: - The machine

    private static func schedule(_ suite: TestSuite) {
        var machine = offering()
        guard let open = offer(machine) else { return suite.expect(false, "a detected call is offered") }
        let effects = machine.handle(.schedule(5 * 60), now: at(4))
        var planned = open
        planned.startsAt = at(304)
        planned.scheduledAt = at(4)
        planned.collapsed = true
        suite.expect(effects == [.showOffer(planned), .announce(.scheduled(minutes: 5))] && offer(machine) == planned,
                     "Start in 5 min plans the start, folds the offer, and is said to VoiceOver")
        suite.expect(ForkMeetingDetectionSupport.clockRuns(phase: machine.phase),
                     "the one-second clock runs for a start planned, though the offer is folded")
        suite.expect(machine.handle(.tick, now: at(30)).isEmpty && machine.handle(.tick, now: at(303)).isEmpty,
                     "nothing starts before it is due, and the 20 s fold asks nothing of an offer already folded")
        var fifteen = offering()
        suite.expect(fifteen.handle(.schedule(15 * 60), now: at(4)).contains(.announce(.scheduled(minutes: 15)))
                        && offer(fifteen)?.startsAt == at(904),
                     "Start in 15 min plans it 15 minutes on")
        var idle = ForkMeetingMachine()
        suite.expect(idle.handle(.schedule(300), now: at(1)).isEmpty && idle.phase == .idle,
                     "with no offer, nothing is planned")
        var silly = offering()
        suite.expect(silly.handle(.schedule(0), now: at(1)).isEmpty && offer(silly)?.startsAt == nil,
                     "a start planned now or before is no plan: nothing changes")
    }

    private static func due(_ suite: TestSuite) {
        var machine = offering()
        machine.handle(.schedule(300), now: at(4))
        let effects = machine.handle(.tick, now: at(304))
        guard let after = offer(machine) else { return suite.expect(false, "the offer is still there when its start is due") }
        suite.expect(effects == [.showOffer(after), .startScheduled] && after.startsAt == nil && after.scheduledAt == nil,
                     "due: the plan goes and the service is asked to answer the offer as Record would")
        suite.expect(machine.handle(.tick, now: at(305)).isEmpty, "the start is asked once")
        let started = machine.handle(.accept(request()), now: at(305))
        guard case let .starting(pending) = machine.phase else { return suite.expect(false, "Record then starts it") }
        suite.expect(started.first == .hideOffer && pending.config.origin == .offered && pending.config.meeting?.identity == meetA,
                     "the start is the offered meeting's, which the detection may stop at its end")

        var blocked = offering(blocked: true)
        blocked.handle(.schedule(300), now: at(4))
        suite.expect(blocked.handle(.tick, now: at(304)).contains(.startScheduled),
                     "a greyed offer may be planned too: its start is still asked when due")
        let refused = blocked.handle(.accept(request(blocked: true)), now: at(305))
        suite.expect(refused.contains(.notice(.failure(.diskFullAtStart(requiredBytes: ForkMeetingDisk.requiredToStart(.standard)))))
                        && offer(blocked) != nil,
                     "and if it still cannot record, the refusal is said and the offer stays")
    }

    private static func cancelled(_ suite: TestSuite) {
        var machine = offering()
        machine.handle(.schedule(300), now: at(4))
        let effects = machine.handle(.schedule(nil), now: at(60))
        guard let after = offer(machine) else { return suite.expect(false, "Cancel keeps the offer") }
        suite.expect(effects == [.showOffer(after), .announce(.scheduleCancelled)] && after.startsAt == nil,
                     "Cancel on the card of a start planned calls it off, said to VoiceOver; the offer stays")
        suite.expect(machine.handle(.tick, now: at(304)).isEmpty, "and nothing starts at the time it was planned for")
        suite.expect(machine.handle(.schedule(nil), now: at(320)).isEmpty, "Cancel with nothing planned does nothing")
    }

    private static func callEnds(_ suite: TestSuite) {
        var gone = offering()
        gone.handle(.schedule(300), now: at(4))
        suite.expect(gone.handle(.candidates([], request()), now: at(100)) == [.hideOffer] && gone.phase == .idle,
                     "the call ending takes the offer away, and its start planned with it")
        suite.expect(gone.handle(.tick, now: at(304)).isEmpty && gone.phase == .idle, "nothing starts once it is over")

        var ended = offering()
        ended.handle(.schedule(300), now: at(4))
        suite.expect(ended.handle(.endProbable(meetA, countdown: 15), now: at(100)) == [.hideOffer]
                        && ended.handle(.tick, now: at(304)).isEmpty,
                     "so does the detection's end of the call")

        var off = offering()
        off.handle(.schedule(300), now: at(4))
        off.handle(.featureDisabled, now: at(10))
        suite.expect(off.handle(.tick, now: at(304)).isEmpty && off.phase == .idle, "turning the feature off too")
    }

    private static func locked(_ suite: TestSuite) {
        var machine = offering()
        machine.handle(.schedule(300), now: at(4))
        machine.handle(.locked, now: at(200))
        suite.expect(machine.handle(.tick, now: at(304)).isEmpty && offer(machine)?.startsAt == at(304),
                     "on a locked screen the start waits: it would film the lock, nobody there to see it")
        machine.handle(.unlocked, now: at(400))
        suite.expect(machine.handle(.tick, now: at(401)).contains(.startScheduled), "it comes at the first tick after the unlock")
    }

    private static func nudgeKeepsThePlan(_ suite: TestSuite) {
        var machine = offering()
        machine.handle(.schedule(300), now: at(4))
        let effects = machine.handle(.nudge(meetA), now: at(90))
        guard let raised = offer(machine) else { return suite.expect(false, "the nudge keeps the offer") }
        suite.expect(effects.contains(.nudgeOffer(raised)) && raised.startsAt == at(304) && !raised.collapsed,
                     "a nudge opens the offer again, its start still planned")
        suite.expect(machine.handle(.tick, now: at(304)).contains(.startScheduled), "and the start still comes")
    }

    /// The kept sound is the offered meeting's for as long as it is
    /// offered: a start planned keeps it offered, and starts that meeting,
    /// whose recording opens with what was kept (`ForkMeetingService.lookback(for:)`).
    private static func keptMinutes(_ suite: TestSuite) {
        var machine = offering()
        machine.handle(.schedule(900), now: at(4))
        var keptAll = true
        for second in stride(from: 30.0, to: 904, by: 30) {
            machine.handle(.candidates([candidate()], request()), now: at(second))
            machine.handle(.tick, now: at(second))
            if offer(machine)?.candidate.identity != meetA { keptAll = false }
        }
        machine.handle(.tick, now: at(904))
        machine.handle(.accept(request()), now: at(905))
        guard case let .starting(pending) = machine.phase else { return suite.expect(false, "the start comes") }
        suite.expect(keptAll && pending.config.meeting?.identity == meetA,
                     "the meeting stays offered while its start is planned, then starts as itself: its kept minutes go with it")
    }

    private static func notOffered(_ suite: TestSuite) {
        var machine = offering()
        machine.handle(.schedule(300), now: at(4))
        suite.expect(machine.handle(.dismiss(.thisTime), now: at(10))
                        == [.hideOffer, .silence(meetA), .notice(.notOffered), .announce(.notOffered)],
                     "✕: no more offers for this meeting, said once on the card, and to VoiceOver")
        suite.expect(machine.handle(.tick, now: at(304)).isEmpty && machine.phase == .idle,
                     "a start planned goes with it")
        suite.expect(ForkMeetingNotifyEvent.event(of: .notOffered) == nil
                        && ForkMeetingNotifyEvent.shows(.notOffered, isOn: { _ in false }),
                     "it answers a click: no switch silences it")
        suite.expect(ForkMeetingIslandCard.note.afterClose(undoUntil: nil, now: at(0)) == .gone,
                     "the island closed over that line keeps nothing")
    }

    // MARK: - The offer's parts

    private static func later(_ suite: TestSuite) {
        suite.expect(ForkMeetingOfferLater.allCases == [.inFive, .inFifteen, .whenever]
                        && ForkMeetingOfferLater.inFive.delay == 300 && ForkMeetingOfferLater.inFifteen.delay == 900
                        && ForkMeetingOfferLater.whenever.delay == nil,
                     "Later: in 5 minutes, in 15, or whenever the person wants (nothing planned)")
        let french = ForkMeetingStrings.strings(.fr)
        suite.expect(ForkMeetingOfferLater.allCases.map { $0.title(french) }
                        == ["Démarrer dans 5\u{00A0}min", "Démarrer dans 15\u{00A0}min", "Quand je veux"],
                     "in French")
    }

    private static func folded(_ suite: TestSuite) {
        suite.expect(ForkMeetingOfferFolded.place(indicator: .auto, islandShowsActivity: true)
                        == ForkMeetingOfferFolded(activity: true, reminder: false),
                     "folded, the offer waits in the closed island alone while it shows there")
        suite.expect(ForkMeetingOfferFolded.place(indicator: .auto, islandShowsActivity: false)
                        == ForkMeetingOfferFolded(activity: true, reminder: true),
                     "the reminder comes back where the island does not show it (hidden, full screen, another activity)")
        suite.expect(ForkMeetingOfferFolded.place(indicator: .pill, islandShowsActivity: false)
                        == ForkMeetingOfferFolded(activity: false, reminder: true),
                     "with the pill alone, no activity: the reminder")
        suite.expect(ForkMeetingOfferFolded.place(indicator: .both, islandShowsActivity: true)
                        == ForkMeetingOfferFolded(activity: true, reminder: true),
                     "with both, both")
        suite.expect(ForkMeetingOfferClick.collapses(offerShownInIsland: true, clickInsideIsland: false)
                        && !ForkMeetingOfferClick.collapses(offerShownInIsland: true, clickInsideIsland: true)
                        && !ForkMeetingOfferClick.collapses(offerShownInIsland: false, clickInsideIsland: false),
                     "a click anywhere outside the island folds its offer; inside, or with no offer there, nothing")
    }

    private static func timing(_ suite: TestSuite) {
        suite.expect(ForkMeetingOfferTiming.countdown(until: at(300), now: at(47.6)) == "4:13"
                        && ForkMeetingOfferTiming.countdown(until: at(900), now: at(0)) == "15:00"
                        && ForkMeetingOfferTiming.countdown(until: at(300), now: at(299.5)) == "0:01"
                        && ForkMeetingOfferTiming.countdown(until: at(300), now: at(301)) == "0:00",
                     "the countdown rounds up: it reads 0:00 only once the start is due")
        suite.expect(ForkMeetingOfferTiming.progress(from: at(0), until: at(300), now: at(75)) == 0.25
                        && ForkMeetingOfferTiming.progress(from: at(0), until: at(300), now: at(-5)) == 0
                        && ForkMeetingOfferTiming.progress(from: at(0), until: at(300), now: at(400)) == 1
                        && ForkMeetingOfferTiming.progress(from: at(0), until: at(0), now: at(0)) == 1,
                     "the island's gauge fills from the choice to the start, bounded")
    }

    /// A CRM's appointment ("RDV : ACME · 10:00", its time written out here:
    /// nothing reads the Mac's 12- or 24-hour setting) gets the compact
    /// card's second line when it holds on one, else stands apart.
    private static func booking(_ suite: TestSuite) {
        let short = ForkMeetingOfferText.compactLines(subtitle: "Google Meet · abc-defg-hij", booking: "RDV : ACME · 10:00")
        suite.expect(short.lines == ["Google Meet · abc-defg-hij", "RDV : ACME · 10:00"] && !short.bookingApart,
                     "short enough, the appointment goes under the service and the code")
        let long = ForkMeetingOfferText.compactLines(subtitle: "Google Meet · abc-defg-hij",
                                                     booking: "RDV : Laboratoires Pierre Fabre · 10:00")
        suite.expect(long.lines == ["Google Meet · abc-defg-hij"] && long.bookingApart,
                     "too long, the card keeps the service and code; the appointment goes first in ⋯ and to VoiceOver")
        let alone = ForkMeetingOfferText.compactLines(subtitle: nil, booking: "RDV : ACME")
        let none = ForkMeetingOfferText.compactLines(subtitle: "Meet", booking: nil)
        suite.expect(alone.lines == ["RDV : ACME"] && !alone.bookingApart && none.lines == ["Meet"] && !none.bookingApart
                        && ForkMeetingOfferText.compactLines(subtitle: nil, booking: nil).lines.isEmpty,
                     "alone, the appointment is the line; without one, nothing changes")
    }

    private static func island(_ suite: TestSuite) {
        let detected = ForkMeetingIslandOffer(provider: "Meet")
        let planned = ForkMeetingIslandOffer(provider: "Meet", startsAt: at(300), scheduledAt: at(0))
        suite.expect(ForkMeetingIslandRules.showsStrip(enabled: true, indicator: .auto, state: .hidden, offer: detected)
                        && ForkMeetingIslandRules.showsStrip(enabled: true, indicator: .both, state: .hidden, offer: planned),
                     "the closed island lists a call offered and not refused")
        suite.expect(!ForkMeetingIslandRules.showsStrip(enabled: true, indicator: .auto, state: .hidden, offer: nil)
                        && !ForkMeetingIslandRules.showsStrip(enabled: true, indicator: .pill, state: .hidden, offer: detected)
                        && !ForkMeetingIslandRules.showsStrip(enabled: false, indicator: .auto, state: .hidden, offer: detected),
                     "not once refused or gone, nor with the pill alone, nor with the feature off")
        let recording = ForkMeetingPillState.recording(ForkMeetingClock(recordedBefore: 0, runningSince: at(0)),
                                                       diskMinutesLeft: nil)
        suite.expect(ForkMeetingIslandRules.showsStrip(enabled: true, indicator: .auto, state: recording, offer: nil)
                        == ForkMeetingIslandRules.showsStrip(enabled: true, indicator: .auto, state: recording),
                     "a recording shows as before")
        suite.expect(detected.phase == .detected && planned.phase == .scheduled(startsAt: at(300), scheduledAt: at(0))
                        && planned.phase.isScheduled && !detected.phase.isScheduled,
                     "Meet · ⏺, or the countdown of a start planned")
        let english = ForkMeetingStrings.strings(.enUS)
        suite.expect(ForkMeetingIslandRules.offerReading(detected, now: at(10)) == "Meet"
                        && ForkMeetingIslandRules.offerReading(planned, now: at(48)) == "4:12",
                     "right of the camera: the provider's short name, never the meeting's, or the time left")
        suite.expect(ForkMeetingIslandRules.offerLabel(detected, strings: english) == "Meeting detected, Meet"
                        && ForkMeetingIslandRules.offerValue(detected, now: at(0), language: .enUS, strings: english).isEmpty,
                     "VoiceOver: what it is")
        let value = ForkMeetingIslandRules.offerValue(planned, now: at(48), language: .enUS, strings: english)
        suite.expect(value.hasPrefix("Starts in ") && value.contains("4") && value.contains("12"),
                     "and when the start comes, as a spoken duration: \(value)")
    }

    // MARK: - Words

    private static func texts(_ suite: TestSuite) {
        var tooLong: [String] = []
        var broken: [String] = []
        for language in AppLanguage.allCases {
            let s = ForkMeetingStrings.strings(language)
            let short = [s.offerLater, s.offerStartIn(minutes: 15), s.offerWhenever, s.offerStartsIn("14:59"),
                         s.offerStartNow, s.offerCancelStart, ForkMeetingNotice.notOffered.title(s)]
            for text in short where text.count > 28 || text.isEmpty { tooLong.append("\(language.rawValue): \(text)") }
            let formats = [s.offerStartInFormat.contains("%d"), s.offerStartsInFormat.contains("%@"),
                           s.islandOfferLabelFormat.contains("%@"), s.voiceScheduledFormat.contains("%d")]
            let words = [s.offerDismiss, s.islandOfferHint, s.noticeNotOfferedDetail, s.voiceScheduleCancelled,
                         s.voiceNotOffered]
            if formats.contains(false) || words.contains(where: \.isEmpty) { broken.append(language.rawValue) }
        }
        suite.expect(tooLong.isEmpty, "every short text of the offer fits in 28 characters: \(tooLong)")
        suite.expect(broken.isEmpty, "every language has every text, its numbers in place: \(broken)")
        let french = ForkMeetingStrings.strings(.fr)
        suite.expect(ForkMeetingAnnouncement.scheduled(minutes: 5).text(french) == "L’enregistrement démarrera dans 5\u{00A0}minutes."
                        && ForkMeetingNotice.notOffered.title(french) == "Plus proposé pour cet appel",
                     "in French, with its no-break spaces")
        suite.expect(ForkMeetingNotice.notOffered.detail(french)?.contains("raccourci") == true
                        && ForkMeetingNotice.notOffered.detail(french)?.contains("l’île") == true,
                     "the line after ✕ says where it can still be recorded from")
    }
}
