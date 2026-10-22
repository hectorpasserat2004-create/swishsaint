// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Charts
import SwiftUI

/// « Santé » (plan §11.3, §7.4): the chain in large, the space with its
/// dates and sources (« inconnu » rather than invented), the agent and the
/// engine, the cost.
struct ForkMacBackupHealthView: View {
    @ObservedObject var model: ForkMacBackupWindowModel
    @ObservedObject var status: ForkMacBackupStatusModel
    @ObservedObject private var engineStore = ForkMacBackupEngineStore.shared

    private var text: ForkMacBackupWindowStrings { model.text }
    private var shared: ForkMacBackupStrings { model.shared }
    private var locale: Locale { model.locale }
    private var presentation: ForkMacBackupPresentation { status.presentation }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                chain
                capacity
                HStack(alignment: .top, spacing: 16) {
                    agent
                    cost
                }
            }
            .padding(20)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Chain

    private struct Node: Identifiable {
        var id: String
        var title: String
        var detail: String
        var symbol: String
        var status: ForkMacBackupPresentation.ChainStatus?
    }

    private var nodes: [Node] {
        if let chain = model.ledger.profile?.chain, !chain.isEmpty {
            return chain.map { node in
                Node(id: node.id, title: node.displayTitle(shared), detail: node.detail, symbol: node.symbol,
                     status: presentation.chain.first { $0.id == node.id })
            }
        }
        return presentation.chain.map { item in
            Node(id: item.id, title: item.displayTitle(shared), detail: "", symbol: item.kind.defaultSymbol, status: item)
        }
    }

    private var chain: some View {
        ForkMacBackupCard(title: text.chainTitle, symbol: "link") {
            if nodes.isEmpty {
                Text(shared.notConfigured).foregroundStyle(.secondary)
            } else {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
                        if index > 0 {
                            connector(from: nodes[index - 1], to: node)
                        }
                        nodeView(node)
                    }
                }
                .frame(maxWidth: .infinity)
                if let error = presentation.lastError {
                    Divider()
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(text.lastProblem + " · " + error.cause.title(shared)
                                 + " · " + ForkMacBackupFormat.relative(error.at, now: model.now(), locale: locale))
                                .font(.callout.weight(.semibold))
                            Text(error.cause.remedy(shared))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func connector(from: Node, to: Node) -> some View {
        let broken = from.status?.state == .broken || to.status?.state == .broken
        let unknown = to.status?.state == nil || to.status?.state == .unknown
        return Rectangle()
            .fill(broken ? Color.red.opacity(0.6) : (unknown ? Color.secondary.opacity(0.3) : ForkMacBackupWindowStyle.teal.opacity(0.6)))
            .frame(height: 2)
            .frame(minWidth: 12, maxWidth: 60)
            .padding(.top, 27)
            .accessibilityHidden(true)
    }

    private func nodeView(_ node: Node) -> some View {
        let state = node.status?.state ?? .unknown
        let color = ForkMacBackupWindowStyle.color(state)
        return VStack(spacing: 5) {
            ZStack {
                Circle().fill(color.opacity(0.12))
                Circle().strokeBorder(color, lineWidth: 2)
                Image(systemName: node.symbol)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(state == .unknown ? Color.secondary : color)
            }
            .frame(width: 56, height: 56)
            Text(node.title)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
            if !node.detail.isEmpty {
                Text(node.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Text(ForkMacBackupWindowStyle.title(state, shared)
                 + (node.status?.latencyMs.map { " · " + String(format: text.latency, $0.formatted(.number.locale(locale))) } ?? ""))
                .font(.caption)
                .foregroundStyle(color)
            if let checked = node.status?.checkedAt {
                Text(String(format: text.checkedAgo, ForkMacBackupFormat.relative(checked, now: model.now(), locale: locale)))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Text(incident(node))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minWidth: 96, maxWidth: 150)
        .accessibilityElement(children: .combine)
    }

    /// The node's last incident: the last error that named it.
    private func incident(_ node: Node) -> String {
        guard let error = presentation.lastError, error.nodeID == node.id else { return text.noIncident }
        return String(format: text.lastIncident, ForkMacBackupFormat.dayAndTime(error.at, locale: locale))
    }

    // MARK: Capacity

    private var capacity: some View {
        let samples = model.ledger.capacity
        let real = ForkMacBackupCapacitySupport.series(samples, kind: .real, now: model.now())
        let physical = ForkMacBackupCapacitySupport.series(samples, kind: .physical, now: model.now())
        let free = ForkMacBackupCapacitySupport.latest(samples, kind: .nasFree)
        return ForkMacBackupCard(title: text.capacityTitle, symbol: "internaldrive") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 12)], alignment: .leading, spacing: 12) {
                tile(text.capProtected, sample: ForkMacBackupCapacitySupport.latest(samples, kind: .real),
                     fallback: presentation.capacity.protectedBytes)
                tile(text.capSent, sample: ForkMacBackupCapacitySupport.latest(samples, kind: .sent),
                     fallback: presentation.capacity.lastSentBytes)
                tile(text.capRepository, sample: ForkMacBackupCapacitySupport.latest(samples, kind: .physical),
                     fallback: presentation.capacity.repositoryBytes)
                tile(text.capNASFree, sample: free, fallback: presentation.capacity.nasFreeBytes)
            }
            Divider()
            HStack {
                Text(text.chartTitle).font(.callout.weight(.semibold))
                Spacer()
                if let months = ForkMacBackupCapacitySupport.monthsUntilFull(physical: physical, free: free?.bytes) {
                    Text(text.fullIn(months: max(1, Int(months.rounded())), model.language))
                        .font(.callout)
                        .foregroundStyle(months < 6 ? Color.orange : Color.secondary)
                }
            }
            if real.count + physical.count < 2 {
                Text(text.chartEmpty).font(.callout).foregroundStyle(.secondary)
            } else {
                Chart {
                    ForEach(Array(real.enumerated()), id: \.offset) { _, sample in
                        LineMark(x: .value(text.columnDate, sample.date), y: .value(text.capProtected, Double(sample.bytes)))
                            .foregroundStyle(by: .value("series", text.capProtected))
                            .interpolationMethod(.monotone)
                    }
                    ForEach(Array(physical.enumerated()), id: \.offset) { _, sample in
                        LineMark(x: .value(text.columnDate, sample.date), y: .value(text.capRepository, Double(sample.bytes)))
                            .foregroundStyle(by: .value("series", text.capRepository))
                            .interpolationMethod(.monotone)
                    }
                }
                .chartForegroundStyleScale([text.capProtected: ForkMacBackupWindowStyle.teal,
                                            text.capRepository: Color.indigo])
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let bytes = value.as(Double.self) {
                                Text(ForkMacBackupFormat.bytes(Int64(bytes), locale: locale))
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .month)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month(.abbreviated).locale(locale))
                    }
                }
                .chartLegend(position: .bottom, alignment: .leading)
                .frame(height: 180)
            }
        }
    }

    private func tile(_ title: String, sample: ForkMacBackupCapacitySample?, fallback: Int64?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            if let sample {
                Text(ForkMacBackupFormat.bytes(sample.bytes, locale: locale))
                    .font(.title2.weight(.semibold).monospacedDigit())
                Text(String(format: text.measured, ForkMacBackupFormat.relative(sample.date, now: model.now(), locale: locale),
                            text.capacitySource(sample.source)))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else if let fallback, let measured = presentation.capacity.measuredAt {
                Text(ForkMacBackupFormat.bytes(fallback, locale: locale))
                    .font(.title2.weight(.semibold).monospacedDigit())
                Text(String(format: text.measured, ForkMacBackupFormat.relative(measured, now: model.now(), locale: locale),
                            text.agentTitle.lowercased()))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                Text(shared.unknown)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: Agent and cost

    private var agent: some View {
        ForkMacBackupCard(title: text.agentTitle, symbol: "gearshape.2") {
            HStack(spacing: 6) {
                Circle().fill(status.agentAlive ? ForkMacBackupWindowStyle.teal : Color.red).frame(width: 8, height: 8)
                Text(status.agentAlive ? text.agentRunning : text.agentStopped).font(.callout.weight(.semibold))
            }
            .accessibilityElement(children: .combine)
            VStack(alignment: .leading, spacing: 3) {
                if let build = status.agentBuild {
                    Text(String(format: text.agentBuild, build))
                }
                if let written = status.stateWrittenAt {
                    Text(String(format: text.stateWritten, ForkMacBackupFormat.relative(written, now: model.now(), locale: locale)))
                }
                Text(engineLine)
                Text(presentation.headline(shared, language: model.language, locale: locale, now: model.now()))
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    private var engineLine: String {
        switch engineStore.state {
        case .installed(let version): return String(format: text.engineInstalled, version)
        case .downloading: return text.engineDownloading
        case .verifying: return text.engineVerifying
        case .failed: return text.engineFailed
        case .notInstalled:
            if let version = model.ledger.engineVersion { return String(format: text.engineInstalled, version) }
            return shared.waitEngine
        }
    }

    private var cost: some View {
        ForkMacBackupCard(title: text.costTitle, symbol: "bolt") {
            Text(presentation.costLine(shared, locale: locale) ?? text.costUnknown)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(presentation.rhythmLine(shared, locale: locale))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

/// « Vérifications » (plan §7.1): every verification and restore test,
/// with its level, result and duration; « Relancer » asks the agent again.
struct ForkMacBackupVerificationsView: View {
    @ObservedObject var model: ForkMacBackupWindowModel

    private var text: ForkMacBackupWindowStrings { model.text }

    private var verifications: [ForkMacBackupRunRecord] {
        model.ledger.runs.filter { $0.kind == .verify }.sorted { $0.start > $1.start }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(text.verificationsTitle).font(.headline)
                Spacer()
                Menu {
                    ForEach(Array(Self.levels.enumerated()), id: \.offset) { _, level in
                        Button(menuTitle(level)) { model.sendVerify(level) }
                    }
                } label: {
                    Label(text.verifyNow, systemImage: "checkmark.shield")
                }
                .fixedSize()
            }
            .padding(16)
            Divider()
            if verifications.isEmpty {
                ForkMacBackupEmptyState(symbol: "checkmark.shield", title: text.verificationsEmpty)
            } else {
                Table(verifications) {
                    TableColumn(text.columnDate) { run in
                        Text(ForkMacBackupFormat.dayAndTime(run.start, locale: model.locale)).monospacedDigit()
                    }
                    .width(min: 120, ideal: 150)
                    TableColumn(text.columnLevel) { run in
                        Label(run.verifyLevel.map { text.title($0, locale: model.locale) } ?? "—",
                              systemImage: isRestoreTest(run) ? "arrow.counterclockwise.circle" : "checkmark.shield")
                    }
                    .width(min: 150, ideal: 200)
                    TableColumn(text.columnResult) { run in
                        HStack(spacing: 5) {
                            Circle().fill(color(run)).frame(width: 7, height: 7).accessibilityHidden(true)
                            Text(text.title(run.outcome)
                                 + (run.failure.map { " · " + $0.title(model.shared) } ?? ""))
                        }
                    }
                    .width(min: 110, ideal: 180)
                    TableColumn(text.duration) { run in
                        Text(run.duration.map { ForkMacBackupFormat.duration($0, locale: model.locale) } ?? "—")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 60, ideal: 80)
                    TableColumn("") { run in
                        if let level = run.verifyLevel {
                            Button(text.rerun) { model.sendVerify(level) }
                                .controlSize(.small)
                        }
                    }
                    .width(min: 80, ideal: 90)
                }
                .tableStyle(.inset(alternatesRowBackgrounds: true))
            }
            if let notice = model.notice {
                Divider()
                Label(notice.text, systemImage: notice.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(notice.isError ? Color.orange : ForkMacBackupWindowStyle.teal)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
            }
        }
    }

    static let levels: [ForkMacBackupVerifyLevel] = [.references, .contentSample(percent: 1), .restoreTest(files: 50), .full]

    private func menuTitle(_ level: ForkMacBackupVerifyLevel) -> String {
        let title = text.title(level, locale: model.locale)
        return level == .full ? title + " — " + text.longWarning : title
    }

    private func isRestoreTest(_ run: ForkMacBackupRunRecord) -> Bool {
        if case .restoreTest = run.verifyLevel { return true }
        return false
    }

    private func color(_ run: ForkMacBackupRunRecord) -> Color {
        switch run.outcome {
        case .complete, .nothingToDo: return ForkMacBackupWindowStyle.teal
        case .partial: return .orange
        case .failed: return .red
        case .canceled: return .secondary
        }
    }
}
