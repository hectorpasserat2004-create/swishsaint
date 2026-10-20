// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// What every pump of one final pass shares (`ForkMeetingFinalizer`): when
/// a sample last moved, and how to let each pump go when nothing moves any
/// more.
///
/// Completed and stalled exclude each other, under the lock: the stall
/// watch could otherwise cancel the writer just as the last sample went
/// in, and the pass then call `endSession` / `finishWriting` on a cancelled
/// writer, an Objective-C exception ("Cannot call method when status is 4")
/// that kills the app.
final class ForkMeetingPassFlow: @unchecked Sendable {
    private let lock = NSLock()
    private var lastMove: UInt64
    private var releases: [() -> Void] = []
    private var stalled = false
    private var completed = false

    init(now: UInt64 = DispatchTime.now().uptimeNanoseconds) {
        lastMove = now
    }

    var isStalled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stalled
    }

    func moved(now: UInt64 = DispatchTime.now().uptimeNanoseconds) {
        lock.lock()
        lastMove = max(lastMove, now)
        lock.unlock()
    }

    func onStall(_ release: @escaping () -> Void) {
        lock.lock()
        releases.append(release)
        lock.unlock()
    }

    /// Silent for `limit`, and not completed: `abandon` cancels the pass,
    /// then every pump is released, once. `true` when it did. The pass is
    /// cancelled first, so no pump released can go on to finish an input of
    /// a writer that is about to be cancelled under it.
    func stallIfSilent(for limit: TimeInterval, now: UInt64 = DispatchTime.now().uptimeNanoseconds,
                       abandon: () -> Void = {}) -> Bool {
        lock.lock()
        let silent = Double(now >= lastMove ? now - lastMove : 0) / 1e9
        guard !stalled, !completed, silent >= limit else {
            lock.unlock()
            return false
        }
        stalled = true
        let pending = releases
        lock.unlock()
        abandon()
        pending.forEach { $0() }
        return true
    }

    /// Every pump ended: no stall can happen from now on. `true` when one
    /// happened first (the pass is then abandoned, its writer cancelled).
    func complete() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        completed = true
        return stalled
    }
}
