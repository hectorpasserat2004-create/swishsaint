// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// The ONE thing every view reads (island, tile, settings, window, Command
/// Bar): written by the agent into `state.json`, published by
/// `ForkMacBackupStatusModel`. Language-free: the words come from
/// `ForkMacBackupStrings` at display time. A view never reads the disk, it
/// reads this.
///
/// Honesty rules, enforced here so no view can break them:
/// - `fraction` is nil while scanning (never a fake percentage);
/// - `progress.eta` stays nil until the agent finds Kopia's estimate stable;
/// - every size is a real size (decision 1 of 22/10).
struct ForkMacBackupPresentation: Codable, Equatable {
    /// The colour of the state: calm (grey, white), teal (protected or
    /// running), orange (needs a look), red (failed or chain broken).
    enum Tone: String, Codable, CaseIterable {
        case calm
        case teal
        case orange
        case red
    }

    /// The live figures of the operation running.
    struct Progress: Codable, Equatable {
        /// Read so far (hashed + cached), real bytes.
        var bytesDone: Int64
        /// Kopia's estimate; nil until it has one.
        var bytesTotal: Int64?
        var bytesUploaded: Int64
        var files: Int64
        var filesTotal: Int64?
        /// Sliding mean over 10 s.
        var bytesPerSecond: Double?
        /// Nil until the estimate has been stable for 30 s.
        var eta: TimeInterval?
        var currentPath: String?
        var errors: Int

        init(bytesDone: Int64 = 0, bytesTotal: Int64? = nil, bytesUploaded: Int64 = 0, files: Int64 = 0,
             filesTotal: Int64? = nil, bytesPerSecond: Double? = nil, eta: TimeInterval? = nil,
             currentPath: String? = nil, errors: Int = 0) {
            self.bytesDone = bytesDone
            self.bytesTotal = bytesTotal
            self.bytesUploaded = bytesUploaded
            self.files = files
            self.filesTotal = filesTotal
            self.bytesPerSecond = bytesPerSecond
            self.eta = eta
            self.currentPath = currentPath
            self.errors = errors
        }
    }

    /// One snapshot, as a line shows it.
    struct SnapshotSummary: Codable, Equatable {
        var manifestID: String
        var date: Date
        var level: ForkMacBackupProofLevel
        /// Real read errors (0 for a complete one).
        var failures: Int
        var bytes: Int64

        init(manifestID: String, date: Date, level: ForkMacBackupProofLevel, failures: Int = 0, bytes: Int64 = 0) {
            self.manifestID = manifestID
            self.date = date
            self.level = level
            self.failures = failures
            self.bytes = bytes
        }
    }

    enum SourceState: String, Codable, CaseIterable {
        case idle
        case waiting
        case running
        case done
        case partial
        case failed
    }

    /// One source: always its last snapshot and its last complete one
    /// together (plan §5.2).
    struct SourceStatus: Codable, Equatable, Identifiable {
        var path: String
        var state: SourceState
        var last: SnapshotSummary?
        var lastComplete: SnapshotSummary?

        var id: String { path }
        var proof: ForkMacBackupProofLevel? { last?.level }
        var displayName: String { ForkMacBackupSource(path: path).displayName }

        init(path: String, state: SourceState = .idle, last: SnapshotSummary? = nil, lastComplete: SnapshotSummary? = nil) {
            self.path = path
            self.state = state
            self.last = last
            self.lastComplete = lastComplete
        }
    }

    enum NodeState: String, Codable, CaseIterable {
        case ok
        /// Answers, over 3 s.
        case slow
        case broken
        case unknown
    }

    /// A chain node's last measure, matched to the profile's node by `id`.
    struct ChainStatus: Codable, Equatable, Identifiable {
        var id: String
        var kind: ForkMacBackupChainNode.Kind
        /// The profile's own title; empty: the kind's word.
        var title: String
        var state: NodeState
        var latencyMs: Int?
        var checkedAt: Date?

        init(id: String, kind: ForkMacBackupChainNode.Kind, title: String = "", state: NodeState = .unknown,
             latencyMs: Int? = nil, checkedAt: Date? = nil) {
            self.id = id
            self.kind = kind
            self.title = title
            self.state = state
            self.latencyMs = latencyMs
            self.checkedAt = checkedAt
        }

        func displayTitle(_ text: ForkMacBackupStrings) -> String {
            title.isEmpty ? kind.title(text) : title
        }
    }

    /// The rhythm, as `fork.macbackup.schedule.*` sets it.
    enum Rhythm: Codable, Equatable {
        /// `about`: the interval the Automatic rhythm currently keeps.
        case automatic(about: TimeInterval?)
        case interval(hours: Int)
        /// « 13:00 », « 21:00 » (24-hour storage, shown in the locale's clock).
        case times([String])
        case both(hours: Int, times: [String])
    }

    struct Capacity: Codable, Equatable {
        var protectedBytes: Int64?
        var lastSentBytes: Int64?
        var repositoryBytes: Int64?
        var nasFreeBytes: Int64?
        var measuredAt: Date?

        init(protectedBytes: Int64? = nil, lastSentBytes: Int64? = nil, repositoryBytes: Int64? = nil,
             nasFreeBytes: Int64? = nil, measuredAt: Date? = nil) {
            self.protectedBytes = protectedBytes
            self.lastSentBytes = lastSentBytes
            self.repositoryBytes = repositoryBytes
            self.nasFreeBytes = nasFreeBytes
            self.measuredAt = measuredAt
        }
    }

    /// What a backup costs on average (the Automatic rhythm's measure).
    struct Cost: Codable, Equatable {
        var averageDuration: TimeInterval
        /// Battery points; nil when never measured on battery.
        var averageBatteryDrop: Double?
        var averageSent: Int64
        var samples: Int
    }

    /// The last failure worth a banner in the section.
    struct ErrorLine: Codable, Equatable {
        var cause: ForkMacBackupRunFailure
        /// The broken node, for `chainBroken`.
        var nodeID: String?
        var at: Date
        /// Kopia's text, for the diagnostics only.
        var message: String?

        init(cause: ForkMacBackupRunFailure, nodeID: String? = nil, at: Date, message: String? = nil) {
            self.cause = cause
            self.nodeID = nodeID
            self.at = at
            self.message = message
        }
    }

    var phase: ForkMacBackupPhase
    var progress: Progress?
    var sources: [SourceStatus]
    /// Files changed since the last complete snapshot (FSEvents), nil when
    /// not counted.
    var pendingChanges: Int?
    var chain: [ChainStatus]
    var nextRun: Date?
    var rhythm: Rhythm
    var capacity: Capacity
    var cost: Cost?
    var lastError: ErrorLine?
    /// The « Ralentir » switch is on.
    var slowDown: Bool
    var updatedAt: Date

    init(phase: ForkMacBackupPhase, progress: Progress? = nil, sources: [SourceStatus] = [], pendingChanges: Int? = nil,
         chain: [ChainStatus] = [], nextRun: Date? = nil, rhythm: Rhythm = .automatic(about: nil),
         capacity: Capacity = Capacity(), cost: Cost? = nil, lastError: ErrorLine? = nil, slowDown: Bool = false,
         updatedAt: Date = Date()) {
        self.phase = phase
        self.progress = progress
        self.sources = sources
        self.pendingChanges = pendingChanges
        self.chain = chain
        self.nextRun = nextRun
        self.rhythm = rhythm
        self.capacity = capacity
        self.cost = cost
        self.lastError = lastError
        self.slowDown = slowDown
        self.updatedAt = updatedAt
    }

    /// Before the agent ever wrote a state.
    static let unknown = ForkMacBackupPresentation(phase: .notConfigured, updatedAt: .distantPast)

    // MARK: Derived

    /// 0…1, nil whenever a percentage would be a guess: while scanning,
    /// without an estimate, or in a phase without a byte count.
    var fraction: Double? {
        guard phase.hasDeterminateProgress, let progress, let total = progress.bytesTotal, total > 0 else { return nil }
        return min(1, max(0, Double(progress.bytesDone) / Double(total)))
    }

    /// The newest snapshot over every source.
    var lastBackup: SnapshotSummary? {
        sources.compactMap(\.last).max { $0.date < $1.date }
    }

    /// The oldest of the sources' last snapshots: the age of the data
    /// protected, the conservative one (plan §5.2). Nil while one source has
    /// none.
    var protectedSince: Date? {
        let lasts = sources.map(\.last)
        guard !lasts.isEmpty, lasts.allSatisfy({ $0 != nil }) else { return nil }
        return lasts.compactMap { $0?.date }.min()
    }

    /// The newest complete snapshot over every source.
    var lastComplete: SnapshotSummary? {
        sources.compactMap(\.lastComplete).max { $0.date < $1.date }
    }

    var hasBrokenNode: Bool { chain.contains { $0.state == .broken } }

    var tone: Tone {
        switch phase {
        case .off, .notConfigured, .paused, .maintaining:
            return .calm
        case .waiting(let reason, _):
            return reason.needsAction ? .orange : .calm
        case .checkingChain, .preparing, .scanning, .uploading, .slowed, .concluding, .restoring, .verifying:
            return .teal
        case .finished(.partial):
            return .orange
        case .finished(.failed):
            return .red
        case .ready, .finished(.complete), .finished(.nothingToDo):
            if lastError != nil || hasBrokenNode { return .red }
            if sources.contains(where: { $0.state == .partial }) { return .orange }
            return protectedSince == nil ? .calm : .teal
        }
    }

    // MARK: Words

    /// The state in a few words (island, ≤ 28 characters once filled).
    func headline(_ text: ForkMacBackupStrings, language: AppLanguage, locale: Locale, now: Date = Date(),
                  reading: ForkMacBackupReading = .percent) -> String {
        switch phase {
        case .off: return text.off
        case .notConfigured: return text.notConfigured
        case .ready, .finished(.nothingToDo): return restingHeadline(text, locale: locale, now: now)
        case .waiting(let reason, _): return reason.title(text)
        case .checkingChain: return text.checkingChain
        case .preparing: return text.preparing
        case .scanning: return text.scanning
        case .uploading:
            return String(format: text.running, compactValue(text, locale: locale, reading: reading))
        case .slowed:
            return String(format: text.slowed, compactValue(text, locale: locale, reading: reading))
        case .paused(let until):
            guard let until else { return text.paused }
            return String(format: text.pausedUntil, ForkMacBackupFormat.time(until, locale: locale))
        case .concluding: return text.concluding
        case .finished(.complete): return text.finished
        case .finished(.partial(let files)): return text.partial(files, language: language)
        case .finished(.failed): return text.failed
        case .restoring: return text.restoring
        case .verifying: return text.verifying
        case .maintaining: return text.maintaining
        }
    }

    private func restingHeadline(_ text: ForkMacBackupStrings, locale: Locale, now: Date) -> String {
        if let since = protectedSince {
            return String(format: text.protectedAgo, ForkMacBackupFormat.age(now.timeIntervalSince(since), locale: locale))
        }
        if let nextRun { return String(format: text.nextAt, ForkMacBackupFormat.time(nextRun, locale: locale)) }
        return text.protected
    }

    /// The closed island's right wing and the tile: « 42 % », « 2 min », or
    /// « calcul… » while there is nothing honest to show.
    func compactValue(_ text: ForkMacBackupStrings, locale: Locale, reading: ForkMacBackupReading = .percent) -> String {
        switch reading {
        case .remaining:
            if let eta = progress?.eta { return ForkMacBackupFormat.duration(eta, locale: locale) }
        case .percent:
            break
        }
        if let fraction { return ForkMacBackupFormat.percent(fraction, locale: locale) }
        return text.calculating
    }

    /// « 1,3 Go / 3,1 Go · 18 Mo/s · reste 2 min » (section, window).
    func progressLine(_ text: ForkMacBackupStrings, locale: Locale) -> String? {
        guard let progress else { return nil }
        var parts: [String] = []
        let done = ForkMacBackupFormat.bytes(progress.bytesDone, locale: locale)
        if let total = progress.bytesTotal, fraction != nil {
            parts.append("\(done) / \(ForkMacBackupFormat.bytes(total, locale: locale))")
        } else {
            parts.append(done)
        }
        if let rate = ForkMacBackupFormat.rate(progress.bytesPerSecond, locale: locale) { parts.append(rate) }
        if phase.hasDeterminateProgress {
            if let eta = progress.eta {
                parts.append(String(format: text.remaining, ForkMacBackupFormat.duration(eta, locale: locale)))
            } else {
                parts.append(text.calculating)
            }
        }
        return parts.joined(separator: " · ")
    }

    /// « Automatique · environ toutes les 2 h », « Toutes les 4 h ».
    func rhythmLine(_ text: ForkMacBackupStrings, locale: Locale) -> String {
        func every(_ hours: Int) -> String {
            String(format: text.rhythmEvery, ForkMacBackupFormat.age(TimeInterval(hours) * 3_600, locale: locale))
        }
        func at(_ times: [String]) -> String {
            String(format: text.rhythmTimes, times.map { Self.displayTime($0, locale: locale) }.joined(separator: ", "))
        }
        switch rhythm {
        case .automatic(let about):
            guard let about, about > 0 else { return text.rhythmAuto }
            return text.rhythmAuto + " · " + String(format: text.rhythmAbout, ForkMacBackupFormat.age(about, locale: locale))
        case .interval(let hours): return every(hours)
        case .times(let times): return at(times)
        case .both(let hours, let times): return every(hours) + " · " + at(times)
        }
    }

    /// « Sauvegarde moyenne : 3 min · 0,8 % de batterie · 1,2 Go envoyés »;
    /// nil before any measure.
    func costLine(_ text: ForkMacBackupStrings, locale: Locale) -> String? {
        guard let cost, cost.samples > 0 else { return nil }
        let battery = cost.averageBatteryDrop.map { ForkMacBackupFormat.batteryPoints($0, locale: locale) } ?? text.unknown
        return String(format: text.costLine, ForkMacBackupFormat.duration(cost.averageDuration, locale: locale), battery,
                      ForkMacBackupFormat.bytes(cost.averageSent, locale: locale))
    }

    /// A stored « HH:mm » in the locale's own clock; anything else as is.
    static func displayTime(_ stored: String, locale: Locale) -> String {
        let parts = stored.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, (0..<24).contains(parts[0]), (0..<60).contains(parts[1]) else { return stored }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        guard let date = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: parts[0],
                                                            minute: parts[1])) else { return stored }
        return ForkMacBackupFormat.time(date, locale: locale, timeZone: calendar.timeZone)
    }
}

/// The closed island's right wing (`fork.macbackup.island.reading`).
enum ForkMacBackupReading: String, Codable, CaseIterable {
    case percent
    case remaining

    static let fallback: ForkMacBackupReading = .percent
}

/// What the closed island shows (`fork.macbackup.island.compact`, decision 2
/// of 22/10): a backup running, or never. Never a delay or a problem.
enum ForkMacBackupCompactSetting: String, Codable, CaseIterable {
    case running
    case never

    static let fallback: ForkMacBackupCompactSetting = .running
}
