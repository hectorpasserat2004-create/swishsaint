// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import AppKit
import Foundation

/// The « Restaurer… » sheet (plan §6.3): what, where, the checks, the
/// progress, the result. Main thread; the volume is read on a utility queue.
final class ForkMacBackupRestoreFlow: ObservableObject, Identifiable {
    enum Step: Int, CaseIterable, Comparable {
        case what
        case place
        case checks
        case progress
        case result

        static func < (lhs: Step, rhs: Step) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    enum Destination: Equatable {
        case separate
        case original
    }

    struct Checks: Equatable {
        var available: Int64?
        var required: Int64
        var room: ForkMacBackupRestoreCheck.Room
        var writable: Bool
        var insideSource: Bool

        var canStart: Bool {
            guard writable else { return false }
            if case .short = room { return false }
            return true
        }
    }

    enum Outcome: Equatable {
        case complete(ForkMacBackupRestoreReport)
        case partial(ForkMacBackupRestoreReport)
        case failed(String)
        case canceled
    }

    let id = UUID()
    let snapshot: ForkMacBackupSnapshotItem
    let key: ForkMacBackupSourceKey
    let items: [ForkMacBackupBrowseEntry]
    let isOtherMac: Bool
    let size: ForkMacBackupSelectionSize
    let language: AppLanguage
    private let engine: ForkMacBackupEngineDriving
    private let activeSources: [String]
    private let queue = DispatchQueue(label: "fork.macbackup.window.restore", qos: .userInitiated)
    private var handle: ForkMacBackupCancellable?
    private var startedAt: Date?

    @Published var step: Step = .what
    @Published var destination: Destination = .separate {
        didSet { if oldValue != destination { checks = nil } }
    }
    @Published var separateFolder: URL {
        didSet { if oldValue != separateFolder { checks = nil } }
    }
    @Published var policy: ForkMacBackupRestoreRequest.Overwrite = .keepBoth
    @Published private(set) var checks: Checks?
    @Published private(set) var progress: ForkMacBackupRestoreProgress?
    @Published private(set) var outcome: Outcome?

    /// The history line, once it ended.
    var onFinish: ((ForkMacBackupRunRecord) -> Void)?

    init(engine: ForkMacBackupEngineDriving, snapshot: ForkMacBackupSnapshotItem, key: ForkMacBackupSourceKey,
         items: [ForkMacBackupBrowseEntry], isOtherMac: Bool, language: AppLanguage, activeSources: [String],
         downloads: URL? = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first) {
        self.engine = engine
        self.snapshot = snapshot
        self.key = key
        self.items = items
        self.isOtherMac = isOtherMac
        self.language = language
        self.activeSources = activeSources
        size = ForkMacBackupSelectionSize.of(items)
        let text = ForkMacBackupWindowStrings.strings(language)
        let base = downloads ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
        let name = ForkMacBackupRestoreNaming.uniqueFolder(
            ForkMacBackupRestoreNaming.folderName(prefix: text.restoredFolderPrefix, date: snapshot.date,
                                                  locale: language.formattingLocale())) {
            FileManager.default.fileExists(atPath: base.appendingPathComponent($0).path)
        }
        separateFolder = base.appendingPathComponent(name, isDirectory: true)
    }

    var text: ForkMacBackupWindowStrings { .strings(language) }

    /// Restoring where they came from is possible only for this Mac's own files.
    var canRestoreInPlace: Bool { !isOtherMac }

    /// The folder the checks are about.
    var targetFolder: URL {
        switch destination {
        case .separate: return separateFolder
        case .original: return URL(fileURLWithPath: key.path, isDirectory: true)
        }
    }

    // MARK: Steps

    func next() {
        switch step {
        case .what: step = .place
        case .place:
            step = .checks
            runChecks()
        case .checks: start()
        case .progress, .result: break
        }
    }

    func back() {
        switch step {
        case .place: step = .what
        case .checks: step = .place
        default: break
        }
    }

    /// Free space, write access and whether the target is backed up itself.
    func runChecks() {
        checks = nil
        let target = targetFolder
        let needed = size.bytes
        let sources = activeSources
        let inPlace = destination == .original
        queue.async { [weak self] in
            let existing = Self.nearestExisting(target)
            let values = try? existing.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey,
                                                               .volumeAvailableCapacityKey])
            let available = values?.volumeAvailableCapacityForImportantUsage
                ?? values?.volumeAvailableCapacity.map(Int64.init)
            // In place, files replaced free their room first; the margin stays.
            let room = ForkMacBackupRestoreCheck.room(needed: needed, available: available)
            let checks = Checks(available: available, required: ForkMacBackupRestoreCheck.required(for: needed),
                                room: room, writable: FileManager.default.isWritableFile(atPath: existing.path),
                                insideSource: inPlace || ForkMacBackupRestoreCheck.isInsideSource(target.path, sources: sources))
            DispatchQueue.main.async { self?.checks = checks }
        }
    }

    static func nearestExisting(_ url: URL) -> URL {
        var current = url
        while !FileManager.default.fileExists(atPath: current.path), current.pathComponents.count > 1 {
            current.deleteLastPathComponent()
        }
        return current
    }

    func chooseFolder(in window: NSWindow?) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = separateFolder.deletingLastPathComponent()
        panel.prompt = text.chooseFolder.replacingOccurrences(of: "…", with: "")
        let apply: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            self.separateFolder = url.appendingPathComponent(self.separateFolder.lastPathComponent, isDirectory: true)
            self.destination = .separate
        }
        if let window {
            panel.beginSheetModal(for: window, completionHandler: apply)
        } else {
            apply(panel.runModal())
        }
    }

    // MARK: Running

    var request: ForkMacBackupRestoreRequest {
        let destination: ForkMacBackupRestoreRequest.Destination
        switch self.destination {
        case .separate: destination = .folder(path: separateFolder.path)
        case .original: destination = .original(policy)
        }
        return ForkMacBackupRestoreRequest(
            manifestID: snapshot.id, sourcePath: key.path,
            items: items.map { .init(objectID: $0.objectID, relativePath: $0.relativePath, isDirectory: $0.isDirectory) },
            destination: destination,
            // Owners never come back as they were: the person restoring owns
            // the files (Kopia fails on « chown » otherwise, SPIKES §2.4).
            skipOwners: true,
            ignorePermissionErrors: true)
    }

    func start() {
        guard checks?.canStart == true, handle == nil else { return }
        if destination == .separate {
            try? FileManager.default.createDirectory(at: separateFolder, withIntermediateDirectories: true)
        }
        step = .progress
        startedAt = Date()
        progress = ForkMacBackupRestoreProgress(bytesDone: 0, bytesTotal: size.bytes, files: 0, filesTotal: size.files,
                                                errors: 0)
        handle = engine.restore(request, progress: { [weak self] progress in
            self?.progress = progress
        }, completion: { [weak self] result in
            self?.finish(result)
        })
    }

    func cancel() {
        handle?.cancel()
    }

    func cancelIfRunning() {
        if step == .progress { handle?.cancel() }
    }

    private func finish(_ result: ForkMacBackupEngineResult<ForkMacBackupRestoreReport>) {
        handle = nil
        let outcome: Outcome
        var record = ForkMacBackupRunRecord(kind: .restore, trigger: .window, start: startedAt ?? Date(), end: Date(),
                                            outcome: .complete)
        switch result {
        case .success(let report):
            outcome = report.failures.isEmpty ? .complete(report) : .partial(report)
            record.bytesRead = report.bytes
            record.outcome = report.failures.isEmpty ? .complete : .partial
        case .failure(.canceled):
            outcome = .canceled
            record.outcome = .canceled
            record.stopReason = .user
        case .failure(let error):
            outcome = .failed(ForkMacBackupWindowModel.describe(error, shared: .strings(language)))
            record.outcome = .failed
            record.failure = error.runFailure
        }
        self.outcome = outcome
        step = .result
        onFinish?(record)
    }

    /// Where the restored files are, for « Afficher dans le Finder ».
    var resultURL: URL? {
        switch outcome {
        case .complete(let report), .partial(let report):
            return URL(fileURLWithPath: report.destinationPath.isEmpty ? targetFolder.path : report.destinationPath)
        default:
            return nil
        }
    }

    func showInFinder() {
        guard let url = resultURL else { return }
        if destination == .original, items.count == 1 {
            let item = URL(fileURLWithPath: ForkMacBackupFolderPath.absolute(items[0].relativePath, in: key.path))
            NSWorkspace.shared.activateFileViewerSelecting([item])
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    func openResult() {
        guard let url = resultURL else { return }
        if items.count == 1 {
            let inside = url.appendingPathComponent(items[0].name)
            let item = destination == .original
                ? URL(fileURLWithPath: ForkMacBackupFolderPath.absolute(items[0].relativePath, in: key.path))
                : inside
            NSWorkspace.shared.open(FileManager.default.fileExists(atPath: item.path) ? item : url)
        } else {
            NSWorkspace.shared.open(url)
        }
    }
}
