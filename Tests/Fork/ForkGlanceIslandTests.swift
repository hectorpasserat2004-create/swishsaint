// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import CoreGraphics
import Foundation

/// Suite `fork-glance-island` — B4: the island's pure rules (plan §9, §11)
/// and its strings (plan §16).
enum ForkGlanceIslandTests {
    private typealias Rules = ForkGlanceIslandRules

    private static let end = Date(timeIntervalSince1970: 1_792_000_000)
    private static let wide = ForkGlanceDisplay(uuid: "LG", name: "LG HDR WQHD",
                                                frame: CGRect(x: 0, y: 0, width: 3440, height: 1440))
    private static let builtIn = ForkGlanceDisplay(uuid: "MB", name: "MacBook",
                                                   frame: CGRect(x: 856, y: 1440, width: 1728, height: 1117),
                                                   isBuiltIn: true, hasNotch: true)
    private static let layout = ForkGlanceDisplayLayout(displays: [wide, builtIn])
    private static let zones = ForkGlanceZones.zones(layout: layout, mode: .zones, splits: [:], windows: [])

    static func run(_ suite: TestSuite) {
        closedIsland(suite)
        order(suite)
        readings(suite)
        glyph(suite)
        section(suite)
        tile(suite)
        notices(suite)
        lines(suite)
        strings(suite)
    }

    // MARK: - The closed island

    private static func activity(_ phase: ForkGlancePhase, setting: ForkGlanceIslandClosed = .paused,
                                 enabled: Bool = true, pausedUntil: Date? = nil,
                                 calibration: (done: Int, total: Int)? = nil,
                                 currentZone: String? = nil) -> Rules.Activity? {
        Rules.activity(enabled: enabled, setting: setting, phase: phase, pausedUntil: pausedUntil,
                       calibration: calibration, currentZone: currentZone)
    }

    private static func closedIsland(_ suite: TestSuite) {
        suite.expect(activity(.paused(.user, until: 900), pausedUntil: end) == .paused(until: end),
                     "a timed pause the person chose shows with its end, by default (D5)")
        suite.expect(activity(.paused(.user, until: nil)) == .paused(until: nil),
                     "a pause until resumed shows without an end")
        suite.expect(activity(.paused(.user, until: nil), pausedUntil: end) == .paused(until: nil),
                     "a stale end is not read for a pause until resumed")
        suite.expect(activity(.calibrating, calibration: (12, 30)) == .calibrating(done: 12, total: 30),
                     "a calibration shows its points")
        suite.expect(activity(.calibrating) == .calibrating(done: 0, total: 0), "a calibration before its first point")
        for reason in ForkGlancePauseReason.allCases where reason != .user {
            suite.expect(activity(.paused(reason, until: nil), setting: .always) == nil,
                         "an automatic pause never shows in the closed island: \(reason)")
        }
        suite.expect(activity(.settled(zone: "LG#0")) == nil, "watching shows nothing while only pauses show")
        suite.expect(activity(.settled(zone: "LG#0"), setting: .always) == .watching(zoneID: "LG#0"),
                     "« Toujours » shows the zone the keyboard is in")
        suite.expect(activity(.candidate(zone: "LG#1", current: "LG#0", since: 1), setting: .always)
                     == .watching(zoneID: "LG#0"), "a candidate is not the zone yet")
        suite.expect(activity(.settled(zone: "LG#0"), setting: .always, currentZone: "MB#0") == .watching(zoneID: "MB#0"),
                     "the service's current zone wins over the phase's")
        suite.expect(activity(.starting, setting: .always) == .watching(zoneID: nil),
                     "« Toujours » while the camera starts: no zone yet")
        for phase: ForkGlancePhase in [.off, .unavailable(.cameraPermission), .needsCalibration(.firstTime)] {
            suite.expect(activity(phase, setting: .always) == nil, "nothing to show while not ready: \(phase)")
        }
        suite.expect(activity(.paused(.user, until: nil), setting: .never) == nil, "« Jamais » shows nothing")
        suite.expect(activity(.calibrating, setting: .never) == nil, "« Jamais » hides a calibration too")
        suite.expect(activity(.paused(.user, until: nil), enabled: false) == nil, "the feature off shows nothing")
    }

    private static func order(_ suite: TestSuite) {
        let official: [NotchCompactActivity] = [.timer, .downloads, .music, .keepAwake]
        suite.expect(Rules.ordered(official, showing: true) == [.timer, .downloads, .music, .glance, .keepAwake],
                     "Glance goes after the music, before Keep Awake")
        suite.expect(Rules.ordered([.meeting, .timer, .macBackup], showing: true) == [.meeting, .timer, .macBackup, .glance],
                     "without Keep Awake, Glance comes last")
        suite.expect(Rules.ordered([], showing: true) == [.glance], "alone, it is the activity")
        suite.expect(Rules.ordered([.glance, .music, .keepAwake], showing: true) == [.music, .glance, .keepAwake],
                     "never listed twice")
        suite.expect(Rules.ordered([.glance, .music], showing: false) == [.music], "not showing, it leaves the list")
        suite.expect(Rules.ordered(official, showing: false) == official, "not showing, the others keep their order")
    }

    private static func readings(_ suite: TestSuite) {
        let locale = Locale(identifier: "en-US")
        let now = end.addingTimeInterval(-14 * 60)
        if case .text(let left) = Rules.reading(.paused(until: end), now: now, locale: locale) {
            suite.expect(left.contains("14"), "a timed pause reads its minutes left: \(left)")
        } else {
            suite.expect(false, "a timed pause reads digits")
        }
        suite.expect(Rules.reading(.paused(until: nil), now: now, locale: locale) == .symbol("infinity"),
                     "a pause until resumed reads ∞, as Keep Awake")
        suite.expect(Rules.reading(.calibrating(done: 12, total: 30), now: now, locale: locale) == .text("12/30"),
                     "a calibration reads « 12/30 »")
        suite.expect(Rules.reading(.calibrating(done: 0, total: 0), now: now, locale: locale) == .text("…"),
                     "a calibration before its plan reads an ellipsis, never 0/0")
        suite.expect(Rules.reading(.watching(zoneID: nil), now: now, locale: locale) == .glyph, "always: the zone glyph")
        suite.expect(Rules.symbol(.paused(until: nil)) == "eye.slash" && Rules.symbol(.calibrating(done: 0, total: 1))
                     == "viewfinder" && Rules.symbol(.watching(zoneID: nil)) == "eyes", "each activity has its mark (plan §2)")
        suite.expect(Rules.readingText(.text("12/30")) == "12/30" && Rules.readingText(.glyph) == nil,
                     "only digits are measured as text")
    }

    private static func glyph(_ suite: TestSuite) {
        let right = Rules.glyph(zones: zones, layout: layout, active: "LG#1")
        suite.expect(right.count == 2, "the wide display's two halves")
        suite.expect(right.map(\.active) == [false, true], "the right half is filled")
        suite.expect(right.first.map { abs($0.rect.width - 0.5) < 0.001 && $0.rect.minX == 0 } == true,
                     "each half is half of the glyph")
        suite.expect(right.last.map { abs($0.rect.minX - 0.5) < 0.001 && abs($0.rect.height - 1) < 0.001 } == true,
                     "the right half starts at the middle and fills the height")
        let builtInCells = Rules.glyph(zones: zones, layout: layout, active: "MB#0")
        suite.expect(builtInCells == [Rules.GlyphCell(rect: CGRect(x: 0, y: 0, width: 1, height: 1), active: true)],
                     "the MacBook, whole, fills the glyph")
        let none = Rules.glyph(zones: zones, layout: layout, active: nil)
        suite.expect(none.count == 2 && none.allSatisfy { !$0.active }, "no zone yet: the first display, empty")
        let empty = Rules.glyph(zones: [], layout: ForkGlanceDisplayLayout(displays: []), active: nil)
        suite.expect(empty.count == 1 && !empty[0].active, "no display: one empty cell, never nothing")
    }

    // MARK: - The section

    private static func section(_ suite: TestSuite) {
        suite.expect(Rules.top(.off) == .off, "off: the empty state")
        suite.expect(Rules.top(.unavailable(.cameraPermission)) == .unavailable(.cameraPermission), "a permission")
        for phase: ForkGlancePhase in [.starting, .searching, .away(zone: nil), .settled(zone: "LG#0"),
                                       .candidate(zone: "LG#1", current: "LG#0", since: 0),
                                       .blocked(zone: nil, guards: [.typing]), .cooldown(zone: nil, until: 1)] {
            suite.expect(Rules.top(phase) == .watching, "the map leads while watching: \(phase)")
        }
        suite.expect(!Rules.showsMap(.off) && !Rules.showsMap(.unavailable(.noCamera)), "no map without a camera")
        suite.expect(Rules.showsMap(.needsCalibration(.newLayout)), "a new layout shows its map, then « Calibrer »")

        suite.expect(Rules.banner(.paused(.user), pausedUntil: end, driftSuggested: true, layoutMoved: false)
                     == .paused(until: end), "a pause the person chose: its band, before anything else")
        suite.expect(Rules.banner(.paused(.battery), pausedUntil: nil, driftSuggested: false, layoutMoved: false)
                     == .resumeAnyway(.battery), "a battery pause offers « Reprendre quand même »")
        suite.expect(Rules.banner(.paused(.locked), pausedUntil: nil, driftSuggested: false, layoutMoved: false) == nil,
                     "a locked Mac offers nothing")
        suite.expect(Rules.banner(.watching, pausedUntil: nil, driftSuggested: true, layoutMoved: false) == .drift,
                     "a drift asks for a recalibration")
        suite.expect(Rules.banner(.watching, pausedUntil: nil, driftSuggested: true, layoutMoved: true) == .layoutMoved,
                     "moved displays come before a drift")
        suite.expect(Rules.banner(.needsCalibration(.firstTime), pausedUntil: nil, driftSuggested: false, layoutMoved: false)
                     == .calibrate(.firstTime), "no profile yet: « Calibrer »")
        suite.expect(Rules.banner(.calibrating, pausedUntil: nil, driftSuggested: true, layoutMoved: true) == nil,
                     "nothing over a calibration running")
        suite.expect(!Rules.showsStatus(banner: .paused(until: nil)) && Rules.showsStatus(banner: .drift)
                     && Rules.showsStatus(banner: nil), "the status line is never said twice")

        let watching = Rules.band(.watching)
        suite.expect(watching == Rules.Band(modes: true, recenter: true, pause: .menu, settings: true),
                     "watching: modes, Recenter, Pause ▾ and the page")
        suite.expect(Rules.band(.paused(.user)).pause == .none && !Rules.band(.paused(.user)).recenter
                        && Rules.banner(.paused(.user), pausedUntil: nil, driftSuggested: false, layoutMoved: false)
                        == .paused(until: nil),
                     "paused by the person: Resume once, in the pause banner, and nothing to recenter")
        suite.expect(Rules.band(.paused(.thermal)).pause == .menu, "an automatic pause still takes a pause of one's own")
        suite.expect(Rules.band(.off) == Rules.Band(modes: false, recenter: false, pause: .none, settings: false),
                     "off: only the empty state's button")
        suite.expect(!Rules.band(.unavailable(.cameraPermission)).modes && Rules.band(.unavailable(.noCamera)).settings,
                     "a missing camera: only the way to the page")
        suite.expect(Rules.pauseChoices == [.fifteenMinutes, .oneHour, .untilTomorrow, .untilResumed],
                     "the pause menu's four choices (plan §11.1)")

        suite.expect(Rules.mapActiveZone(.settled(zone: "LG#0"), current: nil) == "LG#0", "the map fills the zone")
        suite.expect(Rules.mapActiveZone(.starting, current: "LG#0") == nil, "starting: grey zones")
        suite.expect(Rules.mapActiveZone(.paused(.user, until: nil), current: "LG#0") == nil, "paused: no zone filled")
        suite.expect(Rules.mapDimmed(.calibrating) && !Rules.mapDimmed(.watching), "the map dims while nothing follows")
        suite.expect(Rules.holdsLiveLease(liveDot: true, preview: false, top: .watching), "the dot asks for readings")
        suite.expect(!Rules.holdsLiveLease(liveDot: false, preview: false, top: .watching), "only with its option on")
        suite.expect(!Rules.holdsLiveLease(liveDot: true, preview: true, top: .watching), "never in the Settings preview")
        suite.expect(!Rules.holdsLiveLease(liveDot: true, preview: false, top: .paused(.user)), "never while paused")
        suite.expect(Rules.isSpacious(height: 264) && !Rules.isSpacious(height: 180),
                     "the spacious island adds the last switches, the compact one does not")
        suite.expect(Rules.sectionHeight == 264, "the section never grows past the spacious budget")
        suite.expect(Set(ForkGlanceMode.allCases.map(Rules.symbol(for:))).count == 3, "each mode has its own mark")
    }

    // MARK: - The tile

    private static func tile(_ suite: TestSuite) {
        suite.expect(Rules.tileAction(.settled(zone: "LG#0")) == .pause, "watching: a click pauses")
        suite.expect(Rules.tileAction(.blocked(zone: nil, guards: [.typing])) == .pause, "a guard holding: still pauses")
        suite.expect(Rules.tileAction(.paused(.user, until: 30)) == .resume, "paused by the person: a click resumes")
        suite.expect(Rules.tileAction(.paused(.battery, until: nil)) == .openSection,
                     "an automatic pause: the section says why")
        suite.expect(Rules.tileAction(.needsCalibration(.newLayout)) == .calibrate, "a calibration missing: the assistant")
        suite.expect(Rules.tileAction(.unavailable(.accessibilityPermission)) == .openSection, "a permission: the section")
        suite.expect(Rules.tileAction(.calibrating) == .openSection, "a calibration running is not paused")
    }

    // MARK: - Notices

    private static func notices(_ suite: TestSuite) {
        for kind in ForkGlanceNoticeKind.allCases {
            suite.expect(Rules.isOn(nil, kind: kind) == (kind != .recenter),
                         "a switch never set reads its default: every notice but « Recentré » (\(kind))")
            suite.expect(!Rules.isOn(false, kind: kind) && Rules.isOn(true, kind: kind), "the person's choice wins: \(kind)")
        }
        suite.expect(Rules.isOn("yes", kind: .drift), "an unreadable value reads the default")
        suite.expect(Rules.mascot(for: .calibrated(score: 0.97)) == .celebrate, "a calibration made: the companion cheers")
        suite.expect(Rules.mascot(for: .drift) == .confused, "a drift: the companion is puzzled")
        suite.expect(Rules.mascot(for: .paused(until: nil)) == .hush, "a pause: the companion hushes")
        suite.expect(Rules.mascot(for: .resumed) == nil && Rules.mascot(for: .newLayout) == nil,
                     "the other notices leave the companion be")
        let notices: [ForkGlanceNotice] = [.paused(until: nil), .resumed, .newLayout, .cameraUnavailable, .recentered,
                                           .calibrated(score: 1), .drift]
        suite.expect(notices.allSatisfy { !Rules.symbol(for: $0).isEmpty }, "every notice has a mark")
        suite.expect(Rules.symbol(for: ForkGlanceNotice.paused(until: nil)) != Rules.symbol(for: ForkGlanceNotice.resumed),
                     "a pause and a resume look apart")
        suite.expect(Rules.symbol(for: ForkGlanceNoticeKind.pause) == Rules.symbol(for: ForkGlanceNotice.paused(until: nil)),
                     "a switch wears its notice's mark")
    }

    // MARK: - Lines

    private static func lines(_ suite: TestSuite) {
        func calibration(_ accuracy: [String: Double]) -> ForkGlanceCalibration {
            ForkGlanceCalibration(version: 1, date: end, cameraID: "", layoutSignature: "", usesEyes: false,
                                  coefficientsX: [], coefficientsY: [], normalization: [], sigma: .zero, bias: .zero,
                                  yawRange: 0...0, pitchRange: 0...0, zoneAccuracy: accuracy)
        }
        suite.expectClose(Rules.score(calibration(["a": 1, "b": 0.94])) ?? -1, 0.97, "the score is the zones' mean")
        suite.expect(Rules.score(calibration([:])) == nil, "no validation yet: no score")
        suite.expect(Rules.score(nil) == nil, "no calibration: no score")
        suite.expectClose(Rules.score(calibration(["a": 1.4, "b": .nan])) ?? -1, 0.5, "a score never reads past its bounds")

        let dates = (0..<8).map { end.addingTimeInterval(TimeInterval($0) * 60) }
        let latest = Rules.history(dates.shuffled(), date: { $0 })
        suite.expect(latest == Array(dates.reversed().prefix(5)), "the last five switches, the latest first")
        suite.expect(Rules.history(dates, date: { $0 }, limit: 0).isEmpty, "a limit of none lists none")
    }

    // MARK: - Strings

    private static func strings(_ suite: TestSuite) {
        let every: [KeyPath<ForkGlanceIslandStrings, String>] = [
            \.sectionSummary, \.activityHint, \.mapLabel, \.modes, \.historyEmpty, \.layoutMovedTitle, \.showLiveDot,
            \.liveDotCaption, \.showHistory, \.closedIsland, \.notices, \.noticesCaption, \.allSettings, \.islandSettings,
        ]
        let fieldCount = ForkGlanceStringsTests.fields(ForkGlanceIslandStrings.enUS).count
        suite.expect(every.count == fieldCount, "the 28-character check covers every island field (\(fieldCount))")
        ForkGlanceStringsTests.mirrorChecks(suite, "ForkGlanceIslandStrings", ForkGlanceIslandStrings.strings,
                                            island: every, untranslated: [])
        suite.expect(ForkGlanceIslandStrings.fr.sectionSummary == "Le clavier suit votre regard",
                     "the Content tab's line in French")
        let core = ForkGlanceStrings.strings(.fr)
        suite.expect(core.sectionTitle == "Regard", "the section is « Regard »")
        suite.expect(core.islandClosedName(.paused).count > 0
                     && ForkGlanceIslandClosed.allCases.map(core.islandClosedName).count == 3,
                     "the closed island's three choices are named")
    }
}
