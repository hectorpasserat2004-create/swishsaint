// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import AppKit
import SwiftUI

/// The inspector column (plan §6.2): the selection on top, then the backup
/// shown — its date, its proof, its figures, the files it could not read
/// grouped by cause with what to do.
struct ForkMacBackupInspector: View {
    @ObservedObject var model: ForkMacBackupWindowModel

    private var text: ForkMacBackupWindowStrings { model.text }
    private var shared: ForkMacBackupStrings { model.shared }
    private var locale: Locale { model.locale }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if !model.selectedEntries.isEmpty {
                    selectionSection
                    Divider()
                }
                if let snapshot = model.selectedSnapshot {
                    snapshotSection(snapshot)
                    failuresSection(snapshot)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Selection

    @ViewBuilder private var selectionSection: some View {
        let entries = model.selectedEntries
        if entries.count == 1, let entry = entries[0] as ForkMacBackupBrowseEntry? {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 10) {
                    Image(nsImage: ForkMacBackupFileTable.Coordinator.icon(for: entry))
                        .resizable()
                        .frame(width: 44, height: 44)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.name)
                            .font(.headline)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                        Text(entry.size.map { ForkMacBackupFormat.bytes($0, locale: locale) } ?? "—")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                facts([
                    (text.columnModified, entry.modified.map { ForkMacBackupFormat.dayAndTime($0, locale: locale) } ?? "—"),
                    (text.columnStatus, model.isOtherMac ? "—" : text.title(entry.localStatus)),
                ] + (entry.isDirectory ? [(text.files, entry.fileCount.formatted(.number.locale(locale)))] : []))
                if entry.failedCount > 0 {
                    Label(text.unread(Int(entry.failedCount), model.language), systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
                actions(for: entry)
            }
        } else if entries.count > 1 {
            let size = ForkMacBackupSelectionSize.of(entries)
            VStack(alignment: .leading, spacing: 10) {
                Text(text.selected(entries.count, model.language))
                    .font(.headline)
                facts([(text.realSize, ForkMacBackupFormat.bytes(size.bytes, locale: locale)),
                       (text.files, size.files.formatted(.number.locale(locale)))])
                HStack {
                    Button(shared.restore) { model.beginRestore() }
                    if !model.isOtherMac {
                        Button(text.restoreHere) { model.beginRestore(original: true) }
                    }
                }
                .controlSize(.regular)
            }
        }
    }

    /// One button per line, full width: every language fits.
    private func actions(for entry: ForkMacBackupBrowseEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if !entry.isDirectory {
                action(text.quickLook, "eye") { model.previewFile(entry) }
                    .help(text.quickLook + " (␣)")
            }
            action(shared.restore, "clock.arrow.circlepath") { model.beginRestore([entry]) }
            if !model.isOtherMac {
                action(text.restoreHere, "arrow.uturn.backward") { model.beginRestore([entry], original: true) }
            }
            if !entry.isDirectory {
                action(model.versionCounts[entry.relativePath].map { String(format: text.versionsCount, $0) } ?? text.versions,
                       "square.stack.3d.up") { model.showVersions(entry) }
            }
        }
        .controlSize(.regular)
    }

    private func action(_ title: String, _ symbol: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Label(title, systemImage: symbol)
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Snapshot

    private func snapshotSection(_ snapshot: ForkMacBackupSnapshotItem) -> some View {
        let proof = snapshot.proof
        let run = model.ledger.run(saving: snapshot.id)
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(String(format: text.snapshotOf, ForkMacBackupFormat.dayAndTime(snapshot.date, locale: locale)))
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                HStack(spacing: 6) {
                    if proof.isPartial {
                        Text(text.partial)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.orange.opacity(0.18)))
                            .foregroundStyle(.orange)
                    }
                    Text(snapshot.key.machine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(text.proof.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForkMacBackupWindowProofLadder(level: proof.level, isPartial: proof.isPartial, shared: shared, text: text)
            }
            facts([
                (text.files, proof.files.formatted(.number.locale(locale))),
                (text.realSize, ForkMacBackupFormat.bytes(proof.bytes, locale: locale)),
                (text.sent, run.map { ForkMacBackupFormat.bytes($0.bytesSent, locale: locale) } ?? shared.unknown),
                (text.duration, (run?.duration ?? proof.startTime.map { proof.endTime.timeIntervalSince($0) })
                    .map { ForkMacBackupFormat.duration($0, locale: locale) } ?? shared.unknown),
            ])
            VStack(alignment: .leading, spacing: 4) {
                if let verified = proof.verifiedAt {
                    detailLine("checkmark.seal", String(format: text.verifiedOn,
                                                        ForkMacBackupFormat.dayAndTime(verified, locale: locale),
                                                        ForkMacBackupFormat.batteryPoints(proof.verifiedPercent ?? 0,
                                                                                          locale: locale)))
                }
                if let tested = proof.restoreTestedAt {
                    detailLine("arrow.counterclockwise.circle",
                               String(format: text.restoreTestedOn, ForkMacBackupFormat.dayAndTime(tested, locale: locale)))
                }
                if let reason = proof.incomplete {
                    detailLine("pause.circle", String(format: text.interrupted, reason))
                }
                if !proof.cloudOnly.isEmpty {
                    detailLine("icloud", text.cloud(proof.cloudOnly.count, model.language))
                }
            }
        }
    }

    private func detailLine(_ symbol: String, _ line: String) -> some View {
        Label(line, systemImage: symbol)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Failures

    @ViewBuilder private func failuresSection(_ snapshot: ForkMacBackupSnapshotItem) -> some View {
        let (named, unnamed) = model.failures(of: snapshot)
        if !named.isEmpty || unnamed > 0 {
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                Label(text.failuresTitle, systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                    .accessibilityAddTraits(.isHeader)
                ForEach(groups(named), id: \.cause) { group in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(group.cause.title(shared))
                                .font(.callout.weight(.semibold))
                            Spacer()
                            Text(group.failures.count.formatted(.number.locale(locale)))
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        ForEach(Array(group.failures.prefix(4).enumerated()), id: \.offset) { _, failure in
                            Text(ForkMacBackupFormat.middleTruncated(failure.path, limit: 44, home: nil))
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .help(failure.path + "\n" + failure.message)
                        }
                        if group.failures.count > 4 {
                            Text("+ \((group.failures.count - 4).formatted(.number.locale(locale)))")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        if let remedy = group.cause.remedy(shared) {
                            Button(remedy) {
                                model.perform(group.cause, failures: group.failures, sourcePath: snapshot.key.path)
                            }
                            .controlSize(.small)
                            .disabled(model.isOtherMac && group.cause != .other)
                        }
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.07)))
                }
                if unnamed > 0 {
                    Text(String(format: text.failuresUnnamed, unnamed))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func groups(_ failures: [ForkMacBackupFailure])
        -> [(cause: ForkMacBackupFailureCause, failures: [ForkMacBackupFailure])] {
        ForkMacBackupFailureCause.allCases.compactMap { cause in
            let matching = failures.filter { $0.cause == cause }
            return matching.isEmpty ? nil : (cause, matching)
        }
    }

    // MARK: Parts

    private func facts(_ rows: [(String, String)]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 5) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    Text(row.0)
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.leading)
                    Text(row.1)
                        .monospacedDigit()
                        .textSelection(.enabled)
                }
                .font(.callout)
            }
        }
    }
}
