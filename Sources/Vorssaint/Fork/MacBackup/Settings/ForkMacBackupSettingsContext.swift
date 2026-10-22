// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import AppKit
import Combine
import Darwin
import Network
import SwiftUI
import SystemConfiguration

/// What the Settings screens need from outside the package, behind closures
/// so the offscreen renders and the previews run on fakes: nothing here is
/// called from a view's body, only from a button or a model.
struct ForkMacBackupSettingsServices {
    /// The app's engine (`ForkMacBackupEngineFactory.makeClient`); nil until
    /// the Engine package provides one.
    var makeEngine: () -> ForkMacBackupEngineDriving?
    var makeSecrets: () -> ForkMacBackupSecrets?
    /// `tailscale status --json`, parsed; nil when Tailscale is absent or off.
    var tailscale: (@escaping (ForkMacBackupTailscaleStatus.Snapshot?) -> Void) -> Void
    /// A TCP connection to the server: the latency in ms, or a reason.
    var probeServer: (_ host: String, _ port: Int, _ timeout: TimeInterval,
                      _ completion: @escaping (Result<Int, ForkMacBackupProbeError>) -> Void) -> Void
    /// Bran's settings, Kopia's config and, when `withSecrets`, Bran's two
    /// Keychain items: read only when the person clicks « Importer depuis Bran ».
    var readBran: (_ withSecrets: Bool, _ completion: @escaping (ForkMacBackupBranReading) -> Void) -> Void
    /// `launchctl bootout gui/<uid>/com.opahventures.bran.backup`, after a confirmation.
    var stopBran: (_ completion: @escaping (Bool) -> Void) -> Void
    var localHostName: () -> String
    var localUserName: () -> String
    var now: () -> Date
}

enum ForkMacBackupProbeError: Error, Equatable {
    case timeout
    case refused(String)
}

/// What « Importer depuis Bran » found (all optional: Bran may be half set).
struct ForkMacBackupBranReading {
    var config: ForkMacBackupBranConfig?
    var kopia: ForkMacBackupKopiaClientConfig?
    var repositoryPassword: String?
    var secretAccessKey: String?
    /// The config file was not there at all.
    var missing: Bool
}

/// The verifications and maintenance the agent recorded (`runs.jsonl`),
/// read off the main thread for the Options sheet.
struct ForkMacBackupSettingsRecords: Equatable {
    var verifications: [ForkMacBackupRunRecord] = []
    var maintenance: [ForkMacBackupRunRecord] = []
    var cacheBytes: Int64?
    var loadedAt: Date?

    func last(_ level: ForkMacBackupVerifyPlan.Level) -> ForkMacBackupRunRecord? {
        verifications.last { record in
            switch (record.verifyLevel, level) {
            case (.references?, .references), (.manifest?, .references): return true
            case (.contentSample?, .contentSample), (.full?, .contentSample): return true
            case (.restoreTest?, .restoreTest): return true
            default: return false
            }
        }
    }
}

/// The page's one model: the agent's state (through `ForkMacBackupStatusModel`),
/// the machine state this package owns (repository, profile, sources, kit
/// dates), the content preview and the records. Main thread only; the disk
/// is read and written on `queue`.
final class ForkMacBackupSettingsContext: ObservableObject {
    static let shared = ForkMacBackupSettingsContext()

    let status: ForkMacBackupStatusModel
    let engineStore: ForkMacBackupEngineStore
    let agentLink: ForkMacBackupAgentLink
    let defaults: UserDefaults
    let services: ForkMacBackupSettingsServices
    let paths: ForkMacBackupPaths?
    let home: String
    /// Renders and previews: nothing is written, sent or scanned.
    let isPreview: Bool

    @Published private(set) var repository: ForkMacBackupRepository?
    @Published private(set) var profile: ForkMacBackupProfile?
    @Published private(set) var knownProfiles: [ForkMacBackupProfile] = []
    @Published private(set) var sources: [ForkMacBackupSource] = []
    @Published private(set) var kitCreatedAt: Date?
    @Published private(set) var kitRemindAt: Date?
    @Published private(set) var kitFingerprint: String?
    @Published var fullDiskAccess = false
    @Published var notifications: Permissions.NotificationPermissionState = .unknown
    @Published private(set) var preview: ForkMacBackupContentPreview?
    /// Non-nil while « Aperçu » walks the disk.
    @Published private(set) var scanProgress: ForkMacBackupContentScanner.Progress?
    @Published private(set) var records = ForkMacBackupSettingsRecords()
    /// Renders only: the engine and agent states to show instead of the
    /// real stores' (their stubs cannot be set from outside).
    @Published var previewEngineState: ForkMacBackupEngineInstallState?
    @Published var previewRegistration: ForkMacBackupAgentRegistration?

    var engineState: ForkMacBackupEngineInstallState { previewEngineState ?? engineStore.state }
    var registration: ForkMacBackupAgentRegistration { previewRegistration ?? agentLink.registration }

    private let queue = DispatchQueue(label: "fork.macbackup.settings", qos: .utility)
    private var scanCancelled = ForkMacBackupFlag()
    /// The walk « Aperçu » runs, whichever context started it: the switch
    /// turned off stops it (`cancelRunningScan`) without creating a context.
    private static var runningScan: ForkMacBackupFlag?
    private var permissionObservers: Set<AnyCancellable> = []

    private init() {
        status = .shared
        engineStore = .shared
        agentLink = .shared
        defaults = .standard
        services = .live
        paths = ForkMacBackupPaths(container: PrivateFileStore.containerURL)
        home = NSHomeDirectory()
        isPreview = false
        reloadMachineState()
        let permissions = Permissions.shared
        fullDiskAccess = permissions.fullDiskAccess
        notifications = permissions.notifications
        permissions.$fullDiskAccess.receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.fullDiskAccess = $0 }.store(in: &permissionObservers)
        permissions.$notifications.receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.notifications = $0 }.store(in: &permissionObservers)
        loadPreviewCache()
    }

    /// A context for renders and previews: `status` shows a fake state,
    /// `defaults` is a throwaway suite, `services` are fakes.
    init(preview status: ForkMacBackupStatusModel, defaults: UserDefaults, services: ForkMacBackupSettingsServices,
         home: String, engineStore: ForkMacBackupEngineStore = .shared, agentLink: ForkMacBackupAgentLink = .shared) {
        self.status = status
        self.engineStore = engineStore
        self.agentLink = agentLink
        self.defaults = defaults
        self.services = services
        paths = nil
        self.home = home
        isPreview = true
        reloadMachineState()
    }

    // MARK: Machine state

    func reloadMachineState() {
        repository = decode(ForkMacBackupRepository.self, ForkDefaultsKey.macBackupRepository)
        profile = defaults.data(forKey: ForkDefaultsKey.macBackupProfile).flatMap(ForkMacBackupProfile.decode)
            ?? defaults.string(forKey: ForkDefaultsKey.macBackupProfile).flatMap { ForkMacBackupProfile.decode(Data($0.utf8)) }
        knownProfiles = decode([ForkMacBackupProfile].self, ForkDefaultsKey.macBackupKnownProfiles) ?? []
        sources = decode([ForkMacBackupSource].self, ForkDefaultsKey.macBackupSources) ?? []
        kitCreatedAt = date(ForkDefaultsKey.macBackupKitCreatedAt)
        kitRemindAt = date(ForkDefaultsKey.macBackupKitRemindAt)
        kitFingerprint = defaults.string(forKey: ForkDefaultsKey.macBackupKitFingerprint)
    }

    private func decode<Value: Decodable>(_ type: Value.Type, _ key: String) -> Value? {
        let data = defaults.data(forKey: key) ?? defaults.string(forKey: key).map { Data($0.utf8) }
        return data.flatMap { try? ForkMacBackupJSON.decoder.decode(type, from: $0) }
    }

    private func store<Value: Encodable>(_ value: Value?, _ key: String) {
        guard let value, let data = try? ForkMacBackupJSON.encoder.encode(value),
              let text = String(data: data, encoding: .utf8) else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(text, forKey: key)
    }

    private func date(_ key: String) -> Date? {
        let seconds = defaults.double(forKey: key)
        return seconds > 0 ? Date(timeIntervalSince1970: seconds) : nil
    }

    /// The sources backed up: the saved ones, else the home folder.
    var effectiveSources: [ForkMacBackupSource] {
        sources.isEmpty ? [ForkMacBackupSource(path: home, presets: presets, customRules: customRules)] : sources
    }

    var presets: [ForkMacBackupPreset] {
        ForkMacBackupPreset.parse(defaults.string(forKey: ForkDefaultsKey.macBackupPresets)
            ?? ForkMacBackupPreset.storageValue(ForkMacBackupPreset.defaultApplied))
    }

    var customRules: [String] {
        guard let text = defaults.string(forKey: ForkDefaultsKey.macBackupRules), !text.isEmpty,
              let rules = try? JSONDecoder().decode([String].self, from: Data(text.utf8)) else { return [] }
        return rules
    }

    var iCloudMode: ForkMacBackupICloudMode {
        ForkMacBackupICloudMode(rawValue: defaults.string(forKey: ForkDefaultsKey.macBackupICloudMode) ?? "")
            ?? .fallback
    }

    var chain: [ForkMacBackupChainNode] { ForkMacBackupChainDisplay.chain(profile: profile, repository: repository) }

    var kitStatus: ForkMacBackupKitStatus {
        ForkMacBackupKit.status(createdAt: kitCreatedAt, remindAt: kitRemindAt, savedFingerprint: kitFingerprint,
                                repository: repository, now: services.now())
    }

    var setup: ForkMacBackupSetupState {
        ForkMacBackupSetupState(engine: engineState, fullDiskAccess: fullDiskAccess,
                                registration: registration, repository: repository, kitCreatedAt: kitCreatedAt)
    }

    /// The identity this Mac would take when nothing is found to continue.
    var localIdentity: ForkMacBackupRepository.Identity {
        .init(userName: services.localUserName(),
              hostName: ForkMacBackupLocalIdentity.hostName(from: services.localHostName()))
    }

    // MARK: Writes (each tells the agent through the status model's own watch)

    func saveConnection(repository: ForkMacBackupRepository, profile: ForkMacBackupProfile?,
                        sources newSources: [ForkMacBackupSource]?) {
        self.repository = repository
        store(repository, ForkDefaultsKey.macBackupRepository)
        if let profile {
            setProfile(profile)
        } else if let current = self.profile, current.repository.key != repository.key {
            setProfile(nil)
        }
        if let newSources {
            saveSources(newSources)
        } else if sources.isEmpty {
            saveSources(effectiveSources)
        }
        send(.reloadSettings)
    }

    func setProfile(_ profile: ForkMacBackupProfile?) {
        self.profile = profile
        store(profile, ForkDefaultsKey.macBackupProfile)
        if let profile {
            knownProfiles = ForkMacBackupProfileFile.merged(knownProfiles, adding: profile)
            store(knownProfiles, ForkDefaultsKey.macBackupKnownProfiles)
        }
    }

    func saveSources(_ newSources: [ForkMacBackupSource]) {
        sources = newSources
        store(newSources, ForkDefaultsKey.macBackupSources)
    }

    /// Presets apply to every source (and to a new one).
    func setPresets(_ presets: [ForkMacBackupPreset]) {
        let normalized = ForkMacBackupPreset.normalized(presets)
        defaults.set(ForkMacBackupPreset.storageValue(normalized), forKey: ForkDefaultsKey.macBackupPresets)
        saveSources(effectiveSources.map { source in
            var source = source
            source.presets = normalized
            return source
        })
        objectWillChange.send()
    }

    func setCustomRules(_ rules: [String]) {
        let cleaned = rules.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let text = (try? JSONEncoder().encode(cleaned)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        defaults.set(cleaned.isEmpty ? "" : text, forKey: ForkDefaultsKey.macBackupRules)
        saveSources(effectiveSources.map { source in
            var source = source
            source.customRules = cleaned
            return source
        })
        objectWillChange.send()
    }

    func addSource(_ path: String) {
        var list = effectiveSources
        guard !list.contains(where: { $0.path == path }) else { return }
        list.append(ForkMacBackupSource(path: path, presets: presets, customRules: customRules))
        saveSources(list)
    }

    func removeSource(_ path: String) {
        let list = effectiveSources.filter { $0.path != path }
        guard !list.isEmpty else { return }
        saveSources(list)
    }

    func moveSources(from offsets: IndexSet, to destination: Int) {
        var list = effectiveSources
        list.move(fromOffsets: offsets, toOffset: destination)
        saveSources(list)
    }

    func kitMade(at date: Date) {
        kitCreatedAt = date
        kitRemindAt = date.addingTimeInterval(ForkMacBackupKit.reminderInterval)
        kitFingerprint = repository.map(ForkMacBackupKit.fingerprint)
        defaults.set(date.timeIntervalSince1970, forKey: ForkDefaultsKey.macBackupKitCreatedAt)
        defaults.set(kitRemindAt?.timeIntervalSince1970 ?? 0, forKey: ForkDefaultsKey.macBackupKitRemindAt)
        defaults.set(kitFingerprint, forKey: ForkDefaultsKey.macBackupKitFingerprint)
    }

    /// « J'ai vérifié que je peux ouvrir mon kit »: the next reminder in 180 days.
    func kitChecked(at date: Date) {
        kitRemindAt = date.addingTimeInterval(ForkMacBackupKit.reminderInterval)
        defaults.set(kitRemindAt?.timeIntervalSince1970 ?? 0, forKey: ForkDefaultsKey.macBackupKitRemindAt)
    }

    /// Forgets the repository on this Mac: nothing is erased on the server.
    func disconnect() {
        guard let repository else { return }
        let key = repository.key
        let secrets = services.makeSecrets()
        queue.async {
            secrets?.delete(.repositoryPassword, repositoryKey: key)
            secrets?.delete(.s3SecretKey, repositoryKey: key)
        }
        self.repository = nil
        defaults.removeObject(forKey: ForkDefaultsKey.macBackupRepository)
        defaults.removeObject(forKey: ForkDefaultsKey.macBackupKitFingerprint)
        send(.reloadSettings)
    }

    func send(_ command: ForkMacBackupCommand) {
        guard !isPreview else { return }
        status.send(command, origin: .settings)
    }

    // MARK: Secrets

    /// Saves both secrets (off the main thread, the Keychain is bounded);
    /// `completion` on the main thread says whether both are in.
    func saveSecrets(password: String?, secretKey: String?, repositoryKey: String,
                     completion: @escaping (Bool) -> Void) {
        guard let secrets = services.makeSecrets() else {
            completion(false)
            return
        }
        queue.async {
            var saved = true
            if let password, !password.isEmpty {
                saved = secrets.save(password, kind: .repositoryPassword, repositoryKey: repositoryKey)
            }
            if let secretKey, !secretKey.isEmpty {
                saved = secrets.save(secretKey, kind: .s3SecretKey, repositoryKey: repositoryKey) && saved
            }
            DispatchQueue.main.async { completion(saved) }
        }
    }

    /// Both secrets of the current repository, read off the main thread.
    func readSecrets(completion: @escaping (ForkMacBackupKitSecrets?) -> Void) {
        guard let repository, let secrets = services.makeSecrets() else {
            completion(nil)
            return
        }
        let key = repository.key
        queue.async {
            guard case .found(let password) = secrets.read(.repositoryPassword, repositoryKey: key) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            var secretKey: String?
            if case .found(let value) = secrets.read(.s3SecretKey, repositoryKey: key) { secretKey = value }
            DispatchQueue.main.async {
                completion(ForkMacBackupKitSecrets(repositoryPassword: password, s3SecretAccessKey: secretKey))
            }
        }
    }

    // MARK: Content preview

    func scanContent() {
        guard !isPreview, scanProgress == nil else { return }
        let flag = ForkMacBackupFlag()
        scanCancelled = flag
        Self.runningScan = flag
        let settings = ForkMacBackupContentScanner.Settings(presets: presets, customRules: customRules, iCloud: iCloudMode)
        let roots = effectiveSources.map(\.path)
        let home = home
        scanProgress = .init(files: 0, bytes: 0, path: home)
        queue.async { [weak self] in
            let result = ForkMacBackupContentScanner.scan(sources: roots, settings: settings, home: home,
                                                          isCancelled: { flag.isSet }) { progress in
                DispatchQueue.main.async {
                    guard let self, self.scanProgress != nil, !flag.isSet else { return }
                    self.scanProgress = progress
                }
            }
            if result.complete, let data = try? ForkMacBackupJSON.encoder.encode(result), let url = self?.previewCacheURL {
                PrivateFileStore.write(data, to: url)
            }
            DispatchQueue.main.async {
                if Self.runningScan === flag { Self.runningScan = nil }
                // A newer scan's progress is not this one's to clear.
                guard let self, self.scanCancelled === flag else { return }
                self.scanProgress = nil
                if result.complete { self.preview = result }
            }
        }
    }

    /// Main thread: the feature was switched off.
    static func cancelRunningScan() {
        runningScan?.set()
        runningScan = nil
    }

    func cancelScan() {
        scanCancelled.set()
        scanProgress = nil
    }

    /// For renders: a measured preview without walking anything.
    func showPreview(_ value: ForkMacBackupContentPreview?, progress: ForkMacBackupContentScanner.Progress? = nil) {
        preview = value
        scanProgress = progress
    }

    private var previewCacheURL: URL? { paths?.root.appendingPathComponent("settings-preview.json", isDirectory: false) }

    private func loadPreviewCache() {
        guard let url = previewCacheURL else { return }
        queue.async { [weak self] in
            let value = (try? Data(contentsOf: url)).flatMap(ForkMacBackupContentPreview.decode)
            DispatchQueue.main.async { if self?.preview == nil { self?.preview = value } }
        }
    }

    // MARK: Records

    func loadRecords() {
        guard !isPreview, let paths else { return }
        let cache = repository.map { paths.repository($0.key).cache }
        queue.async { [weak self] in
            let runs = (try? Data(contentsOf: paths.runs)).map { ForkMacBackupJSON.lines(ForkMacBackupRunRecord.self, from: $0) } ?? []
            let records = ForkMacBackupSettingsRecords(
                verifications: runs.filter { $0.kind == .verify }, maintenance: runs.filter { $0.kind == .maintenance },
                cacheBytes: cache.map(Self.folderSize), loadedAt: Date())
            DispatchQueue.main.async { self?.records = records }
        }
    }

    /// For renders.
    func showRecords(_ value: ForkMacBackupSettingsRecords) { records = value }

    private static func folderSize(_ url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey]) else {
            return 0
        }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            total += Int64((try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize ?? 0)
        }
        return total
    }

    /// The repository's own folders, for « Journaux » and the Terminal.
    var repositoryFiles: ForkMacBackupPaths.RepositoryFiles? {
        guard let paths, let repository else { return nil }
        return paths.repository(repository.key)
    }
}

// MARK: - Live services

extension ForkMacBackupSettingsServices {
    static var live: ForkMacBackupSettingsServices {
        ForkMacBackupSettingsServices(
            makeEngine: {
                ForkMacBackupPaths(container: PrivateFileStore.containerURL)
                    .flatMap { ForkMacBackupEngineFactory.makeClient(paths: $0) }
            },
            makeSecrets: { ForkMacBackupEngineFactory.makeSecrets() },
            tailscale: ForkMacBackupLiveServices.tailscale,
            probeServer: ForkMacBackupLiveServices.probe,
            readBran: ForkMacBackupLiveServices.readBran,
            stopBran: ForkMacBackupLiveServices.stopBran,
            // The Computer Name from the local store: `Host.current()` resolves
            // names over DNS and can block the main thread for seconds.
            localHostName: { (SCDynamicStoreCopyComputerName(nil, nil) as String?) ?? ForkMacBackupFormat.localHostName },
            localUserName: { NSUserName() },
            now: { Date() })
    }
}

/// The real side effects behind `ForkMacBackupSettingsServices.live`. Each
/// runs off the main thread, bounded, and answers on the main thread.
enum ForkMacBackupLiveServices {
    private static let queue = DispatchQueue(label: "fork.macbackup.settings.services", qos: .userInitiated)

    /// The CLI inside Tailscale.app, else one on the PATH.
    static let tailscaleCandidates = ["/Applications/Tailscale.app/Contents/MacOS/Tailscale",
                                      "/opt/homebrew/bin/tailscale", "/usr/local/bin/tailscale"]

    static func tailscale(_ completion: @escaping (ForkMacBackupTailscaleStatus.Snapshot?) -> Void) {
        queue.async {
            var snapshot: ForkMacBackupTailscaleStatus.Snapshot?
            if let path = tailscaleCandidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
                var environment = ProcessInfo.processInfo.environment
                environment["TAILSCALE_BE_CLI"] = "1"
                let result = BoundedProcessRunner.run(path, ["status", "--json"], timeout: 5,
                                                      maxOutputBytes: 4_000_000, environment: environment)
                if !result.timedOut { snapshot = ForkMacBackupTailscaleStatus.parse(result.output) }
            }
            DispatchQueue.main.async { completion(snapshot) }
        }
    }

    static func probe(host: String, port: Int, timeout: TimeInterval,
                      completion: @escaping (Result<Int, ForkMacBackupProbeError>) -> Void) {
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else {
            completion(.failure(.refused("port")))
            return
        }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        let started = Date()
        let finished = ForkMacBackupFlag()
        let finish: (Result<Int, ForkMacBackupProbeError>) -> Void = { result in
            guard finished.setOnce() else { return }
            connection.cancel()
            DispatchQueue.main.async { completion(result) }
        }
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready: finish(.success(Int(Date().timeIntervalSince(started) * 1_000)))
            case .failed(let error): finish(.failure(.refused(error.localizedDescription)))
            case .waiting(let error): finish(.failure(.refused(error.localizedDescription)))
            default: break
            }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + timeout) { finish(.failure(.timeout)) }
    }

    static func readBran(withSecrets: Bool, completion: @escaping (ForkMacBackupBranReading) -> Void) {
        queue.async {
            let home = NSHomeDirectory()
            let configURL = URL(fileURLWithPath: home).appendingPathComponent(ForkMacBackupBranConfig.relativePath)
            let kopiaURL = URL(fileURLWithPath: home)
                .appendingPathComponent("Library/Application Support/kopia/repository.config")
            let configData = try? Data(contentsOf: configURL)
            var reading = ForkMacBackupBranReading(config: configData.flatMap(ForkMacBackupBranConfig.decode),
                                                   kopia: (try? Data(contentsOf: kopiaURL)).flatMap(ForkMacBackupKopiaClientConfig.parse),
                                                   missing: configData == nil)
            if withSecrets, reading.config != nil {
                let keychain = ForkMeetingKeychain(service: ForkMacBackupBranConfig.keychainService, timeout: 90)
                if case .found(let data) = keychain.read(ForkMacBackupBranConfig.passwordAccount) {
                    reading.repositoryPassword = String(data: data, encoding: .utf8)
                }
                if case .found(let data) = keychain.read(ForkMacBackupBranConfig.secretKeyAccount) {
                    reading.secretAccessKey = String(data: data, encoding: .utf8)
                }
            }
            DispatchQueue.main.async { completion(reading) }
        }
    }

    static func stopBran(_ completion: @escaping (Bool) -> Void) {
        queue.async {
            let target = "gui/\(getuid())/\(ForkMacBackupBranConfig.agentLabel)"
            let result = BoundedProcessRunner.run("/bin/launchctl", ["bootout", target], timeout: 15,
                                                  maxOutputBytes: 64_000)
            // 0: stopped; 3 / 113: it was not loaded, which is what we want too.
            let stopped = !result.timedOut && [0, 3, 113].contains(result.status)
            DispatchQueue.main.async { completion(stopped) }
        }
    }
}
