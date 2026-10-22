// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

extension ForkMeetingStore {
    /// Writes a meeting's CRM record (`castral` of its `meeting.json`),
    /// after every write asked before, in the folder where the meeting is
    /// now (moved in the Finder, renamed by the library). Off the store's
    /// queue; that folder, or `nil` when the file was left as it is.
    @discardableResult
    func writeCastral(_ record: ForkCastralRecord, in folder: URL, id: UUID?) -> URL? {
        dispatchPrecondition(condition: .notOnQueue(queue))
        return queue.sync {
            guard let found = locate(folder, id: id) else { return nil }
            var patch = ForkMeetingSidecarPatch()
            patch.castral = record.json
            let read = ForkMeetingSidecar.read(at: found.appendingPathComponent(ForkMeetingFolder.sidecarName))
            guard let next = ForkMeetingSidecar.rewriting(read, with: patch) else { return nil }
            return writeSidecar(next, in: found) == nil ? found : nil
        }
    }

    /// The meetings of the folder whose CRM record is not settled: a send
    /// cut short (uploading, uploaded), or a deposit still at work on the
    /// server, for the resume at launch; those filed in a company folder
    /// too (a move to another appointment writes the report again). Off the
    /// store's queue.
    func castralUnsettled() -> [(folder: URL, id: UUID?, record: ForkCastralRecord)] {
        dispatchPrecondition(condition: .notOnQueue(queue))
        let root = root()
        return ForkMeetingCompanyFolder.meetings(in: root).compactMap { name in
            let folder = root.appendingPathComponent(name, isDirectory: true)
            guard case let .success(sidecar) = sidecar(in: folder),
                  let record = ForkCastralRecord(json: sidecar.castral), !record.isSettled else {
                return nil
            }
            return (folder, sidecar.id, record)
        }
    }

    /// The meetings to file in their company's folder now, for the pass at
    /// launch: settled on the CRM, their appointment known, not in the
    /// folder of their company's domain; or at the root, with a company
    /// whose domain the record does not hold yet (written before it did).
    /// Off the store's queue.
    func castralUnfiled(target: String) -> [URL] {
        dispatchPrecondition(condition: .notOnQueue(queue))
        let root = root()
        return ForkMeetingCompanyFolder.meetings(in: root).compactMap { name in
            let folder = root.appendingPathComponent(name, isDirectory: true)
            guard case let .success(sidecar) = sidecar(in: folder), sidecar.state == .complete,
                  let record = ForkCastralRecord(json: sidecar.castral), record.target == target,
                  record.booking != nil, record.isSettled else { return nil }
            let here = ForkMeetingCompanyFolder.company(of: name)
            if let company = record.companyFolder { return company == here ? nil : folder }
            return here == nil && record.company != nil ? folder : nil
        }
    }
}
