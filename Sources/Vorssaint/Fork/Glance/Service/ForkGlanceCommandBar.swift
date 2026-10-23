// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import AppKit

/// Glance Focus's rows in the Command Bar (seam `command-bar-glance`, plan
/// §11.5), built on every open so they follow the feature: « Mettre le
/// regard en pause » (15 min, 1 h, jusqu'à reprise) or « Reprendre le
/// regard », « Recentrer », « Calibrer », the two other modes, the page.
///
/// With the feature off, the rows still answer to their names and say it
/// needs doing, as an official feature's rows do: Return opens the page.
/// The rows (`ForkGlanceServiceRules.barItems`) say which need a permission
/// or a calibration.
enum ForkGlanceCommandBar {
    /// Under the `action.` prefix's rule, with the app's own actions.
    static let idPrefix = "action.forkGlance."

    static func entries() -> [CommandBarEntry] {
        let service = ForkGlanceService.shared
        let language = L10n.shared.language
        let text = ForkGlanceStrings.strings(language)
        let area = text.featureTitle
        let keywords = text.commandBarKeywords
        let page = CommandBarEntry.Trouble.needsSetup(featureTitle: area, page: ForkFeature.glanceFocus.settingsPage)
        let keys = ForkGlanceHotKeys.shared.registered
        let items = ForkGlanceServiceRules.barItems(enabled: ForkGlance.isEnabled, phase: service.phase,
                                                    mode: service.settings.mode)
        return items.map { item in
            let trouble: CommandBarEntry.Trouble?
            switch item.trouble {
            case .needsSetup?: trouble = page
            case .needsPermission?: trouble = .needsPermission
            case nil: trouble = nil
            }
            switch item.row {
            case let .pause(duration):
                return CommandBarEntry(id: idPrefix + "pause." + duration.rawValue, title: text.barPause(duration),
                                       subtitle: area, keywords: keywords, icon: .symbol("eye.slash"),
                                       shortcut: duration == .untilResumed ? keys[.pause] : nil, trouble: trouble,
                                       run: { _ in service.pause(duration, from: .commandBar) })
            case .resume:
                return CommandBarEntry(id: idPrefix + "resume", title: text.barResume, subtitle: area,
                                       keywords: keywords, icon: .symbol("eyes"), shortcut: keys[.pause], isActive: true,
                                       trouble: trouble,
                                       run: { _ in service.resume(from: .commandBar) })
            case .recenter:
                return CommandBarEntry(id: idPrefix + "recenter", title: text.barRecenter, subtitle: area,
                                       keywords: keywords, icon: .symbol("scope"), shortcut: keys[.recenter],
                                       trouble: trouble,
                                       run: { _ in afterBeat { service.recenter(from: .commandBar) } })
            case .calibrate:
                return CommandBarEntry(id: idPrefix + "calibrate", title: text.barCalibrate, subtitle: area,
                                       keywords: keywords, icon: .symbol("viewfinder"), trouble: trouble,
                                       run: { _ in afterBeat { service.openCalibration(.full) } })
            case let .mode(mode):
                return CommandBarEntry(id: idPrefix + "mode." + mode.rawValue, title: text.barMode(mode),
                                       subtitle: area, keywords: keywords, icon: .symbol(symbol(mode)),
                                       trouble: trouble, run: { _ in service.setMode(mode) })
            case .settings:
                return CommandBarEntry(id: idPrefix + "settings", title: text.barSettings, subtitle: area,
                                       keywords: keywords, icon: .symbol("eyes"),
                                       run: { _ in afterBeat { service.openSettings() } })
            }
        }
    }

    /// The modes' symbols (plan §2).
    static func symbol(_ mode: ForkGlanceMode) -> String {
        switch mode {
        case .screens: return "display.2"
        case .zones: return "rectangle.split.2x1"
        case .windows: return "macwindow.on.rectangle"
        }
    }

    /// The bar leaves first: a window opened, or a pointer read, comes after it.
    private static func afterBeat(_ work: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }
}
