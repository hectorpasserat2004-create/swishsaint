// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// What the window reads besides the live state: the agent's records
/// (`runs.jsonl`, `slots.jsonl`, `capacity.jsonl`, `proofs.json`) and the
/// machine's setup (sources, repository, profile). Read off the main
/// thread, handed to the main thread whole.
struct ForkMacBackupWindowLedger: Equatable {
    var runs: [ForkMacBackupRunRecord] = []
    var slots: [ForkMacBackupSlotRecord] = []
    var capacity: [ForkMacBackupCapacitySample] = []
    /// By manifest ID, the best proof known.
    var proofs: [String: ForkMacBackupSnapshotProof] = [:]
    var sources: [ForkMacBackupSource] = []
    var repository: ForkMacBackupRepository?
    var profile: ForkMacBackupProfile?
    var iCloud: ForkMacBackupICloudMode = .fallback
    var engineVersion: String?

    static let empty = ForkMacBackupWindowLedger()

    /// The run that saved `manifestID`, for what it sent and how long it took.
    func run(saving manifestID: String) -> ForkMacBackupRunRecord? {
        runs.last { $0.kind == .backup && $0.proofs.contains { $0.manifestID == manifestID } }
    }

    /// Keeps the higher proof of two for the same snapshot; at the same
    /// level, the later one (`rhs`: the agent's, with its complete lists).
    static func better(_ lhs: ForkMacBackupSnapshotProof?, _ rhs: ForkMacBackupSnapshotProof) -> ForkMacBackupSnapshotProof {
        guard let lhs else { return rhs }
        return rhs.level >= lhs.level ? rhs : lhs
    }
}

/// Where the window gets its records: the disk in the app, a fake in the
/// renders and the Developer demo.
protocol ForkMacBackupWindowLedgerReading: AnyObject {
    /// Reads everything; `completion` on the main queue.
    func load(completion: @escaping (ForkMacBackupWindowLedger) -> Void)
    /// The complete failure list of one snapshot (`errors/<id>.json`), when
    /// the agent wrote one; `completion` on the main queue.
    func failures(manifestID: String, completion: @escaping ([ForkMacBackupFailure]?) -> Void)
    /// Adds a restore to the history (`runs.jsonl`).
    func append(_ run: ForkMacBackupRunRecord)
}

/// The app's reader: `ForkMacBackupPaths` on a utility queue, the
/// machine's keys from `UserDefaults` read on the main thread first.
final class ForkMacBackupWindowDiskLedger: ForkMacBackupWindowLedgerReading {
    let paths: ForkMacBackupPaths
    private let defaults: UserDefaults
    private let queue = DispatchQueue(label: "fork.macbackup.window.ledger", qos: .utility)

    init(paths: ForkMacBackupPaths, defaults: UserDefaults = .standard) {
        self.paths = paths
        self.defaults = defaults
    }

    func load(completion: @escaping (ForkMacBackupWindowLedger) -> Void) {
        var base = ForkMacBackupWindowLedger()
        base.sources = decode([ForkMacBackupSource].self, key: ForkDefaultsKey.macBackupSources) ?? []
        base.repository = decode(ForkMacBackupRepository.self, key: ForkDefaultsKey.macBackupRepository)
        base.profile = defaults.data(forKey: ForkDefaultsKey.macBackupProfile).flatMap(ForkMacBackupProfile.decode)
            ?? defaults.string(forKey: ForkDefaultsKey.macBackupProfile).flatMap { ForkMacBackupProfile.decode(Data($0.utf8)) }
        base.iCloud = defaults.string(forKey: ForkDefaultsKey.macBackupICloudMode)
            .flatMap(ForkMacBackupICloudMode.init(rawValue:)) ?? .fallback
        base.engineVersion = defaults.string(forKey: ForkDefaultsKey.macBackupEngineVersion)
        let paths = self.paths
        queue.async {
            var ledger = base
            ledger.runs = Self.lines(ForkMacBackupRunRecord.self, at: paths.runs)
            ledger.slots = Self.lines(ForkMacBackupSlotRecord.self, at: paths.slots)
            ledger.capacity = Self.lines(ForkMacBackupCapacitySample.self, at: paths.capacity)
            var proofs: [String: ForkMacBackupSnapshotProof] = [:]
            for proof in ledger.runs.flatMap(\.proofs) + Self.proofs(at: paths.proofs) {
                proofs[proof.manifestID] = ForkMacBackupWindowLedger.better(proofs[proof.manifestID], proof)
            }
            ledger.proofs = proofs
            DispatchQueue.main.async { completion(ledger) }
        }
    }

    /// `errors/<manifest>.json`: the agent's `[ForkMacBackupFailure]`.
    func failures(manifestID: String, completion: @escaping ([ForkMacBackupFailure]?) -> Void) {
        let url = paths.errorsFile(manifestID: manifestID)
        queue.async {
            let list = (try? Data(contentsOf: url)).flatMap {
                try? ForkMacBackupJSON.decoder.decode([ForkMacBackupFailure].self, from: $0)
            }
            DispatchQueue.main.async { completion(list) }
        }
    }

    /// The same record and the same single `O_APPEND` write as the agent's.
    func append(_ run: ForkMacBackupRunRecord) {
        let url = paths.runs
        let root = paths.root
        queue.async {
            guard PrivateFileStore.createDirectory(at: root, container: PrivateFileStore.containerURL) else { return }
            ForkMacBackupJSON.append(run, to: url)
        }
    }

    private func decode<Value: Decodable>(_ type: Value.Type, key: String) -> Value? {
        if let data = defaults.data(forKey: key) { return try? ForkMacBackupJSON.decoder.decode(type, from: data) }
        if let text = defaults.string(forKey: key) { return try? ForkMacBackupJSON.decoder.decode(type, from: Data(text.utf8)) }
        return nil
    }

    private static func lines<Value: Decodable>(_ type: Value.Type, at url: URL) -> [Value] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return ForkMacBackupJSON.lines(type, from: data)
    }

    /// `proofs.json`, the agent's `ForkMacBackupProofStore`.
    private static func proofs(at url: URL) -> [ForkMacBackupSnapshotProof] {
        guard let data = try? Data(contentsOf: url), let store = ForkMacBackupProofStore.decode(data) else { return [] }
        return Array(store.proofs.values)
    }
}
