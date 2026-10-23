// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// Where everything of the feature lives: `<container>/MacBackup/`, the
/// container being `PrivateFileStore.containerURL`
/// (`~/Library/Application Support/<bundle id>`). Pure: the root is
/// injected, so tests use a temporary folder. Creating the folders (0700)
/// and writing the files (0600) goes through `PrivateFileStore`.
///
/// Never Kopia's own `~/Library/Application Support/kopia`, never Bran's.
struct ForkMacBackupPaths: Equatable {
    /// `…/MacBackup`.
    let root: URL

    init(root: URL) {
        self.root = root
    }

    /// `<container>/MacBackup`; nil without a container (outside a bundle).
    init?(container: URL?) {
        guard let container else { return nil }
        self.init(root: container.appendingPathComponent("MacBackup", isDirectory: true))
    }

    // MARK: Engine

    /// `engine/`: the pinned Kopia binaries, one folder per version.
    var engine: URL { root.appendingPathComponent("engine", isDirectory: true) }

    /// `engine/kopia-<version>/`.
    func engineFolder(version: String) -> URL {
        engine.appendingPathComponent("kopia-\(version)", isDirectory: true)
    }

    /// `engine/kopia-<version>/kopia`.
    func engineBinary(version: String) -> URL {
        engineFolder(version: version).appendingPathComponent("kopia", isDirectory: false)
    }

    // MARK: Repository

    /// One repository's own Kopia files: never the default config.
    struct RepositoryFiles: Equatable {
        let folder: URL
        var config: URL { folder.appendingPathComponent("repository.config", isDirectory: false) }
        var cache: URL { folder.appendingPathComponent("cache", isDirectory: true) }
        var logs: URL { folder.appendingPathComponent("logs", isDirectory: true) }
    }

    /// `repo/<key>/` (`ForkMacBackupRepository.key`).
    func repository(_ key: String) -> RepositoryFiles {
        RepositoryFiles(folder: root.appendingPathComponent("repo", isDirectory: true)
            .appendingPathComponent(key, isDirectory: true))
    }

    // MARK: Run

    /// `run/`: what exists only while the agent runs.
    var run: URL { root.appendingPathComponent("run", isDirectory: true) }
    /// `flock` of the single agent.
    var agentLock: URL { run.appendingPathComponent("agent.lock", isDirectory: false) }
    var kopiaSocket: URL { run.appendingPathComponent("kopia.sock", isDirectory: false) }
    /// `ForkMacBackupServerInfo`.
    var serverInfo: URL { run.appendingPathComponent("server.json", isDirectory: false) }
    /// Touched by the app every few seconds while a view shows the live
    /// progress: a fresh lease makes the agent publish at 1 Hz, else 0.1 Hz.
    var viewerLease: URL { run.appendingPathComponent("viewer.lease", isDirectory: false) }

    /// `commands/`: one file per command (`ForkMacBackupCommandFile`).
    var commands: URL { root.appendingPathComponent("commands", isDirectory: true) }

    func commandFile(_ file: ForkMacBackupCommandFile) -> URL {
        commands.appendingPathComponent(file.fileName, isDirectory: false)
    }

    // MARK: Records

    /// `ForkMacBackupStateFile`.
    var state: URL { root.appendingPathComponent("state.json", isDirectory: false) }
    /// `ForkMacBackupRunRecord` lines.
    var runs: URL { root.appendingPathComponent("runs.jsonl", isDirectory: false) }
    /// `ForkMacBackupSlotRecord` lines.
    var slots: URL { root.appendingPathComponent("slots.jsonl", isDirectory: false) }
    /// The proofs per source (owned by the Agent).
    var proofs: URL { root.appendingPathComponent("proofs.json", isDirectory: false) }
    /// `errors/<manifest id>.json`: a snapshot's complete failure list.
    var errors: URL { root.appendingPathComponent("errors", isDirectory: true) }

    func errorsFile(manifestID: String) -> URL {
        let safe = manifestID.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        return errors.appendingPathComponent("\(safe.isEmpty ? "unknown" : safe).json", isDirectory: false)
    }

    /// `ForkMacBackupCapacitySample` lines.
    var capacity: URL { root.appendingPathComponent("capacity.jsonl", isDirectory: false) }
    /// Changes not protected yet (owned by the Agent).
    var pending: URL { root.appendingPathComponent("pending.json", isDirectory: false) }
    /// The sources' last full pre-scan walk (`ForkMacBackupPrescanCache`, owned by the Agent).
    var prescan: URL { root.appendingPathComponent("prescan.json", isDirectory: false) }
    /// Single files restored for Quick Look, emptied when the window closes.
    var preview: URL { root.appendingPathComponent("preview", isDirectory: true) }

    /// Every folder the agent creates at start.
    var folders: [URL] { [root, engine, run, commands, errors, preview] }

    // MARK: Socket

    /// `sun_path` holds 104 bytes with its final zero. A long home or
    /// bundle id can overflow it: the Engine then binds a short path
    /// (`shortSocket`) and writes the real one in `server.json`.
    static let maxSocketPathBytes = 103

    var socketPathFits: Bool { kopiaSocket.path.utf8.count <= Self.maxSocketPathBytes }

    /// `/tmp/swishsaint-<uid>/kopia.sock`, the fallback (folder 0700, owned
    /// by the user; checked before use).
    static func shortSocket(uid: UInt32) -> URL {
        URL(fileURLWithPath: "/tmp/swishsaint-\(uid)", isDirectory: true)
            .appendingPathComponent("kopia.sock", isDirectory: false)
    }
}
