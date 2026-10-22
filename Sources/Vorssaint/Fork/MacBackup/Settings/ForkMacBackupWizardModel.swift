// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// Where the wizard starts.
enum ForkMacBackupWizardStart: Equatable, Identifiable {
    /// Step 1: the person picks.
    case choose
    case profile(ForkMacBackupProfile)
    case bran
    /// Another Mac's kit, with its secrets when the passphrase opened them.
    case kit(ForkMacBackupKitFile, ForkMacBackupKitSecrets?)
    /// The current connection, from one step (a wrong repository, a password).
    case edit(ForkMacBackupWizardStep)

    var id: String {
        switch self {
        case .choose: return "choose"
        case .profile(let profile): return "profile.\(profile.name)"
        case .bran: return "bran"
        case .kit(let kit, _): return "kit.\(kit.fingerprint)"
        case .edit(let step): return "edit.\(step.rawValue)"
        }
    }
}

/// The connection wizard's state (plan §11.2). Nothing is saved before the
/// test succeeded and the person said « C'est bien mon dépôt »; the secrets
/// go to the Keychain at the very end.
final class ForkMacBackupWizardModel: ObservableObject {
    enum Origin: Equatable {
        case existing
        case newRepository
        /// Read only: another Mac's repository.
        case otherMac
    }

    enum NodeState: Equatable {
        case pending
        case running
        case ok(String)
        case failed(String)
        case skipped
    }

    struct NodeResult: Equatable, Identifiable {
        var node: ForkMacBackupChainNode
        var state: NodeState

        var id: String { node.id }
    }

    enum IdentityChoice: Hashable {
        case continuing(ForkMacBackupRepository.Identity)
        case new

        func hash(into hasher: inout Hasher) {
            switch self {
            case .continuing(let identity):
                hasher.combine(identity.userName)
                hasher.combine(identity.hostName)
            case .new:
                hasher.combine("new")
            }
        }
    }

    enum BranState: Equatable {
        case idle
        case reading
        case missing
        case failed
        case found
    }

    enum StopState: Equatable {
        case idle
        case stopping
        case stopped
        case failed
    }

    let context: ForkMacBackupSettingsContext

    @Published var step: ForkMacBackupWizardStep
    @Published var origin: Origin = .existing
    @Published var form = ForkMacBackupServerForm()
    @Published var showIssues = false
    @Published var password = ""
    @Published var passwordConfirm = ""
    @Published var hasSavedPassword = false
    @Published var peers: [ForkMacBackupTailscalePeer] = []
    @Published var peersLoaded = false
    @Published var testing = false
    @Published var results: [NodeResult] = []
    @Published var uniqueID: String?
    @Published var machines: [ForkMacBackupRepositoryMachine] = []
    @Published var lockedID: String?
    @Published var testError: String?
    @Published var identityChoice: IdentityChoice = .new
    @Published var newUser: String
    @Published var newHost: String
    /// Other Mac: browse only, or take over its backups.
    @Published var browseOnly = true
    @Published var profile: ForkMacBackupProfile?
    @Published var bran: ForkMacBackupBranImport.Result?
    @Published var branState: BranState = .idle
    @Published var branSecretsRead = false
    @Published var stopState: StopState = .idle
    @Published var finishError: String?
    @Published var finished = false

    /// The repository being edited (`.edit`), if any.
    private(set) var existing: ForkMacBackupRepository?

    init(context: ForkMacBackupSettingsContext, start: ForkMacBackupWizardStart) {
        self.context = context
        let local = context.localIdentity
        newUser = local.userName
        newHost = local.hostName
        step = .start
        switch start {
        case .choose:
            step = .start
        case .profile(let profile):
            useProfile(profile)
        case .bran:
            step = .start
        case .kit(let kit, let secrets):
            useKit(kit, secrets: secrets)
        case .edit(let target):
            if let repository = context.repository {
                existing = repository
                form = ForkMacBackupServerForm(repository: repository)
                profile = context.profile?.repository.key == repository.key ? context.profile : nil
                identityChoice = .continuing(repository.clientIdentity)
                checkSavedSecrets(for: repository)
                step = target == .start ? .server : target
            }
        }
    }

    // MARK: Starts

    func useProfile(_ profile: ForkMacBackupProfile) {
        self.profile = profile
        form = ForkMacBackupServerForm(repository: profile.repository)
        origin = .existing
        step = .server
    }

    func useKit(_ kit: ForkMacBackupKitFile, secrets: ForkMacBackupKitSecrets?) {
        origin = .otherMac
        form = ForkMacBackupServerForm(repository: kit.repository)
        if let secrets {
            password = secrets.repositoryPassword
            form.secretKey = secrets.s3SecretAccessKey ?? ""
        }
        existing = nil
        expectedFromStart = kit.repository.expectedUniqueID
        identityChoice = .continuing(kit.repository.clientIdentity)
        step = secrets == nil ? .server : .repository
    }

    func manual(_ origin: Origin) {
        self.origin = origin
        profile = nil
        bran = nil
        if origin == .newRepository { form = ForkMacBackupServerForm() }
        step = .server
    }

    /// The expected unique ID a kit or a profile brought.
    private var expectedFromStart: String?

    var expectedUniqueID: String? {
        expectedFromStart ?? profile?.repository.expectedUniqueID ?? bran?.repository.expectedUniqueID
            ?? existing.flatMap { $0.key == draftKey ? $0.expectedUniqueID : nil }
    }

    // MARK: Bran

    func importBran() {
        branState = .reading
        context.services.tailscale { [weak self] snapshot in
            self?.peers = snapshot?.peers ?? []
            self?.peersLoaded = true
            self?.context.services.readBran(true) { reading in
                self?.applyBran(reading, peers: snapshot?.peers ?? [])
            }
        }
    }

    func applyBran(_ reading: ForkMacBackupBranReading, peers: [ForkMacBackupTailscalePeer]) {
        guard let config = reading.config else {
            branState = reading.missing ? .missing : .failed
            return
        }
        let text = ForkMacBackupSettingsStrings.strings(L10n.shared.language)
        guard let result = ForkMacBackupBranImport.map(config, kopia: reading.kopia, peers: peers, home: context.home,
                                                       localIdentity: context.localIdentity,
                                                       profileName: text.branProfileName) else {
            branState = .failed
            return
        }
        bran = result
        profile = result.profile
        form = ForkMacBackupServerForm(repository: result.repository)
        if let secret = reading.secretAccessKey { form.secretKey = secret }
        if let password = reading.repositoryPassword { self.password = password }
        branSecretsRead = reading.repositoryPassword != nil && reading.secretAccessKey != nil
        identityChoice = .continuing(result.repository.clientIdentity)
        origin = .existing
        branState = .found
    }

    func stopBran() {
        stopState = .stopping
        context.services.stopBran { [weak self] stopped in
            self?.stopState = stopped ? .stopped : .failed
        }
    }

    // MARK: Server

    func loadPeers() {
        guard !peersLoaded else { return }
        context.services.tailscale { [weak self] snapshot in
            self?.peers = snapshot?.peers ?? []
            self?.peersLoaded = true
        }
    }

    private func checkSavedSecrets(for repository: ForkMacBackupRepository) {
        guard let secrets = context.services.makeSecrets() else { return }
        let key = repository.key
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let secret = secrets.exists(.s3SecretKey, repositoryKey: key)
            let password = secrets.exists(.repositoryPassword, repositoryKey: key)
            DispatchQueue.main.async {
                guard let self, self.draftKey == key else { return }
                self.form.hasSavedSecret = secret
                self.hasSavedPassword = password
            }
        }
    }

    private var draftKey: String? { draft?.key }

    /// The repository the form describes, with this Mac's identity for now.
    var draft: ForkMacBackupRepository? {
        form.repository(identity: identity, keeping: existing)
    }

    var identity: ForkMacBackupRepository.Identity {
        switch identityChoice {
        case .continuing(let identity): return identity
        case .new:
            let user = newUser.trimmingCharacters(in: .whitespaces)
            let host = newHost.trimmingCharacters(in: .whitespaces)
            return .init(userName: user.isEmpty ? context.localIdentity.userName : user,
                         hostName: host.isEmpty ? context.localIdentity.hostName : host)
        }
    }

    // MARK: Repository

    var passwordIssue: Bool {
        if password.isEmpty { return !hasSavedPassword }
        return origin == .newRepository && password != passwordConfirm
    }

    var canTest: Bool { form.isValid && !passwordIssue && !testing }

    /// The chain the test walks: the profile's when it has one, else the
    /// repository's default.
    var testChain: [ForkMacBackupChainNode] {
        guard let draft else { return [] }
        guard let profile, !profile.chain.isEmpty else { return ForkMacBackupProfile.defaultChain(for: draft) }
        // The test always reports the repository, even when a profile does not draw it.
        var chain = profile.chain
        if !chain.contains(where: { $0.kind == .repository }) {
            let server = chain.lastIndex { $0.kind == .s3 || $0.kind == .cloud }.map { $0 + 1 } ?? chain.count
            chain.insert(ForkMacBackupChainNode(id: "repository", kind: .repository, detail: draft.bucket,
                                                probe: .init(kind: .repositoryIdentity)), at: server)
        }
        return chain
    }

    func test() {
        guard canTest, var repository = draft else { return }
        repository.expectedUniqueID = expectedUniqueID
        testing = true
        testError = nil
        uniqueID = nil
        machines = []
        lockedID = nil
        results = testChain.map { NodeResult(node: $0, state: .pending) }
        let text = ForkMacBackupSettingsStrings.strings(L10n.shared.language)
        resolveSecrets(for: repository) { [weak self] password, secretKey in
            guard let self else { return }
            self.runProbes(repository: repository, password: password, secretKey: secretKey, text: text)
        }
    }

    /// The typed secrets, else the saved ones (an edit), read off the main thread.
    private func resolveSecrets(for repository: ForkMacBackupRepository,
                                completion: @escaping (String, String?) -> Void) {
        let typedPassword = password
        let typedSecret = form.secretKey
        guard (typedPassword.isEmpty && hasSavedPassword) || (typedSecret.isEmpty && form.hasSavedSecret),
              let secrets = context.services.makeSecrets() else {
            completion(typedPassword, typedSecret.isEmpty ? nil : typedSecret)
            return
        }
        let key = repository.key
        DispatchQueue.global(qos: .userInitiated).async {
            var password = typedPassword
            var secret: String? = typedSecret.isEmpty ? nil : typedSecret
            if password.isEmpty, case .found(let saved) = secrets.read(.repositoryPassword, repositoryKey: key) {
                password = saved
            }
            if secret == nil, case .found(let saved) = secrets.read(.s3SecretKey, repositoryKey: key) { secret = saved }
            DispatchQueue.main.async { completion(password, secret) }
        }
    }

    private func set(_ kind: ForkMacBackupChainNode.Kind, _ state: NodeState) {
        // The S3 server may be drawn as a provider's cloud.
        let kinds: Set<ForkMacBackupChainNode.Kind> = kind == .s3 ? [.s3, .cloud] : [kind]
        for index in results.indices where kinds.contains(results[index].node.kind) {
            results[index].state = state
        }
    }

    private func runProbes(repository: ForkMacBackupRepository, password: String, secretKey: String?,
                           text: ForkMacBackupSettingsStrings) {
        // This Mac: the engine.
        if case .installed(let version) = context.engineState {
            set(.mac, .ok("Kopia \(version)"))
        } else {
            set(.mac, .failed(text.testEngineMissing))
        }
        set(.network, .running)
        set(.name, .running)
        set(.s3, .running)
        // Tailscale: the peer by its stable ID.
        if let peer = repository.peer {
            set(.tailscale, .running)
            context.services.tailscale { [weak self] snapshot in
                guard let self else { return }
                guard let snapshot else {
                    self.set(.tailscale, .failed(text.testTailscaleOff))
                    return
                }
                if let found = ForkMacBackupTailscaleStatus.match(snapshot.peers, stableID: peer.stableID,
                                                                  dnsName: peer.dnsName, hostName: peer.hostName) {
                    self.set(.tailscale, found.online ? .ok(text.testPeerOnline) : .failed(text.testPeerOffline))
                } else {
                    self.set(.tailscale, .failed(text.testPeerMissing))
                }
            }
        } else {
            set(.tailscale, .skipped)
        }
        let timeout = TimeInterval(ForkMacBackupSettingsKeys.int(ForkDefaultsKey.macBackupProbeTimeout, in: context.defaults))
        context.services.probeServer(repository.endpoint.host, repository.endpoint.port ?? 443, max(2, timeout)) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let latency):
                self.set(.network, .ok(text.testNetworkOK))
                self.set(.name, .ok(repository.endpoint.host))
                self.set(.s3, .ok(String(format: text.latencyMs, latency)))
                self.connect(repository: repository, password: password, secretKey: secretKey, text: text)
            case .failure(let error):
                self.set(.network, .ok(text.testNetworkOK))
                self.set(.name, .skipped)
                let message: String
                switch error {
                case .timeout: message = text.testTimeout
                case .refused(let reason): message = reason
                }
                self.set(.s3, .failed(message))
                self.set(.repository, .skipped)
                self.set(.proxmox, .skipped)
                self.set(.nas, .skipped)
                self.testError = text.testServerUnreachable
                self.testing = false
            }
        }
    }

    private func connect(repository: ForkMacBackupRepository, password: String, secretKey: String?,
                         text: ForkMacBackupSettingsStrings) {
        set(.repository, .running)
        guard let engine = context.services.makeEngine() else {
            set(.repository, .failed(text.engineUnavailable))
            finishProbes()
            testError = text.engineUnavailable
            testing = false
            return
        }
        let credentials = ForkMacBackupCredentials(repositoryPassword: password, accessKeyID: repository.accessKeyID,
                                                   secretAccessKey: secretKey)
        engine.connect(repository, credentials: credentials, readOnly: origin == .otherMac) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let status):
                let found = status.uniqueIDHex ?? ""
                self.uniqueID = found
                self.set(.repository, .ok(ForkMacBackupRepository.shortID(found)))
                if let expected = self.expectedUniqueID, !expected.isEmpty, expected.lowercased() == found.lowercased() {
                    self.lockedID = found
                }
                engine.listSnapshots(source: nil) { [weak self] list in
                    guard let self else { return }
                    if case .success(let manifests) = list {
                        self.machines = ForkMacBackupRepositoryMachine.machines(in: manifests)
                        if case .new = self.identityChoice,
                           let suggested = ForkMacBackupRepositoryMachine.suggested(self.machines, localHost: self.newHost,
                                                                          localUser: self.newUser) {
                            self.identityChoice = .continuing(suggested)
                        }
                    }
                    self.finishProbes()
                    self.testing = false
                }
            case .failure(let error):
                self.set(.repository, .failed(self.message(error, text: text)))
                self.testError = self.message(error, text: text)
                self.finishProbes()
                self.testing = false
            }
        }
    }

    /// Nodes past the repository (Proxmox, the NAS) are not probed here.
    private func finishProbes() {
        for index in results.indices {
            if results[index].state == .pending || results[index].state == .running { results[index].state = .skipped }
        }
    }

    func message(_ error: ForkMacBackupEngineError, text: ForkMacBackupSettingsStrings) -> String {
        let shared = ForkMacBackupStrings.strings(L10n.shared.language)
        switch error {
        case .wrongRepository(let found):
            return shared.wrongRepository + " (" + ForkMacBackupRepository.shortID(found) + ")"
        case .authentication: return text.testAuthentication
        case .unreachable(let reason): return reason.isEmpty ? text.testServerUnreachable : reason
        case .timeout: return text.testTimeout
        case .engineMissing: return text.testEngineMissing
        case .serverUnavailable, .notConnected: return text.engineUnavailable
        case .canceled: return shared.runCanceled
        case .kopia(_, let message), .decoding(let message), .other(let message):
            return message.isEmpty ? shared.runOther : ForkMacBackupDiagnostic.scrub(message)
        }
    }

    var testSucceeded: Bool { uniqueID != nil && testError == nil }

    func lock() {
        lockedID = uniqueID
    }

    // MARK: Navigation

    var canContinue: Bool {
        switch step {
        case .start: return false
        case .server: return true
        case .repository: return lockedID != nil && !testing
        case .identity: return !identity.userName.isEmpty && !identity.hostName.isEmpty && !finished
        case .kit: return true
        }
    }

    func next() {
        switch step {
        case .start:
            break
        case .server:
            showIssues = true
            guard form.isValid else { return }
            if results.isEmpty == false, draftKey != existing?.key { resetTest() }
            step = .repository
        case .repository:
            guard lockedID != nil else { return }
            step = .identity
        case .identity:
            finish()
        case .kit:
            break
        }
    }

    func back() {
        switch step {
        case .start, .kit: break
        case .server: step = .start
        case .repository: step = .server
        case .identity: step = .repository
        }
    }

    private func resetTest() {
        results = []
        uniqueID = nil
        lockedID = nil
        machines = []
        testError = nil
    }

    // MARK: Finish

    /// Saves the connection: the secrets first (only now, after the test),
    /// then the repository, its profile and its sources.
    func finish() {
        guard let lockedID, var repository = form.repository(identity: identity, keeping: existing) else { return }
        repository.expectedUniqueID = lockedID
        let text = ForkMacBackupSettingsStrings.strings(L10n.shared.language)
        if origin == .otherMac && browseOnly {
            // Another Mac's repository, read only: nothing of this Mac changes.
            ForkMacBackupWindow.open(.browse)
            finished = true
            step = .kit
            return
        }
        let secretKey = form.secretKey.isEmpty ? nil : form.secretKey
        // An edit that typed no new password keeps the one saved.
        let keepsPassword = password.isEmpty && hasSavedPassword && existing?.key == repository.key
        if keepsPassword && secretKey == nil {
            store(repository)
            return
        }
        finishError = nil
        context.saveSecrets(password: keepsPassword ? nil : password, secretKey: secretKey,
                            repositoryKey: repository.key) { [weak self] saved in
            guard let self else { return }
            guard saved || self.context.isPreview else {
                self.finishError = text.keychainFailed
                return
            }
            self.store(repository)
        }
    }

    private func store(_ repository: ForkMacBackupRepository) {
        var profile = self.profile
        profile?.repository = repository
        if let bran {
            context.setPresets(bran.presets)
            context.setCustomRules(bran.customRules)
            context.defaults.set(context.services.now().timeIntervalSince1970, forKey: ForkDefaultsKey.macBackupBranImportedAt)
        } else if let rules = profile?.rules {
            context.setPresets(rules.presets)
            context.setCustomRules(rules.custom)
            context.defaults.set(rules.iCloud.rawValue, forKey: ForkDefaultsKey.macBackupICloudMode)
        }
        context.saveConnection(repository: repository, profile: profile, sources: bran?.sources)
        finished = true
        step = .kit
    }
}
