// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import CoreGraphics
import Foundation

/// The island's decisions about Glance Focus, apart from its views, so each
/// one is tested (plan §9, §11): when the closed island shows Glance and
/// where among its activities, what its wings read, what the « Regard »
/// section leads with and which controls its top row holds, what the tile
/// does, which notice gets which mark and mascot. Martial's decision D5 of
/// 23/10 is enforced here: by default the closed island shows only a pause
/// the person chose or a calibration, never an automatic pause.
enum ForkGlanceIslandRules {
    // MARK: - The closed island

    /// What the closed island shows of Glance.
    enum Activity: Equatable {
        /// A pause the person chose; its end on the wall clock, nil until resumed.
        case paused(until: Date?)
        /// The assistant collects its points.
        case calibrating(done: Int, total: Int)
        /// « Toujours (zone active) »: the zone the keyboard is in, nil before one is known.
        case watching(zoneID: String?)
    }

    /// The activity for this state, nil when the closed island shows nothing
    /// of Glance: the feature off, « Jamais », an automatic pause (plan §9),
    /// or a state with no zone while only pauses and calibrations show.
    /// `pausedUntil` is the service's wall-clock end of a timed pause (the
    /// phase carries systemUptime).
    static func activity(enabled: Bool, setting: ForkGlanceIslandClosed, phase: ForkGlancePhase,
                         pausedUntil: Date?, calibration: (done: Int, total: Int)?,
                         currentZone: String?) -> Activity? {
        guard enabled, setting != .never else { return nil }
        switch phase {
        case .paused(.user, let until):
            return .paused(until: until == nil ? nil : pausedUntil)
        case .paused:
            return nil
        case .calibrating:
            return .calibrating(done: max(0, calibration?.done ?? 0), total: max(0, calibration?.total ?? 0))
        default:
            guard setting == .always, phase.isWatching else { return nil }
            return .watching(zoneID: currentZone ?? zone(of: phase))
        }
    }

    /// The zone the keyboard is in, as the phase knows it.
    static func zone(of phase: ForkGlancePhase) -> String? {
        switch phase {
        case .away(let zone), .settled(let zone), .blocked(let zone, _), .cooldown(let zone, _): return zone
        case .candidate(_, let current, _): return current
        case .off, .unavailable, .needsCalibration, .calibrating, .paused, .starting, .searching: return nil
        }
    }

    /// Glance goes after the music and before Keep Awake (plan §11.2): a
    /// pause is worth knowing, less than a timer, a meeting or a song, more
    /// than a Mac kept awake. Never listed twice.
    static func ordered(_ activities: [NotchCompactActivity], showing: Bool) -> [NotchCompactActivity] {
        var list = activities.filter { $0 != .glance }
        guard showing else { return list }
        list.insert(.glance, at: list.firstIndex(of: .keepAwake) ?? list.count)
        return list
    }

    /// The mark left of the camera (plan §2).
    static func symbol(_ activity: Activity) -> String {
        switch activity {
        case .paused: return "eye.slash"
        case .calibrating: return "viewfinder"
        case .watching: return "eyes"
        }
    }

    /// What the right of the camera reads.
    enum Reading: Equatable {
        /// Digits: « 14m », « 1h05 », « 12/30 ».
        case text(String)
        /// A pause until resumed: `infinity`, as Keep Awake without an end.
        case symbol(String)
        /// The zones of the display looked at, the active one filled.
        case glyph
    }

    static let openSymbol = "infinity"

    /// The minutes of a timed pause in the timer strip's shapes (« 14m »,
    /// « 1h05 »), like Keep Awake's; the calibration's points.
    static func reading(_ activity: Activity, now: Date, locale: Locale) -> Reading {
        switch activity {
        case .paused(let until):
            guard let until else { return .symbol(openSymbol) }
            return .text(NotchKeepAwakeSupport.compactText(until: until, now: now, locale: locale))
        case .calibrating(let done, let total):
            return .text(total > 0 ? ForkGlanceStrings.progress(done: done, total: total) : "…")
        case .watching:
            return .glyph
        }
    }

    /// The reading's text, for measuring the wings and the capsule; the
    /// glyph and the symbol are measured as drawn.
    static func readingText(_ reading: Reading) -> String? {
        if case .text(let text) = reading { return text }
        return nil
    }

    /// The zone glyph's box, points (plan §11.2).
    static let glyphSize = CGSize(width: 16, height: 10)

    /// One zone in the glyph: its place in a unit box (origin at the top left).
    struct GlyphCell: Equatable {
        var rect: CGRect
        var active: Bool
    }

    /// The zones of the display the active zone is on (else the first one),
    /// each as a share of that display; the whole box when it has none.
    static func glyph(zones: [ForkGlanceZone], layout: ForkGlanceDisplayLayout, active: String?) -> [GlyphCell] {
        let activeZone = zones.first { $0.id == active }
        let uuid = activeZone?.displayUUID ?? layout.displays.first?.uuid ?? zones.first?.displayUUID
        guard let uuid else { return [GlyphCell(rect: CGRect(x: 0, y: 0, width: 1, height: 1), active: false)] }
        let frame = layout.displays.first { $0.uuid == uuid }?.frame
            ?? zones.filter { $0.displayUUID == uuid }.map(\.rect).reduce(CGRect.null) { $0.union($1) }
        let own = zones.filter { $0.displayUUID == uuid }
        guard frame.width > 0, frame.height > 0, !own.isEmpty else {
            return [GlyphCell(rect: CGRect(x: 0, y: 0, width: 1, height: 1), active: activeZone != nil)]
        }
        return own.map { zone in
            let rect = zone.rect.intersection(frame)
            let unit = rect.isNull ? .zero : CGRect(x: (rect.minX - frame.minX) / frame.width,
                                                     y: (rect.minY - frame.minY) / frame.height,
                                                     width: rect.width / frame.width, height: rect.height / frame.height)
            return GlyphCell(rect: unit, active: zone.id == active)
        }
    }

    // MARK: - The section

    /// What the « Regard » section leads with (plan §9).
    enum Top: Equatable {
        case off
        /// A permission, or the camera: an empty state with its next step.
        case unavailable(ForkGlanceUnavailable)
        case needsCalibration(ForkGlanceCalibrationNeed)
        case calibrating
        case paused(ForkGlancePauseReason)
        /// Starting, watching, waiting on a guard or looking away: the map.
        case watching
    }

    static func top(_ phase: ForkGlancePhase) -> Top {
        switch phase {
        case .off: return .off
        case .unavailable(let reason): return .unavailable(reason)
        case .needsCalibration(let need): return .needsCalibration(need)
        case .calibrating: return .calibrating
        case .paused(let reason, _): return .paused(reason)
        case .starting, .searching, .away, .settled, .candidate, .blocked, .cooldown: return .watching
        }
    }

    /// The map of the displays shows, or an empty state takes the page.
    static func showsMap(_ top: Top) -> Bool {
        switch top {
        case .off, .unavailable: return false
        case .needsCalibration, .calibrating, .paused, .watching: return true
        }
    }

    /// The band over the map: the one thing the state asks for.
    enum Banner: Equatable {
        /// « En pause · 14 min » + Reprendre; nil until resumed.
        case paused(until: Date?)
        /// A battery, Low Power or thermal pause: « Reprendre quand même ».
        case resumeAnyway(ForkGlancePauseReason)
        /// « Le regard se trompe souvent » + Recalibrer.
        case drift
        /// The displays moved since the calibration + Recalibrer.
        case layoutMoved
        /// No profile for this layout yet + Calibrer.
        case calibrate(ForkGlanceCalibrationNeed)
    }

    static func banner(_ top: Top, pausedUntil: Date?, driftSuggested: Bool, layoutMoved: Bool) -> Banner? {
        switch top {
        case .paused(.user): return .paused(until: pausedUntil)
        case .paused(let reason): return reason.canResumeAnyway ? .resumeAnyway(reason) : nil
        case .needsCalibration(let need): return .calibrate(need)
        case .watching:
            if layoutMoved { return .layoutMoved }
            return driftSuggested ? .drift : nil
        case .off, .unavailable, .calibrating: return nil
        }
    }

    /// The pause control in the top row; a pause the person chose has its
    /// Reprendre in the pause banner.
    enum PauseControl: Equatable {
        /// « Pause ▾ »: 15 min, 1 h, until tomorrow, until resumed.
        case menu
        case none
    }

    /// The section's top row: modes on the left; on the right Recenter, the
    /// pause, and the way to the feature's page.
    struct Band: Equatable {
        var modes: Bool
        var recenter: Bool
        var pause: PauseControl
        var settings: Bool
    }

    static func band(_ top: Top) -> Band {
        switch top {
        // The empty state's own button leads to the page.
        case .off: return Band(modes: false, recenter: false, pause: .none, settings: false)
        case .unavailable: return Band(modes: false, recenter: false, pause: .none, settings: true)
        case .needsCalibration: return Band(modes: true, recenter: false, pause: .none, settings: true)
        case .calibrating: return Band(modes: false, recenter: false, pause: .none, settings: true)
        // The pause banner holds Reprendre: the top row does not repeat it.
        case .paused(.user): return Band(modes: true, recenter: false, pause: .none, settings: true)
        case .paused: return Band(modes: true, recenter: false, pause: .menu, settings: true)
        case .watching: return Band(modes: true, recenter: true, pause: .menu, settings: true)
        }
    }

    /// The pause menu's choices, in the section and the page.
    static let pauseChoices: [ForkGlancePauseDuration] = [.fifteenMinutes, .oneHour, .untilTomorrow, .untilResumed]

    /// The section's height: the island's compact budget (180 pt) holds
    /// the map and its lines, the spacious one (264 pt) the last switches too.
    static let sectionHeight: Double = 264

    /// From this page height, the section adds the last switches and the
    /// Calibrate and Test buttons.
    static func isSpacious(height: Double) -> Bool { height >= 230 }

    /// The calibration's score: the share of validation hits over its zones.
    static func score(_ calibration: ForkGlanceCalibration?) -> Double? {
        guard let values = calibration?.zoneAccuracy.values, !values.isEmpty else { return nil }
        let total = values.reduce(0) { $0 + min(1, max(0, $1.isFinite ? $1 : 0)) }
        return total / Double(values.count)
    }

    /// « Dernières bascules »: the latest first, five at most.
    static func history<Record>(_ records: [Record], date: (Record) -> Date, limit: Int = 5) -> [Record] {
        Array(records.sorted { date($0) > date($1) }.prefix(max(0, limit)))
    }

    /// The status line under the map, unless the band over it already says
    /// the state (a pause, a calibration to make).
    static func showsStatus(banner: Banner?) -> Bool {
        switch banner {
        case .paused, .resumeAnyway, .calibrate: return false
        case .drift, .layoutMoved, nil: return true
        }
    }

    /// The zone the map fills: only while the keyboard follows, never while
    /// the camera starts (« zones grises », plan §9).
    static func mapActiveZone(_ phase: ForkGlancePhase, current: String?) -> String? {
        guard top(phase) == .watching, phase != .starting else { return nil }
        return current ?? zone(of: phase)
    }

    /// The map is dimmed while nothing follows the gaze.
    static func mapDimmed(_ top: Top) -> Bool { top != .watching }

    /// The mode buttons' marks (plan §2).
    static func symbol(for mode: ForkGlanceMode) -> String {
        switch mode {
        case .screens: return "display.2"
        case .zones: return "rectangle.split.2x1"
        case .windows: return "macwindow.on.rectangle"
        }
    }

    /// The live gaze dot asks the service for readings only with its option
    /// on, outside the Settings preview, while the map watches.
    static func holdsLiveLease(liveDot: Bool, preview: Bool, top: Top) -> Bool {
        liveDot && !preview && top == .watching
    }

    // MARK: - The tile

    enum TileAction: Equatable {
        case pause
        case resume
        /// No profile for this layout: the assistant (plan §9).
        case calibrate
        /// Off, a permission, a calibration running, an automatic pause:
        /// the section says what to do.
        case openSection
    }

    /// The Controls tile and its button around the island: Pause « jusqu'à
    /// reprise » ↔ Reprendre (plan §11.3).
    static func tileAction(_ phase: ForkGlancePhase) -> TileAction {
        switch phase {
        case .paused(.user, _): return .resume
        case .needsCalibration: return .calibrate
        case .off, .unavailable, .calibrating, .paused: return .openSection
        case .starting, .searching, .away, .settled, .candidate, .blocked, .cooldown: return .pause
        }
    }

    // MARK: - Notices

    /// Each notice follows its switch (`fork.glance.notice.<kind>`); a switch
    /// never set reads its default (all on but « Recentré »).
    static func isOn(_ stored: Any?, kind: ForkGlanceNoticeKind) -> Bool {
        (stored as? Bool) ?? kind.defaultOn
    }

    static func symbol(for notice: ForkGlanceNotice) -> String {
        switch notice {
        case .paused: return "eye.slash"
        case .resumed: return "eyes"
        case .newLayout: return "display.2"
        case .cameraUnavailable: return "video.slash"
        case .recentered: return "scope"
        case .calibrated: return "checkmark.circle"
        case .drift: return "viewfinder"
        }
    }

    /// The switch's mark in the Activity tab's card.
    static func symbol(for kind: ForkGlanceNoticeKind) -> String {
        switch kind {
        case .pause: return symbol(for: ForkGlanceNotice.paused(until: nil))
        case .newLayout: return symbol(for: ForkGlanceNotice.newLayout)
        case .camera: return symbol(for: ForkGlanceNotice.cameraUnavailable)
        case .recenter: return symbol(for: ForkGlanceNotice.recentered)
        case .calibrated: return symbol(for: ForkGlanceNotice.calibrated(score: 1))
        case .drift: return symbol(for: ForkGlanceNotice.drift)
        }
    }

    /// The companion's reaction (plan §11.7), through the island's own API.
    static func mascot(for notice: ForkGlanceNotice) -> NotchMascotReaction? {
        switch notice {
        case .calibrated: return .celebrate
        case .drift: return .confused
        case .paused: return .hush
        case .resumed, .newLayout, .cameraUnavailable, .recentered: return nil
        }
    }

    // MARK: - The Settings preview

    /// Two made-up displays for the island's Content tab: nothing is read
    /// from the Mac (plan §11.1). An ultra-wide 34" over a MacBook.
    static let previewLayout = ForkGlanceDisplayLayout(displays: [
        ForkGlanceDisplay(uuid: "preview-wide", name: "LG HDR WQHD", frame: CGRect(x: 0, y: 0, width: 3440, height: 1440),
                          millimeters: CGSize(width: 816, height: 338)),
        ForkGlanceDisplay(uuid: "preview-builtin", name: "MacBook", frame: CGRect(x: 856, y: 1440, width: 1728, height: 1117),
                          millimeters: CGSize(width: 344, height: 222), isBuiltIn: true, hasNotch: true),
    ])

    static var previewZones: [ForkGlanceZone] {
        ForkGlanceZones.zones(layout: previewLayout, mode: .zones, splits: [:], windows: [])
    }

    /// The left half of the wide display.
    static var previewActiveZone: String? { previewZones.first?.id }
}
