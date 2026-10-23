// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// Kopia's JSON, as v0.23.1 writes it (field names read in its sources:
/// `snapshot/manifest.go`, `fs/entry.go`, `internal/serverapi/serverapi.go`,
/// `snapshot/snapshotfs/upload_progress.go`, `internal/uitask/uitask.go`,
/// `cli/command_repository_status.go`).
///
/// Tolerant on purpose: the server API is undocumented and moves between
/// versions. Unknown fields are ignored, every field is optional, a number
/// written as a string (or the reverse) still reads. Dates stay Kopia's
/// RFC 3339 strings (nanoseconds) and are parsed by `date(_:)`.
enum ForkMacBackupKopia {
    // MARK: Decoding

    /// Decodes `type` from Kopia's output, skipping anything printed before
    /// the JSON (a log line, a warning). A `snapshot create --json` that
    /// exits 1 still prints its manifest: decode it, then judge the
    /// manifest, never the exit code alone.
    static func decode<Value: Decodable>(_ type: Value.Type, from data: Data) -> Value? {
        let decoder = JSONDecoder()
        if let value = try? decoder.decode(type, from: data) { return value }
        guard let start = data.firstIndex(where: { $0 == UInt8(ascii: "{") || $0 == UInt8(ascii: "[") }) else {
            return nil
        }
        return try? decoder.decode(type, from: data.subdata(in: start..<data.endIndex))
    }

    /// RFC 3339 with any number of fractional digits; nil for Go's zero
    /// time (year 1) and anything unreadable.
    static func date(_ text: String?) -> Date? {
        guard var text, !text.isEmpty, !text.hasPrefix("0001-01-01") else { return nil }
        var fraction = 0.0
        if let tee = text.firstIndex(of: "T"), let dot = text[tee...].firstIndex(of: ".") {
            let digits = text[text.index(after: dot)...].prefix { $0.isNumber }
            fraction = Double("0." + digits) ?? 0
            text.removeSubrange(dot..<text.index(dot, offsetBy: digits.count + 1))
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text).map { $0.addingTimeInterval(fraction) }
    }

    // MARK: Any JSON

    /// A value of unknown shape (`storage.config`, `schedule`).
    enum JSONValue: Decodable, Equatable {
        case string(String)
        case number(Double)
        case bool(Bool)
        case array([JSONValue])
        case object([String: JSONValue])
        case null

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() {
                self = .null
            } else if let value = try? container.decode(Bool.self) {
                self = .bool(value)
            } else if let value = try? container.decode(Double.self) {
                self = .number(value)
            } else if let value = try? container.decode(String.self) {
                self = .string(value)
            } else if let value = try? container.decode([JSONValue].self) {
                self = .array(value)
            } else {
                self = .object(try container.decode([String: JSONValue].self))
            }
        }

        var string: String? {
            switch self {
            case .string(let value): return value
            case .number(let value): return value == value.rounded() ? String(Int64(value)) : String(value)
            case .bool(let value): return String(value)
            default: return nil
            }
        }

        subscript(key: String) -> JSONValue? {
            if case .object(let object) = self { return object[key] }
            return nil
        }
    }

    // MARK: Snapshots

    struct SourceInfo: Decodable, Equatable {
        var host: String?
        var userName: String?
        var path: String?

        init(host: String? = nil, userName: String? = nil, path: String? = nil) {
            self.host = host
            self.userName = userName
            self.path = path
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: AnyKey.self)
            host = c.mbString("host")
            userName = c.mbString("userName")
            path = c.mbString("path")
        }
    }

    /// `snapshot.Stats`.
    struct Stats: Decodable, Equatable {
        var totalSize: Int64?
        var excludedTotalSize: Int64?
        var fileCount: Int64?
        var cachedFiles: Int64?
        var nonCachedFiles: Int64?
        var dirCount: Int64?
        var excludedFileCount: Int64?
        var excludedDirCount: Int64?
        var ignoredErrorCount: Int64?
        var errorCount: Int64?

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: AnyKey.self)
            totalSize = c.mbInt64("totalSize")
            excludedTotalSize = c.mbInt64("excludedTotalSize")
            fileCount = c.mbInt64("fileCount")
            cachedFiles = c.mbInt64("cachedFiles")
            nonCachedFiles = c.mbInt64("nonCachedFiles")
            dirCount = c.mbInt64("dirCount")
            excludedFileCount = c.mbInt64("excludedFileCount")
            excludedDirCount = c.mbInt64("excludedDirCount")
            ignoredErrorCount = c.mbInt64("ignoredErrorCount")
            errorCount = c.mbInt64("errorCount")
        }
    }

    /// `{path, error}` of a folder summary (at most ten per folder).
    struct EntryError: Decodable, Equatable {
        var path: String?
        var error: String?

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: AnyKey.self)
            path = c.mbString("path")
            error = c.mbString("error")
        }
    }

    /// `fs.DirectorySummary` (`summ`).
    struct DirectorySummary: Decodable, Equatable {
        var size: Int64?
        var files: Int64?
        var symlinks: Int64?
        var dirs: Int64?
        var maxTime: String?
        var incomplete: String?
        var numFailed: Int64?
        var numIgnoredErrors: Int64?
        var errors: [EntryError]

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: AnyKey.self)
            size = c.mbInt64("size")
            files = c.mbInt64("files")
            symlinks = c.mbInt64("symlinks")
            dirs = c.mbInt64("dirs")
            maxTime = c.mbString("maxTime")
            incomplete = c.mbString("incomplete")
            numFailed = c.mbInt64("numFailed")
            numIgnoredErrors = c.mbInt64("numIgnoredErrors")
            errors = c.mbValue([EntryError].self, "errors") ?? []
        }
    }

    /// `snapshot.DirEntry`: a snapshot's root, or one entry of a folder.
    struct DirEntry: Decodable, Equatable {
        var name: String?
        /// « d » folder, « f » file, « s » symlink…
        var type: String?
        /// Octal text (« 0644 ») in v0.23.1; a number reads too.
        var mode: String?
        var mtime: String?
        var uid: Int64?
        var gid: Int64?
        /// The object ID: what `/api/v1/objects/{oid}` takes.
        var obj: String?
        var size: Int64?
        var summ: DirectorySummary?

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: AnyKey.self)
            name = c.mbString("name")
            type = c.mbString("type")
            mode = c.mbString("mode")
            mtime = c.mbString("mtime")
            uid = c.mbInt64("uid")
            gid = c.mbInt64("gid")
            obj = c.mbString("obj")
            size = c.mbInt64("size")
            summ = c.mbValue(DirectorySummary.self, "summ")
        }

        var isDirectory: Bool { type == "d" }
        var isSymlink: Bool { type == "s" }
        var modified: Date? { ForkMacBackupKopia.date(mtime) }
        /// A folder's size is its summary's.
        var totalSize: Int64? { size ?? summ?.size }
    }

    /// `snapshot.Manifest`, as `snapshot list --json`, `snapshot create
    /// --json` and the server's `lastSnapshot` write it.
    struct SnapshotManifest: Decodable, Equatable {
        var id: String
        var source: SourceInfo?
        var description: String?
        var startTime: String?
        var endTime: String?
        var stats: Stats?
        /// Why it is incomplete (« canceled », « checkpoint »…); nil when whole.
        var incomplete: String?
        var rootEntry: DirEntry?
        var tags: [String: String]
        var pins: [String]

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: AnyKey.self)
            id = c.mbString("id") ?? ""
            source = c.mbValue(SourceInfo.self, "source")
            description = c.mbString("description")
            startTime = c.mbString("startTime")
            endTime = c.mbString("endTime")
            stats = c.mbValue(Stats.self, "stats")
            incomplete = c.mbString("incomplete")
            rootEntry = c.mbValue(DirEntry.self, "rootEntry")
            tags = c.mbValue([String: String].self, "tags") ?? [:]
            pins = c.mbValue([String].self, "pins") ?? []
        }

        var startDate: Date? { ForkMacBackupKopia.date(startTime) }
        var endDate: Date? { ForkMacBackupKopia.date(endTime) }
        /// Kopia's own counts: fatal errors and ignored ones.
        var errorCount: Int64 { (stats?.errorCount ?? 0) + (stats?.ignoredErrorCount ?? 0) }
    }

    /// One item of the server's `GET /api/v1/snapshots` (another shape than
    /// the CLI's manifest).
    struct APISnapshot: Decodable, Equatable {
        var id: String
        var description: String?
        var startTime: String?
        var endTime: String?
        var incompleteReason: String?
        var summary: DirectorySummary?
        var rootID: String?
        var retention: [String]
        var pins: [String]

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: AnyKey.self)
            id = c.mbString("id") ?? ""
            description = c.mbString("description")
            startTime = c.mbString("startTime")
            endTime = c.mbString("endTime")
            incompleteReason = c.mbString("incompleteReason")
            summary = c.mbValue(DirectorySummary.self, "summary")
            rootID = c.mbString("rootID")
            retention = c.mbValue([String].self, "retention") ?? []
            pins = c.mbValue([String].self, "pins") ?? []
        }
    }

    struct SnapshotsResponse: Decodable, Equatable {
        var snapshots: [APISnapshot]
        var unfilteredCount: Int64?
        var uniqueCount: Int64?

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: AnyKey.self)
            snapshots = c.mbValue([APISnapshot].self, "snapshots") ?? []
            unfilteredCount = c.mbInt64("unfilteredCount")
            uniqueCount = c.mbInt64("uniqueCount")
        }
    }

    // MARK: Repository

    /// `repository status --json`.
    struct RepositoryStatus: Decodable, Equatable {
        struct ClientOptions: Decodable, Equatable {
            var hostname: String?
            var username: String?
            var readonly: Bool
            var description: String?

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: AnyKey.self)
                hostname = c.mbString("hostname")
                username = c.mbString("username")
                readonly = c.mbValue(Bool.self, "readonly") ?? false
                description = c.mbString("description")
            }
        }

        struct Storage: Decodable, Equatable {
            var type: String?
            var config: [String: JSONValue]

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: AnyKey.self)
                type = c.mbString("type")
                config = c.mbValue([String: JSONValue].self, "config") ?? [:]
            }
        }

        var configFile: String?
        var uniqueIDHex: String?
        var clientOptions: ClientOptions?
        var storage: Storage?

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: AnyKey.self)
            configFile = c.mbString("configFile")
            uniqueIDHex = c.mbString("uniqueIDHex")
            clientOptions = c.mbValue(ClientOptions.self, "clientOptions")
            storage = c.mbValue(Storage.self, "storage")
        }

        /// `user@host` as the repository knows this Mac.
        var identity: ForkMacBackupRepository.Identity? {
            guard let user = clientOptions?.username, let host = clientOptions?.hostname,
                  !user.isEmpty, !host.isEmpty else { return nil }
            return ForkMacBackupRepository.Identity(userName: user, hostName: host)
        }
    }

    // MARK: Server control

    /// `upload` of a source: `snapshotfs.UploadCounters`.
    struct UploadCounters: Decodable, Equatable {
        var hashedBytes: Int64?
        var cachedBytes: Int64?
        var uploadedBytes: Int64?
        var estimatedBytes: Int64?
        var hashedFiles: Int64?
        var cachedFiles: Int64?
        var estimatedFiles: Int64?
        var excludedFiles: Int64?
        var excludedDirs: Int64?
        var errors: Int64?
        var ignoredErrors: Int64?
        var directory: String?
        var lastErrorPath: String?
        var lastError: String?

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: AnyKey.self)
            hashedBytes = c.mbInt64("hashedBytes")
            cachedBytes = c.mbInt64("cachedBytes")
            uploadedBytes = c.mbInt64("uploadedBytes")
            estimatedBytes = c.mbInt64("estimatedBytes")
            hashedFiles = c.mbInt64("hashedFiles")
            cachedFiles = c.mbInt64("cachedFiles")
            estimatedFiles = c.mbInt64("estimatedFiles")
            excludedFiles = c.mbInt64("excludedFiles")
            excludedDirs = c.mbInt64("excludedDirs")
            errors = c.mbInt64("errors")
            ignoredErrors = c.mbInt64("ignoredErrors")
            directory = c.mbString("directory")
            lastErrorPath = c.mbString("lastErrorPath")
            lastError = c.mbString("lastError")
        }

        /// Read so far: hashed (new or changed) plus cached (unchanged).
        var bytesDone: Int64 { (hashedBytes ?? 0) + (cachedBytes ?? 0) }
        var filesDone: Int64 { (hashedFiles ?? 0) + (cachedFiles ?? 0) }
        /// The estimate, once Kopia has one (0 means none yet).
        var estimate: Int64? { (estimatedBytes ?? 0) > 0 ? estimatedBytes : nil }
    }

    /// One source of `GET /api/v1/control/sources`.
    struct SourceStatus: Decodable, Equatable {
        /// IDLE, PENDING, UPLOADING, PAUSED, FAILED, REMOTE.
        var status: String?
        var source: SourceInfo?
        var schedule: JSONValue?
        var lastSnapshot: SnapshotManifest?
        var nextSnapshotTime: String?
        var currentTask: String?
        var upload: UploadCounters?

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: AnyKey.self)
            status = c.mbString("status")
            source = c.mbValue(SourceInfo.self, "source")
            schedule = c.mbValue(JSONValue.self, "schedule")
            lastSnapshot = c.mbValue(SnapshotManifest.self, "lastSnapshot")
            nextSnapshotTime = c.mbString("nextSnapshotTime")
            currentTask = c.mbString("currentTask")
            upload = c.mbValue(UploadCounters.self, "upload")
        }

        var isUploading: Bool { status?.uppercased() == "UPLOADING" }
    }

    struct SourcesResponse: Decodable, Equatable {
        var localHost: String?
        var localUsername: String?
        var sources: [SourceStatus]

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: AnyKey.self)
            localHost = c.mbString("localHost")
            localUsername = c.mbString("localUsername")
            sources = c.mbValue([SourceStatus].self, "sources") ?? []
        }

        func source(path: String) -> SourceStatus? {
            sources.first { $0.source?.path == path }
        }
    }

    // MARK: Tasks

    /// `uitask.Info`: a restore, a maintenance, an estimate…
    struct TaskInfo: Decodable, Equatable {
        struct Counter: Decodable, Equatable {
            var value: Int64
            var units: String?
            var level: String?

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: AnyKey.self)
                value = c.mbInt64("value") ?? 0
                units = c.mbString("units")
                level = c.mbString("level")
            }
        }

        enum Status: String {
            case running = "RUNNING"
            case canceling = "CANCELING"
            case canceled = "CANCELED"
            case success = "SUCCESS"
            case failed = "FAILED"
        }

        var id: String
        var kind: String?
        var description: String?
        var status: String?
        var startTime: String?
        var endTime: String?
        var progressInfo: String?
        var errorMessage: String?
        var counters: [String: Counter]

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: AnyKey.self)
            id = c.mbString("id") ?? ""
            kind = c.mbString("kind")
            description = c.mbString("description")
            status = c.mbString("status")
            startTime = c.mbString("startTime")
            endTime = c.mbString("endTime")
            progressInfo = c.mbString("progressInfo")
            errorMessage = c.mbString("errorMessage")
            counters = c.mbValue([String: Counter].self, "counters") ?? [:]
        }

        var knownStatus: Status? { status.flatMap { Status(rawValue: $0.uppercased()) } }
        var isFinished: Bool { [.canceled, .success, .failed].contains(knownStatus) }

        func counter(_ name: String) -> Int64? { counters[name]?.value }
    }

    struct TasksResponse: Decodable, Equatable {
        var tasks: [TaskInfo]

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: AnyKey.self)
            tasks = c.mbValue([TaskInfo].self, "tasks") ?? []
        }
    }

    // MARK: Browsing

    /// A folder of a snapshot: `GET /api/v1/objects/{oid}` returns Kopia's
    /// directory manifest itself.
    struct DirectoryManifest: Decodable, Equatable {
        /// « kopia:directory ».
        var stream: String?
        var entries: [DirEntry]
        var summary: DirectorySummary?

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: AnyKey.self)
            stream = c.mbString("stream")
            entries = c.mbValue([DirEntry].self, "entries") ?? []
            summary = c.mbValue(DirectorySummary.self, "summary")
        }
    }

    // MARK: Lenient keys

    /// Any key: lets each decoder pick the fields it knows and ignore the rest.
    struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int?

        init(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue: Int) {
            stringValue = String(intValue)
            self.intValue = intValue
        }
    }
}

extension KeyedDecodingContainer where K == ForkMacBackupKopia.AnyKey {
    /// A number, or a number written as text; nil when absent or neither.
    func mbInt64(_ name: String) -> Int64? {
        let key = Key(stringValue: name)
        if let value = try? decodeIfPresent(Int64.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Double.self, forKey: key), value.isFinite { return Int64(value) }
        if let text = try? decodeIfPresent(String.self, forKey: key) { return Int64(text) }
        return nil
    }

    /// Text, or a number or a boolean as text; nil when absent or null.
    func mbString(_ name: String) -> String? {
        let key = Key(stringValue: name)
        if let value = try? decodeIfPresent(String.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Int64.self, forKey: key) { return String(value) }
        if let value = try? decodeIfPresent(Bool.self, forKey: key) { return String(value) }
        return nil
    }

    /// Any decodable; nil when absent, null or of another shape.
    func mbValue<Value: Decodable>(_ type: Value.Type, _ name: String) -> Value? {
        (try? decodeIfPresent(type, forKey: Key(stringValue: name))) ?? nil
    }
}
