// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// The live figures of a run, and the honesty rules of the presentation:
/// the rate is a 10 s sliding mean, the ETA appears only once Kopia's
/// estimate has held for 30 s.
struct ForkMacBackupProgressTracker: Equatable {
    struct Sample: Equatable {
        var date: Date
        var bytes: Int64
    }

    private(set) var samples: [Sample] = []
    private(set) var estimate: Int64?
    private(set) var estimateSince: Date?

    mutating func add(done: Int64, estimate newEstimate: Int64?, at date: Date) {
        samples.append(Sample(date: date, bytes: done))
        samples.removeAll { date.timeIntervalSince($0.date) > ForkMacBackupAgentTuning.rateWindow }
        guard let newEstimate, newEstimate > 0 else {
            estimate = nil
            estimateSince = nil
            return
        }
        if let estimate, Double(abs(newEstimate - estimate)) <= Double(estimate) * ForkMacBackupAgentTuning.estimateTolerance {
            return
        }
        estimate = newEstimate
        estimateSince = date
    }

    /// Bytes per second over the window; nil before two samples 2 s apart.
    func rate() -> Double? {
        guard let first = samples.first, let last = samples.last else { return nil }
        let elapsed = last.date.timeIntervalSince(first.date)
        guard elapsed >= 2 else { return nil }
        return max(0, Double(last.bytes - first.bytes) / elapsed)
    }

    func eta(now: Date, done: Int64, total: Int64?) -> TimeInterval? {
        guard let total, let since = estimateSince, now.timeIntervalSince(since) >= ForkMacBackupAgentTuning.etaStableFor,
              let rate = rate(), rate > 0 else { return nil }
        return max(0, Double(total - done) / rate)
    }
}

/// The run's state machine (plan §3.8). Pure: events in, actions out; the
/// runner does the I/O and feeds the results back. One run at a time, a
/// verification never during a backup.
struct ForkMacBackupMachine {
    enum Step: Equatable {
        case checkingChain
        case preparing
        case starting
        case scanning
        case uploading
        case concluding
    }

    struct Counters: Equatable {
        var done: Int64 = 0
        var total: Int64?
        var uploaded: Int64 = 0
        var files: Int64 = 0
        var filesTotal: Int64?
        var errors: Int = 0
        var path: String?

        /// What moves while Kopia works: a change is progress (the watchdog).
        var signature: Int64 { done &+ uploaded &+ files }
    }

    struct SourceRun: Equatable {
        var source: ForkMacBackupSource
        var startedAt: Date?
        var sawUpload = false
        var listed = false
        var proof: ForkMacBackupSnapshotProof?
        var failure: ForkMacBackupRunFailure?
        var counters = Counters()
        /// The server's snapshot task (its « Uploaded Bytes », its log).
        var taskID: String?
    }

    struct Run: Equatable {
        var id: UUID
        var trigger: ForkMacBackupTrigger
        var due: Date?
        var start: Date
        var step: Step
        var sources: [SourceRun]
        var index = 0
        var tracker = ForkMacBackupProgressTracker()
        var lastProgressAt: Date
        var signature: Int64 = 0
        var stopping: ForkMacBackupStopReason?
        var stopRequestedAt: Date?
        var bytesSent: Int64 = 0
        var abort: ForkMacBackupRunFailure?
        var abortMessage: String?
        var failedNode: String?
        var pollFailures = 0

        var current: SourceRun? { sources.indices.contains(index) ? sources[index] : nil }
    }

    struct VerifyRun: Equatable {
        var level: ForkMacBackupVerifyLevel
        var start: Date
        var trigger: ForkMacBackupTrigger
        var progress = ForkMacBackupVerifyProgress(checked: 0, total: nil)
        var canceled = false
    }

    enum PolicyOutcome: Equatable {
        case matched
        case mismatched
        case failed(ForkMacBackupEngineError)
    }

    /// How a run ended, for the runner (runs.jsonl, slots, proofs, pending).
    struct Summary: Equatable {
        var id: UUID
        var trigger: ForkMacBackupTrigger
        var due: Date?
        var start: Date
        var end: Date
        /// nil for a run stopped before its end (pause, meeting, person…).
        var result: ForkMacBackupRunResult?
        var outcome: ForkMacBackupRunRecord.Outcome
        var failure: ForkMacBackupRunFailure?
        var stopReason: ForkMacBackupStopReason?
        var proofs: [ForkMacBackupSnapshotProof]
        var bytesSent: Int64
        var message: String?
    }

    enum Event: Equatable {
        case configure(ForkMacBackupAgentSettings)
        /// The planner's decision, applied while no operation runs.
        case decision(ForkMacBackupPlanner.Decision)
        /// `nodeID`: the chain node found broken.
        case chainChecked(ForkMacBackupEngineError?, nodeID: String?)
        case policyApplied(ForkMacBackupSource, PolicyOutcome)
        case snapshotTriggered(ForkMacBackupSource, ForkMacBackupEngineError?)
        case progress(ForkMacBackupKopia.SourcesResponse)
        /// The current source's live counters (`liveProgress`), with the
        /// bytes really sent and the server's task; nil: unknown to the server.
        case live(ForkMacBackupKopia.SourceStatus?, uploaded: Int64?, taskID: String?)
        case progressFailed(ForkMacBackupEngineError)
        /// The engine without `conclude`: the manifests listed after the run.
        case listed(ForkMacBackupSource, ForkMacBackupEngineResult<[ForkMacBackupKopia.SnapshotManifest]>)
        /// The engine's conclusion (manifest found again, failures complete).
        case concluded(ForkMacBackupSource, ForkMacBackupEngineResult<ForkMacBackupRunConclusion>)
        /// The upload limit wanted now (planner); nil: none.
        case limit(Int64?)
        /// Whether the keep-awake policy allows the assertion now.
        case keepAwakeAllowed(Bool)
        case command(ForkMacBackupCommand, origin: ForkMacBackupTrigger)
        /// A meeting in « pause » mode began.
        case meetingStarted
        /// The update, the switch, the agent's end.
        case stop(ForkMacBackupStopReason)
        case verifyProgress(ForkMacBackupVerifyProgress)
        case verifyFinished(ForkMacBackupEngineResult<ForkMacBackupVerifyReport>)
        /// The Mac woke: the time asleep is no stall (the watchdog starts again).
        case woke
        case tick
    }

    enum Action: Equatable {
        case checkChain
        case applyPolicy(ForkMacBackupSource)
        case triggerSnapshot(ForkMacBackupSource)
        case cancelSnapshot(ForkMacBackupSource)
        /// Read how the source's snapshot ended (`conclude`, else `listSnapshots`).
        case conclude(ForkMacBackupSource, startedAt: Date, taskID: String?)
        case setThrottle(Int64?)
        case keepAwake(Bool)
        case runStarted(id: UUID, trigger: ForkMacBackupTrigger, due: Date?)
        case runEnded(Summary)
        case startVerify(ForkMacBackupVerifyLevel)
        case cancelVerify
        case verifyEnded(level: ForkMacBackupVerifyLevel, trigger: ForkMacBackupTrigger, start: Date,
                         result: ForkMacBackupEngineResult<ForkMacBackupVerifyReport>)
        /// Ask the planner again (a hold ended, a run ended, a command).
        case replan
        /// « Sauvegarder maintenant » / « Reprendre »: plan with this manual trigger.
        case requestRun(ForkMacBackupTrigger)
        /// A phase change worth publishing at once.
        case publish
    }

    // MARK: State

    private(set) var enabled = false
    private(set) var configured = false
    private(set) var sources: [ForkMacBackupSource] = []
    private(set) var iCloud: ForkMacBackupICloudMode = .fallback
    private(set) var run: Run?
    private(set) var verify: VerifyRun?
    /// A pause asked by the person.
    private(set) var pausedUntil: Date??
    private(set) var waiting: (reason: ForkMacBackupWaitReason, until: Date?)?
    private(set) var next: Date?
    private(set) var finished: (result: ForkMacBackupRunResult, at: Date)?
    private(set) var consecutiveFailures = 0
    private(set) var retryAt: Date?
    private(set) var lastError: ForkMacBackupPresentation.ErrorLine?
    private(set) var slowDown = false
    private(set) var limit: Int64?
    private(set) var appliedLimit: Int64??
    private(set) var keepAwakeAllowed = false
    private(set) var assertionHeld = false
    /// The trigger of a run a pause, a meeting or the update stopped: it
    /// resumes as soon as allowed (Kopia reuses what was sent).
    private(set) var interrupted: ForkMacBackupTrigger?
    private(set) var pendingVerify: (level: ForkMacBackupVerifyLevel, trigger: ForkMacBackupTrigger)?
    /// The source rules could not be written: no backup until the settings change.
    private(set) var rulesProblem = false
    /// `fork.macbackup.timeout.watchdogMinutes`.
    private(set) var watchdog = ForkMacBackupAgentTuning.watchdog
    private var finishedExpired = false

    init() {}

    /// When the machine needs a tick without any event: each second while an
    /// operation runs, the end of a pause, the end of the « finished » display.
    func nextWake(now: Date) -> Date? {
        if run != nil { return now.addingTimeInterval(1) }
        var dates: [Date] = []
        if case .some(.some(let until)) = pausedUntil { dates.append(until) }
        if let finished, !finishedExpired {
            dates.append(finished.at.addingTimeInterval(ForkMacBackupAgentTuning.finishedDisplay))
        }
        return dates.min()
    }

    var isBackingUp: Bool { run != nil }
    var isBusy: Bool { run != nil || verify != nil }
    var isPaused: Bool { pausedUntil != nil }

    // MARK: Phase

    func phase(now: Date) -> ForkMacBackupPhase {
        guard enabled else { return .off }
        if let run {
            switch run.step {
            case .checkingChain: return .checkingChain
            case .preparing, .starting: return .preparing
            case .scanning: return .scanning
            case .uploading: return limit == nil ? .uploading : .slowed
            case .concluding: return .concluding
            }
        }
        if verify != nil { return .verifying }
        guard configured else { return .notConfigured }
        if let pausedUntil { return .paused(until: pausedUntil) }
        if let finished, now.timeIntervalSince(finished.at) < ForkMacBackupAgentTuning.finishedDisplay {
            return .finished(finished.result)
        }
        if rulesProblem { return .waiting(reason: .rulesNotApplied, until: nil) }
        if let waiting { return .waiting(reason: waiting.reason, until: waiting.until) }
        return .ready(next: next)
    }

    /// The live figures of the operation running; nil at rest.
    func progress(now: Date) -> ForkMacBackupPresentation.Progress? {
        if let run {
            let completed = run.sources.prefix(run.index)
            let current = run.current?.counters ?? Counters()
            let done = completed.reduce(0) { $0 + $1.counters.done } + current.done
            let total: Int64? = current.total.map { completed.reduce(0) { $0 + ($1.counters.total ?? $1.counters.done) } + $0 }
            let files = completed.reduce(0) { $0 + $1.counters.files } + current.files
            let filesTotal: Int64? = current.filesTotal.map { completed.reduce(0) { $0 + ($1.counters.filesTotal ?? $1.counters.files) } + $0 }
            let uploaded = completed.reduce(0) { $0 + $1.counters.uploaded } + current.uploaded
            let errors = completed.reduce(0) { $0 + $1.counters.errors } + current.errors
            let scanning = run.step != .uploading
            return ForkMacBackupPresentation.Progress(
                bytesDone: done, bytesTotal: scanning ? nil : total, bytesUploaded: uploaded, files: files,
                filesTotal: scanning ? nil : filesTotal, bytesPerSecond: run.tracker.rate(),
                eta: scanning ? nil : run.tracker.eta(now: now, done: done, total: total),
                currentPath: current.path, errors: errors)
        }
        if let verify {
            return ForkMacBackupPresentation.Progress(files: verify.progress.checked, filesTotal: verify.progress.total)
        }
        return nil
    }

    /// The state of each source, as the section lists them.
    func sourceState(_ path: String) -> ForkMacBackupPresentation.SourceState? {
        guard let run else { return nil }
        guard let index = run.sources.firstIndex(where: { $0.source.path == path }) else { return nil }
        if index == run.index { return .running }
        if index > run.index { return .waiting }
        let done = run.sources[index]
        if done.failure != nil { return .failed }
        if let proof = done.proof { return proof.isPartial ? .partial : .done }
        return nil
    }

    // MARK: Events

    mutating func handle(_ event: Event, now: Date) -> [Action] {
        switch event {
        case .configure(let settings): return configure(settings, now: now)
        case .decision(let decision): return apply(decision, now: now)
        case .chainChecked(let error, let nodeID): return chainChecked(error, nodeID: nodeID, now: now)
        case .policyApplied(let source, let outcome): return policyApplied(source, outcome, now: now)
        case .snapshotTriggered(let source, let error): return snapshotTriggered(source, error, now: now)
        case .progress(let response):
            guard let current = run?.current else { return [] }
            return live(response.source(path: current.source.path), uploaded: nil, taskID: nil, now: now)
        case .live(let status, let uploaded, let taskID): return live(status, uploaded: uploaded, taskID: taskID, now: now)
        case .progressFailed(let error): return progressFailed(error, now: now)
        case .listed(let source, let result): return listed(source, result, now: now)
        case .concluded(let source, let result): return concluded(source, result, now: now)
        case .limit(let value): return setLimit(value)
        case .keepAwakeAllowed(let allowed):
            keepAwakeAllowed = allowed
            return syncAssertion()
        case .command(let command, let origin): return apply(command, origin: origin, now: now)
        case .meetingStarted:
            guard run != nil else { return [] }
            return stop(.meeting, now: now)
        case .stop(let reason):
            var actions: [Action] = []
            if run != nil { actions += stop(reason, now: now) }
            if verify != nil {
                verify?.canceled = true
                actions.append(.cancelVerify)
            }
            return actions
        case .verifyProgress(let progress):
            verify?.progress = progress
            return []
        case .verifyFinished(let result): return verifyFinished(result, now: now)
        case .woke:
            run?.lastProgressAt = now
            if run?.stopRequestedAt != nil { run?.stopRequestedAt = now }
            return []
        case .tick: return tick(now: now)
        }
    }

    private mutating func configure(_ settings: ForkMacBackupAgentSettings, now: Date) -> [Action] {
        let wasEnabled = enabled
        let changedSources = sources != settings.sources
        enabled = settings.enabled
        configured = settings.isConfigured
        watchdog = settings.watchdog
        sources = settings.sources
        iCloud = settings.iCloud
        // New rules may fix what could not be written.
        if changedSources || !wasEnabled { rulesProblem = false }
        rulesProblem = rulesProblem && configured
        var actions: [Action] = []
        if !enabled, wasEnabled {
            actions += handle(.stop(.featureOff), now: now)
            pausedUntil = nil
            interrupted = nil
            waiting = nil
            finished = nil
        }
        return actions + [.replan, .publish]
    }

    private mutating func apply(_ decision: ForkMacBackupPlanner.Decision, now: Date) -> [Action] {
        guard run == nil, verify == nil else { return [] }
        let before = phase(now: now)
        switch decision {
        case .off, .notConfigured:
            waiting = nil
            next = nil
        case .idle(let next):
            waiting = nil
            self.next = next
        case .nothingToDo(_, let next):
            waiting = nil
            self.next = next
        case .wait(let reason, _, _, let forcedAt):
            // `until`: when the wait ends at the latest (the soft conditions
            // give way); a recheck is the agent's business, not a promise.
            waiting = (reason, forcedAt)
            next = nil
        case .run(let trigger, let due):
            guard !rulesProblem, pausedUntil == nil else { return [] }
            return start(trigger: trigger, due: due, now: now)
        }
        return phase(now: now) == before ? [] : [.publish]
    }

    private mutating func start(trigger: ForkMacBackupTrigger, due: Date?, now: Date) -> [Action] {
        guard configured, !sources.isEmpty else { return [] }
        let id = UUID()
        run = Run(id: id, trigger: trigger, due: due, start: now, step: .checkingChain,
                  sources: sources.map { SourceRun(source: $0) }, lastProgressAt: now)
        waiting = nil
        finished = nil
        interrupted = nil
        appliedLimit = nil
        var actions: [Action] = [.runStarted(id: id, trigger: trigger, due: due), .checkChain]
        actions += syncAssertion()
        actions.append(.publish)
        return actions
    }

    private mutating func chainChecked(_ error: ForkMacBackupEngineError?, nodeID: String?, now: Date) -> [Action] {
        guard var run, run.step == .checkingChain, run.stopping == nil else { return stoppedEarly(now: now) }
        if let error {
            run.failedNode = nodeID
            run.abortMessage = message(of: error)
            self.run = run
            return finish(abort: error.runFailure, now: now)
        }
        run.step = .preparing
        run.lastProgressAt = now
        self.run = run
        guard let first = run.sources.first else { return finish(abort: .other, now: now) }
        return [.applyPolicy(first.source), .publish]
    }

    private mutating func policyApplied(_ source: ForkMacBackupSource, _ outcome: PolicyOutcome, now: Date) -> [Action] {
        guard var run, run.step == .preparing, run.stopping == nil else { return stoppedEarly(now: now) }
        switch outcome {
        case .mismatched:
            rulesProblem = true
            run.abortMessage = "rules not applied: \(source.path)"
            self.run = run
            return finish(abort: .other, now: now)
        case .failed(let error):
            run.abortMessage = message(of: error)
            self.run = run
            return finish(abort: error.runFailure, now: now)
        case .matched:
            run.lastProgressAt = now
            guard let index = run.sources.firstIndex(where: { $0.source == source }) else { return [] }
            if index + 1 < run.sources.count {
                self.run = run
                return [.applyPolicy(run.sources[index + 1].source)]
            }
            run.step = .starting
            run.index = 0
            run.sources[0].startedAt = now
            self.run = run
            var actions: [Action] = []
            appliedLimit = .some(limit)
            actions.append(.setThrottle(limit))
            actions.append(.triggerSnapshot(run.sources[0].source))
            return actions
        }
    }

    private mutating func snapshotTriggered(_ source: ForkMacBackupSource, _ error: ForkMacBackupEngineError?,
                                            now: Date) -> [Action] {
        guard var run, let current = run.current, current.source == source else { return [] }
        guard run.stopping == nil else { return [] }
        if let error {
            // Kopia exits 1 WITH its JSON when files failed: not a failure by
            // itself, the manifest decides (plan §3.8).
            if case .kopia(let code, _) = error, code == 1 {
                run.step = .concluding
                self.run = run
                return [concludeAction(run), .publish]
            }
            run.sources[run.index].failure = error.runFailure
            run.abortMessage = message(of: error)
            self.run = run
            return finish(abort: error.runFailure, now: now)
        }
        if run.step == .starting { run.step = .scanning }
        run.lastProgressAt = now
        self.run = run
        return [.publish]
    }

    private mutating func live(_ status: ForkMacBackupKopia.SourceStatus?, uploaded: Int64?, taskID: String?,
                               now: Date) -> [Action] {
        guard var run, let current = run.current else { return [] }
        run.pollFailures = 0
        if let taskID, !taskID.isEmpty { run.sources[run.index].taskID = taskID }
        if let uploaded { run.sources[run.index].counters.uploaded = max(current.counters.uploaded, uploaded) }
        guard [.starting, .scanning, .uploading].contains(run.step) else {
            self.run = run
            return []
        }
        var actions: [Action] = []
        if let status, status.isUploading, let upload = status.upload {
            let before = run.step
            var counters = Counters()
            counters.done = upload.bytesDone
            counters.total = upload.estimate
            // The control API's own count stays 0 in v0.23.1: the task's is the real one.
            counters.uploaded = max(run.sources[run.index].counters.uploaded, upload.uploadedBytes ?? 0)
            counters.files = upload.filesDone
            counters.filesTotal = (upload.estimatedFiles ?? 0) > 0 ? upload.estimatedFiles : nil
            counters.errors = Int((upload.errors ?? 0) + (upload.ignoredErrors ?? 0))
            counters.path = upload.directory.map { Self.join(current.source.path, $0) }
            run.sources[run.index].counters = counters
            run.sources[run.index].sawUpload = true
            run.bytesSent = max(run.bytesSent, run.sources.reduce(0) { $0 + $1.counters.uploaded })
            run.step = counters.total == nil ? .scanning : .uploading
            let signature = counters.signature
            if signature != run.signature {
                run.signature = signature
                run.lastProgressAt = now
            }
            let completed = run.sources.prefix(run.index)
            let done = completed.reduce(0) { $0 + $1.counters.done } + counters.done
            let total = counters.total.map { completed.reduce(0) { $0 + ($1.counters.total ?? $1.counters.done) } + $0 }
            run.tracker.add(done: done, estimate: total, at: now)
            self.run = run
            if before != run.step { actions.append(.publish) }
            return actions
        }
        // Not uploading: done if it ran, or if a snapshot newer than the
        // trigger is there (an unchanged source takes a third of a second).
        let startedAt = current.startedAt ?? run.start
        let fresh = status?.lastSnapshot?.startDate.map { $0 >= startedAt.addingTimeInterval(-2) } ?? false
        if current.sawUpload || fresh {
            if run.stopping != nil {
                self.run = run
                return endStopped(now: now)
            }
            run.step = .concluding
            self.run = run
            return [concludeAction(run), .publish]
        }
        if run.stopping != nil {
            self.run = run
            return endStopped(now: now)
        }
        if now.timeIntervalSince(startedAt) > ForkMacBackupAgentTuning.startGrace {
            run.sources[run.index].failure = .noSnapshot
            self.run = run
            return finish(abort: .noSnapshot, now: now)
        }
        self.run = run
        return []
    }

    private mutating func progressFailed(_ error: ForkMacBackupEngineError, now: Date) -> [Action] {
        guard var run else { return [] }
        run.pollFailures += 1
        self.run = run
        if run.stopping != nil, run.pollFailures >= 3 { return endStopped(now: now) }
        guard run.pollFailures >= 30 else { return [] }
        let text = message(of: error)
        self.run?.abortMessage = text
        return finish(abort: error.runFailure, now: now)
    }

    private mutating func listed(_ source: ForkMacBackupSource,
                                 _ result: ForkMacBackupEngineResult<[ForkMacBackupKopia.SnapshotManifest]>,
                                 now: Date) -> [Action] {
        guard var run, let current = run.current, current.source == source, run.step == .concluding else { return [] }
        let startedAt = current.startedAt ?? run.start
        switch result {
        case .failure(let error):
            run.sources[run.index].failure = error.runFailure
            run.abortMessage = message(of: error)
        case .success(let manifests):
            // `snapshot list <path>` also returns the parents' snapshots.
            let mine = manifests.filter { $0.source?.path == source.path }
                .filter { ($0.startDate ?? .distantPast) >= startedAt.addingTimeInterval(-5) }
                .max { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
            if let manifest = mine {
                let proof = ForkMacBackupSnapshotProof(manifest: manifest, iCloud: iCloud)
                run.sources[run.index].proof = proof
                // Canceled or checkpoint only: no complete walk, no resume.
                if proof.incomplete != nil { run.sources[run.index].failure = .noSnapshot }
            } else {
                run.sources[run.index].failure = .noSnapshot
            }
        }
        return advance(run, now: now)
    }

    private mutating func concluded(_ source: ForkMacBackupSource,
                                    _ result: ForkMacBackupEngineResult<ForkMacBackupRunConclusion>,
                                    now: Date) -> [Action] {
        guard var run, let current = run.current, current.source == source, run.step == .concluding else { return [] }
        switch result {
        case .failure(let error):
            run.sources[run.index].failure = error.runFailure
            run.abortMessage = message(of: error)
        case .success(let conclusion):
            if let sent = conclusion.uploadedBytes {
                run.sources[run.index].counters.uploaded = max(current.counters.uploaded, sent)
                run.bytesSent = max(run.bytesSent, run.sources.reduce(0) { $0 + $1.counters.uploaded })
            }
            if let taskID = conclusion.taskID { run.sources[run.index].taskID = taskID }
            run.sources[run.index].proof = conclusion.proof
            switch conclusion.outcome {
            case .complete, .partial:
                break
            case .canceled, .failed:
                // Canceled or checkpoint only: no complete walk, no resume.
                run.sources[run.index].failure = .noSnapshot
            }
        }
        return advance(run, now: now)
    }

    /// The current source is concluded: the next one, or the end.
    private mutating func advance(_ concludedRun: Run, now: Date) -> [Action] {
        var run = concludedRun
        run.sources[run.index].listed = true
        if run.index + 1 < run.sources.count {
            run.index += 1
            run.sources[run.index].startedAt = now
            run.step = .starting
            run.lastProgressAt = now
            self.run = run
            return [.triggerSnapshot(run.sources[run.index].source), .publish]
        }
        self.run = run
        return finish(abort: nil, now: now)
    }

    private func concludeAction(_ run: Run) -> Action {
        let current = run.sources[run.index]
        return .conclude(current.source, startedAt: current.startedAt ?? run.start, taskID: current.taskID)
    }

    private mutating func setLimit(_ value: Int64?) -> [Action] {
        let before = limit
        limit = value
        guard let run, [.starting, .scanning, .uploading].contains(run.step), appliedLimit != .some(value) else {
            return before == value ? [] : [.publish]
        }
        appliedLimit = .some(value)
        return [.setThrottle(value), .publish]
    }

    private mutating func syncAssertion() -> [Action] {
        let wanted = run != nil && keepAwakeAllowed
        guard wanted != assertionHeld else { return [] }
        assertionHeld = wanted
        return [.keepAwake(wanted)]
    }

    // MARK: Commands

    private mutating func apply(_ command: ForkMacBackupCommand, origin: ForkMacBackupTrigger, now: Date) -> [Action] {
        switch command {
        case .backUpNow:
            guard enabled, configured, run == nil else { return [] }
            pausedUntil = nil
            rulesProblem = false
            return [.requestRun(origin), .publish]
        case .pause(let until):
            guard enabled else { return [] }
            pausedUntil = .some(until)
            var actions: [Action] = []
            if run != nil { actions += stop(.paused, now: now) }
            if verify != nil {
                verify?.canceled = true
                actions.append(.cancelVerify)
            }
            return actions + [.publish]
        case .resume:
            guard pausedUntil != nil else { return [] }
            pausedUntil = nil
            return [.replan, .publish]
        case .slowDown(let on):
            guard slowDown != on else { return [] }
            slowDown = on
            return [.replan, .publish]
        case .verify(let level):
            guard enabled, configured else { return [] }
            if run != nil {
                pendingVerify = (level, origin)
                return []
            }
            guard verify == nil else { return [] }
            return startVerify(level, trigger: origin, now: now)
        case .cancel:
            if run != nil { return stop(.user, now: now) }
            if verify != nil {
                verify?.canceled = true
                return [.cancelVerify]
            }
            return []
        case .reloadSettings:
            return [.replan]
        case .stopOtherEngine:
            // The app stopped the other engine: check the repository again now.
            return [.replan, .publish]
        }
    }

    private mutating func startVerify(_ level: ForkMacBackupVerifyLevel, trigger: ForkMacBackupTrigger,
                                      now: Date) -> [Action] {
        verify = VerifyRun(level: level, start: now, trigger: trigger)
        return [.startVerify(level), .publish]
    }

    private mutating func verifyFinished(_ result: ForkMacBackupEngineResult<ForkMacBackupVerifyReport>,
                                         now: Date) -> [Action] {
        guard let verify else { return [] }
        self.verify = nil
        return [.verifyEnded(level: verify.level, trigger: verify.trigger, start: verify.start, result: result),
                .replan, .publish]
    }

    // MARK: Stopping

    /// Cancels the snapshot running (Kopia keeps a checkpoint); the run ends
    /// once the source is idle again, or after `cancelGrace`.
    private mutating func stop(_ reason: ForkMacBackupStopReason, now: Date) -> [Action] {
        guard var run, run.stopping == nil else { return [] }
        run.stopping = reason
        run.stopRequestedAt = now
        self.run = run
        switch reason {
        case .paused, .meeting, .appUpdate, .sleep: interrupted = run.trigger
        case .user, .watchdog, .featureOff, .agentQuit: interrupted = nil
        }
        switch run.step {
        case .starting, .scanning, .uploading:
            guard let current = run.current else { return endStopped(now: now) }
            return [.cancelSnapshot(current.source), .publish]
        case .checkingChain, .preparing, .concluding:
            // Nothing of Kopia's to cancel: answers still on their way are ignored.
            return endStopped(now: now)
        }
    }

    /// An answer that arrives after a stop ends the run.
    private mutating func stoppedEarly(now: Date) -> [Action] {
        guard let run, run.stopping != nil else { return [] }
        return endStopped(now: now)
    }

    private mutating func endStopped(now: Date) -> [Action] {
        guard let run, let reason = run.stopping else { return [] }
        if reason == .watchdog {
            self.run?.abortMessage = "no progress for \(Int(watchdog / 60)) min"
            return finish(abort: .stalled, now: now)
        }
        let proofs = run.sources.compactMap(\.proof)
        let summary = Summary(id: run.id, trigger: run.trigger, due: run.due, start: run.start, end: now, result: nil,
                              outcome: .canceled, failure: nil, stopReason: reason, proofs: proofs,
                              bytesSent: run.bytesSent, message: nil)
        self.run = nil
        var actions: [Action] = syncAssertion()
        actions.append(.runEnded(summary))
        actions += afterRun(now: now)
        return actions
    }

    private mutating func tick(now: Date) -> [Action] {
        var actions: [Action] = []
        if case .some(.some(let until)) = pausedUntil, until <= now {
            pausedUntil = nil
            actions += [.replan, .publish]
        }
        if let finished, !finishedExpired, now.timeIntervalSince(finished.at) >= ForkMacBackupAgentTuning.finishedDisplay {
            finishedExpired = true
            actions.append(.publish)
        }
        guard let run else { return actions }
        if let requested = run.stopRequestedAt {
            if now.timeIntervalSince(requested) >= ForkMacBackupAgentTuning.cancelGrace {
                actions += endStopped(now: now)
            }
            return actions
        }
        if [.scanning, .uploading, .starting].contains(run.step),
           now.timeIntervalSince(run.lastProgressAt) >= watchdog {
            actions += stop(.watchdog, now: now)
        }
        return actions
    }

    // MARK: Conclusion

    /// Ends the run. `abort`: why it stopped short; nil: every source was listed.
    private mutating func finish(abort: ForkMacBackupRunFailure?, now: Date) -> [Action] {
        guard let run else { return [] }
        let proofs = run.sources.compactMap(\.proof)
        let result = Self.conclusion(sources: run.sources, abort: abort)
        let failure: ForkMacBackupRunFailure?
        let outcome: ForkMacBackupRunRecord.Outcome
        switch result {
        case .complete: failure = nil; outcome = .complete
        case .partial: failure = nil; outcome = .partial
        case .nothingToDo: failure = nil; outcome = .nothingToDo
        case .failed(let cause): failure = cause; outcome = .failed
        }
        if let failure {
            consecutiveFailures += 1
            retryAt = now.addingTimeInterval(Self.backoff(after: consecutiveFailures))
            lastError = ForkMacBackupPresentation.ErrorLine(cause: failure, nodeID: run.failedNode, at: now,
                                                            message: run.abortMessage)
        } else {
            consecutiveFailures = 0
            retryAt = nil
            lastError = nil
        }
        finished = (result, now)
        finishedExpired = false
        let summary = Summary(id: run.id, trigger: run.trigger, due: run.due, start: run.start, end: now,
                              result: result, outcome: outcome, failure: failure, stopReason: run.stopping,
                              proofs: proofs, bytesSent: run.bytesSent, message: run.abortMessage)
        self.run = nil
        var actions: [Action] = syncAssertion()
        actions.append(.runEnded(summary))
        actions += afterRun(now: now)
        return actions
    }

    private mutating func afterRun(now: Date) -> [Action] {
        var actions: [Action] = [.replan, .publish]
        if let pending = pendingVerify {
            pendingVerify = nil
            actions = startVerify(pending.level, trigger: pending.trigger, now: now) + [.replan]
        }
        return actions
    }

    /// Plan §3.8: complete = every manifest found without error; partial =
    /// found with real read errors (named); failed = no manifest, or one
    /// left incomplete, or the run stopped short.
    static func conclusion(sources: [SourceRun], abort: ForkMacBackupRunFailure?) -> ForkMacBackupRunResult {
        if let abort { return .failed(abort) }
        if let failure = sources.compactMap(\.failure).first { return .failed(failure) }
        let proofs = sources.compactMap(\.proof)
        guard proofs.count == sources.count, !proofs.isEmpty else { return .failed(.noSnapshot) }
        let failed = proofs.reduce(0) { $0 + $1.failureCount }
        return failed > 0 ? .partial(files: failed) : .complete
    }

    /// 1, 5, 15, 60 min, then doubling, at most 6 h.
    static func backoff(after failures: Int) -> TimeInterval {
        let steps = ForkMacBackupAgentTuning.backoffSteps
        guard failures > 0 else { return 0 }
        if failures <= steps.count { return steps[failures - 1] }
        let doubled = (steps.last ?? 3_600) * pow(2, Double(failures - steps.count))
        return min(ForkMacBackupAgentTuning.backoffCap, doubled)
    }

    private func message(of error: ForkMacBackupEngineError) -> String? {
        switch error {
        case .unreachable(let text), .decoding(let text), .other(let text): return text
        case .kopia(let code, let text): return "exit \(code): \(text)"
        case .wrongRepository(let found): return "unique ID \(ForkMacBackupRepository.shortID(found))"
        case .engineMissing, .serverUnavailable, .notConnected, .authentication, .timeout, .canceled: return nil
        }
    }

    /// `directory` is relative to the source's root (`.` for the root).
    static func join(_ root: String, _ relative: String) -> String {
        guard !relative.isEmpty, relative != "." else { return root }
        if relative.hasPrefix("/") { return relative }
        return (root as NSString).appendingPathComponent(relative)
    }
}
