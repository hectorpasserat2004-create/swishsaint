// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import AVFoundation
import Foundation
import os

/// The appointment the person chose for a meeting, and what they said was
/// not recorded: what a send by hand takes from the choice.
struct ForkCastralRequest: Equatable {
    var bookingID: String
    var complement: String?
}

/// Sends a meeting's sound to a CRM of the recorder contract, attached to
/// its appointment, for the transcript and the report.
///
/// - **Each step is written in `meeting.json` as it happens**
///   (`ForkCastralRecord`): a quit while the sound leaves sends it again to
///   the same address, or opens a new deposit once that address is over
///   (B3); a failure after the sound arrived only starts it again (B5); the
///   server's `retry` only follows a sound that is there (S1).
/// - **The appointment** is the one the person chose; on its own, only a
///   sure one (`ForkCastralMatch.automatic`), read from the CRM at that
///   moment, never kept from an earlier offer.
/// - **The sound** is FLAC from the mix, 16 kHz or 8 kHz, its size measured
///   before anything opens on the server (`ForkCastralAudioPlan`).
/// - The profile and the token are read from the Keychain at the moment of
///   the send; the upload address stays there until the sound arrived.
struct ForkCastralExporter: ForkMeetingExporter {
    let config: ForkMeetingExporterConfig
    let keychain: ForkMeetingKeychain
    /// Writes the record in the meeting's `meeting.json`, wherever the
    /// meeting is now; `false` when it could not.
    let record: (ForkCastralRecord, ForkMeetingExportPackage) -> Bool
    var trust: ForkWebhookExporter.Trust = .system
    /// The recipe harness's own mapping of hosts; `nil` in the app.
    var route: ((URL) -> URL)?
    /// A send by hand: the appointment chosen.
    var request: ForkCastralRequest?
    var now: () -> Date = Date.init
    /// The server's own sentence of a call it refused, to show beside the
    /// failure (`castralSaid`); `nil` clears it.
    var said: (String?) -> Void = { _ in }
    var temporaryDirectory = FileManager.default.temporaryDirectory

    var id: String { config.id }
    var kind: ForkMeetingExportKind { .castral }
    var mode: ForkMeetingExportMode { config.mode }
    var isConfigured: Bool { (try? check()) != nil }

    private static let log = Logger(subsystem: "fork.meetings", category: "castral")
    /// The FLAC files' folders in the temporary folder: what a quit leaves
    /// there goes at the next launch.
    static let stagingPrefix = "fork.meetings.castral-"

    static func uploadAccount(_ deposit: String) -> String { "castral-upload#\(deposit)" }

    func check() throws {
        guard keychain.exists(ForkMeetingExporterConfig.profileAccount(id)) else { throw ForkMeetingExportFailure.castral(.profile) }
        guard !(config.author ?? "").isEmpty else { throw ForkMeetingExportFailure.castral(.author) }
        guard keychain.exists(ForkMeetingExporterConfig.tokenAccount(id)) else { throw ForkMeetingExportFailure.noSecret }
    }

    /// The profile and the token, read now.
    func credentials() throws -> ForkCastralClient {
        let profile: ForkCastralProfile
        switch keychain.read(ForkMeetingExporterConfig.profileAccount(id)) {
        case let .found(data):
            guard case let .success(read) = ForkCastralProfile.parse(data) else { throw ForkMeetingExportFailure.castral(.profile) }
            profile = read
        case .missing: throw ForkMeetingExportFailure.castral(.profile)
        case .failed: throw ForkMeetingExportFailure.keychain
        }
        switch keychain.read(ForkMeetingExporterConfig.tokenAccount(id)) {
        case let .found(data):
            let token = String(decoding: data, as: UTF8.self)
            guard ForkCastralClient.isToken(token) else { throw ForkMeetingExportFailure.noSecret }
            var client = ForkCastralClient(profile: profile, token: token, trust: trust)
            client.route = route
            return client
        case .missing: throw ForkMeetingExportFailure.noSecret
        case .failed: throw ForkMeetingExportFailure.keychain
        }
    }

    func export(_ package: ForkMeetingExportPackage, progress: @escaping (Double) -> Void) async throws -> ForkMeetingExportReceipt {
        let client = try credentials()
        guard let author = config.author, client.profile.authors.contains(author) else {
            throw ForkMeetingExportFailure.castral(.author)
        }
        let previous = ForkCastralRecord(json: package.sidecar.castral)
        let hasAddress = previous.map { keychain.exists(Self.uploadAccount($0.deposit)) } ?? false
        switch ForkCastralSteps.next(previous, target: id, hasAddress: hasAddress, now: now()) {
        case .follow:
            break
        case .retry:
            guard var record = previous, ForkCastralSteps.allowsRetry(record) else { break }
            if case let .failure(failure) = await client.retry(record.deposit) { throw refused(failure) }
            record.stage = .queued
            record.progress = ForkCastralContract.Stage.queued.progress
            record.error = nil
            record.checkedAt = now()
            try save(record, package)
        case .start:
            guard let record = previous else { break }
            try await start(record, client: client, package: package)
        case .upload:
            guard let record = previous else { break }
            try await upload(record, client: client, package: package, progress: progress)
        case let .reopen(abandoned):
            await client.abandon(abandoned)
            keychain.delete(Self.uploadAccount(abandoned))
            try await open(package, client: client, author: author, reusing: previous, progress: progress)
        case .open:
            try await open(package, client: client, author: author, reusing: nil, progress: progress)
        }
        return ForkMeetingExportReceipt(target: id, kind: .castral, at: now())
    }

    // MARK: - Steps

    /// A call refused: its sentence said, its failure thrown.
    private func refused(_ failure: ForkCastralClient.CallFailure) -> ForkMeetingExportFailure {
        said(failure.said)
        return failure.exportFailure
    }

    private func save(_ record: ForkCastralRecord, _ package: ForkMeetingExportPackage) throws {
        guard self.record(record, package) else { throw ForkMeetingExportFailure.unreadable }
    }

    /// The appointment, the sound, then a deposit opened for it.
    private func open(_ package: ForkMeetingExportPackage, client: ForkCastralClient, author: String,
                      reusing previous: ForkCastralRecord?, progress: @escaping (Double) -> Void) async throws {
        let sidecar = package.sidecar
        let startedAt = sidecar.startedAt ?? now()
        let (choice, complement) = try await appointment(package, client: client, previous: previous, startedAt: startedAt)

        let staging = temporaryDirectory.appendingPathComponent(ForkMeetingLeftovers.name(Self.stagingPrefix), isDirectory: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        let sound = try await write(package, limit: client.profile.maximumUploadBytes, staging: staging,
                                    format: previous?.format)
        let opening = ForkCastralContract.Opening(
            bookingID: choice.booking.id,
            fileName: client.profile.fileName(day: startedAt, who: choice.booking.company?.domain
                                                ?? choice.booking.detectedDomain ?? choice.booking.attendeeName,
                                              extension: ForkCastralAudioPlan.Format.fileExtension),
            mimeType: ForkCastralAudioPlan.Format.mimeType, bytes: sound.written.bytes,
            durationMilliseconds: Int64((sound.written.seconds * 1000).rounded()),
            speakers: config.speakers ?? ForkCastralContract.defaultSpeakers, author: author, complement: complement)
        let opened: ForkCastralContract.Opened
        switch await client.open(opening) {
        case let .success(value): opened = value
        case let .failure(failure):
            Self.log.error("deposit refused: \(failure.exportFailure.code, privacy: .public)")
            throw refused(failure)
        }
        // An answer naming another host is not followed: that deposit goes.
        guard client.profile.allowsUpload(to: opened.uploadURL) else {
            await client.abandon(opened.id)
            throw ForkMeetingExportFailure.castral(.uploadHost)
        }
        guard keychain.save(Data(opened.uploadURL.absoluteString.utf8), account: Self.uploadAccount(opened.id)) else {
            await client.abandon(opened.id)
            throw ForkMeetingExportFailure.keychain
        }
        var record = ForkCastralRecord(target: id, step: .uploading, deposit: opened.id)
        record.booking = choice.booking.id
        record.company = choice.booking.company?.id
        record.companyName = choice.booking.who
        record.bookingStart = choice.booking.startAt
        record.rule = choice.rule
        record.format = sound.format
        record.bytes = sound.written.bytes
        record.seconds = sound.written.seconds
        record.openedAt = now()
        record.engine = opened.engine
        do { try save(record, package) } catch {
            keychain.delete(Self.uploadAccount(opened.id))
            await client.abandon(opened.id)
            throw error
        }
        try await upload(record, client: client, package: package, progress: progress, file: sound.written)
    }

    /// The appointment of a send by hand, or a sure one on its own; the
    /// one an earlier deposit had, when opening again.
    private func appointment(_ package: ForkMeetingExportPackage, client: ForkCastralClient,
                             previous: ForkCastralRecord?, startedAt: Date) async throws
        -> (ForkCastralMatch.Choice, String?) {
        let window = ForkCastralMatch.window(startedAt: startedAt, endedAt: package.sidecar.endedAt)
        let bookings: [ForkCastralContract.Booking]
        switch await client.targets(from: window.from, to: window.to) {
        case let .success(list): bookings = list
        case let .failure(failure): throw refused(failure)
        }
        let wanted = request?.bookingID ?? (previous?.target == id ? previous?.booking : nil)
        if let wanted {
            // Still there, still taking one (B1): never a cancelled one.
            guard let booking = bookings.first(where: { $0.id == wanted }), !booking.isBlocked else {
                throw ForkMeetingExportFailure.castral(.noBooking)
            }
            return (ForkCastralMatch.Choice(booking: booking, rule: request != nil ? .chosen : previous?.rule ?? .chosen,
                                            unique: true), request?.complement)
        }
        guard package.automatic else { throw ForkMeetingExportFailure.castral(.uncertain) }
        let found = ForkCastralMatch.choose(bookings, meetCode: package.sidecar.meetCode, startedAt: startedAt,
                                            endedAt: package.sidecar.endedAt)
        switch ForkCastralMatch.automatic(found) {
        case let .send(choice): return (choice, nil)
        case let .needsChoice(failure): throw ForkMeetingExportFailure.castral(failure)
        }
    }

    private struct Sound {
        let format: ForkCastralAudioPlan.Format
        let written: ForkCastralAudio.Written
    }

    /// FLAC at 16 kHz, else 8 kHz, else refused; `format` written first
    /// when sending again what a deposit was opened for.
    private func write(_ package: ForkMeetingExportPackage, limit: Int64, staging: URL,
                       format known: ForkCastralAudioPlan.Format?) async throws -> Sound {
        do {
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: ForkMeetingStore.folderPermissions])
        } catch {
            throw ForkMeetingExportFailure.temporarySpace
        }
        let seconds = await duration(package)
        var step = known.map(ForkCastralAudioPlan.Step.encode) ?? ForkCastralAudioPlan.first(seconds: seconds, limit: limit)
        while true {
            switch step {
            case let .tooLong(minutes):
                throw ForkMeetingExportFailure.castral(.tooLong(maximumMinutes: minutes))
            case .send:
                throw ForkMeetingExportFailure.castral(.encoding)
            case let .encode(format):
                let started = Date()
                let file = staging.appendingPathComponent("\(package.folderName).\(ForkCastralAudioPlan.Format.fileExtension)")
                let written: ForkCastralAudio.Written
                do {
                    written = try await ForkCastralAudio.write(package.audio, as: format, to: file)
                } catch ForkCastralAudio.Failure.unwritable {
                    throw ForkMeetingExportFailure.temporarySpace
                } catch {
                    throw ForkMeetingExportFailure.castral(.encoding)
                }
                Self.log.notice("FLAC \(format.kilohertz, privacy: .public) kHz: \(written.bytes, privacy: .public) bytes for \(Int(written.seconds), privacy: .public) s in \(Int(Date().timeIntervalSince(started) * 1000), privacy: .public) ms")
                step = ForkCastralAudioPlan.next(after: format, bytes: written.bytes, seconds: written.seconds, limit: limit)
                if step == .send { return Sound(format: format, written: written) }
            }
        }
    }

    /// The meeting's length: what `meeting.json` says, else the file's.
    private func duration(_ package: ForkMeetingExportPackage) async -> Double {
        if let seconds = package.sidecar.recordedSeconds, seconds > 0 { return seconds }
        let length = try? await AVURLAsset(url: package.audio).load(.duration)
        return length.map(CMTimeGetSeconds).flatMap { $0.isFinite ? $0 : nil } ?? 0
    }

    /// Sends the sound to the deposit's address, then starts it. The sound
    /// is written again when the earlier file is gone (a quit).
    private func upload(_ record: ForkCastralRecord, client: ForkCastralClient, package: ForkMeetingExportPackage,
                        progress: @escaping (Double) -> Void, file: ForkCastralAudio.Written? = nil) async throws {
        guard case let .found(stored) = keychain.read(Self.uploadAccount(record.deposit)),
              let address = URL(string: String(decoding: stored, as: UTF8.self)) else {
            throw ForkMeetingExportFailure.castral(.storage)
        }
        var sound = file
        let staging = temporaryDirectory.appendingPathComponent(ForkMeetingLeftovers.name(Self.stagingPrefix), isDirectory: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        if sound == nil {
            sound = try await write(package, limit: client.profile.maximumUploadBytes, staging: staging,
                                    format: record.format ?? .flac16k).written
        }
        guard let sound else { throw ForkMeetingExportFailure.castral(.encoding) }
        var next = record
        switch await client.upload(sound.url, to: address, bytes: sound.bytes, progress: progress) {
        case .success(.done):
            next.step = .uploaded
        case .success(.expired):
            // That address is over: the next try opens a new deposit.
            keychain.delete(Self.uploadAccount(record.deposit))
            throw ForkMeetingExportFailure.castral(.storage)
        case .success(.failed):
            throw ForkMeetingExportFailure.castral(.storage)
        case let .failure(failure):
            throw refused(failure)
        }
        try save(next, package)
        keychain.delete(Self.uploadAccount(record.deposit))
        try await start(next, client: client, package: package)
    }

    private func start(_ record: ForkCastralRecord, client: ForkCastralClient, package: ForkMeetingExportPackage) async throws {
        var next = record
        switch await client.start(record.deposit) {
        case .success(.started):
            next.step = .started
            next.startedAt = now()
            next.stage = .queued
            next.progress = ForkCastralContract.Stage.queued.progress
            next.checkedAt = now()
            try save(next, package)
        case .success(.notArrived), .success(.gone):
            // Not there after all: the next try opens a new deposit.
            next.step = .uploading
            keychain.delete(Self.uploadAccount(record.deposit))
            try save(next, package)
            throw ForkMeetingExportFailure.castral(.notArrived)
        case let .failure(failure):
            throw refused(failure)
        }
    }
}
