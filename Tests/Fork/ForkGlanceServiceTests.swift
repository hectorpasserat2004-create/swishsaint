// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import CoreGraphics
import Foundation

/// Suite `fork-glance-service`: the service's pure rules (`Pure/ForkGlanceServiceRules`)
/// and the shortcuts (`Pure/ForkGlanceShortcuts`).
enum ForkGlanceServiceTests {
    static func run(_ suite: TestSuite) {
        pauseStorage(suite)
        pauseNotices(suite)
        profileChoice(suite)
        rekeying(suite)
        learning(suite)
        smallRules(suite)
        commandBar(suite)
        cost(suite)
        report(suite)
        shortcutStorage(suite)
        shortcutConflicts(suite)
        shortcutPrecedence(suite)
        pauseDefault(suite)
    }

    // MARK: Fixtures

    private static let camera = "0x1420000005ac8600"
    private static let now = Date(timeIntervalSince1970: 1_792_750_000) // 23/10/2026
    private static let desk = ForkGlanceZonesTests.desk
    private static let lg = ForkGlanceZonesTests.lg
    private static let macBook = ForkGlanceZonesTests.macBook

    private static func calibration(for layout: ForkGlanceDisplayLayout) -> ForkGlanceCalibration {
        ForkGlanceCalibration(
            version: ForkGlanceCalibration.currentVersion, date: now, cameraID: camera,
            layoutSignature: ForkGlanceProfiles.signature(layout: layout, cameraID: camera), usesEyes: true,
            coefficientsX: [1], coefficientsY: [1], normalization: [ForkGlanceRange(center: 0, scale: 1)],
            sigma: CGSize(width: 80, height: 120), bias: CGVector(dx: 3, dy: -4),
            yawRange: -0.5...0.5, pitchRange: -0.3...0.3, zoneAccuracy: ["LG-UUID#0": 1, "LG-UUID#1": 0.9])
    }

    private static func calibrated(_ layout: ForkGlanceDisplayLayout, cameraID: String = camera) -> ForkGlanceProfile {
        var profile = ForkGlanceProfiles.newProfile(layout: layout, cameraID: cameraID, now: now)
        profile.calibration = calibration(for: layout)
        return profile
    }

    private static func sample(time: TimeInterval, confidence: Double = 0.9, face: Bool = true) -> ForkGlanceSample {
        ForkGlanceSample(time: time, vector: Array(repeating: 0.1, count: ForkGlanceVectorLayout.count),
                         confidence: confidence, eyesUsable: true, facePresent: face)
    }

    private static func gaze(_ target: ForkGlanceGazeTarget, at time: TimeInterval) -> ForkGlanceGaze {
        ForkGlanceGaze(estimate: ForkGlanceEstimate(point: CGPoint(x: 10, y: 10), sigma: CGSize(width: 50, height: 50),
                                                    time: time, confidence: 0.9),
                       target: target, margin: 1, headSpeed: 0, confidence: 0.9, crowded: false)
    }

    private static func settings(mode: ForkGlanceMode = .zones) -> ForkGlanceSettings {
        let name = "vorss.tests.fork.glance-service-settings"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defaults.set(mode.rawValue, forKey: ForkDefaultsKey.glanceMode)
        let settings = ForkGlanceSettings.read(defaults)
        defaults.removePersistentDomain(forName: name)
        return settings
    }

    private static func withDefaults(_ name: String, _ body: (UserDefaults) -> Void) {
        let suiteName = "vorss.tests.fork.glance-service-\(name)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        body(defaults)
        defaults.removePersistentDomain(forName: suiteName)
    }

    // MARK: Pause

    private static func pauseStorage(_ suite: TestSuite) {
        typealias Rules = ForkGlancePauseRules
        let end = now.addingTimeInterval(3600)
        suite.expect(Rules.decode(Rules.encode(.until(end))) == .until(end),
                     "a timed pause's end comes back from its stored text, to the second")
        suite.expect(Rules.decode(Rules.encode(.untilResumed)) == .untilResumed && Rules.encode(.untilResumed) == "forever",
                     "« jusqu'à reprise » is stored as « forever »")
        suite.expect(Rules.decode("") == .none && Rules.decode(nil) == .none && Rules.decode("next tuesday") == .none,
                     "nothing, or anything unreadable, is no pause: the feature never stays off by accident")
        suite.expect(Rules.restored(.until(now.addingTimeInterval(-1)), now: now) == .none
                        && Rules.restored(.until(end), now: now) == .until(end)
                        && Rules.restored(.untilResumed, now: now) == .untilResumed,
                     "at launch a pause whose end has passed is over; one still running or until resumed goes on")

        // The machine counts in systemUptime: 1 h from now is uptime + 3600.
        let uptime: TimeInterval = 5_000
        suite.expectClose(Rules.uptime(of: end, now: now, uptime: uptime), 8_600, "a wall-clock end in uptime")
        suite.expectClose(Rules.date(ofUptime: 8_600, now: now, uptime: uptime).timeIntervalSince(end), 0,
                          "and back")
        // After a 20 min sleep, uptime stood still: the same end is now 40 min away.
        let afterSleep = now.addingTimeInterval(20 * 60)
        suite.expectClose(Rules.uptime(of: end, now: afterSleep, uptime: uptime) - uptime, 40 * 60,
                          "converted again after a sleep, the pause still ends at its wall-clock time")

        suite.expect(ForkGlanceDefaults.machineKeys.contains(ForkDefaultsKey.glancePausedUntil)
                        && ForkDefaults.registered[ForkDefaultsKey.glancePausedUntil] == nil,
                     "the stored pause is machine state: never registered, never in a settings backup")
    }

    private static func pauseNotices(_ suite: TestSuite) {
        typealias Rules = ForkGlanceServiceRules
        let paused = ForkGlanceNotice.paused(until: nil)
        suite.expect(Rules.showsPauseNotice(paused, origin: .shortcut) && Rules.showsPauseNotice(paused, origin: .commandBar),
                     "« Regard en pause » follows a shortcut or the Command Bar")
        suite.expect(!Rules.showsPauseNotice(paused, origin: .surface) && !Rules.showsPauseNotice(.resumed, origin: .surface),
                     "never a click in the island or the page: the person sees the change already")
        suite.expect(Rules.showsPauseNotice(.resumed, origin: .deadline) && !Rules.showsPauseNotice(paused, origin: .deadline),
                     "a timed pause reaching its end says « Regard repris »")
        suite.expect(!Rules.showsPauseNotice(paused, origin: .restore) && !Rules.showsPauseNotice(.resumed, origin: .restore),
                     "a pause put back at launch or after a wake says nothing")
        suite.expect(Rules.showsPauseNotice(.newLayout, origin: .surface) && Rules.showsPauseNotice(.drift, origin: .restore),
                     "the other notices are not the pause's to filter")
    }

    // MARK: Profiles

    private static func profileChoice(_ suite: TestSuite) {
        typealias Rules = ForkGlanceServiceRules
        let profile = calibrated(desk)
        let identical = Rules.choose(.identical(profile), layout: desk, cameraID: camera, profiles: [profile], now: now)
        suite.expect(identical.profile == profile && identical.need == nil && !identical.isNew && !identical.moved,
                     "the same desk: its calibrated profile loads silently, nothing to do")

        let moved = Rules.choose(.moved(profile), layout: desk, cameraID: camera, profiles: [profile], now: now)
        suite.expect(moved.moved && moved.need == nil && moved.profile == profile,
                     "the same displays moved: loaded, with the hint to recenter")

        let first = Rules.choose(.unknown, layout: desk, cameraID: camera, profiles: [], now: now)
        suite.expect(first.isNew && first.need == .firstTime && first.profile.calibration == nil
                        && first.profile.id == ForkGlanceProfiles.signature(layout: desk, cameraID: camera),
                     "nothing calibrated on this Mac: a new profile for this desk, calibration needed for the first time")
        suite.expect(first.profile.splits[lg.uuid] == .columns2 && first.profile.splits[macBook.uuid] == .whole,
                     "a new profile starts with the default splits: the LG in two columns, the MacBook whole")

        let newCamera = Rules.choose(.unknown, layout: desk, cameraID: "IPHONE", profiles: [profile], now: now)
        suite.expect(newCamera.need == .newCamera, "these very displays calibrated with another camera: a new camera")

        let alone = ForkGlanceDisplayLayout(displays: [macBook])
        let newLayout = Rules.choose(.unknown, layout: alone, cameraID: camera, profiles: [profile], now: now)
        suite.expect(newLayout.need == .newLayout, "another set of displays: a new layout")

        var stored = ForkGlanceProfiles.newProfile(layout: desk, cameraID: camera, now: now)
        stored.splits[lg.uuid] = .columns3
        let uncalibrated = Rules.choose(.identical(stored), layout: desk, cameraID: camera, profiles: [stored], now: now)
        suite.expect(uncalibrated.need == .firstTime && uncalibrated.profile.splits[lg.uuid] == .columns3,
                     "a profile stored for its splits but never calibrated still needs the calibration, splits kept")
        let besideOthers = Rules.choose(.identical(stored), layout: desk, cameraID: camera,
                                        profiles: [stored, calibrated(alone)], now: now)
        suite.expect(besideOthers.need == .newLayout,
                     "the same, on a Mac calibrated for another desk: a new layout")
    }

    private static func rekeying(_ suite: TestSuite) {
        typealias Rules = ForkGlanceServiceRules
        let old = calibrated(desk)
        var lower = macBook
        lower.frame = lower.frame.offsetBy(dx: -200, dy: 0)
        let movedDesk = ForkGlanceDisplayLayout(displays: [lg, lower])
        let rekeyed = Rules.rekeyed(old, layout: movedDesk, cameraID: camera)
        suite.expect(rekeyed.id == ForkGlanceProfiles.signature(layout: movedDesk, cameraID: camera)
                        && rekeyed.layout == movedDesk && rekeyed.calibration?.layoutSignature == rekeyed.id
                        && rekeyed.calibration?.bias == old.calibration?.bias,
                     "carried to the moved desk, the profile takes its signature and keeps its model")
        suite.expect(ForkGlanceProfiles.match(layout: movedDesk, cameraID: camera, in: [rekeyed]) == .identical(rekeyed),
                     "so the next launch finds it identical, without the recenter hint")

        let other = calibrated(ForkGlanceDisplayLayout(displays: [macBook]))
        let list = Rules.replacing(old.id, with: rekeyed, in: [old, other])
        suite.expect(list.count == 2 && list.contains(rekeyed) && !list.contains { $0.id == old.id } && list.contains(other),
                     "the rekeyed profile replaces the old one, the others stay")
        var touched = old
        touched.splits[lg.uuid] = .grid2x2
        let same = Rules.replacing(old.id, with: touched, in: [old, other])
        suite.expect(same.count == 2 && same.first { $0.id == old.id }?.splits[lg.uuid] == .grid2x2,
                     "with the same id, the profile is replaced in place")
    }

    // MARK: Learning

    private static func learning(_ suite: TestSuite) {
        typealias Rules = ForkGlanceServiceRules
        suite.expect(Rules.teaches(sample: sample(time: 10), clickTime: 10.2)
                        && Rules.teaches(sample: sample(time: 10.2), clickTime: 10),
                     "a click within 250 ms of a confident image teaches, the image just before or just after")
        suite.expect(!Rules.teaches(sample: sample(time: 10), clickTime: 10.4),
                     "an older image does not: the gaze may have moved")
        suite.expect(!Rules.teaches(sample: sample(time: 10, confidence: 0.6), clickTime: 10)
                        && !Rules.teaches(sample: sample(time: 10, face: false), clickTime: 10),
                     "a doubtful image, or one without a face, teaches nothing")

        let zones = ForkGlanceZones.zones(layout: desk, mode: .zones, splits: [:], windows: [])
        suite.expect(Rules.zone(at: CGPoint(x: 100, y: 100), in: zones)?.id == "\(lg.uuid)#0"
                        && Rules.zone(at: CGPoint(x: 3000, y: 100), in: zones)?.id == "\(lg.uuid)#1"
                        && Rules.zone(at: CGPoint(x: 1000, y: 2000), in: zones)?.id == "\(macBook.uuid)#0",
                     "a click is filed under the zone it lands in")
        suite.expect(Rules.zone(at: CGPoint(x: 100, y: 2000), in: zones) == nil, "beside every display, no zone")

        suite.expect(Rules.prediction(gaze(.zone("A"), at: 5), clickTime: 5.1) == .some("A"),
                     "the gaze on a zone predicts that zone")
        suite.expect(Rules.prediction(gaze(.between, at: 5), clickTime: 5.1) == .some(nil)
                        && Rules.prediction(gaze(.away, at: 5), clickTime: 5.1) == .some(nil),
                     "between zones or away predicts none: a miss for the drift")
        suite.expect(Rules.prediction(gaze(.zone("A"), at: 5), clickTime: 6) == nil
                        && Rules.prediction(nil, clickTime: 6) == nil
                        && Rules.prediction(gaze(.noFace, at: 5), clickTime: 5) == nil,
                     "no recent image with a face: the click says nothing about the model")

        let calendar = Calendar(identifier: .gregorian)
        suite.expect(Rules.driftNoticeDue(last: nil, now: now, calendar: calendar)
                        && !Rules.driftNoticeDue(last: now.addingTimeInterval(-3600), now: now, calendar: calendar)
                        && Rules.driftNoticeDue(last: now.addingTimeInterval(-86_400), now: now, calendar: calendar),
                     "« Le regard se trompe souvent » once a day at most")
    }

    // MARK: Small rules

    private static func smallRules(_ suite: TestSuite) {
        typealias Rules = ForkGlanceServiceRules
        suite.expectClose(Rules.score(["a": 1, "b": 0.9, "c": 0.8]), 0.9, "the validation's score is the zones' mean")
        suite.expect(Rules.score([:]) == 0, "no zone validated: no score")
        suite.expectClose(Rules.progress(since: 10, dwell: 0.2, now: 10.1), 0.5, "half the dwell, half filled")
        suite.expect(Rules.progress(since: 10, dwell: 0.2, now: 11) == 1 && Rules.progress(since: 10, dwell: 0.2, now: 9) == 0,
                     "the filling zone stays between empty and full")
        suite.expect(Rules.nextMode(after: .screens) == .zones && Rules.nextMode(after: .zones) == .windows
                        && Rules.nextMode(after: .windows) == .screens,
                     "« Changer de mode » goes Écrans, Zones, Fenêtres, and round")
        var records: [Int] = []
        for value in 1...15 { records = Rules.appending(value, to: records) }
        suite.expect(records.count == Rules.recentSwitchLimit && records.first == 15 && records.last == 6,
                     "the last switches are kept newest first, ten of them")
        suite.expect(Rules.phaseName(.blocked(zone: "LG-UUID#0", guards: [.typing, .pointer])) == "blocked(typing, pointer)"
                        && Rules.phaseName(.settled(zone: "LG-UUID#0")) == "settled",
                     "the report names the phase without the zone ids")
    }

    // MARK: Command Bar

    private static func commandBar(_ suite: TestSuite) {
        typealias Rules = ForkGlanceServiceRules
        let active = Rules.barItems(enabled: true, phase: .settled(zone: "z"), mode: .zones)
        suite.expect(active.map(\.row) == [.pause(.fifteenMinutes), .pause(.oneHour), .pause(.untilResumed),
                                           .recenter, .calibrate, .mode(.screens), .mode(.windows), .settings]
                        && active.allSatisfy { $0.trouble == nil },
                     "running: the three pauses, recenter, calibrate, the two other modes and the page, all ready")

        let paused = Rules.barItems(enabled: true, phase: .paused(.user, until: nil), mode: .screens)
        suite.expect(paused.first?.row == .resume && !paused.contains { if case .pause = $0.row { return true }; return false }
                        && paused.contains { $0.row == .mode(.zones) } && !paused.contains { $0.row == .mode(.screens) },
                     "the person's pause: « Reprendre » instead of the pauses")
        let automatic = Rules.barItems(enabled: true, phase: .paused(.battery, until: nil), mode: .zones)
        suite.expect(automatic.first?.row == .pause(.fifteenMinutes),
                     "an automatic pause still offers the person's own")

        let off = Rules.barItems(enabled: false, phase: .off, mode: .zones)
        suite.expect(off.filter { $0.row != .settings }.allSatisfy { $0.trouble == .needsSetup }
                        && off.first { $0.row == .settings }?.trouble == nil,
                     "off, every row answers and opens the page; the page's row just opens it")

        let uncalibrated = Rules.barItems(enabled: true, phase: .needsCalibration(.firstTime), mode: .zones)
        suite.expect(uncalibrated.first { $0.row == .recenter }?.trouble == .needsSetup
                        && uncalibrated.first { $0.row == .calibrate }?.trouble == nil,
                     "without a calibration, « Recentrer » opens the page and « Calibrer » works")
        let noCamera = Rules.barItems(enabled: true, phase: .unavailable(.cameraPermission), mode: .zones)
        suite.expect(noCamera.first { $0.row == .recenter }?.trouble == .needsPermission
                        && noCamera.first { $0.row == .pause(.oneHour) }?.trouble == nil,
                     "a missing permission marks « Recentrer »; pausing still works")
    }

    // MARK: Cost

    private static func cost(_ suite: TestSuite) {
        typealias Reading = ForkGlanceCostMeter.Reading
        var meter = ForkGlanceCostMeter()
        meter.cameraOff(Reading(time: 0, cpuSeconds: 10, energyJoules: 100))
        // Before the camera: 1 % of a core and 0.05 W over 100 s.
        meter.cameraOn(Reading(time: 100, cpuSeconds: 11, energyJoules: 105))
        suite.expect(meter.cost == nil, "no cost before 20 s of camera")
        suite.expect(!meter.due(at: 105) && meter.due(at: 110), "one reading every 10 s")
        meter.add(Reading(time: 110, cpuSeconds: 11.3, energyJoules: 106.5))
        suite.expect(meter.cost == nil, "10 s say nothing yet")
        // With the camera: 4 % and 0.2 W over 100 s, so the camera's share is 3 % and 0.15 W.
        meter.add(Reading(time: 200, cpuSeconds: 15, energyJoules: 125))
        guard let rate = meter.cost else {
            suite.expect(false, "a cost after 100 s of camera")
            return
        }
        suite.expectClose(rate.cores, 0.03, "the camera's cost is the process's less what it cost before", tol: 1e-9)
        suite.expectClose(rate.watts ?? -1, 0.15, "the same for the energy", tol: 1e-9)

        for second in stride(from: 210.0, through: 900, by: 10) {
            meter.add(Reading(time: second, cpuSeconds: 15 + (second - 200) * 0.04, energyJoules: 125))
        }
        suite.expect((meter.readings.first?.time ?? 0) >= 900 - ForkGlanceCostMeter.window - 10
                        && (meter.readings.first?.time ?? 0) <= 900 - ForkGlanceCostMeter.window,
                     "only the last five minutes are kept, plus the reading just before them")

        var unmeasured = ForkGlanceCostMeter()
        unmeasured.cameraOff(Reading(time: 0, cpuSeconds: 1, energyJoules: nil))
        unmeasured.cameraOn(Reading(time: 5, cpuSeconds: 1, energyJoules: nil))
        unmeasured.add(Reading(time: 105, cpuSeconds: 3, energyJoules: nil))
        suite.expect(unmeasured.baseline == nil && unmeasured.cost?.cores == 0.02 && unmeasured.cost?.watts == nil,
                     "a baseline too short to measure leaves the process's own cost; no energy, no watts")
    }

    // MARK: Report

    private static func report(_ suite: TestSuite) {
        var profile = calibrated(desk)
        profile.splits = [lg.uuid: .columns2, macBook.uuid: .whole]
        let input = ForkGlanceServiceRules.ReportInput(
            appVersion: "1.2.3 (456)", macModel: "Mac14,6", systemVersion: "Version 27.0.1", layout: desk,
            camera: "built-in", settings: settings(), profile: profile, phase: .settled(zone: "\(lg.uuid)#0"),
            cost: ForkGlanceCostMeter.Rate(cores: 0.021, watts: 0.1), frameRate: 6, visionMean: 0.0042,
            visionP95: 0.0079, revisions: "rectangles rev 3, landmarks rev 3", now: now)
        let text = ForkGlanceServiceRules.report(input)
        suite.expect(text.contains("App: 1.2.3 (456)") && text.contains("Mac: Mac14,6"),
                     "the report names the version and the Mac")
        suite.expect(text.contains("LG HDR WQHD: 3440×1440 at (0, 0), 816×338 mm, split columns2")
                        && text.contains("1728×1117 at (938, 1440), 344×222 mm, built-in, notch, split whole"),
                     "each display with its size, place, millimeters and split")
        suite.expect(text.contains("head + eyes") && text.contains("score 95 %") && text.contains("σ 80×120 pt"),
                     "the calibration's model, score and error")
        suite.expect(text.contains("Mode: zones · phase settled") && !text.contains("#0"),
                     "the mode and the phase, without zone ids")
        suite.expect(text.contains("2.1 % of a core, 0.10 W") && text.contains("4.2 ms mean"),
                     "the measured cost and Vision's time")
        suite.expect(text.contains("Camera: built-in"), "the camera by kind, never by its name")
        let bare = ForkGlanceServiceRules.report(ForkGlanceServiceRules.ReportInput(
            appVersion: "1", macModel: "Mac", systemVersion: "x", layout: desk, camera: "none", settings: settings(),
            profile: nil, phase: .off, cost: nil, frameRate: 0, visionMean: 0, visionP95: 0, revisions: "", now: now))
        suite.expect(bare.contains("Calibration: none") && !bare.contains("Cost:"),
                     "without a profile or a measure, the report says so and leaves the cost out")
    }

    // MARK: Shortcuts

    private static let free: (GlobalShortcut) -> Bool = { _ in false }
    private static let g = ForkGlanceShortcuts.pauseDefault
    private static let r = GlobalShortcut(keyCode: 15, modifiers: [.control, .option, .command])

    private static func shortcutStorage(_ suite: TestSuite) {
        withDefaults("shortcut-storage") { defaults in
            ForkDefaults.register(defaults)
            suite.expect(ForkGlanceShortcuts.load(defaults, role: .pause) == g
                            && ForkGlanceShortcuts.load(defaults, role: .recenter) == nil,
                         "Pause starts on ⌃⌥⌘G (D6), Recentrer on nothing until one is set")
            ForkGlanceShortcuts.save(g, defaults, role: .pause)
            suite.expect(defaults.string(forKey: ForkDefaultsKey.glanceHotKeyPause) == "control+option+command:5"
                            && ForkGlanceShortcuts.load(defaults, role: .pause) == g,
                         "stored as the official recorder writes it, and read back")
            ForkGlanceShortcuts.save(nil, defaults, role: .pause)
            suite.expect(defaults.string(forKey: ForkDefaultsKey.glanceHotKeyPause) == ""
                            && ForkGlanceShortcuts.load(defaults, role: .pause) == nil,
                         "cleared, it is an empty text")
            defaults.set("broken", forKey: ForkDefaultsKey.glanceHotKeyRecenter)
            suite.expect(ForkGlanceShortcuts.load(defaults, role: .recenter) == nil, "unreadable is none")
        }
        suite.expect(Set(ForkGlanceShortcutRole.allCases.map(\.key)).count == 3
                        && ForkGlanceShortcutRole.allCases.allSatisfy {
                            ForkDefaults.registered[$0.key] != nil && ForkDefaults.backupKeys.contains($0.key)
                        },
                     "each shortcut has its own key, registered and in the settings backup")
    }

    private static func shortcutConflicts(_ suite: TestSuite) {
        withDefaults("shortcut-conflicts") { defaults in
            let problem = { (shortcut: GlobalShortcut, role: ForkGlanceShortcutRole) in
                ForkGlanceShortcuts.problem(of: shortcut, role: role, defaults: defaults, isTakenBySystem: free)
            }
            suite.expect(problem(g, .pause) == nil, "⌃⌥⌘G is free on a quiet Mac")
            suite.expect(problem(GlobalShortcut(keyCode: 53, modifiers: [.command]), .pause) == .reservedKey
                            && problem(GlobalShortcut(keyCode: 5, modifiers: [.shift]), .pause) == .needsModifier,
                         "the same refusals as the Meetings': Escape, a letter without a modifier")
            suite.expect(ForkGlanceShortcuts.problem(of: g, role: .pause, defaults: defaults,
                                                     isTakenBySystem: { $0 == g }) == .conflict,
                         "taken by macOS or an official feature: a conflict")

            defaults.set(true, forKey: ForkDefaultsKey.glanceEnabled)
            ForkGlanceShortcuts.save(g, defaults, role: .pause)
            suite.expect(problem(g, .recenter) == .conflict && problem(g, .pause) == nil,
                         "two of Glance's own on one combination conflict; a shortcut never conflicts with itself")

            let dictation = ForkDictationShortcut(key: .combo(keyCode: r.keyCode, modifiers: Int(r.modifiers.rawValue)))
            ForkDictationShortcuts.save([dictation], defaults)
            suite.expect(problem(r, .recenter) == nil, "Dictation switched off holds no key")
            defaults.set(true, forKey: ForkDefaultsKey.dictationEnabled)
            suite.expect(problem(r, .recenter) == .conflict, "Dictation on: its combination is taken")

            let m = GlobalShortcut(keyCode: 46, modifiers: [.control, .option, .command])
            ForkMeetingShortcut.save(m, defaults, role: .marker)
            suite.expect(problem(m, .mode) == nil, "Meetings switched off hold no key")
            defaults.set(true, forKey: ForkDefaultsKey.meetingsEnabled)
            suite.expect(problem(m, .mode) == .conflict, "Meetings on: their combinations are taken, all three")
        }
    }

    private static func shortcutPrecedence(_ suite: TestSuite) {
        withDefaults("shortcut-precedence") { defaults in
            ForkGlanceShortcuts.save(g, defaults, role: .pause)
            suite.expect(!ForkGlanceShortcuts.usedByGlance(g, defaults: defaults, isTakenBySystem: free),
                         "Glance switched off holds no key")
            defaults.set(true, forKey: ForkDefaultsKey.glanceEnabled)
            suite.expect(ForkGlanceShortcuts.usedByGlance(g, defaults: defaults, isTakenBySystem: free)
                            && !ForkGlanceShortcuts.usedByGlance(g, besides: .pause, defaults: defaults, isTakenBySystem: free),
                         "Glance on holds its combination, for every role but its own")
            suite.expect(!ForkGlanceShortcuts.usedByGlance(g, defaults: defaults, isTakenBySystem: { $0 == g }),
                         "a combination macOS took is not Glance's")

            // Dictation already had ⌃⌥⌘G: it keeps it, Glance's is the one refused.
            let dictation = ForkDictationShortcut(key: .combo(keyCode: g.keyCode, modifiers: Int(g.modifiers.rawValue)))
            ForkDictationShortcuts.save([dictation], defaults)
            defaults.set(true, forKey: ForkDefaultsKey.dictationEnabled)
            suite.expect(!ForkGlanceShortcuts.usedByGlance(g, defaults: defaults, isTakenBySystem: free)
                            && ForkGlanceShortcuts.problem(of: g, role: .pause, defaults: defaults,
                                                           isTakenBySystem: free) == .conflict,
                         "Dictation's combination stays Dictation's: Glance yields, so neither refuses the other for good")
            defaults.set(false, forKey: ForkDefaultsKey.dictationEnabled)
            ForkMeetingShortcut.save(g, defaults, role: .toggle)
            defaults.set(true, forKey: ForkDefaultsKey.meetingsEnabled)
            suite.expect(!ForkGlanceShortcuts.usedByGlance(g, defaults: defaults, isTakenBySystem: free),
                         "the Meetings' too")
        }

        // The Dictation's check (and the Meetings', through it) knows Glance's
        // shortcuts: it reads the app's own settings.
        let standard = UserDefaults.standard
        let keys = [ForkDefaultsKey.glanceEnabled, ForkDefaultsKey.glanceHotKeyRecenter, ForkDefaultsKey.dictationEnabled,
                    ForkDefaultsKey.meetingsEnabled]
        let previous = keys.map { standard.object(forKey: $0) }
        standard.set(true, forKey: ForkDefaultsKey.glanceEnabled)
        standard.set(false, forKey: ForkDefaultsKey.dictationEnabled)
        standard.set(false, forKey: ForkDefaultsKey.meetingsEnabled)
        let combination = GlobalShortcut(keyCode: 15, modifiers: [.control, .option, .shift, .command])
        ForkGlanceShortcuts.save(combination, standard, role: .recenter)
        let takenForDictation = ForkDictationShortcuts.isTakenElsewhere(combination)
        let takenForMeetings = ForkMeetingShortcut.isTakenElsewhere(combination)
        for (key, value) in zip(keys, previous) {
            if let value { standard.set(value, forKey: key) } else { standard.removeObject(forKey: key) }
        }
        suite.expect(takenForDictation && takenForMeetings,
                     "Dictation and Meetings refuse a combination Glance holds")
    }

    private static func pauseDefault(_ suite: TestSuite) {
        suite.expect(g.storageValue == "control+option+command:5" && g.displayString == "⌃⌥⌘G",
                     "the pause's default is ⌃⌥⌘G, stored as « control+option+command:5 »")
        let official = GlobalShortcutRole.conflict(for: g, excluding: nil, isOn: { _ in true }, isAvailable: { _ in true },
                                                   includeInactive: true, radialMenuShortcuts: { [] })
        suite.expect(official == nil, "no official shortcut uses ⌃⌥⌘G by default, switched on or not")
        let recenter = GlobalShortcutRole.conflict(for: r, excluding: nil, isOn: { _ in true }, isAvailable: { _ in true },
                                                   includeInactive: true, radialMenuShortcuts: { [] })
        suite.expect(recenter == nil, "nor ⌃⌥⌘R, the recenter's suggestion")
        suite.expect(!ForkDictationShortcuts.isAppMenuShortcut(g) && !ForkDictationShortcuts.isAppMenuShortcut(r),
                     "neither is an app's menu shortcut")
        suite.expect(ForkMeetingShortcut.problem(of: g, isTaken: free) == nil, "and the recorder accepts it")
    }
}
