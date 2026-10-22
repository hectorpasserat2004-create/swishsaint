// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// The search in one snapshot (plan §6.2): Kopia has no name index, so the
/// folders are walked, breadth first, a few at a time. The walk's state
/// lives on a private queue; the engine answers on the main queue and is
/// asked from it; the results reach the window in batches. Cancellable at
/// any point, and bounded.
final class ForkMacBackupSnapshotSearch {
    struct State: Equatable {
        var query: String
        var results: [ForkMacBackupBrowseEntry]
        var running: Bool
        var truncated: Bool

        static let idle = State(query: "", results: [], running: false, truncated: false)
    }

    static let maxResults = 2_000
    static let maxFolders = 200_000
    static let parallelFolders = 4
    static let publishInterval: TimeInterval = 0.2

    private let engine: ForkMacBackupEngineDriving
    private let rootObjectID: String
    private let query: ForkMacBackupNameQuery
    private let queryText: String
    private let publish: (State) -> Void
    private let queue = DispatchQueue(label: "fork.macbackup.window.search", qos: .userInitiated)
    /// Main thread.
    private var canceledOnMain = false

    // Owned by `queue`.
    private var pending: [(objectID: String, path: String)] = []
    private var inFlight = 0
    private var visited = 0
    private var results: [ForkMacBackupBrowseEntry] = []
    private var truncated = false
    private var canceled = false
    private var finished = false
    private var lastPublish = Date.distantPast
    private var publishScheduled = false

    init(engine: ForkMacBackupEngineDriving, rootObjectID: String, query: String, publish: @escaping (State) -> Void) {
        self.engine = engine
        self.rootObjectID = rootObjectID
        self.query = ForkMacBackupNameQuery(query)
        queryText = query
        self.publish = publish
    }

    func start() {
        queue.async {
            self.pending = [(self.rootObjectID, "")]
            self.pump()
        }
    }

    /// Main thread: nothing is published after it returns.
    func cancel() {
        canceledOnMain = true
        queue.async { self.canceled = true }
    }

    // MARK: On `queue`

    private func pump() {
        guard !canceled, !finished else { return }
        while inFlight < Self.parallelFolders, !pending.isEmpty, !truncated {
            let next = pending.removeFirst()
            inFlight += 1
            visited += 1
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.engine.browse(objectID: next.objectID) { [weak self] result in
                    self?.queue.async { self?.received(result, path: next.path) }
                }
            }
        }
        if inFlight == 0 && (pending.isEmpty || truncated) {
            finished = true
            emit(force: true)
        }
    }

    private func received(_ result: ForkMacBackupEngineResult<ForkMacBackupKopia.DirectoryManifest>, path: String) {
        inFlight -= 1
        guard !canceled else { return }
        if case .success(let manifest) = result {
            for entry in ForkMacBackupBrowseEntry.entries(of: manifest, folder: path) {
                if query.matches(entry.name) {
                    if results.count >= Self.maxResults {
                        truncated = true
                        break
                    }
                    results.append(entry)
                }
                if entry.isDirectory && visited + pending.count < Self.maxFolders {
                    pending.append((entry.objectID, entry.relativePath))
                } else if entry.isDirectory {
                    truncated = true
                }
            }
        }
        emit(force: false)
        pump()
    }

    private func emit(force: Bool) {
        guard !canceled else { return }
        let elapsed = Date().timeIntervalSince(lastPublish)
        if !force && elapsed < Self.publishInterval {
            guard !publishScheduled else { return }
            publishScheduled = true
            queue.asyncAfter(deadline: .now() + Self.publishInterval - elapsed) { [weak self] in
                guard let self else { return }
                self.publishScheduled = false
                self.emit(force: false)
            }
            return
        }
        lastPublish = Date()
        let state = State(query: queryText, results: results.sorted(by: ForkMacBackupBrowseEntry.finderOrder),
                          running: !finished, truncated: truncated)
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.canceledOnMain else { return }
            self.publish(state)
        }
    }
}
