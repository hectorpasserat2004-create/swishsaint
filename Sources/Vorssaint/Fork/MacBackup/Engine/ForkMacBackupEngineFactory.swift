// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// Where the other packages get their engine, their Keychain and the
/// engine's installer. `nil` means « not available yet », and every caller
/// handles it (engine not installed, agent not running).
///
/// Both engines also conform to `ForkMacBackupEngineExtras`
/// (`engine as? ForkMacBackupEngineExtras`): server start and stop, live
/// bytes sent, priority, server PID, conclusion of a run, failure lists,
/// maintenance schedule, versions of another Mac's file.
enum ForkMacBackupEngineFactory {
    /// The app's client of the agent's `kopia server` (`run/server.json`):
    /// progress, browse, versions, restore, and the wizard's probe
    /// (`connect` into a throw-away config). Callbacks on the main queue.
    /// Never nil: without a running agent, its calls fail with
    /// `.serverUnavailable` until the agent writes `server.json`.
    static func makeClient(paths: ForkMacBackupPaths) -> ForkMacBackupEngineDriving? {
        let engine = ForkMacBackupKopiaEngine(role: .client, paths: paths, callbackQueue: .main,
                                              binary: { installedBinary(paths) })
        engine.restoredSuffix = ForkMacBackupEngineStrings.strings(L10n.shared.language).restoredSuffix
        return engine
    }

    /// The agent's engine: owns `kopia server` and the repository's own
    /// config. Callbacks on `callbackQueue`. Nil while the engine is not
    /// installed (or not signed by Kopia). The credentials travel with each
    /// `connect` / `startServer`; `secrets` is the Keychain the agent reads
    /// them from.
    static func makeOwner(paths: ForkMacBackupPaths, secrets: ForkMacBackupSecrets,
                          callbackQueue: DispatchQueue) -> ForkMacBackupEngineDriving? {
        guard installedBinary(paths) != nil else { return nil }
        return ForkMacBackupKopiaEngine(role: .owner, paths: paths, callbackQueue: callbackQueue,
                                        binary: { installedBinary(paths) })
    }

    /// The Keychain (`<bundle id>.macbackup`, AfterFirstUnlockThisDeviceOnly).
    static func makeSecrets() -> ForkMacBackupSecrets? {
        ForkMacBackupKeychain.forCurrentBundle()
    }

    /// `engine/kopia-<version>/kopia` when present and signed by Kopia LLC.
    private static func installedBinary(_ paths: ForkMacBackupPaths) -> URL? {
        let binary = paths.engineBinary(version: ForkMacBackupEngineManifest.version)
        guard FileManager.default.isExecutableFile(atPath: binary.path),
              ForkMacBackupEngineBinary.isTrusted(binary) else { return nil }
        return binary
    }
}
