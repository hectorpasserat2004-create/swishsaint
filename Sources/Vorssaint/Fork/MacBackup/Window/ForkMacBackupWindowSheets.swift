// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import AppKit
import SwiftUI

// MARK: - Restore

/// « Restaurer… » (plan §6.3): what, where, the checks, then the progress
/// and the result, one step at a time.
struct ForkMacBackupRestoreSheet: View {
    @ObservedObject var flow: ForkMacBackupRestoreFlow
    let dismiss: () -> Void

    private var text: ForkMacBackupWindowStrings { flow.text }
    private var shared: ForkMacBackupStrings { .strings(flow.language) }
    private var locale: Locale { flow.language.formattingLocale() }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            Group {
                switch flow.step {
                case .what: what
                case .place: place
                case .checks: checks
                case .progress: progress
                case .result: result
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 210, alignment: .topLeading)
            Divider()
            buttons
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
        }
        .frame(width: 560)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(text.restoreTitle, systemImage: "clock.arrow.circlepath")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
            HStack(spacing: 6) {
                ForEach(ForkMacBackupRestoreFlow.Step.allCases, id: \.self) { step in
                    let current = step == flow.step
                    let done = step < flow.step
                    HStack(spacing: 4) {
                        ZStack {
                            Circle().fill(done || current ? ForkMacBackupWindowStyle.teal : Color.secondary.opacity(0.2))
                            if done {
                                Image(systemName: "checkmark").font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
                            } else {
                                Text("\(step.rawValue + 1)").font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(current ? Color.white : Color.secondary)
                            }
                        }
                        .frame(width: 16, height: 16)
                        Text(title(step))
                            .font(.caption.weight(current ? .semibold : .regular))
                            .foregroundStyle(current ? Color.primary : Color.secondary)
                    }
                    if step != .result {
                        Rectangle().fill(Color.secondary.opacity(0.25)).frame(width: 14, height: 1)
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title(flow.step))
        }
        .padding(20)
    }

    private func title(_ step: ForkMacBackupRestoreFlow.Step) -> String {
        switch step {
        case .what: return text.stepWhat
        case .place: return text.stepWhere
        case .checks: return text.stepChecks
        case .progress: return text.stepProgress
        case .result: return text.stepDone
        }
    }

    // MARK: Steps

    private var what: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(format: text.fromSnapshot, ForkMacBackupFormat.dayAndTime(flow.snapshot.date, locale: locale)))
                .font(.callout)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(flow.items.prefix(6)) { item in
                    HStack(spacing: 8) {
                        Image(nsImage: ForkMacBackupFileTable.Coordinator.icon(for: item))
                            .resizable()
                            .frame(width: 18, height: 18)
                        Text(item.name).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text(item.size.map { ForkMacBackupFormat.bytes($0, locale: locale) } ?? "—")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                if flow.items.count > 6 {
                    Text("+ \(flow.items.count - 6)")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
            Text(text.items(Int(flow.size.files), flow.language) + " · "
                 + ForkMacBackupFormat.bytes(flow.size.bytes, locale: locale))
                .font(.headline)
            if flow.isOtherMac {
                Label(text.checkOtherMac, systemImage: "laptopcomputer")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var place: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker(text.stepWhere, selection: $flow.destination) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(text.whereSeparate)
                    HStack {
                        Text((flow.separateFolder.path as NSString).abbreviatingWithTildeInPath)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button(text.chooseFolder) { flow.chooseFolder(in: NSApp.keyWindow) }
                            .controlSize(.small)
                    }
                }
                .tag(ForkMacBackupRestoreFlow.Destination.separate)
                if flow.canRestoreInPlace {
                    Text(text.whereOriginal).tag(ForkMacBackupRestoreFlow.Destination.original)
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            if flow.destination == .original {
                Picker(text.whereOriginal, selection: $flow.policy) {
                    ForEach(ForkMacBackupRestoreRequest.Overwrite.allCases, id: \.self) { policy in
                        Text(text.title(policy)).tag(policy)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                .padding(.leading, 22)
            }
        }
    }

    private var checks: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text((flow.targetFolder.path as NSString).abbreviatingWithTildeInPath)
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            if let checks = flow.checks {
                switch checks.room {
                case .enough:
                    check(true, String(format: text.checkSpaceOK,
                                       ForkMacBackupFormat.bytes(checks.available ?? 0, locale: locale),
                                       ForkMacBackupFormat.bytes(checks.required, locale: locale)))
                case .short(let missing):
                    check(false, String(format: text.checkSpaceShort, ForkMacBackupFormat.bytes(missing, locale: locale)))
                case .unknown:
                    warning(text.checkSpaceUnknown)
                }
                check(checks.writable, checks.writable ? text.checkWriteOK : text.checkWriteDenied)
                if checks.insideSource { warning(text.checkActiveSource) }
                if flow.destination == .original && flow.policy == .replaceAll { warning(text.checkReplaceAll) }
                if flow.isOtherMac { warning(text.checkOtherMac) }
            } else {
                ProgressView().controlSize(.small)
            }
        }
    }

    private func check(_ ok: Bool, _ line: String) -> some View {
        Label {
            Text(line)
        } icon: {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                .foregroundStyle(ok ? ForkMacBackupWindowStyle.teal : Color.red)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func warning(_ line: String) -> some View {
        Label {
            Text(line)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 12) {
            let progress = flow.progress
            let total = progress?.bytesTotal ?? 0
            if total > 0, let progress {
                ProgressView(value: Double(min(progress.bytesDone, total)), total: Double(total))
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
            }
            if let progress {
                Text([ForkMacBackupFormat.bytes(progress.bytesDone, locale: locale)
                      + (total > 0 ? " / " + ForkMacBackupFormat.bytes(total, locale: locale) : ""),
                      text.restored(Int(progress.files), flow.language)].joined(separator: " · "))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                if progress.errors > 0 {
                    Text(text.errors(progress.errors, flow.language))
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            }
            Text((flow.targetFolder.path as NSString).abbreviatingWithTildeInPath)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    @ViewBuilder private var result: some View {
        switch flow.outcome {
        case .complete(let report), .partial(let report):
            VStack(alignment: .leading, spacing: 10) {
                Label(report.failures.isEmpty ? text.resultComplete : text.resultPartial,
                      systemImage: report.failures.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(report.failures.isEmpty ? ForkMacBackupWindowStyle.teal : Color.orange)
                Text(text.restored(Int(report.files), flow.language) + " · "
                     + ForkMacBackupFormat.bytes(report.bytes, locale: locale))
                if !report.failures.isEmpty {
                    Text(text.errors(report.failures.count, flow.language)).foregroundStyle(.orange)
                    ForEach(Array(report.failures.prefix(5).enumerated()), id: \.offset) { _, failure in
                        Text(failure.cause.title(shared) + " · " + failure.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Text((report.destinationPath as NSString).abbreviatingWithTildeInPath)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        case .failed(let message):
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text(text.resultFailed).font(.title3.weight(.semibold))
                    Text(message).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
            }
        case .canceled:
            Label(text.resultCanceled, systemImage: "stop.circle")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
        case nil:
            EmptyView()
        }
    }

    // MARK: Buttons

    private var buttons: some View {
        HStack {
            switch flow.step {
            case .what, .place, .checks:
                Button(text.cancel, role: .cancel, action: dismiss)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if flow.step != .what {
                    Button(text.back) { flow.back() }
                }
                Button(flow.step == .checks ? text.startRestore : text.continueAction) { flow.next() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(flow.step == .checks && flow.checks?.canStart != true)
            case .progress:
                Spacer()
                Button(text.cancel, role: .cancel) { flow.cancel() }
                    .keyboardShortcut(.cancelAction)
            case .result:
                if flow.resultURL != nil {
                    Button(text.showInFinder) { flow.showInFinder() }
                    Button(text.open) { flow.openResult() }
                }
                Spacer()
                Button(text.done, action: dismiss)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}

// MARK: - Versions

/// The distinct versions of one file, newest first, each with Quick Look.
struct ForkMacBackupVersionsSheet: View {
    @ObservedObject var model: ForkMacBackupWindowModel
    @ObservedObject var sheet: ForkMacBackupVersionsModel

    private var text: ForkMacBackupWindowStrings { model.text }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(nsImage: ForkMacBackupFileTable.Coordinator.icon(for: sheet.entry))
                    .resizable()
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: text.versionsOf, sheet.entry.name))
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if case .loaded(let all, let distinct) = sheet.state {
                        Text(text.saves(all, model.language) + " · " + text.distinct(distinct.count, model.language))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(20)
            Divider()
            Group {
                switch sheet.state {
                case .loading:
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                case .failed(let message):
                    ForkMacBackupEmptyState(symbol: "exclamationmark.triangle",
                                            title: String(format: text.readFailed, message))
                case .loaded(_, let distinct) where distinct.isEmpty:
                    ForkMacBackupEmptyState(symbol: "square.stack.3d.up.slash", title: text.versionsEmpty)
                case .loaded(_, let distinct):
                    List {
                        ForEach(Array(distinct.enumerated()), id: \.element.id) { index, version in
                            row(version, isLatest: index == 0)
                        }
                    }
                    .listStyle(.inset(alternatesRowBackgrounds: true))
                }
            }
            .frame(minHeight: 260)
            Divider()
            HStack {
                Spacer()
                Button(text.close) { model.versionsSheet = nil }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(14)
        }
        .frame(width: 600, height: 440)
    }

    private func row(_ version: ForkMacBackupDistinctVersion, isLatest: Bool) -> some View {
        let locale = model.locale
        let range = version.snapshotCount > 1
            ? String(format: text.seenFromTo, ForkMacBackupFormat.dayAndTime(version.firstSeen, locale: locale),
                     ForkMacBackupFormat.dayAndTime(version.lastSeen, locale: locale))
            : String(format: text.seenOnce, ForkMacBackupFormat.dayAndTime(version.lastSeen, locale: locale))
        var entry = sheet.entry
        entry.objectID = version.newest.objectID
        entry.size = version.newest.size
        entry.modified = version.newest.modified
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(version.newest.modified.map { ForkMacBackupFormat.dayAndTime($0, locale: locale) } ?? range)
                    .font(.body.weight(isLatest ? .semibold : .regular))
                Text(range + " · " + text.saves(version.snapshotCount, model.language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(ForkMacBackupFormat.bytes(version.newest.size, locale: locale))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Button {
                model.previewFile(entry, in: version.newest.manifestID)
            } label: {
                Image(systemName: "eye")
            }
            .help(text.quickLook)
            .accessibilityLabel(text.quickLook)
            Button(text.showInBackup) {
                model.reveal(relativePath: sheet.entry.relativePath, in: version.newest.manifestID)
            }
        }
        .padding(.vertical, 3)
    }
}

// MARK: - « Is this file backed up? »

struct ForkMacBackupVerdictSheet: View {
    @ObservedObject var model: ForkMacBackupWindowModel
    @ObservedObject var verdict: ForkMacBackupVerdictModel

    private var text: ForkMacBackupWindowStrings { model.text }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(text.verdictTitle)
                .font(.title3.weight(.semibold))
            HStack(spacing: 12) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: verdict.url.path))
                    .resizable()
                    .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(verdict.url.lastPathComponent)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text((verdict.url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            answer
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
            HStack {
                if case .decided(_, let found?) = verdict.result {
                    Button(text.showInBackup) {
                        model.sidebarSelection = .source(found.key.id)
                        model.reveal(relativePath: found.entry.relativePath, in: found.snapshot.id)
                    }
                }
                Spacer()
                Button(text.close) { model.verdict = nil }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    @ViewBuilder private var answer: some View {
        switch verdict.result {
        case .checking:
            HStack {
                ProgressView().controlSize(.small)
                Text(text.checking)
            }
        case .decided(let decided, _):
            let (symbol, color, line) = describe(decided)
            Label {
                Text(line).fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: symbol).foregroundStyle(color)
            }
            .font(.body.weight(.medium))
        }
    }

    private func describe(_ verdict: ForkMacBackupFileVerdict) -> (String, Color, String) {
        let locale = model.locale
        switch verdict {
        case .backedUp(let date):
            return ("checkmark.seal.fill", ForkMacBackupWindowStyle.teal,
                    String(format: text.verdictBackedUp, ForkMacBackupFormat.dayAndTime(date, locale: locale)))
        case .modifiedSince(let date, _):
            return ("circle.lefthalf.filled", .orange,
                    String(format: text.verdictModified, ForkMacBackupFormat.dayAndTime(date, locale: locale)))
        case .notYet(let next):
            if let next {
                return ("clock", .orange, String(format: text.verdictNotYet,
                                                 ForkMacBackupFormat.relative(next, now: model.now(), locale: locale)))
            }
            return ("clock", .orange, text.verdictNotYetSoon)
        case .excluded(let rule):
            return ("minus.circle.fill", .secondary, String(format: text.verdictExcluded, rule))
        case .cloudOnly:
            return ("icloud.slash", .secondary, text.verdictCloudOnly)
        case .outsideSources:
            return ("minus.circle.fill", .secondary, text.verdictOutside)
        case .unknown:
            return ("questionmark.circle", .secondary, text.verdictUnknown)
        }
    }
}
