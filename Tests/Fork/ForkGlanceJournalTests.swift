// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import CoreGraphics
import Foundation

/// Suite `fork-glance-journal` — F2: the live journal's lines, files and rotation.
enum ForkGlanceJournalTests {
    private typealias Machine = ForkGlanceMachineTests
    private typealias Journal = ForkGlanceJournal

    static func run(_ suite: TestSuite) {
        files(suite)
        lines(suite)
        frames(suite)
        phases(suite)
        start(suite)
        events(suite)
        rotation(suite)
        defaults(suite)
    }

    private static let layout = ForkGlanceDisplayLayout(displays: [
        ForkGlanceDisplay(uuid: "LG", name: "LG HDR WQHD", frame: CGRect(x: 0, y: 0, width: 3440, height: 1440),
                          millimeters: CGSize(width: 816, height: 338)),
        ForkGlanceDisplay(uuid: "MAC", name: "Built-in Retina Display",
                          frame: CGRect(x: 938, y: 1440, width: 1728, height: 1117),
                          millimeters: CGSize(width: 344, height: 222), isBuiltIn: true, hasNotch: true),
    ])

    private static let calibration = ForkGlanceCalibration(
        version: 1, date: Date(timeIntervalSince1970: 1_792_000_000), cameraID: "cam", layoutSignature: "LG+MAC",
        usesEyes: true, coefficientsX: [1, 2], coefficientsY: [3, 4], normalization: [], sigma: CGSize(width: 30, height: 40),
        bias: CGVector(dx: 5, dy: -6), yawRange: -0.5...0.5, pitchRange: -0.3...0.3, zoneAccuracy: [Machine.left: 0.96])

    private static let camera = Journal.Camera(model: "UVC Camera VendorID_1133 ProductID_2142", kind: "external",
                                               width: 640, height: 480, fps: 12, measuredFps: 11.8, running: true)

    /// The line as a JSON object, and whether it was exactly one line.
    private static func object(_ event: Journal.Event, t: TimeInterval = 1.5) -> (json: [String: Any], oneLine: Bool) {
        guard let data = try? Journal.encode(Journal.Line(t: t, event: event)),
              let text = String(data: data, encoding: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return ([:], false) }
        let oneLine = text.hasSuffix("\n") && text.dropLast().contains("\n") == false
        return (json, oneLine)
    }

    private static func frame(input: Bool = true, face: Bool = true) -> Journal.Frame {
        let sample = ForkGlanceSample(time: 10, vector: [0.1, -0.2, 0.3], confidence: 0.9, eyesUsable: true,
                                      facePresent: true)
        let estimate = ForkGlanceEstimate(point: CGPoint(x: 800, y: 700), sigma: CGSize(width: 60, height: 50),
                                          time: 10, confidence: 0.9)
        let gaze = ForkGlanceGaze(estimate: estimate, target: .zone(Machine.left), margin: 1.4, headSpeed: 3,
                                  confidence: 0.9, crowded: false)
        let observation = ForkGlanceObservation(time: 10, faceBox: CGRect(x: 0.3, y: 0.2, width: 0.25, height: 0.33),
                                                yaw: 0.12, pitch: -0.05, roll: 0.01, leftPupil: CGPoint(x: 0.4, y: 0.4),
                                                faceCount: 1)
        return Journal.Frame(
            sample: sample, gaze: gaze,
            input: input ? ForkGlanceTrace.Input(Machine.hands(sinceKey: 0.4), neverLeaveApps: []) : nil,
            guards: [.typing], face: face ? Journal.Face(observation) : nil,
            phase: Journal.Phase(.blocked(zone: Machine.left, guards: [.typing]), origin: 0))
    }

    // MARK: - Files

    private static func files(_ suite: TestSuite) {
        let date = Date(timeIntervalSince1970: 1_792_000_000) // 2026-10-14 17:46:40 UTC
        let utc = TimeZone(identifier: "UTC")!
        let name = Journal.fileName(for: date, timeZone: utc)
        suite.expect(name == "glance-live-2026-10-14-174640.jsonl", "a journal is named by its local start time: \(name)")
        let again = Journal.fileName(for: date, timeZone: utc, taken: [name])
        let third = Journal.fileName(for: date, timeZone: utc, taken: [name, again])
        suite.expect(again == "glance-live-2026-10-14-174640-2.jsonl" && third == "glance-live-2026-10-14-174640-3.jsonl",
                     "a second journal in the same second never overwrites the first: \(again), \(third)")
        suite.expect(Journal.isJournalFile(name) && !Journal.isJournalFile("glance-trace-2026.json")
                        && !Journal.isJournalFile(".DS_Store"),
                     "only the journal's own files count as journals")

        let names = ["glance-live-2026-10-20-090000.jsonl", "glance-live-2026-10-22-090000.jsonl", "notes.txt",
                     "glance-live-2026-10-21-090000.jsonl", "glance-live-2026-10-22-090000-2.jsonl",
                     "glance-live-2026-10-23-090000.jsonl", "glance-live-2026-10-24-090000.jsonl"]
        let doomed = Journal.surplus(names)
        suite.expect(doomed == ["glance-live-2026-10-20-090000.jsonl"],
                     "past five journals the oldest goes, a same-second « -2 » counting as newer: \(doomed)")
        suite.expect(Journal.surplus(names, keeping: 2) == ["glance-live-2026-10-20-090000.jsonl",
                                                            "glance-live-2026-10-21-090000.jsonl",
                                                            "glance-live-2026-10-22-090000.jsonl",
                                                            "glance-live-2026-10-22-090000-2.jsonl"],
                     "the newest journals are the ones kept")
        suite.expect(Journal.surplus(Array(names.prefix(3))).isEmpty && !Journal.surplus(names).contains("notes.txt"),
                     "nothing goes under the limit, and a file that is not a journal never goes")
    }

    // MARK: - Lines

    private static func lines(_ suite: TestSuite) {
        let events: [Journal.Event] = [
            .start(startLine()), .frame(frame()),
            .click(Journal.Click(point: CGPoint(x: 100, y: 200), zone: Machine.left, gaze: "zone", gazeZone: Machine.left,
                                 app: "com.apple.Terminal")),
            .switch(Journal.Switch(zone: Machine.right, from: Machine.left, succeeded: true, app: "com.apple.Safari",
                                   alreadyFocused: false)),
            .phase(Journal.Phase(.settled(zone: Machine.left), origin: 0)),
            .layout(Journal.Layout(layout: layout, layoutSignature: "LG+MAC", profile: nil)),
            .zones(Machine.zones),
            .calibration(Journal.Calibration(what: .recenter, kept: true, before: calibration, after: calibration)),
            .notice(Journal.Notice(.resumed, origin: 0)),
            .cameraFps(Journal.CameraRate(fps: 6, camera: camera)),
            .stop(reason: "switchedOff"),
        ]
        suite.expect(Set(events.map(\.kind)) == Set(Journal.Kind.allCases), "the test covers every kind of line")
        var problems: [String] = []
        for event in events {
            let (json, oneLine) = object(event, t: 12.3456)
            if !oneLine { problems.append("\(event.kind.rawValue): not one line") }
            if json["kind"] as? String != event.kind.rawValue { problems.append("\(event.kind.rawValue): kind") }
            if (json["t"] as? Double).map({ abs($0 - 12.346) < 1e-9 }) != true { problems.append("\(event.kind.rawValue): t") }
        }
        suite.expect(problems.isEmpty, "every event is one JSON line with its kind and its time to the millisecond: \(problems)")
        suite.expect(Journal.Kind.switch.rawValue == "switch" && Journal.Kind.cameraFps.rawValue == "cameraFps",
                     "the kinds are spelled as the brief names them")

        let switched = object(.switch(Journal.Switch(zone: Machine.right, from: nil, succeeded: false, app: nil,
                                                     alreadyFocused: nil))).json
        suite.expect(switched["zone"] as? String == Machine.right && switched["succeeded"] as? Bool == false
                        && switched["from"] == nil && switched["app"] == nil,
                     "an event's fields sit beside t and kind, an unknown one left out")
        let stop = object(.stop(reason: "timeLimit")).json
        suite.expect(stop["reason"] as? String == "timeLimit", "the stop line says why the journal ended")
    }

    // MARK: - Frames

    private static func frames(_ suite: TestSuite) {
        let json = object(.frame(frame()), t: 10).json
        suite.expect(["sample", "gaze", "input", "guards", "face", "phase"].allSatisfy { json[$0] != nil },
                     "a frame line holds the trace's sample, gaze, input and guards, the raw face and the phase")
        let face = json["face"] as? [String: Any]
        suite.expect(face?["pupils"] as? Int == 1 && (face?["yaw"] as? Double).map { abs($0 - 0.12) < 1e-9 } == true
                        && face?["faces"] as? Int == 1,
                     "the raw face keeps the head's angles and how many pupils Vision found")
        suite.expect((json["phase"] as? [String: Any])?["name"] as? String == "blocked",
                     "each frame says the machine's phase")

        // Trace-compatible: the same field names, so the frames can be replayed.
        var traceFrame = json
        traceFrame["time"] = json["t"]
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "inf", negativeInfinity: "-inf",
                                                                        nan: "nan")
        let original = frame()
        let decoded = (try? JSONSerialization.data(withJSONObject: traceFrame))
            .flatMap { try? decoder.decode(ForkGlanceTrace.Frame.self, from: $0) }
        suite.expect(decoded == ForkGlanceTrace.Frame(time: 10, sample: original.sample, gaze: original.gaze,
                                                      input: original.input!, guards: original.guards),
                     "a frame line reads back as a trace frame (ForkGlanceTrace.Frame)")

        let assistant = object(.frame(frame(input: false, face: false))).json
        suite.expect(assistant["input"] == nil && assistant["face"] == nil && assistant["sample"] != nil,
                     "an image of the assistant has no input, an image without a face no face")

        var odd = frame()
        odd.gaze?.margin = .infinity
        let (oddJSON, oneLine) = object(.frame(odd))
        suite.expect(oneLine && (oddJSON["gaze"] as? [String: Any])?["margin"] as? String == "inf",
                     "a non-finite number is spelled out: the line stays valid JSON")
    }

    // MARK: - Phases

    private static func phases(_ suite: TestSuite) {
        let candidate = Journal.Phase(.candidate(zone: Machine.right, current: Machine.left, since: 1000.25), origin: 1000)
        suite.expect(candidate.name == "candidate" && candidate.zone == Machine.right && candidate.current == Machine.left
                        && candidate.since == 0.25,
                     "a candidate's start is a journal time: \(candidate)")
        let paused = Journal.Phase(.paused(.user, until: 1600), origin: 1000)
        suite.expect(paused.name == "paused" && paused.reason == "user" && paused.until == 600,
                     "a timed pause says its reason and its end in journal time")
        let open = Journal.Phase(.paused(.idle, until: nil), origin: 1000)
        suite.expect(open.until == nil && open.reason == "idle", "a pause without an end has none")
        let cooldown = Journal.Phase(.cooldown(zone: Machine.left, until: 1000.4), origin: 1000)
        suite.expect(cooldown.until.map { abs($0 - 0.4) < 1e-9 } == true, "a cooldown's end is a journal time")
        let blocked = Journal.Phase(.blocked(zone: nil, guards: [.pointer, .typing]), origin: 0)
        suite.expect(blocked.guards == [.pointer, .typing] && blocked.zone == nil, "a blocked phase lists its guards")
        let others: [(ForkGlancePhase, String, String?)] = [
            (.off, "off", nil), (.unavailable(.noCamera), "unavailable", "noCamera"),
            (.needsCalibration(.newLayout), "needsCalibration", "newLayout"), (.calibrating, "calibrating", nil),
            (.starting, "starting", nil), (.searching, "searching", nil), (.away(zone: Machine.mac), "away", nil),
            (.settled(zone: Machine.mac), "settled", nil),
        ]
        let wrong = others.filter { phase, name, reason in
            let line = Journal.Phase(phase, origin: 0)
            return line.name != name || line.reason != reason
        }.map(\.1)
        suite.expect(wrong.isEmpty, "every phase has its name and, for a reason, the reason: \(wrong)")
    }

    // MARK: - Start

    private static func startLine() -> Journal.Start {
        var learned = ForkGlanceLearning()
        learned.recordAgreement(predicted: Machine.left, clicked: Machine.left)
        let profile = ForkGlanceProfile(id: "LG+MAC", title: "LG + MacBook", layout: layout, splits: ["LG": .columns2],
                                        calibration: calibration, learning: learned,
                                        lastUsed: Date(timeIntervalSince1970: 1_792_000_000))
        return Journal.Start(wall: Date(timeIntervalSince1970: 1_792_000_000), appVersion: "1.0 (2240)", macOS: "15.1",
                             mac: "Mac15,6", settings: Machine.settings(), layout: layout, layoutSignature: "LG+MAC",
                             zones: Machine.zones, currentZone: Machine.left,
                             phase: Journal.Phase(.settled(zone: Machine.left), origin: 0),
                             profile: Journal.Profile(profile), camera: camera)
    }

    private static func start(_ suite: TestSuite) {
        let json = object(.start(startLine()), t: 0).json
        suite.expect(json["wall"] as? String == "2026-10-14T17:46:40Z" && json["t"] as? Double == 0
                        && json["version"] as? Int == Journal.currentVersion,
                     "the start line ties t = 0 to the wall clock, in ISO 8601")
        let settings = (json["settings"]).flatMap { try? JSONSerialization.data(withJSONObject: $0) }
            .flatMap { try? JSONDecoder().decode(ForkGlanceSettings.self, from: $0) }
        suite.expect(settings == Machine.settings(), "the start line holds the resolved settings, whole")
        suite.expect(json["layout"] != nil && (json["zones"] as? [Any])?.count == 3 && json["currentZone"] as? String == Machine.left
                        && json["macOS"] as? String == "15.1" && json["appVersion"] as? String == "1.0 (2240)",
                     "the start line holds the layout, the zones, the version and the system")

        let profile = json["profile"] as? [String: Any]
        let summary = profile?["calibration"] as? [String: Any]
        suite.expect(profile?["title"] as? String == "LG + MacBook" && profile?["clickAgreement"] as? Double == 1
                        && profile?["learnedClicks"] as? Int == 0,
                     "the profile says its title, its clicks learned and their agreement")
        suite.expect((summary?["error"] as? Double).map { abs($0 - 50) < 1e-9 } == true
                        && summary?["usesEyes"] as? Bool == true && summary?["sigma"] != nil && summary?["bias"] != nil
                        && (summary?["zoneAccuracy"] as? [String: Double])?[Machine.left] == 0.96
                        && summary?["date"] as? String == "2026-10-14T17:46:40Z",
                     "the calibration is summed up: date, σ and its error, bias, eyes, accuracy per zone")
        suite.expect(summary?["coefficientsX"] == nil && summary?["normalization"] == nil,
                     "never the model's coefficients")
        let cameraJSON = json["camera"] as? [String: Any]
        suite.expect(cameraJSON?["model"] as? String == camera.model && cameraJSON?["width"] as? Int == 640
                        && cameraJSON?["fps"] as? Double == 12 && cameraJSON?["running"] as? Bool == true
                        && cameraJSON?["name"] == nil,
                     "the camera is its model, its image size and its rate, never its name")
    }

    // MARK: - Other events

    private static func events(_ suite: TestSuite) {
        let click = object(.click(Journal.Click(point: CGPoint(x: 100, y: 200), zone: Machine.left, gaze: "between",
                                                gazeZone: nil, app: "com.apple.Terminal"))).json
        suite.expect((click["point"] as? [Double]) == [100, 200] && click["zone"] as? String == Machine.left
                        && click["gaze"] as? String == "between" && click["app"] as? String == "com.apple.Terminal",
                     "a click says its point, its zone, where the gaze was and the app in front")
        suite.expect(Journal.describe(.zone(Machine.left)) == ("zone", Machine.left) && Journal.describe(.noFace).word == "noFace"
                        && Journal.describe(.away).zone == nil,
                     "the gaze at a click reads in a word, with its zone")

        let refit = object(.calibration(Journal.Calibration(what: .refit, kept: false, before: calibration, after: nil,
                                                            errorBefore: 40, errorAfter: 52, reason: "worse"))).json
        suite.expect(refit["what"] as? String == "refit" && refit["kept"] as? Bool == false
                        && refit["errorBefore"] as? Double == 40 && refit["errorAfter"] as? Double == 52
                        && refit["before"] != nil && refit["after"] == nil,
                     "a refused refit says its error before and after on the calibration points")
        let validation = object(.calibration(Journal.Calibration(what: .validation, kept: true, score: 0.93,
                                                                 zoneAccuracy: [Machine.left: 1]))).json
        suite.expect(validation["score"] as? Double == 0.93 && validation["zoneAccuracy"] != nil,
                     "a validation says its score and its accuracy per zone")

        let paused = Journal.Notice(.paused(until: 1900), origin: 1000)
        let calibrated = Journal.Notice(.calibrated(score: 0.9), origin: 1000)
        suite.expect(paused.notice == "paused" && paused.until == 900 && calibrated.score == 0.9
                        && Journal.Notice(.drift, origin: 0).notice == "drift",
                     "a notice says which one, a pause its end, a calibration its score")
        let rate = object(.cameraFps(Journal.CameraRate(fps: 4, camera: camera))).json
        suite.expect(rate["fps"] as? Double == 4 && (rate["camera"] as? [String: Any])?["measuredFps"] as? Double == 11.8,
                     "a new rate step says the rate asked and the one measured")
        let zones = object(.zones(Machine.zones)).json
        suite.expect((zones["zones"] as? [Any])?.count == 3, "a zones line lists the new zones")
    }

    // MARK: - Rotation

    private static func rotation(_ suite: TestSuite) {
        func line(_ text: String) -> Data { Data((text + "\n").utf8) }
        var output = Journal.Output(limit: 100)
        let start = line(String(repeating: "s", count: 19))       // 20 bytes
        let layoutLine = line(String(repeating: "l", count: 9))  // 10 bytes
        suite.expect(output.place(start, kind: .start) == .append && output.place(layoutLine, kind: .layout) == .append,
                     "the first lines go into the file")
        let frame = line(String(repeating: "f", count: 29))      // 30 bytes
        suite.expect(output.place(frame, kind: .frame) == .append && output.place(frame, kind: .frame) == .append
                        && output.written == 90,
                     "lines are appended while the file stays under the limit")
        let newer = line(String(repeating: "L", count: 9))
        suite.expect(output.place(newer, kind: .layout) == .append, "a line that just fits is appended")
        let next = output.place(frame, kind: .frame)
        suite.expect(next == .rotate(preamble: [start, newer]) && output.written == 60,
                     "past the limit a new file starts with the start line and the latest layout, then the line")
        let zonesLine = line(String(repeating: "z", count: 59))
        let rotated = output.place(zonesLine, kind: .zones)
        suite.expect(rotated == .rotate(preamble: [start, newer]) && output.written == 90,
                     "a carried line replaces its own older copy instead of repeating it")

        var fresh = Journal.Output(limit: 10)
        let huge = line(String(repeating: "x", count: 50))
        suite.expect(fresh.place(huge, kind: .frame) == .append, "a line longer than the limit still goes whole into an empty file")
        suite.expect(Journal.Output().limit == 50 * 1024 * 1024 && Journal.keptFiles == 5 && Journal.maxDuration == 1800,
                     "50 MB per file, the last 5 files, 30 minutes")
    }

    // MARK: - Defaults

    private static func defaults(_ suite: TestSuite) {
        let key = ForkDefaultsKey.glanceLiveJournal
        suite.expect(key == "fork.glance.liveJournal" && ForkGlanceDefaults.machineKeys.contains(key)
                        && ForkGlanceDefaults.registered[key] == nil && ForkDefaults.registered[key] == nil
                        && !ForkDefaults.backupKeys.contains(key),
                     "the journal's switch is machine state: never registered, never in the settings backup")
    }
}
