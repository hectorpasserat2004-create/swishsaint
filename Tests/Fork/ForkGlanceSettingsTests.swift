// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import CoreGraphics
import Foundation

/// Suite `fork-glance-settings` — B3: the settings page's pure rules and strings.
enum ForkGlanceSettingsTests {
    static func run(_ suite: TestSuite) {
        ForkGlanceStringsTests.mirrorChecks(suite, "ForkGlanceSettingsStrings", ForkGlanceSettingsStrings.strings,
                                            sameInFrench: sameInFrench,
                                            untranslated: ["islandTitle", "frameRateValue", "extraEntryValue", "visionValue",
                                                           "appsTitle", "rowPhase", "privacyTitle"])
        modes(suite)
        calibration(suite)
        mapZones(suite)
        values(suite)
        diagnostics(suite)
        preview(suite)
        geometry(suite)
        curves(suite)
    }

    /// The words that are the same in French and in English.
    private static let sameInFrench: Set<String> = ["modeTitle", "appsTitle", "islandTitle", "rowPhase", "visionValue"]

    private static let french = Locale(identifier: "fr_FR")
    private static let english = Locale(identifier: "en_US")

    // Martial's setup (plan, annex A).
    private static let lg = ForkGlanceDisplay(uuid: "LG", name: "LG HDR WQHD", frame: CGRect(x: 0, y: 0, width: 3440, height: 1440),
                                              millimeters: CGSize(width: 816, height: 338))
    private static let builtIn = ForkGlanceDisplay(uuid: "BUILTIN", name: "Built-in Retina Display",
                                                   frame: CGRect(x: 938, y: 1440, width: 1728, height: 1117),
                                                   millimeters: CGSize(width: 344, height: 222), isBuiltIn: true,
                                                   hasNotch: true)
    private static let setup = ForkGlanceDisplayLayout(displays: [lg, builtIn])

    private static func calibration(sigma: CGSize, accuracy: [String: Double] = [:]) -> ForkGlanceCalibration {
        ForkGlanceCalibration(version: 1, date: Date(timeIntervalSince1970: 0), cameraID: "cam", layoutSignature: "sig",
                              usesEyes: true, coefficientsX: [], coefficientsY: [], normalization: [], sigma: sigma,
                              bias: .zero, yawRange: -0.5...0.5, pitchRange: -0.3...0.3, zoneAccuracy: accuracy)
    }

    private static func profile(_ id: String, used: TimeInterval, splits: [String: ForkGlanceSplit] = [:])
        -> ForkGlanceProfile {
        ForkGlanceProfile(id: id, title: id, layout: setup, splits: splits, calibration: nil,
                          learning: ForkGlanceLearning(), lastUsed: Date(timeIntervalSince1970: used))
    }

    // MARK: - Modes (plan §5.3)

    private static func modes(_ suite: TestSuite) {
        let single = ForkGlanceDisplayLayout(displays: [lg])
        suite.expect(ForkGlanceSettingsRules.fit(.zones, layout: single, calibration: nil) == .suited,
                     "Zones mode suits any layout, even one display without a calibration")
        suite.expect(ForkGlanceSettingsRules.fit(.screens, layout: setup, calibration: nil) == .suited,
                     "Screens mode suits two displays")
        suite.expect(ForkGlanceSettingsRules.fit(.screens, layout: single, calibration: nil) == .singleScreen,
                     "Screens mode with one display says it pauses (« Un seul écran »)")
        suite.expect(ForkGlanceSettingsRules.fit(.windows, layout: setup, calibration: nil) == .unknown,
                     "Windows mode before a calibration does not claim to suit or not")
        // The MacBook is the narrowest: 8 % of 1728 pt is 138 pt.
        suite.expect(ForkGlanceSettingsRules.fit(.windows, layout: setup,
                                                 calibration: calibration(sigma: CGSize(width: 120, height: 90))) == .suited,
                     "Windows mode suits a σ under 8 % of the narrowest display's width")
        suite.expect(ForkGlanceSettingsRules.fit(.windows, layout: setup,
                                                 calibration: calibration(sigma: CGSize(width: 200, height: 90))) == .lowPrecision,
                     "Windows mode is marked « Précision insuffisante » past 8 % of the narrowest display, even if the LG would allow it")
        suite.expect(ForkGlanceSettingsRules.fit(.windows, layout: setup,
                                                 calibration: calibration(sigma: CGSize(width: CGFloat.nan, height: 1))) == .lowPrecision,
                     "a σ that is not a number never passes for precise")
        suite.expect(ForkGlanceSettingsRules.dwellTuning(for: .screens) == .dwellScreens
                     && ForkGlanceSettingsRules.dwellTuning(for: .zones) == .dwell
                     && ForkGlanceSettingsRules.dwellTuning(for: .windows) == .dwell,
                     "the delay slider edits the Screens ladder in Screens mode and the other one otherwise")
    }

    // MARK: - Calibration (plan §12.3)

    private static func calibration(_ suite: TestSuite) {
        let good = calibration(sigma: CGSize(width: 50, height: 50), accuracy: ["LG#0": 1, "LG#1": 0.96, "BUILTIN#0": 0.94])
        suite.expectClose(ForkGlanceSettingsRules.score(good) ?? -1, 2.9 / 3, "score is the mean of the zones")
        suite.expect(ForkGlanceSettingsRules.grade(good) == .excellent, "a 96.7 % validation reads « Excellente »")
        suite.expect(ForkGlanceSettingsRules.score(calibration(sigma: .zero)) == nil,
                     "a calibration never validated has no score (no badge)")
        suite.expect(ForkGlanceSettingsRules.score(nil) == nil, "no calibration, no score")
        let fair = calibration(sigma: .zero, accuracy: ["a": 0.7, "b": 0.8])
        suite.expect(ForkGlanceSettingsRules.grade(fair) == .fair, "a 75 % validation reads « Moyenne »")

        let profiles = [profile("old", used: 10), profile("current", used: 30), profile("recent", used: 20)]
        let others = ForkGlanceSettingsRules.otherProfiles(profiles, current: "current")
        suite.expect(others.map(\.id) == ["recent", "old"],
                     "« Autres dispositions » leaves the current profile out, the most recently used first")
        suite.expect(ForkGlanceSettingsRules.otherProfiles(profiles, current: nil).count == 3,
                     "without a current profile, every profile is another layout")
    }

    // MARK: - Map zones (plan §5.2, §12.4)

    private static func mapZones(_ suite: TestSuite) {
        let defaults = ForkGlanceSettingsRules.splits(profile: nil, layout: setup)
        suite.expect(defaults == ["LG": .columns2, "BUILTIN": .whole],
                     "without a profile the LG is cut in two columns and the MacBook stays whole")
        let edited = ForkGlanceSettingsRules.splits(profile: profile("p", used: 0, splits: ["BUILTIN": .rows2, "GONE": .grid2x2]),
                                                    layout: setup)
        suite.expect(edited == ["LG": .columns2, "BUILTIN": .rows2],
                     "the profile's splits win, a display that is gone is not listed")

        let zones = ForkGlanceSettingsRules.mapZones(mode: .zones, layout: setup, splits: defaults, liveZones: [])
        suite.expect(zones.map(\.id) == ["LG#0", "LG#1", "BUILTIN#0"], "Zones mode draws the splits the page holds")
        let screens = ForkGlanceSettingsRules.mapZones(mode: .screens, layout: setup, splits: defaults, liveZones: [])
        suite.expect(screens.count == 2, "Screens mode draws one zone per display, whatever the splits")
        let window = ForkGlanceZone(id: "win:7", displayUUID: "LG", rect: CGRect(x: 10, y: 10, width: 500, height: 400),
                                    position: .window, windowID: 7)
        suite.expect(ForkGlanceSettingsRules.mapZones(mode: .windows, layout: setup, splits: defaults, liveZones: [window])
                     == [window], "Windows mode draws the service's live windows only")
    }

    // MARK: - Values (plan §7.3–§7.5, §10.4)

    private static func values(_ suite: TestSuite) {
        let compact: (String?) -> String? = { $0.map { $0.replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{202F}", with: " ") } }
        suite.expect(compact(ForkGlanceSettingsRules.duration(0.2, locale: french)) == "200 ms",
                     "a delay under a second reads in milliseconds: \(String(describing: ForkGlanceSettingsRules.duration(0.2, locale: french)))")
        suite.expect(compact(ForkGlanceSettingsRules.duration(1.5, locale: french)) == "1,5 s",
                     "a pause in seconds keeps its French decimal comma: \(String(describing: ForkGlanceSettingsRules.duration(1.5, locale: french)))")
        suite.expect(compact(ForkGlanceSettingsRules.duration(1.5, locale: english)) == "1.5 sec"
                     || compact(ForkGlanceSettingsRules.duration(1.5, locale: english)) == "1.5 s",
                     "the same pause in English: \(String(describing: ForkGlanceSettingsRules.duration(1.5, locale: english)))")
        suite.expect(compact(ForkGlanceSettingsRules.duration(4, locale: french)) == "4 s", "a whole number of seconds has no decimals")
        suite.expect(compact(ForkGlanceSettingsRules.duration(300, locale: french)) == "5 min",
                     "« Couper la caméra après » reads in minutes")
        suite.expect(ForkGlanceSettingsRules.duration(.infinity, locale: french) == nil, "never has no duration")
        suite.expect(ForkGlanceSettingsRules.stepValue(.idleOff, step: 4, locale: french, never: "Jamais") == "Jamais",
                     "the last step of « Couper la caméra après » is « Jamais »")
        suite.expect(compact(ForkGlanceSettingsRules.stepValue(.dwell, step: 1, locale: french, never: "Jamais")) == "200 ms",
                     "the default delay reads 200 ms")
        suite.expect(compact(ForkGlanceSettingsRules.stepValue(.dwell, step: 99, locale: french, never: "Jamais")) == "700 ms",
                     "a step stored past the ladder reads as its last step")
        suite.expect(ForkGlanceSettingsRules.stepValue(.sensitivity, step: 2, locale: french, never: "Jamais") == nil,
                     "the sensitivity shows no unit: its ends say « Prudent ↔ Vif »")

        let cost = ForkGlanceSettingsRules.cost(cpuCores: 0.02, watts: 0.1, locale: french)
        suite.expect(compact(cost?.cpu) == "2 %", "2 % of a core: \(String(describing: cost?.cpu))")
        suite.expect(compact(cost?.watts) == "0,1 W", "a tenth of a watt in French: \(String(describing: cost?.watts))")
        let small = ForkGlanceSettingsRules.cost(cpuCores: 0.004, watts: nil, locale: french)
        suite.expect(compact(small?.cpu) == "0,4 %" && small?.watts == nil,
                     "under a percent a decimal shows, and no power before it is measured: \(String(describing: small?.cpu))")
        suite.expect(ForkGlanceSettingsRules.cost(cpuCores: nil, watts: 1, locale: french) == nil,
                     "nothing is shown before the CPU is measured")
        suite.expect(ForkGlanceSettingsRules.cost(cpuCores: -1, watts: 1, locale: french) == nil,
                     "a negative measure is not shown")
    }

    // MARK: - Diagnostics (plan §12.11)

    private static func diagnostics(_ suite: TestSuite) {
        suite.expect(ForkGlanceSettingsRules.phaseLabel(.blocked(zone: "LG#0", guards: [.typing, .pointer]))
                     == "blocked · LG#0 · typing, pointer", "a blocked phase names its zone and guards")
        suite.expect(ForkGlanceSettingsRules.phaseLabel(.candidate(zone: "LG#1", current: "LG#0", since: 3),
                                                        zoneName: { $0 == "LG#1" ? "right" : nil })
                     == "candidate · LG#0 → right", "a candidate names both zones, by name when known")
        suite.expect(ForkGlanceSettingsRules.phaseLabel(.paused(.user, until: 12)) == "paused · user · timed",
                     "a timed pause says so")
        suite.expect(ForkGlanceSettingsRules.countsLine(["Safari": 1, "Code": 3, "Mail": 0]) == "Code 3 · Safari 1",
                     "focus failures list the most failing app first and drop the zeros")
        suite.expect(ForkGlanceSettingsRules.countsLine([:]) == nil, "no failure, no line")
        let now = Date(timeIntervalSince1970: 1000)
        suite.expect(ForkGlanceSettingsRules.setAsideLine(["Zoom": now.addingTimeInterval(60),
                                                           "Mail": now.addingTimeInterval(-1)], now: now) == "Zoom",
                     "an app whose 5 minutes are over is no longer set aside")

        let text = ForkGlanceSettingsStrings.fr
        let core = ForkGlanceStrings.fr
        let readings = ForkGlanceDiagnosticReadings(frameRate: 12, visionMean: 0.0042, visionP95: 0.0071, confidence: 0.82,
                                                    guards: [], extraEntry: 0.5, setAside: [:], focusFailures: [:],
                                                    clickAgreement: nil, cpuCores: nil, watts: nil, revisions: "")
        let lines = ForkGlanceSettingsRules.diagnosticLines(readings, phase: .settled(zone: "LG#0"), lastSwitch: nil,
                                                            now: now, locale: french, text: text, core: core)
        let table = Dictionary(uniqueKeysWithValues: lines.map { ($0.item, $0.value.replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{202F}", with: " ")) })
        suite.expect(lines.map(\.item) == ForkGlanceDiagnosticLine.Item.allCases,
                     "the table has every row, in the plan's order")
        suite.expect(table[.frameRate] == "12,0 img/s", "the rate in French: \(table[.frameRate] ?? "")")
        suite.expect(table[.vision] == "4,2 ms · p95 7,1 ms", "Vision's time in milliseconds, mean and p95: \(table[.vision] ?? "")")
        suite.expect(table[.confidence] == "82 %", "the confidence as a percentage: \(table[.confidence] ?? "")")
        suite.expect(table[.guards] == "aucune" && table[.focusFailures] == "aucune" && table[.setAside] == "aucune",
                     "an empty list reads « aucune »")
        suite.expect(table[.clickAgreement] == "–" && table[.lastSwitch] == "–" && table[.revisions] == "–",
                     "what is not known yet reads « – »")
        suite.expect(table[.cost] == text.costMeasuring, "the cost reads « Mesure en cours » until measured")
        suite.expect(table[.extraEntry] == "+0,5 σ", "the anti ping-pong margin in σ: \(table[.extraEntry] ?? "")")

        var busy = readings
        busy.guards = [.typing]
        busy.cpuCores = 0.02
        busy.watts = 0.1
        let busyLines = ForkGlanceSettingsRules.diagnosticLines(busy, phase: .off, lastSwitch: now.addingTimeInterval(-2),
                                                                now: now, locale: french, text: text, core: core)
        let cost = busyLines.first { $0.item == .cost }?.value.replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{202F}", with: " ")
        suite.expect(cost == "≈ 2 % d’un cœur · ≈ 0,1 W (processus)", "the cost line of plan §10.4: \(cost ?? "")")
        suite.expect(busyLines.first { $0.item == .guards }?.value == core.guardTyping, "a guard up is named in words")
        suite.expect(busyLines.first { $0.item == .lastSwitch }?.value.contains("2") == true, "the last switch says how long ago")
    }

    // MARK: - Preview landmarks

    private static func preview(_ suite: TestSuite) {
        let point = ForkGlanceSettingsRules.previewPoint(CGPoint(x: 0.2, y: 0.9), mirrored: true)
        suite.expectClose(point.x, 0.8, "a mirrored preview flips x")
        suite.expectClose(point.y, 0.1, "Vision's bottom-left origin becomes the view's top-left")
        let plain = ForkGlanceSettingsRules.previewPoint(CGPoint(x: 0.2, y: 0.9), mirrored: false)
        suite.expectClose(plain.x, 0.2, "an unmirrored preview keeps x")
        let box = ForkGlanceSettingsRules.previewRect(CGRect(x: 0.1, y: 0.6, width: 0.3, height: 0.2), mirrored: true)
        suite.expectClose(box.minX, 0.6, "a mirrored face box starts where its right edge was")
        suite.expectClose(box.minY, 0.2, "the face box's top is measured from the top")
        suite.expectClose(box.width, 0.3, "the face box keeps its width")
    }

    // MARK: - Map geometry (plan §12.4)

    private static func geometry(_ suite: TestSuite) {
        let map = ForkGlanceMapGeometry(layout: setup, fitting: CGSize(width: 816, height: 560))
        suite.expectClose(map.aspect, 816.0 / 560.0, "the map is as wide as the LG and as tall as both displays, in mm",
                          tol: 0.001)
        guard let top = map.screens.first(where: { $0.display.uuid == "LG" })?.rect,
              let bottom = map.screens.first(where: { $0.display.uuid == "BUILTIN" })?.rect else {
            suite.expect(false, "both displays are drawn")
            return
        }
        suite.expectClose(top.width, 816, "at one point per mm the LG is 816 wide", tol: 0.01)
        suite.expectClose(bottom.width, 344, "and the MacBook 344: millimeters, not points", tol: 0.01)
        suite.expectClose(bottom.minY, top.maxY, "the MacBook sits right under the LG", tol: 0.01)
        // Its center is 82 pt right of the LG's, 82 × 816 / 3440 mm.
        suite.expectClose(bottom.midX - top.midX, 82 * 816 / 3440, "the MacBook is offset as macOS arranges it", tol: 0.01)
        suite.expect(map.screens.map(\.display.uuid) == ["LG", "BUILTIN"], "the displays keep the layout's order")

        let right = ForkGlanceZone(id: "LG#1", displayUUID: "LG", rect: CGRect(x: 1720, y: 0, width: 1720, height: 1440),
                                   position: .right)
        suite.expect(map.rect(of: right).map { abs($0.minX - 408) < 0.01 && abs($0.width - 408) < 0.01 } == true,
                     "the LG's right zone is its right half on the map")
        let center = map.point(CGPoint(x: 1720, y: 720))
        suite.expect(center.map { abs($0.x - top.midX) < 0.01 && abs($0.y - top.midY) < 0.01 } == true,
                     "a gaze at the LG's center lands at its drawing's center")
        let below = map.point(CGPoint(x: 1802, y: 3000))
        suite.expect(below.map { $0.y > bottom.maxY } == true, "a gaze below every screen (the keyboard) is drawn below them")
        let sigma = map.size(CGSize(width: 172, height: 144), at: CGPoint(x: 100, y: 100))
        suite.expect(sigma.map { abs($0.width - 40.8) < 0.01 && abs($0.height - 33.8) < 0.01 } == true,
                     "the σ ellipse takes the display's scale")

        let fitted = ForkGlanceMapGeometry(layout: setup, fitting: CGSize(width: 400, height: 100), inset: 4)
        let union = fitted.screens.reduce(CGRect.null) { $0.union($1.rect) }
        suite.expect(union.minY >= 3.99 && union.maxY <= 96.01 && abs(union.midX - 200) < 0.01,
                     "a wide canvas fits the layout by its height, centered, inside the inset")

        let unknownSize = ForkGlanceDisplay(uuid: "X", name: "Projector", frame: CGRect(x: 3440, y: 0, width: 1920, height: 1080))
        let three = ForkGlanceMapGeometry(layout: ForkGlanceDisplayLayout(displays: [lg, builtIn, unknownSize]),
                                          fitting: CGSize(width: 1000, height: 1000))
        let lgRect = three.screens[0].rect, projector = three.screens[2].rect
        suite.expect(abs(projector.minX - lgRect.maxX) < 0.01 && abs(projector.minY - lgRect.minY) < 0.01,
                     "a display that reports no size still sits against its neighbor's edge")

        suite.expect(ForkGlanceMapGeometry(layout: ForkGlanceDisplayLayout(displays: []),
                                           fitting: CGSize(width: 100, height: 100)).screens.isEmpty,
                     "no display, nothing drawn")
        let portrait = ForkGlanceDisplay(uuid: "P", name: "Dell", frame: CGRect(x: 0, y: 0, width: 1440, height: 2560),
                                         millimeters: CGSize(width: 597, height: 336), rotation: 90)
        suite.expect(ForkGlanceMapGeometry.aspect(of: ForkGlanceDisplayLayout(displays: [portrait])) < 1,
                     "a display turned on its side is drawn upright even if it reports the panel's size")
    }

    // MARK: - Curves (plan §12.11)

    private static func curves(_ suite: TestSuite) {
        var history = ForkGlanceCurveHistory()
        func observation(_ time: TimeInterval, yaw: Double?) -> ForkGlanceObservation {
            ForkGlanceObservation(time: time, faceBox: .zero, yaw: yaw, pitch: 0)
        }
        var vector = Array(repeating: 0.0, count: ForkGlanceVectorLayout.count)
        vector[ForkGlanceVectorLayout.leftEyeX] = 0.4
        vector[ForkGlanceVectorLayout.rightEyeX] = 0.6
        let sample = ForkGlanceSample(time: 0, vector: vector, confidence: 1, eyesUsable: true, facePresent: true)
        history.append(time: 1, observation: observation(1, yaw: .pi / 4), sample: sample)
        suite.expectClose(history.points.last?.yaw ?? 0, 45, "yaw is kept in degrees")
        suite.expectClose(history.points.last?.eyes ?? 0, 0.5, "the eyes are the pupils' mean horizontal place")
        history.append(time: 1, observation: observation(1, yaw: 0), sample: nil)
        suite.expect(history.points.count == 1, "the same image published twice is kept once")
        history.append(time: 0.5, observation: observation(0.5, yaw: 0), sample: nil)
        suite.expect(history.points.count == 1, "an older image is ignored")
        var blink = sample
        blink.eyesUsable = false
        history.append(time: 2, observation: observation(2, yaw: nil), sample: blink)
        history.append(time: 3, observation: observation(3, yaw: -.pi / 4), sample: sample)
        suite.expect(history.segments(.yaw).count == 2, "a missing yaw cuts the curve")
        suite.expect(history.segments(.eyes).count == 2, "a blink cuts the eyes' curve")
        let first = history.segments(.yaw).first?.first
        suite.expect(first.map { abs($0.x - 0.8) < 1e-9 && abs($0.y) < 1e-9 } == true,
                     "45° right is drawn at the top, 2 s before the last image at 80 % of the width")
        history.append(time: 12.5, observation: observation(12.5, yaw: 0), sample: nil)
        suite.expect(history.points.map(\.time) == [3, 12.5], "only the last 10 s are kept")
        let pinned = history.segments(.pitch).flatMap { $0 }
        suite.expect(pinned.allSatisfy { $0.y >= 0 && $0.y <= 1 && $0.x >= 0 && $0.x <= 1 }, "every point fits the curve's frame")
        suite.expect(ForkGlanceCurveHistory().segments(.yaw).isEmpty, "no image, no curve")
    }
}
