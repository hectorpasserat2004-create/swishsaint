// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// How fast the camera looks, and when it should not look at all (plan §7.5,
/// §10.2). Pure: the machine asks it at each image, the tests drive it with
/// an injected clock.
///
/// The rate follows what can happen next. A switch on its way (a candidate)
/// wants every image; a key or the pointer in use means no switch can happen
/// for a while, so a few images keep the face tracked; a still head needs
/// fewer than a turning one. Going up is immediate, so the first turn of the
/// head is never missed; going down waits until the lower rate has been
/// asked for 2 s in a row, so the camera is not reconfigured at every key.
///
/// | Situation                      | Balanced | Reactive | Saver |
/// |--------------------------------|----------|----------|-------|
/// | Candidate, or head moving      | 12       | 15       | 8     |
/// | Head still for 2 s             | 6        | 10       | 4     |
/// | `typing` guard                 | 3        | 5        | 2     |
/// | `pointer` guard                | 4        | 6        | 3     |
///
/// Order: a candidate first (its latency is the feature), then the typing
/// and pointer guards (no switch can happen, a head move changes nothing),
/// then the head's motion.
struct ForkGlanceGovernor {
    /// Filtered yaw or pitch speed past which the head is moving, °/s.
    static let movingSpeed: Double = 20
    /// The head counts as still after this long without moving.
    static let stillAfter: TimeInterval = 2
    /// A lower rate is applied once asked for this long in a row.
    static let downHysteresis: TimeInterval = 2

    /// Images per second for one energy profile.
    struct Rates: Equatable {
        var active: Double
        var still: Double
        var typing: Double
        var pointer: Double
    }

    static func rates(_ energy: ForkGlanceEnergy) -> Rates {
        switch energy {
        case .balanced: return Rates(active: 12, still: 6, typing: 3, pointer: 4)
        case .reactive: return Rates(active: 15, still: 10, typing: 5, pointer: 6)
        case .saver: return Rates(active: 8, still: 4, typing: 2, pointer: 3)
        }
    }

    private var current: Double?
    /// Since when a lower rate than `current` is asked for.
    private var lowerSince: TimeInterval?
    /// The last image where the head moved; the first call counts as one.
    private var lastMoving: TimeInterval?

    init() {}

    /// The profile in force: the person's, unless the Mac asks for less.
    /// On battery with « Économe », in Low Power mode or when the Mac warms
    /// up (`fair` and over, a `serious` one the person resumed anyway), the
    /// saver profile is forced.
    static func energy(settings: ForkGlanceSettings, system: ForkGlanceSystemSnapshot) -> ForkGlanceEnergy {
        if system.onBattery && settings.onBattery == .saver { return .saver }
        if system.lowPower || system.thermal >= .fair { return .saver }
        return settings.energy
    }

    /// The pauses the Mac's state calls for (plan §7.5), before any
    /// « Reprendre quand même ». `sinceInput`: seconds since the last key or
    /// pointer move, infinity when none was ever seen.
    ///
    /// The thermal pause starts at `serious` and ends at `fair`: with the
    /// four states macOS reports, that is « paused while serious or critical ».
    static func automaticPauses(settings: ForkGlanceSettings, system: ForkGlanceSystemSnapshot,
                                sinceInput: TimeInterval) -> Set<ForkGlancePauseReason> {
        var reasons = Set<ForkGlancePauseReason>()
        if system.locked { reasons.insert(.locked) }
        if system.asleep { reasons.insert(.asleep) }
        if system.screensAsleep { reasons.insert(.screensAsleep) }
        if system.sessionInactive { reasons.insert(.sessionInactive) }
        if system.onBattery && settings.onBattery == .pause { reasons.insert(.battery) }
        if system.lowPower && settings.pauseInLowPower { reasons.insert(.lowPower) }
        if system.thermal >= .serious { reasons.insert(.thermal) }
        if system.officialPreviewOpen { reasons.insert(.cameraBusy) }
        if system.cameraInUseElsewhere && settings.duringCalls == .pause { reasons.insert(.call) }
        if settings.mode == .screens && system.displayCount < 2 { reasons.insert(.singleScreen) }
        if system.lidClosedOnBuiltInCamera { reasons.insert(.lidClosedNoCamera) }
        if let idleOff = settings.idleOff, sinceInput >= idleOff { reasons.insert(.idle) }
        return reasons
    }

    /// The rate to run the camera at now. `moving`: this image's head speed
    /// is past `movingSpeed`; `candidate`: a switch is being considered;
    /// `guards`: the ones raised at this image.
    mutating func rate(settings: ForkGlanceSettings, system: ForkGlanceSystemSnapshot, moving: Bool, candidate: Bool,
                       guards: [ForkGlanceGuard], now: TimeInterval) -> Double {
        if moving || lastMoving == nil { lastMoving = now }
        let rates = Self.rates(Self.energy(settings: settings, system: system))
        let still = now - (lastMoving ?? now) >= Self.stillAfter
        let wanted: Double
        if candidate {
            wanted = rates.active
        } else if guards.contains(.typing) {
            wanted = rates.typing
        } else if guards.contains(.pointer) {
            wanted = rates.pointer
        } else {
            wanted = still ? rates.still : rates.active
        }

        guard let current, wanted <= current else {
            current = wanted
            lowerSince = nil
            return wanted
        }
        if wanted == current {
            lowerSince = nil
            return current
        }
        let since = lowerSince ?? now
        lowerSince = since
        if now - since >= Self.downHysteresis {
            self.current = wanted
            lowerSince = nil
            return wanted
        }
        return current
    }

    /// Forgets the rate and the head's motion: the camera starts again.
    mutating func reset() {
        current = nil
        lowerSince = nil
        lastMoving = nil
    }
}
