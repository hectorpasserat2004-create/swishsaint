// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import AppKit
import Combine
import Foundation
import NaturalLanguage
import os

/// The files dropped to be transcribed, one at a time, in the order they
/// came, and the list of those done.
///
/// - **One job at a time**, on one serial queue at `.utility`. None starts
///   while a meeting's transcript runs: two Parakeet instances at once would
///   double the memory and fight for the Neural Engine.
/// - **The updater waits** while a file is transcribed or waits
///   (`ForkMeetingActivity.setTranscribingFiles`), and the Mac does not doze
///   off in the middle of one.
/// - **Parakeet missing**: the jobs wait, said so on their line, and go on
///   their own once it is installed.
/// - **The list is kept** in the app's container (`FileTranscriptions/`,
///   owner-only), with one JSON per transcription for the reader. Machine
///   state: never in the settings backup. A job the app left in the middle
///   reads as interrupted at the next launch.
///
/// State on the main thread; the work on `work`.
final class ForkTranscribeQueue: ObservableObject {
    static let shared = ForkTranscribeQueue()

    @Published private(set) var jobs: [ForkTranscribeJob] = []
    /// The running job's share done, 0…1. Never written.
    @Published private(set) var progress: Double = 0
    /// The transcription the reader shows: a click on a line or a notice.
    @Published var reading: UUID?

    private let work = DispatchQueue(label: "fork.transcribe.work", qos: .utility)
    private let local = ForkTranscribeLocalEngine()
    private let log = Logger(subsystem: "fork.transcribe", category: "queue")
    private let directory: URL
    private let defaults: UserDefaults
    private var stop: ForkMeetingTranscriptStop?
    private var runningID: UUID?
    private var loaded = false
    private var enabled = true
    private var observers: Set<AnyCancellable> = []
    private var meetingObserver: AnyCancellable?

    init(directory: URL? = nil, defaults: UserDefaults = .standard) {
        let container = PrivateFileStore.containerURL ?? FileManager.default.temporaryDirectory
        self.directory = directory ?? container.appendingPathComponent("FileTranscriptions", isDirectory: true)
        self.defaults = defaults
    }

    // MARK: - Launch and switch

    /// At launch (`ForkBootstrap`): the list comes back, and the jobs left
    /// waiting go on.
    func start() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !loaded else { return }
        loaded = true
        if let data = try? Data(contentsOf: indexURL),
           let saved = try? JSONDecoder().decode([ForkTranscribeJob].self, from: data) {
            jobs = ForkTranscribeRules.restored(saved)
            if jobs != saved { save() }
        }
        ForkParakeetModelStore.shared.$state
            .map { if case .installed = $0 { return true } else { return false } }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] installed in if installed { self?.startNext() } }
            .store(in: &observers)
        sync()
    }

    /// Every switch of the feature: off, the running job stops and the
    /// waiting ones are cancelled; on, the queue goes on.
    func sync() {
        dispatchPrecondition(condition: .onQueue(.main))
        enabled = defaults.bool(forKey: ForkDefaultsKey.transcribeEnabled)
        if enabled {
            startNext()
        } else {
            cancelAll()
        }
    }

    var isEnabled: Bool { enabled }

    // MARK: - Asking

    /// The files of a drop, or of the open panel. Folders give their own
    /// files. Returns how many were queued: 0 says nothing was taken.
    @discardableResult
    func add(_ urls: [URL]) -> Int {
        dispatchPrecondition(condition: .onQueue(.main))
        guard enabled else { return 0 }
        let files = ForkTranscribeRules.files(of: urls) { url in
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue
            else { return nil }
            return try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil,
                                                                options: [.skipsHiddenFiles])
        }
        let engine = ForkTranscribeEngine(stored: defaults.string(forKey: ForkDefaultsKey.transcribeEngine))
        let language = ForkTranscribeLanguage(stored: defaults.string(forKey: ForkDefaultsKey.transcribeLanguage))
        let now = Date()
        let added = files.map {
            ForkTranscribeJob(id: UUID(), source: $0, engine: engine, language: language, added: now, stage: .queued)
        }
        guard !added.isEmpty else { return 0 }
        jobs.append(contentsOf: added)
        log.notice("\(added.count, privacy: .public) file(s) queued")
        save()
        startNext()
        return added.count
    }

    /// Stops a running job at its next window, or takes a waiting one out.
    func cancel(_ id: UUID) {
        dispatchPrecondition(condition: .onQueue(.main))
        if runningID == id {
            stop?.cancel()
            return
        }
        update(id) { if $0.stage.isActive { $0.stage = .cancelled; $0.finished = Date() } }
    }

    func cancelAll() {
        dispatchPrecondition(condition: .onQueue(.main))
        for job in jobs where job.stage.isActive { cancel(job.id) }
    }

    /// Back in the queue with its own choices: a failed or cancelled job.
    func retry(_ id: UUID) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard enabled, let job = jobs.first(where: { $0.id == id }), !job.stage.isActive else { return }
        update(id) {
            $0.stage = .queued
            $0.finished = nil
            $0.started = nil
        }
        startNext()
    }

    /// Out of the list; the files written stay where they are.
    func remove(_ id: UUID) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard runningID != id else { return }
        jobs.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: documentURL(id))
        if reading == id { reading = nil }
        save()
    }

    func clearFinished() {
        dispatchPrecondition(condition: .onQueue(.main))
        for job in jobs where !job.stage.isActive { remove(job.id) }
    }

    func job(_ id: UUID) -> ForkTranscribeJob? { jobs.first { $0.id == id } }

    /// The reader's text, kept by the app: there even when the files were
    /// moved.
    func document(_ id: UUID) -> ForkTranscribeDocument? {
        guard let data = try? Data(contentsOf: documentURL(id)) else { return nil }
        return try? JSONDecoder().decode(ForkTranscribeDocument.self, from: data)
    }

    // MARK: - Running

    private func startNext() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard loaded, enabled, runningID == nil else { return }
        guard let id = ForkTranscribeRules.next(in: jobs) else {
            activityChanged()
            work.async { [local] in local.unload() }
            return
        }
        guard let model = ForkParakeetModelStore.shared.installedDirectory else {
            for job in jobs where job.stage == .queued || job.stage == .waitingForEngine {
                update(job.id, saving: false) { $0.stage = .waitingForModel }
            }
            save()
            activityChanged()
            return
        }
        // Parakeet is here: the files that waited for it only wait their turn.
        for job in jobs where job.stage == .waitingForModel && job.id != id {
            update(job.id, saving: false) { $0.stage = .queued }
        }
        // A meeting's transcript holds its own Parakeet: the file waits.
        if ForkMeetingTranscriber.shared.running != nil {
            update(id) { $0.stage = .waitingForEngine }
            watchMeetingTranscript()
            activityChanged()
            return
        }
        guard let job = job(id) else { return }
        let stop = ForkMeetingTranscriptStop()
        self.stop = stop
        runningID = id
        progress = 0
        update(id) {
            $0.stage = .loading
            $0.started = Date()
            $0.finished = nil
        }
        activityChanged()
        let settings = Settings(defaults: defaults, text: ForkTranscribeStrings.strings(L10n.shared.language))
        let fallback = Self.fallbackFolder
        work.async { [weak self] in
            guard let self else { return }
            let activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated],
                                                                 reason: "Transcribing a file")
            defer { ProcessInfo.processInfo.endActivity(activity) }
            let result = self.run(job, model: model, settings: settings, fallback: fallback, stop: stop)
            DispatchQueue.main.async { self.finished(id, result) }
        }
    }

    /// What the work needs from the main thread, read once when it starts.
    struct Settings {
        var kinds: [ForkTranscribeOutput.Kind]
        var folder: URL?
        var replacements: [ForkDictationSupport.Replacement]
        var text: ForkTranscribeStrings

        init(defaults: UserDefaults, text: ForkTranscribeStrings) {
            kinds = ForkTranscribeOutput.kinds(defaults.string(forKey: ForkDefaultsKey.transcribeFormats))
            let path = defaults.string(forKey: ForkDefaultsKey.transcribeFolder) ?? ""
            folder = defaults.bool(forKey: ForkDefaultsKey.transcribeUsesFolder) && !path.isEmpty
                ? URL(fileURLWithPath: path, isDirectory: true) : nil
            replacements = defaults.bool(forKey: ForkDefaultsKey.transcribeReplacements)
                ? ForkDictationSupport.replacements(from: defaults.string(forKey: ForkDefaultsKey.dictationReplacements) ?? "")
                : []
            self.text = text
        }
    }

    private struct Result {
        var outcome: Swift.Result<Written, ForkTranscribeFailure>
        var cancelled = false
        var duration: TimeInterval?
        var processing: TimeInterval?
    }

    private struct Written {
        var outputs: [URL]
        var usedFallback: Bool
        var words: Int
        var language: String?
    }

    /// Work queue: the file's text, written, or why not.
    private func run(_ job: ForkTranscribeJob, model: URL, settings: Settings, fallback: URL,
                     stop: ForkMeetingTranscriptStop) -> Result {
        if let missing = Self.check(job.source) { return Result(outcome: .failure(missing)) }
        var lastPublished = 0.0
        let heard: ForkTranscribeLocalEngine.Heard
        do {
            heard = try local.transcribe(job.source, modelDirectory: model, language: job.language.code) { [weak self] fraction in
                if fraction == 0 || fraction - lastPublished >= 0.004 {
                    lastPublished = fraction
                    DispatchQueue.main.async { self?.progressed(job.id, fraction) }
                }
                return !stop.isCancelled
            }
        } catch is CancellationError {
            return Result(outcome: .failure(.engine), cancelled: true)
        } catch let failure as ForkTranscribeFailure {
            log.error("file transcript failed: \(failure.rawValue, privacy: .public)")
            return Result(outcome: .failure(failure))
        } catch {
            return Result(outcome: .failure(.engine))
        }
        guard !stop.isCancelled else { return Result(outcome: .failure(.engine), cancelled: true) }
        DispatchQueue.main.async { [weak self] in self?.update(job.id, saving: false) { $0.stage = .writing } }

        var segments = ForkTranscribeFormat.sentences(heard.words)
        if !settings.replacements.isEmpty {
            for index in segments.indices {
                segments[index].text = ForkDictationReplacements.apply(settings.replacements, to: segments[index].text)
            }
        }
        guard !segments.isEmpty else {
            return Result(outcome: .failure(.nothingHeard), duration: heard.duration, processing: heard.processing)
        }
        let words = segments.map(\.text).joined(separator: " ")
        let language = ForkMeetingTranscript.baseLanguage(NLLanguageRecognizer.dominantLanguage(for: words)?.rawValue)
        let document = ForkTranscribeDocument(segments: segments, duration: heard.duration, language: language)
        PrivateFileStore.createDirectory(at: directory)
        if let data = try? JSONEncoder().encode(document) { PrivateFileStore.write(data, to: documentURL(job.id)) }

        let written = Self.write(document, for: job, settings: settings, fallback: fallback)
        switch written {
        case let .success((outputs, usedFallback)):
            return Result(outcome: .success(Written(outputs: outputs, usedFallback: usedFallback,
                                                    words: document.wordCount, language: language)),
                          duration: heard.duration, processing: heard.processing)
        case let .failure(failure):
            return Result(outcome: .failure(failure), duration: heard.duration, processing: heard.processing)
        }
    }

    /// Whether the file can be read now: gone, or in iCloud and not here.
    private static func check(_ url: URL) -> ForkTranscribeFailure? {
        guard FileManager.default.fileExists(atPath: url.path) else { return .fileMissing }
        let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
        if values?.isUbiquitousItem == true, values?.ubiquitousItemDownloadingStatus != .current {
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            return .notDownloaded
        }
        return nil
    }

    /// `~/Documents/Transcriptions`: where a text goes when the file's own
    /// folder refuses it.
    static var fallbackFolder: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents")
        return documents.appendingPathComponent("Transcriptions", isDirectory: true)
    }

    /// The files, beside the source (or in the chosen folder), else in the
    /// fallback; never over an existing file.
    static func write(_ document: ForkTranscribeDocument, for job: ForkTranscribeJob, settings: Settings,
                      fallback: URL) -> Swift.Result<([URL], Bool), ForkTranscribeFailure> {
        let manager = FileManager.default
        let labels = labels(for: document, settings.text, at: Date())
        let contents: [ForkTranscribeOutput.Kind: String] = [
            .md: ForkTranscribeFormat.markdown(document, fileName: job.name, labels: labels),
            .txt: ForkTranscribeFormat.text(document, labels: labels),
            .srt: ForkTranscribeFormat.subtitles(document, labels: labels),
        ]
        let (first, firstIsFallback) = ForkTranscribeOutput.folder(
            for: job.source, chosen: settings.folder, fallback: fallback,
            writable: { manager.isWritableFile(atPath: $0.path) })
        var attempts = [(first, firstIsFallback)]
        if !firstIsFallback { attempts.append((fallback, true)) }
        for (folder, isFallback) in attempts {
            if isFallback { try? manager.createDirectory(at: folder, withIntermediateDirectories: true) }
            let urls = ForkTranscribeOutput.urls(for: job.source, in: folder, kinds: settings.kinds,
                                                 exists: { manager.fileExists(atPath: $0.path) })
            var done: [URL] = []
            for (kind, url) in zip(settings.kinds, urls) {
                guard (try? (contents[kind] ?? "").write(to: url, atomically: true, encoding: .utf8)) != nil else { break }
                done.append(url)
            }
            if done.count == urls.count { return .success((done, isFallback)) }
            done.forEach { try? manager.removeItem(at: $0) }
        }
        return .failure(.writeFailed)
    }

    static func labels(for document: ForkTranscribeDocument, _ text: ForkTranscribeStrings,
                       at date: Date) -> ForkTranscribeFormat.Labels {
        let when = DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short)
        return ForkTranscribeFormat.Labels(
            title: { String(format: text.fileTitle, $0) },
            summary: String(format: text.fileSummaryLocal, ForkTranscribeRules.clock(document.duration), when),
            voice: { String(format: text.voice, $0) },
            separator: text.separator)
    }

    private func progressed(_ id: UUID, _ fraction: Double) {
        guard runningID == id else { return }
        if job(id)?.stage == .loading { update(id, saving: false) { $0.stage = .transcribing } }
        if fraction > progress { progress = fraction }
    }

    private func finished(_ id: UUID, _ result: Result) {
        dispatchPrecondition(condition: .onQueue(.main))
        runningID = nil
        stop = nil
        progress = 0
        var outcome: ForkTranscribeJob?
        update(id) { job in
            job.finished = Date()
            job.duration = result.duration ?? job.duration
            job.processingSeconds = result.processing
            if result.cancelled {
                job.stage = .cancelled
            } else {
                switch result.outcome {
                case let .success(written):
                    job.stage = .done
                    job.outputs = written.outputs
                    job.usedFallbackFolder = written.usedFallback
                    job.words = written.words
                    job.heardLanguage = written.language
                case let .failure(failure):
                    job.stage = .failed(failure)
                }
            }
            outcome = job
        }
        if let outcome {
            log.notice("file transcript: \(String(describing: outcome.stage), privacy: .public) in \(outcome.processingSeconds ?? 0, privacy: .public) s")
            ForkTranscribeIsland.tell(outcome)
        }
        startNext()
    }

    /// A file waiting for a meeting's transcript goes once that one ends.
    private func watchMeetingTranscript() {
        guard meetingObserver == nil else { return }
        meetingObserver = ForkMeetingTranscriber.shared.$running
            .map { $0 == nil }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] free in
                guard free, let self else { return }
                self.meetingObserver = nil
                for job in self.jobs where job.stage == .waitingForEngine {
                    self.update(job.id, saving: false) { $0.stage = .queued }
                }
                self.startNext()
            }
    }

    /// The updater waits for a file at work or about to be. Not for one
    /// waiting for Parakeet: it could wait forever, and hold every update.
    private func activityChanged() {
        ForkMeetingActivity.setTranscribingFiles(enabled && (runningID != nil || jobs.contains {
            $0.stage == .queued || $0.stage == .waitingForEngine || $0.stage.isRunning
        }))
    }

    // MARK: - The list on disk

    private var indexURL: URL { directory.appendingPathComponent("jobs.json") }

    private func documentURL(_ id: UUID) -> URL { directory.appendingPathComponent("\(id.uuidString).json") }

    private func update(_ id: UUID, saving: Bool = true, _ change: (inout ForkTranscribeJob) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        change(&jobs[index])
        if saving { save() }
        activityChanged()
    }

    private func save() {
        let kept = ForkTranscribeRules.trimmed(jobs)
        if kept.count != jobs.count {
            let gone = Set(jobs.map(\.id)).subtracting(kept.map(\.id))
            gone.forEach { try? FileManager.default.removeItem(at: documentURL($0)) }
            jobs = kept
        }
        guard PrivateFileStore.createDirectory(at: directory), let data = try? JSONEncoder().encode(jobs) else { return }
        PrivateFileStore.write(data, to: indexURL)
    }

    // MARK: - Diagnostic

    /// What "Copy Diagnostic" gives: the job's facts, never its text.
    func diagnostic(_ id: UUID) -> String {
        guard let job = job(id) else { return "" }
        let info = Bundle.main.infoDictionary
        let lines = [
            "Swishsaint file transcription",
            "build: \(info?["CFBundleVersion"] as? String ?? "?") · macOS \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "file: .\(job.source.pathExtension.lowercased()) · \(Self.fileSize(job.source))",
            "engine: \(job.engine.rawValue) · language: \(job.language.rawValue) · heard: \(job.heardLanguage ?? "?")",
            "stage: \(String(describing: job.stage))",
            "duration: \(job.duration.map { ForkTranscribeRules.clock($0) } ?? "?") · work: \(job.processingSeconds.map { String(format: "%.1f s", $0) } ?? "?")",
            "words: \(job.words.map(String.init) ?? "?") · outputs: \(job.outputs.count) · fallback: \(job.usedFallbackFolder)",
            "model: \(ForkParakeetModelStore.shared.installedDirectory == nil ? "missing" : "installed")",
        ]
        return lines.joined(separator: "\n")
    }

    private static func fileSize(_ url: URL) -> String {
        guard let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize else { return "size ?" }
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
}
