// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation
import notify

/// The one authority on Kopia (README §1): it plans, runs and concludes the
/// backups, keeps the ledgers, and publishes the state. The same code runs
/// in the headless agent (`--fork-backup-agent`) and, when the agent may
/// not run, in the app while it is open (plan §3.4). Everything happens on
/// one serial queue, `fork.macbackup.agent`; the engine answers on it too.
final class ForkMacBackupRunner {
    enum Host {
        case agent
        case app
    }

    enum StartOutcome: Equatable {
        case started
        /// Another process holds `run/agent.lock`.
        case held(role: ForkMacBackupAgentLock.Role?, pid: Int32?)
        case failed
    }

    let host: Host
    let paths: ForkMacBackupPaths
    let bundleID: String
    let queue = DispatchQueue(label: "fork.macbackup.agent", qos: .utility)

    /// The agent asks to leave: 0 when switched off, 75 to move to a new
    /// build (launchd relaunches it, `KeepAlive.SuccessfulExit = false`).
    var onExitRequest: ((Int32) -> Void)?
    /// The app's runner handed the lock over to a starting agent.
    var onHandedOver: (() -> Void)?

    private let defaults: UserDefaults
    private let notify: ForkMacBackupNotify
    private let names: ForkMacBackupAgentIPCSupport.Names
    private let lock: ForkMacBackupAgentLock
    private let watch: ForkMacBackupSystemWatch
    private let fsevents: ForkMacBackupFSEventsWatch
    private let keepAwake = ForkMacBackupKeepAwake()
    private let calendar = Calendar.autoupdatingCurrent
    private let runningBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

    private var machine = ForkMacBackupMachine()
    private var settings: ForkMacBackupAgentSettings
    private var engine: ForkMacBackupEngineDriving?
    /// What the Engine offers beyond the frozen protocol (its owner always
    /// does; a harness's fake may not).
    private var extras: ForkMacBackupEngineExtras? { engine as? ForkMacBackupEngineExtras }
    private var engineTriedAt: Date?
    private var connectedKey: String?
    private var proofs = ForkMacBackupProofStore()
    private var runs: [ForkMacBackupRunRecord] = []
    private var book = ForkMacBackupSlotBook()
    private var timeline = ForkMacBackupSlotTimeline()
    private var chain = ForkMacBackupChainProbe()

    private var peerOnline: Bool?
    private var peerCheckedAt: Date?
    private var peerProbeInFlight = false
    private var wrongRepository = false
    private var otherEngine = false
    private var otherEngineCheckedAt: Date?
    private var diskRefused = false
    private var diskCheckedAt: Date?
    private var spaceLow = false
    private var spaceCheckedAt: Date?

    private var manualRequest: ForkMacBackupTrigger?
    private var wokeAt: Date?
    private var wasPaused = false
    private var lastWaitReason: ForkMacBackupMissedReason?
    private var lastPresentation: ForkMacBackupPresentation?
    private var lastWrittenAt: Date?
    private var wakeTimer: DispatchSourceTimer?
    private var pollTimer: DispatchSourceTimer?
    private var houseTimer: DispatchSourceTimer?
    private var tokens: [Int32] = []
    private var signalSources: [DispatchSourceSignal] = []
    private var running = false
    private var stopping = false
    private var evaluatePending = false
    private var verifyHandle: ForkMacBackupCancellable?
    private var runStartEvent: UInt64?
    private var runCostStart: (reading: ForkMacBackupCostMeter.Reading?, percent: Double?, onAC: Bool)?
    /// Each source's pre-scan: the run's extra rules and its real size.
    private var prescans: [String: Prescan] = [:]
    private var prescanCancel: ForkMacBackupFlag?
    private var maintenanceCheckedAt: Date?
    private var reconciledAt: Date?
    private var blobStatsAt: Date?
    private var repositoryBytes: Int64?
    private var repositoryMeasuredAt: Date?

    /// What the runner gets from outside: the engine (the Engine package's
    /// owner in the app and the agent, a fake in a harness) and the look at
    /// the other Kopia processes.
    struct Dependencies {
        var makeEngine: (ForkMacBackupPaths, DispatchQueue) -> (engine: ForkMacBackupEngineDriving, secrets: ForkMacBackupSecrets)?
        var otherEngineWrites: (ForkMacBackupRepository, URL) -> Bool

        static let live = Dependencies(
            makeEngine: { paths, queue in
                guard let secrets = ForkMacBackupEngineFactory.makeSecrets(),
                      let engine = ForkMacBackupEngineFactory.makeOwner(paths: paths, secrets: secrets,
                                                                        callbackQueue: queue) else { return nil }
                return (engine, secrets)
            },
            otherEngineWrites: { repository, root in ForkMacBackupProcesses.otherEngineWrites(to: repository, ourRoot: root) })
    }

    private let dependencies: Dependencies

    struct Prescan {
        var date: Date
        var rules: [String]
        /// Allocated bytes of what the source keeps.
        var realBytes: Int64
    }

    init(host: Host, paths: ForkMacBackupPaths, bundleID: String, defaults: UserDefaults = .standard,
         dependencies: Dependencies = .live) {
        self.dependencies = dependencies
        self.host = host
        self.paths = paths
        self.bundleID = bundleID
        self.defaults = defaults
        notify = ForkMacBackupNotify(bundleID: bundleID)
        names = ForkMacBackupAgentIPCSupport.Names(bundleID: bundleID)
        lock = ForkMacBackupAgentLock(url: paths.agentLock)
        watch = ForkMacBackupSystemWatch(queue: queue, bundleID: bundleID)
        fsevents = ForkMacBackupFSEventsWatch(queue: queue, fileURL: paths.pending)
        settings = ForkMacBackupAgentSettings { defaults.object(forKey: $0) }
    }

    deinit {
        keepAwake.set(false, reason: "")
    }

    // MARK: Start and stop

    /// Takes the single-instance lock, then starts everything on the queue.
    func start() -> StartOutcome {
        let container = paths.root.deletingLastPathComponent()
        for folder in paths.folders {
            guard PrivateFileStore.createDirectory(at: folder, container: container) else { return .failed }
        }
        switch lock.acquire(role: host == .agent ? .agent : .app) {
        case .acquired: break
        case .held(let role, let pid): return .held(role: role, pid: pid)
        case .failed: return .failed
        }
        queue.async { self.setUp() }
        return .started
    }

    /// The agent waits for the app's runner to hand the lock over.
    func postHandover() {
        notify_post(names.handover)
    }

    /// Stops cleanly: the snapshot running is canceled (Kopia keeps a
    /// checkpoint), the assertion released, the state written, the lock
    /// released; `completion` runs on the queue.
    func shutdown(_ reason: ForkMacBackupStopReason, completion: @escaping () -> Void) {
        queue.async {
            guard self.running, !self.stopping else {
                completion()
                return
            }
            self.stopping = true
            self.prescanCancel?.set()
            self.perform(self.machine.handle(.stop(reason), now: Date()))
            self.waitUntilIdle(deadline: Date().addingTimeInterval(25)) {
                self.tearDown(reason: reason, completion: completion)
            }
        }
    }

    private func setUp() {
        let now = Date()
        running = true
        loadRecords(now: now)
        noteStart(now: now)
        wokeAt = now

        watch.onChange = { [weak self] in self?.conditionsChanged() }
        watch.onWillSleep = { [weak self] in self?.timeline.append(.willSleep, at: Date()) }
        watch.onDidWake = { [weak self] in self?.didWake() }
        watch.start()
        fsevents.onChange = { [weak self] _ in self?.scheduleEvaluate() }
        restartFSEvents()

        listen(notify.command) { [weak self] in self?.readCommands() }
        listen(notify.settings) { [weak self] in self?.reloadSettings() }
        if host == .app {
            listen(names.handover) { [weak self] in self?.handOver() }
        } else {
            for value in [SIGTERM, SIGINT] {
                signal(value, SIG_IGN)
                let source = DispatchSource.makeSignalSource(signal: value, queue: queue)
                source.setEventHandler { [weak self] in
                    self?.shutdown(.agentQuit) { self?.onExitRequest?(0) }
                }
                source.resume()
                signalSources.append(source)
            }
        }
        let house = DispatchSource.makeTimerSource(queue: queue)
        house.schedule(wallDeadline: .now() + 60, repeating: 60, leeway: .seconds(10))
        house.setEventHandler { [weak self] in self?.housekeeping() }
        house.resume()
        houseTimer = house

        makeEngineIfNeeded(now: now)
        perform(machine.handle(.configure(settings), now: now))
        perform(machine.handle(.keepAwakeAllowed(ForkMacBackupPlanner.keepsAwake(settings.keepAwake, onAC: watch.onAC)), now: now))
        readCommands()
        evaluate()
        if !settings.enabled { disabled() }
    }

    private func tearDown(reason: ForkMacBackupStopReason, completion: @escaping () -> Void) {
        keepAwake.set(false, reason: "")
        pollTimer?.cancel()
        pollTimer = nil
        wakeTimer?.cancel()
        wakeTimer = nil
        houseTimer?.cancel()
        houseTimer = nil
        for token in tokens { notify_cancel(token) }
        tokens = []
        for source in signalSources { source.cancel() }
        signalSources = []
        watch.stop()
        fsevents.stop()
        timeline.append(.agentStopped, at: Date())
        publish(force: true)
        running = false
        stopping = false
        verifyHandle = nil
        // The engine's `kopia server` stops BEFORE the lock goes, so the
        // lock's next holder (the agent after the app's runner) starts its
        // own on a free repository.
        let release = { [weak self] in
            guard let self else { return completion() }
            self.engine = nil
            self.secretsStore = nil
            self.connectedKey = nil
            self.lock.release()
            completion()
        }
        guard let extras else { return release() }
        // The engine answers on this queue.
        extras.shutdown(completion: release)
    }

    private func waitUntilIdle(deadline: Date, then: @escaping () -> Void) {
        if !machine.isBusy || Date() >= deadline {
            then()
            return
        }
        queue.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.waitUntilIdle(deadline: deadline, then: then) }
    }

    private func listen(_ name: String, _ handler: @escaping () -> Void) {
        var token: Int32 = 0
        if notify_register_dispatch(name, &token, queue, { _ in handler() }) == UInt32(NOTIFY_STATUS_OK) {
            tokens.append(token)
        }
    }

    /// The app's runner: a starting agent wants the lock.
    private func handOver() {
        shutdown(.agentQuit) { [weak self] in self?.onHandedOver?() }
    }

    /// Switched off: everything stops; the agent leaves for good.
    private func disabled() {
        shutdown(.featureOff) { [weak self] in
            guard let self else { return }
            if self.host == .agent { self.onExitRequest?(0) }
        }
    }

    // MARK: Records

    private func loadRecords(now: Date) {
        if let data = try? Data(contentsOf: paths.proofs), let store = ForkMacBackupProofStore.decode(data) {
            proofs = store
        }
        rotate(paths.runs, as: ForkMacBackupRunRecord.self, now: now) { $0.end ?? $0.start }
        rotate(paths.slots, as: ForkMacBackupSlotRecord.self, now: now) { $0.due }
        if let data = try? Data(contentsOf: paths.runs) {
            runs = Array(ForkMacBackupJSON.lines(ForkMacBackupRunRecord.self, from: data).suffix(500))
        }
        if let data = try? Data(contentsOf: paths.slots) {
            book.lastClosedDue = ForkMacBackupJSON.lines(ForkMacBackupSlotRecord.self, from: data).map(\.due).max()
        }
        if let data = try? Data(contentsOf: paths.capacity) {
            let physical = ForkMacBackupJSON.lines(ForkMacBackupCapacitySample.self, from: data).last { $0.kind == .physical }
            repositoryBytes = physical?.bytes
            repositoryMeasuredAt = physical?.date
            blobStatsAt = physical?.date
        }
    }

    /// The gap since the last state written: off (a boot in between) or not
    /// running (the app closed without an agent).
    private func noteStart(now: Date) {
        if let data = try? Data(contentsOf: paths.state), let file = ForkMacBackupStateFile.decode(data),
           file.writtenAt < now {
            timeline.append(.agentStopped, at: file.writtenAt)
            if let boot = ForkMacBackupSystemWatch.bootTime(), boot > file.writtenAt {
                timeline.append(.booted, at: boot)
            }
        }
        timeline.append(.agentStarted, at: now)
    }

    private func append<Value: Encodable>(_ value: Value, to url: URL) {
        guard let line = ForkMacBackupJSON.line(value) else { return }
        if !FileManager.default.fileExists(atPath: url.path) {
            PrivateFileStore.write(line, to: url)
            return
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: line)
    }

    private func rotate<Value: Codable>(_ url: URL, as type: Value.Type, now: Date, date: (Value) -> Date) {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int,
              size > ForkMacBackupAgentTuning.journalRotateBytes, let data = try? Data(contentsOf: url) else { return }
        PrivateFileStore.write(ForkMacBackupJournal.trimmed(data, as: type, now: now, date: date), to: url)
    }

    private func saveProofs() {
        if let data = proofs.encoded() { PrivateFileStore.write(data, to: paths.proofs) }
    }

    // MARK: Engine

    private func makeEngineIfNeeded(now: Date) {
        guard engine == nil, settings.enabled, settings.isConfigured else { return }
        if let tried = engineTriedAt, now.timeIntervalSince(tried) < 15 * 60 { return }
        engineTriedAt = now
        guard let made = dependencies.makeEngine(paths, queue) else { return }
        engine = made.engine
        secretsStore = made.secrets
    }

    private var secretsStore: ForkMacBackupSecrets?

    /// The repository as it is connected: any change means a new `connect`.
    private var repositoryFingerprint: String? {
        settings.repository.flatMap { try? ForkMacBackupJSON.encoder.encode($0) }.map { String(decoding: $0, as: UTF8.self) }
    }

    private func ensureConnected(_ completion: @escaping (ForkMacBackupEngineError?) -> Void) {
        guard let engine, let repository = settings.repository, let secrets = secretsStore else {
            completion(.engineMissing)
            return
        }
        let fingerprint = repositoryFingerprint
        if connectedKey != nil, connectedKey == fingerprint {
            completion(nil)
            return
        }
        let key = repository.key
        let queue = self.queue
        // The Keychain: bounded, never on the agent's queue.
        DispatchQueue.global(qos: .utility).async {
            let password = secrets.read(.repositoryPassword, repositoryKey: key)
            let secret = repository.accessKeyID == nil ? .missing : secrets.read(.s3SecretKey, repositoryKey: key)
            queue.async {
                guard case .found(let repositoryPassword) = password else {
                    completion(password == .missing ? .authentication : .other("Keychain unavailable"))
                    return
                }
                var credentials = ForkMacBackupCredentials(repositoryPassword: repositoryPassword)
                if case .found(let secretKey) = secret {
                    credentials.accessKeyID = repository.accessKeyID
                    credentials.secretAccessKey = secretKey
                }
                let connect = {
                    engine.connect(repository, credentials: credentials, readOnly: false) { [weak self] result in
                        guard let self else { return }
                        switch result {
                        case .success:
                            self.connected(fingerprint, repository: repository, completion: completion)
                            if let fingerprint { PrivateFileStore.write(Data(fingerprint.utf8), to: self.connectedMarker(repository)) }
                        case .failure(let error):
                            completion(error)
                        }
                    }
                }
                // The same repository as at the last `connect` (this agent or an
                // earlier one): its config stands, the server starts without
                // the network; the chain check still reads the unique ID.
                guard let extras = self.extras, let fingerprint,
                      (try? Data(contentsOf: self.connectedMarker(repository))) == Data(fingerprint.utf8) else {
                    return connect()
                }
                extras.startServer(repository, credentials: credentials) { [weak self] result in
                    guard let self else { return }
                    switch result {
                    case .success: self.connected(fingerprint, repository: repository, completion: completion)
                    case .failure(.notConnected): connect()
                    case .failure(let error): completion(error)
                    }
                }
            }
        }
    }

    private func connected(_ fingerprint: String?, repository: ForkMacBackupRepository,
                           completion: (ForkMacBackupEngineError?) -> Void) {
        connectedKey = fingerprint
        wrongRepository = false
        completion(nil)
        reconcileIfDue(force: true)
    }

    /// `repo/<key>/connected`: the repository as last connected.
    private func connectedMarker(_ repository: ForkMacBackupRepository) -> URL {
        paths.repository(repository.key).folder.appendingPathComponent("connected", isDirectory: false)
    }

    // MARK: Evaluation

    private func scheduleEvaluate() {
        guard !evaluatePending else { return }
        evaluatePending = true
        queue.async { [weak self] in
            self?.evaluatePending = false
            self?.evaluate()
        }
    }

    private var updateHold: Bool {
        let date = (try? FileManager.default.attributesOfItem(atPath: ForkMacBackupAgentIPCSupport.updateHoldURL(paths).path))?[.modificationDate] as? Date
        return ForkMacBackupAgentIPCSupport.updateHoldIsFresh(modifiedAt: date, now: Date())
    }

    private func conditions() -> ForkMacBackupConditions {
        let meeting = watch.meetingBusy || (host == .app && ForkMeetingActivity.isBusy)
        return ForkMacBackupConditions(onAC: watch.onAC, batteryPercent: watch.batteryPercent,
                                       lowPowerMode: watch.lowPowerMode, network: watch.network,
                                       peerOnline: settings.repository?.peer == nil ? nil : peerOnline,
                                       meetingBusy: meeting, engineAvailable: engine != nil,
                                       wrongRepository: wrongRepository, diskAccess: !diskRefused,
                                       localSpaceLow: spaceLow, otherEngine: otherEngine, updateHold: updateHold)
    }

    /// The conditions that send no notification, each at its own pace.
    private func refreshSlowConditions(now: Date) {
        if diskCheckedAt.map({ now.timeIntervalSince($0) >= ForkMacBackupAgentTuning.diskAccessRecheck }) ?? true {
            diskCheckedAt = now
            diskRefused = ForkMacBackupSystemWatch.diskAccessKnownRefused()
        }
        if spaceCheckedAt.map({ now.timeIntervalSince($0) >= 60 }) ?? true {
            spaceCheckedAt = now
            spaceLow = ForkMacBackupSystemWatch.localSpaceLow(at: paths.root)
        }
        if let repository = settings.repository,
           otherEngineCheckedAt.map({ now.timeIntervalSince($0) >= 30 }) ?? true {
            otherEngineCheckedAt = now
            otherEngine = dependencies.otherEngineWrites(repository, paths.root)
        }
        if let peer = settings.repository?.peer, !peerProbeInFlight,
           peerCheckedAt.map({ now.timeIntervalSince($0) >= ForkMacBackupAgentTuning.peerRecheck }) ?? true {
            probePeer(peer)
        }
    }

    private func probePeer(_ peer: ForkMacBackupRepository.Peer) {
        peerProbeInFlight = true
        watch.probePeer(peer, timeout: settings.probeTimeout) { [weak self] online in
            guard let self else { return }
            self.peerProbeInFlight = false
            self.peerCheckedAt = Date()
            let changed = online != self.peerOnline
            self.peerOnline = online
            self.chain.peerOnline = online
            if changed { self.scheduleEvaluate() }
        }
    }

    private func currentLimit(now: Date) -> Int64? {
        ForkMacBackupPlanner.uploadLimit(settings: settings, conditions: conditions(), slowDown: machine.slowDown, now: now,
                                         calendar: calendar)
    }

    private func evaluate() {
        guard running, !stopping else { return }
        let now = Date()
        makeEngineIfNeeded(now: now)
        refreshSlowConditions(now: now)
        perform(machine.handle(.limit(currentLimit(now: now)), now: now))
        perform(machine.handle(.keepAwakeAllowed(ForkMacBackupPlanner.keepsAwake(settings.keepAwake, onAC: watch.onAC)),
                               now: now))
        notePause(now: now)
        var decision: ForkMacBackupPlanner.Decision?
        if !machine.isBusy {
            let conditions = conditions()
            let lastBackup = proofs.lastBackup(paths: settings.sources.map(\.path))
            for record in book.sweep(now: now, lastBackup: lastBackup, settings: settings, onAC: conditions.onAC,
                                     calendar: calendar, timeline: timeline) {
                append(record, to: paths.slots)
            }
            var input = ForkMacBackupPlanner.Input(now: now, calendar: calendar, settings: settings, conditions: conditions,
                                                   lastBackup: lastBackup, lastClosedDue: book.lastClosedDue,
                                                   openSlotDue: book.open?.due, pending: fsevents.summary,
                                                   retryAt: machine.retryAt, interrupted: machine.interrupted,
                                                   wokeAt: wokeAt, manual: manualRequest)
            if machine.isPaused { input.manual = nil }
            let planned = ForkMacBackupPlanner.decide(input)
            manualRequest = nil
            decision = planned
            note(planned, now: now)
            // A Tailscale peer is asked again right before a run.
            if case .run = planned, let peer = settings.repository?.peer,
               peerCheckedAt.map({ now.timeIntervalSince($0) > 60 }) ?? true {
                if !peerProbeInFlight { probePeer(peer) }
                if peerOnline == false || peerCheckedAt == nil {
                    scheduleWake(now: now, decision: .idle(next: now.addingTimeInterval(10)))
                    publish()
                    return
                }
            }
            perform(machine.handle(.decision(planned), now: now))
        }
        scheduleWake(now: now, decision: decision)
        syncPolling()
        publish()
    }

    /// The ledger follows the decision: a slot opened by a wait or a run,
    /// written at once when there is nothing to do.
    private func note(_ decision: ForkMacBackupPlanner.Decision, now: Date) {
        switch decision {
        case .wait(let reason, let due, _, _):
            if let due { book.open(due) }
            book.waited(reason.missedReason)
            if let missed = reason.missedReason {
                if lastWaitReason != missed { timeline.append(.waiting(missed), at: now) }
                lastWaitReason = missed
            }
        case .run(_, let due):
            if let due { book.open(due) }
            clearWait(now: now)
        case .nothingToDo(let due, _):
            append(book.nothingToDo(due), to: paths.slots)
            clearWait(now: now)
        case .idle, .off, .notConfigured:
            clearWait(now: now)
        }
    }

    private func clearWait(now: Date) {
        guard lastWaitReason != nil else { return }
        lastWaitReason = nil
        timeline.append(.clear, at: now)
    }

    private func notePause(now: Date) {
        guard machine.isPaused != wasPaused else { return }
        wasPaused = machine.isPaused
        timeline.append(wasPaused ? .paused : .resumed, at: now)
    }

    /// One timer for the next moment anything is due; at most 15 min apart.
    private func scheduleWake(now: Date, decision: ForkMacBackupPlanner.Decision?) {
        var dates = [now.addingTimeInterval(15 * 60)]
        if let wake = machine.nextWake(now: now), !machine.isBusy { dates.append(wake) }
        switch decision {
        case .idle(let next)?: if let next { dates.append(next) }
        case .nothingToDo(_, let next)?: if let next { dates.append(next) }
        case .wait(_, _, let recheck, let forcedAt)?:
            if let recheck { dates.append(recheck) }
            if let forcedAt { dates.append(forcedAt) }
        case .run?, .off?, .notConfigured?, nil: break
        }
        if case .some(.some(let until)) = machine.pausedUntil { dates.append(until) }
        if let retry = machine.retryAt { dates.append(retry) }
        let target = max(now.addingTimeInterval(1), dates.min() ?? now.addingTimeInterval(15 * 60))
        wakeTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        // Wall clock: a wait « until 18:04 » ends at 18:04, sleep included.
        timer.schedule(wallDeadline: .now() + target.timeIntervalSince(now), leeway: .seconds(30))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.perform(self.machine.handle(.tick, now: Date()))
            self.evaluate()
        }
        timer.resume()
        wakeTimer = timer
    }

    /// Each second while an operation runs: progress, watchdog, publishing.
    private func syncPolling() {
        if machine.isBusy {
            guard pollTimer == nil else { return }
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + ForkMacBackupAgentTuning.progressPollInterval,
                           repeating: ForkMacBackupAgentTuning.progressPollInterval, leeway: .milliseconds(200))
            timer.setEventHandler { [weak self] in self?.poll() }
            timer.resume()
            pollTimer = timer
        } else {
            pollTimer?.cancel()
            pollTimer = nil
        }
    }

    private func poll() {
        let now = Date()
        perform(machine.handle(.tick, now: now))
        if machine.isBackingUp, let extras, let source = machine.run?.current?.source {
            // The source's counters plus the bytes really sent (the task's
            // « Uploaded Bytes »: the control API's count stays 0).
            extras.liveProgress(of: source) { [weak self] result in
                guard let self else { return }
                switch result {
                case .success(let live):
                    self.perform(self.machine.handle(.live(live?.status, uploaded: live?.uploadedBytes,
                                                           taskID: live?.status.currentTask), now: Date()))
                case .failure(let error): self.perform(self.machine.handle(.progressFailed(error), now: Date()))
                }
                self.publish()
            }
        } else if machine.isBackingUp, let engine {
            engine.progress { [weak self] result in
                guard let self else { return }
                switch result {
                case .success(let response): self.perform(self.machine.handle(.progress(response), now: Date()))
                case .failure(let error): self.perform(self.machine.handle(.progressFailed(error), now: Date()))
                }
                self.publish()
            }
        } else {
            publish()
        }
        syncPolling()
    }

    // MARK: Events

    private func conditionsChanged() {
        let now = Date()
        chain.network = {
            switch watch.network {
            case .available: return true
            case .none: return false
            case .unknown: return nil
            }
        }()
        if machine.isBackingUp, ForkMacBackupPlanner.meetingStopsRun(settings: settings, conditions: conditions()) {
            perform(machine.handle(.meetingStarted, now: now))
        }
        if case .available = watch.network, peerOnline == false { peerCheckedAt = nil }
        scheduleEvaluate()
    }

    private func didWake() {
        let now = Date()
        timeline.append(.didWake, at: now)
        wokeAt = now
        peerCheckedAt = nil
        otherEngineCheckedAt = nil
        perform(machine.handle(.woke, now: now))
        // The network comes back a few seconds after the wake.
        queue.asyncAfter(deadline: .now() + 5) { [weak self] in self?.evaluate() }
    }

    private func readCommands() {
        guard running else { return }
        let manager = FileManager.default
        let names = (try? manager.contentsOfDirectory(atPath: paths.commands.path)) ?? []
        let files = names.map { name in
            (name: name, data: try? Data(contentsOf: paths.commands.appendingPathComponent(name, isDirectory: false)))
        }
        let inbox = ForkMacBackupAgentIPCSupport.inbox(files, now: Date())
        for name in inbox.delete {
            try? manager.removeItem(at: paths.commands.appendingPathComponent(name, isDirectory: false))
        }
        for file in inbox.run { apply(file) }
    }

    private func apply(_ file: ForkMacBackupCommandFile) {
        let now = Date()
        switch file.command {
        case .reloadSettings:
            reloadSettings()
            return
        case .cancel where updateHold:
            // The updater's clean stop, recorded as such.
            perform(machine.handle(.stop(.appUpdate), now: now))
        default:
            perform(machine.handle(.command(file.command, origin: file.origin), now: now))
        }
        notePause(now: now)
        scheduleEvaluate()
    }

    private func reloadSettings() {
        guard running, !stopping else { return }
        CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication)
        let new = ForkMacBackupAgentSettings { [defaults] in defaults.object(forKey: $0) }
        let old = settings
        settings = new
        if new.repository != old.repository {
            connectedKey = nil
            wrongRepository = false
            peerOnline = nil
            peerCheckedAt = nil
            chain = ForkMacBackupChainProbe()
            reconciledAt = nil
            engineTriedAt = nil
        }
        if new.sources != old.sources || new.iCloud != old.iCloud {
            prescans = [:]
            restartFSEvents()
        }
        engineTriedAt = engine == nil ? nil : engineTriedAt
        perform(machine.handle(.configure(new), now: Date()))
        if !new.enabled {
            disabled()
            return
        }
        scheduleEvaluate()
    }

    private func restartFSEvents() {
        // Our own folder (state, journals, Kopia's cache) is never a change to protect.
        fsevents.start(sources: settings.enabled ? settings.sources : [], ignoredPrefixes: [paths.root.path])
    }

    private func housekeeping() {
        guard running, !stopping else { return }
        let now = Date()
        timeline.forget(before: now.addingTimeInterval(-ForkMacBackupSlotTimeline.memory))
        // A new build installed in place: idle, the agent moves to it.
        if host == .agent, !machine.isBusy, let running = runningBuild, let installed = installedBuild(), installed != running {
            shutdown(.appUpdate) { [weak self] in self?.onExitRequest?(75) }
            return
        }
        if !machine.isBusy {
            reconcileIfDue(force: false)
            measureRepositoryIfDue(now: now)
            recordMaintenanceIfDue(now: now)
        }
        publish()
    }

    private func installedBuild() -> String? {
        let info = Bundle.main.bundleURL.appendingPathComponent("Contents/Info.plist", isDirectory: false)
        guard let data = try? Data(contentsOf: info),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
        return plist["CFBundleVersion"] as? String
    }

    /// `snapshot list` says what still exists (retention), at start and every 6 h.
    private func reconcileIfDue(force: Bool) {
        guard let engine, connectedKey != nil, !machine.isBusy else { return }
        let now = Date()
        if !force, let reconciledAt, now.timeIntervalSince(reconciledAt) < 6 * 3_600 { return }
        reconciledAt = now
        engine.listSnapshots(source: nil) { [weak self] result in
            guard let self, case .success(let manifests) = result else { return }
            self.proofs.reconcile(with: manifests, paths: self.settings.sources.map(\.path),
                                  identity: self.settings.repository?.clientIdentity, iCloud: self.settings.iCloud,
                                  now: Date())
            self.saveProofs()
            self.publish()
            self.writeMissingFailureLists(manifests)
        }
    }

    /// A partial snapshot whose complete list of failures was never written
    /// (the agent stopped meanwhile): asked again, named in `errors/`.
    private func writeMissingFailureLists(_ manifests: [ForkMacBackupKopia.SnapshotManifest]) {
        guard let extras else { return }
        let missing = manifests.filter { manifest in
            guard let proof = proofs.proofs[manifest.id], proof.isPartial else { return false }
            return !FileManager.default.fileExists(atPath: paths.errorsFile(manifestID: manifest.id).path)
        }
        for manifest in missing.suffix(5) {
            extras.failures(of: manifest, taskID: nil) { [weak self] result in
                guard let self, case .success(let failures) = result,
                      let data = try? ForkMacBackupJSON.encoder.encode(failures) else { return }
                PrivateFileStore.write(data, to: self.paths.errorsFile(manifestID: manifest.id))
            }
        }
    }

    /// Kopia's server runs the maintenance itself (this Mac owns it): its
    /// runs go into the history as they happen, read every few hours.
    private func recordMaintenanceIfDue(now: Date) {
        guard let extras, connectedKey != nil else { return }
        if let maintenanceCheckedAt, now.timeIntervalSince(maintenanceCheckedAt) < ForkMacBackupAgentTuning.maintenanceRecheck {
            return
        }
        maintenanceCheckedAt = now
        extras.maintenanceInfo { [weak self] result in
            guard let self, case .success(let info) = result, let end = info.lastRun else { return }
            let recorded = self.runs.last { $0.kind == .maintenance }?.end
            guard recorded.map({ end.timeIntervalSince($0) > 1 }) ?? true else { return }
            let record = ForkMacBackupRunRecord(kind: .maintenance, trigger: .agent, start: end, end: end,
                                                outcome: info.lastRunSucceeded == false ? .failed : .complete,
                                                failure: info.lastRunSucceeded == false ? .other : nil)
            self.append(record, to: self.paths.runs)
            self.runs.append(record)
        }
    }

    /// The repository's physical size, once a day.
    private func measureRepositoryIfDue(now: Date) {
        guard let engine, connectedKey != nil else { return }
        if let blobStatsAt, now.timeIntervalSince(blobStatsAt) < 86_400 { return }
        blobStatsAt = now
        engine.blobStats { [weak self] result in
            guard let self, case .success(let stats) = result else { return }
            self.repositoryBytes = stats.totalBytes
            self.repositoryMeasuredAt = stats.measuredAt
            self.append(ForkMacBackupCapacitySample(kind: .physical, bytes: stats.totalBytes, date: stats.measuredAt,
                                                    source: "blobStats"), to: self.paths.capacity)
            self.publish()
        }
    }

    // MARK: Actions

    private func perform(_ actions: [ForkMacBackupMachine.Action]) {
        for action in actions { perform(action) }
    }

    private func feed(_ event: ForkMacBackupMachine.Event) {
        perform(machine.handle(event, now: Date()))
        syncPolling()
        publish()
    }

    private func perform(_ action: ForkMacBackupMachine.Action) {
        switch action {
        case .checkChain:
            checkChain()
        case .applyPolicy(let source):
            applyPolicy(source)
        case .triggerSnapshot(let source):
            engine?.startSnapshot(source) { [weak self] result in
                guard let self else { return }
                switch result {
                case .success: self.feed(.snapshotTriggered(source, nil))
                case .failure(let error): self.feed(.snapshotTriggered(source, error))
                }
            }
            if engine == nil { feed(.snapshotTriggered(source, .engineMissing)) }
        case .cancelSnapshot(let source):
            engine?.cancelSnapshot(source) { _ in }
        case .conclude(let source, let startedAt, let taskID):
            if let extras {
                // The manifest found again (incomplete ones too) and EVERY failure named.
                extras.conclude(source, startedAt: startedAt, taskID: taskID, iCloud: settings.iCloud) { [weak self] result in
                    self?.feed(.concluded(source, result))
                }
                return
            }
            guard let engine else {
                feed(.listed(source, .failure(.engineMissing)))
                return
            }
            engine.listSnapshots(source: source) { [weak self] result in self?.feed(.listed(source, result)) }
        case .setThrottle(let limit):
            engine?.setThrottle(uploadBytesPerSecond: limit) { _ in }
        case .keepAwake(let on):
            let language = defaults.string(forKey: DefaultsKey.language).flatMap(AppLanguage.init(rawValue:))
                ?? .systemDefault
            keepAwake.set(on, reason: ForkMacBackupAgentStrings.strings(language).keepAwakeReason)
        case .runStarted(let id, let trigger, _):
            // « Sauvegarder maintenant » at normal priority, the planner's runs as chosen.
            extras?.priority = settings.enginePriority(for: trigger)
            runStarted(id: id)
        case .runEnded(let summary):
            runEnded(summary)
            extras?.priority = settings.enginePriority(for: .scheduled)
        case .startVerify(let level):
            startVerify(level)
        case .cancelVerify:
            verifyHandle?.cancel()
        case .verifyEnded(let level, let trigger, let start, let result):
            verifyEnded(level: level, trigger: trigger, start: start, result: result)
        case .replan:
            scheduleEvaluate()
        case .requestRun(let origin):
            manualRequest = origin
            scheduleEvaluate()
        case .publish:
            publish(force: true)
        }
    }

    private func checkChain() {
        let started = Date()
        guard engine != nil, let repository = settings.repository else {
            feed(.chainChecked(.engineMissing, nodeID: settings.chain.first { $0.kind == .mac }?.id))
            return
        }
        if watch.network == .none {
            chain.network = false
            chain.checkedAt = started
            feed(.chainChecked(.unreachable("no network"), nodeID: settings.chain.first { $0.kind == .network }?.id))
            return
        }
        if repository.peer != nil, peerOnline == false {
            chain.checkedAt = started
            feed(.chainChecked(.unreachable("Tailscale peer offline"),
                               nodeID: settings.chain.first { $0.kind == .tailscale }?.id))
            return
        }
        // One answer, at the latest after `fork.macbackup.timeout.repositorySeconds`.
        let answered = ForkMacBackupFlag()
        let fail: (ForkMacBackupEngineError) -> Void = { [weak self] error in
            guard answered.setOnce() else { return }
            self?.chainFailed(error, at: started)
        }
        queue.asyncAfter(deadline: .now() + settings.repositoryTimeout) { fail(.timeout) }
        ensureConnected { [weak self] error in
            guard let self else { return }
            if let error { return fail(error) }
            self.engine?.repositoryStatus { [weak self] result in
                guard let self else { return }
                switch result {
                case .success(let status):
                    if let found = status.uniqueIDHex, !repository.accepts(uniqueID: found) {
                        return fail(.wrongRepository(found: found))
                    }
                    guard answered.setOnce() else { return }
                    self.chain.macReady = true
                    self.chain.repository = .ok(latencyMs: Int(Date().timeIntervalSince(started) * 1_000))
                    self.chain.checkedAt = Date()
                    self.feed(.chainChecked(nil, nodeID: nil))
                case .failure(let error):
                    if error == .notConnected { self.connectedKey = nil }
                    fail(error)
                }
            }
        }
    }

    private func chainFailed(_ error: ForkMacBackupEngineError, at date: Date) {
        chain.checkedAt = Date()
        switch error {
        case .wrongRepository:
            wrongRepository = true
            chain.repository = .wrongRepository
        case .authentication:
            chain.repository = .authentication
        case .unreachable, .timeout, .notConnected, .serverUnavailable:
            chain.repository = .unreachable
        case .engineMissing:
            chain.macReady = false
        case .kopia, .decoding, .other, .canceled:
            break
        }
        feed(.chainChecked(error, nodeID: chain.brokenNodeID(settings.chain)))
    }

    private func applyPolicy(_ source: ForkMacBackupSource) {
        guard let engine else {
            feed(.policyApplied(source, .failed(.engineMissing)))
            return
        }
        prescan(source) { [weak self] extra in
            guard let self else { return }
            let rules = ForkMacBackupPolicyRules(source: source, extraRules: extra, retention: self.settings.retention)
            engine.readPolicy(of: source) { [weak self] current in
                guard let self else { return }
                if case .success(let existing) = current, existing == rules {
                    self.feed(.policyApplied(source, .matched))
                    return
                }
                engine.applyPolicy(rules, to: source) { [weak self] result in
                    switch result {
                    case .success(let readBack): self?.feed(.policyApplied(source, readBack == rules ? .matched : .mismatched))
                    case .failure(let error): self?.feed(.policyApplied(source, .failed(error)))
                    }
                }
            }
        }
    }

    /// The source's pre-scan (decision 1 of 22/10, plan §4.4), with the
    /// Engine's walker: its sparse disk images and cloud-only files become
    /// the run's extra rules, and what it keeps is measured at its REAL size
    /// (allocated bytes). Trusted 6 h; stopped with the run.
    private func prescan(_ source: ForkMacBackupSource, completion: @escaping ([String]) -> Void) {
        if let cached = prescans[source.path],
           Date().timeIntervalSince(cached.date) < ForkMacBackupAgentTuning.prescanLifetime {
            completion(cached.rules)
            return
        }
        let queue = self.queue
        let iCloud = settings.iCloud
        let home = NSHomeDirectory()
        let cancel = ForkMacBackupFlag()
        prescanCancel = cancel
        DispatchQueue.global(qos: .utility).async {
            let usage = ForkMacBackupContentScan.scan(root: URL(fileURLWithPath: source.path, isDirectory: true),
                                                      matcher: ForkMacBackupRunRules.matcher(for: source),
                                                      collectDataless: iCloud == .local, topFolders: 0,
                                                      isCanceled: { cancel.isSet })
            let rules = ForkMacBackupRunRules.extra(for: source, usage: usage, iCloud: iCloud, home: home)
            queue.async { [weak self] in
                guard let self else { return }
                if !usage.canceled {
                    self.prescans[source.path] = Prescan(date: Date(), rules: rules, realBytes: usage.allocatedBytes)
                }
                completion(rules)
            }
        }
    }

    /// The server's process: the engine's own word, else `server.json`.
    private var serverPID: pid_t? {
        if let pid = extras?.serverProcessID { return pid }
        guard let data = try? Data(contentsOf: paths.serverInfo),
              let info = try? ForkMacBackupJSON.decoder.decode(ForkMacBackupServerInfo.self, from: data) else { return nil }
        return info.pid
    }

    private func runStarted(id: UUID) {
        let now = Date()
        timeline.append(.runStarted, at: now)
        book.runStarted(at: now, runID: id)
        watch.readPower(now: now)
        runCostStart = (serverPID.flatMap(ForkMacBackupCostMeter.read(pid:)), watch.batteryPercent.map(Double.init), watch.onAC)
        runStartEvent = fsevents.currentEventID()
        syncPolling()
    }

    private func runEnded(_ summary: ForkMacBackupMachine.Summary) {
        let now = Date()
        timeline.append(.runEnded, at: now)
        watch.readPower(now: now)
        let start = runCostStart
        runCostStart = nil
        let cost = ForkMacBackupCostMeter.difference(start: start?.reading,
                                                     end: serverPID.flatMap(ForkMacBackupCostMeter.read(pid:)))
        let drop = (start?.onAC ?? true) ? nil : ForkMacBackupCostSupport.batteryDrop(
            samples: watch.batterySamples, start: summary.start, end: summary.end, startPercent: start?.percent,
            endPercent: watch.batteryPercent.map(Double.init))
        let record = ForkMacBackupRunRecord(id: summary.id, kind: .backup, trigger: summary.trigger, start: summary.start,
                                            end: summary.end, bytesSent: summary.bytesSent,
                                            bytesRead: cost?.bytesRead ?? 0, cpuSeconds: cost?.cpuSeconds ?? 0,
                                            batteryDrop: drop, onBattery: !(start?.onAC ?? true), proofs: summary.proofs,
                                            outcome: summary.outcome, failure: summary.failure,
                                            stopReason: summary.stopReason)
        append(record, to: paths.runs)
        runs.append(record)
        if runs.count > 500 { runs.removeFirst(runs.count - 500) }
        if let slot = book.runEnded(summary.result, runID: summary.id, canceledByPerson: summary.stopReason == .user) {
            append(slot, to: paths.slots)
        }
        if !summary.proofs.isEmpty {
            // What the pre-scan measured is the run's real size on disk.
            let measured = summary.proofs.map { proof -> ForkMacBackupSnapshotProof in
                var proof = proof
                if proof.incomplete == nil, let real = prescans[proof.sourcePath]?.realBytes { proof.realBytes = real }
                return proof
            }
            proofs.record(measured, now: now)
            saveProofs()
            for proof in measured where proof.isPartial {
                if let data = try? ForkMacBackupJSON.encoder.encode(proof.failures) {
                    PrivateFileStore.write(data, to: paths.errorsFile(manifestID: proof.manifestID))
                }
            }
            let protected = settings.sources.compactMap { proofs.last(of: $0.path)?.diskBytes }.reduce(0, +)
            append(ForkMacBackupCapacitySample(kind: .real, bytes: protected, date: now, source: "snapshot"), to: paths.capacity)
        }
        if summary.bytesSent > 0 {
            append(ForkMacBackupCapacitySample(kind: .sent, bytes: summary.bytesSent, date: now, source: "run"),
                   to: paths.capacity)
        }
        // A snapshot that protects the sources (complete, or partial with
        // its failures named) starts the count of changes again.
        switch summary.result {
        case .complete?, .partial?:
            if let event = runStartEvent { fsevents.completeSnapshot(startedAt: event, date: summary.start) }
        default:
            break
        }
        runStartEvent = nil
        rotate(paths.runs, as: ForkMacBackupRunRecord.self, now: now) { $0.end ?? $0.start }
        rotate(paths.slots, as: ForkMacBackupSlotRecord.self, now: now) { $0.due }
    }

    private func startVerify(_ level: ForkMacBackupVerifyLevel) {
        guard let engine else {
            feed(.verifyFinished(.failure(.engineMissing)))
            return
        }
        ensureConnected { [weak self] error in
            guard let self else { return }
            if let error {
                self.feed(.verifyFinished(.failure(error)))
                return
            }
            self.verifyHandle = engine.verify(level, progress: { [weak self] progress in
                guard let self else { return }
                self.perform(self.machine.handle(.verifyProgress(progress), now: Date()))
            }, completion: { [weak self] result in
                self?.verifyHandle = nil
                self?.feed(.verifyFinished(result))
            })
        }
    }

    private func verifyEnded(level: ForkMacBackupVerifyLevel, trigger: ForkMacBackupTrigger, start: Date,
                             result: ForkMacBackupEngineResult<ForkMacBackupVerifyReport>) {
        let now = Date()
        var record = ForkMacBackupRunRecord(kind: .verify, trigger: trigger, start: start, end: now, outcome: .failed,
                                            verifyLevel: level)
        switch result {
        case .success(let report):
            record.end = report.end
            record.outcome = report.succeeded ? .complete : .failed
            record.failure = report.succeeded ? nil : .other
            if report.succeeded {
                var percent: Double?
                if case .contentSample(let value) = level { percent = value }
                if case .full = level { percent = 100 }
                proofs.raise(report.manifestIDs, to: level.proofLevel, at: report.end, percent: percent)
                saveProofs()
            }
        case .failure(let error):
            record.outcome = error == .canceled ? .canceled : .failed
            record.failure = error == .canceled ? nil : error.runFailure
            record.stopReason = error == .canceled ? .user : nil
        }
        append(record, to: paths.runs)
        runs.append(record)
    }

    // MARK: Publishing

    private func presentation(now: Date) -> ForkMacBackupPresentation {
        ForkMacBackupPresenter.presentation(machine, context: .init(settings: settings, proofs: proofs, chain: chain,
                                                                    pendingChanges: fsevents.summary?.total, runs: runs,
                                                                    repositoryBytes: repositoryBytes,
                                                                    repositoryMeasuredAt: repositoryMeasuredAt),
                                            now: now)
    }

    /// Writes `state.json` (atomic, 0600) and posts the notification, at the
    /// cadence the lease asks for.
    private func publish(force: Bool = false) {
        let now = Date()
        let current = presentation(now: now)
        let leaseDate = (try? FileManager.default.attributesOfItem(atPath: paths.viewerLease.path))?[.modificationDate] as? Date
        guard ForkMacBackupAgentIPCSupport.shouldPublish(current, last: lastPresentation, lastWrittenAt: lastWrittenAt,
                                                         leaseModifiedAt: leaseDate, now: now, force: force) else { return }
        let file = ForkMacBackupStateFile(presentation: current, writtenAt: now, agentPID: getpid(), agentBuild: runningBuild)
        guard let data = file.encoded(), PrivateFileStore.write(data, to: paths.state) else { return }
        lastPresentation = current
        lastWrittenAt = now
        notify_post(notify.state)
    }
}
