// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// One Kopia call, ready for the runner: what to pass, how long to wait.
struct ForkMacBackupKopiaInvocation: Equatable {
    /// How hard the child may use the Mac (`Process.qualityOfService`).
    enum Priority: Equatable {
        case normal
        case utility
        /// CPU and disk throttled by macOS: the long, scheduled work.
        case background
    }

    var arguments: [String]
    var environment: [String: String]
    /// Killed after this long in all.
    var timeout: TimeInterval
    /// Killed after this long with nothing printed; nil: never.
    var silenceTimeout: TimeInterval?
    var priority: Priority
    /// May the child download cloud-only iCloud files it reads
    /// (`ForkMacBackupDatalessPolicy`)? Only the server of the
    /// « Tout télécharger avant » mode does; never a CLI call.
    var materializeDataless: Bool

    init(arguments: [String], environment: [String: String], timeout: TimeInterval,
         silenceTimeout: TimeInterval? = nil, priority: Priority = .utility, materializeDataless: Bool = false) {
        self.arguments = arguments
        self.environment = environment
        self.timeout = timeout
        self.silenceTimeout = silenceTimeout
        self.priority = priority
        self.materializeDataless = materializeDataless
    }

    /// The command line as a log may show it: it never holds a secret
    /// (secrets only travel in the environment), so it is printed whole.
    var displayLine: String { (["kopia"] + arguments).joined(separator: " ") }
}

/// Kopia's command lines and environments (plan Annex A, bench `SPIKES.md`).
///
/// Every call names the repository's own config and log folder and turns
/// Kopia's Keychain off: a call without them would act on the default
/// `~/Library/Application Support/kopia` (it happened once, SPIKES §0.1).
/// Secrets go in the environment only (`KOPIA_PASSWORD`, `AWS_*`), never on
/// the command line; the environment is built from nothing, so
/// `KOPIA_CACHE_DIRECTORY` (which overrides every repository's cache, §0.2)
/// or a stray `AWS_SESSION_TOKEN` can never leak in.
enum ForkMacBackupKopiaCommand {
    /// The format blob's copies at the root of a repository's cache folder.
    static let cachedFormatBlobs = ["kopia.repository", "kopia.blobcfg"]

    /// Soft cache limits (plan §3.10).
    static let contentCacheMB = 2048
    static let metadataCacheMB = 1024
    /// The description Kopia keeps in the config.
    static let description = "Swishsaint"
    /// The UI user of the private server (its password is random per start).
    static let serverUser = "swishsaint"
    static let controlUser = "server-control"

    /// Names never inherited from the parent, whatever the parent holds.
    static let forbiddenEnvironment: Set<String> = [
        "KOPIA_CACHE_DIRECTORY", "KOPIA_CONFIG_PATH", "KOPIA_LOG_DIR", "KOPIA_PASSWORD",
        "KOPIA_SERVER_PASSWORD", "KOPIA_SERVER_CONTROL_PASSWORD", "KOPIA_SERVER_USERNAME",
        "AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_SESSION_TOKEN", "AWS_PROFILE",
    ]

    /// The few names copied from the parent: the temporary folder and who
    /// the user is (Kopia names the snapshots' owner from them).
    static let inheritedEnvironment = ["TMPDIR", "USER", "LOGNAME"]

    // MARK: Common

    /// `--config-file`, `--log-dir`, `--no-use-keychain`: first on every line.
    static func global(_ files: ForkMacBackupPaths.RepositoryFiles) -> [String] {
        ["--config-file=\(files.config.path)", "--log-dir=\(files.logs.path)", "--no-use-keychain"]
    }

    /// A private `HOME` for the child: whatever Kopia would write beside its
    /// default places stays in the repository's own folder.
    static func home(_ files: ForkMacBackupPaths.RepositoryFiles) -> URL {
        files.folder.appendingPathComponent("home", isDirectory: true)
    }

    /// The child's whole environment: built from nothing, then the secrets.
    static func environment(credentials: ForkMacBackupCredentials?,
                            files: ForkMacBackupPaths.RepositoryFiles,
                            inherited: [String: String] = ProcessInfo.processInfo.environment,
                            extra: [String: String] = [:]) -> [String: String] {
        var environment: [String: String] = [
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": home(files).path,
            "KOPIA_CHECK_FOR_UPDATES": "false",
        ]
        for name in inheritedEnvironment {
            if let value = inherited[name], !value.isEmpty { environment[name] = value }
        }
        if let credentials {
            environment["KOPIA_PASSWORD"] = credentials.repositoryPassword
            if let id = credentials.accessKeyID, !id.isEmpty { environment["AWS_ACCESS_KEY_ID"] = id }
            if let secret = credentials.secretAccessKey, !secret.isEmpty { environment["AWS_SECRET_ACCESS_KEY"] = secret }
        }
        for (name, value) in extra where name != "KOPIA_CACHE_DIRECTORY" { environment[name] = value }
        return environment
    }

    /// One call on the repository: global flags first.
    static func invocation(_ arguments: [String], files: ForkMacBackupPaths.RepositoryFiles,
                           credentials: ForkMacBackupCredentials?, timeout: TimeInterval,
                           silenceTimeout: TimeInterval? = nil,
                           priority: ForkMacBackupKopiaInvocation.Priority = .utility,
                           inherited: [String: String] = ProcessInfo.processInfo.environment) -> ForkMacBackupKopiaInvocation {
        ForkMacBackupKopiaInvocation(arguments: global(files) + arguments,
                                     environment: environment(credentials: credentials, files: files, inherited: inherited),
                                     timeout: timeout, silenceTimeout: silenceTimeout, priority: priority)
    }

    // MARK: Repository

    /// `repository connect` (or `create`) into the repository's own config.
    /// The S3 keys are passed EMPTY on purpose: Kopia would otherwise take
    /// them from `AWS_*` and write the secret into `repository.config`
    /// (SPIKES §1, case A); empty, it keeps nothing and still reads `AWS_*`.
    static func connect(_ repository: ForkMacBackupRepository, files: ForkMacBackupPaths.RepositoryFiles,
                        readOnly: Bool, create: Bool) -> [String] {
        var arguments = ["repository", create ? "create" : "connect"]
        switch repository.kind {
        case .s3:
            arguments += ["s3", "--bucket=\(repository.bucket)", "--endpoint=\(repository.endpoint.hostAndPort)"]
            if !repository.region.isEmpty { arguments.append("--region=\(repository.region)") }
            if !repository.prefix.isEmpty { arguments.append("--prefix=\(repository.prefix)") }
            if !repository.endpoint.tls { arguments.append("--disable-tls") }
            arguments += ["--access-key=", "--secret-access-key=", "--session-token="]
        case .filesystem:
            arguments += ["filesystem", "--path=\(repository.path ?? "")"]
        }
        arguments += [
            "--cache-directory=\(files.cache.path)",
            "--content-cache-size-mb=\(contentCacheMB)",
            "--metadata-cache-size-mb=\(metadataCacheMB)",
            "--override-hostname=\(repository.clientIdentity.hostName)",
            "--override-username=\(repository.clientIdentity.userName)",
            "--no-persist-credentials",
            "--description=\(description)",
        ]
        if readOnly, !create { arguments.append("--readonly") }
        return arguments
    }

    static let status = ["repository", "status", "--json"]

    // MARK: Snapshots

    /// One source's snapshots (`path`) or every source's; Kopia also lists a
    /// parent source's snapshots for a path, so the caller filters on
    /// `source.path` (SPIKES §4).
    static func snapshotList(path: String?, incomplete: Bool) -> [String] {
        var arguments = ["snapshot", "list", "--json"]
        arguments.append(path ?? "--all")
        if incomplete { arguments.append("--incomplete") }
        return arguments
    }

    /// `snapshot verify`; no ID means every snapshot.
    static func verify(percent: Double, manifestIDs: [String] = []) -> [String] {
        ["snapshot", "verify", "--json", "--verify-files-percent=\(percentText(percent))"] + manifestIDs
    }

    /// « 1 », « 0.5 », « 100 »: Kopia reads a float.
    static func percentText(_ percent: Double) -> String {
        let clamped = min(100, max(0, percent))
        if clamped == clamped.rounded() { return String(Int(clamped)) }
        return String(format: "%g", clamped)
    }

    static let contentVerifyFull = ["content", "verify", "--full"]

    // MARK: Storage

    /// Text only, in exact bytes (`--raw`): `ForkMacBackupKopiaText.blobStats`.
    static let blobStats = ["blob", "stats", "--raw"]
    static let maintenanceInfo = ["maintenance", "info", "--json"]

    /// Never `--safety=none`: Kopia's default full safety.
    static func maintenanceRun(full: Bool) -> [String] {
        full ? ["maintenance", "run", "--full"] : ["maintenance", "run"]
    }

    // MARK: Policies

    /// Replaces the source's whole policy definition in one call.
    static func policyImport(file: URL) -> [String] {
        ["policy", "import", "--from-file=\(file.path)"]
    }

    /// The policy defined on `path` only (not merged with the global one).
    static func policyExport(path: String) -> [String] {
        ["policy", "export", path]
    }

    // MARK: Restore

    /// `kopia restore` of a snapshot's path, with progress on stderr
    /// (`ForkMacBackupKopiaText.restoreProgress`). Sparse files stay sparse;
    /// never atomic writes (60× slower on many small files, SPIKES §4).
    static func restore(manifestID: String, relativePath: String, target: String, overwrite: Bool,
                        skipExisting: Bool, skipOwners: Bool, ignorePermissionErrors: Bool) -> [String] {
        let root = ForkMacBackupRestorePlan.rootReference(manifestID: manifestID, relativePath: relativePath)
        var arguments = ["restore", root, target, "--progress", "--progress-update-interval=1s",
                         "--write-sparse-files", "--no-write-files-atomically"]
        arguments.append(overwrite ? "--overwrite-files" : "--no-overwrite-files")
        if skipExisting { arguments.append("--skip-existing") }
        if skipOwners { arguments.append("--skip-owners") }
        if ignorePermissionErrors { arguments.append("--ignore-permission-errors") }
        return arguments
    }

    // MARK: Server

    /// The private server (SPIKES §2.1, §6): a unix socket nobody else can
    /// write to, no TLS on it, connected in the background so it answers at
    /// once, gone when its stdin closes, with the UI API (browse, restore,
    /// policies, tasks). Passwords come from the environment.
    static func serverStart(socketPath: String) -> [String] {
        ["server", "start", "--address=unix:\(socketPath)", "--insecure", "--async-repo-connect",
         "--shutdown-on-stdin", "--ui", "--server-username=\(serverUser)",
         "--server-control-username=\(controlUser)"]
    }

    /// The server's own environment additions.
    static func serverEnvironment(serverPassword: String, controlPassword: String) -> [String: String] {
        ["KOPIA_SERVER_PASSWORD": serverPassword, "KOPIA_SERVER_CONTROL_PASSWORD": controlPassword]
    }

    // MARK: Binary

    /// Prints the version and exits. Never `--help-long` or `--help-full`:
    /// those run the command (SPIKES §0.1).
    static let version = ["--version"]
}
