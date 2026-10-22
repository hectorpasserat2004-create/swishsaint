// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// The one JSON dialect of the feature's own files (state, commands, runs,
/// slots, proofs, profiles): dates as seconds since 1970 (exact round
/// trip), sorted keys (stable files). Kopia's JSON has its own decoder
/// (`ForkMacBackupKopia`).
enum ForkMacBackupJSON {
    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }

    /// One JSONL line (no newline inside, one at the end).
    static func line<Value: Encodable>(_ value: Value) -> Data? {
        guard var data = try? encoder.encode(value) else { return nil }
        data.append(0x0A)
        return data
    }

    /// Every decodable line of a JSONL file; a torn or unknown line is
    /// skipped, never fatal.
    static func lines<Value: Decodable>(_ type: Value.Type, from data: Data) -> [Value] {
        let decoder = decoder
        return data.split(separator: 0x0A).compactMap { try? decoder.decode(type, from: Data($0)) }
    }
}

/// `MacBackup/state.json`: what the agent publishes after every change, then
/// posts `ForkMacBackupNotify.state`. Written atomically (0600) by the agent
/// only; read by the app.
struct ForkMacBackupStateFile: Codable, Equatable {
    static let formatVersion = 1

    var formatVersion: Int
    var writtenAt: Date
    /// The agent's process, to tell a stale file from a live agent.
    var agentPID: Int32?
    /// The agent's build (`CFBundleVersion`), shown in Health.
    var agentBuild: String?
    var presentation: ForkMacBackupPresentation

    init(presentation: ForkMacBackupPresentation, writtenAt: Date = Date(), agentPID: Int32? = nil,
         agentBuild: String? = nil) {
        formatVersion = Self.formatVersion
        self.writtenAt = writtenAt
        self.agentPID = agentPID
        self.agentBuild = agentBuild
        self.presentation = presentation
    }

    func encoded() -> Data? { try? ForkMacBackupJSON.encoder.encode(self) }

    /// A state of this format or an older one; nil for anything else (a
    /// newer agent's file is ignored rather than misread).
    static func decode(_ data: Data) -> ForkMacBackupStateFile? {
        guard let file = try? ForkMacBackupJSON.decoder.decode(ForkMacBackupStateFile.self, from: data),
              file.formatVersion <= formatVersion else { return nil }
        return file
    }
}

/// How deep a verification goes (plan §7.1).
enum ForkMacBackupVerifyLevel: Codable, Equatable {
    /// `snapshot list`: the snapshot is visible.
    case manifest
    /// `snapshot verify --verify-files-percent=0`: every content exists.
    case references
    /// `--verify-files-percent=<percent>`: a sample read back.
    case contentSample(percent: Double)
    /// Restore `files` random files and compare them byte for byte.
    case restoreTest(files: Int)
    /// `content verify --full`: everything, long.
    case full

    /// The proof level a success raises the snapshots to.
    var proofLevel: ForkMacBackupProofLevel {
        switch self {
        case .manifest, .references: return .present
        case .contentSample, .full: return .contentVerified
        case .restoreTest: return .restoreTested
        }
    }
}

/// An order from the app (island, settings, Command Bar, window) to the
/// agent, which alone drives Kopia.
enum ForkMacBackupCommand: Codable, Equatable {
    case backUpNow
    /// nil: until resumed.
    case pause(until: Date?)
    case resume
    case slowDown(Bool)
    case verify(ForkMacBackupVerifyLevel)
    /// Stops the operation running (backup with a checkpoint, verify,
    /// maintenance); a restore is cancelled through its engine handle.
    case cancel
    /// `fork.macbackup.*` changed, or the repository, sources or secrets.
    case reloadSettings
}

/// `MacBackup/commands/<id>.json`: one command, written by the app (0600),
/// then `ForkMacBackupNotify.command` posted; the agent executes it once and
/// deletes the file. A command older than `maxAge` is dropped unexecuted (an
/// agent that was not running must not replay yesterday's « back up now »).
struct ForkMacBackupCommandFile: Codable, Equatable {
    static let formatVersion = 1
    static let maxAge: TimeInterval = 10 * 60

    var formatVersion: Int
    var id: UUID
    var issuedAt: Date
    var origin: ForkMacBackupTrigger
    var command: ForkMacBackupCommand

    init(command: ForkMacBackupCommand, origin: ForkMacBackupTrigger, id: UUID = UUID(), issuedAt: Date = Date()) {
        formatVersion = Self.formatVersion
        self.id = id
        self.issuedAt = issuedAt
        self.origin = origin
        self.command = command
    }

    var fileName: String { "\(id.uuidString).json" }

    func encoded() -> Data? { try? ForkMacBackupJSON.encoder.encode(self) }

    static func decode(_ data: Data) -> ForkMacBackupCommandFile? {
        guard let file = try? ForkMacBackupJSON.decoder.decode(ForkMacBackupCommandFile.self, from: data),
              file.formatVersion <= formatVersion else { return nil }
        return file
    }

    func isFresh(now: Date) -> Bool {
        now.timeIntervalSince(issuedAt) <= Self.maxAge && issuedAt.timeIntervalSince(now) <= 60
    }
}

/// `MacBackup/run/server.json`: how the app's client reaches the agent's
/// private `kopia server` (browse, versions, restore). 0600, rewritten at
/// every server start; the control password is random per start.
struct ForkMacBackupServerInfo: Codable, Equatable {
    var formatVersion: Int
    var socketPath: String
    var serverUser: String
    var serverPassword: String
    var controlUser: String
    var controlPassword: String
    var kopiaVersion: String
    var pid: Int32
    var startedAt: Date

    static let formatVersion = 1
}

/// Darwin notification names, derived from the bundle id so the Developer
/// build and the release never hear each other.
struct ForkMacBackupNotify: Equatable {
    /// The agent wrote `state.json`.
    let state: String
    /// The app wrote a command file.
    let command: String
    /// The app changed `fork.macbackup.*` (also sent as `.reloadSettings`).
    let settings: String

    init(bundleID: String) {
        let base = bundleID + ".macbackup"
        state = base + ".state"
        command = base + ".command"
        settings = base + ".settings"
    }

    static var current: ForkMacBackupNotify {
        ForkMacBackupNotify(bundleID: Bundle.main.bundleIdentifier ?? "swishsaint")
    }
}
