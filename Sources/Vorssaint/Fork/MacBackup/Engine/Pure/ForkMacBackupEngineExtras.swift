// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// What the Engine offers beyond the frozen `ForkMacBackupEngineDriving`:
/// the Agent's server start and stop, live bytes, priority, cost,
/// conclusion and failure lists, maintenance schedule, and the Window's
/// versions of another Mac's file. Both engines of the
/// factory conform: `engine as? ForkMacBackupEngineExtras`. Same threading
/// rules as the protocol it refines: callbacks on the engine's callback
/// queue, exactly one completion per call, `.canceled` after a cancel.
protocol ForkMacBackupEngineExtras: ForkMacBackupEngineDriving {
    /// The private server's process (the Agent measures its CPU); nil when
    /// not running or unknown.
    var serverProcessID: Int32? { get }

    /// How hard Kopia may use the Mac: `.background` for scheduled runs.
    /// Takes effect at the next server start and the next CLI call.
    var priority: ForkMacBackupKopiaInvocation.Priority { get set }

    /// Starts the private server on the repository's EXISTING config, no
    /// network needed (the server connects in the background): for an
    /// agent that starts while the storage is out of reach. `connect`
    /// remains the only way to (re)write the config and check the unique ID.
    func startServer(_ repository: ForkMacBackupRepository, credentials: ForkMacBackupCredentials,
                     completion: @escaping (ForkMacBackupEngineResult<Void>) -> Void)

    /// One source's live counters plus the real bytes sent (the task's
    /// « Uploaded Bytes »); nil when the server does not know the source.
    func liveProgress(of source: ForkMacBackupSource,
                      completion: @escaping (ForkMacBackupEngineResult<ForkMacBackupLiveProgress?>) -> Void)

    /// How the run started at `startedAt` ended: its manifest found again
    /// (incomplete ones included), its failures complete (root summary,
    /// folders below when Kopia counted more, and the task's log when
    /// `taskID` is given).
    func conclude(_ source: ForkMacBackupSource, startedAt: Date, taskID: String?, iCloud: ForkMacBackupICloudMode,
                  completion: @escaping (ForkMacBackupEngineResult<ForkMacBackupRunConclusion>) -> Void)

    /// Every failing file of a snapshot (for `errors/<manifest>.json`).
    func failures(of manifest: ForkMacBackupKopia.SnapshotManifest, taskID: String?,
                  completion: @escaping (ForkMacBackupEngineResult<[ForkMacBackupFailure]>) -> Void)

    /// The distinct versions of `relativePath` as `owner` backed it up
    /// (the frozen `versions(of:in:)` is this Mac's own).
    func versions(of relativePath: String, in source: ForkMacBackupSource, owner: ForkMacBackupRepository.Identity,
                  completion: @escaping (ForkMacBackupEngineResult<[ForkMacBackupFileVersion]>) -> Void)

    /// `maintenance info --json`: owner, intervals, next runs.
    func maintenanceInfo(completion: @escaping (ForkMacBackupEngineResult<ForkMacBackupMaintenanceInfo>) -> Void)

    /// Stops the server and forgets the secrets (feature off, agent quit).
    func shutdown(completion: @escaping () -> Void)
}

/// `maintenance info --json`, the parts the Health tab shows.
struct ForkMacBackupMaintenanceInfo: Equatable {
    var owner: String?
    var quickEnabled: Bool
    var quickInterval: TimeInterval?
    var fullEnabled: Bool
    var fullInterval: TimeInterval?
    var nextQuick: Date?
    var nextFull: Date?
    /// The latest end time of any recorded maintenance task, and whether
    /// all of that run's tasks succeeded.
    var lastRun: Date?
    var lastRunSucceeded: Bool?

    /// Whether this Mac (`user@host`) owns the maintenance.
    func isOwned(by identity: ForkMacBackupRepository.Identity) -> Bool {
        owner == identity.description
    }

    private struct Raw: Decodable {
        struct Cycle: Decodable {
            var enabled: Bool?
            var interval: Double?
        }

        struct Run: Decodable {
            var start: String?
            var end: String?
            var success: Bool?
        }

        struct Schedule: Decodable {
            var nextFullMaintenance: String?
            var nextQuickMaintenance: String?
            var runs: [String: [Run]]?
        }

        var owner: String?
        var quick: Cycle?
        var full: Cycle?
        var schedule: Schedule?
    }

    /// Nil unless it reads as Kopia's maintenance info.
    static func decode(_ data: Data) -> ForkMacBackupMaintenanceInfo? {
        guard let raw = ForkMacBackupKopia.decode(Raw.self, from: data), raw.quick != nil || raw.full != nil else {
            return nil
        }
        // Go durations are nanoseconds.
        func seconds(_ value: Double?) -> TimeInterval? { value.map { $0 / 1_000_000_000 } }
        let runs = (raw.schedule?.runs ?? [:]).values.flatMap { $0 }
        let ends = runs.compactMap { run in ForkMacBackupKopia.date(run.end).map { ($0, run.success ?? false) } }
        let last = ends.max { $0.0 < $1.0 }
        // The tasks of one run end within seconds of each other.
        let lastRun = last.map { latest in ends.filter { latest.0.timeIntervalSince($0.0) < 60 } }
        return ForkMacBackupMaintenanceInfo(owner: raw.owner,
                                            quickEnabled: raw.quick?.enabled ?? false,
                                            quickInterval: seconds(raw.quick?.interval),
                                            fullEnabled: raw.full?.enabled ?? false,
                                            fullInterval: seconds(raw.full?.interval),
                                            nextQuick: ForkMacBackupKopia.date(raw.schedule?.nextQuickMaintenance),
                                            nextFull: ForkMacBackupKopia.date(raw.schedule?.nextFullMaintenance),
                                            lastRun: last?.0,
                                            lastRunSucceeded: lastRun.map { $0.allSatisfy(\.1) })
    }
}

/// Source paths as Kopia names them: absolute, no trailing « / » (but the
/// root itself).
enum ForkMacBackupSourcePath {
    static func normalized(_ path: String) -> String {
        var path = path
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return path
    }
}
