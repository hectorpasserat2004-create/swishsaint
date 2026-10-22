// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation
import os

/// Asks the CRM what became of each meeting sent, until it says ready or
/// failed: every 4 s at first, then 10 s, then 30 s (`ForkCastralSteps`),
/// for half an hour (two for the batch engine), then again at the next
/// look (the meeting's detail, the next launch). The CRM never calls back.
///
/// - Each status read is written in the meeting's `meeting.json`
///   (`castral`) and published for the library and the island.
/// - At launch, a send cut short goes on where it stopped (B3, B5), and a
///   deposit still at work is followed again.
/// - Nothing with the feature off; nothing is asked twice at once.
final class ForkCastralTracker {
    private let queue = DispatchQueue(label: "fork.meetings.castral.follow", qos: .utility)
    private let log = Logger(subsystem: "fork.meetings", category: "castral")
    private unowned let exports: ForkMeetingExports
    private let store: ForkMeetingStore
    private let wanted: () -> Bool

    /// Under `queue`: the meetings followed, by their folder's path.
    private var followed: [String: Follow] = [:]

    private struct Follow {
        var folder: URL
        let exporter: ForkCastralExporter
        let began: Date
        var misses = 0
        /// The meeting's id, from the first read: found again by it when its
        /// folder moved (filed in its company's folder, renamed elsewhere).
        var id: UUID?
    }

    /// Made by its exports (`castralTracker`), which it lives within.
    init(exports: ForkMeetingExports, store: ForkMeetingStore, wanted: @escaping () -> Bool) {
        self.exports = exports
        self.store = store
        self.wanted = wanted
    }

    /// Main thread. Follows the meeting's deposit, unless it already is.
    func follow(_ folder: URL, target: String) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let config = exports.config(target), config.kind == .castral else { return }
        let exporter = exports.castralExporter(config, request: nil)
        let path = folder.standardizedFileURL.path
        exports.castralResting.remove(path)
        queue.async { [self] in
            guard followed[path] == nil else { return }
            followed[path] = Follow(folder: folder, exporter: exporter, began: Date())
            tick(path)
        }
    }

    /// Main thread, at launch: what the last run left goes on, and what it
    /// left unfiled goes into its company's folder.
    func resumeAtLaunch() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard wanted(), let config = exports.castralConfig else { return }
        exports.fileUnfiled()
        queue.async { [self] in
            let unsettled = store.castralUnsettled().filter { $0.record.target == config.id }
            guard !unsettled.isEmpty else { return }
            log.notice("resuming \(unsettled.count, privacy: .public) deposits")
            DispatchQueue.main.async { [self] in
                for meeting in unsettled {
                    if meeting.record.step == .started {
                        follow(meeting.folder, target: config.id)
                    } else {
                        // The steps left say what comes next: no choice asked.
                        exports.enqueue(meeting.folder, config, automatic: false)
                    }
                }
            }
        }
    }

    /// Queue. One status read, then the next one planned, or the end.
    private func tick(_ path: String) {
        guard var follow = followed[path] else { return }
        func stop(resting: Bool = false) {
            followed[path] = nil
            if resting { DispatchQueue.main.async { [exports] in exports.castralResting.insert(path) } }
        }
        guard wanted() else { return stop() }
        var read = store.sidecar(in: follow.folder)
        if case .failure = read, let id = follow.id,
           let found = ForkMeetingExports.folder(of: id, near: follow.folder, root: store.root()) {
            follow.folder = found
            read = store.sidecar(in: found)
        }
        guard case let .success(sidecar) = read,
              var record = ForkCastralRecord(json: sidecar.castral), record.target == follow.exporter.id,
              record.step == .started else { return stop() }
        follow.id = sidecar.id
        if record.isSettled { return stop() }
        let client: ForkCastralClient
        do { client = try follow.exporter.credentials() } catch { return stop(resting: true) }
        let answer = (try? ForkMeetingExports.blocking { await client.status(record.deposit) }) ?? .failure(.network)
        switch answer {
        case let .success(status):
            let before = record.stage
            record.apply(status, at: Date())
            if let moved = store.writeCastral(record, in: follow.folder, id: sidecar.id) {
                follow.folder = moved
            }
            follow.misses = 0
            followed[path] = follow
            let shown = record
            let folder = follow.folder
            DispatchQueue.main.async { [exports] in
                exports.castralRecords[folder.standardizedFileURL.path] = shown
                if shown.stage == .failed, before != .failed, let config = exports.config(shown.target) {
                    exports.castralNoticed(folder, exports.title(config, .current), .failed)
                }
                // Settled: into its company's folder, when asked.
                if shown.isSettled { exports.fileByCompany(folder) }
            }
            if record.isSettled { return stop() }
        case .failure(.token):
            return stop(resting: true)
        case .failure(.refused(404, _)):
            return stop()
        case .failure:
            follow.misses += 1
            followed[path] = follow
            guard follow.misses < ForkCastralSteps.toleratedFailures else { return stop(resting: true) }
        }
        let elapsed = Date().timeIntervalSince(follow.began)
        guard elapsed < ForkCastralSteps.followBudget(engine: record.engine) else { return stop(resting: true) }
        queue.asyncAfter(deadline: .now() + ForkCastralSteps.pollDelay(sinceStart: elapsed)) { [self] in tick(path) }
    }
}
