// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import CoreGraphics
import Foundation

/// Suite `fork-glance-trace` — A5: traces, replay and metrics (plan §12.11, §17.2).
enum ForkGlanceTraceTests {
    private typealias Machine = ForkGlanceMachineTests

    static func run(_ suite: TestSuite) {
        json(suite)
        replay(suite)
        bench(suite)
    }

    /// A seeded generator: the same trace on every run.
    private struct Noise {
        var state: UInt64
        mutating func uniform() -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(state >> 11) / Double(UInt64(1) << 53)
        }
        /// Roughly normal, σ = 1 (sum of uniforms).
        mutating func normal() -> Double {
            var sum = 0.0
            for _ in 0..<6 { sum += uniform() }
            return (sum - 3) * 2.0.squareRoot()
        }
    }

    private static let layout = ForkGlanceDisplayLayout(displays: [
        ForkGlanceDisplay(uuid: "LG", name: "LG HDR WQHD", frame: CGRect(x: 0, y: 0, width: 3440, height: 1440),
                          millimeters: CGSize(width: 816, height: 338)),
        ForkGlanceDisplay(uuid: "MAC", name: "Built-in Retina Display",
                          frame: CGRect(x: 938, y: 1440, width: 1728, height: 1117),
                          millimeters: CGSize(width: 344, height: 222), isBuiltIn: true, hasNotch: true),
    ])

    /// Where the head points, as a horizontal position on the LG, over time.
    private typealias Path = (TimeInterval) -> Double

    /// A head following `path` at 12 img/s with 60 pt of noise, blinking
    /// (one faceless image every 2.5 s, two every 6 s), typing in `typing`.
    private static func synthetic(duration: TimeInterval, path: Path, typing: [ClosedRange<TimeInterval>] = [],
                                  seed: UInt64 = 7) -> ForkGlanceTrace {
        var noise = Noise(state: seed)
        var frames: [ForkGlanceTrace.Frame] = []
        let count = Int(duration * 12)
        var lastKey = -60.0
        for index in 0..<count {
            let time = Double(index) / 12
            if typing.contains(where: { $0.contains(time) }) { lastKey = time }
            let x = path(time) + 60 * noise.normal()
            let blink = index % 30 == 7 || index % 72 == 40 || index % 72 == 41
            let target: ForkGlanceGazeTarget
            if blink {
                target = .noFace
            } else if x < 1620 {
                target = .zone(Machine.left)
            } else if x > 1820 {
                target = .zone(Machine.right)
            } else {
                target = .between
            }
            let estimate = ForkGlanceEstimate(point: CGPoint(x: x, y: 700), sigma: CGSize(width: 60, height: 60),
                                              time: time, confidence: blink ? 0 : 0.9)
            let speed = abs(path(time + 1.0 / 12) - path(time)) * 12 / 40
            let gaze = ForkGlanceGaze(estimate: blink ? nil : estimate, target: target, margin: blink ? 0 : 1.5,
                                      headSpeed: speed, confidence: blink ? 0 : 0.9, crowded: false)
            let sample = blink ? nil : ForkGlanceSample(time: time, vector: Array(repeating: x / 3440, count: 11),
                                                        confidence: 0.9, eyesUsable: true, facePresent: true)
            let input = ForkGlanceTrace.Input(Machine.hands(sinceKey: time - lastKey), neverLeaveApps: [])
            frames.append(ForkGlanceTrace.Frame(time: time, sample: sample, gaze: gaze, input: input, guards: []))
        }
        return ForkGlanceTrace(recorded: Date(timeIntervalSince1970: 1_792_000_000), appVersion: "1.0 (1)",
                               settings: Machine.settings(), layout: layout, layoutSignature: "LG+MAC",
                               usesEyes: false, zones: Machine.zones, initialZone: Machine.left, frames: frames)
    }

    /// Left, then right, a head turn taking 0.3 s at each `turns` time.
    private static func turning(_ turns: [TimeInterval]) -> Path {
        { time in
            var x = 860.0
            for (index, turn) in turns.enumerated() where time >= turn {
                let from = index % 2 == 0 ? 860.0 : 2580
                let to = index % 2 == 0 ? 2580.0 : 860
                x = from + (to - from) * min(1, (time - turn) / 0.3)
            }
            return x
        }
    }

    private static func json(_ suite: TestSuite) {
        var trace = synthetic(duration: 2, path: turning([1]))
        trace.marks = [
            .click(time: 0.5, point: CGPoint(x: 400, y: 300), zone: Machine.left),
            .focusChanged(time: 0.6, zone: Machine.left),
            .switched(time: 1.4, zone: Machine.right, succeeded: true),
            .zonesChanged(time: 1.5, zones: Machine.zones),
        ]
        trace.frames[3].gaze?.margin = .infinity
        trace.frames[4].guards = [.typing, .cooldown]
        do {
            let data = try ForkGlanceTrace.encode(trace)
            let decoded = try ForkGlanceTrace.decode(data)
            suite.expect(decoded == trace, "a trace survives the JSON round trip, marks and an infinite margin included")
            suite.expect(decoded.version == ForkGlanceTrace.currentVersion, "a trace carries its format version")
        } catch {
            suite.expect(false, "a trace encodes and decodes: \(error)")
        }

        let idle = ForkGlanceTrace.Input(.idle, neverLeaveApps: [])
        suite.expect(idle.sinceKey == ForkGlanceTrace.maxAge && idle.sincePointer == ForkGlanceTrace.maxAge,
                     "« never » input ages are capped, so the JSON holds no infinity")
        var keynote = ForkGlanceInputSnapshot.idle
        keynote.frontmostBundleID = "com.apple.Keynote"
        let excluded = ForkGlanceTrace.Input(keynote, neverLeaveApps: ["com.apple."])
        let kept = ForkGlanceTrace.Input(keynote, neverLeaveApps: [])
        suite.expect(excluded.excludedSource && !kept.excludedSource,
                     "the frontmost app is kept only as « in the never-leave list », prefixes included")
        suite.expect(excluded.snapshot.frontmostBundleID == ForkGlanceTrace.excludedMarker
                        && kept.snapshot.frontmostBundleID == nil,
                     "replayed, an excluded app stands as a marker")
        var redacted = synthetic(duration: 0.5, path: { _ in 860 })
        redacted.frames[0].input = excluded
        let text = (try? ForkGlanceTrace.encode(redacted)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        suite.expect(!text.isEmpty && !text.contains("Keynote"), "no app id reaches the exported JSON")

        suite.expect((try? ForkGlanceTrace.decode(Data("{\"version\": 1}".utf8))) == nil,
                     "a truncated trace is refused, not half read")
    }

    private static func replay(_ suite: TestSuite) {
        // Turns at 3, 6, 9 (while typing from 8 to 10) and 14 s.
        let trace = synthetic(duration: 17, path: turning([3, 6, 9, 14]), typing: [8...10])
        let settings = Machine.settings()
        let metrics = ForkGlanceTrace.replay(trace, settings: settings)
        suite.expect(metrics == ForkGlanceTrace.replay(trace, settings: settings),
                     "the replay is deterministic")
        suite.expect(metrics.switches == 4,
                     "a head turning four times, with noise and blinks, switches four times: got \(metrics.switches)")
        suite.expect(metrics.quickReversals == 0, "deliberate turns are not counted as reversals")
        let latency = metrics.meanLatency ?? -1
        suite.expect(latency >= 0.1 && latency <= 0.32,
                     "the latency stays near the 200 ms dwell, the typing wait aside: got \(latency)")
        suite.expect(metrics.blockedShare > 0.15 && metrics.blockedShare < 0.3,
                     "typing for 2 s (+1.5 s pause) blocks about a fifth of 17 s: got \(metrics.blockedShare)")

        let calm = ForkGlanceTrace.replay(synthetic(duration: 17, path: turning([3, 6, 9, 14])), settings: settings)
        suite.expect(calm.blockedShare == 0 && calm.switches == 4, "without typing, nothing blocks")

        if let data = try? ForkGlanceTrace.encode(trace), let decoded = try? ForkGlanceTrace.decode(data) {
            suite.expect(ForkGlanceTrace.replay(decoded, settings: settings) == metrics,
                         "a trace read back from its JSON replays the same")
        } else {
            suite.expect(false, "the synthetic trace encodes")
        }

        let other = synthetic(duration: 17, path: turning([3, 6, 9, 14]), typing: [8...10], seed: 99)
        suite.expect(ForkGlanceTrace.replay(other, settings: settings).switches == 4,
                     "other noise, same switches: the result does not hang on one draw")
    }

    private static func bench(_ suite: TestSuite) {
        // Three 0.4 s glances right, each back to the left.
        let glances: Path = { time in
            [2.0, 5.0, 8.0].contains { time >= $0 && time < $0 + 0.4 } ? 2580 : 860
        }
        let trace = synthetic(duration: 10, path: glances)
        let lively = ForkGlanceTrace.replay(trace, settings: Machine.settings())
        suite.expect(lively.switches == 6 && lively.quickReversals == 3,
                     "with a 200 ms dwell, each 0.4 s glance switches and comes back: got \(lively)")
        let prudent = ForkGlanceTrace.replay(trace, settings: Machine.settings { $0.dwell = 0.7 })
        suite.expect(prudent.switches == 0 && prudent.meanLatency == nil,
                     "a 700 ms dwell ignores them: the bench compares settings")

        let blind = ForkGlanceTrace.replay(trace, settings: Machine.settings(), reclassify: { frame in
            frame.gaze.map { gaze in
                var copy = gaze
                copy.target = .between
                return copy
            }
        })
        suite.expect(blind.switches == 0, "a reclassifying closure replaces the recorded gazes")

        var steady = synthetic(duration: 3, path: { _ in 2580 })
        suite.expect(ForkGlanceTrace.replay(steady, settings: Machine.settings()).switches == 1,
                     "a gaze held on the other zone switches once")
        steady.marks = [.focusChanged(time: 0, zone: Machine.right)]
        suite.expect(ForkGlanceTrace.replay(steady, settings: Machine.settings()).switches == 0,
                     "a recorded focus change by the person is replayed")
        steady.marks = [.switched(time: 0.3, zone: Machine.right, succeeded: true)]
        suite.expect(ForkGlanceTrace.replay(steady, settings: Machine.settings()).switches == 1,
                     "the recorded switches are not fed back: the replay decides again")

        var single = synthetic(duration: 3, path: { _ in 2580 })
        single.layout = ForkGlanceDisplayLayout(displays: [layout.displays[0]])
        suite.expect(ForkGlanceTrace.replay(single, settings: Machine.settings { $0.mode = .screens }).switches == 0,
                     "the replay keeps the recorded layout's screen count")
    }
}
