// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import CoreGraphics
import Foundation

/// A recording of what Glance Focus saw and did, about 60 s, exported from
/// the diagnostics (plan §12.11) to tune the feature without a guided session
/// (plan §17.2). It holds numbers only: no image, no window or app name, no
/// key. The frontmost app is kept as one flag, « in the never-leave list ».
///
/// `replay` runs the decision machine again over the recorded images with
/// other settings, the bench for the dwell, the pauses and the guards; with
/// `reclassify`, a classifier can turn the recorded estimates into gazes again
/// (the margins). It is deterministic: no clock, no randomness.
struct ForkGlanceTrace: Codable, Equatable {
    static let currentVersion = 1
    /// What the diagnostics records.
    static let maxDuration: TimeInterval = 60
    /// Input ages are capped here so the JSON never holds an infinity.
    static let maxAge: TimeInterval = 86_400

    /// The input state at one image, ages only.
    struct Input: Codable, Equatable {
        var sinceKey: TimeInterval
        var sincePointer: TimeInterval
        var buttonsDown: Bool
        var modifiersDown: Bool
        var secureInput: Bool
        var dictationActive: Bool
        var menuOrOverview: Bool
        var islandKey: Bool
        var ownPanelKey: Bool
        /// The frontmost app was in « Ne jamais quitter », its id not kept.
        var excludedSource: Bool

        init(_ snapshot: ForkGlanceInputSnapshot, neverLeaveApps: Set<String>) {
            sinceKey = min(max(snapshot.sinceKey, 0), ForkGlanceTrace.maxAge)
            sincePointer = min(max(snapshot.sincePointer, 0), ForkGlanceTrace.maxAge)
            buttonsDown = snapshot.buttonsDown
            modifiersDown = snapshot.modifiersDown
            secureInput = snapshot.secureInput
            dictationActive = snapshot.dictationActive
            menuOrOverview = snapshot.menuOrOverview
            islandKey = snapshot.islandKey
            ownPanelKey = snapshot.ownPanelKey
            excludedSource = ForkGlanceSettings.list(Array(neverLeaveApps), contains: snapshot.frontmostBundleID)
        }

        /// The snapshot to replay; an excluded source stands as `excludedMarker`.
        var snapshot: ForkGlanceInputSnapshot {
            ForkGlanceInputSnapshot(sinceKey: sinceKey, sincePointer: sincePointer, buttonsDown: buttonsDown,
                                    modifiersDown: modifiersDown, secureInput: secureInput,
                                    dictationActive: dictationActive, menuOrOverview: menuOrOverview,
                                    islandKey: islandKey, ownPanelKey: ownPanelKey,
                                    frontmostBundleID: excludedSource ? ForkGlanceTrace.excludedMarker : nil)
        }
    }

    /// The bundle id an excluded frontmost app is replayed as.
    static let excludedMarker = "trace.excluded"

    /// One processed image.
    struct Frame: Codable, Equatable {
        /// Seconds since the trace began.
        var time: TimeInterval
        /// The filtered vector, nil without a face.
        var sample: ForkGlanceSample?
        /// The classified gaze, its estimate included; nil when the camera
        /// gave nothing usable.
        var gaze: ForkGlanceGaze?
        var input: Input
        /// Raised when it was recorded.
        var guards: [ForkGlanceGuard]
    }

    /// What happened between images.
    enum Mark: Codable, Equatable {
        /// A real click, its zone when it lay in one (the learning's pairs).
        case click(time: TimeInterval, point: CGPoint, zone: String?)
        /// The person changed window themselves.
        case focusChanged(time: TimeInterval, zone: String?)
        /// A switch the feature made, and whether the focus took.
        case switched(time: TimeInterval, zone: String, succeeded: Bool)
        case zonesChanged(time: TimeInterval, zones: [ForkGlanceZone])

        var time: TimeInterval {
            switch self {
            case let .click(time, _, _), let .focusChanged(time, _), let .switched(time, _, _),
                 let .zonesChanged(time, _):
                return time
            }
        }
    }

    struct Metrics: Equatable {
        var switches: Int
        /// Switches back to the zone the previous switch left, within
        /// `quickReversal` of it: the proxy for a wrong switch.
        var quickReversals: Int
        /// From the moment the gaze reached the zone, or the last guard
        /// dropped if later, to the switch. Nil without a switch.
        var meanLatency: TimeInterval?
        /// The share of watched images with a guard raised (the cooldown
        /// aside): no switch could have happened then, 0…1.
        var blockedShare: Double
    }

    /// A reversal quicker than this counts in `quickReversals`.
    static let quickReversal: TimeInterval = 2

    var version: Int
    var recorded: Date
    /// « 1.2.3 (456) », to tell traces apart.
    var appVersion: String
    var settings: ForkGlanceSettings
    var layout: ForkGlanceDisplayLayout
    var layoutSignature: String
    var usesEyes: Bool
    var zones: [ForkGlanceZone]
    /// The zone that had the keyboard when the recording began.
    var initialZone: String?
    var frames: [Frame]
    var marks: [Mark]

    init(recorded: Date, appVersion: String, settings: ForkGlanceSettings, layout: ForkGlanceDisplayLayout,
         layoutSignature: String, usesEyes: Bool, zones: [ForkGlanceZone], initialZone: String?,
         frames: [Frame] = [], marks: [Mark] = []) {
        version = Self.currentVersion
        self.recorded = recorded
        self.appVersion = appVersion
        self.settings = settings
        self.layout = layout
        self.layoutSignature = layoutSignature
        self.usesEyes = usesEyes
        self.zones = zones
        self.initialZone = initialZone
        self.frames = frames
        self.marks = marks
    }

    /// The recorded span, seconds.
    var duration: TimeInterval {
        max(frames.last?.time ?? 0, marks.map(\.time).max() ?? 0)
    }

    // MARK: - JSON

    /// Pretty, sorted, with dates in ISO 8601 and any stray non-finite number
    /// spelled out, so a trace always encodes and diffs well.
    static func encode(_ trace: ForkGlanceTrace) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        encoder.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "inf", negativeInfinity: "-inf",
                                                                      nan: "nan")
        return try encoder.encode(trace)
    }

    static func decode(_ data: Data) throws -> ForkGlanceTrace {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "inf", negativeInfinity: "-inf",
                                                                        nan: "nan")
        return try decoder.decode(ForkGlanceTrace.self, from: data)
    }

    // MARK: - Replay

    static func replay(_ trace: ForkGlanceTrace, settings: ForkGlanceSettings) -> Metrics {
        replay(trace, settings: settings, reclassify: nil)
    }

    /// The machine fed with the recorded images and marks in time order,
    /// its deadlines ticked as the service's timer would, every focus
    /// reported as successful. The recorded switches and clicks are the
    /// recording's own outcome: they are not fed back.
    static func replay(_ trace: ForkGlanceTrace, settings: ForkGlanceSettings,
                       reclassify: ((Frame) -> ForkGlanceGaze?)?) -> Metrics {
        var replayed = settings
        replayed.enabled = true
        replayed.neverLeaveApps.insert(excludedMarker)
        var system = ForkGlanceSystemSnapshot.ready
        system.displayCount = trace.layout.displays.count

        var bench = Bench(keyboard: trace.initialZone)
        var machine = ForkGlanceMachine(settings: replayed)
        let start = min(trace.frames.first?.time ?? 0, trace.marks.map(\.time).min() ?? 0)
        machine.handle(.system(system), now: start)
        machine.handle(.calibrationNeed(nil), now: start)
        machine.handle(.zonesChanged(trace.zones), now: start)
        machine.handle(.focusChanged(zone: trace.initialZone), now: start)

        enum Step {
            case frame(Frame)
            case mark(Mark)
            var time: TimeInterval {
                switch self {
                case let .frame(frame): return frame.time
                case let .mark(mark): return mark.time
                }
            }
        }
        // Marks first at an equal time; the sort is stable, so the order of
        // the recording is kept otherwise.
        let steps = (trace.marks.map(Step.mark) + trace.frames.map(Step.frame)).enumerated().sorted {
            ($0.element.time, $0.offset) < ($1.element.time, $1.offset)
        }.map(\.element)

        for step in steps {
            let time = step.time
            while let deadline = machine.nextDeadline, deadline <= time {
                let effects = machine.handle(.tick, now: deadline)
                bench.run(effects, at: deadline, machine: &machine)
            }
            switch step {
            case let .frame(frame):
                let inputs = machine.handle(.inputs(frame.input.snapshot), now: time)
                bench.run(inputs, at: time, machine: &machine)
                let gaze = reclassify.map { $0(frame) } ?? frame.gaze
                bench.follow(gaze?.target ?? .noFace, at: time)
                let effects = machine.handle(.gaze(gaze), now: time)
                bench.run(effects, at: time, machine: &machine)
                bench.count(machine, at: time)
            case let .mark(.focusChanged(_, zone)):
                bench.keyboard = zone
                bench.run(machine.handle(.focusChanged(zone: zone), now: time), at: time, machine: &machine)
            case let .mark(.zonesChanged(_, zones)):
                bench.run(machine.handle(.zonesChanged(zones), now: time), at: time, machine: &machine)
            case .mark(.click), .mark(.switched):
                break
            }
        }
        return bench.metrics
    }

    /// The replay's bookkeeping.
    private struct Bench {
        struct Switch {
            var time: TimeInterval
            var from: String?
            var to: String
        }

        /// The zone with the keyboard, as the replay saw it.
        var keyboard: String?
        var switches: [Switch] = []
        var latencies: [TimeInterval] = []
        var watched = 0
        var blocked = 0
        var lastBlocked: TimeInterval?
        /// The zone the gaze has stayed on, and since when (two faceless
        /// images forgiven, like the machine).
        var runZone: String?
        var runStart: TimeInterval = 0
        var runMisses = 0

        mutating func follow(_ target: ForkGlanceGazeTarget, at time: TimeInterval) {
            switch target {
            case let .zone(zone):
                runMisses = 0
                if zone != runZone {
                    runZone = zone
                    runStart = time
                }
            case .noFace:
                runMisses += 1
                if runMisses > ForkGlanceMachine.toleratedMisses { runZone = nil }
            case .between, .away:
                runZone = nil
                runMisses = 0
            }
        }

        mutating func run(_ effects: [ForkGlanceEffect], at time: TimeInterval, machine: inout ForkGlanceMachine) {
            for effect in effects {
                guard case let .focus(zone) = effect else { continue }
                switches.append(Switch(time: time, from: keyboard, to: zone))
                keyboard = zone
                let onset = runZone == zone ? runStart : time
                latencies.append(time - max(onset, lastBlocked ?? onset))
                machine.handle(.focusResult(zone: zone, succeeded: true), now: time)
            }
        }

        mutating func count(_ machine: ForkGlanceMachine, at time: TimeInterval) {
            guard machine.phase.isWatching else { return }
            watched += 1
            if machine.guards.contains(where: { $0 != .cooldown }) {
                blocked += 1
                lastBlocked = time
            }
        }

        var metrics: Metrics {
            var reversals = 0
            for (previous, next) in zip(switches, switches.dropFirst())
            where next.to == previous.from && next.time - previous.time < ForkGlanceTrace.quickReversal {
                reversals += 1
            }
            let latency = latencies.isEmpty ? nil : latencies.reduce(0, +) / Double(latencies.count)
            return Metrics(switches: switches.count, quickReversals: reversals, meanLatency: latency,
                           blockedShare: watched == 0 ? 0 : Double(blocked) / Double(watched))
        }
    }
}
