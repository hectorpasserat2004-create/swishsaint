// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// The agent's private `kopia server`: where its socket lives, what
/// `run/server.json` says, how often it is restarted after a crash.
enum ForkMacBackupServerPlan {
    /// The socket to bind: `run/kopia.sock` when its path fits in
    /// `sun_path`, else a short one under `/tmp/swishsaint-<uid>/` named after
    /// this feature's root (a Developer build and the release must not
    /// share one socket).
    static func socketPath(paths: ForkMacBackupPaths, uid: UInt32) -> URL {
        if paths.socketPathFits { return paths.kopiaSocket }
        let folder = ForkMacBackupPaths.shortSocket(uid: uid).deletingLastPathComponent()
        let name = "kopia-" + ForkMacBackupHash.fnv1a64Hex(paths.root.standardizedFileURL.path) + ".sock"
        return folder.appendingPathComponent(name, isDirectory: false)
    }

    /// Whether the fallback folder may hold our socket: ours, 0700, a real
    /// folder (not a link someone else planted in `/tmp`).
    static func isSafeSocketFolder(ownerUID: UInt32, mode: UInt16, isSymlink: Bool, uid: UInt32) -> Bool {
        !isSymlink && ownerUID == uid && mode & 0o077 == 0
    }

    /// 32 random bytes in hexadecimal (a per-start password).
    static func randomPassword<Generator: RandomNumberGenerator>(using generator: inout Generator) -> String {
        (0..<32).map { _ in String(format: "%02x", UInt8.random(in: 0...255, using: &generator)) }.joined()
    }

    static func randomPassword() -> String {
        var generator = SystemRandomNumberGenerator()
        return randomPassword(using: &generator)
    }

    /// What the app's client needs to reach the server.
    static func info(socket: URL, serverPassword: String, controlPassword: String, pid: Int32,
                     startedAt: Date) -> ForkMacBackupServerInfo {
        ForkMacBackupServerInfo(formatVersion: ForkMacBackupServerInfo.formatVersion, socketPath: socket.path,
                                serverUser: ForkMacBackupKopiaCommand.serverUser, serverPassword: serverPassword,
                                controlUser: ForkMacBackupKopiaCommand.controlUser, controlPassword: controlPassword,
                                kopiaVersion: ForkMacBackupEngineManifest.version, pid: pid, startedAt: startedAt)
    }

    static func encode(_ info: ForkMacBackupServerInfo) -> Data? {
        try? ForkMacBackupJSON.encoder.encode(info)
    }

    /// `server.json` of this format or an older one; nil otherwise.
    static func decode(_ data: Data) -> ForkMacBackupServerInfo? {
        guard let info = try? ForkMacBackupJSON.decoder.decode(ForkMacBackupServerInfo.self, from: data),
              info.formatVersion <= ForkMacBackupServerInfo.formatVersion, !info.socketPath.isEmpty else { return nil }
        return info
    }

    // MARK: Supervision

    /// Seconds before restart number `attempt` (0 = the first): 1, 2, 5,
    /// 10, 30, 60, then every 5 minutes.
    static func restartDelay(attempt: Int) -> TimeInterval {
        let steps: [TimeInterval] = [1, 2, 5, 10, 30, 60]
        return attempt < steps.count ? steps[max(0, attempt)] : 300
    }

    /// A server that ran this long was healthy: the next crash starts the
    /// delays over.
    static let healthyRun: TimeInterval = 120

    /// How long the server may take to print its address.
    static let startTimeout: TimeInterval = 30
}
