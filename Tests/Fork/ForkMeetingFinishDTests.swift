// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// "I forget to start the recording": the offer comes back when others
/// talk, and the last 5 minutes kept in memory open the recording. What
/// listens keeps no sound for the nudge; what is kept is in memory only,
/// and goes at every listed event.
enum ForkMeetingFinishDTests {
    static func run(_ suite: TestSuite) {
        gate(suite)
        gateKeepsNoSound(suite)
        meter(suite)
        nudges(suite)
        listening(suite)
        emptied(suite)
        ring(suite)
        handOver(suite)
        alignment(suite)
        machine(suite)
        texts(suite)
        sidecar(suite)
        soundOnlyMeeting(suite)
        fileTime(suite)
        offersSilenced(suite)
        island(suite)
    }

    private static let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private static let meetA = ForkMeetingIdentity("meet:abc-defg-hij")
    private static let meetB = ForkMeetingIdentity("meet:xyz-qrst-uvw")

    private static func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    // MARK: - The gate

    /// Talk: loud syllables and short drops, voiced and hissed sounds.
    private static func speechFrame(_ index: Int) -> ForkMeetingFrameMeter.Frame {
        let syllable = [3e-3, 1e-2, 2e-4, 6e-3, 1e-4][index % 5] as Float
        let crossings = [40, 60, 300, 50, 420][index % 5]
        return .init(energy: syllable, crossings: crossings)
    }

    /// Music: a steady level and steady crossings.
    private static func musicFrame(_ index: Int) -> ForkMeetingFrameMeter.Frame {
        .init(energy: index % 2 == 0 ? 4e-3 : 3e-3, crossings: index % 2 == 0 ? 100 : 110)
    }

    private static func gate(_ suite: TestSuite) {
        var talk = ForkMeetingVoiceGate()
        for index in 0..<40 { talk.add(speechFrame(index)) }
        suite.expect(!talk.hearsSpeech && abs(talk.speechSeconds - 2) < 0.01,
                     "two seconds of talk are not yet a meeting")
        for index in 40..<60 { talk.add(speechFrame(index)) }
        suite.expect(talk.hearsSpeech && abs(talk.speechSeconds - 3) < 0.01, "three seconds of talk in ten are")

        var music = ForkMeetingVoiceGate()
        for index in 0..<2_000 { music.add(musicFrame(index)) }
        suite.expect(!music.hearsSpeech && music.speechSeconds == 0, "music, however long, is never talk")

        var quiet = ForkMeetingVoiceGate()
        for index in 0..<400 { quiet.add(.init(energy: 1e-7, crossings: index % 2 == 0 ? 10 : 400)) }
        suite.expect(quiet.speechSeconds == 0, "a call's comfort noise is never talk")

        var faded = ForkMeetingVoiceGate()
        for index in 0..<100 { faded.add(speechFrame(index)) }
        for index in 0..<200 { faded.add(musicFrame(index)) }
        suite.expect(!faded.hearsSpeech, "only the last ten seconds count")
        faded.reset()
        suite.expect(faded.count == 0 && faded.speechSeconds == 0, "a reset forgets everything")
    }

    /// Privacy: the level tap keeps two numbers per 50 ms for the last 10 s,
    /// nothing else, whatever it heard.
    private static func gateKeepsNoSound(_ suite: TestSuite) {
        var gate = ForkMeetingVoiceGate()
        for index in 0..<72_000 { gate.add(speechFrame(index)) }
        let stored = Mirror(reflecting: gate).children.map { child -> Int in
            if let values = child.value as? [Float] { return values.count }
            return child.value is Int ? 0 : -1_000_000
        }
        suite.expect(stored.reduce(0, +) == 2 * ForkMeetingVoiceGate.windowFrames && stored.count == 3,
                     "after an hour of sound the gate still holds 400 numbers (energy and crossings), no sample")
    }

    private static func meter(_ suite: TestSuite) {
        var meter = ForkMeetingFrameMeter(sampleRate: 48_000)
        let tone = (0..<4_800).map { index in Float(index % 2 == 0 ? 0.5 : -0.5) }
        let frames = tone.withUnsafeBufferPointer { meter.take($0) }
        suite.expect(meter.frameLength == 2_400 && frames.count == 2
                        && frames.allSatisfy { abs($0.energy - 0.25) < 1e-6 && $0.crossings == 2_399 },
                     "50 ms frames at 48 kHz: their energy and their sign changes")
        let half = [Float](repeating: 0.1, count: 1_200)
        suite.expect(half.withUnsafeBufferPointer { meter.take($0) }.isEmpty, "a frame waits for its 50 ms")
    }

    // MARK: - When the offer comes back

    private static func nudges(_ suite: TestSuite) {
        var plan = ForkMeetingNudgePlan()
        let closed = plan.second(meeting: meetA, source: .app, speaking: true, microphoneOpen: false)
        suite.expect(!closed.nudge, "voices with the person's microphone closed are not their meeting yet")
        let first = plan.second(meeting: meetA, source: .app, speaking: true, microphoneOpen: true)
        suite.expect(first.nudge && !first.last, "others talking, microphone open: the offer comes back")
        var seconds = 0
        var last = (nudge: false, last: false)
        while !last.nudge, seconds < 1_000 {
            seconds += 1
            last = plan.second(meeting: meetA, source: .app, speaking: true, microphoneOpen: true)
        }
        suite.expect(last.nudge && last.last && seconds == 120,
                     "then a last time after 2 minutes of conversation")
        var call = ForkMeetingNudgePlan()
        _ = call.second(meeting: meetA, source: .app, speaking: true, microphoneOpen: true)
        var elapsed = 0
        var lastOne = (nudge: false, last: false)
        while !lastOne.nudge, elapsed < 1_000 {
            elapsed += 1
            // The others talk one second in three; the person's microphone stays open.
            lastOne = call.second(meeting: meetA, source: .app, speaking: elapsed % 3 == 0, microphoneOpen: true)
        }
        suite.expect(lastOne.last && elapsed == 120,
                     "the 2 minutes are the call's, the person's own turns included, and it comes while someone talks")
        let more = (0..<600).contains { _ in plan.second(meeting: meetA, source: .app, speaking: true,
                                                         microphoneOpen: true).nudge }
        suite.expect(!more && !plan.wantsMore(for: meetA), "never a third time")
        suite.expect(plan.second(meeting: meetB, source: .app, speaking: true, microphoneOpen: true).nudge
                        && plan.wantsMore(for: meetB),
                     "another meeting starts anew")

        var silent = ForkMeetingNudgePlan()
        let quiet = (0..<600).contains { _ in silent.second(meeting: meetA, source: .app, speaking: false,
                                                            microphoneOpen: true).nudge }
        suite.expect(!quiet, "nobody talking, nothing comes back")

        var microphone = ForkMeetingNudgePlan()
        var talk = 0
        while !microphone.second(meeting: meetA, source: .microphone, speaking: true, microphoneOpen: true).nudge,
              talk < 1_000 { talk += 1 }
        suite.expect(talk + 1 == 60, "without the system audio permission, after a minute of talk on the microphone")
        microphone.forget()
        suite.expect(microphone == ForkMeetingNudgePlan(), "an offer gone forgets its nudges")
    }

    // MARK: - What listens

    private static func facts(_ change: (inout ForkMeetingListenPlan.Facts) -> Void = { _ in })
        -> ForkMeetingListenPlan.Facts {
        var facts = ForkMeetingListenPlan.Facts(nudgeOn: true, lookbackOn: false, meeting: meetA, nudgesLeft: true,
                                                systemAudio: true, microphoneAllowed: true)
        change(&facts)
        return facts
    }

    private static func listening(_ suite: TestSuite) {
        let plain = ForkMeetingListenPlan.plan(facts())
        suite.expect(plain.app && !plain.microphone && !plain.keeps,
                     "by default only the meeting app's level is listened to: no microphone, nothing kept")
        suite.expect(!ForkMeetingListenPlan.plan(facts { $0.meeting = nil }).listens,
                     "no offer waiting for an answer, nothing listens")
        let noTap = ForkMeetingListenPlan.plan(facts { $0.systemAudio = false })
        suite.expect(!noTap.app && noTap.microphone,
                     "never a tap before system audio is proven allowed (macOS would ask mid-call): the microphone instead")
        suite.expect(!ForkMeetingListenPlan.plan(facts { $0.systemAudio = false; $0.microphoneAllowed = false }).listens,
                     "nothing allowed, nothing asked, nothing listens")
        suite.expect(!ForkMeetingListenPlan.plan(facts { $0.nudgeOn = false }).listens
                        && !ForkMeetingListenPlan.plan(facts { $0.nudgesLeft = false }).listens,
                     "the nudge off, or both nudges given, and the lookback off: nothing listens")
        let keeping = ForkMeetingListenPlan.plan(facts { $0.lookbackOn = true; $0.nudgeOn = false })
        suite.expect(keeping.app && keeping.microphone && keeping.keeps,
                     "the last 5 minutes on: the app's sound and the microphone are kept")
        suite.expect(ForkMeetingDefaultsCheck.lookbackOffByDefault && ForkMeetingDefaultsCheck.nudgeOnByDefault,
                     "the nudge is on by default, the last 5 minutes off")
    }

    /// Privacy: the kept sound goes at each listed event.
    private static func emptied(_ suite: TestSuite) {
        let kept = facts { $0.lookbackOn = true }
        let events: [(String, ForkMeetingListenPlan.Facts)] = [
            ("the call ends (no offer)", facts { $0.lookbackOn = true; $0.meeting = nil }),
            ("Not now (no offer)", facts { $0.lookbackOn = true; $0.meeting = nil }),
            ("Never (no offer)", facts { $0.lookbackOn = true; $0.meeting = nil }),
            ("the screen locks", facts { $0.lookbackOn = true; $0.locked = true }),
            ("the Mac sleeps", facts { $0.lookbackOn = true; $0.asleep = true }),
            ("the feature is turned off (no offer)", facts { $0.lookbackOn = true; $0.meeting = nil }),
            ("the setting is turned off", facts { $0.lookbackOn = false }),
            ("the app quits", facts { $0.lookbackOn = true; $0.terminating = true }),
            ("another meeting is offered", facts { $0.lookbackOn = true; $0.meeting = meetB }),
        ]
        let kept1 = events.filter { !ForkMeetingListenPlan.clears(from: kept, to: $0.1) }.map(\.0)
        suite.expect(kept1.isEmpty, "the kept sound is emptied at every listed event: \(kept1)")
        suite.expect(!ForkMeetingListenPlan.clears(from: kept, to: kept)
                        && !ForkMeetingListenPlan.clears(from: kept, to: facts { $0.lookbackOn = true; $0.nudgeOn = false }),
                     "and kept otherwise, the nudge on or off")
        suite.expect(!ForkMeetingListenPlan.plan(facts { $0.lookbackOn = true; $0.locked = true }).listens
                        && !ForkMeetingListenPlan.plan(facts { $0.lookbackOn = true; $0.asleep = true }).listens,
                     "nothing listens on a locked screen or in sleep")
    }

    // MARK: - The ring

    private static func samples(_ count: Int, _ value: Float = 0.25) -> [Float] {
        [Float](repeating: value, count: count)
    }

    private static func ring(_ suite: TestSuite) {
        let empty = ForkMeetingLookbackRing()
        suite.expect(empty.bytesHeld == 0 && empty.span == nil, "nothing kept, no memory taken")

        let ring = ForkMeetingLookbackRing(seconds: 300)
        let second = samples(16_000)
        for index in 0..<360 { second.withUnsafeBufferPointer { ring.append($0, startHost: 1_000 + Double(index)) } }
        suite.expect(ring.storedSeconds == 300 && ring.bytesHeld == 300 * 16_000 * 2,
                     "6 minutes heard, 5 kept: 9.6 MB, 16-bit, 16 kHz, never more")
        suite.expect(ring.span.map { abs($0.start - 1_060) < 1e-6 && abs($0.end - 1_360) < 1e-6 } == true,
                     "the newest 5 minutes, on the host clock")

        let gaps = ForkMeetingLookbackRing(seconds: 10)
        second.withUnsafeBufferPointer { gaps.append($0, startHost: 0) }
        second.withUnsafeBufferPointer { gaps.append($0, startHost: 2) }
        let read = gaps.read(from: 0, count: 48_000)
        suite.expect(read[15_999] > 0.2 && read[16_000] == 0 && read[31_999] == 0 && read[32_000] > 0.2
                        && gaps.storedSeconds == 3,
                     "a source silent for a second leaves a second of silence: what follows stays in time")
        let overlap = ForkMeetingLookbackRing(seconds: 10)
        second.withUnsafeBufferPointer { overlap.append($0, startHost: 0) }
        samples(16_000, 0.5).withUnsafeBufferPointer { overlap.append($0, startHost: 0.5) }
        suite.expect(abs(overlap.storedSeconds - 1.5) < 1e-6 && overlap.read(from: 1.2, count: 1)[0] > 0.4,
                     "a buffer overlapping the last one is not counted twice")

        ring.clear()
        suite.expect(ring.bytesHeld == 0 && ring.span == nil && ring.storedSeconds == 0
                        && ring.read(from: 1_100, count: 10).allSatisfy { $0 == 0 },
                     "emptied: zeros first, then its memory let go")
        ring.freeze()
        second.withUnsafeBufferPointer { ring.append($0, startHost: 5_000) }
        suite.expect(ring.storedSeconds == 0, "frozen, it takes nothing more")
    }

    private static func handOver(_ suite: TestSuite) {
        let ring = ForkMeetingLookbackRing(seconds: 10)
        samples(32_000).withUnsafeBufferPointer { ring.append($0, startHost: 100) }
        let taken = ring.handOver()
        suite.expect(taken.storedSeconds == 2 && taken.span?.end == 102 && ring.bytesHeld == 0 && ring.span == nil,
                     "a recording takes the kept sound whole; the offer's ring is left empty")
        samples(16_000).withUnsafeBufferPointer { ring.append($0, startHost: 102) }
        ring.clear()
        suite.expect(ring.storedSeconds == 0 && taken.storedSeconds == 2,
                     "and emptying the offer's ring never touches what the recording took")
        taken.clear()
        suite.expect(taken.bytesHeld == 0, "which the file empties once written")
    }

    /// The two tracks start together at the file's zero, each sample at
    /// its host time.
    private static func alignment(_ suite: TestSuite) {
        let plan = ForkMeetingLookbackPlan.plan(spans: [(start: 700, end: 1_000.4), (start: 820, end: 999.9)], zero: 1_000)
        let close = { (a: Double, b: Double) in abs(a - b) < 1e-6 }
        suite.expect(plan.map { plan in
                         plan.seconds == 300 && plan.tracks.count == 2
                             && plan.tracks[0] == .init(silence: 0, from: 700, seconds: 300)
                             && close(plan.tracks[1].silence, 120) && plan.tracks[1].from == 820
                             && close(plan.tracks[1].seconds, 179.9)
                     } == true,
                     "5 minutes at most; the track that kept less opens with silence, and stops where it stopped")
        let capped = ForkMeetingLookbackPlan.plan(spans: [(start: 0, end: 1_000), nil], zero: 1_000)
        suite.expect(capped?.seconds == 300 && capped?.tracks[1] == .init(silence: 300, from: 1_000, seconds: 0),
                     "never more than 5 minutes; a track that kept nothing is silence")
        suite.expect(ForkMeetingLookbackPlan.plan(spans: [(start: 999.5, end: 1_000), nil], zero: 1_000) == nil
                        && ForkMeetingLookbackPlan.plan(spans: [nil, nil], zero: 1_000) == nil,
                     "under a second, or nothing kept: the file starts at the click, as without it")

        // A click 3.25 s into a ring read back: it lands on its sample.
        let ring = ForkMeetingLookbackRing(seconds: 10)
        var sound = samples(16_000 * 5, 0)
        sound[52_000] = 1
        sound.withUnsafeBufferPointer { ring.append($0, startHost: 50) }
        let back = ring.read(from: 50, count: 16_000 * 5)
        suite.expect(back.firstIndex { $0 > 0.5 } == 52_000, "a sample read back sits at its host time, to the sample")
    }

    // MARK: - The machine

    private static func candidate(_ identity: ForkMeetingIdentity = meetA) -> ForkMeetingCandidate {
        ForkMeetingCandidate(identity: identity, provider: "meet", providerName: "Google Meet", providerShortName: "Meet",
                             titleName: "Point hebdo", meetCode: String(identity.value.dropFirst(5)), calendarTitle: nil,
                             appBundle: "com.google.Chrome", pid: 100, windowID: 1, windowBundle: "com.google.Chrome",
                             defaultSound: .app, policy: .ask, silenced: false, bornAt: t0, alwaysProof: .meetCode)
    }

    private static func offering(blocked: Bool = false) -> ForkMeetingMachine {
        var machine = ForkMeetingMachine()
        let facts = ForkMeetingStartFacts(freeBytes: blocked ? 0 : 50_000_000_000, screenRecordingAllowed: true,
                                          microphoneAllowed: true, officialRecorderBusy: false)
        let settings = ForkMeetingCaptureSettings(target: .window, systemAudio: .app, microphone: "meeting",
                                                  quality: .standard)
        machine.handle(.candidates([candidate()], ForkMeetingStartRequest(settings: settings, facts: facts)), now: at(0))
        machine.handle(.tick, now: at(21))
        return machine
    }

    private static func machine(_ suite: TestSuite) {
        var machine = offering()
        guard case let .offering(folded) = machine.phase, folded.collapsed else {
            return suite.expect(false, "the offer folds after 20 s")
        }
        let effects = machine.handle(.nudge(meetA), now: at(90))
        var raised = folded
        raised.collapsed = false
        raised.collapsesAt = at(110)
        suite.expect(effects == [.nudgeOffer(raised), .announce(.nudged("Point hebdo"))] && machine.phase == .offering(raised),
                     "a nudge opens the folded offer again, said to VoiceOver, and it folds back 20 s later")
        suite.expect(machine.handle(.tick, now: at(109)).isEmpty && machine.handle(.tick, now: at(110)) == [.collapseOffer],
                     "left alone, it folds back")
        suite.expect(machine.handle(.nudge(meetB), now: at(120)).isEmpty, "another meeting's nudge raises nothing")
        var blocked = offering(blocked: true)
        suite.expect(blocked.handle(.nudge(meetA), now: at(90)).isEmpty, "a greyed offer, which could not record, is not raised")
        var idle = ForkMeetingMachine()
        suite.expect(idle.handle(.nudge(meetA), now: at(5)).isEmpty && idle.phase == .idle,
                     "with no offer (Not now, Never, the call over), a nudge does nothing")
        var dismissed = offering()
        dismissed.handle(.dismiss(.thisTime), now: at(30))
        suite.expect(dismissed.handle(.nudge(meetA), now: at(90)).isEmpty, "after Not now, never")
    }

    // MARK: - Words

    private static func texts(_ suite: TestSuite) {
        let english = ForkMeetingStrings.strings(.enUS), french = ForkMeetingStrings.strings(.fr)
        suite.expect(ForkMeetingLookbackText.kept(since: at(0), now: at(252), strings: english) == "+4 min 12 s already kept"
                        && ForkMeetingLookbackText.kept(since: at(0), now: at(45), strings: english) == "+45 s already kept"
                        && ForkMeetingLookbackText.kept(since: at(0), now: at(4_000), strings: english) == "+5 min already kept",
                     "the kept sound, as the offer counts it, never more than 5 minutes")
        suite.expect(ForkMeetingLookbackText.kept(since: at(0), now: at(252), strings: french)
                        == "+4\u{00A0}min 12\u{00A0}s déjà gardées",
                     "in French too")
        suite.expect(ForkMeetingLookbackText.soundOnly(seconds: 252, strings: french)
                        == "Les 4 premières minutes\u{00A0}: son seulement"
                        && ForkMeetingLookbackText.soundOnly(seconds: 40, strings: french)
                        == "La première minute\u{00A0}: son seulement",
                     "the detail says how the file begins, to the nearest minute")
        suite.expect(french.nudgeTitle == "Ça a commencé · Enregistrer\u{00A0}?"
                        && ForkMeetingAnnouncement.nudged("Point hebdo").text(english)
                        == "Point hebdo has started. Do you want to record it?",
                     "the offer back says it started, and VoiceOver with its name")
        var tooLong: [String] = []
        for language in AppLanguage.allCases {
            let s = ForkMeetingStrings.strings(language)
            for short in [s.nudgeTitle, ForkMeetingLookbackText.kept(since: at(0), now: at(299), strings: s)]
            where short.count > 30 { tooLong.append("\(language.rawValue): \(short)") }
        }
        suite.expect(tooLong.isEmpty, "the island's words stay short in every language: \(tooLong)")
    }

    private static func sidecar(_ suite: TestSuite) {
        var meeting = ForkMeetingSidecar.started(id: UUID(), startedAt: t0, origin: .offered, title: "Point hebdo",
                                                 titleSource: .window,
                                                 capture: .init(target: .window, systemAudio: .app, microphone: "AirPods",
                                                                quality: .standard))
        meeting = ForkMeetingSidecarPatch(gap: .init(at: 0, seconds: 252, kind: .lookback)).applied(to: meeting)
        let data = (try? meeting.encoded()) ?? Data()
        guard case let .success(back) = ForkMeetingSidecar.decode(data) else {
            return suite.expect(false, "meeting.json reads back")
        }
        suite.expect(String(decoding: data, as: UTF8.self).contains("\"lookback\"")
                        && back.gaps == [.init(at: 0, seconds: 252, kind: .lookback)],
                     "meeting.json says the file opens on 252 s of sound only")
        var contents = ForkMeetingFolder.Contents()
        contents.hasSidecar = true
        contents.video = "Point hebdo.mp4"
        let entry = ForkMeetingLibraryEntry(folderName: "2026-10-19 10h00 — Point hebdo", sidecar: .success(back),
                                            contents: contents)
        suite.expect(entry?.soundOnlySeconds == 252, "and the library's detail reads it")
    }

    // MARK: - The island (Finish A)

    /// The nudge lives in the offer's card: no live activity is ever shown
    /// beside it (nothing records while an offer waits), the island's own
    /// spring brings it in, Reduce Motion stills it, VoiceOver reads it.
    private static func island(_ suite: TestSuite) {
        var machine = offering()
        let effects = machine.handle(.nudge(meetA), now: at(90))
        let pills = effects.filter { if case .showPill = $0 { return true }; return false }
        suite.expect(pills.isEmpty && !ForkMeetingIslandRules.showsStrip(enabled: true, indicator: .both, state: .hidden),
                     "a nudge shows no pill and no strip: the offer waits, nothing records")
        suite.expect(ForkMeetingAttentionStyle.style(inIsland: true, reduceMotion: false)
                        == .init(springs: false, pulses: true, arrowMoves: true)
                        && ForkMeetingAttentionStyle.style(inIsland: false, reduceMotion: false)
                        == .init(springs: true, pulses: true, arrowMoves: true),
                     "in the island the card comes with the island's spring, its ring pulsing; in the bubble it springs itself")
        suite.expect(ForkMeetingAttentionStyle.style(inIsland: true, reduceMotion: true) == .init()
                        && ForkMeetingAttentionStyle.style(inIsland: false, reduceMotion: true) == .init(),
                     "with Reduce Motion nothing moves: the ring is simply lit")
        let english = ForkMeetingStrings.strings(.enUS)
        let spoken = ForkMeetingLookbackText.spokenKept(since: at(0), now: at(252), strings: english, language: .enUS)
        let drawn = ForkMeetingLookbackText.kept(since: at(0), now: at(252), strings: english)
        suite.expect(spoken.hasPrefix("+") && spoken.hasSuffix("already kept") && spoken.contains("4")
                        && spoken.contains("12") && spoken != drawn
                        && ForkMeetingLookbackText.spokenKept(since: at(0), now: at(4_000), strings: english, language: .enUS)
                        .contains("5"),
                     "VoiceOver reads the kept time in its words (\(spoken)), never more than 5 minutes")
        suite.expect(AppLanguage.allCases.allSatisfy { language in
                        let s = ForkMeetingStrings.strings(language)
                        return !ForkMeetingLookbackText.spokenKept(since: at(0), now: at(252), strings: s, language: language)
                            .isEmpty
                     }, "in every language")
    }

    // MARK: - The notification switches (Finish B)

    /// The nudge is an offer again, and the kept sound is said only on the
    /// offer's card: with the offers silenced, nothing listens, nothing is
    /// kept, and what was kept goes.
    private static func offersSilenced(_ suite: TestSuite) {
        let silenced = ForkMeetingListenPlan.plan(facts { $0.offersShown = false })
        let keepingSilenced = ForkMeetingListenPlan.plan(facts { $0.offersShown = false; $0.lookbackOn = true })
        suite.expect(!silenced.listens && !keepingSilenced.listens && !keepingSilenced.keeps,
                     "offers silenced: no nudge, nothing listens, nothing kept, the last 5 minutes on or not")
        suite.expect(ForkMeetingListenPlan.clears(from: facts { $0.lookbackOn = true },
                                                  to: facts { $0.lookbackOn = true; $0.offersShown = false }),
                     "silencing the offers while sound is kept empties it")
        suite.expect(ForkMeetingListenPlan.Facts().offersShown && ForkMeetingNotifyEvent.isOn(.offers, defaults: freshDefaults()),
                     "the offers' word is on by default, and so the nudge")
        var wrong: [String] = []
        for language in AppLanguage.allCases {
            let s = ForkMeetingStrings.strings(language)
            if s.nudgeOffersOff.isEmpty || !s.nudgeOffersOff.contains(s.notifyTitle) { wrong.append(language.rawValue) }
        }
        suite.expect(wrong.isEmpty, "under the nudge, the page names the section where the offers were silenced: \(wrong)")
    }

    private static func freshDefaults() -> UserDefaults {
        let name = "fork.tests.finish-d.offers"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    // MARK: - Markers and the transcript (Finish E)

    /// The kept minutes are the file's first: the meeting's clock starts
    /// with them, so a ★ pressed after the click, the transcript's lines and
    /// the `.srt` the review plays from are all in the same file time.
    private static func fileTime(_ suite: TestSuite) {
        var machine = ForkMeetingMachine()
        let facts = ForkMeetingStartFacts(freeBytes: 50_000_000_000, screenRecordingAllowed: true,
                                          microphoneAllowed: true, officialRecorderBusy: false)
        let settings = ForkMeetingCaptureSettings(target: .window, systemAudio: .app, microphone: "meeting",
                                                  quality: .standard)
        machine.handle(.manualStart(.init(settings: settings, facts: facts)), now: at(0))
        guard case let .starting(pending) = machine.phase else { return suite.expect(false, "the recording starts") }
        // The engine answers that the file's zero came 252 s before the
        // click: the kept sound opens it.
        machine.handle(.captureStarted(pending.token, folder: URL(fileURLWithPath: "/tmp/Meetings/Point hebdo"),
                                       target: .window, startedAt: at(1 - 252)), now: at(1))
        let early = machine.activeSession.map { $0.recorded(at: at(31)) }
        machine.handle(.pause, now: at(41))
        machine.handle(.resume, now: at(61))
        let late = machine.activeSession.map { $0.recorded(at: at(71)) }
        suite.expect(early == 282 && late == 302,
                     "the meeting's clock counts the kept 252 s, then the time since the click, pauses left out")
        let marker = ForkMeetingMarkers.time(recorded: late ?? 0)
        suite.expect(marker == 302 && ForkMeetingMarkers.clock(marker) == "00:05:02",
                     "a ★ pressed 50 s after the click (20 s of them paused) is at 5:02 of the file")

        // Heard before the click (1:40, in the kept sound) and after it.
        let word = { (text: String, start: Double) in
            ForkParakeetWord(text: text, start: start, end: start + 1, confidence: 0.9)
        }
        let document = ForkMeetingTranscriptFormat.document(
            me: [word("Bonjour.", 100), word("On commence.", 300)],
            participants: [word("Oui.", 120), word("Allons-y.", 305)],
            microEnvelope: nil, meetingEnvelope: nil, label: { $0 == .me ? "Moi : " : "Eux : " }, markers: [marker])
        suite.expect(document.text == """
                        [00:01:40] Moi : Bonjour.

                        [00:02:00] Eux : Oui.

                        [00:05:00] Moi : On commence.

                        ★ [00:05:02]

                        [00:05:05] Eux : Allons-y.

                        """,
                     "the transcript writes the kept minutes' words at their file time, the ★ between the lines around it")
        let cues = ForkMeetingPlayback.cues(srt: document.srt)
        let rows = ForkMeetingPlayback.rows(cues: cues, markers: [marker])
        suite.expect(cues.map(\.start) == [100, 120, 300, 305] && rows.map(\.time) == [100, 120, 300, 302, 305]
                        && ForkMeetingPlayback.current(rows, at: 306).map { rows[$0].time } == 305
                        && ForkMeetingPlayback.current(rows, at: 101).map { rows[$0].time } == 100
                        && ForkMeetingMarkers.playFrom(marker) == 299,
                     "the review lines the .srt and the ★ up in file time, the kept minutes' lines lit as they play")
        suite.expect(ForkMeetingMarkers.fraction(marker, duration: 252 + 70 - 20) == marker / 302,
                     "and the player's strip places the ★ on the whole file, kept minutes included")
    }

    // MARK: - With sound only (Finish C)

    /// A meeting recorded as sound only, opened by 252 s kept before the
    /// click: its `.m4a` has no picture at all, so the detail never speaks
    /// of a picture missing; it says where those minutes come from.
    private static func soundOnlyMeeting(_ suite: TestSuite) {
        let name = "2026-10-19 10h00 — Point hebdo"
        var meeting = ForkMeetingSidecar.started(id: UUID(), startedAt: t0, origin: .offered, title: "Point hebdo",
                                                 titleSource: .window,
                                                 capture: .init(target: .audioOnly, systemAudio: .app,
                                                                microphone: "AirPods", quality: .standard))
        meeting = ForkMeetingSidecarPatch(gap: .init(at: 0, seconds: 252, kind: .lookback)).applied(to: meeting)
        meeting.state = .complete
        meeting.recordedSeconds = 262
        let contents = ForkMeetingFolder.contents(of: ["\(name).m4a", ForkMeetingFolder.sidecarName], folderName: name)
        let entry = ForkMeetingLibraryEntry(folderName: name, sidecar: .success(meeting), contents: contents)
        suite.expect(entry?.isAudioOnly == true && entry?.playable == "\(name).m4a" && entry?.status == .complete
                        && entry?.soundOnlySeconds == 252,
                     "sound only and opened by the kept minutes: it plays its .m4a, complete, and knows how it opens")
        let english = ForkMeetingStrings.strings(.enUS), french = ForkMeetingStrings.strings(.fr)
        suite.expect(ForkMeetingLookbackText.opening(seconds: 252, audioOnly: true, strings: english)
                        == "The first 4 minutes: kept from before the click"
                        && ForkMeetingLookbackText.opening(seconds: 40, audioOnly: true, strings: french)
                        == "La première minute\u{00A0}: gardée avant le clic"
                        && ForkMeetingLookbackText.opening(seconds: 252, audioOnly: false, strings: english)
                        == ForkMeetingLookbackText.soundOnly(seconds: 252, strings: english),
                     "without picture the detail says the first minutes come from before the click; a video's still says sound only")
        var wrong: [String] = []
        for language in AppLanguage.allCases {
            let s = ForkMeetingStrings.strings(language)
            let one = ForkMeetingLookbackText.opening(seconds: 30, audioOnly: true, strings: s)
            let four = ForkMeetingLookbackText.opening(seconds: 252, audioOnly: true, strings: s)
            if !four.contains("4") || one == four || one == s.lookbackSoundOnlyOne
                || four == ForkMeetingLookbackText.soundOnly(seconds: 252, strings: s) { wrong.append(language.rawValue) }
        }
        suite.expect(wrong.isEmpty, "in every language, its own words with the minutes: \(wrong)")

        // Killed while recording: the kept minutes are the file's own, the
        // recovery measures them in its length and leaves the gap alone.
        var crashed = meeting
        crashed.state = .recording
        crashed.recordedSeconds = 252
        let facts = ForkMeetingRecoveryPlan.Facts(sidecar: .success(crashed), master: .init(duration: 300))
        let action = ForkMeetingRecoveryPlan.plan(facts)
        let patch = ForkMeetingRecoveryPlan.patch(for: action, facts: facts)
        let recovered = patch.map { $0.applied(to: crashed) }
        suite.expect(action == .finalize(stopReason: .crash, recovered: true, discardDrafts: false)
                        && recovered?.recordedSeconds == 300 && recovered?.gaps == crashed.gaps
                        && recovered?.isAudioOnly == true,
                     "recovered, its .m4a is finalized again with the kept minutes counted and still said")
        suite.expect(ForkMeetingTranscript.source(video: contents.media(audioOnly: true), hasMaster: false) == "\(name).m4a",
                     "and it is transcribed from its .m4a, whose time starts with the kept minutes")
    }
}

/// The two settings' defaults, as registered.
private enum ForkMeetingDefaultsCheck {
    static var nudgeOnByDefault: Bool { ForkDefaults.registered[ForkDefaultsKey.meetingsNudge] as? Bool == true }
    static var lookbackOffByDefault: Bool { ForkDefaults.registered[ForkDefaultsKey.meetingsLookback] as? Bool == false }
}
