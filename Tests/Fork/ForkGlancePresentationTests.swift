// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// Suite `fork-glance-presentation` — A5: state to symbols, tints and status (plan §9).
enum ForkGlancePresentationTests {
    private static let names = ["LG#0": "Zone gauche du LG", "LG#1": "Zone droite du LG"]
    private static let end = Date(timeIntervalSince1970: 1_792_000_000)

    private static func status(_ phase: ForkGlancePhase, calibration: (done: Int, total: Int)? = nil,
                               facelessFor: TimeInterval = 0, pausedUntil: Date? = nil) -> ForkGlanceStatusLine {
        ForkGlancePresentation.status(phase, zoneName: { names[$0] }, calibration: calibration,
                                      facelessFor: facelessFor, pausedUntil: pausedUntil)
    }

    /// One of each phase.
    private static let phases: [ForkGlancePhase] = [
        .off, .unavailable(.cameraPermission), .needsCalibration(.newLayout), .calibrating,
        .paused(.user, until: 900), .starting, .searching, .away(zone: "LG#0"), .settled(zone: "LG#0"),
        .candidate(zone: "LG#1", current: "LG#0", since: 1), .blocked(zone: "LG#0", guards: [.typing]),
        .cooldown(zone: "LG#1", until: 2),
    ]

    static func run(_ suite: TestSuite) {
        lines(suite)
        looks(suite)
    }

    private static func lines(_ suite: TestSuite) {
        suite.expect(status(.off) == .off, "off says off")
        suite.expect(status(.unavailable(.accessibilityPermission)) == .unavailable(.accessibilityPermission),
                     "a missing permission is named")
        suite.expect(status(.needsCalibration(.newCamera)) == .needsCalibration(.newCamera),
                     "a calibration need carries its reason")
        suite.expect(status(.calibrating, calibration: (12, 30)) == .calibrating(done: 12, total: 30),
                     "the calibration shows its progress, « 12/30 »")
        suite.expect(status(.calibrating) == .calibrating(done: 0, total: 0), "before the first point, 0 of 0")
        suite.expect(status(.starting) == .starting, "« Démarrage de la caméra… »")

        suite.expect(status(.settled(zone: "LG#0")) == .active(zoneName: "Zone gauche du LG"),
                     "settled: « Actif · Zone gauche du LG »")
        suite.expect(status(.settled(zone: nil)) == .active(zoneName: nil), "before any zone, active without a name")
        suite.expect(status(.settled(zone: "win:42")) == .active(zoneName: nil), "an unnamed zone shows no name")
        suite.expect(status(.candidate(zone: "LG#1", current: "LG#0", since: 1)) == .active(zoneName: "Zone gauche du LG"),
                     "a candidate still names the zone that has the keyboard")
        suite.expect(status(.cooldown(zone: "LG#1", until: 2)) == .active(zoneName: "Zone droite du LG"),
                     "right after a switch, the new zone")
        suite.expect(status(.blocked(zone: "LG#0", guards: [.typing, .pointer])) == .waiting(.typing),
                     "blocked: « En attente : vous tapez », the first guard")
        suite.expect(status(.blocked(zone: "LG#0", guards: [])) == .active(zoneName: "Zone gauche du LG"),
                     "blocked with no guard listed reads as active")

        suite.expect(status(.searching, facelessFor: 2.9) == .active(zoneName: nil)
                        && status(.searching, facelessFor: 3) == .noFace,
                     "« Visage non détecté » only after 3 s")
        suite.expect(status(.away(zone: "LG#0"), facelessFor: 1) == .active(zoneName: "Zone gauche du LG")
                        && status(.away(zone: "LG#0"), facelessFor: 4) == .away,
                     "a glance at the keyboard is not news; looking away for 3 s is")

        suite.expect(status(.paused(.user, until: 900), pausedUntil: end) == .paused(.user, until: end),
                     "a timed pause shows its end, « reprise à 15:42 »")
        suite.expect(status(.paused(.user, until: nil), pausedUntil: end) == .paused(.user, until: nil),
                     "« jusqu'à reprise » has no time")
        suite.expect(status(.paused(.battery, until: nil), pausedUntil: end) == .paused(.battery, until: nil),
                     "an automatic pause has no time")
    }

    private static func looks(_ suite: TestSuite) {
        suite.expect(ForkGlancePresentation.symbol(.paused(.idle, until: nil)) == "eye.slash", "a pause is eye.slash")
        suite.expect(ForkGlancePresentation.symbol(.calibrating) == "viewfinder"
                        && ForkGlancePresentation.symbol(.needsCalibration(.firstTime)) == "viewfinder",
                     "calibrating, or waiting for it, is the viewfinder")
        suite.expect(ForkGlancePresentation.symbol(.settled(zone: nil)) == "eyes"
                        && ForkGlancePresentation.symbol(.off) == "eyes",
                     "the feature itself is eyes")
        suite.expect(ForkGlancePresentation.symbol(.unavailable(.cameraFailed)) == "exclamationmark.triangle",
                     "a fault is a warning triangle")
        suite.expect(phases.allSatisfy { !ForkGlancePresentation.symbol($0).isEmpty }, "every phase has a symbol")

        suite.expect(ForkGlancePresentation.tint(.off) == .idle && ForkGlancePresentation.tint(.searching) == .idle,
                     "off and faceless are grey")
        suite.expect(ForkGlancePresentation.tint(.unavailable(.noCamera)) == .error, "unavailable is red")
        suite.expect(ForkGlancePresentation.tint(.needsCalibration(.newLayout)) == .warning,
                     "waiting for a calibration is yellow")
        suite.expect(ForkGlancePresentation.tint(.paused(.user, until: nil)) == .paused, "a pause has its tint")
        suite.expect(ForkGlancePresentation.tint(.blocked(zone: nil, guards: [.typing])) == .active
                        && ForkGlancePresentation.tint(.settled(zone: "LG#0")) == .active,
                     "watching, held back or not, is active")

        for phase in phases {
            suite.expect(ForkGlancePresentation.tileIsActive(phase) == phase.isWatching,
                         "the tile is lit exactly while the camera watches: \(phase)")
        }
        suite.expect(!ForkGlancePresentation.tileIsActive(.paused(.user, until: nil))
                        && !ForkGlancePresentation.tileIsActive(.calibrating)
                        && ForkGlancePresentation.tileIsActive(.blocked(zone: nil, guards: [.pointer])),
                     "paused or calibrating greys the tile; waiting on a guard does not")
    }
}
