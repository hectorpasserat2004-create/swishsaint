// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// The official "Support Vorssaint" window never opens in the fork.
enum ForkSupportPopupTests {
    static func run(_ suite: TestSuite) {
        var seen = 0
        var next = 0
        let skipped = ForkSupportPopup.skip(isReview: false, markSeen: { seen += 1 }, next: { next += 1 })
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        suite.expect(skipped && seen == 1 && next == 1,
                     "after an update the window is skipped, marked as seen, and the next intros follow")

        seen = 0
        next = 0
        let replay = ForkSupportPopup.skip(isReview: true, markSeen: { seen += 1 }, next: { next += 1 })
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        suite.expect(replay && seen == 0 && next == 0,
                     "replaying the update tour skips it too, without touching the update state")

        let delegate = (try? String(contentsOfFile: "Sources/Vorssaint/App/AppDelegate.swift", encoding: .utf8)) ?? ""
        suite.expect(delegate.contains("    private func showSupportUpdateIntro(isReview: Bool = false) {\n"
                + "        if ForkSupportPopup.skip(isReview: isReview, markSeen: markSupportUpdateIntroSeen, "
                + "next: { [weak self] in self?.presentUpdateIntros() }) { return } // FORK(no-support-popup)\n"),
                     "the seam no-support-popup opens showSupportUpdateIntro")
    }
}
