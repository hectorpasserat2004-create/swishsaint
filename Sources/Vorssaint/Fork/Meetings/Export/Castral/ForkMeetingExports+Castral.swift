// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation
import os

/// What the last look at a CRM found: the page's "Connected · 12 upcoming".
enum ForkCastralLink: Equatable {
    case connected(upcoming: Int, at: Date)
    case tokenRefused(at: Date)
    case offline(at: Date)
    case failed(status: Int, at: Date)

    var at: Date {
        switch self {
        case let .connected(_, at), let .tokenRefused(at), let .offline(at), let .failed(_, at): return at
        }
    }

    init(_ result: Result<[ForkCastralContract.Booking], ForkCastralClient.CallFailure>, now: Date) {
        switch result {
        case let .success(bookings):
            self = .connected(upcoming: bookings.filter { !$0.isBlocked && ($0.startAt ?? .distantPast) >= now }.count, at: now)
        case .failure(.token): self = .tokenRefused(at: now)
        case .failure(.network), .failure(.certificate): self = .offline(at: now)
        case let .failure(.refused(status, _)), let .failure(.server(status, _)), let .failure(.shape(status)):
            self = .failed(status: status, at: now)
        case .failure(.redirected), .failure(.uploadHost): self = .failed(status: 0, at: now)
        }
    }
}

/// The library's sheet before a send by hand: which appointment this
/// meeting was, among those around it, the likeliest first and chosen.
struct ForkCastralChoice: Identifiable, Equatable {
    let id = UUID()
    let folder: URL
    let target: String
    let name: String
    var startedAt: Date
    var recordedSeconds: Double?
    var bookings: [ForkCastralContract.Booking] = []
    var proposed: String?
    var loading = true
    var failure: ForkMeetingExportFailure?
}

/// A meeting in the CRM, as the island's Meetings page and the library's
/// row show it (lot G reads it here): the phase, and its share when known.
struct ForkCastralStatus: Equatable {
    let name: String
    let phase: ForkCastralPhase
    let progress: Double?
    /// The send failed before the server took it: why, beside its Retry.
    let failure: ForkMeetingExportFailure?
}

extension ForkMeetingExports {
    private static let castralLog = Logger(subsystem: "fork.meetings", category: "castral")
    /// The window "Connected · N upcoming" counts in, at most the server's.
    static let castralUpcomingWindow: TimeInterval = 30 * 86_400

    var castralConfig: ForkMeetingExporterConfig? { configs.first { $0.kind == .castral } }

    /// The page's and the menus' name: the profile's, once read.
    func title(_ config: ForkMeetingExporterConfig, _ text: ForkMeetingStrings) -> String {
        guard config.kind == .castral else { return config.title(text) }
        return castralProfiles[config.id]?.displayName ?? text.castralKindName
    }

    /// Keychain queue, then the main thread: the profiles as stored.
    func refreshCastralProfiles(_ done: (() -> Void)?) {
        let ids = configs.filter { $0.kind == .castral }.map(\.id)
        guard !ids.isEmpty else {
            castralProfiles = [:]
            done?()
            return
        }
        let keychain = self.keychain
        keychainQueue.async { [self] in
            var read: [String: ForkCastralProfile] = [:]
            for id in ids {
                if case let .found(data) = keychain.read(ForkMeetingExporterConfig.profileAccount(id)),
                   case let .success(profile) = ForkCastralProfile.parse(data) {
                    read[id] = profile
                }
            }
            DispatchQueue.main.async { [self] in
                castralProfiles = read
                done?()
            }
        }
    }

    func castralExporter(_ config: ForkMeetingExporterConfig, request: ForkCastralRequest?,
                         key: String? = nil) -> ForkCastralExporter {
        let store = self.store
        var exporter = ForkCastralExporter(config: config, keychain: keychain, record: { [weak self] record, package in
            guard let folder = package.folder, let written = store.writeCastral(record, in: folder, id: package.sidecar.id) else {
                return false
            }
            DispatchQueue.main.async { self?.castralRecords[written.standardizedFileURL.path] = record }
            return true
        })
        exporter.trust = trust
        exporter.request = request
        return exporter
    }

    /// The share sent, published at most ten times a second.
    func castralProgressReporter(_ key: String) -> (Double) -> Void {
        let lock = NSLock()
        var last = Date.distantPast
        return { [weak self] share in
            let now = Date()
            let due = lock.withLock { () -> Bool in
                guard share >= 1 || now.timeIntervalSince(last) >= 0.1 else { return false }
                last = now
                return true
            }
            guard due else { return }
            DispatchQueue.main.async { self?.castralProgress[key] = share }
        }
    }

    /// A send ended: said in a notice, then followed on the server.
    func castralSent(_ folder: URL, config: ForkMeetingExporterConfig, failed: Bool) {
        let name = title(config, ForkMeetingStrings.current)
        refreshResults(folder)
        castralNoticed(folder, name, !failed)
        if !failed { castralTracker.follow(folder, target: config.id) }
    }

    // MARK: - The page

    enum ProfileImport: Equatable {
        case imported(id: String, serverChanged: Bool)
        case refused(ForkCastralProfile.Refusal)
        case keychainRefused
        case listUnconfirmed
    }

    /// "Import a Profile…": the profile goes to the Keychain, then the
    /// exporter to the list (manual, the profile's first author). One CRM
    /// at a time: a second profile replaces the first, and a new server
    /// erases the old token, which was its own.
    func importCastralProfile(_ data: Data, done: @escaping (ProfileImport) -> Void) {
        guard !listChanged else { return done(.listUnconfirmed) }
        let profile: ForkCastralProfile
        switch ForkCastralProfile.parse(data) {
        case let .success(read): profile = read
        case let .failure(refusal): return done(.refused(refusal))
        }
        let existing = castralConfig
        let id = existing?.id ?? UUID().uuidString
        let previous = existing.flatMap { castralProfiles[$0.id] }
        let serverChanged = previous.map { $0.origin != profile.origin || $0.uploadHost != profile.uploadHost } ?? false
        let keychain = self.keychain
        askKeychain({ () -> Bool in
            if serverChanged { keychain.delete(ForkMeetingExporterConfig.tokenAccount(id)) }
            return keychain.save(profile.encoded(), account: ForkMeetingExporterConfig.profileAccount(id))
        }) { [self] saved in
            guard saved else { return done(.keychainRefused) }
            var config = existing ?? ForkMeetingExporterConfig(id: id, kind: .castral)
            if config.author.map(profile.authors.contains) != true { config.author = profile.authors.first }
            config.speakers = config.speakers ?? ForkCastralContract.defaultSpeakers
            if existing == nil {
                guard store(configs + [config]) else { return done(.listUnconfirmed) }
            } else {
                update(config)
            }
            castralLinks[id] = nil
            refresh { done(.imported(id: id, serverChanged: serverChanged)) }
        }
    }

    enum TokenChange: Equatable {
        case saved
        case invalid
        case keychainRefused
    }

    /// The new token, written once at its Save, then checked.
    func saveCastralToken(_ id: String, token: String, done: @escaping (TokenChange) -> Void) {
        let typed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ForkCastralClient.isToken(typed) else { return done(.invalid) }
        let keychain = self.keychain
        askKeychain({ keychain.save(Data(typed.utf8), account: ForkMeetingExporterConfig.tokenAccount(id)) }) { [self] saved in
            guard saved else { return done(.keychainRefused) }
            refresh { [self] in
                testCastral(id)
                done(.saved)
            }
        }
    }

    /// "Test", and each display of the page a minute after the last look:
    /// the appointments of the coming month, counted.
    func testCastral(_ id: String, unlessCheckedWithin recent: TimeInterval = 0) {
        guard let config = config(id), config.kind == .castral, !castralChecking.contains(id),
              savedSecrets.contains(ForkMeetingExporterConfig.tokenAccount(id)) else { return }
        if recent > 0, let last = castralLinks[id]?.at, Date().timeIntervalSince(last) < recent { return }
        castralChecking.insert(id)
        let exporter = castralExporter(config, request: nil)
        // Not behind an hour of sound leaving on the export queue.
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let now = Date()
            let link: ForkCastralLink
            do {
                let client = try exporter.credentials()
                link = ForkCastralLink(try Self.blocking {
                    await client.targets(from: now, to: now.addingTimeInterval(Self.castralUpcomingWindow))
                }, now: now)
            } catch {
                link = (error as? ForkMeetingExportFailure) == .noSecret ? .tokenRefused(at: now) : .failed(status: 0, at: now)
            }
            DispatchQueue.main.async { [self] in
                castralChecking.remove(id)
                castralLinks[id] = link
            }
        }
    }

    // MARK: - The choice

    /// "Export To" a CRM: a deposit under way goes on (sent again, started,
    /// retried, followed) without a question; otherwise the sheet asks
    /// which appointment, the likeliest chosen.
    func askCastralChoice(_ folder: URL, _ config: ForkMeetingExporterConfig) {
        let name = title(config, ForkMeetingStrings.current)
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let read = store.sidecar(in: folder)
            guard case let .success(sidecar) = read else {
                return DispatchQueue.main.async { [self] in refuse(folder, config.id, .unreadable) }
            }
            if let record = ForkCastralRecord(json: sidecar.castral), record.target == config.id {
                return DispatchQueue.main.async { [self] in enqueue(folder, config, automatic: false) }
            }
            let startedAt = sidecar.startedAt ?? Date()
            var choice = ForkCastralChoice(folder: folder, target: config.id, name: name, startedAt: startedAt,
                                           recordedSeconds: sidecar.recordedSeconds)
            DispatchQueue.main.async { [self] in castralChoice = choice }
            let exporter = castralExporter(config, request: nil)
            do {
                let client = try exporter.credentials()
                let window = ForkCastralMatch.window(startedAt: startedAt, endedAt: sidecar.endedAt)
                switch try Self.blocking({ await client.targets(from: window.from, to: window.to) }) {
                case let .success(bookings):
                    choice.bookings = ForkCastralMatch.candidates(bookings, startedAt: startedAt)
                    choice.proposed = ForkCastralMatch.choose(bookings, meetCode: sidecar.meetCode, startedAt: startedAt,
                                                              endedAt: sidecar.endedAt)?.booking.id
                case let .failure(failure):
                    choice.failure = failure.exportFailure
                }
            } catch {
                choice.failure = error as? ForkMeetingExportFailure ?? .network
            }
            choice.loading = false
            let shown = choice
            DispatchQueue.main.async { [self] in
                // Only the sheet still open for that meeting.
                if castralChoice?.id == shown.id { castralChoice = shown }
            }
        }
    }

    func confirmCastralChoice(_ choice: ForkCastralChoice, booking: String, complement: String) {
        castralChoice = nil
        guard let config = config(choice.target), config.kind == .castral else { return }
        enqueue(choice.folder, config, automatic: false,
                request: ForkCastralRequest(bookingID: booking, complement: ForkCastralContract.complement(complement)))
    }

    // MARK: - Read by the island and the library

    /// What became of the meeting in the CRM, or `nil` when nothing went:
    /// for the island's Meetings page (lot G) and the library's row.
    func castralStatus(_ folder: URL) -> ForkCastralStatus? {
        guard let config = castralConfig else { return nil }
        let path = folder.standardizedFileURL.path
        let key = Self.key(folder, config.id)
        let name = title(config, ForkMeetingStrings.current)
        let failure = refusals[key] ?? result(folder, config.id).flatMap { $0.status == .failed ? $0.failure : nil }
        if pending.contains(key) {
            return ForkCastralStatus(name: name, phase: .sending(castralProgress[key]),
                                     progress: castralProgress[key], failure: nil)
        }
        if let record = castralRecords[path], record.target == config.id {
            let phase = ForkCastralPhase(record: record, followed: !castralResting.contains(path))
            let unsent = record.step != .started
            return ForkCastralStatus(name: name, phase: phase, progress: phase.progress(record),
                                     failure: unsent ? failure : nil)
        }
        guard let failure else { return nil }
        return ForkCastralStatus(name: name, phase: .failed, progress: nil, failure: failure)
    }

    /// "Open in <CRM>": the company's record, on the profile's own origin.
    func castralDashboard(_ folder: URL) -> URL? {
        guard let config = castralConfig, let profile = castralProfiles[config.id],
              let record = castralRecords[folder.standardizedFileURL.path], let company = record.company else { return nil }
        return profile.dashboardURL(companyID: company)
    }
}
