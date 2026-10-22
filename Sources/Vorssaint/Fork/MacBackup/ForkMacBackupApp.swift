// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// Mac Backup in the app (not the agent): started once at launch by
/// `ForkBootstrap.start()`, then synced by every switch of the feature
/// (`ForkFeature.macBackup.sync()`). Each work package fills its own entry
/// point; off, every one of them stops what it started.
enum ForkMacBackupApp {
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: ForkDefaultsKey.macBackupEnabled) }

    /// At launch. The island's hooks are set whatever the switch says (they
    /// answer « unavailable » while it is off), like the Meetings section.
    static func start() {
        ForkMacBackupIsland.start()
        ForkMacBackupStatusModel.shared.sync()
        ForkMacBackupAgentLink.start()
    }

    /// The switch moved (its page, the Extras page, a settings import).
    static func sync() {
        ForkMacBackupStatusModel.shared.sync()
        ForkMacBackupAgentLink.sync()
        ForkMacBackupIsland.sync()
        // Off: an engine download stops too. The window closes itself on
        // the `.off` state the status model publishes.
        if !isEnabled, ForkMacBackupEngineStore.shared.isBusy { ForkMacBackupEngineStore.shared.cancel() }
    }
}
