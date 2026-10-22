// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import AppKit

/// Mac Backup's rows in the Command Bar (seam `command-bar-macbackup`),
/// built on every open so they follow the backup: « Back Up This Mac Now »,
/// or « Pause » while one runs and « Resume » while paused; the state as an
/// answer; restore a file, what is not backed up, verify, the window, the
/// recovery kit.
///
/// With the feature off or not set up, the rows still answer to their names
/// and say it needs doing, as an official feature's rows do: Return opens
/// the Mac Backup page. Without Full Disk Access they say so.
enum ForkMacBackupCommandBar {
    /// Under the `action.` prefix's rule, with the app's own actions.
    static let backUpID = "action.forkMacBackup.backUpNow"
    static let pauseID = "action.forkMacBackup.pause"
    static let resumeID = "action.forkMacBackup.resume"
    static let statusID = "action.forkMacBackup.status"
    static let restoreID = "action.forkMacBackup.restore"
    static let notBackedUpID = "action.forkMacBackup.notBackedUp"
    static let verifyID = "action.forkMacBackup.verify"
    static let windowID = "action.forkMacBackup.window"
    static let kitID = "action.forkMacBackup.kit"

    static func entries() -> [CommandBarEntry] {
        let language = L10n.shared.language
        let text = ForkMacBackupStrings.strings(language)
        let bar = ForkMacBackupIslandStrings.strings(language)
        let area = ForkExtrasStrings.strings(language).macBackupTitle
        let keywords = [bar.barKeywords, ForkMacBackupIslandStrings.enUS.barKeywords, area,
                        ForkExtrasStrings.strings(.enUS).macBackupTitle].joined(separator: ", ")
        let status = ForkMacBackupStatusModel.shared
        let state = status.presentation
        let rows = ForkMacBackupIslandRules.barRows(enabled: ForkMacBackupApp.isEnabled, phase: state.phase,
                                                    fullDiskAccess: Permissions.shared.fullDiskAccess)
        let setup: CommandBarEntry.Trouble?
        switch rows.trouble {
        case .featureOff?, .notConfigured?: setup = .needsSetup(featureTitle: area, page: ForkFeature.macBackup.settingsPage)
        case .diskAccess?: setup = .needsPermission
        case nil: setup = nil
        }
        // The rows that need a backup set up: a missing permission still
        // lets them run (the agent says what it can).
        let ready = rows.trouble == nil || rows.trouble == .diskAccess

        var entries: [CommandBarEntry] = []
        if rows.backUpNow {
            entries.append(CommandBarEntry(
                id: backUpID, title: bar.barBackUpNow, subtitle: area, keywords: keywords,
                icon: .symbol("clock.arrow.circlepath"), trouble: setup,
                run: { _ in send(.backUpNow) }))
        }
        if rows.pause {
            entries.append(CommandBarEntry(
                id: pauseID, title: bar.barPause, subtitle: area, keywords: keywords,
                icon: .symbol("pause.circle"), isActive: true,
                run: { _ in send(.pause(until: ForkMacBackupIslandRules.pauseEnd(.oneHour, now: Date()))) }))
        }
        if rows.resume {
            entries.append(CommandBarEntry(
                id: resumeID, title: bar.barResume, subtitle: area, keywords: keywords,
                icon: .symbol("play.circle"), isActive: true,
                run: { _ in send(.resume) }))
        }
        if ready {
            let locale = language.formattingLocale()
            entries.append(CommandBarEntry(
                id: statusID, title: bar.barStatus, subtitle: area, keywords: keywords,
                icon: .symbol("checkmark.shield"),
                answerValue: ForkMacBackupIslandRules.statusAnswer(state, text: text, language: language,
                                                                   locale: locale, now: Date()),
                run: { _ in NotchService.shared.open(.macBackup) }))
        }
        entries.append(CommandBarEntry(
            id: restoreID, title: bar.barRestore, subtitle: area, keywords: keywords,
            icon: .symbol("arrow.counterclockwise"), trouble: ready ? nil : setup,
            run: { _ in afterBeat { ForkMacBackupWindow.open(.browse) } }))
        entries.append(CommandBarEntry(
            id: notBackedUpID, title: bar.barNotBackedUp, subtitle: area, keywords: keywords,
            icon: .symbol("questionmark.folder"), trouble: ready ? nil : setup,
            run: { _ in afterBeat { ForkSettingsPages.open(.macBackup) } }))
        if rows.verify {
            entries.append(CommandBarEntry(
                id: verifyID, title: bar.barVerify, subtitle: area, keywords: keywords,
                icon: .symbol("checkmark.seal"), trouble: ready ? nil : setup,
                run: { _ in send(.verify(.contentSample(percent: 1))) }))
        }
        entries.append(CommandBarEntry(
            id: windowID, title: text.openBackups, subtitle: area, keywords: keywords,
            icon: .symbol("arrow.up.forward.app"), trouble: ready ? nil : setup,
            run: { _ in afterBeat { ForkMacBackupWindow.open(.browse) } }))
        entries.append(CommandBarEntry(
            id: kitID, title: bar.barKit, subtitle: area, keywords: keywords,
            icon: .symbol("key.horizontal"), trouble: ready ? nil : setup,
            run: { _ in afterBeat { ForkSettingsPages.open(.macBackup) } }))
        return entries
    }

    private static func send(_ command: ForkMacBackupCommand) {
        ForkMacBackupStatusModel.shared.send(command, origin: .commandBar)
    }

    /// The bar leaves first: a window opened by hand comes in front of it.
    private static func afterBeat(_ work: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }
}
