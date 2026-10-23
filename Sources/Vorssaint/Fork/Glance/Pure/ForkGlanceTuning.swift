// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// The Glance Focus settings a person tunes as a short ladder of steps, like
/// `ForkTrackpadTuning`: « Prudent ↔ Vif » means something, a margin of 0.4 σ
/// does not. A step is stored as its index; each ladder reads left to right
/// the way its slider does.
enum ForkGlanceTuning: CaseIterable {
    /// The extra entry margin `s`, in σ (plan §7.2): less is livelier.
    case sensitivity
    /// The dwell before a switch in Zones and Windows modes (plan §7.3).
    case dwell
    /// The same in Screens mode.
    case dwellScreens
    /// No switch this long after a key (the `typing` guard).
    case typingPause
    /// No switch this long after the pointer moved (the `pointer` guard).
    case pointerPause
    /// The camera goes off after this long without input; the last step is never.
    case idleOff

    var key: String {
        switch self {
        case .sensitivity: return ForkDefaultsKey.glanceSensitivityStep
        case .dwell: return ForkDefaultsKey.glanceDwellStep
        case .dwellScreens: return ForkDefaultsKey.glanceDwellScreensStep
        case .typingPause: return ForkDefaultsKey.glanceTypingPauseStep
        case .pointerPause: return ForkDefaultsKey.glancePointerPauseStep
        case .idleOff: return ForkDefaultsKey.glanceIdleOffStep
        }
    }

    /// The values, left to right on the slider (seconds for durations).
    var steps: [Double] {
        switch self {
        case .sensitivity: return [0.9, 0.6, 0.4, 0.25, 0.1]
        case .dwell, .dwellScreens: return [0.12, 0.2, 0.3, 0.45, 0.7]
        case .typingPause: return [0.5, 1, 1.5, 2.5, 4]
        case .pointerPause: return [0.5, 1, 1.5, 3, 5]
        case .idleOff: return [120, 300, 600, 1800, .infinity]
        }
    }

    var defaultStep: Int {
        switch self {
        case .sensitivity: return 2
        case .dwell: return 1
        case .dwellScreens: return 2
        case .typingPause: return 2
        case .pointerPause: return 2
        case .idleOff: return 1
        }
    }

    var defaultValue: Double { steps[defaultStep] }

    /// A stored step, kept on the ladder.
    func clampedStep(_ stored: Int) -> Int {
        min(max(stored, 0), steps.count - 1)
    }

    func value(atStep stored: Int) -> Double {
        steps[clampedStep(stored)]
    }

    func value(in defaults: UserDefaults) -> Double {
        let stored = defaults.object(forKey: key) as? Int ?? defaultStep
        return value(atStep: stored)
    }
}
