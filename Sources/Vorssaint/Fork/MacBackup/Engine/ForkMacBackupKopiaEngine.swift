// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Darwin
import Foundation
import os

/// Kopia, driven (`ForkMacBackupEngineDriving` + `ForkMacBackupEngineExtras`).
/// Two roles from one class:
///
/// - **owner** (the agent): writes the repository's own config
///   (`repository connect`, secrets in the environment, unique ID checked),
///   owns the private `kopia server`, writes policies, triggers snapshots,
///   runs the CLI for listing, verification, blob stats and maintenance;
/// - **client** (the app): reaches the agent's server through
///   `run/server.json` for progress, browsing, versions and restores. It
///   never writes a policy nor starts a snapshot (`.other("agent only")`);
///   its `connect` is a probe in a throw-away config (the wizard's « C'est
///   bien mon dépôt ? »), which leaves the agent's config alone.
///
/// Threading: state on one serial queue (`work`); every completion and
/// progress callback on `callbackQueue`; exactly one completion per call,
/// `.canceled` after a cancel.
final class ForkMacBackupKopiaEngine: ForkMacBackupEngineExtras {
    enum Role: Equatable {
        case owner
        case client
    }

    static let log = Logger(subsystem: "fork.macbackup", category: "engine")

    let role: Role
    let paths: ForkMacBackupPaths
    let callbackQueue: DispatchQueue
    /// The word after a kept-both copy's name (« restored »); the factory
    /// sets the person's language.
    var restoredSuffix = ForkMacBackupEngineStrings.enUS.restoredSuffix

    let work = DispatchQueue(label: "fork.macbackup.engine", qos: .utility)
    private let binaryProvider: () -> URL?
    private let lock = NSLock()
    private var priorityValue: ForkMacBackupKopiaInvocation.Priority = .utility
    private var ownerServerPID: Int32?

    // Owned by `work`.
    private(set) var repository: ForkMacBackupRepository?
    private var credentials: ForkMacBackupCredentials?
    var identity: ForkMacBackupRepository.Identity?
    private var server: ForkMacBackupKopiaServer?
    private var api: ForkMacBackupKopiaAPI?

    /// `binary`: the installed engine, read at each use (an install while
    /// running is picked up).
    init(role: Role, paths: ForkMacBackupPaths, callbackQueue: DispatchQueue, binary: @escaping () -> URL?) {
        self.role = role
        self.paths = paths
        self.callbackQueue = callbackQueue
        self.binaryProvider = binary
    }

    /// Also applied at once to the running server (macOS background state
    /// on or off, `setpriority(PRIO_DARWIN_PROCESS)`), so a « Sauvegarder
    /// maintenant » runs at normal speed and a scheduled run stays quiet.
    var priority: ForkMacBackupKopiaInvocation.Priority {
        get { lock.withLock { priorityValue } }
        set {
            let pid: Int32? = lock.withLock {
                priorityValue = newValue
                return role == .owner ? ownerServerPID : nil
            }
            if let pid, pid > 0 {
                _ = setpriority(PRIO_DARWIN_PROCESS, id_t(pid), newValue == .background ? PRIO_DARWIN_BG : 0)
            }
            work.async { [weak self] in self?.server?.priority = newValue }
        }
    }

    /// Safe from any queue (a cached value, refreshed at every server
    /// start and exit).
    var serverProcessID: Int32? {
        if role == .owner { return lock.withLock { ownerServerPID } }
        return loadServerInfo()?.pid
    }

    // MARK: - Plumbing

    /// One completion, on `callbackQueue`.
    func task<Value>(_ completion: @escaping (ForkMacBackupEngineResult<Value>) -> Void) -> ForkMacBackupEngineTask<Value> {
        ForkMacBackupEngineTask(queue: callbackQueue, completion: completion)
    }

    func ownerOnly<Value>(_ task: ForkMacBackupEngineTask<Value>) -> Bool {
        guard role == .owner else {
            task.finish(.failure(.other("agent only")))
            return false
        }
        return true
    }

    func loadServerInfo() -> ForkMacBackupServerInfo? {
        guard let data = try? Data(contentsOf: paths.serverInfo) else { return nil }
        return ForkMacBackupServerPlan.decode(data)
    }

    /// The API of the running server (owner: started on demand; client:
    /// from `server.json`). On `work`.
    func withAPI(_ failure: @escaping (ForkMacBackupEngineError) -> Void,
                 _ body: @escaping (ForkMacBackupKopiaAPI) -> Void) {
        dispatchPrecondition(condition: .onQueue(work))
        switch role {
        case .client:
            guard let info = loadServerInfo() else { return failure(.serverUnavailable) }
            body(api(for: info))
        case .owner:
            if let info = server?.info { return body(api(for: info)) }
            guard let repository, let credentials else { return failure(.notConnected) }
            launchServer(repository: repository, credentials: credentials) { [weak self] result in
                guard let self else { return }
                switch result {
                case .success(let info): body(self.api(for: info))
                case .failure(let error): failure(error)
                }
            }
        }
    }

    private func api(for info: ForkMacBackupServerInfo) -> ForkMacBackupKopiaAPI {
        if let api, api.info == info { return api }
        let fresh = ForkMacBackupKopiaAPI(info: info, queue: work)
        api = fresh
        return fresh
    }

    /// A server this young may still be opening the repository
    /// (`--async-repo-connect`): « not connected » is waited out.
    static let connectGrace: TimeInterval = 20

    /// One API call; a client whose server restarted (new passwords, new
    /// socket) re-reads `server.json` once; a server just started gets
    /// `connectGrace` to open the repository.
    func request(_ method: String, _ path: String, query: [(String, String)] = [], json: Any? = nil,
                 auth: ForkMacBackupKopiaAPI.Auth, timeout: TimeInterval = ForkMacBackupKopiaAPI.jsonTimeout,
                 retry: Bool = true, completion: @escaping (Result<Data, ForkMacBackupKopiaAPI.Failure>) -> Void) {
        withAPI({ completion(.failure(.engine($0))) }) { [weak self] api in
            api.call(method, path, query: query, json: json, auth: auth, timeout: timeout) { result in
                guard let self else { return }
                if case .failure(.engine(.serverUnavailable)) = result, retry, self.role == .client {
                    self.api = nil
                    return self.request(method, path, query: query, json: json, auth: auth, timeout: timeout,
                                        retry: false, completion: completion)
                }
                if case .failure(.engine(.notConnected)) = result,
                   Date().timeIntervalSince(api.info.startedAt) < Self.connectGrace {
                    return self.work.asyncAfter(deadline: .now() + 0.5) {
                        self.request(method, path, query: query, json: json, auth: auth, timeout: timeout,
                                     retry: retry, completion: completion)
                    }
                }
                completion(result)
            }
        }
    }

    func requestDecoding<Value: Decodable>(_ type: Value.Type, _ method: String, _ path: String,
                                           query: [(String, String)] = [], json: Any? = nil,
                                           auth: ForkMacBackupKopiaAPI.Auth,
                                           timeout: TimeInterval = ForkMacBackupKopiaAPI.jsonTimeout,
                                           completion: @escaping (ForkMacBackupEngineResult<Value>) -> Void) {
        request(method, path, query: query, json: json, auth: auth, timeout: timeout) { result in
            switch result {
            case .failure(let failure): completion(.failure(failure.engineError))
            case .success(let data):
                guard let value = ForkMacBackupKopia.decode(type, from: data) else {
                    return completion(.failure(.decoding(String(describing: type))))
                }
                completion(.success(value))
            }
        }
    }

    /// The repository's own Kopia files.
    var files: ForkMacBackupPaths.RepositoryFiles? {
        repository.map { paths.repository($0.key) }
    }

    /// One CLI call on the connected repository (owner); `completion` on
    /// `work`.
    @discardableResult
    func runCLI(_ arguments: [String], timeout: TimeInterval, silenceTimeout: TimeInterval? = nil,
                files override: ForkMacBackupPaths.RepositoryFiles? = nil,
                credentials explicit: ForkMacBackupCredentials? = nil,
                onStderrLine: ((String) -> Void)? = nil,
                completion: @escaping (Result<ForkMacBackupKopiaProcess.Outcome, ForkMacBackupEngineError>) -> Void)
        -> ForkMacBackupKopiaProcess? {
        dispatchPrecondition(condition: .onQueue(work))
        guard let binary = binaryProvider() else {
            completion(.failure(.engineMissing))
            return nil
        }
        guard ForkMacBackupEngineBinary.isTrusted(binary) else {
            completion(.failure(.engineMissing))
            return nil
        }
        guard let files = override ?? files, let secrets = explicit ?? credentials else {
            completion(.failure(.notConnected))
            return nil
        }
        let invocation = ForkMacBackupKopiaCommand.invocation(arguments, files: files, credentials: secrets,
                                                              timeout: timeout, silenceTimeout: silenceTimeout,
                                                              priority: priority)
        let process = ForkMacBackupKopiaProcess(binary: binary, invocation: invocation,
                                                queue: DispatchQueue(label: "fork.macbackup.kopia", qos: .utility),
                                                onStderrLine: onStderrLine)
        process.start { [weak self] outcome in
            self?.work.async {
                if outcome.launchFailed { return completion(.failure(.engineMissing)) }
                completion(.success(outcome))
            }
        }
        return process
    }

    /// A finished CLI call's error, when it failed.
    static func failure(of outcome: ForkMacBackupKopiaProcess.Outcome) -> ForkMacBackupEngineError? {
        if outcome.canceled { return .canceled }
        if outcome.timedOut { return .timeout }
        guard outcome.status != 0 else { return nil }
        return ForkMacBackupKopiaText.classify(stderr: outcome.stderr, exitCode: outcome.status)
    }

    private func launchServer(repository: ForkMacBackupRepository, credentials: ForkMacBackupCredentials,
                              completion: @escaping (Result<ForkMacBackupServerInfo, ForkMacBackupEngineError>) -> Void) {
        guard let binary = binaryProvider() else { return completion(.failure(.engineMissing)) }
        let files = paths.repository(repository.key)
        if server == nil || server?.files != files || server?.binary != binary {
            server?.stop {}
            let fresh = ForkMacBackupKopiaServer(binary: binary, paths: paths, files: files, queue: work)
            fresh.onChange = { [weak self, weak fresh] in
                let pid = fresh?.processIdentifier
                self?.lock.withLock { self?.ownerServerPID = pid }
            }
            server = fresh
        }
        server?.priority = priority
        server?.start(credentials: credentials, completion: completion)
    }

    private func ensureFolders(_ files: ForkMacBackupPaths.RepositoryFiles) -> Bool {
        PrivateFileStore.createDirectory(at: files.folder) && PrivateFileStore.createDirectory(at: files.cache)
            && PrivateFileStore.createDirectory(at: files.logs)
            && PrivateFileStore.createDirectory(at: ForkMacBackupKopiaCommand.home(files))
    }

    /// The `userName`/`host`/`path` query naming a source on the server.
    func sourceQuery(_ path: String) -> [(String, String)] {
        let identity = self.identity ?? repository?.clientIdentity
        return [("userName", identity?.userName ?? ""), ("host", identity?.hostName ?? ""),
                ("path", ForkMacBackupSourcePath.normalized(path))]
    }

    // MARK: - Connect

    func connect(_ repository: ForkMacBackupRepository, credentials: ForkMacBackupCredentials, readOnly: Bool,
                 completion: @escaping (ForkMacBackupEngineResult<ForkMacBackupKopia.RepositoryStatus>) -> Void) {
        let task = task(completion)
        work.async { [self] in
            switch role {
            case .owner:
                let files = paths.repository(repository.key)
                guard ensureFolders(files) else { return task.finish(.failure(.other("folders"))) }
                let stop: (@escaping () -> Void) -> Void = { then in
                    if let server = self.server { server.stop(completion: then) } else { then() }
                }
                stop {
                    self.api = nil
                    self.connectInto(files, repository: repository, credentials: credentials, readOnly: readOnly,
                                     task: task) { status in
                        self.repository = repository
                        self.credentials = credentials
                        self.identity = status.identity ?? repository.clientIdentity
                        self.launchServer(repository: repository, credentials: credentials) { result in
                            if case .failure(let error) = result {
                                Self.log.error("server did not start after connect: \(String(describing: error), privacy: .public)")
                            }
                            task.finish(.success(status))
                        }
                    }
                }
            case .client:
                // A probe: a throw-away config, removed whatever happens.
                let folder = paths.root.appendingPathComponent("probe", isDirectory: true)
                    .appendingPathComponent(UUID().uuidString, isDirectory: true)
                let files = ForkMacBackupPaths.RepositoryFiles(folder: folder)
                guard ensureFolders(files) else { return task.finish(.failure(.other("folders"))) }
                let cleanup: () -> Void = { try? FileManager.default.removeItem(at: folder) }
                connectInto(files, repository: repository, credentials: credentials, readOnly: readOnly, task: task,
                            cleanup: cleanup) { status in
                    cleanup()
                    task.finish(.success(status))
                }
            }
        }
    }

    /// `repository connect` (or `create` for an empty storage when the
    /// person has not locked a unique ID yet), then `repository status`,
    /// then the unique ID check; a mismatch removes the config AND the cache
    /// (a cache shared between repositories corrupts both, SPIKES §0.2).
    private func connectInto(_ files: ForkMacBackupPaths.RepositoryFiles, repository: ForkMacBackupRepository,
                             credentials: ForkMacBackupCredentials, readOnly: Bool,
                             task: ForkMacBackupEngineTask<ForkMacBackupKopia.RepositoryStatus>,
                             cleanup: @escaping () -> Void = {},
                             success: @escaping (ForkMacBackupKopia.RepositoryStatus) -> Void) {
        let forget = {
            try? FileManager.default.removeItem(at: files.config)
            try? FileManager.default.removeItem(at: files.cache)
            cleanup()
        }
        let status = {
            _ = self.runCLI(ForkMacBackupKopiaCommand.status, timeout: 120, files: files, credentials: credentials) { result in
                switch result {
                case .failure(let error):
                    forget()
                    task.finish(.failure(error))
                case .success(let outcome):
                    if let error = Self.failure(of: outcome) {
                        forget()
                        return task.finish(.failure(error))
                    }
                    guard let status = ForkMacBackupKopia.decode(ForkMacBackupKopia.RepositoryStatus.self, from: outcome.stdout),
                          let unique = status.uniqueIDHex, !unique.isEmpty else {
                        forget()
                        return task.finish(.failure(.decoding("repository status")))
                    }
                    guard repository.accepts(uniqueID: unique) else {
                        Self.log.error("wrong repository: \(ForkMacBackupRepository.shortID(unique), privacy: .public)")
                        forget()
                        return task.finish(.failure(.wrongRepository(found: unique)))
                    }
                    success(status)
                }
            }
        }
        let connect = ForkMacBackupKopiaCommand.connect(repository, files: files, readOnly: readOnly, create: false)
        let processHandle = runCLI(connect, timeout: 180, files: files, credentials: credentials) { result in
            switch result {
            case .failure(let error):
                cleanup()
                task.finish(.failure(error))
            case .success(let outcome) where outcome.succeeded:
                status()
            case .success(let outcome):
                let mayCreate = !readOnly && (repository.expectedUniqueID ?? "").isEmpty
                guard mayCreate, ForkMacBackupKopiaText.isNotInitialized(outcome.stderr) else {
                    cleanup()
                    return task.finish(.failure(Self.failure(of: outcome) ?? .other("connect")))
                }
                Self.log.info("empty storage: creating the repository")
                let create = ForkMacBackupKopiaCommand.connect(repository, files: files, readOnly: false, create: true)
                let creating = self.runCLI(create, timeout: 300, files: files, credentials: credentials) { result in
                    switch result {
                    case .failure(let error):
                        cleanup()
                        task.finish(.failure(error))
                    case .success(let outcome):
                        if let error = Self.failure(of: outcome) {
                            cleanup()
                            return task.finish(.failure(error))
                        }
                        status()
                    }
                }
                task.attach(creating)
            }
        }
        task.attach(processHandle)
    }

    func startServer(_ repository: ForkMacBackupRepository, credentials: ForkMacBackupCredentials,
                     completion: @escaping (ForkMacBackupEngineResult<Void>) -> Void) {
        let task = task(completion)
        guard ownerOnly(task) else { return }
        work.async { [self] in
            let files = paths.repository(repository.key)
            guard FileManager.default.fileExists(atPath: files.config.path) else {
                return task.finish(.failure(.notConnected))
            }
            self.repository = repository
            self.credentials = credentials
            if identity == nil { identity = repository.clientIdentity }
            launchServer(repository: repository, credentials: credentials) { result in
                task.finish(result.map { _ in () })
            }
        }
    }

    func shutdown(completion: @escaping () -> Void) {
        work.async { [self] in
            let done = {
                self.api = nil
                self.credentials = nil
                self.callbackQueue.async(execute: completion)
            }
            guard let server else { return done() }
            server.stop(completion: done)
        }
    }

    // MARK: - Status

    func repositoryStatus(completion: @escaping (ForkMacBackupEngineResult<ForkMacBackupKopia.RepositoryStatus>) -> Void) {
        let task = task(completion)
        work.async { [self] in
            switch role {
            case .owner:
                let handle = runCLI(ForkMacBackupKopiaCommand.status, timeout: 120) { result in
                    switch result {
                    case .failure(let error): task.finish(.failure(error))
                    case .success(let outcome):
                        if let error = Self.failure(of: outcome) { return task.finish(.failure(error)) }
                        guard let status = ForkMacBackupKopia.decode(ForkMacBackupKopia.RepositoryStatus.self,
                                                                     from: outcome.stdout) else {
                            return task.finish(.failure(.decoding("repository status")))
                        }
                        task.finish(.success(status))
                    }
                }
                task.attach(handle)
            case .client:
                // The server's own status, in the CLI's shape (no unique ID).
                request("GET", "/api/v1/control/status", auth: .control) { result in
                    switch result {
                    case .failure(let failure): task.finish(.failure(failure.engineError))
                    case .success(let data):
                        guard let object = ForkMacBackupPolicyDocument.object(data) else {
                            return task.finish(.failure(.decoding("control status")))
                        }
                        if object["connected"] as? Bool == false { return task.finish(.failure(.notConnected)) }
                        let shaped: [String: Any] = [
                            "configFile": object["configFile"] ?? "",
                            "clientOptions": ["hostname": object["hostname"] ?? "", "username": object["username"] ?? "",
                                              "description": object["description"] ?? "",
                                              "readonly": object["readonly"] ?? false],
                            "storage": ["type": object["storage"] ?? ""],
                        ]
                        guard let data = try? JSONSerialization.data(withJSONObject: shaped),
                              let status = ForkMacBackupKopia.decode(ForkMacBackupKopia.RepositoryStatus.self, from: data) else {
                            return task.finish(.failure(.decoding("control status")))
                        }
                        task.finish(.success(status))
                    }
                }
            }
        }
    }

    // MARK: - Policies

    func applyPolicy(_ rules: ForkMacBackupPolicyRules, to source: ForkMacBackupSource,
                     completion: @escaping (ForkMacBackupEngineResult<ForkMacBackupPolicyRules>) -> Void) {
        let task = task(completion)
        guard ownerOnly(task) else { return }
        work.async { [self] in
            let query = sourceQuery(source.path)
            request("GET", "/api/v1/policy", query: query, auth: .ui) { result in
                var existing: [String: Any]?
                switch result {
                case .success(let data): existing = ForkMacBackupPolicyDocument.object(data)
                case .failure(let failure) where failure.isNotFound: existing = nil
                case .failure(.engine(.serverUnavailable)), .failure(.engine(.timeout)):
                    // The server cannot be reached: the same single write through the CLI.
                    return self.applyPolicyWithCLI(rules, source: source, task: task)
                case .failure(let failure): return task.finish(.failure(failure.engineError))
                }
                let merged = ForkMacBackupPolicyDocument.merged(existing, rules: rules)
                self.request("PUT", "/api/v1/policy", query: query, json: merged, auth: .ui) { result in
                    if case .failure(let failure) = result { return task.finish(.failure(failure.engineError)) }
                    self.readPolicyFromServer(query: query) { readBack in
                        // A new source appears in `control/sources` at once (default refresh: 4 h).
                        self.request("POST", "/api/v1/control/refresh", auth: .control) { _ in
                            task.finish(readBack)
                        }
                    }
                }
            }
        }
    }

    func readPolicy(of source: ForkMacBackupSource,
                    completion: @escaping (ForkMacBackupEngineResult<ForkMacBackupPolicyRules>) -> Void) {
        let task = task(completion)
        work.async { [self] in
            readPolicyFromServer(query: sourceQuery(source.path)) { result in
                switch result {
                case .failure(.serverUnavailable), .failure(.timeout):
                    if self.role == .owner, self.files != nil { return self.readPolicyWithCLI(source: source, task: task) }
                default:
                    break
                }
                task.finish(result)
            }
        }
    }

    private func readPolicyFromServer(query: [(String, String)],
                                      completion: @escaping (ForkMacBackupEngineResult<ForkMacBackupPolicyRules>) -> Void) {
        request("GET", "/api/v1/policy", query: query, auth: .ui) { result in
            switch result {
            case .failure(let failure): completion(.failure(failure.engineError))
            case .success(let data):
                guard let policy = ForkMacBackupPolicyDocument.object(data),
                      let rules = ForkMacBackupPolicyDocument.rules(from: policy) else {
                    return completion(.failure(.decoding("policy")))
                }
                completion(.success(rules))
            }
        }
    }

    /// The fallback without the server: `policy export`, merged, `policy
    /// import` (one call), `policy export` again.
    private func applyPolicyWithCLI(_ rules: ForkMacBackupPolicyRules, source: ForkMacBackupSource,
                                    task: ForkMacBackupEngineTask<ForkMacBackupPolicyRules>) {
        let path = ForkMacBackupSourcePath.normalized(source.path)
        guard let files, let identity = identity ?? repository?.clientIdentity else {
            return task.finish(.failure(.notConnected))
        }
        let export = runCLI(ForkMacBackupKopiaCommand.policyExport(path: path), timeout: 120) { result in
            let existing: [String: Any]?
            if case .success(let outcome) = result, outcome.succeeded {
                existing = ForkMacBackupPolicyDocument.exported(outcome.stdout)
            } else {
                existing = nil
            }
            let merged = ForkMacBackupPolicyDocument.merged(existing, rules: rules)
            let file = files.folder.appendingPathComponent("policy-\(UUID().uuidString).json")
            guard let data = ForkMacBackupPolicyDocument.importData(merged, identity: identity, path: path),
                  PrivateFileStore.write(data, to: file) else {
                return task.finish(.failure(.other("policy file")))
            }
            let importing = self.runCLI(ForkMacBackupKopiaCommand.policyImport(file: file), timeout: 120) { result in
                try? FileManager.default.removeItem(at: file)
                switch result {
                case .failure(let error): task.finish(.failure(error))
                case .success(let outcome):
                    if let error = Self.failure(of: outcome) { return task.finish(.failure(error)) }
                    self.readPolicyWithCLI(source: source, task: task)
                }
            }
            task.attach(importing)
        }
        task.attach(export)
    }

    private func readPolicyWithCLI(source: ForkMacBackupSource, task: ForkMacBackupEngineTask<ForkMacBackupPolicyRules>) {
        let path = ForkMacBackupSourcePath.normalized(source.path)
        let handle = runCLI(ForkMacBackupKopiaCommand.policyExport(path: path), timeout: 120) { result in
            switch result {
            case .failure(let error): task.finish(.failure(error))
            case .success(let outcome):
                if let error = Self.failure(of: outcome) { return task.finish(.failure(error)) }
                guard let policy = ForkMacBackupPolicyDocument.exported(outcome.stdout),
                      let rules = ForkMacBackupPolicyDocument.rules(from: policy) else {
                    return task.finish(.failure(.decoding("policy")))
                }
                task.finish(.success(rules))
            }
        }
        task.attach(handle)
    }

    // MARK: - Snapshots

    func startSnapshot(_ source: ForkMacBackupSource, completion: @escaping (ForkMacBackupEngineResult<Void>) -> Void) {
        let task = task(completion)
        guard ownerOnly(task) else { return }
        work.async { [self] in
            controlSource("trigger-snapshot", source: source, refreshFirst: false, task: task)
        }
    }

    func cancelSnapshot(_ source: ForkMacBackupSource, completion: @escaping (ForkMacBackupEngineResult<Void>) -> Void) {
        let task = task(completion)
        guard ownerOnly(task) else { return }
        work.async { [self] in
            controlSource("cancel-snapshot", source: source, refreshFirst: false, task: task)
        }
    }

    /// `POST control/<action>?userName=&host=&path=`; answers
    /// `{"sources":{"user@host:/path":{"success":true}}}`. A source the
    /// server does not know yet gets one `control/refresh` and a retry.
    private func controlSource(_ action: String, source: ForkMacBackupSource, refreshFirst: Bool,
                               task: ForkMacBackupEngineTask<Void>) {
        let run = {
            self.request("POST", "/api/v1/control/" + action, query: self.sourceQuery(source.path), auth: .control) { result in
                switch result {
                case .failure(let failure) where failure.isNotFound && !refreshFirst:
                    // « no source matching the provided filters »: not known yet.
                    self.controlSource(action, source: source, refreshFirst: true, task: task)
                case .failure(let failure): task.finish(.failure(failure.engineError))
                case .success(let data):
                    let answers = (ForkMacBackupPolicyDocument.object(data)?["sources"] as? [String: Any]) ?? [:]
                    let succeeded = answers.values.contains { ($0 as? [String: Any])?["success"] as? Bool == true }
                    if succeeded { return task.finish(.success(())) }
                    if !refreshFirst { return self.controlSource(action, source: source, refreshFirst: true, task: task) }
                    let message = answers.values.compactMap { ($0 as? [String: Any])?["error"] as? String }.first
                    task.finish(.failure(.other(message ?? "unknown source")))
                }
            }
        }
        guard refreshFirst else { return run() }
        request("POST", "/api/v1/control/refresh", auth: .control) { _ in run() }
    }

    func progress(completion: @escaping (ForkMacBackupEngineResult<ForkMacBackupKopia.SourcesResponse>) -> Void) {
        let task = task(completion)
        work.async { [self] in
            requestDecoding(ForkMacBackupKopia.SourcesResponse.self, "GET", "/api/v1/control/sources", auth: .control) {
                task.finish($0)
            }
        }
    }

    func setThrottle(uploadBytesPerSecond: Int64?, completion: @escaping (ForkMacBackupEngineResult<Void>) -> Void) {
        let task = task(completion)
        guard ownerOnly(task) else { return }
        work.async { [self] in
            // `{}` lifts every limit; Kopia keeps the limit in the config (SPIKES §2.3).
            var body: [String: Any] = [:]
            if let limit = uploadBytesPerSecond, limit > 0 { body["maxUploadSpeedBytesPerSecond"] = limit }
            request("PUT", "/api/v1/control/throttle", json: body, auth: .control) { result in
                task.finish(result.map { _ in () }.mapError(\.engineError))
            }
        }
    }

    func listSnapshots(source: ForkMacBackupSource?,
                       completion: @escaping (ForkMacBackupEngineResult<[ForkMacBackupKopia.SnapshotManifest]>) -> Void) {
        let task = task(completion)
        work.async { [self] in
            listManifests(sourcePath: source?.path, incomplete: false, task: task) { task.finish(.success($0)) }
        }
    }

    /// The manifests, a source's own (filtered on `source.path`) or all,
    /// oldest first (Kopia's order). Owner: the CLI; client: the server.
    func listManifests<Value>(sourcePath: String?, incomplete: Bool, task: ForkMacBackupEngineTask<Value>,
                              then: @escaping ([ForkMacBackupKopia.SnapshotManifest]) -> Void) {
        dispatchPrecondition(condition: .onQueue(work))
        let path = sourcePath.map(ForkMacBackupSourcePath.normalized)
        switch role {
        case .owner:
            let handle = runCLI(ForkMacBackupKopiaCommand.snapshotList(path: path, incomplete: incomplete),
                                timeout: 600) { result in
                switch result {
                case .failure(let error): task.finish(.failure(error))
                case .success(let outcome):
                    if let error = Self.failure(of: outcome) { return task.finish(.failure(error)) }
                    guard let manifests = ForkMacBackupKopia.decode([ForkMacBackupKopia.SnapshotManifest].self,
                                                                    from: outcome.stdout) else {
                        return task.finish(.failure(.decoding("snapshot list")))
                    }
                    then(path.map { path in manifests.filter { $0.source?.path == path } } ?? manifests)
                }
            }
            task.attach(handle)
        case .client:
            // Every Mac and account of the repository (`multiUser`); the
            // server learns new sources every 4 h only, so the whole list
            // asks it to look again first (another Mac's first snapshot).
            let list = {
                self.requestDecoding(ForkMacBackupKopia.SourcesResponse.self, "GET", "/api/v1/sources", auth: .ui) { result in
                    switch result {
                    case .failure(let error): task.finish(.failure(error))
                    case .success(let sources):
                        let wanted = sources.sources.compactMap(\.source).filter { path == nil || $0.path == path }
                        self.collectSnapshots(wanted, incomplete: incomplete, collected: [], task: task, then: then)
                    }
                }
            }
            guard path == nil else { return list() }
            request("POST", "/api/v1/control/refresh", auth: .control) { _ in list() }
        }
    }

    private func collectSnapshots<Value>(_ sources: [ForkMacBackupKopia.SourceInfo], incomplete: Bool,
                                         collected: [ForkMacBackupKopia.SnapshotManifest],
                                         task: ForkMacBackupEngineTask<Value>,
                                         then: @escaping ([ForkMacBackupKopia.SnapshotManifest]) -> Void) {
        guard let source = sources.first else {
            return then(collected.sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) })
        }
        // `all=1`: without it the server folds identical snapshots into one.
        let query = [("userName", source.userName ?? ""), ("host", source.host ?? ""), ("path", source.path ?? ""),
                     ("all", "1")]
        requestDecoding(ForkMacBackupKopia.SnapshotsResponse.self, "GET", "/api/v1/snapshots", query: query,
                        auth: .ui) { result in
            switch result {
            case .failure(let error): task.finish(.failure(error))
            case .success(let response):
                let mapped = response.snapshots
                    .filter { incomplete || ($0.incompleteReason ?? "").isEmpty }
                    .compactMap { ForkMacBackupSnapshotMapping.manifest($0, source: source) }
                self.collectSnapshots(Array(sources.dropFirst()), incomplete: incomplete, collected: collected + mapped,
                                      task: task, then: then)
            }
        }
    }

    // MARK: - Live progress and conclusion

    func liveProgress(of source: ForkMacBackupSource,
                      completion: @escaping (ForkMacBackupEngineResult<ForkMacBackupLiveProgress?>) -> Void) {
        let task = task(completion)
        work.async { [self] in
            requestDecoding(ForkMacBackupKopia.SourcesResponse.self, "GET", "/api/v1/control/sources", auth: .control) { result in
                switch result {
                case .failure(let error): task.finish(.failure(error))
                case .success(let sources):
                    guard let status = sources.source(path: ForkMacBackupSourcePath.normalized(source.path)) else {
                        return task.finish(.success(nil))
                    }
                    guard let taskID = status.currentTask, !taskID.isEmpty else {
                        return task.finish(.success(ForkMacBackupLiveProgress(status: status, uploadedBytes: nil, task: nil)))
                    }
                    self.requestDecoding(ForkMacBackupKopia.TaskInfo.self, "GET",
                                         "/api/v1/tasks/" + ForkMacBackupHTTP.percentEncoded(taskID), auth: .ui) { taskResult in
                        let info = try? taskResult.get()
                        task.finish(.success(ForkMacBackupLiveProgress(
                            status: status, uploadedBytes: info.flatMap(ForkMacBackupLiveProgress.uploadedBytes(of:)),
                            task: info)))
                    }
                }
            }
        }
    }

    func conclude(_ source: ForkMacBackupSource, startedAt: Date, taskID: String?, iCloud: ForkMacBackupICloudMode,
                  completion: @escaping (ForkMacBackupEngineResult<ForkMacBackupRunConclusion>) -> Void) {
        let task = task(completion)
        work.async { [self] in
            let path = ForkMacBackupSourcePath.normalized(source.path)
            listManifests(sourcePath: path, incomplete: true, task: task) { manifests in
                self.snapshotTask(path: path, startedAt: startedAt, knownID: taskID) { info in
                    let finish = { (conclusion: ForkMacBackupRunConclusion) in
                        var conclusion = conclusion
                        conclusion.taskID = info?.id ?? taskID
                        conclusion.uploadedBytes = info.flatMap(ForkMacBackupLiveProgress.uploadedBytes(of:))
                        task.finish(.success(conclusion))
                    }
                    guard let manifest = ForkMacBackupRunConclusion.manifest(of: path, startedAt: startedAt,
                                                                             in: manifests) else {
                        return finish(.conclude(sourcePath: path, startedAt: startedAt, manifests: manifests,
                                                failures: nil, iCloud: iCloud))
                    }
                    self.collectFailures(of: manifest, taskID: info?.id ?? taskID, task: task) { failures in
                        finish(.conclude(sourcePath: path, startedAt: startedAt, manifests: manifests,
                                         failures: failures, iCloud: iCloud))
                    }
                }
            }
        }
    }

    /// The server's snapshot task of the run: `knownID`'s, else the latest
    /// one of this source started since `startedAt` (a short run may end
    /// before the agent ever sees its `currentTask`). Nil when the server
    /// does not answer or forgot it.
    private func snapshotTask(path: String, startedAt: Date, knownID: String?,
                              completion: @escaping (ForkMacBackupKopia.TaskInfo?) -> Void) {
        if let knownID, !knownID.isEmpty {
            return requestDecoding(ForkMacBackupKopia.TaskInfo.self, "GET",
                                   "/api/v1/tasks/" + ForkMacBackupHTTP.percentEncoded(knownID), auth: .ui) {
                completion(try? $0.get())
            }
        }
        let identity = self.identity ?? repository?.clientIdentity
        guard let identity else { return completion(nil) }
        requestDecoding(ForkMacBackupKopia.TasksResponse.self, "GET", "/api/v1/tasks", auth: .ui) { result in
            let tasks = (try? result.get())?.tasks ?? []
            completion(ForkMacBackupRunConclusion.snapshotTask(in: tasks, identity: identity, sourcePath: path,
                                                               startedAt: startedAt))
        }
    }

    func failures(of manifest: ForkMacBackupKopia.SnapshotManifest, taskID: String?,
                  completion: @escaping (ForkMacBackupEngineResult<[ForkMacBackupFailure]>) -> Void) {
        let task = task(completion)
        work.async { [self] in
            collectFailures(of: manifest, taskID: taskID, task: task) { task.finish(.success($0)) }
        }
    }

    /// The root summary's errors, the folders' below when Kopia counted
    /// more, and the snapshot task's log. A part that cannot be read (the
    /// server down) leaves the others.
    private func collectFailures<Value>(of manifest: ForkMacBackupKopia.SnapshotManifest, taskID: String?,
                                        task: ForkMacBackupEngineTask<Value>,
                                        then: @escaping ([ForkMacBackupFailure]) -> Void) {
        var summaries: [(folder: String, errors: [ForkMacBackupKopia.EntryError])] =
            [("", manifest.rootEntry?.summ?.errors ?? [])]
        let withLogs: (ForkMacBackupFailureList.TaskLogs?) -> Void = { logs in
            then(ForkMacBackupFailureList.merge(summaries: summaries, taskLogs: logs))
        }
        let readLogs = {
            guard let taskID, !taskID.isEmpty else { return withLogs(nil) }
            self.requestDecoding(ForkMacBackupFailureList.TaskLogs.self, "GET",
                                 "/api/v1/tasks/\(ForkMacBackupHTTP.percentEncoded(taskID))/logs", auth: .ui,
                                 timeout: 120) { result in
                withLogs(try? result.get())
            }
        }
        guard ForkMacBackupFailureList.needsWalk(manifest), let root = manifest.rootEntry?.obj else { return readLogs() }
        walkFailures([(root, "")], budget: 10_000) { found in
            summaries += found
            readLogs()
        }
    }

    /// Folders with failures, breadth first, at most `budget` listings.
    private func walkFailures(_ queue: [(oid: String, folder: String)], budget: Int,
                              found: [(folder: String, errors: [ForkMacBackupKopia.EntryError])] = [],
                              then: @escaping ([(folder: String, errors: [ForkMacBackupKopia.EntryError])]) -> Void) {
        guard let next = queue.first, budget > 0 else { return then(found) }
        requestDecoding(ForkMacBackupKopia.DirectoryManifest.self, "GET",
                        "/api/v1/objects/" + ForkMacBackupHTTP.percentEncoded(next.oid), auth: .uiWithoutCSRF) { result in
            var rest = Array(queue.dropFirst())
            var found = found
            if case .success(let directory) = result {
                found.append((next.folder, directory.summary?.errors ?? []))
                for entry in directory.entries where entry.isDirectory && (entry.summ?.numFailed ?? 0) > 0 {
                    guard let oid = entry.obj, let name = entry.name else { continue }
                    rest.append((oid, next.folder.isEmpty ? name : next.folder + "/" + name))
                }
            }
            self.walkFailures(rest, budget: budget - 1, found: found, then: then)
        }
    }

    // MARK: - Maintenance info

    func maintenanceInfo(completion: @escaping (ForkMacBackupEngineResult<ForkMacBackupMaintenanceInfo>) -> Void) {
        let task = task(completion)
        guard ownerOnly(task) else { return }
        work.async { [self] in
            let handle = runCLI(ForkMacBackupKopiaCommand.maintenanceInfo, timeout: 120) { result in
                switch result {
                case .failure(let error): task.finish(.failure(error))
                case .success(let outcome):
                    if let error = Self.failure(of: outcome) { return task.finish(.failure(error)) }
                    guard let info = ForkMacBackupMaintenanceInfo.decode(outcome.stdout) else {
                        return task.finish(.failure(.decoding("maintenance info")))
                    }
                    task.finish(.success(info))
                }
            }
            task.attach(handle)
        }
    }

    /// Polls `/api/v1/tasks/{id}` every half second until it ends; a
    /// cancel of `task` cancels the server's task.
    func followTask<Value>(_ id: String, task: ForkMacBackupEngineTask<Value>,
                           progress: @escaping (ForkMacBackupKopia.TaskInfo) -> Void,
                           then: @escaping (ForkMacBackupKopia.TaskInfo) -> Void) {
        let path = "/api/v1/tasks/" + ForkMacBackupHTTP.percentEncoded(id)
        task.attach(ForkMacBackupEngineCallback { [weak self] in
            self?.work.async { self?.request("POST", path + "/cancel", auth: .ui) { _ in } }
        })
        func poll() {
            guard !task.isFinished else { return }
            requestDecoding(ForkMacBackupKopia.TaskInfo.self, "GET", path, auth: .ui) { [weak self] result in
                guard let self, !task.isFinished else { return }
                switch result {
                case .failure(let error): task.finish(.failure(error))
                case .success(let info):
                    if info.isFinished { return then(info) }
                    progress(info)
                    self.work.asyncAfter(deadline: .now() + 0.5) { poll() }
                }
            }
        }
        poll()
    }
}

/// One call's completion, once, on its queue; a cancel cancels its
/// children (processes, downloads, the server's task) and completes with
/// `.canceled`.
final class ForkMacBackupEngineTask<Value>: ForkMacBackupCancellable {
    private let lock = NSLock()
    private let queue: DispatchQueue
    private var completion: ((ForkMacBackupEngineResult<Value>) -> Void)?
    private var children: [ForkMacBackupCancellable] = []
    private var canceled = false

    init(queue: DispatchQueue, completion: @escaping (ForkMacBackupEngineResult<Value>) -> Void) {
        self.queue = queue
        self.completion = completion
    }

    var isCanceled: Bool { lock.withLock { canceled } }
    var isFinished: Bool { lock.withLock { completion == nil } }

    /// A child to cancel with the task (cancelled at once when the task
    /// already is).
    func attach(_ child: ForkMacBackupCancellable?) {
        guard let child else { return }
        let cancelNow: Bool = lock.withLock {
            if canceled { return true }
            children.append(child)
            return false
        }
        if cancelNow { child.cancel() }
    }

    func finish(_ result: ForkMacBackupEngineResult<Value>) {
        let completion: ((ForkMacBackupEngineResult<Value>) -> Void)? = lock.withLock {
            let pending = self.completion
            self.completion = nil
            children.removeAll()
            return pending
        }
        guard let completion else { return }
        queue.async { completion(result) }
    }

    func cancel() {
        let children: [ForkMacBackupCancellable] = lock.withLock {
            guard !canceled, completion != nil else { return [] }
            canceled = true
            return self.children
        }
        children.forEach { $0.cancel() }
        finish(.failure(.canceled))
    }
}

/// A cancel action as a `ForkMacBackupCancellable`.
final class ForkMacBackupEngineCallback: ForkMacBackupCancellable {
    private let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    func cancel() { action() }
}
