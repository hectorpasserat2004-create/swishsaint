// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import AppKit
import Combine
import Foundation

/// One backed-up folder of one Mac, as Kopia names it.
struct ForkMacBackupSourceKey: Hashable, Identifiable {
    var userName: String
    var host: String
    var path: String

    var id: String { "\(userName)@\(host):\(path)" }
    var machine: String { "\(userName)@\(host)" }
    /// « Dossier personnel » for that account's home, else the folder's name.
    func displayName(_ text: ForkMacBackupStrings) -> String {
        ForkMacBackupFormat.sourceName(path, text: text, userName: userName)
    }

    init(userName: String, host: String, path: String) {
        self.userName = userName
        self.host = host
        self.path = path
    }

    init?(_ info: ForkMacBackupKopia.SourceInfo?) {
        guard let path = info?.path, !path.isEmpty else { return nil }
        self.init(userName: info?.userName ?? "", host: info?.host ?? "", path: path)
    }
}

/// One snapshot as the window shows it.
struct ForkMacBackupSnapshotItem: Equatable, Identifiable {
    var id: String
    var key: ForkMacBackupSourceKey
    var date: Date
    var rootObjectID: String?
    var proof: ForkMacBackupSnapshotProof

    var timeline: ForkMacBackupTimeline.Snapshot {
        ForkMacBackupTimeline.Snapshot(manifestID: id, date: date, level: proof.level, isPartial: proof.isPartial)
    }
}

/// The sidebar's rows.
enum ForkMacBackupSidebarItem: Hashable {
    case source(String)
    case history
    case health
    case verifications

    var tab: ForkMacBackupWindowTab {
        switch self {
        case .source: return .browse
        case .history: return .history
        case .health: return .health
        case .verifications: return .verifications
        }
    }
}

/// The window's whole state. Main thread only; the engine answers on the
/// main queue, the Mac's files are read on `localQueue`.
final class ForkMacBackupWindowModel: ObservableObject {
    enum EngineState: Equatable {
        case loading
        /// No client (agent not running, engine not installed) or an error.
        case unavailable(ForkMacBackupEngineError?)
        case ready
    }

    enum FolderState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    /// A short line under the window (a copy, a request sent).
    struct Notice: Equatable, Identifiable {
        let id = UUID()
        var text: String
        var isError = false

        static func == (lhs: Notice, rhs: Notice) -> Bool { lhs.id == rhs.id }
    }

    // MARK: Dependencies

    let status: ForkMacBackupStatusModel
    let ledgerReader: ForkMacBackupWindowLedgerReading?
    let previewFolder: URL
    private let makeEngine: () -> ForkMacBackupEngineDriving?
    /// The Mac's facts for a path (injected by the renders).
    let localFacts: (String) -> ForkMacBackupLocalStatus.LocalFacts?
    let now: () -> Date
    let calendar: Calendar
    private let localQueue = DispatchQueue(label: "fork.macbackup.window.local", qos: .userInitiated)

    // MARK: Published

    @Published private(set) var language: AppLanguage
    @Published private(set) var engineState: EngineState = .loading
    @Published private(set) var ledger: ForkMacBackupWindowLedger = .empty
    @Published private(set) var snapshots: [ForkMacBackupSourceKey: [ForkMacBackupSnapshotItem]] = [:]
    @Published var sidebarSelection: ForkMacBackupSidebarItem? = nil {
        didSet { if oldValue != sidebarSelection { sidebarDidChange(from: oldValue) } }
    }
    @Published private(set) var selectedSnapshotID: String?
    @Published private(set) var folder: [String] = []
    @Published private(set) var folderState: FolderState = .idle
    @Published private(set) var folderNote: String?
    @Published private(set) var entries: [ForkMacBackupBrowseEntry] = []
    @Published var selection: Set<String> = [] {
        didSet { if oldValue != selection { selectionDidChange() } }
    }
    @Published var zoom: ForkMacBackupTimelineZoom = .week
    @Published var timelineEnd: Date
    @Published var inspectorShown = true
    @Published var searchText = "" {
        didSet { if oldValue != searchText { searchTextDidChange() } }
    }
    @Published var searchFocusToken = 0
    @Published private(set) var search: ForkMacBackupSnapshotSearch.State = .idle
    @Published private(set) var versionCounts: [String: Int] = [:]
    @Published var versionsSheet: ForkMacBackupVersionsModel?
    @Published var restoreFlow: ForkMacBackupRestoreFlow?
    @Published var verdict: ForkMacBackupVerdictModel?
    @Published private(set) var snapshotFailures: [String: [ForkMacBackupFailure]] = [:]
    @Published var notice: Notice?
    @Published private(set) var transfer: ForkMacBackupTransfer?

    private(set) var engine: ForkMacBackupEngineDriving?
    private var directoryCache: [String: ForkMacBackupKopia.DirectoryManifest] = [:]
    private var directoryCacheOrder: [String] = []
    private var generation = 0
    private var searchTask: ForkMacBackupSnapshotSearch?
    private var searchDebounce: DispatchWorkItem?
    private var noticeClear: DispatchWorkItem?
    private var languageObserver: AnyCancellable?
    private var isOpen = false
    private var lastSourceID: String?
    let quickLook = ForkMacBackupQuickLook()

    static let directoryCacheLimit = 300

    init(status: ForkMacBackupStatusModel, ledgerReader: ForkMacBackupWindowLedgerReading?, previewFolder: URL,
         language: AppLanguage? = nil, now: @escaping () -> Date = Date.init, calendar: Calendar = .autoupdatingCurrent,
         localFacts: @escaping (String) -> ForkMacBackupLocalStatus.LocalFacts? = { ForkMacBackupLocalStatus.facts(atPath: $0) },
         makeEngine: @escaping () -> ForkMacBackupEngineDriving?) {
        self.status = status
        self.ledgerReader = ledgerReader
        self.previewFolder = previewFolder
        self.makeEngine = makeEngine
        self.localFacts = localFacts
        self.now = now
        self.calendar = calendar
        self.language = language ?? L10n.shared.language
        timelineEnd = now()
        if language == nil {
            languageObserver = L10n.shared.$language.receive(on: DispatchQueue.main).sink { [weak self] value in
                self?.language = value
            }
        }
    }

    var text: ForkMacBackupWindowStrings { .strings(language) }
    var shared: ForkMacBackupStrings { .strings(language) }
    var locale: Locale { language.formattingLocale() }

    // MARK: Opening

    func open(_ tab: ForkMacBackupWindowTab) {
        let wasOpen = isOpen
        isOpen = true
        if !wasOpen { reload() }
        select(tab)
    }

    func select(_ tab: ForkMacBackupWindowTab) {
        switch tab {
        case .browse:
            if case .source = sidebarSelection { return }
            sidebarSelection = defaultSourceKey.map { .source($0.id) }
        case .history: sidebarSelection = .history
        case .health: sidebarSelection = .health
        case .verifications: sidebarSelection = .verifications
        }
    }

    /// The window closed: searches and previews stop, the next opening reads again.
    func close() {
        isOpen = false
        searchTask?.cancel()
        searchTask = nil
        transfer?.handle?.cancel()
        quickLook.close()
        restoreFlow?.cancelIfRunning()
        clearPreviewFolder()
    }

    /// Reads the records and the snapshots again.
    func reload() {
        ledgerReader?.load { [weak self] ledger in
            guard let self else { return }
            self.ledger = ledger
            self.rebuildProofs()
        }
        engineState = .loading
        engine = engine ?? makeEngine()
        guard let engine else {
            engineState = .unavailable(nil)
            return
        }
        engine.listSnapshots(source: nil) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let manifests):
                self.engineState = .ready
                self.apply(manifests)
            case .failure(let error):
                self.engineState = .unavailable(error)
            }
        }
    }

    // MARK: Sources and snapshots

    private var manifests: [ForkMacBackupKopia.SnapshotManifest] = []

    private func apply(_ manifests: [ForkMacBackupKopia.SnapshotManifest]) {
        self.manifests = manifests
        rebuildProofs()
        if sidebarSelection == nil || isSourceSelectionMissing {
            sidebarSelection = defaultSourceKey.map { .source($0.id) } ?? sidebarSelection
        } else if case .source = sidebarSelection, selectedSnapshotID == nil {
            selectLatestSnapshot()
        }
    }

    private var isSourceSelectionMissing: Bool {
        guard case .source(let id) = sidebarSelection else { return false }
        return !snapshots.keys.contains { $0.id == id }
    }

    private func rebuildProofs() {
        var grouped: [ForkMacBackupSourceKey: [ForkMacBackupSnapshotItem]] = [:]
        for manifest in manifests {
            guard let key = ForkMacBackupSourceKey(manifest.source) else { continue }
            let computed = ForkMacBackupSnapshotProof(manifest: manifest, iCloud: ledger.iCloud)
            let proof = ForkMacBackupWindowLedger.better(computed, ledger.proofs[manifest.id] ?? computed)
            let date = manifest.startDate ?? manifest.endDate ?? proof.endTime
            grouped[key, default: []].append(ForkMacBackupSnapshotItem(id: manifest.id, key: key, date: date,
                                                                       rootObjectID: manifest.rootEntry?.obj, proof: proof))
        }
        for key in grouped.keys { grouped[key]?.sort { $0.date < $1.date } }
        snapshots = grouped
    }

    /// This Mac's identity: the repository's client, else the hosts of the
    /// sources this Mac backs up.
    func isThisMac(_ key: ForkMacBackupSourceKey) -> Bool {
        if let identity = ledger.repository?.clientIdentity {
            return key.host.caseInsensitiveCompare(identity.hostName) == .orderedSame
                && key.userName.caseInsensitiveCompare(identity.userName) == .orderedSame
        }
        let known = Set(ledger.sources.map(\.path) + status.presentation.sources.map(\.path))
        if known.contains(key.path) { return true }
        let host = ProcessInfo.processInfo.hostName.split(separator: ".").first.map(String.init) ?? ""
        return key.host.caseInsensitiveCompare(host) == .orderedSame && key.userName == NSUserName()
    }

    var localSources: [ForkMacBackupSourceKey] {
        snapshots.keys.filter(isThisMac).sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    /// Other Macs of the repository, each with its sources.
    var otherMachines: [(machine: String, sources: [ForkMacBackupSourceKey])] {
        let others = Dictionary(grouping: snapshots.keys.filter { !isThisMac($0) }, by: \.machine)
        return others.keys.sorted().map { machine in
            (machine, (others[machine] ?? []).sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending })
        }
    }

    private var defaultSourceKey: ForkMacBackupSourceKey? {
        localSources.first ?? otherMachines.first?.sources.first
    }

    var selectedKey: ForkMacBackupSourceKey? {
        guard case .source(let id) = sidebarSelection else { return nil }
        return snapshots.keys.first { $0.id == id }
    }

    var currentSnapshots: [ForkMacBackupSnapshotItem] {
        selectedKey.flatMap { snapshots[$0] } ?? []
    }

    var selectedSnapshot: ForkMacBackupSnapshotItem? {
        currentSnapshots.first { $0.id == selectedSnapshotID }
    }

    var isOtherMac: Bool { selectedKey.map { !isThisMac($0) } ?? false }

    /// Another source: its latest backup, at its root. Back on the same
    /// source after another tab: where it was.
    private func sidebarDidChange(from old: ForkMacBackupSidebarItem?) {
        guard case .source(let id) = sidebarSelection else { return }
        if id == lastSourceID, selectedSnapshot != nil { return }
        lastSourceID = id
        folder = []
        cancelSearch()
        selectedSnapshotID = nil
        folderState = .idle
        selectLatestSnapshot()
    }

    private func selectLatestSnapshot() {
        guard let latest = currentSnapshots.last else {
            selectedSnapshotID = nil
            entries = []
            folderState = .idle
            return
        }
        selectSnapshot(latest.id)
    }

    // MARK: Snapshot selection and timeline

    /// Shows `manifestID`, in the same folder when it existed then.
    func selectSnapshot(_ manifestID: String) {
        guard selectedSnapshotID != manifestID || folderState == .idle else { return }
        selectedSnapshotID = manifestID
        if let snapshot = selectedSnapshot {
            timelineEnd = ForkMacBackupTimeline.endShowing(snapshot.date, currentEnd: timelineEnd, zoom: zoom,
                                                           now: now(), calendar: calendar)
            loadFailuresIfNeeded(snapshot)
        }
        loadFolder(folder, keepSelection: true)
        if !search.query.isEmpty { startSearch() }
    }

    /// ← and →: the backup before or after.
    func stepSnapshot(_ step: Int) {
        let neighbor = ForkMacBackupTimeline.neighbor(of: selectedSnapshotID, step: step,
                                                      in: currentSnapshots.map(\.timeline))
        if let neighbor { selectSnapshot(neighbor.manifestID) }
    }

    func showNow() {
        timelineEnd = now()
        if let latest = currentSnapshots.last { selectSnapshot(latest.id) }
    }

    func shiftTimeline(_ direction: Int) {
        timelineEnd = ForkMacBackupTimeline.shifted(end: timelineEnd, zoom: zoom, direction: direction, now: now(),
                                                    calendar: calendar)
    }

    func setZoom(_ zoom: ForkMacBackupTimelineZoom) {
        self.zoom = zoom
        if let snapshot = selectedSnapshot {
            timelineEnd = min(now(), snapshot.date.addingTimeInterval(
                (calendar.date(byAdding: zoom.span, to: snapshot.date) ?? snapshot.date).timeIntervalSince(snapshot.date) / 2))
        }
    }

    var timeline: ForkMacBackupTimeline {
        ForkMacBackupTimeline.build(currentSnapshots.map(\.timeline), zoom: zoom, end: timelineEnd, calendar: calendar)
    }

    // MARK: Folders

    func openFolder(_ entry: ForkMacBackupBrowseEntry) {
        guard entry.isDirectory else { return }
        cancelSearchKeepingText(false)
        loadFolder(ForkMacBackupFolderPath.components(entry.relativePath), keepSelection: false)
    }

    func goTo(depth: Int) {
        guard depth < folder.count else { return }
        loadFolder(Array(folder.prefix(depth)), keepSelection: false)
    }

    /// ⌘↑: the enclosing folder, the current one selected.
    func goToParent() {
        guard !folder.isEmpty else { return }
        let child = ForkMacBackupFolderPath.join(folder)
        loadFolder(Array(folder.dropLast()), keepSelection: false, select: child)
    }

    /// Walks `components` from the snapshot's root; stops at the deepest
    /// one that existed then and says so.
    func loadFolder(_ components: [String], keepSelection: Bool, select: String? = nil) {
        generation += 1
        let token = generation
        guard let engine, let snapshot = selectedSnapshot, let root = snapshot.rootObjectID else {
            entries = []
            folderState = .idle
            return
        }
        let previousSelection = selection
        folderState = .loading
        folderNote = nil
        walk(engine: engine, objectID: root, remaining: components, reached: [], token: token) { [weak self] result in
            guard let self, token == self.generation else { return }
            switch result {
            case .failure(let error):
                self.entries = []
                self.folderState = .failed(Self.describe(error, shared: self.shared))
            case .success(let found):
                self.folder = found.reached
                if found.reached.count < components.count, let missing = components.dropFirst(found.reached.count).first {
                    self.folderNote = String(format: self.text.folderMissingAtDate, missing)
                }
                let path = ForkMacBackupFolderPath.join(found.reached)
                var list = ForkMacBackupBrowseEntry.entries(of: found.manifest, folder: path)
                list.sort(by: ForkMacBackupBrowseEntry.finderOrder)
                self.entries = list
                self.folderState = .loaded
                let ids = Set(list.map(\.id))
                if let select {
                    self.selection = ids.contains(select) ? [select] : []
                } else {
                    self.selection = keepSelection ? previousSelection.intersection(ids) : []
                }
                self.compareWithMac(list, token: token)
            }
        }
    }

    private struct Reached {
        var reached: [String]
        var manifest: ForkMacBackupKopia.DirectoryManifest
    }

    private func walk(engine: ForkMacBackupEngineDriving, objectID: String, remaining: [String], reached: [String],
                      token: Int, completion: @escaping (ForkMacBackupEngineResult<Reached>) -> Void) {
        directory(engine: engine, objectID: objectID) { [weak self] result in
            guard let self, token == self.generation else { return }
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let manifest):
                guard let next = remaining.first else {
                    completion(.success(Reached(reached: reached, manifest: manifest)))
                    return
                }
                guard let child = manifest.entries.first(where: { $0.name == next && $0.isDirectory }),
                      let childID = child.obj else {
                    completion(.success(Reached(reached: reached, manifest: manifest)))
                    return
                }
                self.walk(engine: engine, objectID: childID, remaining: Array(remaining.dropFirst()),
                          reached: reached + [next], token: token, completion: completion)
            }
        }
    }

    /// A folder's manifest, from the cache when it was read already (an
    /// object ID never changes content).
    func directory(engine: ForkMacBackupEngineDriving, objectID: String,
                   completion: @escaping (ForkMacBackupEngineResult<ForkMacBackupKopia.DirectoryManifest>) -> Void) {
        if let cached = directoryCache[objectID] {
            completion(.success(cached))
            return
        }
        engine.browse(objectID: objectID) { [weak self] result in
            if case .success(let manifest) = result { self?.remember(manifest, for: objectID) }
            completion(result)
        }
    }

    private func remember(_ manifest: ForkMacBackupKopia.DirectoryManifest, for objectID: String) {
        if directoryCache[objectID] == nil { directoryCacheOrder.append(objectID) }
        directoryCache[objectID] = manifest
        while directoryCacheOrder.count > Self.directoryCacheLimit {
            directoryCache[directoryCacheOrder.removeFirst()] = nil
        }
    }

    /// The status of each entry against this Mac, read off the main thread.
    private func compareWithMac(_ list: [ForkMacBackupBrowseEntry], token: Int) {
        guard let key = selectedKey, isThisMac(key), !list.isEmpty else { return }
        let facts = localFacts
        localQueue.async { [weak self] in
            let statuses = list.map { entry -> ForkMacBackupLocalStatus in
                let local = facts(ForkMacBackupFolderPath.absolute(entry.relativePath, in: key.path))
                return ForkMacBackupLocalStatus.compare(isDirectory: entry.isDirectory, size: entry.size,
                                                        modified: entry.modified, local: local)
            }
            DispatchQueue.main.async {
                guard let self, token == self.generation else { return }
                var updated = self.entries
                for index in updated.indices where index < statuses.count && updated[index].id == list[index].id {
                    updated[index].localStatus = statuses[index]
                }
                self.entries = updated
            }
        }
    }

    // MARK: Selection

    var selectedEntries: [ForkMacBackupBrowseEntry] {
        let pool = search.query.isEmpty ? entries : search.results
        return pool.filter { selection.contains($0.id) }
    }

    private func selectionDidChange() {
        guard selectedEntries.count == 1, let entry = selectedEntries.first, !entry.isDirectory else { return }
        loadVersionCount(entry)
    }

    /// The versions of a file of `key`: that Mac's and that account's
    /// snapshots only (another Mac may back up the same path).
    private func versions(of entry: ForkMacBackupBrowseEntry, in key: ForkMacBackupSourceKey, engine: ForkMacBackupEngineDriving,
                          completion: @escaping (ForkMacBackupEngineResult<[ForkMacBackupFileVersion]>) -> Void) {
        let source = ForkMacBackupSource(path: key.path)
        if let extras = engine as? ForkMacBackupEngineExtras {
            extras.versions(of: entry.relativePath, in: source,
                            owner: ForkMacBackupRepository.Identity(userName: key.userName, hostName: key.host),
                            completion: completion)
        } else {
            engine.versions(of: entry.relativePath, in: source, completion: completion)
        }
    }

    private func loadVersionCount(_ entry: ForkMacBackupBrowseEntry) {
        guard versionCounts[entry.relativePath] == nil, let engine, let key = selectedKey else { return }
        versions(of: entry, in: key, engine: engine) { [weak self] result in
            guard case .success(let versions) = result else { return }
            self?.versionCounts[entry.relativePath] = ForkMacBackupDistinctVersion.distinct(versions).count
        }
    }

    func showVersions(_ entry: ForkMacBackupBrowseEntry) {
        guard let engine, let key = selectedKey, !entry.isDirectory else { return }
        let sheet = ForkMacBackupVersionsModel(entry: entry)
        versionsSheet = sheet
        versions(of: entry, in: key, engine: engine) { [weak self, weak sheet] result in
            guard let self, let sheet else { return }
            switch result {
            case .success(let versions):
                let distinct = ForkMacBackupDistinctVersion.distinct(versions)
                sheet.state = .loaded(all: versions.count, distinct: distinct)
                self.versionCounts[entry.relativePath] = distinct.count
            case .failure(let error):
                sheet.state = .failed(Self.describe(error, shared: self.shared))
            }
        }
    }

    /// « Voir dans la sauvegarde » of a version: its snapshot, its folder, the file selected.
    func reveal(relativePath: String, in manifestID: String) {
        versionsSheet = nil
        verdict = nil
        cancelSearchKeepingText(false)
        selectedSnapshotID = manifestID
        if let snapshot = selectedSnapshot {
            timelineEnd = ForkMacBackupTimeline.endShowing(snapshot.date, currentEnd: timelineEnd, zoom: zoom,
                                                           now: now(), calendar: calendar)
        }
        let parent = ForkMacBackupFolderPath.parent(of: relativePath) ?? ""
        loadFolder(ForkMacBackupFolderPath.components(parent), keepSelection: false, select: relativePath)
    }

    // MARK: Failures of a snapshot

    private func loadFailuresIfNeeded(_ snapshot: ForkMacBackupSnapshotItem) {
        guard snapshot.proof.unnamedFailureCount > 0, snapshotFailures[snapshot.id] == nil else { return }
        ledgerReader?.failures(manifestID: snapshot.id) { [weak self] list in
            guard let list, !list.isEmpty else { return }
            self?.snapshotFailures[snapshot.id] = list
        }
    }

    /// The failures of `snapshot`, complete when the agent wrote them apart.
    func failures(of snapshot: ForkMacBackupSnapshotItem) -> (named: [ForkMacBackupFailure], unnamed: Int) {
        if let complete = snapshotFailures[snapshot.id], complete.count >= snapshot.proof.failures.count {
            return (complete, max(0, snapshot.proof.failureCount - complete.count))
        }
        return (snapshot.proof.failures, snapshot.proof.unnamedFailureCount)
    }

    // MARK: Search

    private func searchTextDidChange() {
        searchDebounce?.cancel()
        let query = ForkMacBackupNameQuery(searchText)
        guard !query.isEmpty else {
            cancelSearch()
            return
        }
        let work = DispatchWorkItem { [weak self] in self?.startSearch() }
        searchDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func startSearch() {
        searchTask?.cancel()
        guard let engine, let snapshot = selectedSnapshot, let root = snapshot.rootObjectID else { return }
        let query = searchText
        let isLocal = selectedKey.map(isThisMac) ?? false
        let sourcePath = selectedKey?.path ?? ""
        let facts = localFacts
        let queue = localQueue
        let task = ForkMacBackupSnapshotSearch(engine: engine, rootObjectID: root, query: query) { [weak self] state in
            guard let self, state.query == self.searchText else { return }
            guard isLocal else {
                self.search = state
                return
            }
            // The results compared with this Mac, off the main thread.
            queue.async { [weak self] in
                var compared = state
                for index in compared.results.indices {
                    let entry = compared.results[index]
                    compared.results[index].localStatus = ForkMacBackupLocalStatus.compare(
                        isDirectory: entry.isDirectory, size: entry.size, modified: entry.modified,
                        local: facts(ForkMacBackupFolderPath.absolute(entry.relativePath, in: sourcePath)))
                }
                DispatchQueue.main.async {
                    guard let self, compared.query == self.searchText, self.searchTask != nil || !compared.running else { return }
                    self.search = compared
                }
            }
        }
        searchTask = task
        search = ForkMacBackupSnapshotSearch.State(query: query, results: [], running: true, truncated: false)
        selection = []
        task.start()
    }

    func stopSearch() {
        searchTask?.cancel()
        searchTask = nil
        search.running = false
    }

    func cancelSearch() { cancelSearchKeepingText(false) }

    private func cancelSearchKeepingText(_ keep: Bool) {
        searchDebounce?.cancel()
        searchTask?.cancel()
        searchTask = nil
        search = .idle
        if !keep && !searchText.isEmpty { searchText = "" }
    }

    func focusSearch() { searchFocusToken += 1 }

    // MARK: Notices

    func show(_ text: String, isError: Bool = false) {
        notice = Notice(text: text, isError: isError)
        noticeClear?.cancel()
        let clear = DispatchWorkItem { [weak self] in self?.notice = nil }
        noticeClear = clear
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: clear)
    }

    // MARK: Remedies (inspector)

    func perform(_ cause: ForkMacBackupFailureCause, failures: [ForkMacBackupFailure], sourcePath: String) {
        switch cause {
        case .cloudOnly:
            let urls = failures.map { URL(fileURLWithPath: ForkMacBackupFolderPath.absolute($0.path, in: sourcePath)) }
            localQueue.async {
                for url in urls { try? FileManager.default.startDownloadingUbiquitousItem(at: url) }
            }
            show(text.downloadStarted)
        case .permission:
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                NSWorkspace.shared.open(url)
            }
        case .busy:
            status.send(.backUpNow, origin: .window) { [weak self] sent in
                guard let self else { return }
                self.show(sent ? self.text.backupRequested : self.text.requestFailed, isError: !sent)
            }
        case .vanished:
            break
        case .other:
            let diagnostic = failures.map { "\($0.path): \($0.message)" }.joined(separator: "\n")
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(diagnostic, forType: .string)
            show(text.copied)
        }
    }

    func sendVerify(_ level: ForkMacBackupVerifyLevel) {
        status.send(.verify(level), origin: .window) { [weak self] sent in
            guard let self else { return }
            self.show(sent ? self.text.requestSent : self.text.requestFailed, isError: !sent)
        }
    }

    // MARK: Restores (sheet, Quick Look, dragging)

    func beginRestore(_ items: [ForkMacBackupBrowseEntry]? = nil, original: Bool = false) {
        let chosen = items ?? selectedEntries
        guard let engine, let snapshot = selectedSnapshot, let key = selectedKey, !chosen.isEmpty else { return }
        let flow = ForkMacBackupRestoreFlow(engine: engine, snapshot: snapshot, key: key, items: chosen,
                                            isOtherMac: !isThisMac(key), language: language,
                                            activeSources: ledger.sources.map(\.path)
                                                + status.presentation.sources.map(\.path))
        if original { flow.destination = .original }
        // Restores run here, in the app: the status model lays their
        // progress over the agent's state (the island's activity), the
        // island's card « Afficher dans le Finder / Ouvrir » ends them.
        var token: UUID?
        flow.onStart = { [weak self] progress in token = self?.status.restoreStarted(progress) }
        flow.onProgress = { [weak self] progress in
            if let token { self?.status.restoreProgressed(token, progress) }
        }
        flow.onFinish = { [weak self] record, report in
            guard let self else { return }
            self.record(record)
            if let report { ForkMacBackupIsland.restoreFinished(report) }
            if let token { self.status.restoreEnded(token) }
        }
        restoreFlow = flow
    }

    func record(_ run: ForkMacBackupRunRecord) {
        ledgerReader?.append(run)
        ledger.runs.append(run)
    }

    func restoreForPreview(_ entry: ForkMacBackupBrowseEntry, completion: @escaping (Result<URL, ForkMacBackupEngineError>) -> Void)
        -> ForkMacBackupCancellable? {
        guard let engine, let snapshot = selectedSnapshot, let key = selectedKey else {
            completion(.failure(.serverUnavailable))
            return nil
        }
        let folder = previewFolder.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        let request = ForkMacBackupRestoreRequest(
            manifestID: snapshot.id, sourcePath: key.path,
            items: [.init(objectID: entry.objectID, relativePath: entry.relativePath, isDirectory: entry.isDirectory)],
            destination: .folder(path: folder.path), skipOwners: true, ignorePermissionErrors: true)
        return engine.restore(request, progress: { _ in }, completion: { result in
            switch result {
            case .success(let report):
                completion(.success(Self.restoredItem(named: entry.name, report: report, folder: folder)))
            case .failure(let error):
                completion(.failure(error))
            }
        })
    }

    /// Where the one item of a restore landed.
    /// The engine reports the item itself for a one-item restore.
    static func restoredItem(named name: String, report: ForkMacBackupRestoreReport, folder: URL) -> URL {
        report.destinationPath.isEmpty ? folder.appendingPathComponent(name) : URL(fileURLWithPath: report.destinationPath)
    }

    func toggleQuickLook() {
        if quickLook.isVisible {
            quickLook.close()
            return
        }
        guard let entry = selectedEntries.first, !entry.isDirectory else { return }
        previewFile(entry)
    }

    func previewFile(_ entry: ForkMacBackupBrowseEntry, in manifestID: String? = nil) {
        quickLook.prepare(title: entry.name, text: text)
        let start = { [weak self] in
            guard let self else { return }
            _ = self.restoreForPreview(entry) { [weak self] result in
                guard let self else { return }
                switch result {
                case .success(let url): self.quickLook.show(url)
                case .failure(let error):
                    self.quickLook.close()
                    self.show(String(format: self.text.previewFailed, Self.describe(error, shared: self.shared)), isError: true)
                }
            }
        }
        if let manifestID, manifestID != selectedSnapshotID {
            restoreVersionForPreview(entry, manifestID: manifestID)
        } else {
            start()
        }
    }

    private func restoreVersionForPreview(_ entry: ForkMacBackupBrowseEntry, manifestID: String) {
        guard let engine, let key = selectedKey else { return }
        let folder = previewFolder.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        let request = ForkMacBackupRestoreRequest(
            manifestID: manifestID, sourcePath: key.path,
            items: [.init(objectID: entry.objectID, relativePath: entry.relativePath, isDirectory: false)],
            destination: .folder(path: folder.path), skipOwners: true, ignorePermissionErrors: true)
        engine.restore(request, progress: { _ in }, completion: { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let report): self.quickLook.show(Self.restoredItem(named: entry.name, report: report, folder: folder))
            case .failure(let error):
                self.quickLook.close()
                self.show(String(format: self.text.previewFailed, Self.describe(error, shared: self.shared)), isError: true)
            }
        })
    }

    /// A file promise kept: the item restored apart, then moved where the
    /// Finder asked, under a free name.
    func fulfillPromise(_ entry: ForkMacBackupBrowseEntry, to url: URL, completion: @escaping (Error?) -> Void) {
        let move: (Result<URL, ForkMacBackupEngineError>) -> Void = { [weak self] result in
            self?.transfer = nil
            switch result {
            case .failure(let error):
                completion(error)
            case .success(let restored):
                let folder = url.deletingLastPathComponent()
                let word = ForkMacBackupEngineStrings.strings(self?.language ?? .enUS).restoredSuffix
                let name = ForkMacBackupRestoreNaming.keepBothName(url.lastPathComponent, isDirectory: entry.isDirectory,
                                                                   word: word) {
                    FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path)
                }
                do {
                    try FileManager.default.moveItem(at: restored, to: folder.appendingPathComponent(name))
                    try? FileManager.default.removeItem(at: restored.deletingLastPathComponent())
                    completion(nil)
                } catch {
                    completion(error)
                }
            }
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                completion(ForkMacBackupEngineError.canceled)
                return
            }
            self.transfer = ForkMacBackupTransfer(name: entry.name, handle: nil)
            let handle = self.restoreForPreview(entry, completion: move)
            self.transfer?.handle = handle
        }
    }

    private func clearPreviewFolder() {
        let folder = previewFolder
        localQueue.async {
            let contents = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            for item in contents { try? FileManager.default.removeItem(at: item) }
        }
    }

    // MARK: « Is this file backed up? »

    func check(_ url: URL) {
        let model = ForkMacBackupVerdictModel(url: url)
        verdict = model
        let sources = ledger.sources.isEmpty
            ? status.presentation.sources.map { ForkMacBackupSource(path: $0.path) }
            : ledger.sources
        let path = url.standardizedFileURL.path
        let facts = localFacts
        localQueue.async { [weak self] in
            let local = facts(path)
            let values = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey, .isUbiquitousItemKey])
            let cloudOnly = values?.isUbiquitousItem == true
                && values?.ubiquitousItemDownloadingStatus == URLUbiquitousItemDownloadingStatus.notDownloaded
            DispatchQueue.main.async {
                self?.lookUp(path: path, local: local, isCloudOnly: cloudOnly, sources: sources, model: model)
            }
        }
    }

    private func lookUp(path: String, local: ForkMacBackupLocalStatus.LocalFacts?, isCloudOnly: Bool,
                        sources: [ForkMacBackupSource], model: ForkMacBackupVerdictModel) {
        let isDirectory = local?.isDirectory ?? false
        let finish: (ForkMacBackupVerdictModel.Found?, Bool) -> Void = { [weak self, weak model] found, lookedUp in
            guard let self, let model else { return }
            let decided = ForkMacBackupFileVerdict.decide(
                path: path, isDirectory: isDirectory, local: local, isCloudOnly: isCloudOnly, iCloud: self.ledger.iCloud,
                sources: sources,
                found: found.map { .init(snapshotDate: $0.snapshot.date, isDirectory: $0.entry.isDirectory,
                                         size: $0.entry.size, modified: $0.entry.modified) },
                lookedUp: lookedUp, nextBackup: self.status.presentation.nextRun)
            model.result = .decided(decided, found)
        }
        guard let source = ForkMacBackupFileVerdict.source(of: path, in: sources),
              let relative = ForkMacBackupFolderPath.relative(path, to: source.path),
              ForkMacBackupIgnoreMatcher(rules: source.ignoreRules).excludingRule(for: relative, isDirectory: isDirectory) == nil,
              let key = localSources.first(where: { $0.path == source.path }),
              let snapshot = snapshots[key]?.last, let root = snapshot.rootObjectID, let engine else {
            finish(nil, engine != nil && !localSources.isEmpty)
            return
        }
        let parts = ForkMacBackupFolderPath.components(relative)
        guard let name = parts.last else {
            finish(nil, true)
            return
        }
        findEntry(engine: engine, objectID: root, parents: Array(parts.dropLast()), name: name, reached: []) { found in
            guard let found else {
                finish(nil, true)
                return
            }
            finish(ForkMacBackupVerdictModel.Found(key: key, snapshot: snapshot, entry: found), true)
        }
    }

    private func findEntry(engine: ForkMacBackupEngineDriving, objectID: String, parents: [String], name: String,
                           reached: [String], completion: @escaping (ForkMacBackupBrowseEntry?) -> Void) {
        directory(engine: engine, objectID: objectID) { [weak self] result in
            guard let self, case .success(let manifest) = result else {
                completion(nil)
                return
            }
            if let next = parents.first {
                guard let child = manifest.entries.first(where: { $0.name == next && $0.isDirectory }), let id = child.obj else {
                    completion(nil)
                    return
                }
                self.findEntry(engine: engine, objectID: id, parents: Array(parents.dropFirst()), name: name,
                               reached: reached + [next], completion: completion)
            } else {
                let folder = ForkMacBackupFolderPath.join(reached)
                completion(ForkMacBackupBrowseEntry.entries(of: manifest, folder: folder).first { $0.name == name })
            }
        }
    }

    // MARK: Words

    static func describe(_ error: ForkMacBackupEngineError, shared: ForkMacBackupStrings) -> String {
        switch error {
        case .unreachable(let message), .other(let message), .decoding(let message):
            return message.isEmpty ? error.runFailure.title(shared) : message
        case .kopia(_, let message):
            return message.isEmpty ? error.runFailure.title(shared) : message
        default:
            return error.runFailure.title(shared)
        }
    }
}

/// A file being restored for a drag to the Finder.
struct ForkMacBackupTransfer: Equatable {
    var name: String
    var handle: ForkMacBackupCancellable?

    static func == (lhs: ForkMacBackupTransfer, rhs: ForkMacBackupTransfer) -> Bool {
        lhs.name == rhs.name && lhs.handle === rhs.handle
    }
}

/// The versions sheet.
final class ForkMacBackupVersionsModel: ObservableObject, Identifiable {
    enum State: Equatable {
        case loading
        case loaded(all: Int, distinct: [ForkMacBackupDistinctVersion])
        case failed(String)
    }

    let id = UUID()
    let entry: ForkMacBackupBrowseEntry
    @Published var state: State = .loading

    init(entry: ForkMacBackupBrowseEntry) {
        self.entry = entry
    }
}

/// « Ce fichier est-il sauvegardé ? » for one dropped file.
final class ForkMacBackupVerdictModel: ObservableObject, Identifiable {
    struct Found {
        var key: ForkMacBackupSourceKey
        var snapshot: ForkMacBackupSnapshotItem
        var entry: ForkMacBackupBrowseEntry
    }

    enum Result {
        case checking
        case decided(ForkMacBackupFileVerdict, Found?)
    }

    let id = UUID()
    let url: URL
    @Published var result: Result = .checking

    init(url: URL) {
        self.url = url
    }
}
