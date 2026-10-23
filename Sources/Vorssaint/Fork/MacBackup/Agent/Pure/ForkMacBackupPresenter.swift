// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// The chain as last measured: what the agent's own checks found, turned
/// into one state per profile node (plan §8.1).
struct ForkMacBackupChainProbe: Equatable {
    enum Repository: Equatable {
        case ok(latencyMs: Int?)
        case wrongRepository
        case authentication
        /// The storage did not answer: the first unprobed node after the
        /// last one known good is the broken one.
        case unreachable
    }

    var macReady: Bool?
    var network: Bool?
    var peerOnline: Bool?
    var repository: Repository?
    var checkedAt: Date?

    init(macReady: Bool? = nil, network: Bool? = nil, peerOnline: Bool? = nil, repository: Repository? = nil,
         checkedAt: Date? = nil) {
        self.macReady = macReady
        self.network = network
        self.peerOnline = peerOnline
        self.repository = repository
        self.checkedAt = checkedAt
    }

    /// One state per node, in the chain's order. Once a node is broken, the
    /// ones after it are unknown: nothing behind a break can be seen. A
    /// repository that answered proves every node on the way.
    func statuses(_ nodes: [ForkMacBackupChainNode]) -> [ForkMacBackupPresentation.ChainStatus] {
        var result: [ForkMacBackupPresentation.ChainStatus] = []
        var brokenSeen = false
        var storageBlamed = false
        for node in nodes {
            var state: ForkMacBackupPresentation.NodeState = .unknown
            var latency: Int?
            if !brokenSeen {
                switch node.probe?.kind {
                case .macReadiness?:
                    state = macReady.map { $0 ? .ok : .broken } ?? (repositoryAnswered ? .ok : .unknown)
                case .network?:
                    state = network.map { $0 ? .ok : .broken } ?? (repositoryAnswered ? .ok : .unknown)
                case .tailscalePeer?:
                    state = peerOnline.map { $0 ? .ok : .broken } ?? (repositoryAnswered ? .ok : .unknown)
                case .repositoryIdentity?:
                    switch repository {
                    case .ok?: state = .ok
                    case .wrongRepository?, .authentication?: state = .broken
                    case .unreachable?: state = storageBlamed ? .unknown : .broken
                    case nil: state = .unknown
                    }
                case .nameResolution?, .s3Endpoint?, .minioHealth?, .sshReadOnly?, nil:
                    switch repository {
                    case .ok(let ms)?:
                        state = .ok
                        if node.kind == .s3 { latency = ms }
                    case .wrongRepository?, .authentication?:
                        state = .ok
                    case .unreachable?:
                        if node.kind == .mac || node.kind == .network {
                            state = .ok
                        } else if !storageBlamed {
                            state = .broken
                            storageBlamed = true
                        }
                    case nil:
                        state = .unknown
                    }
                }
            }
            if state == .broken { brokenSeen = true }
            if let ms = latency, ms > 3_000, state == .ok { state = .slow }
            result.append(ForkMacBackupPresentation.ChainStatus(id: node.id, kind: node.kind, title: node.title,
                                                                state: state, latencyMs: latency,
                                                                checkedAt: state == .unknown ? nil : checkedAt))
        }
        return result
    }

    private var repositoryAnswered: Bool {
        switch repository {
        case .ok?, .wrongRepository?, .authentication?: return true
        case .unreachable?, nil: return false
        }
    }

    /// The node to name in a « chain broken » banner.
    func brokenNodeID(_ nodes: [ForkMacBackupChainNode]) -> String? {
        statuses(nodes).first { $0.state == .broken }?.id
    }
}

/// One battery reading, for the cost of a run on battery.
struct ForkMacBackupBatterySample: Equatable {
    var date: Date
    var percent: Double
    var onAC: Bool
}

/// What backups cost, measured (plan §3.9.1), and the rhythm Automatic keeps.
enum ForkMacBackupCostSupport {
    /// Battery points a run cost beyond the slope of the 30 minutes before
    /// it; nil on AC (or charging at any moment of the run).
    static func batteryDrop(samples: [ForkMacBackupBatterySample], start: Date, end: Date,
                            startPercent: Double?, endPercent: Double?) -> Double? {
        guard let startPercent, let endPercent, end > start else { return nil }
        let during = samples.filter { $0.date >= start && $0.date <= end }
        guard !during.contains(where: \.onAC) else { return nil }
        let window = ForkMacBackupAgentTuning.batterySlopeWindow
        let before = samples.filter { $0.date >= start.addingTimeInterval(-window) && $0.date <= start }
        var slopePerSecond = 0.0
        if let first = before.first, let last = before.last, !before.contains(where: \.onAC),
           last.date.timeIntervalSince(first.date) >= 5 * 60 {
            slopePerSecond = (first.percent - last.percent) / last.date.timeIntervalSince(first.date)
        }
        let expected = max(0, slopePerSecond) * end.timeIntervalSince(start)
        return max(0, (startPercent - endPercent) - expected)
    }

    /// The average of the last backups that left a snapshot.
    static func cost(_ runs: [ForkMacBackupRunRecord],
                     samples: Int = ForkMacBackupAgentTuning.costSamples) -> ForkMacBackupPresentation.Cost? {
        let backups = runs.filter { $0.kind == .backup && ($0.outcome == .complete || $0.outcome == .partial) }
            .compactMap { run -> (ForkMacBackupRunRecord, TimeInterval)? in run.duration.map { (run, $0) } }
            .suffix(samples)
        guard !backups.isEmpty else { return nil }
        let count = Double(backups.count)
        let duration = backups.reduce(0) { $0 + $1.1 } / count
        let sent = backups.reduce(Int64(0)) { $0 + $1.0.bytesSent } / Int64(backups.count)
        let drops = backups.compactMap { $0.0.batteryDrop }
        let battery = drops.isEmpty ? nil : drops.reduce(0, +) / Double(drops.count)
        return ForkMacBackupPresentation.Cost(averageDuration: duration, averageBatteryDrop: battery, averageSent: sent,
                                              samples: backups.count)
    }

    /// The interval Automatic currently keeps: the median gap between the
    /// backups of the last week; nil before three of them.
    static func automaticInterval(_ runs: [ForkMacBackupRunRecord], now: Date) -> TimeInterval? {
        let starts = runs.filter { $0.kind == .backup && ($0.outcome == .complete || $0.outcome == .partial) }
            .map(\.start).filter { now.timeIntervalSince($0) <= 7 * 86_400 }.sorted()
        guard starts.count >= 3 else { return nil }
        let gaps = zip(starts.dropFirst(), starts).map { $0.timeIntervalSince($1) }.sorted()
        let middle = gaps.count / 2
        return gaps.count % 2 == 1 ? gaps[middle] : (gaps[middle - 1] + gaps[middle]) / 2
    }
}

/// The ONE presentation (plan §3.8): the machine's state and the agent's
/// knowledge, put together for every view.
enum ForkMacBackupPresenter {
    struct Context {
        var settings: ForkMacBackupAgentSettings
        var proofs: ForkMacBackupProofStore
        var chain: ForkMacBackupChainProbe
        var pendingChanges: Int?
        var runs: [ForkMacBackupRunRecord]
        var repositoryBytes: Int64?
        var repositoryMeasuredAt: Date?
        /// The pre-scan's walk, while one runs.
        var preparation: ForkMacBackupPresentation.Preparation?

        init(settings: ForkMacBackupAgentSettings, proofs: ForkMacBackupProofStore = ForkMacBackupProofStore(),
             chain: ForkMacBackupChainProbe = ForkMacBackupChainProbe(), pendingChanges: Int? = nil,
             runs: [ForkMacBackupRunRecord] = [], repositoryBytes: Int64? = nil, repositoryMeasuredAt: Date? = nil,
             preparation: ForkMacBackupPresentation.Preparation? = nil) {
            self.preparation = preparation
            self.settings = settings
            self.proofs = proofs
            self.chain = chain
            self.pendingChanges = pendingChanges
            self.runs = runs
            self.repositoryBytes = repositoryBytes
            self.repositoryMeasuredAt = repositoryMeasuredAt
        }
    }

    /// The snapshots of `path` this Mac's runs made since the proofs were
    /// last reconciled, newest first. A run's snapshot is « Dernière » even
    /// before the proofs hold it (they may lag: read at start, emptied by
    /// a list asked before the run ended). Older ones are the proofs' word
    /// alone (retention, another repository).
    static func recentProofs(of path: String, runs: [ForkMacBackupRunRecord],
                             after: Date?) -> [ForkMacBackupSnapshotProof] {
        let path = ForkMacBackupSourcePath.normalized(path)
        let floor = after ?? .distantPast
        return runs.filter { $0.kind == .backup && ($0.outcome == .complete || $0.outcome == .partial) }
            .flatMap(\.proofs)
            .filter { $0.incomplete == nil && $0.endTime > floor && ForkMacBackupSourcePath.normalized($0.sourcePath) == path }
            .sorted { $0.endTime > $1.endTime }
    }

    private static func newest(_ a: ForkMacBackupSnapshotProof?, _ b: ForkMacBackupSnapshotProof?) -> ForkMacBackupSnapshotProof? {
        guard let a else { return b }
        guard let b else { return a }
        return b.endTime > a.endTime ? b : a
    }

    static func presentation(_ machine: ForkMacBackupMachine, context: Context, now: Date) -> ForkMacBackupPresentation {
        let settings = context.settings
        let phase = machine.phase(now: now)
        let lastRunFailed: Bool = {
            if case .failed = machine.finished?.result { return true }
            return false
        }()
        let sources = settings.sources.map { source -> ForkMacBackupPresentation.SourceStatus in
            let ran = recentProofs(of: source.path, runs: context.runs, after: context.proofs.reconciledAt)
            let last = newest(context.proofs.last(of: source.path), ran.first)
            let complete = newest(context.proofs.lastComplete(of: source.path),
                                  ran.first { !$0.isPartial && $0.level >= .complete })
            var state: ForkMacBackupPresentation.SourceState
            if let live = machine.sourceState(source.path) {
                state = live
            } else if case .waiting = phase {
                state = .waiting
            } else if lastRunFailed {
                state = .failed
            } else if let last {
                state = last.isPartial || last.level < .complete ? .partial : .done
            } else {
                state = .idle
            }
            if case .off = phase { state = .idle }
            return ForkMacBackupPresentation.SourceStatus(path: source.path, state: state,
                                                          last: last.map(ForkMacBackupProofStore.summary),
                                                          lastComplete: complete.map(ForkMacBackupProofStore.summary))
        }
        var rhythm = settings.rhythm
        if case .automatic = rhythm {
            rhythm = .automatic(about: ForkMacBackupCostSupport.automaticInterval(context.runs, now: now))
        }
        let lastSent = context.runs.last { $0.kind == .backup && $0.outcome != .nothingToDo }?.bytesSent
        let protectedSizes = settings.sources.compactMap { context.proofs.last(of: $0.path)?.diskBytes }.filter { $0 > 0 }
        let capacity = ForkMacBackupPresentation.Capacity(
            protectedBytes: protectedSizes.isEmpty ? nil : protectedSizes.reduce(0, +),
            lastSentBytes: lastSent, repositoryBytes: context.repositoryBytes, nasFreeBytes: nil,
            measuredAt: context.repositoryMeasuredAt ?? context.proofs.lastBackup(paths: settings.sources.map(\.path)))
        let nextRun: Date? = {
            switch phase {
            case .ready(let next): return next
            case .waiting(_, let until): return until
            case .paused(let until): return until
            case .finished: return machine.next ?? machine.retryAt
            default: return nil
            }
        }()
        var lastError = machine.lastError
        if lastError?.cause == .chainBroken, lastError?.nodeID == nil {
            lastError?.nodeID = context.chain.brokenNodeID(settings.chain)
        }
        let enabled: Bool = { if case .off = phase { return false }; return true }()
        return ForkMacBackupPresentation(
            phase: phase,
            progress: machine.progress(now: now),
            preparation: phase == .preparing ? context.preparation : nil,
            sources: enabled ? sources : [],
            pendingChanges: enabled ? context.pendingChanges : nil,
            chain: enabled ? context.chain.statuses(settings.chain) : [],
            nextRun: enabled ? nextRun : nil,
            rhythm: rhythm,
            capacity: enabled ? capacity : ForkMacBackupPresentation.Capacity(),
            cost: enabled ? ForkMacBackupCostSupport.cost(context.runs) : nil,
            lastError: enabled ? lastError : nil,
            slowDown: machine.slowDown,
            updatedAt: now)
    }
}
