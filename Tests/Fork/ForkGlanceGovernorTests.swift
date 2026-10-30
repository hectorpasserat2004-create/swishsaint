// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// Suite `fork-glance-governor` — A5: frame rate and camera cuts (plan §7.5, §10.2).
enum ForkGlanceGovernorTests {
    private typealias Machine = ForkGlanceMachineTests

    static func run(_ suite: TestSuite) {
        table(suite)
        hysteresis(suite)
        energy(suite)
        cuts(suite)
    }

    /// A first answer: no hysteresis yet, so it is the row's rate.
    private static func firstRate(_ settings: ForkGlanceSettings = Machine.settings(),
                                  system: ForkGlanceSystemSnapshot = .ready, moving: Bool = false,
                                  candidate: Bool = false, guards: [ForkGlanceGuard] = []) -> Double {
        var governor = ForkGlanceGovernor()
        return governor.rate(settings: settings, system: system, moving: moving, candidate: candidate, guards: guards,
                             now: 10)
    }

    /// The rate once the head has been still long enough to settle.
    private static func stillRate(_ settings: ForkGlanceSettings, system: ForkGlanceSystemSnapshot = .ready) -> Double {
        var governor = ForkGlanceGovernor()
        var rate = 0.0
        for step in 0...10 {
            rate = governor.rate(settings: settings, system: system, moving: false, candidate: false, guards: [],
                                 now: Double(step))
        }
        return rate
    }

    private static func table(_ suite: TestSuite) {
        let rows: [(ForkGlanceEnergy, active: Double, still: Double, typing: Double, pointer: Double)] = [
            (.balanced, 12, 6, 3, 4),
            (.reactive, 15, 10, 5, 6),
            (.saver, 8, 4, 2, 3),
        ]
        for row in rows {
            let settings = Machine.settings { $0.energy = row.0 }
            let name = row.0.rawValue
            suite.expect(firstRate(settings, moving: true) == row.active, "\(name): a moving head, \(row.active) img/s")
            suite.expect(firstRate(settings, candidate: true) == row.active,
                         "\(name): a candidate, \(row.active) img/s")
            suite.expect(stillRate(settings) == row.still, "\(name): a head still for 2 s, \(row.still) img/s")
            suite.expect(firstRate(settings, guards: [.typing]) == row.typing, "\(name): typing, \(row.typing) img/s")
            suite.expect(firstRate(settings, guards: [.pointer]) == row.pointer,
                         "\(name): the pointer in use, \(row.pointer) img/s")
            suite.expect(firstRate(settings, guards: [.pointer, .typing]) == row.typing,
                         "\(name): typing and the pointer, the typing rate")
            suite.expect(firstRate(settings, candidate: true, guards: [.typing]) == row.active,
                         "\(name): a candidate held by typing still gets every image")
        }

        var governor = ForkGlanceGovernor()
        let settings = Machine.settings()
        _ = governor.rate(settings: settings, system: .ready, moving: true, candidate: false, guards: [], now: 0)
        let early = governor.rate(settings: settings, system: .ready, moving: false, candidate: false, guards: [],
                                  now: 1.9)
        suite.expect(early == 12, "a head that stopped less than 2 s ago is still treated as moving")
    }

    private static func hysteresis(_ suite: TestSuite) {
        let settings = Machine.settings()
        var governor = ForkGlanceGovernor()
        func ask(_ guards: [ForkGlanceGuard], candidate: Bool = false, at time: TimeInterval) -> Double {
            governor.rate(settings: settings, system: .ready, moving: false, candidate: candidate, guards: guards,
                          now: time)
        }
        suite.expect(ask([], candidate: true, at: 0) == 12, "a candidate starts at the active rate")
        suite.expect(ask([.typing], at: 0.5) == 12 && ask([.typing], at: 2.4) == 12,
                     "a lower rate waits 2 s before it applies")
        suite.expect(ask([.typing], at: 2.5) == 3, "asked for 2 s in a row, the lower rate applies")
        suite.expect(ask([], candidate: true, at: 2.6) == 12, "going up is immediate")
        suite.expect(ask([.typing], at: 3) == 12 && ask([], candidate: true, at: 4) == 12
                        && ask([.typing], at: 4.5) == 12 && ask([.typing], at: 6.4) == 12,
                     "a rise in between restarts the 2 s wait")
        suite.expect(ask([.typing], at: 6.5) == 3, "then the lower rate applies")
        suite.expect(ask([.pointer], at: 7) == 4, "from typing to the pointer is a rise: immediate")

        var restarted = ForkGlanceGovernor()
        _ = restarted.rate(settings: settings, system: .ready, moving: false, candidate: false, guards: [.typing],
                           now: 0)
        restarted.reset()
        suite.expect(restarted.rate(settings: settings, system: .ready, moving: false, candidate: false, guards: [],
                                    now: 100) == 12,
                     "a camera restart forgets the old rate and starts active")
    }

    private static func energy(_ suite: TestSuite) {
        let reactive = Machine.settings { $0.energy = .reactive }
        let battery = ForkGlanceMachineTests.change(ForkGlanceSystemSnapshot.ready) { $0.onBattery = true }
        suite.expect(ForkGlanceGovernor.energy(settings: reactive, system: battery) == .saver
                        && firstRate(reactive, system: battery, candidate: true) == 8,
                     "on battery with « Économe », the saver rates apply")
        let same = Machine.settings { $0.energy = .reactive; $0.onBattery = .same }
        suite.expect(ForkGlanceGovernor.energy(settings: same, system: battery) == .reactive,
                     "on battery with « Comme sur secteur », the person's profile stays")
        suite.expect(ForkGlanceGovernor.energy(settings: reactive, system: .ready) == .reactive,
                     "on the charger, the person's profile")

        let lowPower = ForkGlanceMachineTests.change(ForkGlanceSystemSnapshot.ready) { $0.lowPower = true }
        suite.expect(ForkGlanceGovernor.energy(settings: reactive, system: lowPower) == .saver,
                     "Low Power mode (not paused) forces the saver rates")
        let fair = ForkGlanceMachineTests.change(ForkGlanceSystemSnapshot.ready) { $0.thermal = .fair }
        suite.expect(ForkGlanceGovernor.energy(settings: reactive, system: fair) == .saver,
                     "a warm Mac (fair) gets the saver rates")
        let nominal = ForkGlanceMachineTests.change(ForkGlanceSystemSnapshot.ready) { $0.thermal = .nominal }
        suite.expect(ForkGlanceGovernor.energy(settings: reactive, system: nominal) == .reactive,
                     "a cool Mac keeps the person's profile")
        suite.expect(stillRate(Machine.settings(), system: battery) == 4, "on battery, a still head is 4 img/s")
    }

    private static func cuts(_ suite: TestSuite) {
        func pauses(_ settings: ForkGlanceSettings = Machine.settings(), sinceInput: TimeInterval = 1,
                    _ alter: (inout ForkGlanceSystemSnapshot) -> Void = { _ in }) -> Set<ForkGlancePauseReason> {
            ForkGlanceGovernor.automaticPauses(settings: settings, system: ForkGlanceMachineTests.change(.ready, alter),
                                               sinceInput: sinceInput)
        }
        suite.expect(pauses().isEmpty, "a ready Mac in use has no pause")
        suite.expect(pauses { $0.locked = true } == [.locked] && pauses { $0.asleep = true } == [.asleep]
                        && pauses { $0.screensAsleep = true } == [.screensAsleep]
                        && pauses { $0.sessionInactive = true } == [.sessionInactive],
                     "locked, asleep, screens asleep, another session: each pauses")
        suite.expect(pauses(Machine.settings { $0.onBattery = .pause }) { $0.onBattery = true } == [.battery],
                     "on battery with « Pause »: paused")
        suite.expect(pauses { $0.onBattery = true }.isEmpty, "on battery with « Économe »: slower, not paused")
        suite.expect(pauses { $0.lowPower = true } == [.lowPower], "Low Power mode pauses by default")
        suite.expect(pauses(Machine.settings { $0.pauseInLowPower = false }) { $0.lowPower = true }.isEmpty,
                     "unless the person turned that off")
        suite.expect(pauses { $0.thermal = .serious } == [.thermal] && pauses { $0.thermal = .critical } == [.thermal],
                     "serious or critical heat pauses")
        suite.expect(pauses { $0.thermal = .fair }.isEmpty, "fair heat resumes")
        suite.expect(pauses { $0.officialPreviewOpen = true } == [.cameraBusy],
                     "the official camera preview open: the two sessions would fight, paused")
        suite.expect(pauses(Machine.settings { $0.duringCalls = .pause }) { $0.cameraInUseElsewhere = true } == [.call],
                     "a call with « Pause »: paused")
        suite.expect(pauses { $0.cameraInUseElsewhere = true }.isEmpty, "a call with « Continuer »: running")
        suite.expect(pauses(Machine.settings { $0.mode = .screens }) { $0.displayCount = 1 } == [.singleScreen],
                     "Screens mode with one screen: paused")
        suite.expect(pauses { $0.displayCount = 1 }.isEmpty, "Zones mode works on one screen")
        suite.expect(pauses { $0.lidClosedOnBuiltInCamera = true } == [.lidClosedNoCamera],
                     "the lid closed over the chosen camera: paused")

        suite.expect(pauses(sinceInput: 299).isEmpty && pauses(sinceInput: 300) == [.idle],
                     "5 min without input: the camera goes off")
        suite.expect(pauses(Machine.settings { $0.idleOff = 120 }, sinceInput: 120) == [.idle],
                     "the idle delay follows the setting")
        suite.expect(pauses(Machine.settings { $0.idleOff = nil }, sinceInput: .infinity).isEmpty,
                     "« jamais »: never off for inactivity")
    }
}
