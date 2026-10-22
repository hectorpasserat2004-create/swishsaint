// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// The words of the « Sauvegardes » window. The shared ones (states, proof
/// levels, causes, remedies, nodes) stay in `ForkMacBackupStrings`.
///
/// Same contract as the other feature strings: memberwise init in
/// declaration order, one static per language. French: `\u{00A0}` before
/// « : ; ! ? » and inside « », typographic apostrophes. The `…One`,
/// `…Few`, `…Many` triplets go through `ForkMacBackupStrings.counted`.
struct ForkMacBackupWindowStrings {
    // MARK: Window and sidebar
    let windowTitle: String
    let sidebarOtherMacs: String
    let sidebarActivity: String
    let tabBrowse: String
    let tabHistory: String
    let tabHealth: String
    let tabVerifications: String
    let searchPlaceholder: String
    let toggleInspector: String
    let now: String
    let zoomDay: String
    let zoomWeek: String
    let zoomMonth: String
    let previousSnapshot: String
    let nextSnapshot: String
    let earlier: String
    let later: String
    let noSnapshotInSpan: String
    let parentFolder: String

    // MARK: Browser
    let columnName: String
    let columnStatus: String
    let columnSize: String
    let columnModified: String
    let statusIdentical: String
    let statusModified: String
    let statusDeleted: String
    let statusPresent: String
    let folderEmpty: String
    /// `%@`: the folder's name.
    let folderMissingAtDate: String
    let loading: String
    let itemsOne: String
    let itemsFew: String
    let itemsMany: String
    let unreadOne: String
    let unreadFew: String
    let unreadMany: String
    let noSnapshotTitle: String
    let noSnapshotDetail: String
    let unavailableTitle: String
    let unavailableDetail: String
    let notConfiguredDetail: String
    let retry: String
    /// `%@`: what went wrong.
    let readFailed: String
    let open: String
    let quickLook: String
    let restoreHere: String
    /// `%d`: how many versions.
    let versionsCount: String
    let versions: String
    let copyPath: String
    let showOnMac: String

    // MARK: Search
    /// `%@`: the query.
    let searching: String
    let searchResultsOne: String
    let searchResultsFew: String
    let searchResultsMany: String
    let searchNoResult: String
    let searchStop: String
    let searchTruncated: String

    // MARK: Inspector
    /// `%@`: a day and a time.
    let snapshotOf: String
    let source: String
    let proof: String
    /// `%@`: a proof level; `%d`: its rank of 4.
    let proofVoice: String
    let partial: String
    let files: String
    let realSize: String
    let sent: String
    let duration: String
    /// `%@`: a date; second `%@`: a percentage of files.
    let verifiedOn: String
    /// `%@`: a date.
    let restoreTestedOn: String
    /// `%@`: Kopia's reason.
    let interrupted: String
    let failuresTitle: String
    /// `%d`: failures Kopia counted but did not name.
    let failuresUnnamed: String
    let cloudOne: String
    let cloudFew: String
    let cloudMany: String
    let selectedOne: String
    let selectedFew: String
    let selectedMany: String
    let noVersionHint: String
    let copied: String
    let downloadStarted: String
    let backupRequested: String

    // MARK: Versions
    /// `%@`: the file's name.
    let versionsOf: String
    let savesOne: String
    let savesFew: String
    let savesMany: String
    let distinctOne: String
    let distinctFew: String
    let distinctMany: String
    /// `%@`: first date; second `%@`: last date.
    let seenFromTo: String
    /// `%@`: a date.
    let seenOnce: String
    let versionsEmpty: String
    let close: String

    // MARK: Quick Look and dragging
    let preparingPreview: String
    /// `%@`: what went wrong.
    let previewFailed: String
    /// `%@`: the file's name.
    let restoringItem: String

    // MARK: « Is this file backed up? »
    let dropHint: String
    let verdictTitle: String
    let checking: String
    /// `%@`: a day and a time.
    let verdictBackedUp: String
    /// `%@`: a day and a time.
    let verdictModified: String
    /// `%@`: a day and a time.
    let verdictNotYet: String
    let verdictNotYetSoon: String
    /// `%@`: the rule.
    let verdictExcluded: String
    let verdictCloudOnly: String
    let verdictOutside: String
    let verdictUnknown: String
    let showInBackup: String

    // MARK: Restore
    let restoreTitle: String
    let stepWhat: String
    let stepWhere: String
    let stepChecks: String
    let stepProgress: String
    let stepDone: String
    /// `%@`: a day and a time.
    let fromSnapshot: String
    let whereSeparate: String
    let chooseFolder: String
    let whereOriginal: String
    let policyKeepBoth: String
    let policyReplaceOlder: String
    let policyReplaceAll: String
    /// The word in « rapport (restauré).pdf ».
    let restoredWord: String
    /// The start of « Restauré — 22 oct. 2026 à 10.04 ».
    let restoredFolderPrefix: String
    /// `%@`: free space; second `%@`: what is needed.
    let checkSpaceOK: String
    /// `%@`: what is missing.
    let checkSpaceShort: String
    let checkSpaceUnknown: String
    let checkWriteOK: String
    let checkWriteDenied: String
    let checkActiveSource: String
    let checkReplaceAll: String
    let checkOtherMac: String
    let continueAction: String
    let back: String
    let cancel: String
    let startRestore: String
    let resultComplete: String
    let resultPartial: String
    let resultFailed: String
    let resultCanceled: String
    let restoredOne: String
    let restoredFew: String
    let restoredMany: String
    let errorsOne: String
    let errorsFew: String
    let errorsMany: String
    let showInFinder: String
    let done: String

    // MARK: History
    let runsTitle: String
    let kindBackup: String
    let kindVerify: String
    let kindRestore: String
    let kindMaintenance: String
    let triggerScheduled: String
    let triggerCatchUp: String
    let triggerEarly: String
    let triggerIsland: String
    let triggerSettings: String
    let triggerCommandBar: String
    let triggerWindow: String
    let triggerAgent: String
    let outcomeComplete: String
    let outcomePartial: String
    let outcomeFailed: String
    let outcomeCanceled: String
    let outcomeNothing: String
    let stopUser: String
    let stopPaused: String
    let stopMeeting: String
    let stopSleep: String
    let stopAppUpdate: String
    let stopWatchdog: String
    let stopFeatureOff: String
    let stopAgentQuit: String
    let onBattery: String
    let onPower: String
    /// `%@`: battery points.
    let batteryUsed: String
    let columnDate: String
    let columnOperation: String
    let columnTrigger: String
    let columnResult: String
    let columnConditions: String
    let runsEmpty: String
    let slotsTitle: String
    let slotsEmpty: String
    let markDone: String
    let markPartial: String
    let markFailed: String
    let markNothing: String
    let markAsleep: String
    let markBattery: String
    let markNetwork: String
    let markPaused: String
    let markMissed: String
    let markUpcoming: String
    let reasonAsleep: String
    let reasonOff: String
    /// `%@`: a time of day.
    let slotDue: String
    /// `%@`: a time of day.
    let slotStarted: String
    /// `%@`: a day and a time.
    let slotCaughtUp: String
    let slotNotCaughtUp: String

    // MARK: Health
    let chainTitle: String
    /// `%@`: a number of milliseconds.
    let latency: String
    /// `%@`: a relative date.
    let checkedAgo: String
    /// `%@`: what happened and when.
    let lastIncident: String
    let noIncident: String
    let capacityTitle: String
    let capProtected: String
    let capSent: String
    let capRepository: String
    let capNASFree: String
    /// `%@`: a relative date; second `%@`: the source.
    let measured: String
    let sourceSnapshot: String
    let sourceRun: String
    let sourceBlobStats: String
    let chartTitle: String
    let chartEmpty: String
    let fullOne: String
    let fullFew: String
    let fullMany: String
    let agentTitle: String
    let agentRunning: String
    let agentStopped: String
    /// `%@`: a build.
    let agentBuild: String
    /// `%@`: a relative date.
    let stateWritten: String
    /// `%@`: the version.
    let engineInstalled: String
    let engineDownloading: String
    let engineVerifying: String
    let engineFailed: String
    let costTitle: String
    let costUnknown: String
    let lastProblem: String

    // MARK: Verifications
    let verificationsTitle: String
    let levelManifest: String
    let levelReferences: String
    /// `%@`: a percentage.
    let levelSample: String
    let levelRestoreTest: String
    let levelFull: String
    let rerun: String
    let verifyNow: String
    let requestSent: String
    let requestFailed: String
    let verificationsEmpty: String
    let columnLevel: String
    let longWarning: String

    static func strings(_ language: AppLanguage) -> ForkMacBackupWindowStrings {
        switch language {
        case .enUS: return .enUS
        case .ptBR: return .ptBR
        case .tr: return .tr
        case .ru: return .ru
        case .es: return .es
        case .sk: return .sk
        case .de: return .de
        case .fr: return .fr
        case .it: return .it
        case .ja: return .ja
        case .ko: return .ko
        case .uk: return .uk
        case .zhHans: return .zhHans
        case .zhTW: return .zhTW
        case .zhHK: return .zhHK
        }
    }

    // MARK: Counted

    func items(_ count: Int, _ language: AppLanguage) -> String {
        ForkMacBackupStrings.counted(count, language: language, one: itemsOne, few: itemsFew, many: itemsMany)
    }

    func unread(_ count: Int, _ language: AppLanguage) -> String {
        ForkMacBackupStrings.counted(count, language: language, one: unreadOne, few: unreadFew, many: unreadMany)
    }

    func searchResults(_ count: Int, _ language: AppLanguage) -> String {
        ForkMacBackupStrings.counted(count, language: language, one: searchResultsOne, few: searchResultsFew,
                                     many: searchResultsMany)
    }

    func cloud(_ count: Int, _ language: AppLanguage) -> String {
        ForkMacBackupStrings.counted(count, language: language, one: cloudOne, few: cloudFew, many: cloudMany)
    }

    func selected(_ count: Int, _ language: AppLanguage) -> String {
        ForkMacBackupStrings.counted(count, language: language, one: selectedOne, few: selectedFew, many: selectedMany)
    }

    func saves(_ count: Int, _ language: AppLanguage) -> String {
        ForkMacBackupStrings.counted(count, language: language, one: savesOne, few: savesFew, many: savesMany)
    }

    func distinct(_ count: Int, _ language: AppLanguage) -> String {
        ForkMacBackupStrings.counted(count, language: language, one: distinctOne, few: distinctFew, many: distinctMany)
    }

    func restored(_ count: Int, _ language: AppLanguage) -> String {
        ForkMacBackupStrings.counted(count, language: language, one: restoredOne, few: restoredFew, many: restoredMany)
    }

    func errors(_ count: Int, _ language: AppLanguage) -> String {
        ForkMacBackupStrings.counted(count, language: language, one: errorsOne, few: errorsFew, many: errorsMany)
    }

    func fullIn(months: Int, _ language: AppLanguage) -> String {
        ForkMacBackupStrings.counted(months, language: language, one: fullOne, few: fullFew, many: fullMany)
    }

    // MARK: Enumerations

    func title(_ tab: ForkMacBackupWindowTab) -> String {
        switch tab {
        case .browse: return tabBrowse
        case .history: return tabHistory
        case .health: return tabHealth
        case .verifications: return tabVerifications
        }
    }

    func title(_ status: ForkMacBackupLocalStatus) -> String {
        switch status {
        case .identical: return statusIdentical
        case .modifiedSince: return statusModified
        case .deletedSince: return statusDeleted
        case .present: return statusPresent
        case .unknown: return "—"
        }
    }

    func title(_ zoom: ForkMacBackupTimelineZoom) -> String {
        switch zoom {
        case .day: return zoomDay
        case .week: return zoomWeek
        case .month: return zoomMonth
        }
    }

    func title(_ policy: ForkMacBackupRestoreRequest.Overwrite) -> String {
        switch policy {
        case .keepBoth: return policyKeepBoth
        case .replaceIfOlder: return policyReplaceOlder
        case .replaceAll: return policyReplaceAll
        }
    }

    func title(_ kind: ForkMacBackupRunRecord.Kind) -> String {
        switch kind {
        case .backup: return kindBackup
        case .verify: return kindVerify
        case .restore: return kindRestore
        case .maintenance: return kindMaintenance
        }
    }

    func title(_ trigger: ForkMacBackupTrigger) -> String {
        switch trigger {
        case .scheduled: return triggerScheduled
        case .catchUp: return triggerCatchUp
        case .early: return triggerEarly
        case .island: return triggerIsland
        case .settings: return triggerSettings
        case .commandBar: return triggerCommandBar
        case .window: return triggerWindow
        case .agent: return triggerAgent
        }
    }

    func title(_ outcome: ForkMacBackupRunRecord.Outcome) -> String {
        switch outcome {
        case .complete: return outcomeComplete
        case .partial: return outcomePartial
        case .failed: return outcomeFailed
        case .canceled: return outcomeCanceled
        case .nothingToDo: return outcomeNothing
        }
    }

    func title(_ reason: ForkMacBackupStopReason) -> String {
        switch reason {
        case .user: return stopUser
        case .paused: return stopPaused
        case .meeting: return stopMeeting
        case .sleep: return stopSleep
        case .appUpdate: return stopAppUpdate
        case .watchdog: return stopWatchdog
        case .featureOff: return stopFeatureOff
        case .agentQuit: return stopAgentQuit
        }
    }

    func title(_ mark: ForkMacBackupSlotsGrid.Mark) -> String {
        switch mark {
        case .done: return markDone
        case .partial: return markPartial
        case .failed: return markFailed
        case .nothingToDo: return markNothing
        case .asleep: return markAsleep
        case .battery: return markBattery
        case .network: return markNetwork
        case .paused: return markPaused
        case .missed: return markMissed
        case .upcoming: return markUpcoming
        case .empty: return ""
        }
    }

    /// Why a slot was missed, in the shared words where they exist.
    func title(_ reason: ForkMacBackupMissedReason, shared: ForkMacBackupStrings) -> String {
        switch reason {
        case .asleep: return reasonAsleep
        case .off: return reasonOff
        case .battery: return shared.waitBattery
        case .lowPower: return shared.waitLowPower
        case .network: return shared.waitNetwork
        case .limitedNetwork: return shared.waitLimitedNetwork
        case .peerOffline: return shared.waitPeer
        case .paused: return shared.paused
        case .meeting: return shared.waitMeeting
        case .notApproved: return shared.waitApproval
        case .noDiskAccess: return shared.waitDiskAccess
        case .engineMissing: return shared.waitEngine
        case .notConfigured: return shared.notConfigured
        case .wrongRepository: return shared.wrongRepository
        }
    }

    func title(_ level: ForkMacBackupVerifyLevel, locale: Locale) -> String {
        switch level {
        case .manifest: return levelManifest
        case .references: return levelReferences
        case .contentSample(let percent):
            return String(format: levelSample, ForkMacBackupFormat.percent(percent / 100, locale: locale))
        case .restoreTest: return levelRestoreTest
        case .full: return levelFull
        }
    }

    /// The source of a capacity measure, in words when it is a known one.
    func capacitySource(_ source: String) -> String {
        switch source.lowercased() {
        case "snapshot": return sourceSnapshot
        case "run": return sourceRun
        case "blobstats": return sourceBlobStats
        default: return source
        }
    }
}

extension ForkMacBackupWindowStrings {
    static let enUS = ForkMacBackupWindowStrings(
        windowTitle: "Backups",
        sidebarOtherMacs: "Other Macs",
        sidebarActivity: "Activity",
        tabBrowse: "Browse",
        tabHistory: "History",
        tabHealth: "Health",
        tabVerifications: "Verifications",
        searchPlaceholder: "Search this backup",
        toggleInspector: "Show or hide the inspector",
        now: "Now",
        zoomDay: "Day",
        zoomWeek: "Week",
        zoomMonth: "Month",
        previousSnapshot: "Previous backup",
        nextSnapshot: "Next backup",
        earlier: "Earlier",
        later: "Later",
        noSnapshotInSpan: "No backup in this period",
        parentFolder: "Enclosing folder",
        columnName: "Name",
        columnStatus: "On This Mac",
        columnSize: "Size",
        columnModified: "Date Modified",
        statusIdentical: "Same",
        statusModified: "Changed since",
        statusDeleted: "Deleted since",
        statusPresent: "Still here",
        folderEmpty: "This folder is empty in this backup.",
        folderMissingAtDate: "“%@” did not exist at that date: here is the closest folder.",
        loading: "Loading…",
        itemsOne: "1 item",
        itemsFew: "%d items",
        itemsMany: "%d items",
        unreadOne: "1 file not read",
        unreadFew: "%d files not read",
        unreadMany: "%d files not read",
        noSnapshotTitle: "No backup yet",
        noSnapshotDetail: "Once this source is backed up, its folders appear here, date by date.",
        unavailableTitle: "Backups unavailable",
        unavailableDetail: "The backup engine is not answering. It runs with the backup agent: check the Mac Backup page in Settings.",
        notConfiguredDetail: "Set up Mac Backup in Settings to browse your backups here.",
        retry: "Try Again",
        readFailed: "Could not read the backup: %@",
        open: "Open",
        quickLook: "Quick Look",
        restoreHere: "Restore Here…",
        versionsCount: "Versions (%d)",
        versions: "Versions",
        copyPath: "Copy Path",
        showOnMac: "Show on This Mac",
        searching: "Searching for “%@”…",
        searchResultsOne: "1 result",
        searchResultsFew: "%d results",
        searchResultsMany: "%d results",
        searchNoResult: "No file of this backup has this name.",
        searchStop: "Stop",
        searchTruncated: "Only the first results are shown: refine the search.",
        snapshotOf: "Backup of %@",
        source: "Source",
        proof: "Proof",
        proofVoice: "Proof: %@, level %d of 4",
        partial: "Partial",
        files: "Files",
        realSize: "Real size",
        sent: "Sent",
        duration: "Duration",
        verifiedOn: "Content verified on %@ (%@ of files)",
        restoreTestedOn: "Restore tested on %@",
        interrupted: "Interrupted: %@",
        failuresTitle: "Files not backed up",
        failuresUnnamed: "+ %d more not named by Kopia",
        cloudOne: "1 file in iCloud only, listed apart",
        cloudFew: "%d files in iCloud only, listed apart",
        cloudMany: "%d files in iCloud only, listed apart",
        selectedOne: "1 item selected",
        selectedFew: "%d items selected",
        selectedMany: "%d items selected",
        noVersionHint: "Select a file to see its versions.",
        copied: "Copied",
        downloadStarted: "Download started: the next backup will include them.",
        backupRequested: "A backup was requested.",
        versionsOf: "Versions of “%@”",
        savesOne: "1 backup",
        savesFew: "%d backups",
        savesMany: "%d backups",
        distinctOne: "1 distinct version",
        distinctFew: "%d distinct versions",
        distinctMany: "%d distinct versions",
        seenFromTo: "Saved from %@ to %@",
        seenOnce: "Saved on %@",
        versionsEmpty: "No other version of this file.",
        close: "Close",
        preparingPreview: "Preparing the preview…",
        previewFailed: "No preview: %@",
        restoringItem: "Restoring “%@”…",
        dropHint: "Drop a file here to know whether it is backed up",
        verdictTitle: "Is this file backed up?",
        checking: "Checking…",
        verdictBackedUp: "Backed up · latest version of %@",
        verdictModified: "Changed since the backup of %@",
        verdictNotYet: "Not backed up yet · next backup %@",
        verdictNotYetSoon: "Not backed up yet · the next backup will include it",
        verdictExcluded: "Never backed up · left out by the rule “%@”",
        verdictCloudOnly: "Never backed up · in iCloud only",
        verdictOutside: "Never backed up · outside the backed-up folders",
        verdictUnknown: "Cannot check right now",
        showInBackup: "Show in Backup",
        restoreTitle: "Restore",
        stepWhat: "What",
        stepWhere: "Where",
        stepChecks: "Checks",
        stepProgress: "Restoring",
        stepDone: "Done",
        fromSnapshot: "From the backup of %@",
        whereSeparate: "In a separate folder",
        chooseFolder: "Choose…",
        whereOriginal: "Where they came from",
        policyKeepBoth: "Keep both (“restored” suffix)",
        policyReplaceOlder: "Replace if older",
        policyReplaceAll: "Replace all",
        restoredWord: "restored",
        restoredFolderPrefix: "Restored",
        checkSpaceOK: "%@ free, %@ needed",
        checkSpaceShort: "Not enough space: %@ missing",
        checkSpaceUnknown: "Free space unknown",
        checkWriteOK: "Write access granted",
        checkWriteDenied: "Cannot write in this folder",
        checkActiveSource: "This folder is backed up: the restored files will be in the next backup.",
        checkReplaceAll: "Files on this Mac with the same name will be replaced.",
        checkOtherMac: "Backup of another Mac: file owners are not kept.",
        continueAction: "Continue",
        back: "Back",
        cancel: "Cancel",
        startRestore: "Restore",
        resultComplete: "Restore complete",
        resultPartial: "Restore complete with errors",
        resultFailed: "The restore failed",
        resultCanceled: "Restore canceled",
        restoredOne: "1 file restored",
        restoredFew: "%d files restored",
        restoredMany: "%d files restored",
        errorsOne: "1 file failed",
        errorsFew: "%d files failed",
        errorsMany: "%d files failed",
        showInFinder: "Show in Finder",
        done: "Done",
        runsTitle: "Operations",
        kindBackup: "Backup",
        kindVerify: "Verification",
        kindRestore: "Restore",
        kindMaintenance: "Maintenance",
        triggerScheduled: "Scheduled",
        triggerCatchUp: "Catch-up",
        triggerEarly: "Early",
        triggerIsland: "Island",
        triggerSettings: "Settings",
        triggerCommandBar: "Command Bar",
        triggerWindow: "Backups window",
        triggerAgent: "Agent",
        outcomeComplete: "Complete",
        outcomePartial: "Partial",
        outcomeFailed: "Failed",
        outcomeCanceled: "Canceled",
        outcomeNothing: "Nothing new",
        stopUser: "stopped by you",
        stopPaused: "paused",
        stopMeeting: "meeting",
        stopSleep: "Mac asleep",
        stopAppUpdate: "app update",
        stopWatchdog: "stuck, stopped",
        stopFeatureOff: "feature turned off",
        stopAgentQuit: "agent quit",
        onBattery: "On battery",
        onPower: "On power",
        batteryUsed: "%@ of battery",
        columnDate: "Date",
        columnOperation: "Operation",
        columnTrigger: "Started by",
        columnResult: "Result",
        columnConditions: "Conditions",
        runsEmpty: "No operation recorded yet.",
        slotsTitle: "Slots of the last 30 days",
        slotsEmpty: "No slot expected yet.",
        markDone: "Done",
        markPartial: "Partial",
        markFailed: "Failed",
        markNothing: "Nothing new",
        markAsleep: "Asleep",
        markBattery: "Battery",
        markNetwork: "Network",
        markPaused: "Paused",
        markMissed: "Missed",
        markUpcoming: "Upcoming",
        reasonAsleep: "Mac asleep",
        reasonOff: "Mac off",
        slotDue: "Due at %@",
        slotStarted: "Started at %@",
        slotCaughtUp: "Caught up at %@",
        slotNotCaughtUp: "Not caught up yet",
        chainTitle: "The chain",
        latency: "%@ ms",
        checkedAgo: "checked %@",
        lastIncident: "Last incident: %@",
        noIncident: "No incident known",
        capacityTitle: "Space",
        capProtected: "Protected (real size)",
        capSent: "Last sent",
        capRepository: "Repository on the storage",
        capNASFree: "Free on the NAS",
        measured: "measured %@ · %@",
        sourceSnapshot: "last backup",
        sourceRun: "last operation",
        sourceBlobStats: "repository count",
        chartTitle: "Last 90 days",
        chartEmpty: "Not enough measures for a chart yet.",
        fullOne: "Full in about 1 month at this pace",
        fullFew: "Full in about %d months at this pace",
        fullMany: "Full in about %d months at this pace",
        agentTitle: "Agent and engine",
        agentRunning: "Agent running",
        agentStopped: "Agent not running",
        agentBuild: "Build %@",
        stateWritten: "state written %@",
        engineInstalled: "Kopia %@ installed",
        engineDownloading: "Downloading the engine…",
        engineVerifying: "Checking the engine…",
        engineFailed: "Engine installation failed",
        costTitle: "Cost",
        costUnknown: "Not measured yet",
        lastProblem: "Last problem",
        verificationsTitle: "Verifications and restore tests",
        levelManifest: "Manifest",
        levelReferences: "References",
        levelSample: "Content sample (%@)",
        levelRestoreTest: "Restore test",
        levelFull: "Full content",
        rerun: "Run Again",
        verifyNow: "Verify Now",
        requestSent: "Request sent to the agent",
        requestFailed: "The agent did not get the request",
        verificationsEmpty: "No verification recorded yet.",
        columnLevel: "Level",
        longWarning: "Long: may take hours"
    )

    static let fr = ForkMacBackupWindowStrings(
        windowTitle: "Sauvegardes",
        sidebarOtherMacs: "Autres Mac",
        sidebarActivity: "Suivi",
        tabBrowse: "Parcourir",
        tabHistory: "Historique",
        tabHealth: "Santé",
        tabVerifications: "Vérifications",
        searchPlaceholder: "Rechercher dans cette sauvegarde",
        toggleInspector: "Afficher ou masquer l’inspecteur",
        now: "Maintenant",
        zoomDay: "Jour",
        zoomWeek: "Semaine",
        zoomMonth: "Mois",
        previousSnapshot: "Sauvegarde précédente",
        nextSnapshot: "Sauvegarde suivante",
        earlier: "Plus tôt",
        later: "Plus tard",
        noSnapshotInSpan: "Aucune sauvegarde sur cette période",
        parentFolder: "Dossier parent",
        columnName: "Nom",
        columnStatus: "Sur ce Mac",
        columnSize: "Taille",
        columnModified: "Date de modification",
        statusIdentical: "Identique",
        statusModified: "Modifié depuis",
        statusDeleted: "Supprimé depuis",
        statusPresent: "Toujours là",
        folderEmpty: "Ce dossier est vide dans cette sauvegarde.",
        folderMissingAtDate: "«\u{00A0}%@\u{00A0}» n’existait pas à cette date\u{00A0}: voici le dossier le plus proche.",
        loading: "Chargement…",
        itemsOne: "1 élément",
        itemsFew: "%d éléments",
        itemsMany: "%d éléments",
        unreadOne: "1 fichier non lu",
        unreadFew: "%d fichiers non lus",
        unreadMany: "%d fichiers non lus",
        noSnapshotTitle: "Pas encore de sauvegarde",
        noSnapshotDetail: "Une fois cette source sauvegardée, ses dossiers apparaissent ici, date par date.",
        unavailableTitle: "Sauvegardes indisponibles",
        unavailableDetail: "Le moteur de sauvegarde ne répond pas. Il tourne avec l’agent de sauvegarde\u{00A0}: vérifie la page Sauvegarde du Mac des réglages.",
        notConfiguredDetail: "Configure la Sauvegarde du Mac dans les réglages pour parcourir tes sauvegardes ici.",
        retry: "Réessayer",
        readFailed: "Lecture de la sauvegarde impossible\u{00A0}: %@",
        open: "Ouvrir",
        quickLook: "Coup d’œil",
        restoreHere: "Restaurer ici…",
        versionsCount: "Versions (%d)",
        versions: "Versions",
        copyPath: "Copier le chemin",
        showOnMac: "Afficher sur ce Mac",
        searching: "Recherche de «\u{00A0}%@\u{00A0}»…",
        searchResultsOne: "1 résultat",
        searchResultsFew: "%d résultats",
        searchResultsMany: "%d résultats",
        searchNoResult: "Aucun fichier de cette sauvegarde ne porte ce nom.",
        searchStop: "Arrêter",
        searchTruncated: "Seuls les premiers résultats sont affichés\u{00A0}: précise la recherche.",
        snapshotOf: "Sauvegarde du %@",
        source: "Source",
        proof: "Preuve",
        proofVoice: "Preuve\u{00A0}: %@, niveau %d sur 4",
        partial: "Partielle",
        files: "Fichiers",
        realSize: "Taille réelle",
        sent: "Envoyé",
        duration: "Durée",
        verifiedOn: "Contenu vérifié le %@ (%@ des fichiers)",
        restoreTestedOn: "Restauration testée le %@",
        interrupted: "Interrompue\u{00A0}: %@",
        failuresTitle: "Fichiers non sauvegardés",
        failuresUnnamed: "+ %d autres non nommés par Kopia",
        cloudOne: "1 fichier dans iCloud seulement, listé à part",
        cloudFew: "%d fichiers dans iCloud seulement, listés à part",
        cloudMany: "%d fichiers dans iCloud seulement, listés à part",
        selectedOne: "1 élément sélectionné",
        selectedFew: "%d éléments sélectionnés",
        selectedMany: "%d éléments sélectionnés",
        noVersionHint: "Sélectionne un fichier pour voir ses versions.",
        copied: "Copié",
        downloadStarted: "Téléchargement lancé\u{00A0}: la prochaine sauvegarde les inclura.",
        backupRequested: "Une sauvegarde a été demandée.",
        versionsOf: "Versions de «\u{00A0}%@\u{00A0}»",
        savesOne: "1 sauvegarde",
        savesFew: "%d sauvegardes",
        savesMany: "%d sauvegardes",
        distinctOne: "1 version différente",
        distinctFew: "%d versions différentes",
        distinctMany: "%d versions différentes",
        seenFromTo: "Sauvegardée du %@ au %@",
        seenOnce: "Sauvegardée le %@",
        versionsEmpty: "Aucune autre version de ce fichier.",
        close: "Fermer",
        preparingPreview: "Préparation de l’aperçu…",
        previewFailed: "Aperçu impossible\u{00A0}: %@",
        restoringItem: "Restauration de «\u{00A0}%@\u{00A0}»…",
        dropHint: "Dépose un fichier ici pour savoir s’il est sauvegardé",
        verdictTitle: "Ce fichier est-il sauvegardé\u{00A0}?",
        checking: "Vérification…",
        verdictBackedUp: "Sauvegardé · dernière version du %@",
        verdictModified: "Modifié depuis la sauvegarde du %@",
        verdictNotYet: "Pas encore sauvegardé · prochaine sauvegarde %@",
        verdictNotYetSoon: "Pas encore sauvegardé · la prochaine sauvegarde l’inclura",
        verdictExcluded: "Jamais sauvegardé · exclu par la règle «\u{00A0}%@\u{00A0}»",
        verdictCloudOnly: "Jamais sauvegardé · dans iCloud seulement",
        verdictOutside: "Jamais sauvegardé · hors des dossiers sauvegardés",
        verdictUnknown: "Vérification impossible pour l’instant",
        showInBackup: "Voir dans la sauvegarde",
        restoreTitle: "Restaurer",
        stepWhat: "Quoi",
        stepWhere: "Où",
        stepChecks: "Contrôles",
        stepProgress: "Restauration",
        stepDone: "Terminé",
        fromSnapshot: "Depuis la sauvegarde du %@",
        whereSeparate: "Dans un dossier à part",
        chooseFolder: "Choisir…",
        whereOriginal: "À leur emplacement d’origine",
        policyKeepBoth: "Garder les deux (suffixe «\u{00A0}restauré\u{00A0}»)",
        policyReplaceOlder: "Remplacer si plus ancien",
        policyReplaceAll: "Tout remplacer",
        restoredWord: "restauré",
        restoredFolderPrefix: "Restauré",
        checkSpaceOK: "%@ libres, %@ nécessaires",
        checkSpaceShort: "Pas assez d’espace\u{00A0}: il manque %@",
        checkSpaceUnknown: "Espace libre inconnu",
        checkWriteOK: "Écriture autorisée",
        checkWriteDenied: "Écriture impossible dans ce dossier",
        checkActiveSource: "Ce dossier est sauvegardé\u{00A0}: les fichiers restaurés seront dans la prochaine sauvegarde.",
        checkReplaceAll: "Les fichiers de ce Mac portant le même nom seront remplacés.",
        checkOtherMac: "Sauvegarde d’un autre Mac\u{00A0}: les propriétaires des fichiers ne sont pas repris.",
        continueAction: "Continuer",
        back: "Retour",
        cancel: "Annuler",
        startRestore: "Restaurer",
        resultComplete: "Restauration terminée",
        resultPartial: "Restauration terminée avec des erreurs",
        resultFailed: "La restauration a échoué",
        resultCanceled: "Restauration annulée",
        restoredOne: "1 fichier restauré",
        restoredFew: "%d fichiers restaurés",
        restoredMany: "%d fichiers restaurés",
        errorsOne: "1 fichier en erreur",
        errorsFew: "%d fichiers en erreur",
        errorsMany: "%d fichiers en erreur",
        showInFinder: "Afficher dans le Finder",
        done: "Terminé",
        runsTitle: "Opérations",
        kindBackup: "Sauvegarde",
        kindVerify: "Vérification",
        kindRestore: "Restauration",
        kindMaintenance: "Maintenance",
        triggerScheduled: "Planifiée",
        triggerCatchUp: "Rattrapage",
        triggerEarly: "Anticipée",
        triggerIsland: "Île",
        triggerSettings: "Réglages",
        triggerCommandBar: "Command Bar",
        triggerWindow: "Fenêtre Sauvegardes",
        triggerAgent: "Agent",
        outcomeComplete: "Complète",
        outcomePartial: "Partielle",
        outcomeFailed: "Échec",
        outcomeCanceled: "Annulée",
        outcomeNothing: "Rien de nouveau",
        stopUser: "arrêtée par toi",
        stopPaused: "mise en pause",
        stopMeeting: "réunion",
        stopSleep: "Mac en veille",
        stopAppUpdate: "mise à jour de l’app",
        stopWatchdog: "bloquée, arrêtée",
        stopFeatureOff: "fonction désactivée",
        stopAgentQuit: "agent arrêté",
        onBattery: "Sur batterie",
        onPower: "Sur secteur",
        batteryUsed: "%@ de batterie",
        columnDate: "Date",
        columnOperation: "Opération",
        columnTrigger: "Lancée par",
        columnResult: "Résultat",
        columnConditions: "Conditions",
        runsEmpty: "Aucune opération enregistrée pour l’instant.",
        slotsTitle: "Créneaux des 30 derniers jours",
        slotsEmpty: "Aucun créneau attendu pour l’instant.",
        markDone: "Fait",
        markPartial: "Partiel",
        markFailed: "Échec",
        markNothing: "Rien de nouveau",
        markAsleep: "Veille",
        markBattery: "Batterie",
        markNetwork: "Réseau",
        markPaused: "Pause",
        markMissed: "Manqué",
        markUpcoming: "À venir",
        reasonAsleep: "Mac en veille",
        reasonOff: "Mac éteint",
        slotDue: "Prévu à %@",
        slotStarted: "Lancé à %@",
        slotCaughtUp: "Rattrapé le %@",
        slotNotCaughtUp: "Pas encore rattrapé",
        chainTitle: "La chaîne",
        latency: "%@ ms",
        checkedAgo: "vérifié %@",
        lastIncident: "Dernier incident\u{00A0}: %@",
        noIncident: "Aucun incident connu",
        capacityTitle: "Espace",
        capProtected: "Protégé (taille réelle)",
        capSent: "Dernier envoi",
        capRepository: "Dépôt sur le stockage",
        capNASFree: "Libre sur le NAS",
        measured: "mesuré %@ · %@",
        sourceSnapshot: "dernière sauvegarde",
        sourceRun: "dernière opération",
        sourceBlobStats: "inventaire du dépôt",
        chartTitle: "90 derniers jours",
        chartEmpty: "Pas encore assez de mesures pour un graphe.",
        fullOne: "Plein dans environ 1 mois à ce rythme",
        fullFew: "Plein dans environ %d mois à ce rythme",
        fullMany: "Plein dans environ %d mois à ce rythme",
        agentTitle: "Agent et moteur",
        agentRunning: "Agent en marche",
        agentStopped: "Agent arrêté",
        agentBuild: "Version %@",
        stateWritten: "état écrit %@",
        engineInstalled: "Kopia %@ installé",
        engineDownloading: "Téléchargement du moteur…",
        engineVerifying: "Vérification du moteur…",
        engineFailed: "Installation du moteur échouée",
        costTitle: "Coût",
        costUnknown: "Pas encore mesuré",
        lastProblem: "Dernier problème",
        verificationsTitle: "Vérifications et restaurations test",
        levelManifest: "Manifeste",
        levelReferences: "Références",
        levelSample: "Échantillon de contenu (%@)",
        levelRestoreTest: "Restauration test",
        levelFull: "Contenu complet",
        rerun: "Relancer",
        verifyNow: "Vérifier maintenant",
        requestSent: "Demande envoyée à l’agent",
        requestFailed: "L’agent n’a pas reçu la demande",
        verificationsEmpty: "Aucune vérification enregistrée pour l’instant.",
        columnLevel: "Niveau",
        longWarning: "Long\u{00A0}: peut prendre des heures"
    )

    // Filled by their translations below; English until then.
    static let ptBR = enUS
    static let tr = enUS
    static let ru = enUS
    static let es = enUS
    static let sk = enUS
    static let de = enUS
    static let it = enUS
    static let ja = enUS
    static let ko = enUS
    static let uk = enUS
    static let zhHans = enUS
    static let zhTW = enUS
    static let zhHK = enUS
}
