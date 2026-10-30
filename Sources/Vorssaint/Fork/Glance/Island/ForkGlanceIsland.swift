// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import AppKit
import Combine
import SwiftUI
import os

/// Glance Focus in the Dynamic Island (plan §11): the « Regard » section
/// (⌥⌘L), the closed island's activity, the tile, the notices and the
/// mascot. The only file that talks to `NotchService` for Glance's notices:
/// it is the official API that moves the most.
///
/// The service (B1) shows the notices and opens the section through
/// `show(_:)` and `openSection()`; the island reads the service's published
/// state, never the camera.
enum ForkGlanceIsland {
    /// At launch: sets the official hooks (unavailable while the feature is
    /// off). The island's own code and its tests build without the fork, so
    /// they reach Glance through these hooks, never by its name.
    static func start() {
        precondition(Thread.isMainThread)
        let enabled: (UserDefaults) -> Bool = { $0.bool(forKey: ForkDefaultsKey.glanceEnabled) }
        NotchModule.glanceHooks = (
            title: { ForkGlanceStrings.strings($0).sectionTitle },
            summary: { ForkGlanceIslandStrings.strings(L10n.shared.language).sectionSummary },
            isAvailable: enabled,
            height: { CGFloat(ForkGlanceIslandRules.sectionHeight) })
        NotchCompactActivity.glanceHooks = (
            title: { ForkGlanceStrings.strings($0).sectionTitle },
            ordered: { ForkGlanceIslandRules.ordered($0, showing: ForkGlanceIslandModel.shared.showsActivity) },
            wing: { ForkGlanceIslandStrip.wing(in: $0) })
        NotchControlItem.glanceIsAvailable = enabled
        // Its own switch is the feature's: which notices are told is chosen
        // per kind in the Activity tab's card (`fork.glance.notice.*`).
        NotchEvent.glanceHooks = (preferenceKey: ForkDefaultsKey.glanceEnabled, routes: enabled)
        // A keystroke while the island holds the keyboard is the island's,
        // never a reason to switch (guard `islandOpen`). AppKit's own record
        // counts: `resignPanelKey` can leave it on the panel (`showScratchpad`).
        ForkGlanceInputWatch.shared.islandKeyProvider = {
            let island = NotchService.shared
            guard island.expanded, let panel = island.presentationWindow else { return false }
            return island.panelIsKey || panel.isKeyWindow || NSApp.keyWindow === panel
        }
        sync()
    }

    /// The switch moved: the section, the tile and the activity follow; off,
    /// nothing stays (observers, the activity).
    static func sync() {
        precondition(Thread.isMainThread)
        ForkGlanceIslandModel.shared.sync()
    }

    // MARK: Notices

    /// The last notice the island took from Glance: a click on it opens the
    /// section (seam `notch-glance9`).
    private static var lastShown: NotchNotice?

    /// Shows `notice` if its switch (`fork.glance.notice.<kind>`) is on, with
    /// the companion's reaction (plan §11.7). Nothing at all when the switch
    /// is off: no notice, no reaction.
    static func show(_ notice: ForkGlanceNotice) {
        precondition(Thread.isMainThread)
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: ForkDefaultsKey.glanceEnabled),
              ForkGlanceIslandRules.isOn(defaults.object(forKey: ForkDefaultsKey.glanceNotice(notice.kind)),
                                         kind: notice.kind) else { return }
        let shown = notchNotice(for: notice, language: L10n.shared.language)
        guard NotchService.shared.show(shown) else { return }
        lastShown = shown
        if let mascot = shown.mascot { NotchService.shared.reactMascot(mascot) }
    }

    static func notchNotice(for notice: ForkGlanceNotice, language: AppLanguage,
                            now: Date = Date(), uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) -> NotchNotice {
        let text = ForkGlanceStrings.strings(language)
        let locale = language.formattingLocale()
        return NotchNotice(event: .glance, title: text.noticeTitle(notice, locale: locale),
                           detail: text.noticeSubtitle(notice, locale: locale, now: now, uptime: uptime) ?? "",
                           symbol: ForkGlanceIslandRules.symbol(for: notice),
                           mascot: ForkGlanceIslandRules.mascot(for: notice))
    }

    /// A click on one of our notices opens the « Regard » section; with the
    /// section hidden, the island's own choice stands.
    static func activate(_ notice: NotchNotice) -> Bool {
        let island = NotchService.shared
        guard notice.event == .glance, notice == lastShown, island.modules.contains(.glance) else { return false }
        island.open(.glance)
        return true
    }

    // MARK: Ways in and out

    /// Opens the island on the « Regard » section.
    static func openSection() {
        openSection(from: .shared)
    }

    /// From a tile, a button around the island, the activity or a notice;
    /// the feature's page when the section is hidden.
    static func openSection(from service: NotchService) {
        precondition(Thread.isMainThread)
        if service.modules.contains(.glance) {
            service.openActivity(.glance)
        } else {
            ForkSettingsPages.open(.glanceFocus)
        }
    }

    /// The island's own settings for Glance: its Content tab, on the section.
    static func openIslandSettings() {
        SettingsRouter.shared.notchModule = .glance
        SettingsRouter.shared.request(FeatureSettingsDestination(.notch))
    }

    /// The Glance Focus page, for what the island does not hold.
    static func openFeatureSettings() {
        ForkSettingsPages.open(.glanceFocus)
    }

    /// The island lays itself out again: the activity came or went, or its
    /// reading changed width.
    static func refreshIsland() {
        let island = NotchService.shared
        guard island.presentationWindow != nil else { return }
        island.objectWillChange.send()
        island.refreshPresentation()
    }

    /// A pause the person chose in the island: no notice there (plan §11.4),
    /// the companion ducks all the same (plan §11.7).
    static func pause(_ duration: ForkGlancePauseDuration) {
        ForkGlanceService.shared.pause(duration, from: .island)
        NotchService.shared.reactMascot(.hush)
    }
}

/// What the closed island follows of Glance, on the main thread: whether
/// the activity shows and what it reads. Reads only the service's published
/// state; observes it only while the feature is on.
final class ForkGlanceIslandModel: ObservableObject {
    static let shared = ForkGlanceIslandModel()

    @Published private(set) var activity: ForkGlanceIslandRules.Activity?

    private let defaults = UserDefaults.standard
    private let log = Logger(subsystem: "fork.glance", category: "island")
    private var observers: [AnyCancellable] = []
    private var defaultsObserver: NSObjectProtocol?
    private var lastShape = ""

    private init() {}

    private var service: ForkGlanceService { .shared }
    var isEnabled: Bool { defaults.bool(forKey: ForkDefaultsKey.glanceEnabled) }
    var isRunning: Bool { !observers.isEmpty }

    var closedSetting: ForkGlanceIslandClosed {
        defaults.string(forKey: ForkDefaultsKey.glanceIslandClosed).flatMap(ForkGlanceIslandClosed.init) ?? .fallback
    }

    /// Whether the closed island lists Glance now (hook `ordered`). The
    /// island asks on every layout: a switch turned on before anyone called
    /// `sync()` starts the model here.
    var showsActivity: Bool {
        if isEnabled != isRunning { DispatchQueue.main.async { [weak self] in self?.sync() } }
        return activity != nil
    }

    // MARK: Switch

    func sync() {
        precondition(Thread.isMainThread)
        if isEnabled { start() } else { stop() }
    }

    private func start() {
        guard observers.isEmpty else { return }
        log.debug("island follows Glance")
        let changes: [AnyPublisher<Void, Never>] = [
            service.$phase.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            service.$pausedUntil.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            service.$calibrationProgress.map { _ in () }.eraseToAnyPublisher(),
            service.$currentZone.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            service.$zones.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
        ]
        // `@Published` sends before it sets: read the new values on the next turn.
        observers = changes.map { $0.receive(on: DispatchQueue.main).sink { [weak self] in self?.recompute() } }
        defaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification,
                                                                  object: nil, queue: .main) { [weak self] _ in
            self?.recompute()
        }
        recompute()
    }

    private func stop() {
        guard !observers.isEmpty || defaultsObserver != nil || activity != nil else { return }
        observers = []
        if let defaultsObserver { NotificationCenter.default.removeObserver(defaultsObserver) }
        defaultsObserver = nil
        lastShape = ""
        if activity != nil {
            activity = nil
            ForkGlanceIsland.refreshIsland()
        }
    }

    // MARK: Changes

    private func recompute() {
        guard isRunning else { return }
        let next = ForkGlanceIslandRules.activity(
            enabled: isEnabled, setting: closedSetting, phase: service.phase, pausedUntil: service.pausedUntil,
            calibration: service.calibrationProgress, currentZone: service.currentZone)
        let shape = next.map(Self.shape) ?? ""
        guard next != activity else { return }
        let relayout = (next == nil) != (activity == nil) || shape != lastShape
        activity = next
        lastShape = shape
        if relayout { ForkGlanceIsland.refreshIsland() }
    }

    /// What decides the wings' width: the kind, and the reading's digits as
    /// one shape (« 14m » and « 12m » are as wide).
    private static func shape(_ activity: ForkGlanceIslandRules.Activity) -> String {
        let reading = ForkGlanceIslandRules.reading(activity, now: Date(),
                                                    locale: Locale(identifier: L10n.shared.language.rawValue))
        switch reading {
        case .text(let text): return "text " + NotchAgentSupport.readingShape(text)
        case .symbol(let name): return "symbol " + name
        case .glyph: return "glyph"
        }
    }
}
