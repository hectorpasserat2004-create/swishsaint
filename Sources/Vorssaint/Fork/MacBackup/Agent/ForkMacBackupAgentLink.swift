// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// The app's side of the agent: registers it (`SMAppService.agent`, or a
/// plain LaunchAgent in a Developer build), unregisters it when the feature
/// is switched off, and publishes whether it may run. Stub until WP Agent
/// fills it; nothing is registered yet.
final class ForkMacBackupAgentLink: ObservableObject {
    static let shared = ForkMacBackupAgentLink()

    @Published private(set) var registration: ForkMacBackupAgentRegistration = .notRegistered

    /// At launch.
    static func start() {
        shared.sync()
    }

    /// The feature's switch moved.
    static func sync() {
        shared.sync()
    }

    func sync() {}

    /// System Settings › General › Login Items, where the agent is allowed.
    func openApprovalSettings() {}
}
