// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import CoreServices
import Foundation

/// The changes not protected yet (plan §5.5): an FSEvents stream on the
/// sources, replayed from the event at the start of the last complete
/// snapshot (FSEvents keeps its history on disk, so the count survives a
/// restart). Counts only: no file is opened. Callbacks on `queue`.
final class ForkMacBackupFSEventsWatch {
    /// The summary changed (nil: the count is not known).
    var onChange: ((ForkMacBackupPendingSummary?) -> Void)?

    private let queue: DispatchQueue
    private let fileURL: URL
    private var stream: FSEventStreamRef?
    private var filters: [ForkMacBackupPendingChanges.Filter] = []
    private var tally = ForkMacBackupPendingChanges.Tally()
    private var file: ForkMacBackupPendingChanges.File
    /// Events were dropped, or there is no starting point yet: unknown
    /// until the next complete snapshot.
    private var unknown = false
    private var savedAt: Date = .distantPast

    init(queue: DispatchQueue, fileURL: URL) {
        self.queue = queue
        self.fileURL = fileURL
        file = (try? Data(contentsOf: fileURL)).flatMap(ForkMacBackupPendingChanges.File.decode)
            ?? ForkMacBackupPendingChanges.File(sinceEventID: nil, since: nil, updatedAt: Date())
    }

    deinit {
        stopStream()
    }

    /// nil when not counted.
    var summary: ForkMacBackupPendingSummary? { unknown ? nil : tally.summary }

    /// (Re)starts the stream on `sources`. On `queue`.
    func start(sources: [ForkMacBackupSource], extraRules: [String: [String]] = [:], ignoredPrefixes: [String]) {
        stopStream()
        let home = NSHomeDirectory()
        filters = sources.map {
            ForkMacBackupPendingChanges.Filter(source: $0, extraRules: extraRules[$0.path] ?? [], home: home,
                                               ignoredPrefixes: ignoredPrefixes)
        }
        tally.clear()
        let current = FSEventsGetCurrentEventId()
        let since = ForkMacBackupPendingChanges.replayStart(saved: file.sinceEventID, current: current)
        unknown = since == nil
        guard !sources.isEmpty else { return }
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes
                                             | kFSEventStreamCreateFlagNoDefer)
        let callback: FSEventStreamCallback = { _, info, count, paths, eventFlags, eventIDs in
            guard let info else { return }
            let watch = Unmanaged<ForkMacBackupFSEventsWatch>.fromOpaque(info).takeUnretainedValue()
            let list = Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as? [String] ?? []
            watch.received(count: count, paths: list, flags: eventFlags, ids: eventIDs)
        }
        guard let created = FSEventStreamCreate(kCFAllocatorDefault, callback, &context,
                                                sources.map(\.path) as CFArray,
                                                since ?? FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                                                5.0, flags) else {
            unknown = true
            return
        }
        FSEventStreamSetDispatchQueue(created, queue)
        guard FSEventStreamStart(created) else {
            FSEventStreamInvalidate(created)
            FSEventStreamRelease(created)
            unknown = true
            return
        }
        stream = created
    }

    func stop() {
        stopStream()
        save(force: true)
    }

    private func stopStream() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    /// The event ID at the start of a run: a complete snapshot clears up to it.
    func currentEventID() -> UInt64 { FSEventsGetCurrentEventId() }

    /// A complete snapshot that started at `eventID` protects every change
    /// before it; the count starts again from there.
    func completeSnapshot(startedAt eventID: UInt64, date: Date) {
        tally.reset(upTo: eventID)
        if unknown {
            // A fresh start point: what happened during the run stays unknown
            // (dropped events), so the count starts clean from the run's start.
            tally.clear()
            unknown = false
        }
        file.sinceEventID = eventID
        file.since = date
        save(force: true)
        onChange?(summary)
    }

    private func received(count: Int, paths: [String], flags: UnsafePointer<FSEventStreamEventFlags>,
                          ids: UnsafePointer<FSEventStreamEventId>) {
        let before = summary
        for index in 0..<min(count, paths.count) {
            let flag = Int(flags[index])
            if flag & (kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagUserDropped
                       | kFSEventStreamEventFlagKernelDropped | kFSEventStreamEventFlagEventIdsWrapped
                       | kFSEventStreamEventFlagRootChanged) != 0 {
                unknown = true
                continue
            }
            if flag & kFSEventStreamEventFlagHistoryDone != 0 { continue }
            guard flag & (kFSEventStreamEventFlagItemIsFile | kFSEventStreamEventFlagItemIsSymlink) != 0 else { continue }
            let path = paths[index]
            guard let weight = filters.lazy.compactMap({ $0.weight(of: path) }).first else { continue }
            tally.add(path, weight: weight, eventID: ids[index])
        }
        let after = summary
        if after != before {
            onChange?(after)
            save(force: false)
        }
    }

    private func save(force: Bool) {
        let now = Date()
        guard force || now.timeIntervalSince(savedAt) > 5 * 60 else { return }
        savedAt = now
        let current = summary
        file.total = current?.total
        file.important = current?.important
        file.updatedAt = now
        guard let data = try? ForkMacBackupJSON.encoder.encode(file) else { return }
        PrivateFileStore.write(data, to: fileURL)
    }
}
