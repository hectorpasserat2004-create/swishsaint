// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation
import os

/// Glance Focus: the profiles on disk, in
/// `~/Library/Application Support/<bundle id>/Glance/profiles.json` (plan
/// §8.6). The bundle id tells the release from the Developer build, so each
/// keeps its own. Owner-only through `PrivateFileStore` (folder 0700, file
/// 0600, atomic writes), and outside the settings backup: the splits and the
/// calibration only fit this Mac's desk.
///
/// Main thread for every call; the disk is only touched on `queue`, in the
/// order the calls came.
final class ForkGlanceStore {
    static let shared = ForkGlanceStore()

    /// The last list loaded or saved.
    private(set) var profiles: [ForkGlanceProfile] = []

    private let file: URL?
    private let queue = DispatchQueue(label: "fork.glance.store", qos: .utility)
    private let log = Logger(subsystem: "fork.glance", category: "store")
    /// Bumped by each save and delete: a load that lands after one is stale.
    private var generation = 0

    /// - Parameter directory: where `profiles.json` goes; the app's own
    ///   folder when nil. Outside a real bundle there is none, and nothing is
    ///   kept.
    init(directory: URL? = PrivateFileStore.containerURL?.appendingPathComponent("Glance", isDirectory: true)) {
        file = directory?.appendingPathComponent("profiles.json", isDirectory: false)
    }

    /// Reads the file off the main thread, then calls `done` on it. A file
    /// missing or unreadable gives an empty list; a save made meanwhile wins
    /// over what was read.
    func load(_ done: @escaping ([ForkGlanceProfile]) -> Void) {
        precondition(Thread.isMainThread)
        let started = generation
        guard let file else {
            DispatchQueue.main.async { done(self.profiles) }
            return
        }
        let log = self.log
        queue.async {
            var read: [ForkGlanceProfile] = []
            if let data = try? Data(contentsOf: file) {
                read = ForkGlanceProfiles.decode(data)
                if read.isEmpty, !data.isEmpty { log.error("profiles unreadable, starting empty") }
            }
            DispatchQueue.main.async {
                if self.generation == started { self.profiles = read }
                done(self.profiles)
            }
        }
    }

    /// Keeps `profiles` as given, in this order; bounding the list is
    /// `ForkGlanceProfiles.upserting`'s.
    func save(_ profiles: [ForkGlanceProfile]) {
        precondition(Thread.isMainThread)
        generation += 1
        self.profiles = profiles
        guard let file else { return }
        let log = self.log
        queue.async {
            let data = ForkGlanceProfiles.encode(profiles)
            guard PrivateFileStore.createDirectory(at: file.deletingLastPathComponent()),
                  PrivateFileStore.write(data, to: file) else {
                log.error("profiles not written")
                return
            }
        }
    }

    /// Every profile, from memory and from disk.
    func deleteAll() {
        precondition(Thread.isMainThread)
        generation += 1
        profiles = []
        guard let file else { return }
        let log = self.log
        queue.async {
            guard FileManager.default.fileExists(atPath: file.path) else { return }
            do {
                try FileManager.default.removeItem(at: file)
            } catch {
                log.error("profiles not deleted: \(error.localizedDescription, privacy: .private)")
            }
        }
    }
}
