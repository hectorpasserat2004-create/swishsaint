// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Darwin
import Foundation

/// Verification (plan §7.1), blob stats and maintenance: the owner's CLI
/// work, plus the sample restore test through the server.
extension ForkMacBackupKopiaEngine {
    @discardableResult
    func verify(_ level: ForkMacBackupVerifyLevel, progress: @escaping (ForkMacBackupVerifyProgress) -> Void,
                completion: @escaping (ForkMacBackupEngineResult<ForkMacBackupVerifyReport>) -> Void)
        -> ForkMacBackupCancellable {
        let task = task(completion)
        guard ownerOnly(task) else { return task }
        let start = Date()
        let report = { (ids: [String], checked: Int64, errors: [String]) in
            ForkMacBackupVerifyReport(level: level, manifestIDs: ids, checked: checked, errors: errors, start: start,
                                      end: Date())
        }
        let callback = callbackQueue
        work.async { [self] in
            listManifests(sourcePath: nil, incomplete: false, task: task) { manifests in
                let ids = manifests.map(\.id)
                switch level {
                case .manifest:
                    task.finish(.success(report(ids, Int64(ids.count), [])))
                case .references, .contentSample:
                    var percent = 0.0
                    if case .contentSample(let value) = level { percent = value }
                    var lastProgress = Date.distantPast
                    let handle = self.runCLI(ForkMacBackupKopiaCommand.verify(percent: percent), timeout: 48 * 3600,
                                             silenceTimeout: 30 * 60, onStderrLine: { line in
                        guard let value = ForkMacBackupKopiaText.verifyProgress(line) else { return }
                        let now = Date()
                        guard now.timeIntervalSince(lastProgress) >= 0.5 else { return }
                        lastProgress = now
                        callback.async { progress(value) }
                    }) { result in
                        switch result {
                        case .failure(let error): task.finish(.failure(error))
                        case .success(let outcome):
                            if outcome.canceled { return task.finish(.failure(.canceled)) }
                            if outcome.timedOut { return task.finish(.failure(.timeout)) }
                            guard let verified = ForkMacBackupKopiaText.verifyResult(outcome.stdout) else {
                                return task.finish(.failure(Self.failure(of: outcome) ?? .decoding("verify")))
                            }
                            var errors = Self.errorLines(outcome.stderr)
                            let count = Int(verified.errorCount ?? 0)
                            if count > errors.count {
                                errors += Array(repeating: ForkMacBackupKopiaText.errorLine(outcome.stderr),
                                                count: count - errors.count)
                            }
                            if count == 0 { errors = [] }
                            // Kopia failed without naming an error: never a success.
                            if outcome.status != 0, errors.isEmpty {
                                return task.finish(.failure(Self.failure(of: outcome) ?? .other("verify")))
                            }
                            let checked = verified.stats?.processedObjectCount ?? 0
                            task.finish(.success(report(ids, checked, errors)))
                        }
                    }
                    task.attach(handle)
                case .full:
                    let handle = self.runCLI(ForkMacBackupKopiaCommand.contentVerifyFull, timeout: 72 * 3600,
                                             silenceTimeout: 60 * 60) { result in
                        switch result {
                        case .failure(let error): task.finish(.failure(error))
                        case .success(let outcome):
                            if outcome.canceled { return task.finish(.failure(.canceled)) }
                            if outcome.timedOut { return task.finish(.failure(.timeout)) }
                            let errors = Self.errorLines(outcome.stderr)
                            if outcome.status != 0, errors.isEmpty {
                                return task.finish(.failure(Self.failure(of: outcome) ?? .other("content verify")))
                            }
                            task.finish(.success(report(ids, Int64(ids.count), errors)))
                        }
                    }
                    task.attach(handle)
                case .restoreTest(let count):
                    self.restoreTest(count: count, manifests: manifests, task: task, progress: progress) { ids, checked, errors in
                        // Nothing compared (no snapshot, every file changed since,
                        // the server unreachable during the walk): not a proof.
                        if checked == 0, errors.isEmpty {
                            return task.finish(.failure(.other("restore test: no file could be compared")))
                        }
                        task.finish(.success(report(ids, checked, errors)))
                    }
                }
            }
        }
        return task
    }

    /// Kopia's error lines (not its JSON progress, not « Listing blobs »).
    static func errorLines(_ stderr: String) -> [String] {
        ForkMacBackupKopiaText.lines(stderr).filter { line in
            let lower = line.lowercased()
            return !line.hasPrefix("{") && (lower.hasPrefix("error") || lower.contains(" error ")
                || lower.contains("failed") || lower.contains("unable to") || lower.contains("not found"))
        }
    }

    func blobStats(completion: @escaping (ForkMacBackupEngineResult<ForkMacBackupBlobStats>) -> Void) {
        let task = task(completion)
        guard ownerOnly(task) else { return }
        work.async { [self] in
            let handle = runCLI(ForkMacBackupKopiaCommand.blobStats, timeout: 6 * 3600, silenceTimeout: 30 * 60) { result in
                switch result {
                case .failure(let error): task.finish(.failure(error))
                case .success(let outcome):
                    if let error = Self.failure(of: outcome) { return task.finish(.failure(error)) }
                    guard let stats = ForkMacBackupKopiaText.blobStats(String(decoding: outcome.stdout, as: UTF8.self),
                                                                       measuredAt: Date()) else {
                        return task.finish(.failure(.decoding("blob stats")))
                    }
                    task.finish(.success(stats))
                }
            }
            task.attach(handle)
        }
    }

    @discardableResult
    func maintenance(full: Bool, completion: @escaping (ForkMacBackupEngineResult<Void>) -> Void) -> ForkMacBackupCancellable {
        let task = task(completion)
        guard ownerOnly(task) else { return task }
        work.async { [self] in
            let handle = runCLI(ForkMacBackupKopiaCommand.maintenanceRun(full: full), timeout: 24 * 3600) { result in
                switch result {
                case .failure(let error): task.finish(.failure(error))
                case .success(let outcome):
                    if let error = Self.failure(of: outcome) { return task.finish(.failure(error)) }
                    task.finish(.success(()))
                }
            }
            task.attach(handle)
        }
        return task
    }

    // MARK: Sample restore test

    /// A file of a snapshot that can be compared with the Mac.
    struct SampleFile {
        var manifestID: String
        var sourcePath: String
        var relativePath: String
        var entry: ForkMacBackupKopia.DirEntry
    }

    /// `count` files of the latest complete snapshot of each of this Mac's
    /// sources, found by random walks down the tree, among those unchanged
    /// on the Mac since (same size, same date); each is downloaded to a
    /// temporary folder and compared byte for byte with the original, which
    /// must still be unchanged after the comparison.
    private func restoreTest<Value>(count: Int, manifests: [ForkMacBackupKopia.SnapshotManifest],
                                    task: ForkMacBackupEngineTask<Value>,
                                    progress: @escaping (ForkMacBackupVerifyProgress) -> Void,
                                    then: @escaping ([String], Int64, [String]) -> Void) {
        let identity = self.identity
        var latest: [String: ForkMacBackupKopia.SnapshotManifest] = [:]
        for manifest in manifests where manifest.incomplete == nil && manifest.rootEntry?.obj != nil {
            guard let path = manifest.source?.path,
                  identity == nil || (manifest.source?.userName == identity?.userName
                                      && manifest.source?.host == identity?.hostName) else { continue }
            if (latest[path]?.startDate ?? .distantPast) < (manifest.startDate ?? .distantPast) { latest[path] = manifest }
        }
        let chosen = Array(latest.values)
        guard !chosen.isEmpty, count > 0 else { return then([], 0, []) }
        var generator = SystemRandomNumberGenerator()
        let walks = max(8, count * 4)
        collectSamples(chosen, walks: walks, found: [:], generator: &generator, task: task) { [weak self] candidates in
            guard let self else { return }
            var generator = SystemRandomNumberGenerator()
            let eligible = candidates.filter { Self.isUnchanged($0) }
            let sample = ForkMacBackupRestorePlan.sample(eligible, count: count, size: { $0.entry.size ?? 0 },
                                                        using: &generator)
            let folder = self.paths.root.appendingPathComponent("verify", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            guard PrivateFileStore.createDirectory(at: folder) else { return task.finish(.failure(.other("folders"))) }
            self.compareSamples(sample, index: 0, folder: folder, checked: 0, errors: [], task: task,
                                progress: progress) { checked, errors in
                try? FileManager.default.removeItem(at: folder)
                then(Array(Set(sample.map(\.manifestID))).sorted(), checked, errors)
            }
        }
    }

    /// Random walks from each snapshot's root; every file met is a
    /// candidate (key: source + path).
    private func collectSamples<Value>(_ manifests: [ForkMacBackupKopia.SnapshotManifest], walks: Int,
                                       found: [String: SampleFile], generator: inout SystemRandomNumberGenerator,
                                       task: ForkMacBackupEngineTask<Value>,
                                       then: @escaping ([SampleFile]) -> Void) {
        guard walks > 0, !task.isFinished, let manifest = manifests.randomElement(using: &generator),
              let root = manifest.rootEntry?.obj, let sourcePath = manifest.source?.path else {
            return then(Array(found.values))
        }
        walkDown(oid: root, folder: "", depth: 0, manifest: manifest, sourcePath: sourcePath, found: found,
                 task: task) { [weak self] found in
            var generator = SystemRandomNumberGenerator()
            self?.collectSamples(manifests, walks: walks - 1, found: found, generator: &generator, task: task, then: then)
        }
    }

    private func walkDown<Value>(oid: String, folder: String, depth: Int, manifest: ForkMacBackupKopia.SnapshotManifest,
                                 sourcePath: String, found: [String: SampleFile], task: ForkMacBackupEngineTask<Value>,
                                 then: @escaping ([String: SampleFile]) -> Void) {
        guard depth < 24, !task.isFinished else { return then(found) }
        requestDecoding(ForkMacBackupKopia.DirectoryManifest.self, "GET",
                        "/api/v1/objects/" + ForkMacBackupHTTP.percentEncoded(oid), auth: .uiWithoutCSRF) { [weak self] result in
            guard let self, case .success(let directory) = result else { return then(found) }
            var found = found
            var folders: [(String, String)] = []
            for entry in directory.entries {
                guard let name = entry.name, let object = entry.obj else { continue }
                let relative = folder.isEmpty ? name : folder + "/" + name
                if entry.isDirectory {
                    folders.append((object, relative))
                } else if entry.type == "f" {
                    found[sourcePath + "\u{0}" + relative] = SampleFile(manifestID: manifest.id, sourcePath: sourcePath,
                                                                        relativePath: relative, entry: entry)
                }
            }
            guard let next = folders.randomElement() else { return then(found) }
            self.walkDown(oid: next.0, folder: next.1, depth: depth + 1, manifest: manifest, sourcePath: sourcePath,
                          found: found, task: task, then: then)
        }
    }

    /// Same size and same modification date (to the microsecond) as in the
    /// snapshot.
    static func isUnchanged(_ sample: SampleFile) -> Bool {
        let path = (sample.sourcePath as NSString).appendingPathComponent(sample.relativePath)
        var info = stat()
        guard lstat(path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
              let size = sample.entry.size, Int64(info.st_size) == size, let modified = sample.entry.modified else {
            return false
        }
        let local = Double(info.st_mtimespec.tv_sec) + Double(info.st_mtimespec.tv_nsec) / 1e9
        return abs(local - modified.timeIntervalSince1970) < 1e-5
    }

    private func compareSamples<Value>(_ samples: [SampleFile], index: Int, folder: URL, checked: Int64, errors: [String],
                                       task: ForkMacBackupEngineTask<Value>,
                                       progress: @escaping (ForkMacBackupVerifyProgress) -> Void,
                                       then: @escaping (Int64, [String]) -> Void) {
        guard index < samples.count, !task.isFinished else { return then(checked, errors) }
        let sample = samples[index]
        let copy = folder.appendingPathComponent("\(index)")
        let next = { (checked: Int64, errors: [String]) in
            try? FileManager.default.removeItem(at: copy)
            let total = Int64(samples.count)
            self.callbackQueue.async { progress(ForkMacBackupVerifyProgress(checked: checked, total: total)) }
            self.compareSamples(samples, index: index + 1, folder: folder, checked: checked, errors: errors, task: task,
                                progress: progress, then: then)
        }
        guard let oid = sample.entry.obj, FileManager.default.createFile(atPath: copy.path, contents: nil),
              let handle = try? FileHandle(forWritingTo: copy) else {
            return next(checked, errors + ["\(sample.relativePath): local copy"])
        }
        withAPI({ error in
            try? handle.close()
            next(checked, errors + ["\(sample.relativePath): \(error)"])
        }) { api in
            let download = api.download(objectID: oid, sink: { chunk in
                (try? handle.write(contentsOf: chunk)) != nil
            }, progress: { _ in }, completion: { result in
                try? handle.close()
                switch result {
                case .failure(let failure):
                    next(checked, errors + ["\(sample.relativePath): \(failure.engineError)"])
                case .success:
                    let original = URL(fileURLWithPath: sample.sourcePath).appendingPathComponent(sample.relativePath)
                    let same = Self.sameBytes(copy, original)
                    // Changed while compared: not a failure of the backup.
                    guard Self.isUnchanged(sample) else { return next(checked, errors) }
                    next(checked + 1, same ? errors : errors + ["\(sample.relativePath): content differs"])
                }
            })
            task.attach(download)
        }
    }

    /// Byte-for-byte comparison, 1 MB at a time.
    static func sameBytes(_ a: URL, _ b: URL) -> Bool {
        guard let first = try? FileHandle(forReadingFrom: a), let second = try? FileHandle(forReadingFrom: b) else {
            return false
        }
        defer {
            try? first.close()
            try? second.close()
        }
        while true {
            let left = (try? first.read(upToCount: 1 << 20)) ?? Data()
            let right = (try? second.read(upToCount: 1 << 20)) ?? Data()
            if left != right { return false }
            if left.isEmpty { return true }
        }
    }
}
