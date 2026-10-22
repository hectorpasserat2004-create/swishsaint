// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Darwin
import Foundation

/// Whether a Kopia child may download the iCloud files that are only in the
/// cloud (`SF_DATALESS`) when it reads them (plan §4.4). The policy is the
/// process's `IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES`, inherited by a
/// child at spawn: the parent sets it, spawns, then puts its own back.
///
/// Always explicit, never inherited by chance: an app or agent started from
/// a shell or by Foundation may already allow it (measured 22/10: a Swift
/// tool launched from Terminal reads ON), and a Kopia child of such a
/// process would then download every cloud-only file it meets in the
/// « Fichiers présents sur le Mac » mode. OFF, a read of a cloud-only file
/// fails with EDEADLK, which the conclusion files under
/// `ForkMacBackupFailureCause.cloudOnly`.
enum ForkMacBackupDatalessPolicy {
    /// Serializes every spawn with its policy: two children started at the
    /// same time on two queues each get their own.
    private static let lock = NSLock()

    /// The process's own policy now (`IOPOL_MATERIALIZE_DATALESS_FILES_*`), -1 when unreadable.
    static var current: Int32 {
        getiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_PROCESS)
    }

    static func value(materialize: Bool) -> Int32 {
        materialize ? IOPOL_MATERIALIZE_DATALESS_FILES_ON : IOPOL_MATERIALIZE_DATALESS_FILES_OFF
    }

    /// Runs `spawn` (a `Process.run()`) with the process policy set to
    /// `materialize`, then restores the previous one. The window is the
    /// spawn itself: the caller's other threads never walk into a
    /// cloud-only folder (the pre-scan skips them), so the brief change is
    /// harmless to them.
    static func spawning<Result>(materialize: Bool, _ spawn: () throws -> Result) rethrows -> Result {
        lock.lock()
        defer { lock.unlock() }
        let previous = current
        let wanted = value(materialize: materialize)
        let changed = previous >= 0 && previous != wanted
            && setiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_PROCESS, wanted) == 0
        defer {
            if changed { _ = setiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_PROCESS, previous) }
        }
        return try spawn()
    }
}
