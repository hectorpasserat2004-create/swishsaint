// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// "File by company" (the CRM's block, `filesByCompany`): once the CRM says
/// what became of a meeting (ready or failed, `ForkCastralRecord.isSettled`),
/// the meeting's folder goes into the folder of its company's domain inside
/// the meetings folder (`ForkMeetingCompanyFolder`), made when missing. The
/// library, the follow and the sends find it there by its id.
///
/// - Asked when the follow settles a meeting, and at launch and when the
///   option is turned on for the meetings left at their old place (a record
///   written before the domain was kept learns it with one status read).
/// - Never while the meeting is written, sent, moved to another
///   appointment, chosen for, transcribed or summarised on this Mac: it is
///   filed at the next settling or launch.
extension ForkMeetingExports {
    /// The folders a transcription or a summary on this Mac works on, or
    /// waits to. Main thread.
    private static var workedOnFolders: Set<String> {
        let transcriber = ForkMeetingTranscriber.shared, summarizer = ForkMeetingSummarizer.shared
        let folders = ([transcriber.running?.job].compactMap { $0 } + transcriber.waiting).map(\.folder)
            + ([summarizer.running?.job].compactMap { $0 } + summarizer.waiting).map(\.folder)
        return Set(folders.map { $0.standardizedFileURL.path })
    }

    /// Main thread. Files the meeting when the CRM exporter files by
    /// company and its company's domain is known.
    func fileByCompany(_ folder: URL) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard isWantedNow, let config = castralConfig, config.filesByCompany == true, !listChanged else { return }
        let path = folder.standardizedFileURL.path
        guard !isSending(folder), !castralMoving.contains(path),
              castralChoice?.folder.standardizedFileURL.path != path else { return }
        let busy = foldersWritten.union(sendingFolders).union(Self.workedOnFolders)
        guard !busy.contains(path) else { return }
        let exporter = castralExporter(config, request: nil)
        let store = self.store
        DispatchQueue.global(qos: .utility).async { [self] in
            guard case let .success(sidecar) = store.sidecar(in: folder), sidecar.state == .complete,
                  var record = ForkCastralRecord(json: sidecar.castral), record.target == config.id,
                  record.booking != nil, record.isSettled else { return }
            var learnt = false
            // A record written before the domain was kept: one status read.
            if record.companyFolder == nil, record.company != nil, record.step == .started,
               let client = try? exporter.credentials(),
               case let .success(status)? = try? Self.blocking({ await client.status(record.deposit) }) {
                record.apply(status, at: Date())
                learnt = store.writeCastral(record, in: folder, id: sidecar.id) != nil
            }
            let shown = record
            let moved = record.companyFolder.flatMap {
                store.fileInCompany(folder, id: sidecar.id, company: $0, busy: busy)
            }
            DispatchQueue.main.async { [self] in
                if learnt { castralRecords[path] = shown }
                if let moved { folderMoved(from: folder, to: moved) }
            }
        }
    }

    /// Main thread, at launch and when the option is turned on: the
    /// meetings left where they were.
    func fileUnfiled() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard isWantedNow, let config = castralConfig, config.filesByCompany == true else { return }
        let store = self.store
        DispatchQueue.global(qos: .utility).async { [self] in
            let folders = store.castralUnfiled(target: config.id)
            guard !folders.isEmpty else { return }
            DispatchQueue.main.async { [self] in folders.forEach(fileByCompany) }
        }
    }
}
