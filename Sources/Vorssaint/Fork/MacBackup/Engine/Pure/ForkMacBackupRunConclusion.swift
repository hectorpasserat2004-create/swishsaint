// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// How a backup run ended, read from what Kopia left (plan §3.8): the
/// manifest is looked up again, never inferred from an exit code or a task
/// status (the server marks a snapshot task SUCCESS even with file errors
/// and even when canceled, SPIKES §2.5).
struct ForkMacBackupRunConclusion: Equatable {
    enum Outcome: String, Equatable {
        /// A manifest without errors (cloud-only files in `.local` mode do
        /// not count).
        case complete
        /// A manifest with named failures.
        case partial
        /// Canceled with a checkpoint: the next run resumes (« incomplete:
        /// canceled »).
        case canceled
        /// No manifest of this run.
        case failed
    }

    var outcome: Outcome
    /// The run's manifest; nil when it failed.
    var manifest: ForkMacBackupKopia.SnapshotManifest?
    /// The proof of that manifest, failures complete.
    var proof: ForkMacBackupSnapshotProof?

    /// The latest manifest of `sourcePath` started at or after `startedAt`
    /// (less `slack`: the server stamps its own start a moment after the
    /// trigger, the agent's clock may round), incomplete ones included.
    static func manifest(of sourcePath: String, startedAt: Date, in manifests: [ForkMacBackupKopia.SnapshotManifest],
                         slack: TimeInterval = 5) -> ForkMacBackupKopia.SnapshotManifest? {
        manifests
            .filter { $0.source?.path == sourcePath }
            .filter { ($0.startDate ?? .distantPast) >= startedAt.addingTimeInterval(-slack) }
            .max { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
    }

    /// Concludes from the manifests listed after the run, and every failure
    /// named anywhere (`failures`, completed by `ForkMacBackupFailureList`).
    static func conclude(sourcePath: String, startedAt: Date, manifests: [ForkMacBackupKopia.SnapshotManifest],
                         failures: [ForkMacBackupFailure]?, iCloud: ForkMacBackupICloudMode) -> ForkMacBackupRunConclusion {
        guard let manifest = manifest(of: sourcePath, startedAt: startedAt, in: manifests) else {
            return ForkMacBackupRunConclusion(outcome: .failed, manifest: nil, proof: nil)
        }
        var proof = ForkMacBackupSnapshotProof(manifest: manifest, iCloud: iCloud)
        if let failures {
            let real = failures.filter { $0.cause.countsAsError(iCloud: iCloud) }
            let cloud = failures.filter { !$0.cause.countsAsError(iCloud: iCloud) }.map(\.path)
            let counted = max(Int(manifest.errorCount),
                              Int((manifest.rootEntry?.summ?.numFailed ?? 0) + (manifest.rootEntry?.summ?.numIgnoredErrors ?? 0)))
            proof.failures = real
            proof.cloudOnly = cloud
            proof.unnamedFailureCount = max(0, counted - failures.count)
            let complete = real.isEmpty && proof.unnamedFailureCount == 0 && manifest.incomplete == nil
            proof.level = complete ? .complete : .present
        }
        let outcome: Outcome
        if manifest.incomplete != nil {
            outcome = .canceled
        } else if proof.isPartial {
            outcome = .partial
        } else {
            outcome = .complete
        }
        return ForkMacBackupRunConclusion(outcome: outcome, manifest: manifest, proof: proof)
    }
}

/// A snapshot's COMPLETE list of failing files (plan §3.5), from every
/// place Kopia names them: the root summary (uncapped in v0.23.1, SPIKES §5),
/// the summaries of the folders below, and the server task's log (one
/// `snapshotted file` entry per failure). Paths are relative to the source,
/// each named once, classified by Core's classifier.
enum ForkMacBackupFailureList {
    /// The task log's entries (`GET /api/v1/tasks/{id}/logs`).
    struct TaskLogs: Decodable, Equatable {
        struct Entry: Decodable, Equatable {
            var msg: String?
            var path: String?
            var error: String?
        }

        var logs: [Entry]
    }

    /// Summaries' errors with the folder they were read in, relative to the
    /// source (« » for the root): every error path inside a folder's
    /// directory manifest (its `summary` and its entries' `summ`) is
    /// relative to that folder (`flat/bad01.txt` in the root's listing,
    /// `deeper/bad1.txt` in `nested`'s).
    static func merge(summaries: [(folder: String, errors: [ForkMacBackupKopia.EntryError])],
                      taskLogs: TaskLogs?) -> [ForkMacBackupFailure] {
        var seen = Set<String>()
        var failures: [ForkMacBackupFailure] = []
        func add(_ path: String, _ message: String) {
            let normalized = normalize(path)
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { return }
            failures.append(ForkMacBackupFailure(path: normalized, message: message))
        }
        for summary in summaries {
            for error in summary.errors {
                guard let path = error.path, !path.isEmpty else { continue }
                let full = summary.folder.isEmpty ? path : summary.folder + "/" + path
                add(full, error.error ?? "")
            }
        }
        for entry in taskLogs?.logs ?? [] where entry.msg == "snapshotted file" {
            guard let path = entry.path, let error = entry.error, !error.isEmpty else { continue }
            add(path, error)
        }
        return failures
    }

    /// `./a//b/` → `a/b`.
    static func normalize(_ path: String) -> String {
        path.split(separator: "/").filter { $0 != "." && !$0.isEmpty }.joined(separator: "/")
    }

    /// Whether the folders below must be walked: Kopia counted more
    /// failures than the root names (an older Kopia capped them at ten per
    /// folder).
    static func needsWalk(_ manifest: ForkMacBackupKopia.SnapshotManifest) -> Bool {
        guard let summary = manifest.rootEntry?.summ else { return false }
        let counted = max(Int(manifest.errorCount), Int((summary.numFailed ?? 0) + (summary.numIgnoredErrors ?? 0)))
        return counted > summary.errors.count
    }
}

/// The live state of one source while it uploads, with the real bytes
/// sent: `upload.uploadedBytes` stays 0 in v0.23.1, the task's
/// « Uploaded Bytes » counter does not (SPIKES §2.5).
struct ForkMacBackupLiveProgress: Equatable {
    var status: ForkMacBackupKopia.SourceStatus
    /// nil when the task could not be read.
    var uploadedBytes: Int64?
    /// The task's own « Hashed Bytes »/« Cached Bytes »… for the record.
    var task: ForkMacBackupKopia.TaskInfo?

    var isUploading: Bool { status.isUploading }

    /// « Uploaded Bytes » of a snapshot task.
    static func uploadedBytes(of task: ForkMacBackupKopia.TaskInfo) -> Int64? {
        task.counter("Uploaded Bytes")
    }
}
