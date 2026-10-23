// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import CoreGraphics
import Foundation

/// Suite `fork-glance-machine` — A5: the decision machine (plan §7, §17.1).
/// Scenarios run like the service: images at a steady rate, the machine's
/// deadlines ticked in between, each focus reported back.
enum ForkGlanceMachineTests {
    static let left = "LG#0"
    static let right = "LG#1"
    static let mac = "MAC#0"
    static let zones = [
        ForkGlanceZone(id: left, displayUUID: "LG", rect: CGRect(x: 0, y: 0, width: 1720, height: 1440), position: .left),
        ForkGlanceZone(id: right, displayUUID: "LG", rect: CGRect(x: 1720, y: 0, width: 1720, height: 1440),
                       position: .right),
        ForkGlanceZone(id: mac, displayUUID: "MAC", rect: CGRect(x: 938, y: 1440, width: 1728, height: 1117),
                       position: .whole),
    ]

    /// The defaults of plan §14, enabled, in Zones mode.
    static func settings(_ change: (inout ForkGlanceSettings) -> Void = { _ in }) -> ForkGlanceSettings {
        var settings = ForkGlanceSettings(
            enabled: true, mode: .zones, sensitivity: 0.4, dwell: 0.2, typingPause: 1.5, pointerPause: 1.5, raise: true,
            pointer: .stay, feedback: .halo, learnFromClicks: true, panes: false, panesClickFallback: false,
            panesApps: [], neverLeaveApps: [], neverFocusApps: [], energy: .balanced, onBattery: .saver,
            pauseInLowPower: true, idleOff: 300, duringCalls: .keepRunning, islandClosed: .paused, gazeDot: false)
        change(&settings)
        return settings
    }

    static func gaze(_ target: ForkGlanceGazeTarget, confidence: Double = 0.9, crowded: Bool = false,
                     headSpeed: Double = 0) -> ForkGlanceGaze {
        ForkGlanceGaze(estimate: nil, target: target, margin: 2, headSpeed: headSpeed, confidence: confidence,
                       crowded: crowded)
    }

    /// Calm hands: the last key and pointer move a minute ago.
    static func hands(sinceKey: TimeInterval = 60, sincePointer: TimeInterval = 60,
                      _ change: (inout ForkGlanceInputSnapshot) -> Void = { _ in }) -> ForkGlanceInputSnapshot {
        var snapshot = ForkGlanceInputSnapshot.idle
        snapshot.sinceKey = sinceKey
        snapshot.sincePointer = sincePointer
        change(&snapshot)
        return snapshot
    }

    /// Drives a machine the way the service does.
    struct Driver {
        var machine: ForkGlanceMachine
        var now: TimeInterval = 0
        /// Everything emitted, with its time.
        var log: [(time: TimeInterval, effect: ForkGlanceEffect)] = []

        var focuses: [String] { log.compactMap { if case let .focus(zone) = $0.effect { return zone } else { return nil } } }
        var focusTimes: [TimeInterval] { log.compactMap { if case .focus = $0.effect { return $0.time } else { return nil } } }

        @discardableResult
        mutating func send(_ event: ForkGlanceEvent, at time: TimeInterval? = nil) -> [ForkGlanceEffect] {
            let time = time ?? now
            tick(until: time)
            now = time
            let effects = machine.handle(event, now: time)
            record(effects, at: time)
            return effects
        }

        /// The service's single timer, fired at each deadline up to `time`.
        mutating func tick(until time: TimeInterval) {
            while let deadline = machine.nextDeadline, deadline <= time {
                now = deadline
                record(machine.handle(.tick, now: deadline), at: deadline)
            }
        }

        private mutating func record(_ effects: [ForkGlanceEffect], at time: TimeInterval) {
            for effect in effects {
                log.append((time, effect))
                if case let .focus(zone) = effect {
                    record(machine.handle(.focusResult(zone: zone, succeeded: true), now: time), at: time)
                }
            }
        }

        /// Images at `fps` from `start` (included) to `end` (excluded), the
        /// input snapshot sent before each, built from the image's time.
        mutating func look(_ target: ForkGlanceGazeTarget?, from start: TimeInterval, to end: TimeInterval,
                           fps: Double = 12, confidence: Double = 0.9, crowded: Bool = false,
                           inputs: (TimeInterval) -> ForkGlanceInputSnapshot = { _ in hands() }) {
            var index = 0.0
            while start + index / fps < end - 1e-9 {
                let time = start + index / fps
                send(.inputs(inputs(time)), at: time)
                send(.gaze(target.map { gaze($0, confidence: confidence, crowded: crowded) }), at: time)
                index += 1
            }
            tick(until: end)
        }
    }

    /// A machine watching, the keyboard in the left zone, settled after one image.
    static func watching(_ settings: ForkGlanceSettings = settings()) -> Driver {
        var driver = Driver(machine: ForkGlanceMachine(settings: settings))
        driver.send(.system(.ready), at: 0)
        driver.send(.calibrationNeed(nil), at: 0)
        driver.send(.zonesChanged(zones), at: 0)
        driver.send(.focusChanged(zone: left), at: 0)
        driver.look(.zone(left), from: 0, to: 0.5)
        return driver
    }

    static func run(_ suite: TestSuite) {
        startup(suite)
        switching(suite)
        tolerance(suite)
        guards(suite)
        pauses(suite)
        availability(suite)
        calibration(suite)
        focusResults(suite)
        inputRules(suite)
        menuWindows(suite)
    }

    private static func startup(_ suite: TestSuite) {
        var machine = ForkGlanceMachine(settings: settings())
        suite.expect(machine.phase == .starting && machine.handle(.system(.ready), now: 0).isEmpty,
                     "until the calibration is known, the camera stays off")
        let started = machine.handle(.calibrationNeed(nil), now: 0)
        suite.expect(started.first == .startCamera && started.contains(.setRate(12)) && machine.phase == .starting,
                     "once the system and a calibrated profile are known, the camera starts at the active rate")
        machine.handle(.gaze(gaze(.zone(left))), now: 0.1)
        suite.expect(machine.phase == .candidate(zone: left, current: nil, since: 0.1),
                     "with no known keyboard zone, the first gazed zone is a candidate")

        var disabled = ForkGlanceMachine(settings: settings { $0.enabled = false })
        disabled.handle(.system(.ready), now: 0)
        suite.expect(disabled.handle(.calibrationNeed(nil), now: 0).isEmpty && disabled.phase == .off,
                     "a disabled feature never starts the camera")
        suite.expect(disabled.handle(.gaze(gaze(.zone(right))), now: 1).isEmpty,
                     "an image arriving while the camera is off is dropped")
        let enabled = disabled.handle(.settings(settings()), now: 2)
        suite.expect(enabled.first == .startCamera && disabled.phase == .starting, "enabling starts the camera")

        var driver = watching()
        suite.expect(driver.machine.phase == .settled(zone: left) && driver.machine.currentZone == left,
                     "looking at the keyboard's zone settles there")
        driver.send(.settings(settings { $0.enabled = false }), at: 1)
        suite.expect(driver.log.last?.effect == .stopCamera && driver.machine.phase == .off,
                     "disabling stops the camera right away")
    }

    private static func switching(_ suite: TestSuite) {
        var driver = watching()
        driver.look(.zone(right), from: 1, to: 1.25)
        suite.expect(driver.focuses == [right], "looking right for 250 ms gives the right zone the keyboard")
        let switchTime = driver.focusTimes.first ?? 0
        suite.expect(switchTime >= 1.2 - 1e-9 && switchTime <= 1.2 + 1e-9,
                     "the switch happens at the end of the 200 ms dwell, from the timer: got \(switchTime)")
        suite.expect(driver.log.contains { $0.effect == .showFeedback(zone: right) },
                     "the halo shows once the focus took")
        suite.expect(driver.machine.currentZone == right, "the right zone now has the keyboard")
        if case let .cooldown(zone, until) = driver.machine.phase {
            suite.expect(zone == right && abs(until - 1.6) < 1e-9, "a 400 ms cooldown follows the switch")
        } else {
            suite.expect(false, "a cooldown follows the switch, got \(driver.machine.phase)")
        }
        driver.look(.zone(right), from: 1.25, to: 2)
        suite.expect(driver.machine.phase == .settled(zone: right) && driver.focuses == [right],
                     "staying on the new zone settles there, without a second switch")

        var brief = watching()
        brief.look(.zone(right), from: 1, to: 1.15)
        brief.look(.zone(left), from: 1.15, to: 2)
        suite.expect(brief.focuses.isEmpty, "a 150 ms glance right and back switches nothing")

        var same = watching()
        same.look(.zone(left), from: 1, to: 4)
        suite.expect(!same.log.contains { if case .focus = $0.effect { return true }
                                          if case .showFeedback = $0.effect { return true }
                                          return false },
                     "looking at the zone that already has the keyboard does nothing")

        var between = watching()
        between.look(.zone(right), from: 1, to: 1.15)
        between.look(.between, from: 1.15, to: 1.2)
        between.look(.zone(right), from: 1.2, to: 1.35)
        suite.expect(between.focuses.isEmpty && between.machine.currentZone == left,
                     "a gaze between zones restarts the dwell and keeps the keyboard where it is")

        var away = watching()
        away.look(.away, from: 1, to: 3)
        suite.expect(away.focuses.isEmpty && away.machine.phase == .away(zone: left),
                     "looking away (the keyboard, off the screens) never acts and keeps the zone")

        var reversal = watching()
        reversal.look(.zone(right), from: 1, to: 1.3)
        reversal.look(.zone(left), from: 1.3, to: 1.45)
        suite.expect(reversal.focuses == [right], "no switch back during the 400 ms cooldown")
        reversal.look(.zone(left), from: 1.45, to: 1.8)
        suite.expect(reversal.focuses == [right, left], "a gaze held through the cooldown switches once it ends")
        let back = reversal.focusTimes.last ?? 0
        suite.expect(back >= 1.6 - 1e-9, "the switch back waits for the cooldown: got \(back)")

        var person = watching()
        person.send(.focusChanged(zone: right), at: 1)
        person.look(.zone(right), from: 1, to: 2)
        suite.expect(person.focuses.isEmpty && person.machine.currentZone == right,
                     "after the person clicks into a zone, gazing at it does nothing")

        var gone = watching()
        gone.send(.zonesChanged([zones[1], zones[2]]), at: 1)
        suite.expect(gone.machine.currentZone == nil, "a vanished zone no longer holds the keyboard")
        gone.look(.zone(left), from: 1, to: 2)
        suite.expect(gone.focuses.isEmpty, "a gaze on a zone that no longer exists is not a candidate")
    }

    private static func tolerance(_ suite: TestSuite) {
        var blink = watching()
        blink.look(.zone(right), from: 1, to: 1 + 2 / 12.0)
        blink.look(nil, from: 1 + 2 / 12.0, to: 1 + 4 / 12.0)
        suite.expect(blink.machine.phase == .candidate(zone: right, current: left, since: 1) && blink.focuses.isEmpty,
                     "two images without a face are forgiven: the candidate holds, but cannot fire blind")
        blink.look(.zone(right), from: 1 + 4 / 12.0, to: 1.5)
        suite.expect(blink.focuses == [right] && (blink.focusTimes.first ?? 0) <= 1 + 4 / 12.0 + 1e-9,
                     "the next image on the zone switches, the dwell counted from the first one")

        var lost = watching()
        lost.look(.zone(right), from: 1, to: 1 + 2 / 12.0)
        lost.look(.noFace, from: 1 + 2 / 12.0, to: 1 + 5 / 12.0)
        suite.expect(lost.machine.phase == .searching, "the third image without a face is searching")
        lost.look(.zone(right), from: 1 + 5 / 12.0, to: 1.5)
        suite.expect(lost.focuses.isEmpty, "after searching, the dwell starts over")
        lost.look(.zone(right), from: 1.5, to: 1.7)
        suite.expect(lost.focuses == [right], "and a full dwell then switches")
    }

    private static func guards(_ suite: TestSuite) {
        var typing = watching()
        typing.look(.zone(right), from: 1, to: 2.4, inputs: { hands(sinceKey: $0 - 1) })
        suite.expect(typing.focuses.isEmpty, "while typing, looking right switches nothing")
        suite.expect(typing.machine.phase == .blocked(zone: left, guards: [.typing]),
                     "the phase says what holds the switch: typing")
        typing.look(.zone(right), from: 2.4, to: 2.8, inputs: { hands(sinceKey: $0 - 1) })
        let resumed = typing.focusTimes.first ?? 0
        suite.expect(typing.focuses == [right] && abs(resumed - 2.5) < 1e-9,
                     "the switch happens as the 1.5 s typing pause ends, the gaze still there: got \(resumed)")

        var pointer = watching()
        pointer.look(.zone(right), from: 1, to: 3, inputs: { _ in hands(sincePointer: 0.05) })
        suite.expect(pointer.focuses.isEmpty && pointer.machine.guards == [.pointer],
                     "a moving pointer has priority: no switch")

        var command = watching()
        command.look(.zone(right), from: 1, to: 3, inputs: { _ in hands { $0.modifiersDown = true } })
        suite.expect(command.focuses.isEmpty && command.machine.guards == [.buttonsOrModifiers],
                     "⌘ held: no switch")
        command.look(.zone(right), from: 3, to: 3.2)
        suite.expect(command.focuses == [right], "released, the held gaze switches at once")

        var dragging = watching()
        dragging.look(.zone(right), from: 1, to: 2, inputs: { _ in hands { $0.buttonsDown = true } })
        suite.expect(dragging.focuses.isEmpty, "a mouse button down (a drag): no switch")

        let flags: [(ForkGlanceGuard, (inout ForkGlanceInputSnapshot) -> Void, String)] = [
            (.dictation, { $0.dictationActive = true }, "the fork's Dictation records"),
            (.secureInput, { $0.secureInput = true }, "a password is being typed"),
            (.menuOrOverview, { $0.menuOrOverview = true }, "a menu or Mission Control is open"),
            (.islandOpen, { $0.islandKey = true }, "the island has the keyboard"),
            (.ownPanel, { $0.ownPanelKey = true }, "a Swishsaint window is key"),
        ]
        for (raised, change, situation) in flags {
            var driver = watching()
            driver.look(.zone(right), from: 1, to: 2, inputs: { _ in hands(change) })
            suite.expect(driver.focuses.isEmpty && driver.machine.guards == [raised], "\(situation): no switch")
        }

        var excluded = watching(settings { $0.neverLeaveApps = ["com.apple.Keynote"] })
        excluded.look(.zone(right), from: 1, to: 2, inputs: { _ in hands { $0.frontmostBundleID = "com.apple.Keynote" } })
        suite.expect(excluded.focuses.isEmpty && excluded.machine.guards == [.excludedSource],
                     "an app in « Ne jamais quitter » keeps the keyboard")

        var unsure = watching()
        unsure.look(.zone(right), from: 1, to: 2, confidence: 0.3)
        suite.expect(unsure.focuses.isEmpty && unsure.machine.guards == [.lowConfidence],
                     "a low-confidence sample switches nothing")
        var crowded = watching()
        crowded.look(.zone(right), from: 1, to: 2, crowded: true)
        suite.expect(crowded.focuses.isEmpty, "several faces of a similar size: no switch")

        var calm = watching()
        calm.look(.zone(left), from: 1, to: 2, inputs: { hands(sinceKey: $0 - 1) })
        suite.expect(calm.machine.phase == .settled(zone: left),
                     "typing while looking at the keyboard's zone is not shown as waiting")
    }

    private static func pauses(_ suite: TestSuite) {
        var lock = watching()
        lock.send(.system(change(.ready) { $0.locked = true }), at: 1)
        suite.expect(lock.log.last?.effect == .stopCamera && lock.machine.phase == .paused(.locked, until: nil),
                     "locking the Mac stops the camera")
        lock.look(.zone(right), from: 1, to: 2)
        suite.expect(lock.focuses.isEmpty, "a late image while locked does nothing")
        let unlocked = lock.send(.system(.ready), at: 3)
        suite.expect(unlocked.first == .startCamera && lock.machine.phase == .starting,
                     "unlocking starts the camera again")
        suite.expect(!lock.log.contains { if case .notice = $0.effect { return true } else { return false } },
                     "an automatic pause shows no notice")

        var timed = watching()
        let effects = timed.send(.pause(.user, until: 900), at: 1)
        suite.expect(effects == [.stopCamera, .notice(.paused(until: 900))]
                        && timed.machine.phase == .paused(.user, until: 900),
                     "a timed pause stops the camera and says so")
        suite.expect(timed.machine.nextDeadline == 900, "the pause's end is the next deadline")
        timed.send(.inputs(hands(sinceKey: 1)), at: 899)
        timed.tick(until: 900)
        suite.expect(timed.log.suffix(3).map(\.effect) == [.startCamera, .setRate(12), .notice(.resumed)]
                        && timed.log.last?.time == 900,
                     "at its end the camera starts again and « Regard repris » shows")

        var open = watching()
        open.send(.pause(.user, until: nil), at: 1)
        suite.expect(open.machine.nextDeadline == nil && open.machine.phase == .paused(.user, until: nil),
                     "« jusqu'à reprise » has no deadline")
        suite.expect(open.send(.resume(.user), at: 50) == [.startCamera, .setRate(12), .notice(.resumed)],
                     "resuming by hand starts the camera and says so")
        suite.expect(open.send(.resume(.user), at: 51).isEmpty, "resuming twice says nothing")

        var stacked = watching()
        stacked.send(.pause(.user, until: nil), at: 1)
        stacked.send(.system(change(.ready) { $0.locked = true }), at: 2)
        suite.expect(stacked.machine.phase == .paused(.user, until: nil)
                        && stacked.machine.pauses == [.user, .locked],
                     "with several pauses, the user's is shown first")
        stacked.send(.resume(.user), at: 3)
        suite.expect(stacked.machine.phase == .paused(.locked, until: nil), "resumed, the lock still holds")

        var idle = watching()
        idle.send(.inputs(hands(sinceKey: 299, sincePointer: 400)), at: 1)
        suite.expect(idle.machine.phase.isWatching, "before 5 min without input, the camera runs")
        idle.send(.inputs(hands(sinceKey: 300, sincePointer: 400)), at: 2)
        suite.expect(idle.machine.phase == .paused(.idle, until: nil) && idle.log.last?.effect == .stopCamera,
                     "after 5 min without a key or the pointer, the camera goes off")
        idle.send(.inputs(hands(sinceKey: 0.2, sincePointer: 400)), at: 3)
        suite.expect(idle.machine.phase == .starting, "the first key wakes it")

        var quiet = watching()
        quiet.send(.inputs(hands(sinceKey: 200, sincePointer: 200)), at: 1)
        quiet.tick(until: 200)
        suite.expect(quiet.machine.phase == .paused(.idle, until: nil),
                     "the idle cut comes from the timer when no input snapshot arrives")

        let system: [(String, (inout ForkGlanceSystemSnapshot) -> Void, ForkGlanceSettings, ForkGlancePauseReason?)] = [
            ("asleep", { $0.asleep = true }, settings(), .asleep),
            ("screens asleep", { $0.screensAsleep = true }, settings(), .screensAsleep),
            ("session inactive", { $0.sessionInactive = true }, settings(), .sessionInactive),
            ("on battery, « Pause »", { $0.onBattery = true }, settings { $0.onBattery = .pause }, .battery),
            ("on battery, « Économe »", { $0.onBattery = true }, settings(), nil),
            ("Low Power mode", { $0.lowPower = true }, settings(), .lowPower),
            ("Low Power mode, not paused", { $0.lowPower = true }, settings { $0.pauseInLowPower = false }, nil),
            ("serious thermal state", { $0.thermal = .serious }, settings(), .thermal),
            ("fair thermal state", { $0.thermal = .fair }, settings(), nil),
            ("official preview open", { $0.officialPreviewOpen = true }, settings(), .cameraBusy),
            ("in a call, « Pause »", { $0.cameraInUseElsewhere = true }, settings { $0.duringCalls = .pause }, .call),
            ("in a call, « Continuer »", { $0.cameraInUseElsewhere = true }, settings(), nil),
            ("Screens mode, one screen", { $0.displayCount = 1 }, settings { $0.mode = .screens }, .singleScreen),
            ("Zones mode, one screen", { $0.displayCount = 1 }, settings(), nil),
            ("lid closed on the built-in camera", { $0.lidClosedOnBuiltInCamera = true }, settings(), .lidClosedNoCamera),
        ]
        for (situation, alter, settings, expected) in system {
            var driver = watching(settings)
            driver.send(.system(change(.ready, alter)), at: 1)
            if let expected {
                suite.expect(driver.machine.phase == .paused(expected, until: nil)
                                && driver.log.contains { $0.time == 1 && $0.effect == .stopCamera },
                             "\(situation): paused, the camera off")
            } else {
                suite.expect(driver.machine.phase.isWatching, "\(situation): the camera keeps running")
            }
        }

        var lid = watching()
        let closed = lid.send(.system(change(.ready) { $0.lidClosedOnBuiltInCamera = true }), at: 1)
        suite.expect(closed.contains(.notice(.cameraUnavailable)), "the lid closing over the camera says it")

        var hot = watching()
        hot.send(.system(change(.ready) { $0.thermal = .serious }), at: 1)
        hot.send(.system(change(.ready) { $0.thermal = .critical }), at: 2)
        suite.expect(hot.machine.phase == .paused(.thermal, until: nil), "critical keeps the thermal pause")
        hot.send(.system(change(.ready) { $0.thermal = .fair }), at: 3)
        suite.expect(hot.machine.phase.isWatching, "back to fair, it resumes")

        var battery = watching(settings { $0.onBattery = .pause })
        battery.send(.system(change(.ready) { $0.onBattery = true }), at: 1)
        let anyway = battery.send(.resumeAnyway, at: 2)
        suite.expect(anyway.first == .startCamera && battery.machine.phase.isWatching,
                     "« Reprendre quand même » lifts the battery pause")
        battery.send(.system(change(.ready) { $0.onBattery = true; $0.lowPower = false }), at: 3)
        suite.expect(battery.machine.phase.isWatching, "an unrelated change keeps it lifted")
        battery.send(.system(.ready), at: 4)
        battery.send(.system(change(.ready) { $0.onBattery = true }), at: 5)
        suite.expect(battery.machine.phase == .paused(.battery, until: nil),
                     "back on battery after the charger, it pauses again")

        var locked = watching()
        locked.send(.system(change(.ready) { $0.locked = true }), at: 1)
        locked.send(.resumeAnyway, at: 2)
        suite.expect(locked.machine.phase == .paused(.locked, until: nil), "a lock cannot be overridden")
    }

    private static func availability(_ suite: TestSuite) {
        let cases: [(String, (inout ForkGlanceSystemSnapshot) -> Void, ForkGlanceUnavailable)] = [
            ("camera permission denied", { $0.cameraPermission = .denied }, .cameraPermission),
            ("camera permission not asked", { $0.cameraPermission = .notDetermined }, .cameraPermission),
            ("Accessibility missing", { $0.accessibility = false }, .accessibilityPermission),
            ("no camera", { $0.cameraPresent = false }, .noCamera),
        ]
        for (situation, alter, expected) in cases {
            var driver = watching()
            driver.send(.system(change(.ready, alter)), at: 1)
            suite.expect(driver.machine.phase == .unavailable(expected) && driver.log.last?.effect == .stopCamera,
                         "\(situation): unavailable, the camera off")
        }

        var failing = watching()
        let failed = failing.send(.cameraFailure(.cameraFailed), at: 1)
        suite.expect(failed == [.stopCamera, .notice(.cameraUnavailable)]
                        && failing.machine.phase == .unavailable(.cameraFailed),
                     "a camera failure stops it and says « Caméra indisponible »")
        suite.expect(failing.send(.cameraFailure(.cameraDisconnected), at: 2) == [],
                     "a second failure report says nothing more")
        suite.expect(failing.send(.cameraFailure(nil), at: 3).first == .startCamera,
                     "the camera back, it starts again")

        var paused = watching()
        paused.send(.pause(.user, until: nil), at: 1)
        paused.send(.system(change(.ready) { $0.accessibility = false }), at: 2)
        suite.expect(paused.machine.phase == .unavailable(.accessibilityPermission),
                     "a missing permission shows before a pause")
    }

    private static func calibration(_ suite: TestSuite) {
        var layout = watching()
        let newLayout = layout.send(.calibrationNeed(.newLayout), at: 1)
        suite.expect(newLayout == [.stopCamera, .notice(.newLayout)]
                        && layout.machine.phase == .needsCalibration(.newLayout),
                     "a new display layout asks for a calibration, once")
        suite.expect(layout.send(.calibrationNeed(.newLayout), at: 2).isEmpty, "the same need again says nothing")
        layout.look(.zone(right), from: 2, to: 3)
        suite.expect(layout.focuses.isEmpty, "uncalibrated, nothing switches")

        let started = layout.send(.calibrationStarted, at: 4)
        suite.expect(started.isEmpty && layout.machine.phase == .calibrating, "the assistant runs")
        let finished = layout.send(.calibrationFinished(score: 0.96), at: 30)
        suite.expect(finished == [.startCamera, .setRate(12), .notice(.calibrated(score: 0.96))],
                     "a finished calibration starts watching and celebrates the score")

        var running = watching()
        suite.expect(running.send(.calibrationStarted, at: 1) == [.stopCamera] && running.machine.phase == .calibrating,
                     "starting the assistant hands the camera over")
        suite.expect(running.send(.calibrationCancelled, at: 2).first == .startCamera,
                     "cancelling it goes back to watching with the old profile")

        var first = ForkGlanceMachine(settings: settings())
        first.handle(.system(.ready), now: 0)
        suite.expect(first.handle(.calibrationNeed(.firstTime), now: 0).isEmpty
                        && first.phase == .needsCalibration(.firstTime),
                     "never calibrated: waiting for the assistant, without a notice")
    }

    private static func focusResults(_ suite: TestSuite) {
        var quiet = watching(settings { $0.feedback = .none })
        quiet.look(.zone(right), from: 1, to: 1.3)
        suite.expect(quiet.focuses == [right] && !quiet.log.contains { $0.effect == .showFeedback(zone: right) },
                     "without feedback chosen, no halo")

        var driver = watching()
        driver.send(.inputs(hands()), at: 1)
        driver.send(.gaze(gaze(.zone(right))), at: 1)
        let effects = driver.machine.handle(.gaze(gaze(.zone(right))), now: 1.25)
        suite.expect(effects.contains(.focus(zone: right)), "the switch is asked for")
        let failed = driver.machine.handle(.focusResult(zone: right, succeeded: false), now: 1.25)
        suite.expect(!failed.contains(.showFeedback(zone: right)) && driver.machine.currentZone == left,
                     "a failed focus gives the keyboard's zone back, without a halo")
        var retries = 0
        for step in 1...20 {
            let time = 1.25 + Double(step) / 12
            retries += driver.machine.handle(.gaze(gaze(.zone(right))), now: time).filter { $0 == .focus(zone: right) }
                .count
            _ = driver.machine.handle(.tick, now: time)
        }
        suite.expect(retries == 0, "a failed zone is not retried while the gaze stays on it")
        driver.machine.handle(.gaze(gaze(.zone(left))), now: 3)
        var again: [ForkGlanceEffect] = []
        for step in 1...6 {
            again += driver.machine.handle(.gaze(gaze(.zone(right))), now: 3 + Double(step) / 12)
        }
        suite.expect(again.contains(.focus(zone: right)), "after looking away from it, the zone may be tried again")
    }

    // MARK: The input watch's rules (Pure/ForkGlanceInputRules)

    private static func inputRules(_ suite: TestSuite) {
        let rules = ForkGlanceInputRules.self
        suite.expect(rules.isGlancePointer(at: 10.1, from: 10, until: 10.3),
                     "a pointer event inside Glance's warp window is Glance's own")
        suite.expect(!rules.isGlancePointer(at: 9.9, from: 10, until: 10.3)
                     && !rules.isGlancePointer(at: 10.4, from: 10, until: 10.3),
                     "a pointer event before or after the warp window is the person's")
        suite.expect(!rules.isGlancePointer(at: 0, from: 0, until: 0),
                     "before any warp, no pointer event is Glance's")
        suite.expect(rules.isRealClick(sourcePID: 0, userData: 0, ownPID: 42),
                     "a hardware click (no poster, no marker) is the person's")
        suite.expect(!rules.isRealClick(sourcePID: 42, userData: 0, ownPID: 42),
                     "a click this app posted never teaches the model")
        suite.expect(!rules.isRealClick(sourcePID: 0, userData: rules.syntheticClickMarker, ownPID: 42),
                     "the panes' fallback click, marked, never teaches the model")
        suite.expect(!rules.isRealClick(sourcePID: 77, userData: 0x1234, ownPID: 42),
                     "a click another program posted with a marker is not the person's")
    }

    private static func window(pid: Int32, layer: Int, owner: String = "App", alpha: Double = 1,
                               _ rect: CGRect) -> [String: Any] {
        [kCGWindowOwnerPID as String: NSNumber(value: pid), kCGWindowLayer as String: layer,
         kCGWindowOwnerName as String: owner, kCGWindowAlpha as String: alpha,
         kCGWindowBounds as String: rect.dictionaryRepresentation as NSDictionary]
    }

    private static func menuWindows(_ suite: TestSuite) {
        let rules = ForkGlanceMenuWindows.self
        let own: pid_t = 42
        let lg = CGSize(width: 3440, height: 1440)
        let sizes = [lg, CGSize(width: 1728, height: 1117)]
        let full = CGRect(origin: .zero, size: lg)
        var asked: [pid_t] = []
        func hit(_ windows: [[String: Any]], ids: [pid_t: String] = [:]) -> ForkGlanceMenuWindows.Hit? {
            rules.hit(in: windows, ownPID: own, displaySizes: sizes) { pid in
                asked.append(pid)
                return ids[pid] ?? ""
            }
        }
        let menu = CGRect(x: 100, y: 30, width: 220, height: 300)
        suite.expect(hit([window(pid: 7, layer: rules.menuLayer, menu)]) == .menu,
                     "another app's menu (layer 101) holds the menu guard")
        suite.expect(hit([window(pid: own, layer: rules.menuLayer, menu)]) == nil,
                     "this app's own menus and tooltips never count (its menus come from NSMenu)")
        suite.expect(hit([window(pid: 7, layer: rules.menuLayer, alpha: 0, menu)]) == nil,
                     "a transparent window at the menu layer is no menu")
        suite.expect(hit([window(pid: 7, layer: rules.menuLayer, CGRect(x: 0, y: 0, width: 1, height: 1))]) == nil,
                     "a one-point sliver at the menu layer is no menu")
        suite.expect(hit([window(pid: 9, layer: 18, owner: "Dock", full)]) == .overview,
                     "Dock's window covering a display at layer 18 is Mission Control")
        suite.expect(hit([window(pid: 9, layer: 18, owner: "Dock", CGRect(x: 0, y: 1300, width: 900, height: 80))]) == nil,
                     "Dock's own strip, not covering a display, is no overview")
        suite.expect(hit([window(pid: 9, layer: 19, owner: "WindowManager", full)]) == .overview,
                     "WindowManager's display-wide window at layer 19 is the overview of recent macOS")
        suite.expect(hit([window(pid: 9, layer: 18, owner: "WindowManager", full)]) == nil,
                     "Show Desktop's layer 18 stays out")
        asked = []
        suite.expect(hit([window(pid: 11, layer: 25, owner: "screencaptureui", full)],
                         ids: [11: rules.screenshotBundleID]) == .screenshot,
                     "screencaptureui covering a display is a screenshot selection")
        suite.expect(asked == [11], "the bundle id is asked only for the window that covers a display")
        suite.expect(hit([window(pid: 11, layer: 0, full)], ids: [11: rules.screenshotBundleID]) == nil,
                     "a window at layer 0, even of screencaptureui, is an ordinary window")
        asked = []
        suite.expect(hit([window(pid: 12, layer: 3, full)], ids: [12: "com.example.player"]) == nil,
                     "another app's full-display window above layer 0 is no guard")
        suite.expect(hit([window(pid: 7, layer: 0, menu), window(pid: 7, layer: rules.menuLayer, menu)]) == .menu,
                     "the list is read to the end: a menu behind an ordinary window still counts")
        suite.expect(hit([]) == nil && rules.bounds(of: [:]) == .zero, "no window, no guard; no bounds, a zero rect")
    }

    static func change<Value>(_ value: Value, _ alter: (inout Value) -> Void) -> Value {
        var copy = value
        alter(&copy)
        return copy
    }
}
