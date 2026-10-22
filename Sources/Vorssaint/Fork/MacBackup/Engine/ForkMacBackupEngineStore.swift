// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Combine
import CryptoKit
import Darwin
import Foundation
import os
import Security

/// The pinned Kopia binary on this Mac (plan §3.7), modelled on
/// `ForkParakeetModelStore`: nothing is downloaded without `install()`; the
/// archive is checked (size, SHA-256) before it is unpacked with
/// `/usr/bin/tar`; the binary must carry Kopia LLC's Developer ID signature
/// and print the pinned version; the unpacked folder is renamed into
/// `engine/kopia-<version>/` only once whole, Apache's `LICENSE` beside the
/// binary. The folder is either absent or complete.
///
/// `state` changes on the main thread. The engine belongs to this Mac: no
/// setting records it, the settings backup never carries it.
final class ForkMacBackupEngineStore: ObservableObject {
    typealias Manifest = ForkMacBackupEngineManifest

    static let shared = ForkMacBackupEngineStore(paths: ForkMacBackupPaths(container: PrivateFileStore.containerURL))

    @Published private(set) var state: ForkMacBackupEngineInstallState = .notInstalled

    let paths: ForkMacBackupPaths?
    private let source: URL
    private static let log = Logger(subsystem: "fork.macbackup", category: "engine-store")
    private let work = DispatchQueue(label: "fork.macbackup.engine-store", qos: .utility)
    private let lock = NSLock()
    private var token = 0
    private var download: Download?
    private var busy = false

    /// `source`: the archive's address (a `file://` copy in tests).
    init(paths: ForkMacBackupPaths?, source: URL = Manifest.url) {
        self.paths = paths
        self.source = source
        refresh()
    }

    /// `engine/kopia-<version>/kopia`, whether installed or not.
    var binaryLocation: URL? { paths?.engineBinary(version: Manifest.version) }

    /// The binary, when installed and signed by Kopia (checked on the
    /// calling thread: cached, cheap after the first call).
    var installedBinary: URL? {
        guard let binary = binaryLocation, FileManager.default.isExecutableFile(atPath: binary.path),
              ForkMacBackupEngineBinary.isTrusted(binary) else { return nil }
        return binary
    }

    var isBusy: Bool { lock.withLock { busy } }

    // MARK: State

    /// Reads the state from the disk (signature check off the main thread).
    func refresh() {
        guard !isBusy else { return }
        work.async { [weak self] in
            guard let self else { return }
            let installed = self.installedBinary != nil
            DispatchQueue.main.async {
                guard !self.isBusy else { return }
                if installed {
                    self.state = .installed(version: Manifest.version)
                } else if case .failed = self.state {
                    // Keep the last failure until the next attempt.
                } else {
                    self.state = .notInstalled
                }
            }
        }
    }

    // MARK: Install

    func install() {
        let current: Int? = lock.withLock {
            guard !busy else { return nil }
            busy = true
            token += 1
            return token
        }
        guard let current else { return }
        publish(current, .verifying)
        work.async { [weak self] in
            guard let self else { return }
            guard let paths = self.paths else { return self.finish(current, .failure(.io)) }
            if self.installedBinary != nil, self.versionMatches(paths.engineBinary(version: Manifest.version)) {
                return self.finish(current, .success(()))
            }
            guard PrivateFileStore.createDirectory(at: paths.engine) else { return self.finish(current, .failure(.io)) }
            if let free = Self.availableBytes(near: paths.engine), free < Manifest.requiredFreeBytes {
                return self.finish(current, .failure(.space))
            }
            self.publish(current, .downloading(0))
            let download = Download(source: self.source, progress: { [weak self] fraction in
                self?.publish(current, .downloading(fraction))
            }, completion: { [weak self] result in
                guard let self else { return }
                self.work.async {
                    guard self.isCurrent(current) else {
                        if case .success(let file) = result { try? FileManager.default.removeItem(at: file) }
                        return
                    }
                    switch result {
                    case .failure(let failure): self.finish(current, .failure(failure))
                    case .success(let archive): self.installArchive(archive, paths: paths, current: current)
                    }
                }
            })
            self.lock.withLock { self.download = download }
            download.start(into: paths.engine.appendingPathComponent(Manifest.archiveName + ".partial"))
        }
    }

    /// Stops a download; the state goes back to not installed.
    func cancel() {
        let download: Download? = lock.withLock {
            guard busy else { return nil }
            token += 1
            busy = false
            let running = self.download
            self.download = nil
            return running
        }
        download?.cancel()
        DispatchQueue.main.async { self.state = .notInstalled; self.refresh() }
    }

    /// Removes the engine, then installs it again (a binary that no longer
    /// starts, a failed signature).
    func reinstall() {
        let ready: Bool = lock.withLock {
            guard !busy else { return false }
            token += 1
            return true
        }
        guard ready, let paths else { return }
        work.async { [weak self] in
            try? FileManager.default.removeItem(at: paths.engineFolder(version: Manifest.version))
            ForkMacBackupEngineBinary.forget(paths.engineBinary(version: Manifest.version))
            DispatchQueue.main.async {
                self?.state = .notInstalled
                self?.install()
            }
        }
    }

    // MARK: Steps (on `work`)

    private func installArchive(_ archive: URL, paths: ForkMacBackupPaths, current: Int) {
        defer { try? FileManager.default.removeItem(at: archive) }
        publish(current, .verifying)
        guard Self.size(of: archive) == Manifest.archiveSize,
              Self.sha256(of: archive) == Manifest.archiveSHA256 else {
            Self.log.error("the downloaded archive is not the pinned one")
            return finish(current, .failure(.checksum))
        }
        let manager = FileManager.default
        let unpacked = paths.engine.appendingPathComponent("kopia-\(Manifest.version).unpack", isDirectory: true)
        let staging = paths.engine.appendingPathComponent("kopia-\(Manifest.version).partial", isDirectory: true)
        let final = paths.engineFolder(version: Manifest.version)
        try? manager.removeItem(at: unpacked)
        try? manager.removeItem(at: staging)
        defer { try? manager.removeItem(at: unpacked) }
        guard PrivateFileStore.createDirectory(at: unpacked), PrivateFileStore.createDirectory(at: staging) else {
            return finish(current, .failure(.io))
        }
        let tar = BoundedProcessRunner.run("/usr/bin/tar", ["-xzf", archive.path, "-C", unpacked.path],
                                           timeout: 120, maxOutputBytes: 16 * 1024,
                                           environment: ["PATH": "/usr/bin:/bin"])
        guard isCurrent(current) else { try? manager.removeItem(at: staging); return }
        let folder = unpacked.appendingPathComponent(Manifest.archiveFolder, isDirectory: true)
        let binary = folder.appendingPathComponent(Manifest.binaryName)
        let license = folder.appendingPathComponent(Manifest.licenseFile)
        guard tar.status == 0, Self.isRegularFile(binary), Self.isRegularFile(license) else {
            try? manager.removeItem(at: staging)
            return finish(current, .failure(.extract))
        }
        let stagedBinary = staging.appendingPathComponent(Manifest.binaryName)
        guard (try? manager.moveItem(at: binary, to: stagedBinary)) != nil,
              (try? manager.moveItem(at: license, to: staging.appendingPathComponent(Manifest.licenseFile))) != nil,
              chmod(stagedBinary.path, 0o755) == 0 else {
            try? manager.removeItem(at: staging)
            return finish(current, .failure(.io))
        }
        ForkMacBackupEngineBinary.forget(stagedBinary)
        guard ForkMacBackupEngineBinary.isTrusted(stagedBinary), versionMatches(stagedBinary) else {
            try? manager.removeItem(at: staging)
            return finish(current, .failure(.launch))
        }
        guard isCurrent(current) else { try? manager.removeItem(at: staging); return }
        try? manager.removeItem(at: final)
        guard (try? manager.moveItem(at: staging, to: final)) != nil else {
            try? manager.removeItem(at: staging)
            return finish(current, .failure(.io))
        }
        ForkMacBackupEngineBinary.forget(paths.engineBinary(version: Manifest.version))
        PrivateFileStore.createDirectory(at: final)
        Self.log.info("engine \(Manifest.version, privacy: .public) installed")
        finish(current, .success(()))
    }

    /// `kopia --version` prints the pinned build. Its HOME is a temporary
    /// folder: nothing of Kopia's lands in the user's own.
    private func versionMatches(_ binary: URL) -> Bool {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("swishsaint-kopia-version-\(getpid())")
        try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let result = BoundedProcessRunner.run(binary.path, ForkMacBackupKopiaCommand.version, timeout: 20,
                                              maxOutputBytes: 4096,
                                              environment: ["PATH": "/usr/bin:/bin", "HOME": home.path,
                                                            "KOPIA_CHECK_FOR_UPDATES": "false"])
        return result.status == 0 && Manifest.matchesVersionOutput(String(decoding: result.output, as: UTF8.self))
    }

    // MARK: State plumbing

    private func publish(_ current: Int, _ state: ForkMacBackupEngineInstallState) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isCurrent(current) else { return }
            self.state = state
        }
    }

    private func finish(_ current: Int, _ result: Result<Void, ForkMacBackupEngineInstallFailure>) {
        lock.withLock {
            guard token == current else { return }
            busy = false
            download = nil
        }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isCurrent(current) else { return }
            switch result {
            case .success: self.state = .installed(version: Manifest.version)
            case .failure(let failure): self.state = .failed(failure.rawValue)
            }
        }
    }

    private func isCurrent(_ candidate: Int) -> Bool {
        lock.withLock { token == candidate }
    }

    // MARK: Disk

    private static func size(of url: URL) -> Int64? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
    }

    static func sha256(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return Manifest.hex(Array(hasher.finalize()))
    }

    private static func isRegularFile(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFREG
    }

    private static func availableBytes(near url: URL) -> Int64? {
        var candidate = url
        while !FileManager.default.fileExists(atPath: candidate.path), candidate.pathComponents.count > 1 {
            candidate.deleteLastPathComponent()
        }
        let values = try? candidate.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    // MARK: Download

    /// One archive download into `target` (URLSession, no quarantine
    /// attribute); progress 0…1.
    private final class Download: NSObject, URLSessionDownloadDelegate {
        private let source: URL
        private let progress: (Double) -> Void
        private let completion: (Result<URL, ForkMacBackupEngineInstallFailure>) -> Void
        private var session: URLSession?
        private var target: URL?
        private let lock = NSLock()
        private var done = false
        private var lastReport = Date.distantPast

        init(source: URL, progress: @escaping (Double) -> Void,
             completion: @escaping (Result<URL, ForkMacBackupEngineInstallFailure>) -> Void) {
            self.source = source
            self.progress = progress
            self.completion = completion
        }

        func start(into target: URL) {
            self.target = target
            try? FileManager.default.removeItem(at: target)
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 60
            configuration.urlCache = nil
            configuration.httpCookieStorage = nil
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Developer"
            configuration.httpAdditionalHeaders = ["User-Agent": "Swishsaint/\(version)"]
            let queue = OperationQueue()
            queue.maxConcurrentOperationCount = 1
            queue.qualityOfService = .utility
            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
            self.session = session
            session.downloadTask(with: source).resume()
        }

        func cancel() {
            session?.invalidateAndCancel()
            end(.failure(.network))
        }

        private func end(_ result: Result<URL, ForkMacBackupEngineInstallFailure>) {
            let first: Bool = lock.withLock {
                guard !done else { return false }
                done = true
                return true
            }
            guard first else { return }
            session?.finishTasksAndInvalidate()
            completion(result)
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                        totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
            let expected = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : Manifest.archiveSize
            let now = Date()
            guard now.timeIntervalSince(lastReport) >= 0.1 else { return }
            lastReport = now
            progress(min(1, Double(totalBytesWritten) / Double(expected)))
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
            let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 200
            guard status / 100 == 2, let target else { return end(.failure(.network)) }
            // The temporary file vanishes when this method returns: move it now.
            try? FileManager.default.removeItem(at: target)
            guard (try? FileManager.default.moveItem(at: location, to: target)) != nil else { return end(.failure(.io)) }
            progress(1)
            end(.success(target))
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            if error != nil { end(.failure(.network)) }
        }
    }
}

/// Kopia LLC's Developer ID signature on a binary, checked before every
/// launch (SPIKES §6.1), cached by file identity so a launch costs one
/// `stat` once checked.
enum ForkMacBackupEngineBinary {
    private struct Identity: Equatable {
        var inode: UInt64
        var size: Int64
        var modified: Int
    }

    private static let lock = NSLock()
    private static var cache: [String: (identity: Identity, trusted: Bool)] = [:]

    static func isTrusted(_ url: URL) -> Bool {
        var info = stat()
        guard lstat(url.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { return false }
        let identity = Identity(inode: UInt64(info.st_ino), size: Int64(info.st_size), modified: info.st_mtimespec.tv_sec)
        if let cached = lock.withLock({ cache[url.path] }), cached.identity == identity { return cached.trusted }
        let trusted = checkSignature(url)
        lock.withLock { cache[url.path] = (identity, trusted) }
        return trusted
    }

    static func forget(_ url: URL) {
        lock.withLock { _ = cache.removeValue(forKey: url.path) }
    }

    private static func checkSignature(_ url: URL) -> Bool {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { return false }
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(ForkMacBackupEngineManifest.codeRequirement as CFString, [],
                                             &requirement) == errSecSuccess, let requirement else { return false }
        return SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures), requirement) == errSecSuccess
    }
}
