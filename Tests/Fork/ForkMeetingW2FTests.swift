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
        reviewProbes(suite)
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

    private static func request(blocked: Bool = false, onMicrophone: Bool = false) -> ForkMeetingStartRequest {
        var facts = ForkMeetingStartFacts(freeBytes: blocked ? 0 : 50_000_000_000, screenRecordingAllowed: true,
                                          microphoneAllowed: true, officialRecorderBusy: false)
        if onMicrophone { facts.meetingsOnMicrophone = [meetA] }
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
        suite.expect(effects == [.showOffer(after), .startScheduled] && after.startAsked && after.startsAt == at(304),
                     "due: the service is asked to answer the offer as Record would, the plan drawn full meanwhile")
        suite.expect(machine.handle(.tick, now: at(305)).isEmpty, "the start is asked once")
        let started = machine.handle(.accept(request()), now: at(305))
        guard case let .starting(pending) = machine.phase else { return suite.expect(false, "Record then starts it") }
        suite.expect(started.first == .hideOffer && pending.config.origin == .offered && pending.config.meeting?.identity == meetA,
                     "the start is the offered meeting's, which the detection may stop at its end")

        // Greyed once planned (the disk filled meanwhile): asked, refused.
        var blocked = offering()
        blocked.handle(.schedule(300), now: at(4))
        blocked.handle(.candidates([candidate()], request(blocked: true)), now: at(100))
        suite.expect(blocked.handle(.tick, now: at(304)).contains(.startScheduled),
                     "an offer greyed after its plan still has its start asked when due")
        let refused = blocked.handle(.accept(request(blocked: true)), now: at(305))
        suite.expect(refused.contains(.notice(.failure(.diskFullAtStart(requiredBytes: ForkMeetingDisk.requiredToStart(.standard)))))
                        && offer(blocked) != nil && offer(blocked)?.startsAt == nil,
                     "and if it still cannot record, the refusal is said, the offer stays and its plan goes")
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
        machine.handle(.unlocked, now: at(340))
        suite.expect(machine.handle(.tick, now: at(341)).contains(.startScheduled),
                     "it comes at the first tick after an unlock within a minute of its time")
    }

    private static func nudgeKeepsThePlan(_ suite: TestSuite) {
        var machine = offering()
        machine.handle(.schedule(300), now: at(4))
        suite.expect(machine.handle(.nudge(meetA), now: at(90)).isEmpty && offer(machine)?.collapsed == true,
                     "a start planned is the answer: no nudge raises the offer meanwhile")
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

    /// The review's probes P1–P6, and what came of them.
    private static func reviewProbes(_ suite: TestSuite) {
        // P1: "Never for Meet" chosen on the page while a start is planned.
        var never = offering()
        never.handle(.schedule(300), now: at(2))
        var refused = candidate()
        refused.policy = .never
        let calledOff = never.handle(.candidates([refused], request()), now: at(100))
        suite.expect(calledOff.contains(.announce(.scheduleCancelled)) && offer(never)?.startsAt == nil
                        && !never.handle(.tick, now: at(302)).contains(.startScheduled),
                     "P1: Never chosen meanwhile calls the start planned off")

        // P2: its app off the microphone since the plan: asked again.
        var left = ForkMeetingMachine()
        left.handle(.candidates([candidate()], request(onMicrophone: true)), now: at(0))
        left.handle(.schedule(300), now: at(2))
        for second in stride(from: 10.0, to: 302, by: 10) {
            left.handle(.candidates([candidate()], request(onMicrophone: false)), now: at(second))
        }
        let asked = left.handle(.tick, now: at(302))
        guard let reopened = offer(left) else { return suite.expect(false, "P2: the offer stays") }
        suite.expect(asked == [.reopenOffer(reopened), .announce(.offered("Point hebdo"))]
                        && reopened.startsAt == nil && !reopened.collapsed && reopened.collapsesAt == at(322),
                     "P2: a call its app has left is not recorded on the plan: the offer opens again for 20 s")
        var stayed = ForkMeetingMachine()
        stayed.handle(.candidates([candidate()], request(onMicrophone: true)), now: at(0))
        stayed.handle(.schedule(300), now: at(2))
        stayed.handle(.candidates([candidate()], request(onMicrophone: true)), now: at(250))
        suite.expect(stayed.handle(.tick, now: at(302)).contains(.startScheduled),
                     "its app still on the microphone, it starts")
        var unknown = offering()
        unknown.handle(.schedule(300), now: at(2))
        suite.expect(unknown.handle(.tick, now: at(302)).contains(.startScheduled),
                     "a Mac that cannot tell which app has the microphone starts it as planned")

        // P3: asleep without a lock, awake 2 h later.
        var slept = offering()
        slept.handle(.schedule(300), now: at(2))
        slept.handle(.willSleep, now: at(60))
        slept.handle(.didWake, now: at(7260))
        let late = slept.handle(.tick, now: at(7261))
        suite.expect(late.first.map { if case .reopenOffer = $0 { return true } else { return false } } == true
                        && !late.contains(.startScheduled),
                     "P3: a start long overdue (the Mac asleep) asks again instead of recording")
        // P4: locked 2 h, then unlocked.
        var locked = offering()
        locked.handle(.schedule(300), now: at(2))
        locked.handle(.locked, now: at(60))
        locked.handle(.unlocked, now: at(7260))
        suite.expect(!locked.handle(.tick, now: at(7261)).contains(.startScheduled) && offer(locked)?.startsAt == nil,
                     "P4: and so does one the lock held 2 hours")
        var shortLock = offering()
        shortLock.handle(.schedule(300), now: at(2))
        shortLock.handle(.locked, now: at(280))
        shortLock.handle(.unlocked, now: at(330))
        suite.expect(shortLock.handle(.tick, now: at(331)).contains(.startScheduled),
                     "a lock that ends within a minute of the time still starts it")

        // P6: no nudge, no "It's started", while a start is planned.
        var planned = offering()
        planned.handle(.schedule(900), now: at(2))
        suite.expect(planned.handle(.nudge(meetA), now: at(60)).isEmpty, "P6: a start planned is not nudged")

        // Its gauge stays full until the recording starts; refused, the plan goes.
        var due = offering()
        due.handle(.schedule(300), now: at(2))
        due.handle(.tick, now: at(302))
        suite.expect(offer(due)?.startsAt == at(302) && offer(due)?.startAsked == true
                        && due.handle(.tick, now: at(303)).isEmpty,
                     "asked, the plan stays drawn (no ◉ Meet for a second) and is asked once")
        let refusal = due.handle(.accept(request(blocked: true)), now: at(304))
        suite.expect(offer(due)?.startsAt == nil && refusal.contains(where: { if case .showOffer = $0 { return true } else { return false } }),
                     "a start planned and refused takes its plan away")
        var lost = offering()
        lost.handle(.schedule(300), now: at(2))
        lost.handle(.tick, now: at(302))
        suite.expect(lost.handle(.tick, now: at(320)).isEmpty
                        && lost.handle(.tick, now: at(333)).first.map { if case .reopenOffer = $0 { return true } else { return false } } == true,
                     "an answer lost on the way: after 30 s the offer asks again")

        // A greyed offer plans nothing.
        var greyed = offering(blocked: true)
        suite.expect(greyed.handle(.schedule(300), now: at(2)).isEmpty && offer(greyed)?.startsAt == nil,
                     "a greyed offer, which could not start then either, plans nothing")
        suite.expect(ForkMeetingOfferLater.choices(blocked: true) == [.whenever]
                        && ForkMeetingOfferLater.choices(blocked: false) == ForkMeetingOfferLater.allCases,
                     "its Later offers When I want only")
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
    /// card's second line, cut with "…" when long, said whole to VoiceOver;
    /// never in ⋯, which screen shares see.
    private static func booking(_ suite: TestSuite) {
        let short = ForkMeetingOfferText.compactLines(subtitle: "Google Meet · abc-defg-hij", booking: "RDV : ACME · 10:00")
        suite.expect(short.lines == ["Google Meet · abc-defg-hij", "RDV : ACME · 10:00"] && short.bookingInFull == nil,
                     "short enough, the appointment goes under the service and the code")
        let whole = "RDV : Laboratoires Pierre Fabre · 10:00"
        let long = ForkMeetingOfferText.compactLines(subtitle: "Google Meet · abc-defg-hij", booking: whole)
        suite.expect(long.lines.count == 2 && long.lines[1].hasSuffix("…") && long.lines[1].count <= 32
                        && whole.hasPrefix(String(long.lines[1].dropLast())) && long.bookingInFull == whole,
                     "too long, its line is cut with …, and the whole goes to VoiceOver and the tooltip: \(long.lines)")
        let alone = ForkMeetingOfferText.compactLines(subtitle: nil, booking: "RDV : ACME")
        let none = ForkMeetingOfferText.compactLines(subtitle: "Meet", booking: nil)
        suite.expect(alone.lines == ["RDV : ACME"] && none.lines == ["Meet"] && none.bookingInFull == nil
                        && ForkMeetingOfferText.compactLines(subtitle: nil, booking: nil).lines.isEmpty,
                     "alone, the appointment is the line; without one, nothing changes")
        // The reviewer's probe P5: a company of 12 letters fits in every language.
        for language in [AppLanguage.enUS, .fr, .de] {
            let line = ForkMeetingStrings.strings(language).castralBooking("ACME Conseil · 10:00")
            let result = ForkMeetingOfferText.compactLines(subtitle: "Google Meet · abc-defg-hij", booking: line)
            suite.expect(result.lines.last.map { $0 == line || $0.hasSuffix("…") } == true,
                         "\(language.rawValue): the appointment shows, whole or cut, never moved away")
        }
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
        suite.expect(ForkMeetingIslandRules.listsOffer(scheduled: false, otherActivityLive: false)
                        && !ForkMeetingIslandRules.listsOffer(scheduled: false, otherActivityLive: true)
                        && ForkMeetingIslandRules.listsOffer(scheduled: true, otherActivityLive: true),
                     "a call only offered never goes before a live official activity, but its countdown does")
        suite.expect(ForkMeetingIslandRules.offerReading(planned, now: at(48), named: true) == "Meet · 4:12"
                        && ForkMeetingIslandRules.offerReading(detected, now: at(48), named: true) == "Meet",
                     "where there is room, the countdown carries the service's name")
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
            let words = [s.offerDismiss, s.islandOfferHint, s.noticeNotOfferedDetail, s.noticeNotOfferedShortcutDetail,
                         s.voiceScheduleCancelled, s.offerCancelStartSpoken, s.offerLaterHelp]
            if formats.contains(false) || words.contains(where: \.isEmpty) { broken.append(language.rawValue) }
        }
        suite.expect(tooLong.isEmpty, "every short text of the offer fits in 28 characters: \(tooLong)")
        suite.expect(broken.isEmpty, "every language has every text, its numbers in place: \(broken)")
        let french = ForkMeetingStrings.strings(.fr)
        suite.expect(ForkMeetingAnnouncement.scheduled(minutes: 5).text(french) == "L’enregistrement démarrera dans 5\u{00A0}minutes."
                        && ForkMeetingNotice.notOffered.title(french) == "Plus proposé pour cet appel",
                     "in French, with its no-break spaces")
        suite.expect(ForkMeetingNotice.notOffered.detail(french)
                        == "Vous pouvez encore l’enregistrer depuis l’île ou la barre de commandes."
                        && french.noticeNotOfferedShortcutDetail.contains("raccourci"),
                     "the line after ✕ says where it can still be recorded from; the shortcut only in its own version")
        suite.expect(ForkMeetingAnnouncement.notOffered.text(french)
                        == "Plus proposé pour cet appel. Vous pouvez encore l’enregistrer depuis l’île ou la barre de commandes.",
                     "VoiceOver hears the title, then the line")
        var cut: [String] = []
        for language in AppLanguage.allCases {
            let s = ForkMeetingStrings.strings(language)
            if !s.lookbackCaption.contains("✕") { cut.append(language.rawValue + " (no ✕)") }
        }
        suite.expect(cut.isEmpty, "the kept minutes' caption names ✕, the offer having no Not Now any more: \(cut)")
    }
}
