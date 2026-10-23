// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import CoreGraphics
import Foundation

// The settings page's rules (plan §12), pure so the tests run them: how a
// mode suits the layout (§5.3), the calibration's score, the zones the map
// draws, the steps' and the cost's words, the diagnostics' lines (§12.11),
// the preview's landmarks, the map's geometry and the curves' history.

/// How a mode suits this layout and its calibration (plan §5.3, §12.4).
enum ForkGlanceModeFit: Sendable, Equatable {
    case suited
    /// Screens mode with a single display: the machine pauses (`singleScreen`).
    case singleScreen
    /// Windows mode with a σ over 8 % of a display's width: still choosable, marked.
    case lowPrecision
    /// Windows mode before any calibration says how precise the gaze is.
    case unknown
}

enum ForkGlanceSettingsRules {
    /// Windows mode wants the gaze within this share of a display's width (plan §5.3).
    static let windowsSigmaShare: CGFloat = 0.08

    // MARK: - Modes

    /// Zones always suit. Screens needs two displays. Windows needs a σ of at
    /// most 8 % of the narrowest display's width: the point must land inside
    /// a window there too.
    static func fit(_ mode: ForkGlanceMode, layout: ForkGlanceDisplayLayout,
                    calibration: ForkGlanceCalibration?) -> ForkGlanceModeFit {
        switch mode {
        case .zones:
            return .suited
        case .screens:
            return ForkGlanceZones.screensModePossible(layout) ? .suited : .singleScreen
        case .windows:
            guard let calibration else { return .unknown }
            let widths = layout.displays.map(\.frame.width).filter { $0 > 0 }
            guard let narrowest = widths.min() else { return .unknown }
            let sigma = calibration.sigma.width
            guard sigma.isFinite, sigma >= 0 else { return .lowPrecision }
            return sigma <= narrowest * windowsSigmaShare ? .suited : .lowPrecision
        }
    }

    /// The dwell ladder the slider edits: Screens mode has its own (plan §7.3).
    static func dwellTuning(for mode: ForkGlanceMode) -> ForkGlanceTuning {
        mode == .screens ? .dwellScreens : .dwell
    }

    // MARK: - Calibration

    /// The validation's score: the mean of its zones, nil before any validation.
    static func score(_ calibration: ForkGlanceCalibration?) -> Double? {
        guard let accuracy = calibration?.zoneAccuracy.values.filter(\.isFinite), !accuracy.isEmpty else { return nil }
        return min(1, max(0, accuracy.reduce(0, +) / Double(accuracy.count)))
    }

    static func grade(_ calibration: ForkGlanceCalibration?) -> ForkGlanceGrade? {
        score(calibration).map(ForkGlanceGrade.init(score:))
    }

    /// « Autres dispositions »: every profile but the current one, the most
    /// recently used first.
    static func otherProfiles(_ profiles: [ForkGlanceProfile], current: String?) -> [ForkGlanceProfile] {
        profiles.filter { $0.id != current }.sorted { $0.lastUsed > $1.lastUsed }
    }

    /// Each display's split: the profile's, else its default (plan §5.2).
    static func splits(profile: ForkGlanceProfile?, layout: ForkGlanceDisplayLayout) -> [String: ForkGlanceSplit] {
        var splits = ForkGlanceZones.defaultSplits(layout)
        for (uuid, split) in profile?.splits ?? [:] where splits[uuid] != nil { splits[uuid] = split }
        return splits
    }

    /// The zones the page's map draws. Screens and Zones come from the
    /// splits on the page, so a new split shows at once; Windows mode has
    /// only the service's live window zones.
    static func mapZones(mode: ForkGlanceMode, layout: ForkGlanceDisplayLayout, splits: [String: ForkGlanceSplit],
                         liveZones: [ForkGlanceZone]) -> [ForkGlanceZone] {
        mode == .windows ? liveZones : ForkGlanceZones.zones(layout: layout, mode: mode, splits: splits, windows: [])
    }

    // MARK: - Words for values

    /// « 120 ms », « 1,5 s », « 5 min » in the locale's own units; nil for
    /// an infinite value (the « Jamais » step says it in words).
    static func duration(_ seconds: TimeInterval, locale: Locale) -> String? {
        guard seconds.isFinite, seconds >= 0 else { return nil }
        if seconds < 1 {
            return Measurement(value: (seconds * 1000).rounded(), unit: UnitDuration.milliseconds)
                .formatted(.measurement(width: .abbreviated, usage: .asProvided,
                                        numberFormatStyle: .number.precision(.fractionLength(0)))
                    .locale(locale))
        }
        if seconds < 60 {
            return Measurement(value: seconds, unit: UnitDuration.seconds)
                .formatted(.measurement(width: .abbreviated, usage: .asProvided,
                                        numberFormatStyle: .number.precision(.fractionLength(0...1)))
                    .locale(locale))
        }
        return Measurement(value: (seconds / 60).rounded(), unit: UnitDuration.minutes)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided,
                                    numberFormatStyle: .number.precision(.fractionLength(0)))
                .locale(locale))
    }

    /// A step's value as the slider shows it; `never` for the last step of
    /// « Couper la caméra après ». The sensitivity has no unit to show: nil.
    static func stepValue(_ tuning: ForkGlanceTuning, step: Int, locale: Locale, never: String) -> String? {
        guard tuning != .sensitivity else { return nil }
        return duration(tuning.value(atStep: step), locale: locale) ?? never
    }

    /// The process's share of a core and its power (plan §10.4): « 2 % »
    /// (« 0,4 % » under one percent) and « 0,1 W ». Nil until measured.
    static func cost(cpuCores: Double?, watts: Double?, locale: Locale) -> (cpu: String, watts: String?)? {
        guard let cpuCores, cpuCores.isFinite, cpuCores >= 0 else { return nil }
        let digits = cpuCores < 0.01 ? 0...1 : 0...0
        let cpu = cpuCores.formatted(.percent.precision(.fractionLength(digits)).locale(locale))
        let power = watts.flatMap { value -> String? in
            guard value.isFinite, value >= 0 else { return nil }
            return Measurement(value: value, unit: UnitPower.watts)
                .formatted(.measurement(width: .abbreviated, usage: .asProvided,
                                        numberFormatStyle: .number.precision(.fractionLength(value < 1 ? 1...2 : 0...1)))
                    .locale(locale))
        }
        return (cpu, power)
    }

    static func number(_ value: Double, fractionDigits: Int, locale: Locale) -> String {
        guard value.isFinite else { return "–" }
        return value.formatted(.number.precision(.fractionLength(fractionDigits)).locale(locale))
    }

    // MARK: - Diagnostics (plan §12.11)

    /// The machine's phase in a few English words: a diagnostic label, read
    /// in a report, never translated.
    static func phaseLabel(_ phase: ForkGlancePhase, zoneName: (String) -> String? = { _ in nil }) -> String {
        func zone(_ id: String?) -> String { id.map { zoneName($0) ?? $0 } ?? "–" }
        switch phase {
        case .off: return "off"
        case .unavailable(let reason): return "unavailable · \(reason.rawValue)"
        case .needsCalibration(let need): return "needs calibration · \(need.rawValue)"
        case .calibrating: return "calibrating"
        case .paused(let reason, let until): return "paused · \(reason.rawValue)" + (until == nil ? "" : " · timed")
        case .starting: return "starting"
        case .searching: return "searching"
        case .away(let current): return "away · \(zone(current))"
        case .settled(let current): return "settled · \(zone(current))"
        case .candidate(let target, let current, _): return "candidate · \(zone(current)) → \(zone(target))"
        case .blocked(let current, let guards):
            return "blocked · \(zone(current)) · " + guards.map(\.rawValue).joined(separator: ", ")
        case .cooldown(let current, _): return "cooldown · \(zone(current))"
        }
    }

    /// « Safari 3 · Code 1 », the most failing first; nil when none failed.
    static func countsLine(_ counts: [String: Int]) -> String? {
        let listed = counts.filter { $0.value > 0 }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
        guard !listed.isEmpty else { return nil }
        return listed.map { "\($0.key) \($0.value)" }.joined(separator: " · ")
    }

    /// The apps still set aside at `now`, by name; nil when none.
    static func setAsideLine(_ setAside: [String: Date], now: Date) -> String? {
        let names = setAside.filter { $0.value > now }.keys.sorted()
        return names.isEmpty ? nil : names.joined(separator: " · ")
    }

    // MARK: - The camera preview's landmarks

    /// A point Vision gives (normalized, origin at the bottom left) where the
    /// preview draws it (unit square, origin at the top left). The preview is
    /// mirrored like a mirror, so x flips with it.
    static func previewPoint(_ point: CGPoint, mirrored: Bool) -> CGPoint {
        CGPoint(x: mirrored ? 1 - point.x : point.x, y: 1 - point.y)
    }

    static func previewRect(_ rect: CGRect, mirrored: Bool) -> CGRect {
        let x = mirrored ? 1 - rect.maxX : rect.minX
        return CGRect(x: x, y: 1 - rect.maxY, width: rect.width, height: rect.height)
    }
}

// MARK: - The diagnostics' table

/// What the diagnostics read from the service's live readings, pure so the
/// lines are tested (the live type itself lives with the service).
struct ForkGlanceDiagnosticReadings: Sendable, Equatable {
    var frameRate: Double
    var visionMean: TimeInterval
    var visionP95: TimeInterval
    var confidence: Double?
    var guards: [ForkGlanceGuard]
    var extraEntry: Double
    var setAside: [String: Date]
    var focusFailures: [String: Int]
    var clickAgreement: Double?
    var cpuCores: Double?
    var watts: Double?
    var revisions: String
}

/// One row of the diagnostics' table.
struct ForkGlanceDiagnosticLine: Sendable, Equatable, Identifiable {
    enum Item: String, Sendable, CaseIterable {
        case frameRate, vision, confidence, guards, phase, lastSwitch, focusFailures, clickAgreement,
             extraEntry, setAside, cost, revisions
    }

    var item: Item
    var label: String
    var value: String
    var id: Item { item }
}

extension ForkGlanceSettingsRules {
    /// The table, in the plan's order (§12.11). Values the camera has not
    /// given yet read « – »; a list with nothing in it reads « aucune ».
    static func diagnosticLines(_ readings: ForkGlanceDiagnosticReadings, phase: ForkGlancePhase,
                                lastSwitch: Date?, now: Date, locale: Locale,
                                text: ForkGlanceSettingsStrings, core: ForkGlanceStrings,
                                zoneName: (String) -> String? = { _ in nil }) -> [ForkGlanceDiagnosticLine] {
        let dash = "–"
        let rate = ForkGlanceStrings.fill(text.frameRateValue, number(readings.frameRate, fractionDigits: 1, locale: locale))
        let vision = ForkGlanceStrings.fill(text.visionValue,
                                            number(readings.visionMean * 1000, fractionDigits: 1, locale: locale),
                                            number(readings.visionP95 * 1000, fractionDigits: 1, locale: locale))
        let confidence = readings.confidence.map { ForkGlanceStrings.percent($0, locale: locale) } ?? dash
        let guards = readings.guards.isEmpty ? text.none : readings.guards.map(core.guardText).joined(separator: ", ")
        let last = lastSwitch.map { ForkGlanceStrings.relative($0, now: now, locale: locale) } ?? dash
        let agreement = readings.clickAgreement.map { ForkGlanceStrings.percent($0, locale: locale) } ?? dash
        let extra = ForkGlanceStrings.fill(text.extraEntryValue, number(readings.extraEntry, fractionDigits: 1, locale: locale))
        let cost = Self.cost(cpuCores: readings.cpuCores, watts: readings.watts, locale: locale).map { parts in
            parts.watts.map { ForkGlanceStrings.fill(text.costLine, parts.cpu, $0) }
                ?? ForkGlanceStrings.fill(text.costCPUOnly, parts.cpu)
        } ?? text.costMeasuring
        let rows: [(ForkGlanceDiagnosticLine.Item, String, String)] = [
            (.frameRate, text.rowFrameRate, rate),
            (.vision, text.rowVision, vision),
            (.confidence, text.rowConfidence, confidence),
            (.guards, text.rowGuards, guards),
            (.phase, text.rowPhase, phaseLabel(phase, zoneName: zoneName)),
            (.lastSwitch, text.rowLastSwitch, last),
            (.focusFailures, text.rowFocusFailures, countsLine(readings.focusFailures) ?? text.none),
            (.clickAgreement, text.rowClickAgreement, agreement),
            (.extraEntry, text.rowExtraEntry, extra),
            (.setAside, text.rowSetAside, setAsideLine(readings.setAside, now: now) ?? text.none),
            (.cost, text.costTitle, cost),
            (.revisions, text.rowRevisions, readings.revisions.isEmpty ? dash : readings.revisions),
        ]
        return rows.map { ForkGlanceDiagnosticLine(item: $0.0, label: $0.1, value: $0.2) }
    }
}

// MARK: - The map's geometry

/// The displays at the scale of their millimeters, placed as macOS arranges
/// them (plan §12.4), fitted in a canvas. Each display keeps its own scale
/// (points per millimeter differ between a Retina laptop and a large
/// monitor); a neighbor is placed against the edge it shares with an
/// already placed display, its offset along that edge measured in that
/// display's millimeters.
struct ForkGlanceMapGeometry: Equatable {
    struct Screen: Equatable, Identifiable {
        var display: ForkGlanceDisplay
        /// In the canvas.
        var rect: CGRect
        var id: String { display.uuid }
    }

    /// Millimeters per point when a display reports no size: about a 27"
    /// at 2560 pt, between a laptop's 0.2 and a large monitor's 0.24.
    static let fallbackScale: CGFloat = 0.22

    let screens: [Screen]
    /// The bounding box's width over its height (1.6 for no display).
    let aspect: CGFloat

    init(layout: ForkGlanceDisplayLayout, fitting canvas: CGSize, inset: CGFloat = 0) {
        let physical = Self.physicalRects(layout)
        let bounds = physical.reduce(CGRect.null) { $0.union($1.rect) }
        guard !physical.isEmpty, bounds.width > 0, bounds.height > 0 else {
            screens = []
            aspect = 1.6
            return
        }
        aspect = bounds.width / bounds.height
        let room = CGSize(width: max(0, canvas.width - 2 * inset), height: max(0, canvas.height - 2 * inset))
        let scale = min(room.width / bounds.width, room.height / bounds.height)
        let origin = CGPoint(x: inset + (room.width - bounds.width * scale) / 2,
                             y: inset + (room.height - bounds.height * scale) / 2)
        screens = physical.map { item in
            Screen(display: item.display,
                   rect: CGRect(x: origin.x + (item.rect.minX - bounds.minX) * scale,
                                y: origin.y + (item.rect.minY - bounds.minY) * scale,
                                width: item.rect.width * scale, height: item.rect.height * scale))
        }
    }

    /// The bounding box's width over its height, without a canvas.
    static func aspect(of layout: ForkGlanceDisplayLayout) -> CGFloat {
        ForkGlanceMapGeometry(layout: layout, fitting: CGSize(width: 100, height: 100)).aspect
    }

    /// A zone, proportionally inside its display's drawing.
    func rect(of zone: ForkGlanceZone) -> CGRect? {
        guard let screen = screens.first(where: { $0.display.uuid == zone.displayUUID }) else { return nil }
        let frame = screen.display.frame
        guard frame.width > 0, frame.height > 0 else { return nil }
        let part = zone.rect.intersection(frame)
        guard !part.isNull, part.width > 0, part.height > 0 else { return nil }
        return transform(part, from: frame, to: screen.rect)
    }

    /// A global point in the canvas, through the display it lies on, or the
    /// nearest one (a gaze just off the screens still shows where it went).
    func point(_ global: CGPoint) -> CGPoint? {
        guard global.x.isFinite, global.y.isFinite else { return nil }
        let screen = screens.first { $0.display.frame.contains(global) }
            ?? screens.min { Self.distance(global, $0.display.frame) < Self.distance(global, $1.display.frame) }
        guard let screen else { return nil }
        let frame = screen.display.frame
        guard frame.width > 0, frame.height > 0 else { return nil }
        return CGPoint(x: screen.rect.minX + (global.x - frame.minX) / frame.width * screen.rect.width,
                       y: screen.rect.minY + (global.y - frame.minY) / frame.height * screen.rect.height)
    }

    /// A size in global points around `global`, in the canvas (the σ ellipse).
    func size(_ size: CGSize, at global: CGPoint) -> CGSize? {
        let screen = screens.first { $0.display.frame.contains(global) }
            ?? screens.min { Self.distance(global, $0.display.frame) < Self.distance(global, $1.display.frame) }
        guard let screen, screen.display.frame.width > 0, screen.display.frame.height > 0 else { return nil }
        return CGSize(width: size.width / screen.display.frame.width * screen.rect.width,
                      height: size.height / screen.display.frame.height * screen.rect.height)
    }

    private func transform(_ rect: CGRect, from frame: CGRect, to drawn: CGRect) -> CGRect {
        CGRect(x: drawn.minX + (rect.minX - frame.minX) / frame.width * drawn.width,
               y: drawn.minY + (rect.minY - frame.minY) / frame.height * drawn.height,
               width: rect.width / frame.width * drawn.width,
               height: rect.height / frame.height * drawn.height)
    }

    // MARK: Millimeters

    private struct Physical {
        var display: ForkGlanceDisplay
        /// Millimeters per point, on each axis.
        var scale: CGSize
        /// Millimeters, in a space of the main display's origin.
        var rect: CGRect
    }

    private static func physicalRects(_ layout: ForkGlanceDisplayLayout) -> [Physical] {
        let displays = layout.displays.filter { $0.frame.width > 0 && $0.frame.height > 0 }
        guard !displays.isEmpty else { return [] }
        let known = displays.compactMap { display -> CGFloat? in
            guard let mm = oriented(display), mm.width > 0 else { return nil }
            return mm.width / display.frame.width
        }.sorted()
        let fallback = known.isEmpty ? fallbackScale : known[known.count / 2]

        func size(_ display: ForkGlanceDisplay) -> CGSize {
            if let mm = oriented(display), mm.width > 0, mm.height > 0 { return mm }
            return CGSize(width: display.frame.width * fallback, height: display.frame.height * fallback)
        }

        let mainIndex = displays.firstIndex { $0.frame.origin == .zero } ?? 0
        var remaining = displays
        let main = remaining.remove(at: mainIndex)
        let mainSize = size(main)
        var placed = [Physical(display: main,
                               scale: CGSize(width: mainSize.width / main.frame.width,
                                             height: mainSize.height / main.frame.height),
                               rect: CGRect(origin: .zero, size: mainSize))]
        while !remaining.isEmpty {
            // The display nearest to one already placed goes next, against it.
            var best: (index: Int, reference: Physical, gap: CGFloat)?
            for (index, display) in remaining.enumerated() {
                for reference in placed {
                    let gap = distance(display.frame, reference.display.frame)
                    if best == nil || gap < best!.gap { best = (index, reference, gap) }
                }
            }
            guard let best else { break }
            let display = remaining.remove(at: best.index)
            let mm = size(display)
            let reference = best.reference
            let frame = display.frame, refFrame = reference.display.frame
            let x = place(start: frame.minX, end: frame.maxX, refStart: refFrame.minX, refEnd: refFrame.maxX,
                          refMM: (reference.rect.minX, reference.rect.maxX), scale: reference.scale.width,
                          length: mm.width)
            let y = place(start: frame.minY, end: frame.maxY, refStart: refFrame.minY, refEnd: refFrame.maxY,
                          refMM: (reference.rect.minY, reference.rect.maxY), scale: reference.scale.height,
                          length: mm.height)
            placed.append(Physical(display: display,
                                   scale: CGSize(width: mm.width / frame.width, height: mm.height / frame.height),
                                   rect: CGRect(x: x, y: y, width: mm.width, height: mm.height)))
        }
        // Back in the layout's own order.
        return displays.compactMap { display in placed.first { $0.display == display } }
    }

    /// One axis: past the reference's end, before its start, or across it:
    /// flush with an edge both share (two displays aligned at the top stay
    /// so), otherwise centered where its center falls, in the reference's
    /// millimeters.
    private static func place(start: CGFloat, end: CGFloat, refStart: CGFloat, refEnd: CGFloat,
                              refMM: (CGFloat, CGFloat), scale: CGFloat, length: CGFloat) -> CGFloat {
        if start >= refEnd { return refMM.1 + (start - refEnd) * scale }
        if end <= refStart { return refMM.0 - (refStart - end) * scale - length }
        if abs(start - refStart) < 1 { return refMM.0 }
        if abs(end - refEnd) < 1 { return refMM.1 - length }
        return refMM.0 + ((start + end) / 2 - refStart) * scale - length / 2
    }

    /// The reported size, turned like the display when it reports the panel
    /// the other way round.
    private static func oriented(_ display: ForkGlanceDisplay) -> CGSize? {
        guard let mm = display.millimeters, mm.width > 0, mm.height > 0 else { return nil }
        let landscape = display.frame.width >= display.frame.height
        return (mm.width >= mm.height) == landscape ? mm : CGSize(width: mm.height, height: mm.width)
    }

    private static func distance(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let dx = max(0, max(lhs.minX - rhs.maxX, rhs.minX - lhs.maxX))
        let dy = max(0, max(lhs.minY - rhs.maxY, rhs.minY - lhs.maxY))
        return dx * dx + dy * dy
    }

    private static func distance(_ point: CGPoint, _ rect: CGRect) -> CGFloat {
        let dx = max(0, max(rect.minX - point.x, point.x - rect.maxX))
        let dy = max(0, max(rect.minY - point.y, point.y - rect.maxY))
        return dx * dx + dy * dy
    }
}

// MARK: - The curves

/// The last 10 s of head and eyes (plan §12.11): yaw and pitch in degrees,
/// the eyes as the pupils' mean horizontal place (0…1). Kept by the
/// diagnostics view while it is open, nowhere else.
struct ForkGlanceCurveHistory: Sendable, Equatable {
    static let window: TimeInterval = 10

    struct Point: Sendable, Equatable {
        var time: TimeInterval
        var yaw: Double?
        var pitch: Double?
        var eyes: Double?
    }

    enum Series: Sendable, CaseIterable {
        case yaw, pitch, eyes

        /// What fills the curve's height: ±45° for the head, 0…1 for the eyes.
        var range: ClosedRange<Double> {
            switch self {
            case .yaw, .pitch: return -45...45
            case .eyes: return 0...1
            }
        }
    }

    private(set) var points: [Point] = []

    /// Adds an image's readings; an image seen already, or older than the
    /// last, is ignored. Points past the window go.
    mutating func append(time: TimeInterval, observation: ForkGlanceObservation?, sample: ForkGlanceSample?) {
        guard time.isFinite else { return }
        if let last = points.last, time <= last.time { return }
        let degrees = 180 / Double.pi
        var eyes: Double?
        if let sample, sample.eyesUsable, sample.vector.count > ForkGlanceVectorLayout.rightEyeX {
            let left = sample.vector[ForkGlanceVectorLayout.leftEyeX]
            let right = sample.vector[ForkGlanceVectorLayout.rightEyeX]
            if left.isFinite, right.isFinite { eyes = (left + right) / 2 }
        }
        points.append(Point(time: time, yaw: observation?.yaw.map { $0 * degrees },
                            pitch: observation?.pitch.map { $0 * degrees }, eyes: eyes))
        let oldest = time - Self.window
        if let keep = points.firstIndex(where: { $0.time >= oldest }), keep > 0 { points.removeFirst(keep) }
    }

    /// A series in the unit square (x: time over the window ending at the
    /// last point, y: top = the range's top), cut where a value is missing.
    func segments(_ series: Series) -> [[CGPoint]] {
        guard let end = points.last?.time else { return [] }
        let range = series.range
        var segments: [[CGPoint]] = []
        var current: [CGPoint] = []
        for point in points {
            let value: Double?
            switch series {
            case .yaw: value = point.yaw
            case .pitch: value = point.pitch
            case .eyes: value = point.eyes
            }
            guard let value, value.isFinite else {
                if !current.isEmpty { segments.append(current) }
                current = []
                continue
            }
            let clamped = min(range.upperBound, max(range.lowerBound, value))
            let x = 1 - (end - point.time) / Self.window
            let y = 1 - (clamped - range.lowerBound) / (range.upperBound - range.lowerBound)
            current.append(CGPoint(x: x, y: y))
        }
        if !current.isEmpty { segments.append(current) }
        return segments
    }
}
