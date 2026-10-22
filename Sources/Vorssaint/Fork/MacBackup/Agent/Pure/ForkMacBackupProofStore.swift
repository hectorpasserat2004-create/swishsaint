// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// `MacBackup/proofs.json` (owned by the Agent, read by anyone): what is
/// proven about each snapshot of this Mac's sources that is still in the
/// repository. Reconciled with `snapshot list` at every start and after
/// every run, so a snapshot removed by the retention is never counted
/// (plan §3.5); raised by verifications and restore tests (§5.1).
struct ForkMacBackupProofStore: Codable, Equatable {
    static let formatVersion = 1

    var formatVersion: Int
    var updatedAt: Date
    /// By manifest ID.
    var proofs: [String: ForkMacBackupSnapshotProof]

    init(proofs: [String: ForkMacBackupSnapshotProof] = [:], updatedAt: Date = .distantPast) {
        formatVersion = Self.formatVersion
        self.updatedAt = updatedAt
        self.proofs = proofs
    }

    static func decode(_ data: Data) -> ForkMacBackupProofStore? {
        guard let store = try? ForkMacBackupJSON.decoder.decode(ForkMacBackupProofStore.self, from: data),
              store.formatVersion <= formatVersion else { return nil }
        return store
    }

    func encoded() -> Data? { try? ForkMacBackupJSON.encoder.encode(self) }

    // MARK: Reading

    /// A source's snapshots, newest first.
    func snapshots(of path: String) -> [ForkMacBackupSnapshotProof] {
        proofs.values.filter { $0.sourcePath == path }.sorted { $0.endTime > $1.endTime }
    }

    /// The newest snapshot of `path`, partial or not.
    func last(of path: String) -> ForkMacBackupSnapshotProof? {
        snapshots(of: path).first { $0.incomplete == nil }
    }

    /// The newest snapshot of `path` without a read error.
    func lastComplete(of path: String) -> ForkMacBackupSnapshotProof? {
        snapshots(of: path).first { $0.incomplete == nil && $0.level >= .complete }
    }

    /// The end of the newest snapshot over `paths` (the planner's « last backup »).
    func lastBackup(paths: [String]) -> Date? {
        paths.compactMap { last(of: $0)?.endTime }.max()
    }

    static func summary(_ proof: ForkMacBackupSnapshotProof) -> ForkMacBackupPresentation.SnapshotSummary {
        ForkMacBackupPresentation.SnapshotSummary(manifestID: proof.manifestID, date: proof.endTime, level: proof.level,
                                                  failures: proof.failureCount, bytes: proof.bytes)
    }

    // MARK: Writing

    /// A run's proofs, as concluded.
    mutating func record(_ new: [ForkMacBackupSnapshotProof], now: Date) {
        for proof in new { proofs[proof.manifestID] = merged(proof) }
        updatedAt = now
    }

    /// `snapshot list` says what still exists: new manifests are added,
    /// those of `paths` that are gone are dropped, the levels already
    /// raised are kept. Other sources (another Mac, another account) are
    /// left out by the caller's filter.
    mutating func reconcile(with manifests: [ForkMacBackupKopia.SnapshotManifest], paths: [String],
                            identity: ForkMacBackupRepository.Identity?, iCloud: ForkMacBackupICloudMode, now: Date) {
        let mine = manifests.filter { manifest in
            guard let path = manifest.source?.path, paths.contains(path) else { return false }
            guard let identity else { return true }
            let host = manifest.source?.host ?? identity.hostName
            let user = manifest.source?.userName ?? identity.userName
            return host == identity.hostName && user == identity.userName
        }
        let present = Set(mine.map(\.id))
        proofs = proofs.filter { !paths.contains($0.value.sourcePath) || present.contains($0.key) }
        for manifest in mine {
            proofs[manifest.id] = merged(ForkMacBackupSnapshotProof(manifest: manifest, iCloud: iCloud))
        }
        updatedAt = now
    }

    /// A verification or a restore test succeeded on `manifestIDs`. Only
    /// complete snapshots climb: a partial one stays « present ».
    mutating func raise(_ manifestIDs: [String], to level: ForkMacBackupProofLevel, at date: Date,
                        percent: Double? = nil) {
        for id in manifestIDs {
            guard var proof = proofs[id], proof.level >= .complete else { continue }
            proof.level = max(proof.level, level)
            switch level {
            case .contentVerified:
                proof.verifiedAt = date
                proof.verifiedPercent = percent
            case .restoreTested:
                proof.restoreTestedAt = date
            case .present, .complete:
                break
            }
            proofs[id] = proof
        }
        updatedAt = date
    }

    /// The new reading of a snapshot, keeping what a verification proved.
    private func merged(_ proof: ForkMacBackupSnapshotProof) -> ForkMacBackupSnapshotProof {
        guard let old = proofs[proof.manifestID] else { return proof }
        var merged = proof
        if proof.level >= .complete { merged.level = max(proof.level, old.level) }
        merged.verifiedAt = old.verifiedAt
        merged.verifiedPercent = old.verifiedPercent
        merged.restoreTestedAt = old.restoreTestedAt
        return merged
    }
}
