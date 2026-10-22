// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Darwin
import Foundation

/// Browsing, versions and restoring (plan §6): both roles, through the
/// server (the owner falls back to `kopia restore` when its server is
/// down).
extension ForkMacBackupKopiaEngine {
    // MARK: Browse

    func browse(objectID: String,
                completion: @escaping (ForkMacBackupEngineResult<ForkMacBackupKopia.DirectoryManifest>) -> Void) {
        let task = task(completion)
        work.async { [self] in
            listing(objectID) { task.finish($0) }
        }
    }

    /// `GET /api/v1/objects/{oid}` read as a folder (Basic auth only).
    func listing(_ objectID: String,
                 completion: @escaping (ForkMacBackupEngineResult<ForkMacBackupKopia.DirectoryManifest>) -> Void) {
        requestDecoding(ForkMacBackupKopia.DirectoryManifest.self, "GET",
                        "/api/v1/objects/" + ForkMacBackupHTTP.percentEncoded(objectID), auth: .uiWithoutCSRF) { result in
            if case .success(let directory) = result, directory.stream != nil, directory.stream != "kopia:directory" {
                return completion(.failure(.decoding("not a folder")))
            }
            completion(result)
        }
    }

    // MARK: Versions

    /// This Mac's versions (the repository's client identity).
    func versions(of relativePath: String, in source: ForkMacBackupSource,
                  completion: @escaping (ForkMacBackupEngineResult<[ForkMacBackupFileVersion]>) -> Void) {
        let task = task(completion)
        work.async { [self] in
            currentIdentity { identity in
                guard let identity else { return task.finish(.failure(.notConnected)) }
                self.collectVersions(of: relativePath, in: source, owner: identity, task: task)
            }
        }
    }

    /// The versions of `owner`'s file (another Mac's in the window).
    func versions(of relativePath: String, in source: ForkMacBackupSource, owner: ForkMacBackupRepository.Identity,
                  completion: @escaping (ForkMacBackupEngineResult<[ForkMacBackupFileVersion]>) -> Void) {
        let task = task(completion)
        work.async { [self] in
            collectVersions(of: relativePath, in: source, owner: owner, task: task)
        }
    }

    private func collectVersions(of relativePath: String, in source: ForkMacBackupSource,
                                 owner: ForkMacBackupRepository.Identity,
                                 task: ForkMacBackupEngineTask<[ForkMacBackupFileVersion]>) {
        let path = ForkMacBackupSourcePath.normalized(source.path)
        listManifests(sourcePath: path, incomplete: false, task: task) { manifests in
            let wanted = ForkMacBackupVersionsPlan.manifests(of: path, owner: owner, in: manifests)
            self.resolveAll(wanted, relativePath: relativePath, index: 0, found: [], cache: [:], task: task) { found in
                task.finish(.success(ForkMacBackupVersionsPlan.distinct(found)))
            }
        }
    }

    /// Who this Mac is in the repository: the owner's connected identity;
    /// for the app's client, the agent's server says it
    /// (`control/sources`: `localUsername@localHost`). On `work`.
    func currentIdentity(_ completion: @escaping (ForkMacBackupRepository.Identity?) -> Void) {
        dispatchPrecondition(condition: .onQueue(work))
        if let known = identity ?? repository?.clientIdentity { return completion(known) }
        requestDecoding(ForkMacBackupKopia.SourcesResponse.self, "GET", "/api/v1/control/sources", auth: .control) { [weak self] result in
            guard let self else { return completion(nil) }
            guard case .success(let sources) = result, let user = sources.localUsername, let host = sources.localHost,
                  !user.isEmpty, !host.isEmpty else { return completion(nil) }
            let found = ForkMacBackupRepository.Identity(userName: user, hostName: host)
            self.identity = found
            completion(found)
        }
    }

    /// Resolves the path in each snapshot in turn; folder listings are
    /// cached by object ID across snapshots (an unchanged folder keeps its
    /// object ID).
    private func resolveAll<Value>(_ manifests: [ForkMacBackupKopia.SnapshotManifest], relativePath: String, index: Int,
                                   found: [ForkMacBackupVersionsPlan.Found],
                                   cache: [String: ForkMacBackupKopia.DirectoryManifest],
                                   task: ForkMacBackupEngineTask<Value>,
                                   then: @escaping ([ForkMacBackupVersionsPlan.Found]) -> Void) {
        guard index < manifests.count, !task.isFinished else { return then(found) }
        let manifest = manifests[index]
        resolve(relativePath, in: manifest, cache: cache) { [weak self] result, cache in
            guard let self else { return }
            var found = found
            switch result {
            case .success(let entry):
                found.append(.init(manifest: manifest, entry: entry))
            case .failure(let error) where [.serverUnavailable, .notConnected, .timeout, .canceled].contains(error):
                return task.finish(.failure(error))
            case .failure:
                // An unreadable folder in one snapshot: that snapshot does not count.
                found.append(.init(manifest: manifest, entry: nil))
            }
            self.resolveAll(manifests, relativePath: relativePath, index: index + 1, found: found, cache: cache,
                            task: task, then: then)
        }
    }

    /// The entry at `relativePath` in a snapshot (the root entry for « »);
    /// `.success(nil)` when the path did not exist in it.
    func resolve(_ relativePath: String, in manifest: ForkMacBackupKopia.SnapshotManifest,
                 cache: [String: ForkMacBackupKopia.DirectoryManifest] = [:],
                 completion: @escaping (ForkMacBackupEngineResult<ForkMacBackupKopia.DirEntry?>,
                                        [String: ForkMacBackupKopia.DirectoryManifest]) -> Void) {
        let parts = ForkMacBackupVersionsPlan.components(relativePath)
        guard let root = manifest.rootEntry else { return completion(.success(nil), cache) }
        guard !parts.isEmpty else { return completion(.success(root), cache) }
        descend(root, parts: parts[...], cache: cache, completion: completion)
    }

    private func descend(_ entry: ForkMacBackupKopia.DirEntry, parts: ArraySlice<String>,
                         cache: [String: ForkMacBackupKopia.DirectoryManifest],
                         completion: @escaping (ForkMacBackupEngineResult<ForkMacBackupKopia.DirEntry?>,
                                                [String: ForkMacBackupKopia.DirectoryManifest]) -> Void) {
        guard let name = parts.first else { return completion(.success(entry), cache) }
        guard entry.isDirectory, let oid = entry.obj else { return completion(.success(nil), cache) }
        let step = { (directory: ForkMacBackupKopia.DirectoryManifest, cache: [String: ForkMacBackupKopia.DirectoryManifest]) in
            guard let child = ForkMacBackupVersionsPlan.entry(named: name, in: directory) else {
                return completion(.success(nil), cache)
            }
            self.descend(child, parts: parts.dropFirst(), cache: cache, completion: completion)
        }
        if let cached = cache[oid] { return step(cached, cache) }
        listing(oid) { result in
            switch result {
            case .failure(let error): completion(.failure(error), cache)
            case .success(let directory):
                var cache = cache
                cache[oid] = directory
                step(directory, cache)
            }
        }
    }

    // MARK: Restore

    @discardableResult
    func restore(_ request: ForkMacBackupRestoreRequest, progress: @escaping (ForkMacBackupRestoreProgress) -> Void,
                 completion: @escaping (ForkMacBackupEngineResult<ForkMacBackupRestoreReport>) -> Void)
        -> ForkMacBackupCancellable {
        let task = task(completion)
        work.async { [self] in
            let sourcePath = ForkMacBackupSourcePath.normalized(request.sourcePath)
            listManifests(sourcePath: sourcePath, incomplete: true, task: task) { manifests in
                guard let manifest = manifests.first(where: { $0.id == request.manifestID }) else {
                    return task.finish(.failure(.other("snapshot not found")))
                }
                let steps = ForkMacBackupRestorePlan.steps(request, word: self.restoredSuffix) { FileManager.default.fileExists(atPath: $0) }
                self.resolveSteps(steps, manifest: manifest, index: 0, resolved: [], task: task) { resolved in
                    let run = RestoreRun(request: request, manifest: manifest, steps: resolved,
                                         staging: self.paths.root.appendingPathComponent("restore", isDirectory: true)
                                            .appendingPathComponent(UUID().uuidString, isDirectory: true),
                                         progress: progress)
                    self.restoreNext(run, index: 0, task: task)
                }
            }
        }
        return task
    }

    /// One restore's running totals.
    final class RestoreRun {
        let request: ForkMacBackupRestoreRequest
        let manifest: ForkMacBackupKopia.SnapshotManifest
        let steps: [(step: ForkMacBackupRestorePlan.Step, entry: ForkMacBackupKopia.DirEntry)]
        let staging: URL
        let progress: (ForkMacBackupRestoreProgress) -> Void
        let bytesTotal: Int64
        let filesTotal: Int64
        var bytesDone: Int64 = 0
        var filesDone: Int64 = 0
        var failures: [ForkMacBackupFailure] = []
        /// Where the single item really landed (« garder les deux » renames it).
        var landedPath: String?

        init(request: ForkMacBackupRestoreRequest, manifest: ForkMacBackupKopia.SnapshotManifest,
             steps: [(step: ForkMacBackupRestorePlan.Step, entry: ForkMacBackupKopia.DirEntry)], staging: URL,
             progress: @escaping (ForkMacBackupRestoreProgress) -> Void) {
            self.request = request
            self.manifest = manifest
            self.steps = steps
            self.staging = staging
            self.progress = progress
            bytesTotal = steps.reduce(0) { $0 + ($1.entry.totalSize ?? 0) }
            filesTotal = steps.reduce(0) { $0 + ($1.entry.isDirectory ? ($1.entry.summ?.files ?? 0) : 1) }
        }

        func report(bytes: Int64, files: Int64, queue: DispatchQueue) {
            let value = ForkMacBackupRestoreProgress(bytesDone: bytesDone + bytes,
                                                     bytesTotal: bytesTotal > 0 ? bytesTotal : nil,
                                                     files: filesDone + files,
                                                     filesTotal: filesTotal > 0 ? filesTotal : nil,
                                                     errors: failures.count)
            let progress = self.progress
            queue.async { progress(value) }
        }
    }

    private func resolveSteps<Value>(_ steps: [ForkMacBackupRestorePlan.Step], manifest: ForkMacBackupKopia.SnapshotManifest,
                                     index: Int,
                                     resolved: [(step: ForkMacBackupRestorePlan.Step, entry: ForkMacBackupKopia.DirEntry)],
                                     task: ForkMacBackupEngineTask<Value>,
                                     then: @escaping ([(step: ForkMacBackupRestorePlan.Step, entry: ForkMacBackupKopia.DirEntry)]) -> Void) {
        guard index < steps.count else { return then(resolved) }
        resolve(steps[index].item.relativePath, in: manifest) { [weak self] result, _ in
            switch result {
            case .failure(let error): task.finish(.failure(error))
            case .success(nil): task.finish(.failure(.other("not in this snapshot: \(steps[index].item.relativePath)")))
            case .success(let entry?):
                self?.resolveSteps(steps, manifest: manifest, index: index + 1, resolved: resolved + [(steps[index], entry)],
                                   task: task, then: then)
            }
        }
    }

    private func restoreNext(_ run: RestoreRun, index: Int, task: ForkMacBackupEngineTask<ForkMacBackupRestoreReport>) {
        guard !task.isFinished else {
            try? FileManager.default.removeItem(at: run.staging)
            return
        }
        guard index < run.steps.count else {
            try? FileManager.default.removeItem(at: run.staging)
            let destination: String
            if run.steps.count == 1, let only = run.steps.first {
                destination = run.landedPath ?? only.step.target
            } else if case .folder(let folder) = run.request.destination {
                destination = folder
            } else {
                destination = run.request.sourcePath
            }
            return task.finish(.success(ForkMacBackupRestoreReport(files: run.filesDone, bytes: run.bytesDone,
                                                                   failures: run.failures,
                                                                   destinationPath: destination)))
        }
        let (step, entry) = run.steps[index]
        var landing = URL(fileURLWithPath: step.target)
        if case .staged = step.kind {
            landing = run.staging.appendingPathComponent("\(index)", isDirectory: true)
                .appendingPathComponent(landing.lastPathComponent)
        }
        // The staging folder is ours (0700); a destination is the person's
        // and keeps the permissions it has or would get from the Finder.
        let parent = landing.deletingLastPathComponent()
        let ready: Bool
        if case .staged = step.kind {
            ready = PrivateFileStore.createDirectory(at: parent, container: paths.root)
        } else {
            ready = (try? FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)) != nil
        }
        guard ready else { return task.finish(.failure(.other("destination folder"))) }
        let finishStep = { (result: ForkMacBackupEngineResult<(files: Int64, bytes: Int64)>) in
            switch result {
            case .failure(let error):
                try? FileManager.default.removeItem(at: run.staging)
                task.finish(.failure(error))
            case .success(let counts):
                if case .staged(let rule) = step.kind {
                    var failures: [ForkMacBackupFailure] = []
                    var placed: String?
                    let merged = Self.merge(landing, into: URL(fileURLWithPath: step.target), rule: rule,
                                            suffix: self.restoredSuffix, sourceRoot: run.request.sourcePath,
                                            failures: &failures, placed: &placed)
                    run.failures += failures
                    if run.steps.count == 1 { run.landedPath = placed }
                    run.filesDone += merged.files
                    run.bytesDone += merged.bytes
                } else {
                    run.filesDone += counts.files
                    run.bytesDone += counts.bytes
                }
                run.report(bytes: 0, files: 0, queue: self.callbackQueue)
                self.restoreNext(run, index: index + 1, task: task)
            }
        }
        let root = ForkMacBackupRestorePlan.rootReference(manifestID: run.manifest.id, relativePath: step.item.relativePath)
        if entry.isDirectory {
            let mode = ForkMacBackupRestorePlan.KopiaMode(overwrite: step.overwrite, skipOwners: run.request.skipOwners,
                                                          ignorePermissionErrors: run.request.ignorePermissionErrors)
            restoreFolder(root: root, target: landing, mode: mode, run: run, task: task, completion: finishStep)
        } else {
            restoreFile(entry, to: landing, overwrite: step.overwrite, run: run, task: task, completion: finishStep)
        }
    }

    /// One file: streamed from `/api/v1/objects/{oid}` into `.partial`,
    /// then renamed, with its date and permissions.
    private func restoreFile(_ entry: ForkMacBackupKopia.DirEntry, to target: URL, overwrite: Bool, run: RestoreRun,
                             task: ForkMacBackupEngineTask<ForkMacBackupRestoreReport>,
                             completion: @escaping (ForkMacBackupEngineResult<(files: Int64, bytes: Int64)>) -> Void) {
        guard let oid = entry.obj else { return completion(.failure(.decoding("object ID"))) }
        if !overwrite, FileManager.default.fileExists(atPath: target.path) {
            return completion(.failure(.other("exists: \(target.path)")))
        }
        let partial = target.deletingLastPathComponent().appendingPathComponent(Self.partialName(for: target.lastPathComponent))
        try? FileManager.default.removeItem(at: partial)
        guard FileManager.default.createFile(atPath: partial.path, contents: nil, attributes: [.posixPermissions: 0o600]),
              let handle = try? FileHandle(forWritingTo: partial) else {
            return completion(.failure(.other("cannot write \(target.path)")))
        }
        let queue = callbackQueue
        var lastReport = Date.distantPast
        withAPI({ error in
            try? handle.close()
            try? FileManager.default.removeItem(at: partial)
            completion(.failure(error))
        }) { api in
            let download = api.download(objectID: oid, sink: { chunk in
                (try? handle.write(contentsOf: chunk)) != nil
            }, progress: { [weak self] received in
                let now = Date()
                guard now.timeIntervalSince(lastReport) >= 0.25 else { return }
                lastReport = now
                self?.work.async { run.report(bytes: received, files: 0, queue: queue) }
            }, completion: { result in
                try? handle.close()
                switch result {
                case .failure(let failure):
                    try? FileManager.default.removeItem(at: partial)
                    completion(.failure(failure.engineError))
                case .success(let bytes):
                    let manager = FileManager.default
                    // A link's object holds its destination: it comes back as a link.
                    let landed: URL
                    if entry.type == "s" {
                        let destination = (try? Data(contentsOf: partial)).map { String(decoding: $0, as: UTF8.self) }
                        try? manager.removeItem(at: partial)
                        let link = target.deletingLastPathComponent()
                            .appendingPathComponent("." + UUID().uuidString + ".link", isDirectory: false)
                        guard let destination, !destination.isEmpty,
                              (try? manager.createSymbolicLink(atPath: link.path, withDestinationPath: destination)) != nil else {
                            return completion(.failure(.other("cannot write \(target.path)")))
                        }
                        landed = link
                    } else {
                        landed = partial
                    }
                    var existing = stat()
                    let exists = lstat(target.path, &existing) == 0
                    // Never a folder replaced by a file; never the old file lost
                    // when the new one cannot take its place.
                    if exists, (existing.st_mode & S_IFMT) == S_IFDIR {
                        try? manager.removeItem(at: landed)
                        return completion(.failure(.other("a folder is in the way: \(target.path)")))
                    }
                    let placed: Bool
                    if exists && overwrite {
                        placed = (try? Self.replace(target, with: landed)) != nil
                    } else {
                        placed = (try? manager.moveItem(at: landed, to: target)) != nil
                    }
                    guard placed else {
                        try? manager.removeItem(at: landed)
                        return completion(.failure(.other("cannot write \(target.path)")))
                    }
                    if entry.type == "s" { return completion(.success((1, 0))) }
                    var attributes: [FileAttributeKey: Any] = [:]
                    if let modified = entry.modified { attributes[.modificationDate] = modified }
                    if let mode = entry.mode.flatMap({ Int($0, radix: 8) }) { attributes[.posixPermissions] = mode & 0o7777 }
                    try? manager.setAttributes(attributes, ofItemAtPath: target.path)
                    completion(.success((1, bytes)))
                }
            })
            task.attach(download)
        }
    }

    /// One folder: the server's restore task (full depth), followed every
    /// half second; the owner falls back to `kopia restore` when its server
    /// is down.
    private func restoreFolder(root: String, target: URL, mode: ForkMacBackupRestorePlan.KopiaMode, run: RestoreRun,
                               task: ForkMacBackupEngineTask<ForkMacBackupRestoreReport>,
                               completion: @escaping (ForkMacBackupEngineResult<(files: Int64, bytes: Int64)>) -> Void) {
        let body = ForkMacBackupRestorePlan.apiRequest(root: root, target: target.path, mode: mode)
        requestDecoding(ForkMacBackupKopia.TaskInfo.self, "POST", "/api/v1/restore", json: body, auth: .ui) { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(.serverUnavailable) where self.role == .owner:
                self.restoreFolderWithCLI(root: root, target: target, mode: mode, run: run, task: task, completion: completion)
            case .failure(let error):
                completion(.failure(error))
            case .success(let started):
                self.followTask(started.id, task: task, progress: { info in
                    run.report(bytes: info.counter("Restored Bytes") ?? 0, files: info.counter("Restored Files") ?? 0,
                               queue: self.callbackQueue)
                }, then: { info in
                    let ignored = info.counter("Ignored Errors") ?? 0
                    if ignored > 0 {
                        run.failures.append(ForkMacBackupFailure(path: root, cause: .permission,
                                                                 message: "\(ignored) ignored errors"))
                    }
                    switch info.knownStatus {
                    case .success?:
                        completion(.success((info.counter("Restored Files") ?? 0, info.counter("Restored Bytes") ?? 0)))
                    case .canceled?:
                        completion(.failure(.canceled))
                    default:
                        Self.log.error("restore task \(info.id, privacy: .public) ended \(info.status ?? "-", privacy: .public): \(info.errorMessage ?? "", privacy: .public)")
                        completion(.failure(.kopia(exitCode: 1, message: info.errorMessage ?? info.status ?? "restore")))
                    }
                })
            }
        }
    }

    private func restoreFolderWithCLI(root: String, target: URL, mode: ForkMacBackupRestorePlan.KopiaMode,
                                      run: RestoreRun, task: ForkMacBackupEngineTask<ForkMacBackupRestoreReport>,
                                      completion: @escaping (ForkMacBackupEngineResult<(files: Int64, bytes: Int64)>) -> Void) {
        let parts = root.split(separator: "/", maxSplits: 1).map(String.init)
        let arguments = ForkMacBackupKopiaCommand.restore(manifestID: parts[0], relativePath: parts.count > 1 ? parts[1] : "",
                                                          target: target.path, overwrite: mode.overwrite,
                                                          skipExisting: false, skipOwners: mode.skipOwners,
                                                          ignorePermissionErrors: mode.ignorePermissionErrors)
        let queue = callbackQueue
        let handle = runCLI(arguments, timeout: 7 * 24 * 3600, silenceTimeout: 30 * 60, onStderrLine: { line in
            guard let value = ForkMacBackupKopiaText.restoreProgressLine(line) else { return }
            run.report(bytes: value.processedBytes, files: value.processedEntries, queue: queue)
        }) { result in
            switch result {
            case .failure(let error): completion(.failure(error))
            case .success(let outcome):
                if let error = Self.failure(of: outcome) { return completion(.failure(error)) }
                let summary = ForkMacBackupKopiaText.restoreSummary(outcome.stderr)
                completion(.success((summary?.files ?? 0, summary?.bytes ?? 0)))
            }
        }
        task.attach(handle)
    }

    // MARK: Merging a staged restore

    /// Moves what was restored into `target` by `rule` (Kopia has neither
    /// « keep both » nor « replace if older »). Returns the files and bytes
    /// that landed; a file that cannot be moved is named in `failures`.
    static func merge(_ staged: URL, into target: URL, rule: ForkMacBackupRestoreRequest.Overwrite, suffix: String,
                      sourceRoot: String, failures: inout [ForkMacBackupFailure]) -> (files: Int64, bytes: Int64) {
        var placed: String?
        return merge(staged, into: target, rule: rule, suffix: suffix, sourceRoot: sourceRoot, failures: &failures,
                     placed: &placed)
    }

    /// `placed`: where `staged` itself landed (renamed by « garder les
    /// deux »), nil when it was kept out or merged into an existing folder
    /// (then `target`).
    static func merge(_ staged: URL, into target: URL, rule: ForkMacBackupRestoreRequest.Overwrite, suffix: String,
                      sourceRoot: String, failures: inout [ForkMacBackupFailure],
                      placed: inout String?) -> (files: Int64, bytes: Int64) {
        let manager = FileManager.default
        var info = stat()
        guard lstat(staged.path, &info) == 0 else { return (0, 0) }
        let stagedIsDirectory = (info.st_mode & S_IFMT) == S_IFDIR
        var existing = stat()
        let exists = lstat(target.path, &existing) == 0
        let targetIsDirectory = exists && (existing.st_mode & S_IFMT) == S_IFDIR
        let relative = target.path.hasPrefix(sourceRoot + "/") ? String(target.path.dropFirst(sourceRoot.count + 1)) : target.path
        func fail(_ message: String) {
            failures.append(ForkMacBackupFailure(path: relative, cause: .other, message: message))
        }

        if stagedIsDirectory && targetIsDirectory {
            placed = target.path
            var total: (files: Int64, bytes: Int64) = (0, 0)
            for child in (try? manager.contentsOfDirectory(atPath: staged.path)) ?? [] {
                let part = merge(staged.appendingPathComponent(child), into: target.appendingPathComponent(child),
                                 rule: rule, suffix: suffix, sourceRoot: sourceRoot, failures: &failures)
                total.files += part.files
                total.bytes += part.bytes
            }
            return total
        }
        let counts = stagedIsDirectory ? Self.counts(of: staged) : (1, Int64(info.st_size))
        // A folder against a file (or the reverse) is never replaced: both are kept.
        let mismatched = exists && stagedIsDirectory != targetIsDirectory
        let restoredFacts = ForkMacBackupRestorePlan.FileFacts(size: Int64(info.st_size), modified: Self.modified(info))
        let existingFacts: ForkMacBackupRestorePlan.FileFacts? = exists
            ? .init(size: mismatched ? -1 : Int64(existing.st_size), modified: Self.modified(existing)) : nil
        let decision = ForkMacBackupRestorePlan.decision(rule: mismatched ? .keepBoth : rule, name: target.lastPathComponent,
                                                         isDirectory: stagedIsDirectory,
                                                         restored: restoredFacts, existing: existingFacts,
                                                         suffix: suffix, isTaken: { name in
            manager.fileExists(atPath: target.deletingLastPathComponent().appendingPathComponent(name).path)
        })
        do {
            switch decision {
            case .keep:
                return (0, 0)
            case .move:
                try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try manager.moveItem(at: staged, to: target)
                placed = target.path
            case .replace:
                try replace(target, with: staged)
                placed = target.path
            case .moveRenamed(let name):
                let renamed = target.deletingLastPathComponent().appendingPathComponent(name)
                try manager.moveItem(at: staged, to: renamed)
                placed = renamed.path
            }
            return counts
        } catch {
            fail(error.localizedDescription)
            return (0, 0)
        }
    }

    /// Puts `source` in place of `target` without ever losing both: the
    /// existing item steps aside first (a rename in its own folder) and
    /// comes back when `source` cannot take its place (another volume full,
    /// a locked file).
    static func replace(_ target: URL, with source: URL) throws {
        let manager = FileManager.default
        let aside = target.deletingLastPathComponent()
            .appendingPathComponent("." + UUID().uuidString + ".replaced", isDirectory: false)
        try manager.moveItem(at: target, to: aside)
        do {
            try manager.moveItem(at: source, to: target)
        } catch {
            try? manager.moveItem(at: aside, to: target)
            throw error
        }
        try? manager.removeItem(at: aside)
    }

    /// `.<name>.partial`, or a short random name when that would pass the
    /// 255-byte limit of a file name.
    static func partialName(for name: String) -> String {
        let partial = "." + name + ".partial"
        return partial.utf8.count <= 255 ? partial : "." + UUID().uuidString + ".partial"
    }

    private static func modified(_ info: stat) -> Date {
        Date(timeIntervalSince1970: Double(info.st_mtimespec.tv_sec) + Double(info.st_mtimespec.tv_nsec) / 1e9)
    }

    private static func counts(of folder: URL) -> (files: Int64, bytes: Int64) {
        var files: Int64 = 0
        var bytes: Int64 = 0
        let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey])
        while let url = walker?.nextObject() as? URL {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values?.isRegularFile == true else { continue }
            files += 1
            bytes += Int64(values?.fileSize ?? 0)
        }
        return (files, bytes)
    }
}
