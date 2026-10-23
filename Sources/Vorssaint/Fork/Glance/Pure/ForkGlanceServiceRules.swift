// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import CoreGraphics
import Foundation

/// Glance Focus: the service's own rules, kept pure so the tests read them
/// (`Service/ForkGlanceService` applies them): which profile a layout loads
/// and why a calibration is needed (plan §8.6), which notices a pause says
/// (plan §11.4), when a click teaches the model (plan §7.6), the Command
/// Bar's rows (plan §11.5) and the report (plan §12.11).
enum ForkGlanceServiceRules {
    // MARK: - Profiles (plan §8.6)

    /// What the service loads for a layout and a camera.
    struct ProfileChoice: Equatable {
        /// The profile in force: a stored one, or a new one not stored yet.
        var profile: ForkGlanceProfile
        /// Not in `profiles.json` yet: stored at its first split change or
        /// calibration, so a layout seen once leaves nothing on disk.
        var isNew: Bool
        /// The same displays and camera, moved (case 2): loaded, with a
        /// hint to recenter.
        var moved: Bool
        /// Nil: calibrated, the machine may watch.
        var need: ForkGlanceCalibrationNeed?
    }

    static func choose(_ match: ForkGlanceProfiles.Match, layout: ForkGlanceDisplayLayout, cameraID: String,
                       profiles: [ForkGlanceProfile], now: Date) -> ProfileChoice {
        switch match {
        case let .identical(profile), let .moved(profile):
            var moved = false
            if case .moved = match { moved = true }
            let others = profiles.filter { $0.id != profile.id }
            return ProfileChoice(profile: profile, isNew: false, moved: moved,
                                 need: profile.calibration == nil ? need(forUnknown: layout, profiles: others) : nil)
        case .unknown:
            return ProfileChoice(profile: ForkGlanceProfiles.newProfile(layout: layout, cameraID: cameraID, now: now),
                                 isNew: true, moved: false, need: need(forUnknown: layout, profiles: profiles))
        }
    }

    /// Why a layout without a calibrated profile needs one: the first time
    /// when no profile on this Mac is calibrated, a new camera when one has
    /// these very displays, a new layout otherwise.
    static func need(forUnknown layout: ForkGlanceDisplayLayout,
                     profiles: [ForkGlanceProfile]) -> ForkGlanceCalibrationNeed {
        let calibrated = profiles.filter { $0.calibration != nil }
        guard !calibrated.isEmpty else { return .firstTime }
        let displays = layout.displays.map(\.uuid).sorted()
        if calibrated.contains(where: { $0.layout.displays.map(\.uuid).sorted() == displays }) { return .newCamera }
        return .newLayout
    }

    /// A profile carried over to the layout as it is now (a calibration or
    /// a quick recenter on a moved layout): its id becomes the layout's
    /// signature, so the next launch finds it identical.
    static func rekeyed(_ profile: ForkGlanceProfile, layout: ForkGlanceDisplayLayout,
                        cameraID: String) -> ForkGlanceProfile {
        var result = profile
        result.id = ForkGlanceProfiles.signature(layout: layout, cameraID: cameraID)
        result.title = ForkGlanceProfiles.title(for: layout)
        result.layout = layout
        result.calibration?.layoutSignature = result.id
        return result
    }

    /// `profile` stored in place of the one with id `old` (they differ when
    /// it was rekeyed), the list bounded by `ForkGlanceProfiles.upserting`.
    static func replacing(_ old: String, with profile: ForkGlanceProfile,
                          in profiles: [ForkGlanceProfile]) -> [ForkGlanceProfile] {
        ForkGlanceProfiles.upserting(profile, into: profiles.filter { $0.id != old || old == profile.id })
    }

    // MARK: - Notices (plan §11.4)

    /// Where a pause or a resume came from.
    enum NoticeOrigin: Equatable {
        case shortcut
        case commandBar
        /// The island or the settings page: the person sees the change already.
        case surface
        /// A timed pause reached its end.
        case deadline
        /// The service put back a stored pause (launch, wake): nothing new.
        case restore
    }

    /// « Regard en pause » only follows a shortcut or the Command Bar;
    /// « Regard repris » also the end of a timed pause. Never a click in the
    /// island, the page, nor a pause put back at launch.
    static func showsPauseNotice(_ notice: ForkGlanceNotice, origin: NoticeOrigin) -> Bool {
        switch (notice, origin) {
        case (.paused, .shortcut), (.paused, .commandBar): return true
        case (.resumed, .shortcut), (.resumed, .commandBar), (.resumed, .deadline): return true
        case (.paused, _), (.resumed, _): return false
        default: return true
        }
    }

    /// « Le regard se trompe souvent » once a day at most (plan §7.6).
    static func driftNoticeDue(last: Date?, now: Date, calendar: Calendar = .current) -> Bool {
        guard let last else { return true }
        return !calendar.isDate(last, inSameDayAs: now)
    }

    // MARK: - Learning (plan §7.6)

    /// A real click teaches the model when a confident sample with a face is
    /// at most `ForkGlanceLearning.maximumSampleAge` from it, on either side:
    /// the image may be processed just after the click.
    static func teaches(sample: ForkGlanceSample, clickTime: TimeInterval) -> Bool {
        sample.facePresent && sample.confidence >= ForkGlanceLearning.minimumConfidence
            && abs(clickTime - sample.time) <= ForkGlanceLearning.maximumSampleAge
    }

    /// The zone a click lands in: the first one holding the point (front to
    /// back in Windows mode, where they never overlap anyway).
    static func zone(at point: CGPoint, in zones: [ForkGlanceZone]) -> ForkGlanceZone? {
        zones.first { $0.rect.contains(point) }
    }

    /// What the gaze predicted for a click, for the drift: nil when the gaze
    /// says nothing about it (no recent image with a face), `.some(nil)`
    /// when it pointed at no zone (a miss), else the zone.
    static func prediction(_ gaze: ForkGlanceGaze?, clickTime: TimeInterval) -> String?? {
        guard let gaze, let estimate = gaze.estimate,
              abs(clickTime - estimate.time) <= ForkGlanceLearning.maximumSampleAge else { return nil }
        switch gaze.target {
        case let .zone(zone): return .some(zone)
        case .between, .away: return .some(nil)
        case .noFace: return nil
        }
    }

    // MARK: - Small rules

    /// The validation's score: the mean of the zones' (plan §8.4, step 6);
    /// 0 without a zone.
    static func score(_ zoneAccuracy: [String: Double]) -> Double {
        let values = zoneAccuracy.values.filter(\.isFinite)
        guard !values.isEmpty else { return 0 }
        return min(max(values.reduce(0, +) / Double(values.count), 0), 1)
    }

    /// How far a candidate's dwell has gone, 0…1.
    static func progress(since: TimeInterval, dwell: TimeInterval, now: TimeInterval) -> Double {
        guard dwell > 0 else { return 1 }
        return min(max((now - since) / dwell, 0), 1)
    }

    /// « Changer de mode »: Écrans → Zones → Fenêtres → Écrans.
    static func nextMode(after mode: ForkGlanceMode) -> ForkGlanceMode {
        let all = ForkGlanceMode.allCases
        let index = all.firstIndex(of: mode) ?? 0
        return all[(index + 1) % all.count]
    }

    /// The island lists 5 switches; a few more are kept for the spacious page.
    static let recentSwitchLimit = 10

    /// Newest first, bounded.
    static func appending<Record>(_ record: Record, to records: [Record]) -> [Record] {
        Array(([record] + records).prefix(recentSwitchLimit))
    }

    // MARK: - Command Bar (plan §11.5)

    enum BarRow: Equatable {
        case pause(ForkGlancePauseDuration)
        case resume
        case recenter
        case calibrate
        case mode(ForkGlanceMode)
        case settings
    }

    /// What keeps a row from doing its thing, as the official rows say it.
    enum BarTrouble: Equatable {
        /// Return opens the feature's page.
        case needsSetup
        /// Return runs anyway.
        case needsPermission
    }

    struct BarItem: Equatable {
        var row: BarRow
        var trouble: BarTrouble?
    }

    /// The pauses the bar offers (plan §11.5).
    static let barPauses: [ForkGlancePauseDuration] = [.fifteenMinutes, .oneHour, .untilResumed]

    /// The rows, in order. A person's pause shows « Reprendre » instead of
    /// the pauses; the modes are the two others. Off, every row answers to
    /// its name and opens the page; a missing permission marks « Recentrer »;
    /// without a calibration « Recentrer » opens the page, « Calibrer » works.
    static func barItems(enabled: Bool, phase: ForkGlancePhase, mode: ForkGlanceMode) -> [BarItem] {
        var rows: [BarRow] = []
        if case .paused(.user, _) = phase {
            rows.append(.resume)
        } else {
            rows += barPauses.map(BarRow.pause)
        }
        rows += [.recenter, .calibrate]
        rows += ForkGlanceMode.allCases.filter { $0 != mode }.map(BarRow.mode)
        rows.append(.settings)

        return rows.map { row in
            guard enabled else { return BarItem(row: row, trouble: row == .settings ? nil : .needsSetup) }
            guard row == .recenter else { return BarItem(row: row, trouble: nil) }
            switch phase {
            case .unavailable(.cameraPermission), .unavailable(.accessibilityPermission):
                return BarItem(row: row, trouble: .needsPermission)
            case .needsCalibration:
                return BarItem(row: row, trouble: .needsSetup)
            default:
                return BarItem(row: row, trouble: nil)
            }
        }
    }

    // MARK: - Report (plan §12.11 « Copier le rapport »)

    struct ReportInput {
        var appVersion: String
        var macModel: String
        var systemVersion: String
        var layout: ForkGlanceDisplayLayout
        /// « built-in », « external », « Continuity » or « none »: never the
        /// camera's name, which may carry a person's.
        var camera: String
        var settings: ForkGlanceSettings
        var profile: ForkGlanceProfile?
        var phase: ForkGlancePhase
        var cost: ForkGlanceCostMeter.Rate?
        var frameRate: Double
        var visionMean: TimeInterval
        var visionP95: TimeInterval
        var revisions: String
        var now: Date
    }

    /// A short English text, numbers only past the display names: what to
    /// paste in a message to tune the feature from afar.
    static func report(_ input: ReportInput) -> String {
        let posix = Locale(identifier: "en_US_POSIX")
        func number(_ value: Double, _ digits: Int = 1) -> String {
            String(format: "%.\(digits)f", locale: posix, value)
        }
        func size(_ rect: CGRect) -> String { "\(Int(rect.width))×\(Int(rect.height))" }
        let settings = input.settings
        var lines = ["Glance Focus report", "App: \(input.appVersion)",
                     "Mac: \(input.macModel) · \(input.systemVersion)"]

        lines.append("Displays: \(input.layout.displays.count)\(input.layout.lidClosed ? " (lid closed)" : "")")
        for display in input.layout.displays {
            var parts = ["\(display.name): \(size(display.frame)) at (\(Int(display.frame.minX)), \(Int(display.frame.minY)))"]
            if let millimeters = display.millimeters { parts.append("\(Int(millimeters.width))×\(Int(millimeters.height)) mm") }
            if display.isBuiltIn { parts.append("built-in") }
            if display.hasNotch { parts.append("notch") }
            if display.rotation != 0 { parts.append("rotated \(Int(display.rotation))°") }
            let split = input.profile?.splits[display.uuid]?.rawValue
            if let split { parts.append("split \(split)") }
            lines.append("  " + parts.joined(separator: ", "))
        }
        lines.append("Camera: \(input.camera)")
        lines.append("Mode: \(settings.mode.rawValue) · phase \(phaseName(input.phase))")

        if let profile = input.profile, let calibration = profile.calibration {
            let day = ISO8601DateFormatter.string(from: calibration.date, timeZone: .current,
                                                  formatOptions: [.withFullDate])
            let scoreText = calibration.zoneAccuracy.isEmpty ? "not validated"
                : "\(Int((score(calibration.zoneAccuracy) * 100).rounded())) %"
            lines.append("Calibration: \(day), \(calibration.usesEyes ? "head + eyes" : "head only"), "
                         + "σ \(Int(calibration.sigma.width))×\(Int(calibration.sigma.height)) pt, score \(scoreText), "
                         + "bias \(Int(calibration.bias.dx)), \(Int(calibration.bias.dy)) pt")
            let agreement = profile.learning.agreement.map { "\(Int(($0 * 100).rounded())) %" } ?? "none yet"
            lines.append("Learning: \(profile.learning.pairs.count) pairs, clicks agree \(agreement)")
        } else {
            lines.append("Calibration: none")
        }

        let idle = settings.idleOff.map { "\(Int($0)) s" } ?? "never"
        lines.append("Settings: sensitivity \(number(settings.sensitivity, 2)), dwell \(number(settings.dwell, 2)) s, "
                     + "typing \(number(settings.typingPause)) s, pointer \(number(settings.pointerPause)) s, "
                     + "raise \(settings.raise ? "on" : "off"), pointer \(settings.pointer.rawValue), "
                     + "feedback \(settings.feedback.rawValue), learn \(settings.learnFromClicks ? "on" : "off"), "
                     + "panes \(settings.panes ? "on" : "off")")
        lines.append("Energy: \(settings.energy.rawValue), battery \(settings.onBattery.rawValue), "
                     + "low power pause \(settings.pauseInLowPower ? "on" : "off"), camera off after \(idle), "
                     + "calls \(settings.duringCalls.rawValue)")
        if let cost = input.cost {
            let watts = cost.watts.map { ", \(number($0, 2)) W" } ?? ""
            lines.append("Cost: \(number(cost.cores * 100)) % of a core\(watts) (process)")
        }
        lines.append("Vision: \(input.revisions), \(number(input.visionMean * 1000)) ms mean, "
                     + "\(number(input.visionP95 * 1000)) ms p95, \(number(input.frameRate)) images/s")
        lines.append("Written: \(ISO8601DateFormatter.string(from: input.now, timeZone: .current, formatOptions: [.withInternetDateTime]))")
        return lines.joined(separator: "\n")
    }

    /// The phase's case, without the zone ids.
    static func phaseName(_ phase: ForkGlancePhase) -> String {
        switch phase {
        case .off: return "off"
        case let .unavailable(reason): return "unavailable(\(reason.rawValue))"
        case let .needsCalibration(need): return "needsCalibration(\(need.rawValue))"
        case .calibrating: return "calibrating"
        case let .paused(reason, _): return "paused(\(reason.rawValue))"
        case .starting: return "starting"
        case .searching: return "searching"
        case .away: return "away"
        case .settled: return "settled"
        case .candidate: return "candidate"
        case let .blocked(_, guards): return "blocked(\(guards.map(\.rawValue).joined(separator: ", ")))"
        case .cooldown: return "cooldown"
        }
    }
}

// MARK: - Pause persistence (plan §7.5, `fork.glance.pausedUntil`)

/// A person's pause outlives a relaunch: its end is kept on the wall clock
/// (the machine counts in `systemUptime`, which stops while the Mac sleeps),
/// and converted back at launch and at each wake.
enum ForkGlancePauseRules {
    /// The stored value of « jusqu'à reprise ».
    static let untilResumedValue = "forever"

    enum Stored: Equatable {
        case none
        case untilResumed
        case until(Date)
    }

    static func encode(_ stored: Stored) -> String {
        switch stored {
        case .none: return ""
        case .untilResumed: return untilResumedValue
        case let .until(date): return ISO8601DateFormatter().string(from: date)
        }
    }

    /// Anything unreadable is no pause: the feature must never stay off
    /// because of a stray value.
    static func decode(_ text: String?) -> Stored {
        let text = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return .none }
        if text == untilResumedValue { return .untilResumed }
        guard let date = ISO8601DateFormatter().date(from: text) else { return .none }
        return .until(date)
    }

    /// What a stored pause still means now: an end already passed is none.
    static func restored(_ stored: Stored, now: Date) -> Stored {
        if case let .until(date) = stored, date <= now { return .none }
        return stored
    }

    /// The machine's end (`systemUptime`) for a wall-clock end.
    static func uptime(of date: Date, now: Date, uptime: TimeInterval) -> TimeInterval {
        uptime + date.timeIntervalSince(now)
    }

    /// The wall-clock end for the machine's.
    static func date(ofUptime value: TimeInterval, now: Date, uptime: TimeInterval) -> Date {
        now.addingTimeInterval(value - uptime)
    }
}

// MARK: - Cost (plan §10.4)

/// The process's CPU and energy while the camera runs (`proc_pid_rusage`
/// readings, taken by the service every `interval`), over the last 5
/// minutes, less what the process cost before the camera started when that
/// was measured: « ≈ 2 % d'un cœur · ≈ 0,1 W ».
struct ForkGlanceCostMeter: Equatable {
    static let window: TimeInterval = 300
    /// Shorter than this, a rate says nothing.
    static let minimumSpan: TimeInterval = 20
    /// One reading this often.
    static let interval: TimeInterval = 10

    struct Reading: Equatable {
        /// `systemUptime`.
        var time: TimeInterval
        /// User + system CPU time, seconds.
        var cpuSeconds: Double
        /// `ri_energy_nj` in joules; nil when the system gives none.
        var energyJoules: Double?
    }

    struct Rate: Equatable {
        /// 0.02 = 2 % of a core.
        var cores: Double
        var watts: Double?
    }

    /// While the camera runs, oldest first.
    private(set) var readings: [Reading] = []
    /// The process before the camera started.
    private(set) var baseline: Rate?
    /// The feature on, the camera off: the baseline's start.
    private var idleFrom: Reading?

    init() {}

    /// The feature is up with the camera off (at start, and each time the camera stops).
    mutating func cameraOff(_ reading: Reading) {
        readings = []
        idleFrom = reading
    }

    /// The baseline is the rate from the camera's last stop (or the
    /// feature's start), when long enough.
    mutating func cameraOn(_ reading: Reading) {
        if let idleFrom, let rate = Self.rate(from: idleFrom, to: reading) { baseline = rate }
        idleFrom = nil
        readings = [reading]
    }

    /// A reading is due.
    func due(at time: TimeInterval) -> Bool {
        guard let last = readings.last else { return false }
        return time - last.time >= Self.interval
    }

    /// Keeps the readings of the last window, plus the one just before it.
    mutating func add(_ reading: Reading) {
        guard !readings.isEmpty else { return }
        readings.append(reading)
        let start = reading.time - Self.window
        if let firstInside = readings.firstIndex(where: { $0.time >= start }), firstInside > 1 {
            readings.removeFirst(firstInside - 1)
        }
    }

    /// The camera's cost, nil before `minimumSpan` of readings. Never below
    /// zero: the baseline is an estimate.
    var cost: Rate? {
        guard let first = readings.first, let last = readings.last, let rate = Self.rate(from: first, to: last) else {
            return nil
        }
        guard let baseline else { return rate }
        let watts: Double?
        if let total = rate.watts { watts = max(total - (baseline.watts ?? 0), 0) } else { watts = nil }
        return Rate(cores: max(rate.cores - baseline.cores, 0), watts: watts)
    }

    static func rate(from start: Reading, to end: Reading) -> Rate? {
        let span = end.time - start.time
        guard span >= minimumSpan, end.cpuSeconds >= start.cpuSeconds else { return nil }
        var watts: Double?
        if let startEnergy = start.energyJoules, let endEnergy = end.energyJoules, endEnergy >= startEnergy {
            watts = (endEnergy - startEnergy) / span
        }
        return Rate(cores: (end.cpuSeconds - start.cpuSeconds) / span, watts: watts)
    }
}
