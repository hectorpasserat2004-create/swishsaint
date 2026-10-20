// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// Crash audit of the fork: the final pass's stall watch against its end,
/// and the inputs that used to trap (empty echo slices, NaN durations).
enum ForkMeetingPassFlowTests {
    static func run(_ suite: TestSuite) {
        flow(suite)
        race(suite)
        finalizerSource(suite)
        traps(suite)
    }

    private static let second: UInt64 = 1_000_000_000

    private static func flow(_ suite: TestSuite) {
        let done = ForkMeetingPassFlow(now: 0)
        suite.expect(!done.complete(), "a pass that ends before any stall is not stalled")
        suite.expect(!done.stallIfSilent(for: 120, now: 500 * second) && !done.isStalled,
                     "once completed, the stall watch can no longer cancel the writer")

        let silent = ForkMeetingPassFlow(now: 0)
        var released = 0
        silent.onStall { released += 1 }
        suite.expect(!silent.stallIfSilent(for: 120, now: 119 * second), "119 s of silence is no stall")
        silent.moved(now: 100 * second)
        suite.expect(!silent.stallIfSilent(for: 120, now: 219 * second), "a sample that moved restarts the wait")
        suite.expect(silent.stallIfSilent(for: 120, now: 220 * second) && released == 1,
                     "120 s without a sample stalls and releases every pump")
        suite.expect(!silent.stallIfSilent(for: 120, now: 900 * second) && released == 1, "a stall happens once")
        suite.expect(silent.complete(), "a pass stalled before its end says so: the writer is not finished")

        let clock = ForkMeetingPassFlow(now: 50 * second)
        suite.expect(!clock.stallIfSilent(for: 0.5, now: 10 * second), "a clock read before the last move never traps")
    }

    /// The watch and the end, racing: exactly one of them wins, every time.
    private static func race(_ suite: TestSuite) {
        var disagreements = 0, stalls = 0
        let rounds = 2_000
        for _ in 0..<rounds {
            let flow = ForkMeetingPassFlow(now: 0)
            let group = DispatchGroup()
            let lock = NSLock()
            var watched = false
            DispatchQueue.global().async(group: group) {
                let stalled = flow.stallIfSilent(for: 0, now: second)
                lock.withLock { watched = stalled }
            }
            let ended = flow.complete()
            group.wait()
            let stalled = lock.withLock { watched }
            if stalled != ended { disagreements += 1 }
            if stalled { stalls += 1 }
        }
        suite.expect(disagreements == 0,
                     "the end and the stall exclude each other (\(stalls) stalls first in \(rounds) races, "
                        + "\(disagreements) disagreements)")
    }

    private static func finalizerSource(_ suite: TestSuite) {
        let finalizer = ForkMeetingFinalizeTests.source("Sources/Vorssaint/Fork/Meetings/ForkMeetingFinalizer.swift")
        suite.expect(finalizer.contains("return flow.complete()") && !finalizer.contains("return flow.isStalled"),
                     "the pump reports a stall under the same lock that ends the pass")
        let backstop = "guard writer.status == .writing else { throw PassError.notWriting(writer) }"
        suite.expect(finalizer.components(separatedBy: backstop).count == 3,
                     "endSession and the M4A's finishWriting are never called on a writer no longer writing")
        if let end = finalizer.range(of: "writer.endSession(atSourceTime: duration)"),
           let guardAt = finalizer.range(of: backstop) {
            suite.expect(guardAt.lowerBound < end.lowerBound, "the backstop comes before endSession")
        }
    }

    private static func traps(_ suite: TestSuite) {
        typealias Listing = ForkDictationHistoryListing
        suite.expect(Listing.duration(.nan) == "0:00" && Listing.duration(.infinity) == "0:00"
                        && Listing.duration(1e300) == "5999:59" && Listing.duration(61.4) == "1:01",
                     "a NaN, infinite or absurd duration reads without trapping")

        // Enough twin words for a gain, and no energy at all: no slice.
        var micro: [ForkParakeetWord] = [], meeting: [ForkParakeetWord] = []
        for index in 0..<30 {
            let at = Double(index) * 2
            meeting.append(ForkParakeetWord(text: "mot\(index)", start: at, end: at + 0.5, confidence: 0.9))
            micro.append(ForkParakeetWord(text: "mot\(index)", start: at + 0.12, end: at + 0.62, confidence: 0.9))
        }
        let report = ForkMeetingEcho.filter(micro: micro, meeting: meeting, microEnvelope: ForkMeetingEnvelope(),
                                            meetingEnvelope: ForkMeetingEnvelope())
        suite.expect(report.echo.isEmpty, "the echo filter on empty envelopes keeps every word, without trapping")
    }
}
