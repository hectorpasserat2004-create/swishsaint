// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// Where the other packages get their engine, their Keychain and the
/// engine's installer. Stubs until WP Engine fills them: `nil` means « not
/// available yet », and every caller must already handle it (engine not
/// installed, agent not running).
enum ForkMacBackupEngineFactory {
    /// The app's client of the agent's `kopia server` (`run/server.json`):
    /// browse, versions, restore. Callbacks on the main queue.
    static func makeClient(paths: ForkMacBackupPaths) -> ForkMacBackupEngineDriving? { nil }

    /// The agent's engine: owns `kopia server` and the repository's own
    /// config. Callbacks on `callbackQueue`.
    static func makeOwner(paths: ForkMacBackupPaths, secrets: ForkMacBackupSecrets,
                          callbackQueue: DispatchQueue) -> ForkMacBackupEngineDriving? { nil }

    /// The Keychain (`<bundle id>.macbackup`, AfterFirstUnlockThisDeviceOnly).
    static func makeSecrets() -> ForkMacBackupSecrets? { nil }
}

/// The pinned Kopia binary on this Mac: download, SHA-256 check, install
/// (modelled on `ForkParakeetModelStore`). Stub until WP Engine fills it.
final class ForkMacBackupEngineStore: ObservableObject {
    static let shared = ForkMacBackupEngineStore()

    @Published private(set) var state: ForkMacBackupEngineInstallState = .notInstalled

    func install() {}

    func cancel() {}
}
