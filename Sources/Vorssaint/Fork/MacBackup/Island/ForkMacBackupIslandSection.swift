// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import AppKit
import SwiftUI

/// The island's Backup section (⌥⌘K, seams `notch-macbackups*`): where the
/// backup's state lives, on demand (decision 2 of 22/10). On top a card with
/// a ring, the freshness at rest or the bytes while something runs, and the
/// state in words: the last backup with its proof ladder, the next one and
/// the files waiting; or the step running, its bytes, its speed, the folder
/// being read. Under it the chain, one dot per node, and the actions:
/// Restore…, Verify, Pause ▾ (Slow Down while sending). Beside the camera:
/// Back Up Now (or Pause, Resume) and the window. Spacious, it adds the
/// sources each with its last and last complete backup, the rhythm, the
/// cost and the space.
///
/// Reads only `ForkMacBackupStatusModel.presentation`; sends the agent
/// commands. In the Settings preview nothing starts.
struct ForkMacBackupIslandSection: View {
    @ObservedObject var service: NotchService
    let size: CGSize
    @ObservedObject private var status: ForkMacBackupStatusModel
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(ForkDefaultsKey.macBackupIslandShowChain) private var showChain = true
    @AppStorage(ForkDefaultsKey.macBackupIslandShowPending) private var showPending = true
    @AppStorage(ForkDefaultsKey.macBackupIslandSize) private var sizeStored = "compact"
    @AppStorage(ForkDefaultsKey.macBackupNotifyLateHours) private var lateHours = 24
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hoveredNode: String?
    /// A fixed clock (the render harness); nil: now.
    private let fixedNow: Date?

    init(service: NotchService, size: CGSize, status: ForkMacBackupStatusModel = .shared, now: Date? = nil) {
        self.service = service
        self.size = size
        _status = ObservedObject(wrappedValue: status)
        fixedNow = now
    }

    private var text: ForkMacBackupStrings { ForkMacBackupStrings.strings(l10n.language) }
    private var island: ForkMacBackupIslandStrings { ForkMacBackupIslandStrings.strings(l10n.language) }
    private var locale: Locale { l10n.language.formattingLocale() }
    private var spacious: Bool { sizeStored == "spacious" && size.height >= 230 }

    var body: some View {
        let state = status.presentation
        let top = ForkMacBackupIslandRules.top(state.phase)
        Group {
            switch top {
            case .off, .notConfigured:
                NotchEmptyView(symbol: NotchModule.macBackup.symbol, message: island.emptyMessage) {
                    NotchPillButton(title: text.configure, prominent: true) {
                        service.perform { ForkSettingsPages.open(.macBackup) }
                    }
                }
            default:
                // The age at rest moves by the minute; a run moves by itself.
                TimelineView(.periodic(from: Date(), by: 30)) { context in
                    page(state, top: top, now: fixedNow ?? context.date)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .notchBand(trailing: { band(state, top: top) })
        .modifier(ForkMacBackupLiveLease(status: status, active: state.phase.showsInClosedIsland))
        .animation(reduceMotion ? nil : .smooth(duration: 0.26), value: top)
    }

    // MARK: - The page

    private func page(_ state: ForkMacBackupPresentation, top: ForkMacBackupIslandRules.Top, now: Date) -> some View {
        VStack(alignment: .leading, spacing: NotchLayout.rowSpacing) {
            hero(state, top: top, now: now)
            if showChain, !state.chain.isEmpty {
                chainRow(state)
            }
            actions(state, top: top)
            if spacious {
                details(state, now: now)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    // MARK: Band

    @ViewBuilder private func band(_ state: ForkMacBackupPresentation, top: ForkMacBackupIslandRules.Top) -> some View {
        // The card's own button says it when it has one: never twice.
        // The pause has its menu among the actions while a backup runs.
        switch Self.heroHasAction(top) ? ForkMacBackupIslandRules.Primary.none : ForkMacBackupIslandRules.primary(state.phase) {
        case .backUpNow, .backUpAnyway:
            NotchIconButton(symbol: "arrow.clockwise", title: text.backUpNow) { send(.backUpNow) }
        case .resume:
            NotchIconButton(symbol: "play.fill", title: text.resume) { send(.resume) }
        case .pause, .none:
            EmptyView()
        }
        // Nothing to open before a backup is set up: the page's own button leads there.
        if top != .off, top != .notConfigured {
            NotchIconButton(symbol: "arrow.up.forward.app", title: text.openBackups) {
                service.perform { ForkMacBackupWindow.open(.browse) }
            }
        }
    }

    // MARK: Hero

    private func hero(_ state: ForkMacBackupPresentation, top: ForkMacBackupIslandRules.Top, now: Date) -> some View {
        HStack(alignment: .center, spacing: 12) {
            ring(state, top: top, now: now)
            VStack(alignment: .leading, spacing: 3) {
                Text(headline(state, top: top, now: now))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(headlineColor(state, top: top))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .contentTransition(.opacity)
                    // The ring's figure is drawn, not read: the full sentence is.
                    .accessibilityLabel(spokenHeadline(state, top: top, now: now))
                    .accessibilityAddTraits(.isHeader)
                lines(state, top: top, now: now)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            heroAction(state, top: top)
        }
        .padding(12)
        .modifier(NotchControlSurface(cornerRadius: 14))
        .accessibilityElement(children: .contain)
    }

    private func headline(_ state: ForkMacBackupPresentation, top: ForkMacBackupIslandRules.Top, now: Date) -> String {
        switch top {
        case .failed(let failure): return failure.title(text)
        case .partial(let files): return text.partial(files, language: l10n.language)
        default:
            if let title = ForkMacBackupIslandRules.heroTitle(state, text: text) { return title }
            let reading = ForkMacBackupIslandModel.shared.readingSetting
            return state.headline(text, language: l10n.language, locale: locale, now: now, reading: reading)
        }
    }

    private func spokenHeadline(_ state: ForkMacBackupPresentation, top: ForkMacBackupIslandRules.Top,
                                now: Date) -> String {
        switch top {
        case .failed, .partial: return headline(state, top: top, now: now)
        default:
            return state.headline(text, language: l10n.language, locale: locale, now: now,
                                  reading: ForkMacBackupIslandModel.shared.readingSetting)
        }
    }

    private func headlineColor(_ state: ForkMacBackupPresentation, top: ForkMacBackupIslandRules.Top) -> Color {
        switch top {
        case .failed: return Color(nsColor: .systemRed)
        case .partial: return .orange
        case .waiting(let reason): return reason.needsAction ? .orange : .white
        case .running where ForkMacBackupIslandRules.readingIsSlowed(state): return .orange
        default: return .white
        }
    }

    @ViewBuilder private func ring(_ state: ForkMacBackupPresentation, top: ForkMacBackupIslandRules.Top,
                                   now: Date) -> some View {
        switch top {
        case .running, .restoring, .verifying, .maintaining:
            let fraction = state.fraction
            ForkMacBackupIslandHeroRing(
                progress: fraction, tint: ForkMacBackupIslandRules.readingIsSlowed(state) ? .orange : .teal,
                value: fraction.map { ForkMacBackupFormat.percent($0, locale: locale) },
                symbol: ForkMacBackupIslandRules.glyph(phase: state.phase, finishing: false).symbol,
                symbolTint: .white)
        case .rest:
            let interval = ForkMacBackupIslandRules.interval(of: state.rhythm)
            let tone = ForkMacBackupIslandRules.freshnessTone(protectedSince: state.protectedSince, interval: interval,
                                                              lateHours: lateHours, now: now)
            ForkMacBackupIslandHeroRing(
                progress: ForkMacBackupIslandRules.freshness(protectedSince: state.protectedSince,
                                                             nextRun: state.nextRun, interval: interval, now: now),
                tint: tone == .calm ? .teal : tone.color,
                value: state.protectedSince.map { ForkMacBackupFormat.age(now.timeIntervalSince($0), locale: locale) },
                symbol: "checkmark.shield", turnsWhenUnknown: false)
        case .paused:
            ForkMacBackupIslandHeroRing(progress: nil, tint: .white.opacity(0.55), value: nil, symbol: "pause.fill",
                                        symbolTint: .white, turnsWhenUnknown: false)
        case .waiting(let reason):
            ForkMacBackupIslandHeroRing(progress: nil, tint: reason.needsAction ? .orange : .white.opacity(0.55),
                                        value: nil, symbol: Self.symbol(for: reason),
                                        symbolTint: reason.needsAction ? .orange : .white, turnsWhenUnknown: false)
        case .partial:
            ForkMacBackupIslandHeroRing(progress: 1, tint: .orange, value: nil, symbol: "exclamationmark")
        case .failed:
            ForkMacBackupIslandHeroRing(progress: nil, tint: Color(nsColor: .systemRed), value: nil, symbol: "xmark",
                                        turnsWhenUnknown: false)
        case .off, .notConfigured:
            EmptyView()
        }
    }

    /// The step's lines under the headline.
    @ViewBuilder private func lines(_ state: ForkMacBackupPresentation, top: ForkMacBackupIslandRules.Top,
                                    now: Date) -> some View {
        switch top {
        case .running, .restoring, .verifying, .maintaining:
            if let progress = state.progress, progress.bytesDone > 0 || progress.bytesTotal != nil,
               let line = state.progressLine(text, locale: locale) {
                caption(line, digits: true)
            }
            if let path = state.progress?.currentPath, !path.isEmpty {
                caption(ForkMacBackupFormat.middleTruncated(path, limit: 46), tone: 0.45)
                    .truncationMode(.middle)
            } else if let files = state.progress?.files, files > 0 {
                caption(filesLine(state.progress), digits: true)
            }
            if spacious, state.progress?.currentPath != nil, let files = state.progress?.files, files > 0 {
                caption(filesLine(state.progress), digits: true)
            }
        case .rest, .paused:
            lastLine(state, now: now)
            if top == .rest {
                nextLine(state, now: now)
            } else if showPending, let pending = state.pendingChanges, pending > 0 {
                caption(text.pending(pending, language: l10n.language))
            }
        case .waiting(let reason):
            if case .waiting(_, let until?) = state.phase, !reason.needsAction, until > now {
                caption(String(format: text.forcedIn, ForkMacBackupFormat.duration(until.timeIntervalSince(now),
                                                                                   locale: locale)))
            }
            lastLine(state, now: now)
        case .partial:
            lastLine(state, now: now)
            if let complete = state.lastComplete {
                caption(String(format: text.lastComplete, ForkMacBackupIslandRules.when(complete.date, now: now,
                                                                                          locale: locale)))
            }
        case .failed(let failure):
            Text(failure == .chainBroken ? chainRemedy(state) : failure.remedy(text))
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.65))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        case .off, .notConfigured:
            EmptyView()
        }
    }

    /// « Dernière : aujourd’hui 10:04 ●●○○ ».
    @ViewBuilder private func lastLine(_ state: ForkMacBackupPresentation, now: Date) -> some View {
        if let last = state.lastBackup {
            HStack(spacing: 6) {
                caption(String(format: text.lastBackup, ForkMacBackupIslandRules.when(last.date, now: now, locale: locale)))
                ForkMacBackupIslandProofLadder(level: last.level)
            }
        } else {
            caption(String(format: text.lastBackup, text.never))
        }
    }

    /// « Prochaine à 13:00 · 214 fichiers en attente ».
    @ViewBuilder private func nextLine(_ state: ForkMacBackupPresentation, now: Date) -> some View {
        let parts = [state.nextRun.flatMap { $0 > now ? String(format: text.nextAt, ForkMacBackupFormat.time($0, locale: locale)) : nil },
                     showPending ? state.pendingChanges.flatMap { $0 > 0 ? text.pending($0, language: l10n.language) : nil } : nil]
            .compactMap { $0 }
        if !parts.isEmpty { caption(parts.joined(separator: " · ")) }
    }

    /// The broken node named, then what to do.
    private func chainRemedy(_ state: ForkMacBackupPresentation) -> String {
        guard let id = state.lastError?.nodeID, let node = state.chain.first(where: { $0.id == id }) else {
            return text.fixChain
        }
        return "\(node.displayTitle(text)) · \(node.state.title(text)). \(text.fixChain)"
    }

    private func filesLine(_ progress: ForkMacBackupPresentation.Progress?) -> String {
        guard let progress else { return "" }
        var files = progress.files.formatted(.number.locale(locale))
        if let total = progress.filesTotal, total >= progress.files {
            files += " / " + total.formatted(.number.locale(locale))
        }
        return String(format: island.filesRead, files) + " · " + island.errors(progress.errors, language: l10n.language)
    }

    static func heroHasAction(_ top: ForkMacBackupIslandRules.Top) -> Bool {
        switch top {
        case .waiting, .paused, .partial: return true
        case .failed(let failure): return failure != .chainBroken
        default: return false
        }
    }

    /// The card's own button, on its right: the one thing the state asks.
    @ViewBuilder private func heroAction(_ state: ForkMacBackupPresentation, top: ForkMacBackupIslandRules.Top) -> some View {
        switch top {
        case .waiting:
            ForkMacBackupIslandButton(title: text.backUpAnyway) { send(.backUpNow) }
        case .paused:
            ForkMacBackupIslandButton(symbol: "play.fill", title: text.resume, prominent: true) { send(.resume) }
        case .partial:
            ForkMacBackupIslandButton(title: island.see, label: island.seeHint) {
                service.perform { ForkMacBackupWindow.open(.history) }
            }
        case .failed(let failure) where failure != .chainBroken:
            ForkMacBackupIslandButton(symbol: "arrow.clockwise", title: text.backUpNow) { send(.backUpNow) }
        default:
            EmptyView()
        }
    }

    // MARK: Chain

    private func chainRow(_ state: ForkMacBackupPresentation) -> some View {
        HStack(spacing: 8) {
            ForkMacBackupIslandChain(chain: state.chain, hovered: $hoveredNode) {
                service.perform { ForkMacBackupWindow.open(.health) }
            }
            Spacer(minLength: 6)
            Group {
                if let id = hoveredNode, let node = state.chain.first(where: { $0.id == id }) {
                    Text(ForkMacBackupIslandChain.label(node, text: text))
                        .foregroundStyle(.white.opacity(0.85))
                } else if let free = state.capacity.nasFreeBytes {
                    Text(String(format: text.freeSpace, ForkMacBackupFormat.bytes(free, locale: locale)))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .font(.system(size: 10, weight: .medium)).monospacedDigit()
            .lineLimit(1)
            .transition(.opacity)
            .animation(reduceMotion ? nil : .smooth(duration: 0.18), value: hoveredNode)
        }
        .frame(height: 20)
    }

    // MARK: Actions

    @ViewBuilder private func actions(_ state: ForkMacBackupPresentation, top: ForkMacBackupIslandRules.Top) -> some View {
        HStack(spacing: 8) {
            switch top {
            case .running:
                ForkMacBackupIslandButton(symbol: state.slowDown ? "tortoise.fill" : "tortoise", title: text.slowDown,
                                          prominent: state.slowDown) { send(.slowDown(!state.slowDown)) }
                pauseMenu
                restoreButton
            case .restoring:
                // A restore is cancelled from the window that runs it.
                ForkMacBackupIslandButton(symbol: "arrow.up.forward.app", title: text.openBackups) {
                    service.perform { ForkMacBackupWindow.open(.browse) }
                }
            case .verifying, .maintaining:
                ForkMacBackupIslandButton(symbol: "xmark", title: FeatureStrings.clipboard(l10n.language).cancel) {
                    send(.cancel)
                }
                restoreButton
            case .paused:
                restoreButton
                verifyButton
            default:
                restoreButton
                verifyButton
                pauseMenu
            }
            Spacer(minLength: 0)
        }
    }

    private var restoreButton: some View {
        ForkMacBackupIslandButton(symbol: "arrow.counterclockwise", title: text.restore) {
            service.perform { ForkMacBackupWindow.open(.browse) }
        }
    }

    private var verifyButton: some View {
        ForkMacBackupIslandButton(symbol: "checkmark.shield", title: text.verify) {
            send(.verify(.contentSample(percent: 1)))
        }
    }

    /// « Pause ▾ »: an hour, until tomorrow, until resumed. Never `Menu`.
    private var pauseMenu: some View {
        let now = Date()
        let items = ForkMacBackupIslandRules.PauseChoice.allCases.map { choice -> NotchMenuItem in
            let title: String
            switch choice {
            case .oneHour: title = text.pauseOneHour
            case .untilTomorrow: title = text.pauseUntilTomorrow
            case .untilResumed: title = text.pauseUntilResumed
            }
            return NotchMenuItem(title: title, symbol: choice == .untilResumed ? "pause.circle" : "clock") {
                send(.pause(until: ForkMacBackupIslandRules.pauseEnd(choice, now: now)))
            }
        }
        return NotchMenuButton(title: text.pause, items: items, cornerRadius: 14) {
            ForkMacBackupIslandPill(symbol: "pause.fill", title: text.pause, chevron: true)
        }
    }

    // MARK: Spacious

    @ViewBuilder private func details(_ state: ForkMacBackupPresentation, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(state.sources) { source in
                sourceRow(source, now: now)
            }
            let facts = [state.rhythmLine(text, locale: locale),
                         state.capacity.protectedBytes.map { String(format: text.protectedSize, ForkMacBackupFormat.bytes($0, locale: locale)) },
                         state.capacity.repositoryBytes.map { String(format: text.repositorySize, ForkMacBackupFormat.bytes($0, locale: locale)) }]
                .compactMap { $0 }
            caption(facts.joined(separator: " · "))
            if let cost = state.costLine(text, locale: locale) {
                caption(cost, tone: 0.45)
            }
        }
        .padding(.horizontal, 4)
    }

    private func sourceRow(_ source: ForkMacBackupPresentation.SourceStatus, now: Date) -> some View {
        HStack(spacing: 8) {
            Image(systemName: Self.symbol(for: source.state))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Self.color(for: source.state))
                .frame(width: 14)
            Text(source.displayName(text))
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
            Text(sourceState(source, now: now))
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            if let level = source.proof { ForkMacBackupIslandProofLadder(level: level) }
        }
        .accessibilityElement(children: .combine)
    }

    private func sourceState(_ source: ForkMacBackupPresentation.SourceStatus, now: Date) -> String {
        switch source.state {
        case .running: return island.sourceRunning
        case .waiting: return island.sourceWaiting
        case .failed: return island.sourceFailed
        case .partial:
            guard let complete = source.lastComplete else { return island.sourceFailed }
            return String(format: text.lastComplete, ForkMacBackupIslandRules.when(complete.date, now: now, locale: locale))
        case .idle, .done:
            guard let last = source.last else { return island.sourceNever }
            return ForkMacBackupIslandRules.when(last.date, now: now, locale: locale)
        }
    }

    // MARK: Parts

    private func caption(_ string: String, tone: Double = 0.6, digits: Bool = false) -> some View {
        Text(string)
            .font(.system(size: 11)).monospacedDigit()
            .foregroundStyle(.white.opacity(tone))
            .lineLimit(1)
    }

    private func send(_ command: ForkMacBackupCommand) {
        status.send(command, origin: .island)
    }

    static func symbol(for reason: ForkMacBackupWaitReason) -> String {
        switch reason {
        case .power, .lowBattery, .lowPowerMode: return "powerplug"
        case .noNetwork, .limitedNetwork: return "wifi.exclamationmark"
        case .peerOffline: return "server.rack"
        case .meeting: return "person.2.wave.2"
        case .notApproved, .noDiskAccess: return "lock"
        case .engineMissing: return "shippingbox"
        case .wrongRepository: return "exclamationmark.triangle"
        case .localSpace: return "internaldrive"
        case .rulesNotApplied: return "list.bullet.rectangle"
        case .otherEngine: return "arrow.triangle.2.circlepath"
        }
    }

    static func symbol(for state: ForkMacBackupPresentation.SourceState) -> String {
        switch state {
        case .idle, .done: return "checkmark.circle.fill"
        case .waiting: return "clock"
        case .running: return "arrow.up.circle"
        case .partial: return "exclamationmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }

    static func color(for state: ForkMacBackupPresentation.SourceState) -> Color {
        switch state {
        case .idle, .done, .running: return .teal
        case .waiting: return .white.opacity(0.5)
        case .partial: return .orange
        case .failed: return Color(nsColor: .systemRed)
        }
    }
}
