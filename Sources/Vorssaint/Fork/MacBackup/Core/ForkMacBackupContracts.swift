// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

// The cross-package calls, frozen: the Engine implements them, the Agent,
// the Window and the Settings call them, and each package's tests drive
// them with a fake. Completion handlers, no async/await (fork rule).

/// What went wrong talking to Kopia.
enum ForkMacBackupEngineError: Error, Equatable {
    case engineMissing
    /// The agent's `kopia server` does not answer (or `server.json` is missing).
    case serverUnavailable
    case notConnected
    /// `uniqueIDHex` is not the expected one.
    case wrongRepository(found: String)
    /// Password or S3 key refused.
    case authentication
    /// The storage did not answer (the text says how).
    case unreachable(String)
    case timeout
    case canceled
    /// Kopia exited with an error and no usable JSON.
    case kopia(exitCode: Int32, message: String)
    case decoding(String)
    case other(String)

    /// The run failure a banner names.
    var runFailure: ForkMacBackupRunFailure {
        switch self {
        case .engineMissing: return .engineMissing
        case .serverUnavailable: return .engineStopped
        case .notConnected, .unreachable, .timeout: return .chainBroken
        case .wrongRepository: return .wrongRepository
        case .authentication: return .authentication
        case .canceled: return .canceled
        case .kopia, .decoding, .other: return .other
        }
    }
}

typealias ForkMacBackupEngineResult<Value> = Result<Value, ForkMacBackupEngineError>

/// A long operation's handle.
protocol ForkMacBackupCancellable: AnyObject {
    func cancel()
}

/// The secrets handed to Kopia for one call, through its environment
/// (`KOPIA_PASSWORD`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`), never on
/// its command line. Never Codable, never logged.
struct ForkMacBackupCredentials: Equatable {
    var repositoryPassword: String
    var accessKeyID: String?
    var secretAccessKey: String?

    init(repositoryPassword: String, accessKeyID: String? = nil, secretAccessKey: String? = nil) {
        self.repositoryPassword = repositoryPassword
        self.accessKeyID = accessKeyID
        self.secretAccessKey = secretAccessKey
    }
}

/// The Keychain items of one repository.
enum ForkMacBackupSecretKind: String, CaseIterable {
    case repositoryPassword = "repo-password"
    case s3SecretKey = "s3-secret"

    /// `repo-password#<repository key>`.
    func account(repositoryKey: String) -> String { "\(rawValue)#\(repositoryKey)" }

    /// The Keychain service: `<bundle id>.macbackup`.
    static func service(bundleID: String) -> String { bundleID + ".macbackup" }
}

enum ForkMacBackupSecretRead: Equatable {
    case found(String)
    case missing
    /// The Keychain refused or did not answer in time.
    case failed
}

/// The Keychain, behind a protocol so the wizard and the agent are tested
/// with a fake. Implemented by the Engine package
/// (`AfterFirstUnlockThisDeviceOnly`: the night backup runs with the screen
/// locked). Synchronous and bounded: never call it on the main thread for a
/// read.
protocol ForkMacBackupSecrets: AnyObject {
    /// Whether a secret is saved, without reading it.
    func exists(_ kind: ForkMacBackupSecretKind, repositoryKey: String) -> Bool
    func read(_ kind: ForkMacBackupSecretKind, repositoryKey: String) -> ForkMacBackupSecretRead
    @discardableResult
    func save(_ value: String, kind: ForkMacBackupSecretKind, repositoryKey: String) -> Bool
    @discardableResult
    func delete(_ kind: ForkMacBackupSecretKind, repositoryKey: String) -> Bool
}

/// `kopia blob stats`: the repository's physical size.
struct ForkMacBackupBlobStats: Codable, Equatable {
    var blobCount: Int64
    var totalBytes: Int64
    var measuredAt: Date
}

struct ForkMacBackupVerifyProgress: Codable, Equatable {
    var checked: Int64
    var total: Int64?
}

struct ForkMacBackupVerifyReport: Codable, Equatable {
    var level: ForkMacBackupVerifyLevel
    /// The snapshots it covered.
    var manifestIDs: [String]
    var checked: Int64
    /// Kopia's error lines, named.
    var errors: [String]
    var start: Date
    var end: Date

    var succeeded: Bool { errors.isEmpty }
}

/// One distinct version of a file across snapshots (`versions(of:)`).
struct ForkMacBackupFileVersion: Codable, Equatable {
    var manifestID: String
    var snapshotTime: Date
    var objectID: String
    var size: Int64
    var modified: Date?
}

/// What the window asks to restore (plan §6.3).
struct ForkMacBackupRestoreRequest: Codable, Equatable {
    /// Kopia has no « keep both »: the engine restores to a temporary folder,
    /// then moves with a « (restauré) » suffix.
    enum Overwrite: String, Codable, CaseIterable {
        case keepBoth
        case replaceIfOlder
        case replaceAll
    }

    enum Destination: Codable, Equatable {
        /// A folder apart (default: `~/Downloads/Restauré — <date>/`).
        case folder(path: String)
        /// Where they came from, with an explicit rule.
        case original(Overwrite)
    }

    struct Item: Codable, Equatable {
        var objectID: String
        /// Relative to the source's root.
        var relativePath: String
        var isDirectory: Bool
    }

    var manifestID: String
    var sourcePath: String
    var items: [Item]
    var destination: Destination
    /// Another Mac or another account.
    var skipOwners: Bool
    var ignorePermissionErrors: Bool
}

struct ForkMacBackupRestoreProgress: Codable, Equatable {
    var bytesDone: Int64
    var bytesTotal: Int64?
    var files: Int64
    var filesTotal: Int64?
    var errors: Int
}

struct ForkMacBackupRestoreReport: Codable, Equatable {
    var files: Int64
    var bytes: Int64
    var failures: [ForkMacBackupFailure]
    /// Where the files landed, for « Afficher dans le Finder ».
    var destinationPath: String
}

/// Kopia, driven. Two implementations by the Engine package: the agent's
/// (owns `kopia server`, connects, writes policies, snapshots) and the
/// app's client (talks to the agent's server through `server.json`: browse,
/// versions, restore). The app never starts a snapshot itself: it sends a
/// `ForkMacBackupCommand`.
///
/// Threading: every completion and progress callback arrives on the
/// engine's callback queue (the main queue for the app's client, the agent's
/// serial queue for the agent's), never on the I/O thread; exactly one
/// completion per call, also after a cancel (`.canceled`).
protocol ForkMacBackupEngineDriving: AnyObject {
    /// `repository connect` into the repository's own config, secrets in the
    /// environment, then `repository status --json`. Fails with
    /// `.wrongRepository` when the unique ID is not the expected one, in
    /// which case nothing is kept.
    func connect(_ repository: ForkMacBackupRepository, credentials: ForkMacBackupCredentials, readOnly: Bool,
                 completion: @escaping (ForkMacBackupEngineResult<ForkMacBackupKopia.RepositoryStatus>) -> Void)

    func repositoryStatus(completion: @escaping (ForkMacBackupEngineResult<ForkMacBackupKopia.RepositoryStatus>) -> Void)

    /// Writes `rules` in ONE `policy set`, reads the policy back, and hands
    /// the read-back: the caller compares it with `rules`.
    func applyPolicy(_ rules: ForkMacBackupPolicyRules, to source: ForkMacBackupSource,
                     completion: @escaping (ForkMacBackupEngineResult<ForkMacBackupPolicyRules>) -> Void)

    func readPolicy(of source: ForkMacBackupSource,
                    completion: @escaping (ForkMacBackupEngineResult<ForkMacBackupPolicyRules>) -> Void)

    /// `trigger-snapshot` for one source; progress through `progress`.
    func startSnapshot(_ source: ForkMacBackupSource, completion: @escaping (ForkMacBackupEngineResult<Void>) -> Void)

    /// `GET /api/v1/control/sources`: the live counters.
    func progress(completion: @escaping (ForkMacBackupEngineResult<ForkMacBackupKopia.SourcesResponse>) -> Void)

    /// `cancel-snapshot`: Kopia keeps a checkpoint, the next run resumes.
    func cancelSnapshot(_ source: ForkMacBackupSource, completion: @escaping (ForkMacBackupEngineResult<Void>) -> Void)

    /// `PUT /api/v1/control/throttle` on the live process; nil: no limit.
    func setThrottle(uploadBytesPerSecond: Int64?, completion: @escaping (ForkMacBackupEngineResult<Void>) -> Void)

    /// `snapshot list --all --json`, or one source's.
    func listSnapshots(source: ForkMacBackupSource?,
                       completion: @escaping (ForkMacBackupEngineResult<[ForkMacBackupKopia.SnapshotManifest]>) -> Void)

    @discardableResult
    func verify(_ level: ForkMacBackupVerifyLevel, progress: @escaping (ForkMacBackupVerifyProgress) -> Void,
                completion: @escaping (ForkMacBackupEngineResult<ForkMacBackupVerifyReport>) -> Void)
        -> ForkMacBackupCancellable

    func blobStats(completion: @escaping (ForkMacBackupEngineResult<ForkMacBackupBlobStats>) -> Void)

    /// Never `--safety=none`.
    @discardableResult
    func maintenance(full: Bool, completion: @escaping (ForkMacBackupEngineResult<Void>) -> Void)
        -> ForkMacBackupCancellable

    /// `GET /api/v1/objects/{oid}`: one folder of a snapshot.
    func browse(objectID: String,
                completion: @escaping (ForkMacBackupEngineResult<ForkMacBackupKopia.DirectoryManifest>) -> Void)

    /// The distinct versions of `relativePath` across the source's
    /// snapshots, newest first.
    func versions(of relativePath: String, in source: ForkMacBackupSource,
                  completion: @escaping (ForkMacBackupEngineResult<[ForkMacBackupFileVersion]>) -> Void)

    /// `/api/v1/restore` followed through `/api/v1/tasks/{id}`.
    @discardableResult
    func restore(_ request: ForkMacBackupRestoreRequest, progress: @escaping (ForkMacBackupRestoreProgress) -> Void,
                 completion: @escaping (ForkMacBackupEngineResult<ForkMacBackupRestoreReport>) -> Void)
        -> ForkMacBackupCancellable
}

/// The window's tabs, so the island, the settings and the Command Bar can
/// open the right one (`ForkMacBackupWindow.open(_:)`).
enum ForkMacBackupWindowTab: String, CaseIterable {
    case browse
    case history
    case health
    case verifications
}

/// Whether the background agent may run (`SMAppService` or, in a
/// Developer build, a plain LaunchAgent), as the Settings show it.
enum ForkMacBackupAgentRegistration: String, Codable, CaseIterable {
    case notRegistered
    /// Waits for « Autoriser » in System Settings › Login Items.
    case requiresApproval
    case enabled
    /// A Developer build without the plist in its bundle: a LaunchAgent
    /// written in `~/Library/LaunchAgents`.
    case developmentFallback
    case failed
}

/// The pinned Kopia engine on this Mac (`ForkMacBackupEngineStore`), modelled
/// on Parakeet's model store.
enum ForkMacBackupEngineInstallState: Equatable {
    case notInstalled
    /// 0…1.
    case downloading(Double)
    case verifying
    case installed(version: String)
    case failed(String)
}
