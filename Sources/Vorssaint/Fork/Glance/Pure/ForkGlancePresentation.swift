// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// The machine's phase as every surface draws it (plan §9): the settings
/// header, the island's section, tile and activity. Words come later, from
/// `ForkGlanceStatusLine` and the core strings; this says which line, which
/// symbol, which tint.
enum ForkGlancePresentation {
    /// « Visage non détecté » and « Regard ailleurs » only after this long:
    /// a glance at the keyboard is not news.
    static let facelessDelay: TimeInterval = 3

    /// - Parameters:
    ///   - zoneName: the zone's name (« Zone gauche du LG »), nil if unknown.
    ///   - calibration: points done and total while the assistant runs.
    ///   - facelessFor: how long the phase has been `searching` or `away`.
    ///   - pausedUntil: a timed user pause's end on the wall clock (the
    ///     phase carries systemUptime); ignored for every other pause.
    static func status(_ phase: ForkGlancePhase, zoneName: (String) -> String?, calibration: (done: Int, total: Int)?,
                       facelessFor: TimeInterval, pausedUntil: Date?) -> ForkGlanceStatusLine {
        func active(_ zone: String?) -> ForkGlanceStatusLine { .active(zoneName: zone.flatMap(zoneName)) }
        switch phase {
        case .off:
            return .off
        case let .unavailable(reason):
            return .unavailable(reason)
        case let .needsCalibration(need):
            return .needsCalibration(need)
        case .calibrating:
            return .calibrating(done: calibration?.done ?? 0, total: calibration?.total ?? 0)
        case let .paused(reason, until):
            return .paused(reason, until: reason == .user && until != nil ? pausedUntil : nil)
        case .starting:
            return .starting
        case .searching:
            return facelessFor >= facelessDelay ? .noFace : active(nil)
        case let .away(zone):
            return facelessFor >= facelessDelay ? .away : active(zone)
        case let .settled(zone), let .cooldown(zone, _):
            return active(zone)
        case let .candidate(_, current, _):
            return active(current)
        case let .blocked(zone, guards):
            return guards.first.map(ForkGlanceStatusLine.waiting) ?? active(zone)
        }
    }

    /// SF Symbols (plan §2), all present since macOS 11.
    static func symbol(_ phase: ForkGlancePhase) -> String {
        switch phase {
        case .unavailable: return "exclamationmark.triangle"
        case .needsCalibration, .calibrating: return "viewfinder"
        case .paused: return "eye.slash"
        case .off, .starting, .searching, .away, .settled, .candidate, .blocked, .cooldown: return "eyes"
        }
    }

    enum Tint: Equatable {
        /// Watching, the keyboard follows (or the assistant runs).
        case active
        /// Off, or watching without a usable gaze.
        case idle
        case paused
        /// Waiting for a calibration.
        case warning
        case error
    }

    static func tint(_ phase: ForkGlancePhase) -> Tint {
        switch phase {
        case .off, .searching, .away: return .idle
        case .unavailable: return .error
        case .needsCalibration: return .warning
        case .paused: return .paused
        case .calibrating, .starting, .settled, .candidate, .blocked, .cooldown: return .active
        }
    }

    /// The Controls tile lights up exactly while the camera watches (plan §9):
    /// a pause, a calibration, a missing permission or calibration grey it.
    static func tileIsActive(_ phase: ForkGlancePhase) -> Bool {
        phase.isWatching
    }
}
