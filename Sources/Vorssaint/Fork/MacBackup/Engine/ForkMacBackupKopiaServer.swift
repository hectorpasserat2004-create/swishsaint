// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Darwin
import Foundation
import os

/// The agent's private `kopia server` (SPIKES §6): one per repository, a
/// child of the agent, on a unix socket only the user can write to, with
/// random passwords per start passed in its environment. Ready when it
/// prints `SERVER ADDRESS:`; then `run/server.json` (0600) tells the app's
/// client how to reach it.
///
/// Supervised: an unexpected exit removes `server.json` and restarts it
/// after 1, 2, 5, 10, 30, 60 s, then every 5 min (a run longer than 2 min
/// starts the delays over). `stop()` closes its stdin (`--shutdown-on-stdin`,
/// < 0.1 s), then SIGTERM, then SIGKILL.
///
/// Everything runs on the engine's serial `queue`.
final class ForkMacBackupKopiaServer {
    private static let log = Logger(subsystem: "fork.macbackup", category: "server")

    let binary: URL
    let paths: ForkMacBackupPaths
    let files: ForkMacBackupPaths.RepositoryFiles
    let queue: DispatchQueue
    var priority: ForkMacBackupKopiaInvocation.Priority = .utility
    /// Called on `queue` after every start and every exit.
    var onChange: (() -> Void)?

    private(set) var info: ForkMacBackupServerInfo?
    private var process: ForkMacBackupKopiaProcess?
    private var credentials: ForkMacBackupCredentials?
    private var stopping = false
    private var attempt = 0
    private var startedAt: Date?
    private var restart: DispatchWorkItem?
    private var generation = 0
    /// Reached « ready » since the last `start`: only then is a crash
    /// restarted (a server that cannot start reports to its caller instead).
    private var everReady = false

    init(binary: URL, paths: ForkMacBackupPaths, files: ForkMacBackupPaths.RepositoryFiles, queue: DispatchQueue) {
        self.binary = binary
        self.paths = paths
        self.files = files
        self.queue = queue
    }

    /// Released (its engine dropped without `shutdown`): the child still
    /// stops, through its stdin, so no `kopia server` outlives its owner.
    deinit {
        restart?.cancel()
        process?.closeStdin()
    }

    var isRunning: Bool { info != nil }
    var processIdentifier: Int32? { info?.pid }

    /// Starts (or restarts) the server with `credentials`; `completion` on
    /// `queue`, once.
    func start(credentials: ForkMacBackupCredentials,
               completion: @escaping (Result<ForkMacBackupServerInfo, ForkMacBackupEngineError>) -> Void) {
        dispatchPrecondition(condition: .onQueue(queue))
        self.credentials = credentials
        stopping = false
        everReady = false
        restart?.cancel()
        restart = nil
        attempt = 0
        terminateCurrent { [weak self] in
            self?.launch(completion: completion)
        }
    }

    /// Stops it for good (until the next `start`).
    func stop(completion: @escaping () -> Void) {
        dispatchPrecondition(condition: .onQueue(queue))
        stopping = true
        credentials = nil
        restart?.cancel()
        restart = nil
        terminateCurrent(completion)
    }

    // MARK: Launch

    private func launch(completion: @escaping (Result<ForkMacBackupServerInfo, ForkMacBackupEngineError>) -> Void) {
        guard let credentials else { return completion(.failure(.notConnected)) }
        guard ForkMacBackupEngineBinary.isTrusted(binary) else { return completion(.failure(.engineMissing)) }
        let uid = getuid()
        let socket = ForkMacBackupServerPlan.socketPath(paths: paths, uid: uid)
        guard prepareSocketFolder(socket.deletingLastPathComponent(), uid: uid) else {
            return completion(.failure(.other("socket folder")))
        }
        unlink(socket.path)
        PrivateFileStore.createDirectory(at: ForkMacBackupKopiaCommand.home(files))
        PrivateFileStore.createDirectory(at: files.logs)

        let serverPassword = ForkMacBackupServerPlan.randomPassword()
        let controlPassword = ForkMacBackupServerPlan.randomPassword()
        let extra = ForkMacBackupKopiaCommand.serverEnvironment(serverPassword: serverPassword,
                                                               controlPassword: controlPassword)
        let invocation = ForkMacBackupKopiaInvocation(
            arguments: ForkMacBackupKopiaCommand.global(files) + ForkMacBackupKopiaCommand.serverStart(socketPath: socket.path),
            environment: ForkMacBackupKopiaCommand.environment(credentials: credentials, files: files, extra: extra),
            timeout: .infinity, silenceTimeout: nil, priority: priority)

        generation += 1
        let current = generation
        var pending: ((Result<ForkMacBackupServerInfo, ForkMacBackupEngineError>) -> Void)? = completion
        var ready = false
        let startTimeout = DispatchWorkItem { [weak self] in
            guard let self, self.generation == current, !ready else { return }
            Self.log.error("server did not print its address in time")
            self.process?.cancel()
            pending?(.failure(.timeout))
            pending = nil
        }
        let child = ForkMacBackupKopiaProcess(binary: binary, invocation: invocation, queue: queue, stdinPipe: true,
                                              onStderrLine: { [weak self] line in
            guard let self, self.generation == current, !ready else { return }
            guard case .address = ForkMacBackupKopiaText.serverLine(line) else { return }
            ready = true
            startTimeout.cancel()
            let pid = self.process?.processIdentifier ?? 0
            let info = ForkMacBackupServerPlan.info(socket: socket, serverPassword: serverPassword,
                                                    controlPassword: controlPassword, pid: pid, startedAt: Date())
            guard let data = ForkMacBackupServerPlan.encode(info),
                  PrivateFileStore.createDirectory(at: self.paths.run),
                  PrivateFileStore.write(data, to: self.paths.serverInfo) else {
                self.process?.cancel()
                pending?(.failure(.other("server.json")))
                pending = nil
                return
            }
            self.info = info
            self.startedAt = Date()
            self.everReady = true
            Self.log.info("server ready, pid \(pid, privacy: .public)")
            pending?(.success(info))
            pending = nil
            self.onChange?()
        })
        process = child
        queue.asyncAfter(deadline: .now() + ForkMacBackupServerPlan.startTimeout, execute: startTimeout)
        child.start { [weak self] outcome in
            startTimeout.cancel()
            guard let self, self.generation == current else {
                // Superseded by a newer start or a stop.
                pending?(.failure(.canceled))
                pending = nil
                return
            }
            if let completion = pending {
                pending = nil
                completion(.failure(outcome.launchFailed ? .engineMissing
                    : ForkMacBackupKopiaText.classify(stderr: outcome.stderr, exitCode: outcome.status)))
            }
            self.exited(outcome, wasReady: ready)
        }
    }

    private func exited(_ outcome: ForkMacBackupKopiaProcess.Outcome, wasReady: Bool) {
        process = nil
        info = nil
        try? FileManager.default.removeItem(at: paths.serverInfo)
        onChange?()
        guard !stopping, credentials != nil, everReady else { return }
        let ranFor = startedAt.map { Date().timeIntervalSince($0) } ?? 0
        if wasReady, ranFor >= ForkMacBackupServerPlan.healthyRun { attempt = 0 }
        let delay = ForkMacBackupServerPlan.restartDelay(attempt: attempt)
        attempt += 1
        let line = ForkMacBackupKopiaText.errorLine(outcome.stderr)
        Self.log.error("server exited (\(outcome.status, privacy: .public)): \(line, privacy: .public); restart in \(delay, privacy: .public) s")
        let item = DispatchWorkItem { [weak self] in
            guard let self, !self.stopping, self.process == nil else { return }
            self.launch { _ in }
        }
        restart = item
        queue.asyncAfter(deadline: .now() + delay, execute: item)
    }

    /// Ends the running child, if any, then calls `then` on `queue`.
    private func terminateCurrent(_ then: @escaping () -> Void) {
        generation += 1
        guard let child = process else {
            info = nil
            try? FileManager.default.removeItem(at: paths.serverInfo)
            return then()
        }
        process = nil
        info = nil
        try? FileManager.default.removeItem(at: paths.serverInfo)
        let pid = child.processIdentifier
        child.closeStdin()
        // `--shutdown-on-stdin` exits in well under a second; then SIGTERM.
        queue.asyncAfter(deadline: .now() + 2) {
            if let pid, kill(pid, 0) == 0 { child.cancel() }
        }
        waitForExit(pid: pid, deadline: Date().addingTimeInterval(6), then: { [weak self] in
            self?.onChange?()
            then()
        })
    }

    private func waitForExit(pid: Int32?, deadline: Date, then: @escaping () -> Void) {
        guard let pid, kill(pid, 0) == 0, Date() < deadline else { return then() }
        queue.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.waitForExit(pid: pid, deadline: deadline, then: then)
        }
    }

    // MARK: Socket folder

    /// `run/` (in the container) or the short `/tmp/swishsaint-<uid>/`:
    /// created 0700, and refused unless it is a real folder of ours that
    /// nobody else can enter.
    private func prepareSocketFolder(_ folder: URL, uid: UInt32) -> Bool {
        if folder.path.hasPrefix(paths.root.path) {
            return PrivateFileStore.createDirectory(at: folder)
        }
        mkdir(folder.path, 0o700)
        var info = stat()
        guard lstat(folder.path, &info) == 0 else { return false }
        let isSymlink = (info.st_mode & S_IFMT) == S_IFLNK
        let isDirectory = (info.st_mode & S_IFMT) == S_IFDIR
        guard isDirectory, ForkMacBackupServerPlan.isSafeSocketFolder(ownerUID: info.st_uid, mode: UInt16(info.st_mode & 0o7777),
                                                                     isSymlink: isSymlink, uid: uid) else {
            Self.log.error("refusing the socket folder: not a private folder of this user")
            return false
        }
        return true
    }
}
