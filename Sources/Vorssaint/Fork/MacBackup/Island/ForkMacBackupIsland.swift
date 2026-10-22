// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import AppKit
import Combine
import SwiftUI

/// WP Island's entry point: the section (⌥⌘K), the closed island's activity,
/// the tile, the notices, the cards, the Command Bar and the island's
/// settings. The only file that talks to `NotchService` for Mac Backup's
/// notices and cards: it is the official API that moves the most.
///
/// Martial's decisions of 22/10: the state lives in the section, on demand;
/// the closed island shows only a backup, a restore or a verification
/// running; a notice only ends a run or a restore; no alert anywhere else.
enum ForkMacBackupIsland {
    /// At launch: sets the official hooks (unavailable while the feature is
    /// off). The island's own code and its tests build without the fork, so
    /// they reach Mac Backup through these hooks, never by its name.
    static func start() {
        let enabled: (UserDefaults) -> Bool = { $0.bool(forKey: ForkDefaultsKey.macBackupEnabled) }
        NotchModule.macBackupHooks = (
            title: { ForkMacBackupStrings.strings($0).islandTitle },
            summary: { ForkMacBackupIslandStrings.strings(L10n.shared.language).sectionSummary },
            isAvailable: enabled,
            height: { CGFloat(ForkMacBackupIslandRules.sectionHeight(
                UserDefaults.standard.string(forKey: ForkDefaultsKey.macBackupIslandSize))) })
        NotchCompactActivity.macBackupHooks = (
            title: { ForkMacBackupStrings.strings($0).islandTitle },
            ordered: { ForkMacBackupIslandRules.ordered($0, showing: ForkMacBackupIslandModel.shared.showsActivity) },
            wing: { ForkMacBackupIslandStrip.wing(in: $0) })
        NotchControlItem.macBackupIsAvailable = enabled
        // Its own switch is the feature's: which ends are told is chosen per
        // event in the Activity tab's card (`fork.macbackup.notify.*`).
        NotchEvent.backupHooks = (preferenceKey: ForkDefaultsKey.macBackupEnabled,
                                  routes: { enabled($0) && NotchSupport.modules(in: $0).contains(.macBackup) })
        sync()
    }

    /// The feature's switch moved: on, the island follows the backup; off,
    /// nothing stays (observers, timers, the activity, a card up).
    static func sync() {
        ForkMacBackupIslandModel.shared.sync()
    }

    // MARK: Notices

    /// The last notice the island took from Mac Backup: a click on it opens
    /// the section (seam `notch-macbackups9`).
    private static var lastShown: NotchNotice?

    /// Whether the closed island is free for a notice or a card now.
    static var isAvailable: Bool {
        let island = NotchService.shared
        return island.presentationWindow != nil && island.showsSystemFeedback && !island.expanded
            && !island.dragPlaceholder && island.captureControls == nil
    }

    /// False when the island refused it (busy, off, in full screen).
    @discardableResult
    static func show(_ notice: ForkMacBackupIslandRules.Notice, mascot: NotchMascotReaction?,
                     language: AppLanguage = L10n.shared.language) -> Bool {
        let shown = notchNotice(for: notice, mascot: mascot, language: language)
        guard NotchService.shared.show(shown) else { return false }
        lastShown = shown
        return true
    }

    static func notchNotice(for notice: ForkMacBackupIslandRules.Notice, mascot: NotchMascotReaction?,
                            language: AppLanguage) -> NotchNotice {
        let text = ForkMacBackupStrings.strings(language)
        let island = ForkMacBackupIslandStrings.strings(language)
        let locale = language.formattingLocale()
        let title: String
        let detail: String
        switch notice {
        case .complete(let sent):
            title = text.finished
            detail = sent.map { $0 > 0 ? String(format: text.sentSize, ForkMacBackupFormat.bytes($0, locale: locale)) : "" } ?? ""
        case .partial(let files):
            title = island.noticePartial
            // The files the section names, not « errors »: the same words there and here.
            detail = ForkMacBackupIslandRules.count(text.partial(files, language: language))
        case .failed(let failure):
            title = text.failed
            detail = failure.title(text)
        case .restored(let files):
            title = island.noticeRestore
            detail = files.map { island.restored(Int(clamping: $0), language: language) } ?? ""
        }
        return NotchNotice(event: .backup, title: title, detail: detail, symbol: notice.symbol, mascot: mascot)
    }

    /// A click on one of our notices opens the Backup section, where the
    /// run's end is told in full; with the section hidden, the island's own
    /// choice stands.
    static func activate(_ notice: NotchNotice) -> Bool {
        let island = NotchService.shared
        guard notice.event == .backup, notice == lastShown, island.modules.contains(.macBackup) else { return false }
        island.open(.macBackup)
        return true
    }

    // MARK: Cards

    /// Opens the island on a card with buttons, without taking the keyboard.
    @discardableResult
    static func present(_ card: ForkMacBackupIslandCard, id: UUID, close: @escaping () -> Void) -> Bool {
        guard isAvailable || NotchService.shared.isCaptureVisible(id: id) else { return false }
        let content = ForkMacBackupIslandCardView(card: card)
        return NotchService.shared.presentCapture(
            id: id, content: AnyView(content), actions: nil, height: height(of: content, minimum: 64),
            takeFocus: false, closeOnCollapse: true, fallback: close, close: close, hover: { _ in })
    }

    static func remove(id: UUID) {
        NotchService.shared.removeCapture(id: id)
    }

    /// A card's height measured at the island's width: a caption of three
    /// lines is never cut.
    static func height<Content: View>(of content: Content, minimum: CGFloat) -> CGFloat {
        let width = NotchService.shared.expandedGeometry.contentWidth
        guard width > 0 else { return minimum }
        let host = NSHostingView(rootView: content
            .environment(\.notchPresentation, true)
            .frame(width: width)
            .fixedSize(horizontal: false, vertical: true))
        let measured = host.fittingSize.height
        return measured.isFinite ? max(minimum, measured.rounded(.up)) : minimum
    }

    /// The island lays itself out again: the activity came or went, or its
    /// reading changed width.
    static func refreshIsland() {
        let island = NotchService.shared
        guard island.presentationWindow != nil else { return }
        island.objectWillChange.send()
        island.refreshPresentation()
    }

    /// The Backup section, from a tile, a button around the island, the
    /// activity or a card.
    static func openSection(from service: NotchService = .shared) {
        if service.modules.contains(.macBackup) {
            service.openActivity(.macBackup)
        } else {
            ForkSettingsPages.open(.macBackup)
        }
    }

    /// The island's own settings for Mac Backup: its Content tab, on the
    /// Backup section.
    static func openIslandSettings() {
        SettingsRouter.shared.notchModule = .macBackup
        SettingsRouter.shared.request(FeatureSettingsDestination(.notch))
    }

    /// The Mac Backup settings page, for what the island does not hold.
    static func openFeatureSettings() {
        ForkSettingsPages.open(.macBackup)
    }

    /// Called by the window once a restore it ran has landed: the card with
    /// « Show in Finder » and « Open », or the notice when the island cannot
    /// take a card.
    static func restoreFinished(_ report: ForkMacBackupRestoreReport) {
        ForkMacBackupIslandModel.shared.restoreFinished(report)
    }
}

/// What the island follows of the backup, on the main thread: the closed
/// island's activity (and the checkmark that ends it), the notices at the
/// end of a run, the mascot's reactions and the cards offered once. Reads
/// only `ForkMacBackupStatusModel.shared.presentation`, never the disk.
final class ForkMacBackupIslandModel: ObservableObject {
    static let shared = ForkMacBackupIslandModel()

    /// The ring has just filled: it shows a checkmark for a moment.
    @Published private(set) var finishing = false
    /// The filled ring has turned into its checkmark.
    @Published private(set) var checked = false

    private let defaults = UserDefaults.standard
    private var stateObserver: AnyCancellable?
    private var defaultsObserver: NSObjectProtocol?
    private var last: ForkMacBackupPresentation?
    private var lastShows = false
    private var lastReadingShape = ""
    private var failuresInRow = 0
    private var finishWork: DispatchWorkItem?
    private var checkWork: DispatchWorkItem?
    private var card: (id: UUID, kind: ForkMacBackupIslandCard.Kind)?
    private var cardShownAt: Date?
    private var waitsForPower = false
    private var powerObserver: AnyCancellable?

    private init() {}

    var status: ForkMacBackupStatusModel { .shared }
    var isEnabled: Bool { defaults.bool(forKey: ForkDefaultsKey.macBackupEnabled) }

    var compactSetting: ForkMacBackupCompactSetting {
        defaults.string(forKey: ForkDefaultsKey.macBackupIslandCompact).flatMap(ForkMacBackupCompactSetting.init)
            ?? .fallback
    }

    var readingSetting: ForkMacBackupReading {
        defaults.string(forKey: ForkDefaultsKey.macBackupIslandReading).flatMap(ForkMacBackupReading.init) ?? .fallback
    }

    /// Whether the closed island lists the backup now (hook `ordered`).
    var showsActivity: Bool {
        ForkMacBackupIslandRules.showsActivity(enabled: isEnabled, setting: compactSetting,
                                               phase: status.presentation.phase, finishing: finishing)
    }

    // MARK: Switch

    func sync() {
        if isEnabled { start() } else { stop() }
    }

    private func start() {
        guard stateObserver == nil else { return }
        last = status.presentation
        lastShows = showsActivity
        stateObserver = status.$presentation
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.changed(to: state) }
        defaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification,
                                                                  object: nil, queue: .main) { [weak self] _ in
            self?.relayoutIfNeeded()
        }
        ForkMacBackupIsland.refreshIsland()
    }

    private func stop() {
        stateObserver = nil
        if let defaultsObserver { NotificationCenter.default.removeObserver(defaultsObserver) }
        defaultsObserver = nil
        finishWork?.cancel()
        finishWork = nil
        powerObserver = nil
        waitsForPower = false
        if finishing { finishing = false }
        if checked { checked = false }
        checkWork?.cancel()
        checkWork = nil
        if let card { ForkMacBackupIsland.remove(id: card.id) }
        card = nil
        last = nil
        failuresInRow = 0
        lastShows = false
        ForkMacBackupIsland.refreshIsland()
    }

    // MARK: Changes

    private func changed(to state: ForkMacBackupPresentation) {
        let previous = last
        last = state
        defer { relayoutIfNeeded() }
        // A state read at launch, or the feature just turned on, tells
        // nothing new: only a change seen live ends a run.
        guard let previous, previous.updatedAt != .distantPast, previous.phase != .off else { return }
        if let result = ForkMacBackupIslandRules.endedRun(from: previous.phase, to: state.phase) {
            runEnded(result, previous: previous, state: state)
        }
        // A restore's end is told by `restoreFinished` (the window's report),
        // only when it succeeded: the phase leaving « restoring » says nothing
        // of how it ended (canceled, failed).
        offerCards(state)
    }

    private func runEnded(_ result: ForkMacBackupRunResult, previous: ForkMacBackupPresentation,
                          state: ForkMacBackupPresentation) {
        let mascot = ForkMacBackupIslandRules.mascot(for: result, hadComplete: previous.lastComplete != nil,
                                                     failuresBefore: failuresInRow)
        failuresInRow = ForkMacBackupIslandRules.failures(after: result, before: failuresInRow)
        let notice = ForkMacBackupIslandRules.notice(for: result, sent: state.capacity.lastSentBytes) { [defaults] event in
            ForkMacBackupIslandRules.channel(defaults.string(forKey: ForkDefaultsKey.macBackupNotify(event)), event: event)
        }
        // Nothing at all when the person chose « Rien » for this end: no
        // notice, and no mascot reacting to a failure in the closed island
        // (decision 3 of 22/10).
        let tell = {
            guard let notice else { return }
            ForkMacBackupIsland.show(notice, mascot: mascot)
            if let mascot { NotchService.shared.reactMascot(mascot) }
        }
        // The ring fills and turns into a checkmark before it leaves, when
        // the closed island showed it.
        if case .complete = result, lastShows {
            finish(then: tell)
        } else {
            tell()
        }
    }

    private func finish(then tell: @escaping () -> Void) {
        finishWork?.cancel()
        checkWork?.cancel()
        finishing = true
        checked = false
        ForkMacBackupIsland.refreshIsland()
        // The ring fills first, then turns into the checkmark.
        let check = DispatchWorkItem { [weak self] in
            self?.checkWork = nil
            self?.checked = true
        }
        checkWork = check
        DispatchQueue.main.asyncAfter(deadline: .now() + ForkMacBackupIslandRules.fillHold, execute: check)
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.finishWork = nil
            self.finishing = false
            self.checked = false
            tell()
            self.relayoutIfNeeded()
        }
        finishWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + ForkMacBackupIslandRules.finishHold, execute: work)
    }

    /// Lays the island out again when the activity comes or goes, or its
    /// reading changes width.
    private func relayoutIfNeeded() {
        let shows = showsActivity
        let state = status.presentation
        let shape = NotchAgentSupport.readingShape(ForkMacBackupIslandRules.reading(
            state, text: ForkMacBackupStrings.strings(L10n.shared.language), locale: L10n.shared.language.formattingLocale(),
            reading: readingSetting, finishing: finishing))
        guard shows != lastShows || (shows && shape != lastReadingShape) else { return }
        lastShows = shows
        lastReadingShape = shape
        ForkMacBackupIsland.refreshIsland()
    }

    // MARK: Cards

    private var offered: Set<String> {
        ForkMacBackupIslandRules.offered(defaults.string(forKey: ForkDefaultsKey.macBackupOffered))
    }

    private func markOffered(_ name: String) {
        defaults.set(ForkMacBackupIslandRules.adding(name, to: defaults.string(forKey: ForkDefaultsKey.macBackupOffered)),
                     forKey: ForkDefaultsKey.macBackupOffered)
    }

    private func offerCards(_ state: ForkMacBackupPresentation) {
        guard card == nil, ForkMacBackupIsland.isAvailable else { return }
        if ForkMacBackupIslandRules.offersBranStop(state, branImported: defaults.object(forKey: ForkDefaultsKey.macBackupBranImportedAt) != nil,
                                                   offered: offered) {
            markOffered(ForkMacBackupIslandRules.offeredBran)
            show(.bran)
        } else if ForkMacBackupIslandRules.offersFirstBackup(state, offered: offered) {
            markOffered(ForkMacBackupIslandRules.offeredFirstBackup)
            show(.firstBackup(bytes: state.capacity.protectedBytes))
        }
    }

    private func show(_ kind: ForkMacBackupIslandCard.Kind) {
        let id = UUID()
        let card = ForkMacBackupIslandCard(kind: kind) { [weak self] action in self?.cardAction(action, id: id) }
        guard ForkMacBackupIsland.present(card, id: id, close: { [weak self] in
            guard self?.card?.id == id else { return }
            self?.card = nil
        }) else { return }
        self.card = (id, kind)
        cardShownAt = Date()
    }

    private func cardAction(_ action: ForkMacBackupIslandCard.Action, id: UUID) {
        ForkMacBackupIsland.remove(id: id)
        if card?.id == id { card = nil }
        switch action {
        case .chooseContent:
            NotchService.shared.perform { ForkMacBackupIsland.openFeatureSettings() }
        case .startOnPower:
            startWhenPlugged()
        case .showInFinder(let path):
            NotchService.shared.perform {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            }
        case .open(let path):
            NotchService.shared.perform { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
        case .stopBran:
            // Bran's own agent is stopped here; ours then plans again at once
            // instead of waiting for the other engine to show up as gone.
            ForkMacBackupLiveServices.stopBran { _ in self.status.send(.stopOtherEngine, origin: .island) }
        case .later:
            break
        }
    }

    /// « Commencer sur secteur »: now when plugged in, else at the plug.
    private func startWhenPlugged() {
        let island = NotchService.shared
        if island.power.externalConnected || !island.power.hasBattery {
            status.send(.backUpNow, origin: .island)
            return
        }
        waitsForPower = true
        powerObserver = island.$power
            .map(\.externalConnected)
            .removeDuplicates()
            .filter { $0 }
            .first()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.waitsForPower, self.isEnabled else { return }
                self.waitsForPower = false
                self.powerObserver = nil
                self.status.send(.backUpNow, origin: .island)
            }
    }

    fileprivate func restoreFinished(_ report: ForkMacBackupRestoreReport) {
        let channel = ForkMacBackupIslandRules.channel(defaults.string(forKey: ForkDefaultsKey.macBackupNotify(.restoreDone)),
                                                      event: .restoreDone)
        guard isEnabled, ForkMacBackupIslandRules.showsInIsland(channel) else { return }
        if card == nil, ForkMacBackupIsland.isAvailable {
            show(.restored(files: report.files, path: report.destinationPath))
            if card != nil { return }
        }
        ForkMacBackupIsland.show(.restored(files: report.files), mascot: nil)
    }
}
