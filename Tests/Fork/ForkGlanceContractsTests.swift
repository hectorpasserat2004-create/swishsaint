// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import CoreGraphics
import Foundation

/// Suite `fork-glance-contracts` — W0: the shared contracts, the ladders and
/// the settings read from the defaults (plan §4, §14, decisions of 23/10).
enum ForkGlanceContractsTests {
    static func run(_ suite: TestSuite) {
        defaults(suite)
        settings(suite)
        contracts(suite)
    }

    private static func scratch() -> UserDefaults {
        let name = "fork-glance-contracts-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        ForkDefaults.register(defaults)
        return defaults
    }

    private static func defaults(_ suite: TestSuite) {
        let values = ForkGlanceDefaults.registered
        suite.expect(values.keys.allSatisfy { $0.hasPrefix("fork.glance.") },
                     "every Glance Focus setting lives under fork.glance.")
        suite.expect(values.values.allSatisfy { $0 is Bool || $0 is Int || $0 is String },
                     "Glance Focus settings are Bool, Int or String, the only types a backup imports")
        suite.expect(values[ForkDefaultsKey.glanceMode] as? String == "zones"
                        && values[ForkDefaultsKey.glanceOnBattery] as? String == "saver"
                        && values[ForkDefaultsKey.glanceDuringCalls] as? String == "continue"
                        && values[ForkDefaultsKey.glanceFeedback] as? String == "halo"
                        && values[ForkDefaultsKey.glanceLearnFromClicks] as? Bool == true
                        && values[ForkDefaultsKey.glancePanes] as? Bool == false
                        && values[ForkDefaultsKey.glancePanesClickFallback] as? Bool == false
                        && values[ForkDefaultsKey.glanceIslandClosed] as? String == "paused"
                        && values[ForkDefaultsKey.glanceIdleOffStep] as? Int == 1,
                     "Martial's decisions of 23/10: Zones, Saver on battery, keep running in calls, halo, learning on, panes and their click off, island during a pause, off after 5 min")
        suite.expect(ForkGlanceNoticeKind.allCases.allSatisfy {
                         values[ForkDefaultsKey.glanceNotice($0)] as? Bool == ($0 != .recenter)
                     },
                     "every notice is on but « Recentré »")
        suite.expect(ForkGlanceTuning.allCases.allSatisfy {
                         values[$0.key] as? Int == $0.defaultStep && $0.steps.indices.contains($0.defaultStep)
                     },
                     "each ladder registers its default step, which is on the ladder")
        suite.expect(ForkGlanceTuning.sensitivity.defaultValue == 0.4 && ForkGlanceTuning.dwell.defaultValue == 0.2
                        && ForkGlanceTuning.dwellScreens.defaultValue == 0.3
                        && ForkGlanceTuning.typingPause.defaultValue == 1.5
                        && ForkGlanceTuning.pointerPause.defaultValue == 1.5
                        && ForkGlanceTuning.idleOff.defaultValue == 300,
                     "the plan's defaults: margin 0.4, 200 ms (300 ms in Screens), 1.5 s after a key or the pointer, camera off after 5 min")
        suite.expect(ForkGlanceTuning.dwell.value(atStep: 99) == 0.7 && ForkGlanceTuning.dwell.value(atStep: -3) == 0.12,
                     "a step off the ladder lands on its nearest end")
    }

    private static func settings(_ suite: TestSuite) {
        let defaults = scratch()
        var read = ForkGlanceSettings.read(defaults)
        suite.expect(!read.enabled && read.mode == .zones && read.dwell == 0.2 && read.pointer == .stay
                        && read.idleOff == 300 && read.raise && read.energy == .balanced
                        && read.onBattery == .saver && read.duringCalls == .keepRunning && read.pauseInLowPower
                        && read.neverLeaveApps.isEmpty && read.panesApps == ForkGlanceDefaults.defaultPanesApps,
                     "the registered defaults read back as the plan's settings")
        defaults.set("screens", forKey: ForkDefaultsKey.glanceMode)
        read = ForkGlanceSettings.read(defaults)
        suite.expect(read.dwell == 0.3 && read.pointer == .followScreen,
                     "Screens mode takes its own dwell, and the automatic pointer follows the screen")
        defaults.set("windowCenter", forKey: ForkDefaultsKey.glancePointer)
        defaults.set(4, forKey: ForkDefaultsKey.glanceIdleOffStep)
        defaults.set("bogus", forKey: ForkDefaultsKey.glanceEnergy)
        defaults.set("not json", forKey: ForkDefaultsKey.glanceNeverFocusApps)
        read = ForkGlanceSettings.read(defaults)
        suite.expect(read.pointer == .windowCenter && read.idleOff == nil && read.energy == .balanced
                        && read.neverFocusApps.isEmpty,
                     "a chosen pointer stays, the last idle step is never, an unknown value or list falls back")
        defaults.set(ForkGlanceDefaults.encode(["com.apple.Keynote"]), forKey: ForkDefaultsKey.glanceNeverLeaveApps)
        suite.expect(ForkGlanceSettings.read(defaults).neverLeaveApps == ["com.apple.Keynote"],
                     "an app list round-trips through its JSON")
        suite.expect(ForkGlanceSettings.list(["com.jetbrains."], contains: "com.jetbrains.intellij")
                        && !ForkGlanceSettings.list(["com.jetbrains."], contains: "com.jetbrainsx")
                        && ForkGlanceSettings.list(["dev.zed.Zed"], contains: "dev.zed.Zed")
                        && !ForkGlanceSettings.list(["dev.zed.Zed"], contains: "dev.zed.Zed2")
                        && !ForkGlanceSettings.list(["dev.zed.Zed"], contains: nil),
                     "an entry ending with a dot matches a bundle id prefix, the others exactly")
    }

    private static func contracts(_ suite: TestSuite) {
        suite.expect(ForkGlancePauseReason.shown([.idle, .battery, .user]) == .user
                        && ForkGlancePauseReason.shown([.idle, .call, .thermal]) == .call
                        && ForkGlancePauseReason.shown([]) == nil
                        && Set(ForkGlancePauseReason.displayOrder) == Set(ForkGlancePauseReason.allCases)
                        && ForkGlancePauseReason.displayOrder.count == ForkGlancePauseReason.allCases.count,
                     "several pauses show the plan's first one, and every reason has its place")
        suite.expect(ForkGlanceGrade(score: 0.97) == .excellent && ForkGlanceGrade(score: 0.95) == .excellent
                        && ForkGlanceGrade(score: 0.9) == .good && ForkGlanceGrade(score: 0.7) == .fair
                        && ForkGlanceGrade(score: 0.69) == .poor,
                     "validation grades: ≥ 95 % excellent, ≥ 85 % good, ≥ 70 % fair")
        suite.expect(ForkGlanceVectorLayout.components(usesEyes: false) == 0..<6
                        && ForkGlanceVectorLayout.components(usesEyes: true) == 0..<11,
                     "the head-only profile reads the first six components")
        let range = ForkGlanceRange(center: 2, scale: 4)
        suite.expect(range.reduce(6) == 1 && range.expand(1) == 6, "a range reduces and expands back")
        suite.expect(ForkGlancePhase.settled(zone: "a").isWatching && !ForkGlancePhase.paused(.user, until: nil).isWatching
                        && !ForkGlancePhase.needsCalibration(.newLayout).isWatching,
                     "the camera runs only while watching")
        let calibration = ForkGlanceCalibration(version: 1, date: Date(timeIntervalSince1970: 0), cameraID: "cam",
                                                layoutSignature: "sig", usesEyes: true, coefficientsX: [1, 2],
                                                coefficientsY: [3], normalization: [range],
                                                sigma: CGSize(width: 40, height: 60), bias: CGVector(dx: 1, dy: -2),
                                                yawRange: -0.5...0.5, pitchRange: -0.2...0.3,
                                                zoneAccuracy: ["a#0": 0.97])
        let data = try? JSONEncoder().encode(calibration)
        suite.expect(data.flatMap { try? JSONDecoder().decode(ForkGlanceCalibration.self, from: $0) } == calibration,
                     "a calibration round-trips through JSON")
        suite.expect(ForkGlanceCallPolicy.keepRunning.rawValue == "continue"
                        && ForkGlancePointerBehavior.auto.resolved(for: .zones) == .stay,
                     "the stored values keep the plan's spelling")
    }
}
