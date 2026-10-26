// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import CoreGraphics
import Foundation

/// The live journal (Diagnostic › « Journal en direct pour l'analyse »): while
/// its switch is on, what Glance Focus measures and does is appended to a
/// JSON Lines file, one object per line, so the feature can be tuned from a
/// terminal that only reads the file while the person works. Measurements
/// only: never an image, never a window title, never a key.
///
/// Each line is `{"kind": …, "t": …, …}`: `t` is seconds since the journal
/// began (the `start` line also holds the wall clock), `kind` one of `Kind`.
/// The frames reuse the trace's types (`ForkGlanceTrace.Input`, the sample,
/// the gaze, the guards). Files live in `Glance/journal/`
/// (`glance-live-<yyyy-MM-dd-HHmmss>.jsonl`), at most `maxFileBytes` each;
/// a new file starts with the lines that describe the session (`Output`),
/// and only the last `keptFiles` stay.
///
/// Pure: the service writes, on its own serial queue, what this encodes.
enum ForkGlanceJournal {
    static let currentVersion = 1
    /// The switch turns itself off after this long.
    static let maxDuration: TimeInterval = 30 * 60
    static let maxFileBytes = 50 * 1024 * 1024
    static let keptFiles = 5
    /// Under `PrivateFileStore.containerURL/Glance/`.
    static let folderName = "journal"
    static let filePrefix = "glance-live-"
    static let fileExtension = "jsonl"

    // MARK: - Files

    /// `glance-live-2026-10-26-143205.jsonl`, in local time; « -2 », « -3 »…
    /// when a name of that second is `taken`. Sorting the names sorts the files by age.
    static func fileName(for date: Date, timeZone: TimeZone = .current, taken: Set<String> = []) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let stem = filePrefix + formatter.string(from: date)
        var name = "\(stem).\(fileExtension)"
        var index = 2
        while taken.contains(name) {
            name = "\(stem)-\(index).\(fileExtension)"
            index += 1
        }
        return name
    }

    static func isJournalFile(_ name: String) -> Bool {
        name.hasPrefix(filePrefix) && name.hasSuffix(".\(fileExtension)")
    }

    /// The journal files to delete so that only the `keeping` newest stay;
    /// any other file in the folder is left alone.
    static func surplus(_ names: [String], keeping: Int = keptFiles) -> [String] {
        let journals = names.filter(isJournalFile).sorted(by: newerLast)
        return Array(journals.dropLast(max(keeping, 0)))
    }

    /// Name order, except that « …-143205-2 » comes after « …-143205 ».
    private static func newerLast(_ lhs: String, _ rhs: String) -> Bool {
        func key(_ name: String) -> (String, Int) {
            let stem = String(name.dropLast(fileExtension.count + 1))
            guard stem.count > filePrefix.count + 17, let dash = stem.lastIndex(of: "-"),
                  let index = Int(stem[stem.index(after: dash)...]) else { return (stem, 1) }
            return (String(stem[..<dash]), index)
        }
        return key(lhs) < key(rhs)
    }

    // MARK: - Lines

    enum Kind: String, Codable, CaseIterable {
        case start
        case frame
        case click
        case `switch`
        case phase
        case layout
        case zones
        case calibration
        case notice
        case cameraFps
        /// The journal ends: the switch, its time limit, the feature going down.
        case stop
    }

    /// What one line says.
    enum Event {
        case start(Start)
        case frame(Frame)
        case click(Click)
        case `switch`(Switch)
        case phase(Phase)
        case layout(Layout)
        case zones([ForkGlanceZone])
        case calibration(Calibration)
        case notice(Notice)
        case cameraFps(CameraRate)
        case stop(reason: String)

        var kind: Kind {
            switch self {
            case .start: return .start
            case .frame: return .frame
            case .click: return .click
            case .switch: return .switch
            case .phase: return .phase
            case .layout: return .layout
            case .zones: return .zones
            case .calibration: return .calibration
            case .notice: return .notice
            case .cameraFps: return .cameraFps
            case .stop: return .stop
            }
        }

        /// The fields beside `t` and `kind`.
        fileprivate var payload: Encodable {
            switch self {
            case let .start(start): return start
            case let .frame(frame): return frame
            case let .click(click): return click
            case let .switch(record): return record
            case let .phase(phase): return PhaseChange(phase: phase)
            case let .layout(layout): return layout
            case let .zones(zones): return ZonesChange(zones: zones)
            case let .calibration(calibration): return calibration
            case let .notice(notice): return notice
            case let .cameraFps(rate): return rate
            case let .stop(reason): return Stop(reason: reason)
            }
        }
    }

    /// One line: `t`, `kind`, then the event's own fields at the same level.
    struct Line: Encodable {
        /// Seconds since the journal began, to the millisecond.
        var t: TimeInterval
        var event: Event

        init(t: TimeInterval, event: Event) {
            self.t = t.isFinite ? (t * 1000).rounded() / 1000 : t
            self.event = event
        }

        private enum CodingKeys: String, CodingKey { case t, kind }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(t, forKey: .t)
            try container.encode(event.kind, forKey: .kind)
            // The same keyed container: the event's fields sit beside `t` and `kind`.
            try event.payload.encode(to: encoder)
        }
    }

    /// One line of JSON, newline included: sorted keys, ISO 8601 dates, a
    /// stray non-finite number spelled out as in the traces.
    static func encode(_ line: Line) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        encoder.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "inf", negativeInfinity: "-inf",
                                                                      nan: "nan")
        var data = try encoder.encode(line)
        data.append(0x0A)
        return data
    }

    // MARK: - Payloads

    /// The session: who, what settings, which desk, which profile, which camera.
    struct Start: Encodable {
        var version = ForkGlanceJournal.currentVersion
        /// The wall clock at `t` = 0.
        var wall: Date
        /// « 1.2.3 (456) ».
        var appVersion: String
        var macOS: String
        /// `hw.model`.
        var mac: String
        var settings: ForkGlanceSettings
        var layout: ForkGlanceDisplayLayout
        var layoutSignature: String
        var zones: [ForkGlanceZone]
        var currentZone: String?
        var phase: Phase
        var profile: Profile?
        var camera: Camera
    }

    /// The profile in force, its calibration summed up.
    struct Profile: Codable, Equatable {
        var title: String
        var calibration: CalibrationSummary?
        var learnedClicks: Int
        /// Share of the last clicks whose zone was the predicted one.
        var clickAgreement: Double?

        init(_ profile: ForkGlanceProfile) {
            title = profile.title
            calibration = profile.calibration.map(CalibrationSummary.init)
            learnedClicks = profile.learning.pairs.count
            clickAgreement = profile.learning.agreement
        }
    }

    /// A calibration as the tuning needs it; never its coefficients.
    struct CalibrationSummary: Codable, Equatable {
        var date: Date
        /// The cross-validated residual, points (x, y).
        var sigma: CGSize
        /// √(σx² + σy²), points.
        var error: Double
        var bias: CGVector
        var usesEyes: Bool
        var zoneAccuracy: [String: Double]

        init(_ calibration: ForkGlanceCalibration) {
            date = calibration.date
            sigma = calibration.sigma
            error = hypot(Double(calibration.sigma.width), Double(calibration.sigma.height))
            bias = calibration.bias
            usesEyes = calibration.usesEyes
            zoneAccuracy = calibration.zoneAccuracy
        }
    }

    /// The camera filmed with: its model, never its name (it may carry a person's).
    struct Camera: Codable, Equatable {
        /// `AVCaptureDevice.modelID`.
        var model: String?
        /// `builtIn`, `external`, `continuity` or `none`.
        var kind: String
        /// The device's active format, in pixels.
        var width: Int?
        var height: Int?
        /// The rate asked (images per second), and the rate measured while running.
        var fps: Double?
        var measuredFps: Double?
        var running: Bool

        init(model: String?, kind: String, width: Int?, height: Int?, fps: Double?, measuredFps: Double?,
             running: Bool) {
            self.model = model
            self.kind = kind
            self.width = width
            self.height = height
            self.fps = fps
            self.measuredFps = measuredFps
            self.running = running
        }
    }

    /// The machine's phase, its times as journal times.
    struct Phase: Codable, Equatable {
        /// The case: `off`, `unavailable`, `needsCalibration`, `calibrating`,
        /// `paused`, `starting`, `searching`, `away`, `settled`, `candidate`,
        /// `blocked`, `cooldown`.
        var name: String
        /// Why it is unavailable, paused, or needs a calibration.
        var reason: String?
        var zone: String?
        /// A candidate's zone with the keyboard.
        var current: String?
        var guards: [ForkGlanceGuard]?
        /// A candidate's start.
        var since: TimeInterval?
        /// A cooldown's or a timed pause's end.
        var until: TimeInterval?

        /// `origin`: the `systemUptime` of `t` = 0.
        init(_ phase: ForkGlancePhase, origin: TimeInterval) {
            func time(_ uptime: TimeInterval) -> TimeInterval { ((uptime - origin) * 1000).rounded() / 1000 }
            switch phase {
            case .off: name = "off"
            case let .unavailable(why):
                name = "unavailable"
                reason = why.rawValue
            case let .needsCalibration(need):
                name = "needsCalibration"
                reason = need.rawValue
            case .calibrating: name = "calibrating"
            case let .paused(why, end):
                name = "paused"
                reason = why.rawValue
                until = end.map(time)
            case .starting: name = "starting"
            case .searching: name = "searching"
            case let .away(zone):
                name = "away"
                self.zone = zone
            case let .settled(zone):
                name = "settled"
                self.zone = zone
            case let .candidate(zone, current, start):
                name = "candidate"
                self.zone = zone
                self.current = current
                since = time(start)
            case let .blocked(zone, raised):
                name = "blocked"
                self.zone = zone
                guards = raised
            case let .cooldown(zone, end):
                name = "cooldown"
                self.zone = zone
                until = time(end)
            }
        }
    }

    /// What Vision saw, in numbers (the trace keeps only the filtered vector).
    struct Face: Codable, Equatable {
        /// Normalized x, y, width, height, origin at the bottom left.
        var box: CGRect
        /// Radians.
        var yaw: Double?
        var pitch: Double?
        var roll: Double?
        /// Pupils found, 0 to 2.
        var pupils: Int
        var faces: Int
        var otherFaceRatio: Double
        /// Only measured in the assistant.
        var quality: Double?

        init(_ observation: ForkGlanceObservation) {
            box = observation.faceBox
            yaw = observation.yaw
            pitch = observation.pitch
            roll = observation.roll
            pupils = [observation.leftPupil, observation.rightPupil].compactMap { $0 }.count
            faces = observation.faceCount
            otherFaceRatio = observation.otherFaceRatio
            quality = observation.captureQuality
        }
    }

    /// One processed image: a trace frame's fields (`ForkGlanceTrace.Frame`),
    /// the raw face and the phase. No input while the assistant runs.
    struct Frame: Encodable {
        var sample: ForkGlanceSample?
        var gaze: ForkGlanceGaze?
        var input: ForkGlanceTrace.Input?
        var guards: [ForkGlanceGuard]
        var face: Face?
        var phase: Phase
    }

    /// A real click.
    struct Click: Codable, Equatable {
        /// Global points.
        var point: CGPoint
        var zone: String?
        /// Where the gaze was at that moment (`gaze`), and its zone if any.
        var gaze: String?
        var gazeZone: String?
        /// The frontmost app's bundle id.
        var app: String?
    }

    /// A switch the feature made.
    struct Switch: Codable, Equatable {
        var zone: String
        /// The zone that had the keyboard.
        var from: String?
        var succeeded: Bool
        /// The target window's app, bundle id.
        var app: String?
        /// The target had the keyboard already (no visible effect).
        var alreadyFocused: Bool?
    }

    /// The displays changed: the new layout and the profile matched for it.
    struct Layout: Encodable {
        var layout: ForkGlanceDisplayLayout
        var layoutSignature: String
        var profile: Profile?
    }

    /// The end of a calibration, a recenter, a quick recenter, a validation
    /// or a refit from the clicks.
    struct Calibration: Codable, Equatable {
        enum What: String, Codable {
            case calibration
            case validation
            case recenter
            case quickRecenter
            case refit
        }

        var what: What
        /// Whether the result is now the profile's.
        var kept: Bool
        var before: CalibrationSummary?
        var after: CalibrationSummary?
        /// The refits: the RMS error on the calibration points, points.
        var errorBefore: Double?
        var errorAfter: Double?
        /// The validation's score and per-zone accuracy.
        var score: Double?
        var zoneAccuracy: [String: Double]?
        /// Why it was not kept.
        var reason: String?

        init(what: What, kept: Bool, before: ForkGlanceCalibration? = nil, after: ForkGlanceCalibration? = nil,
             errorBefore: Double? = nil, errorAfter: Double? = nil, score: Double? = nil,
             zoneAccuracy: [String: Double]? = nil, reason: String? = nil) {
            self.what = what
            self.kept = kept
            self.before = before.map(CalibrationSummary.init)
            self.after = after.map(CalibrationSummary.init)
            self.errorBefore = errorBefore
            self.errorAfter = errorAfter
            self.score = score
            self.zoneAccuracy = zoneAccuracy
            self.reason = reason
        }
    }

    /// A notice handed to the island.
    struct Notice: Codable, Equatable {
        /// `paused`, `resumed`, `newLayout`, `cameraUnavailable`, `recentered`, `calibrated`, `drift`.
        var notice: String
        var score: Double?
        /// A timed pause's end, journal time.
        var until: TimeInterval?

        init(_ notice: ForkGlanceNotice, origin: TimeInterval) {
            switch notice {
            case let .paused(end):
                self.notice = "paused"
                until = end.map { (($0 - origin) * 1000).rounded() / 1000 }
            case .resumed: self.notice = "resumed"
            case .newLayout: self.notice = "newLayout"
            case .cameraUnavailable: self.notice = "cameraUnavailable"
            case .recentered: self.notice = "recentered"
            case let .calibrated(value):
                self.notice = "calibrated"
                score = value
            case .drift: self.notice = "drift"
            }
        }
    }

    /// The machine asked for another rate.
    struct CameraRate: Codable, Equatable {
        var fps: Double
        var camera: Camera
    }

    private struct PhaseChange: Encodable { var phase: Phase }
    private struct ZonesChange: Encodable { var zones: [ForkGlanceZone] }
    private struct Stop: Encodable { var reason: String }

    /// What a gaze pointed at, in a word.
    static func describe(_ target: ForkGlanceGazeTarget) -> (word: String, zone: String?) {
        switch target {
        case let .zone(zone): return ("zone", zone)
        case .between: return ("between", nil)
        case .away: return ("away", nil)
        case .noFace: return ("noFace", nil)
        }
    }

    // MARK: - Output

    /// Where each encoded line goes: the current file while it stays under
    /// `limit`, else a new file that first repeats the lines describing the
    /// session (the `start`, and the latest `layout` and `zones`), so every
    /// file reads on its own. A single line longer than the limit still goes
    /// whole into a fresh file.
    struct Output {
        enum Placement: Equatable {
            case append
            /// Close the file, open a new one, write `preamble` then the line.
            case rotate(preamble: [Data])
        }

        /// Repeated at the top of each new file, in this order.
        static let carried: [Kind] = [.start, .layout, .zones]

        let limit: Int
        /// Bytes in the current file.
        private(set) var written = 0
        private var latest: [Kind: Data] = [:]

        init(limit: Int = ForkGlanceJournal.maxFileBytes) {
            self.limit = limit
        }

        mutating func place(_ line: Data, kind: Kind) -> Placement {
            var placement = Placement.append
            if written > 0, written + line.count > limit {
                // The line itself replaces its kind's older copy.
                let preamble = Self.carried.filter { $0 != kind }.compactMap { latest[$0] }
                written = preamble.reduce(0) { $0 + $1.count }
                placement = .rotate(preamble: preamble)
            }
            written += line.count
            if Self.carried.contains(kind) { latest[kind] = line }
            return placement
        }
    }
}
