// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// The first backup's choice, in the connection wizard's last step (decision
/// 3 of 22/10: nothing proactive outside the feature's own surfaces, so what
/// the island's « first heavy backup » card used to offer lives here, where
/// the person is already).
enum ForkMacBackupFirstBackup {
    /// What the person chose.
    enum Choice: Equatable {
        case started
        case waitingForPower
    }

    /// Now when plugged in or when there is no battery, else at the plug.
    static func startsAtOnce(externalConnected: Bool, hasBattery: Bool) -> Bool {
        externalConnected || !hasBattery
    }

    /// The real size to send: the content preview's (allocated bytes), else
    /// what the agent already measured; nil while neither is known.
    static func sizeToSend(preview: ForkMacBackupContentPreview?, protectedBytes: Int64?) -> Int64? {
        preview?.includedBytes ?? protectedBytes
    }
}
