// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// The words of the Settings package's screens: the page, its sheets, the
/// wizard, the kit. Shared words (states, nodes, buttons) stay in
/// `ForkMacBackupStrings`. Same contract as the other fork string tables:
/// memberwise init in declaration order, one static per language.
/// French: `\u{00A0}` before « : ; ! ? » and inside « », typographic
/// apostrophes. `%d` and `%@` are kept as in English, in the same order.
struct ForkMacBackupSettingsStrings {
    // MARK: General
    let done: String
    let cancel: String
    let apply: String
    let back: String
    let continueAction: String
    let finish: String
    let later: String
    let tryAgain: String
    let allow: String
    let connect: String
    let optional: String
    let openSystemSettings: String
    let showInFinder: String
    let fileNotSaved: String
    let folderMissing: String
    /// `%d`: how many more.
    let andMore: String
    let savedOnThisMac: String
    let engineUnavailable: String
    /// `%d`: milliseconds.
    let latencyMs: String
    /// `%d`: minutes.
    let minutesValue: String
    /// `%d`: seconds.
    let secondsValue: String
    /// `%d`: megabytes per second.
    let megabytesPerSecond: String
    let duration: String

    // MARK: Page
    let homeFolder: String
    let folderOne: String
    let folderFew: String
    let folderMany: String
    let exclusionOne: String
    let exclusionFew: String
    let exclusionMany: String
    let contentTitle: String
    let rhythmTitle: String
    let kitTitle: String
    let optionsTitle: String
    let optionsSummary: String
    let kitNeedsConnection: String
    let kitMissing: String
    /// `%@`: a date.
    let kitUpToDate: String
    let kitStaleChanged: String
    /// `%@`: a date.
    let kitStaleOld: String
    /// `%@`: a time of day.
    let nextAround: String
    /// `%@`: a node's name.
    let bannerNodeDown: String
    let editConnection: String
    let updatePassword: String
    let reinstallEngine: String

    // MARK: Chain
    let chainTitle: String
    /// `%@`: the server.
    let explainDirect: String
    /// `%@`: the server.
    let explainTailscale: String
    /// `%@` × 2: the server, the storage.
    let explainTailscaleStorage: String
    let nodeDetailHint: String
    let detailAddress: String
    let detailObservedIPs: String
    let detailLastCheck: String
    let detailFree: String
    let detailUniqueID: String
    let detailProbe: String
    let detailNotProbed: String
    let beyondBreak: String
    let aboutMac: String
    let aboutNetwork: String
    let aboutTailscale: String
    let aboutName: String
    let aboutS3: String
    let aboutRepository: String
    let aboutProxmox: String
    let aboutNAS: String
    let aboutCloud: String
    let remedyMac: String
    let remedyNetwork: String
    let remedyTailscale: String
    let remedyName: String
    let remedyS3: String
    let remedyRepository: String
    let remedyProxmox: String
    let remedyNAS: String
    let remedyCloud: String

    // MARK: Profiles
    let profilesMenu: String
    let profilesKnown: String
    let profileImport: String
    let profileExport: String
    let profileCreate: String
    let profileNone: String
    let profileNoneLabel: String
    /// `%@`: the profile's name.
    let profileNamed: String
    let profileUnreadable: String
    /// `%@`: the bucket.
    let profileDefaultName: String

    // MARK: Setup
    let setupTitle: String
    /// `%d` × 2: steps done, steps in all.
    let setupProgress: String
    let setupSwitchHint: String
    let stepDone: String
    let stepToDo: String
    let stepEngine: String
    let stepDiskAccess: String
    let stepBackground: String
    let stepRepository: String
    let stepKit: String
    let stepEngineCaption: String
    /// `%@`: the app's name.
    let stepDiskAccessCaption: String
    let stepBackgroundCaption: String
    let stepBackgroundAfterSwitch: String
    let stepBackgroundFailed: String
    let stepRepositoryCaption: String
    let stepKitCaption: String
    let engineInstall: String
    /// `%@`: a percentage.
    let engineDownloading: String
    let engineVerifying: String
    let engineFailed: String
    let engineNotInstalled: String
    let relaunch: String
    let kitCreate: String

    // MARK: Content
    let contentSubtitle: String
    let sourcesTitle: String
    let sourceAdd: String
    let sourceRemove: String
    let sourceDropHint: String
    let previewTitle: String
    let previewRun: String
    let previewRefresh: String
    let previewNever: String
    /// `%@`: a number of files.
    let previewScanning: String
    /// `%@`: a size.
    let previewKept: String
    /// `%@`: a size.
    let previewLeftOut: String
    /// `%@` × 2: when (« il y a 5 min »), a number of files.
    let previewMeasured: String
    let previewFooter: String
    let presetsTitle: String
    let presetsFooter: String
    let presetTrash: String
    let presetTrashCaption: String
    let presetCaches: String
    let presetCachesCaption: String
    let presetDocker: String
    let presetDockerCaption: String
    let presetAppleContainer: String
    let presetAppleContainerCaption: String
    let presetSparse: String
    let presetVirtualMachines: String
    let presetVirtualMachinesCaption: String
    let presetDevFolders: String
    let presetDevFoldersCaption: String
    let presetGenericBuild: String
    let presetGenericBuildCaption: String
    let presetCloudStorage: String
    let presetCloudStorageCaption: String
    let presetCacheTag: String
    let presetCacheTagCaption: String
    let presetLogs: String
    let presetLogsCaption: String
    let presetSecrets: String
    let presetSecretsCaption: String
    let secretsIncluded: String
    let vmWarning: String
    let matchOne: String
    let matchFew: String
    let matchMany: String
    let sparseTitle: String
    let sparseExplain: String
    /// `%@` × 3: the file, the size it announces, the size it holds.
    let sparseExplainMeasured: String
    /// `%@` × 2: announced, held.
    let sparseSizes: String
    let iCloudHeader: String
    let iCloudTitle: String
    let iCloudModeLocal: String
    let iCloudModeMaterialize: String
    let iCloudModeExclude: String
    let iCloudCaptionLocal: String
    let iCloudCaptionMaterialize: String
    let iCloudCaptionExclude: String
    /// `%@` × 2: a number of files, a size.
    let iCloudCloudOnly: String
    let rulesTitle: String
    let ruleOne: String
    let ruleFew: String
    let ruleMany: String
    let ruleField: String
    let rulePlaceholder: String
    let ruleAdd: String
    let ruleRemove: String
    let ruleNoMatch: String
    let rulesSyntax: String
    /// `%@`: the rule's name.
    let ruleExplainAnywhereFolder: String
    /// `%@`: the rule's name.
    let ruleExplainAnywhere: String
    /// `%@`: the rule's path.
    let ruleExplainAnchored: String

    // MARK: Rhythm
    let rhythmSubtitle: String
    let scheduleAuto: String
    let scheduleInterval: String
    let scheduleTimes: String
    let scheduleBoth: String
    let autoExplain: String
    let autoNotMeasured: String
    let measuredOne: String
    let measuredFew: String
    let measuredMany: String
    let every: String
    let atTimes: String
    let timeAdd: String
    let timeRemove: String
    let catchUp: String
    let catchUpCaption: String
    let powerHeader: String
    let powerTitle: String
    let powerAlways: String
    let powerAC: String
    let powerThreshold: String
    let powerMinimum: String
    let forceAfter: String
    let lowPowerWaits: String
    let keepAwake: String
    let keepAwakeNever: String
    let keepAwakeAC: String
    let keepAwakeAlways: String
    let keepAwakeCaption: String
    let conditionsHeader: String
    let limitedNetwork: String
    let limitedNetworkCaption: String
    let conditionWait: String
    let conditionSlow: String
    let conditionIgnore: String
    let meetingTitle: String
    let meetingPause: String
    let meetingNothing: String
    let earlyTitle: String
    /// `%d`: a number of files.
    let earlyCaption: String
    let earlyThreshold: String
    let speedHeader: String
    let slowLimit: String
    let slowLimitCaption: String
    let windowTitle: String
    let windowFrom: String
    let windowTo: String
    let windowLimit: String
    let priorityTitle: String
    let priorityLow: String
    let priorityNormal: String
    let priorityCaption: String

    // MARK: Options
    let optionsTabRetention: String
    let optionsTabVerifications: String
    let optionsTabNotifications: String
    let optionsTabAdvanced: String
    let retentionHeader: String
    let retentionBalanced: String
    let retentionEconomical: String
    let retentionLong: String
    let retentionCustom: String
    let latestOne: String
    let latestFew: String
    let latestMany: String
    let keepTheLatestOne: String
    let keepTheLatestFew: String
    let keepTheLatestMany: String
    /// `%@`: a span, « 48 heures ».
    let retentionHourly: String
    let retentionDaily: String
    let retentionWeekly: String
    let retentionMonthly: String
    let retentionAnnual: String
    /// `%@`: the list of what is kept.
    let retentionLead: String
    let retentionTail: String
    let retentionNothing: String
    let keepLatest: String
    let keepHourly: String
    let keepDaily: String
    let keepWeekly: String
    let keepMonthly: String
    let keepAnnual: String
    let retentionPreviewHeader: String
    let retentionPreviewCaption: String
    let retentionPreviewButton: String
    let retentionLoading: String
    /// `%d`: how many backups.
    let retentionKeepsAll: String
    /// `%d` × 2: deleted, in all.
    let retentionWouldDelete: String
    let retentionConfirmTitle: String
    /// `%d`: how many.
    let retentionConfirmMessage: String
    let maintenanceHeader: String
    let maintenanceLast: String
    let maintenanceFooter: String
    let repositorySizeLabel: String
    let outcomeComplete: String
    let outcomePartial: String
    let outcomeFailed: String
    let outcomeCanceled: String
    let outcomeNothing: String
    let verifyPlanHeader: String
    let verifyPlanFooter: String
    let verifyReferences: String
    let verifyReferencesCaption: String
    let verifyContent: String
    let verifyContentCaption: String
    let verifyRestore: String
    let verifyRestoreCaption: String
    let periodNever: String
    let periodDaily: String
    let periodWeekly: String
    let periodMonthly: String
    /// `%@`: a span.
    let periodEvery: String
    /// `%@`: when.
    let verifyLastOK: String
    /// `%@`: when.
    let verifyLastFailed: String
    let verifyNever: String
    let verifyNowHeader: String
    let verifyNow: String
    let verifyFull: String
    let verifyFullCaption: String
    let openVerifications: String
    let notifyHeader: String
    let notifyEvent: String
    let notifyIsland: String
    let notifySystem: String
    let notifyNothing: String
    let eventStart: String
    let eventComplete: String
    let eventPartial: String
    let eventFailure: String
    let eventLate: String
    let eventChainBroken: String
    let eventChainRestored: String
    let eventNASLow: String
    let eventVerifyFailed: String
    let eventRestoreDone: String
    let eventKitStale: String
    let notifyFooter: String
    let thresholdsHeader: String
    let lateThreshold: String
    let nasThreshold: String
    let notifyPermissionHeader: String
    let notifyGranted: String
    let notifyDenied: String
    let notifyUndetermined: String
    let engineHeader: String
    let engineVersion: String
    let cacheSize: String
    let timeoutsHeader: String
    let watchdog: String
    let repositoryTimeout: String
    let probeTimeout: String
    let toolsHeader: String
    let openLogs: String
    let exportDiagnostic: String
    let openTerminal: String
    let openTerminalCaption: String
    let terminalPasswordPrompt: String
    let terminalSecretPrompt: String
    let terminalBanner: String
    let connectionHeader: String
    let importBran: String
    let importBranCaption: String
    let disconnect: String
    let disconnectCaption: String
    let disconnectConfirmTitle: String

    // MARK: Kit
    let kitSubtitle: String
    let kitWhy: String
    let kitStaleChangedCaption: String
    let kitCreateHeader: String
    let kitIncludeSecrets: String
    let kitIncludeSecretsCaption: String
    let passphrase: String
    let passphraseConfirm: String
    let passphraseTooShort: String
    let passphraseMismatch: String
    let passphraseWrong: String
    let kitSavePDF: String
    let kitPrint: String
    let kitSaveFile: String
    let kitCopyFields: String
    let kitCopied: String
    /// `%@`: a file name.
    let kitSaved: String
    let kitInsideBackup: String
    let kitSecretsUnavailable: String
    let kitWhereFooter: String
    let kitReminderHeader: String
    let kitNextReminder: String
    let kitChecked: String
    let kitReminderFooter: String
    let kitOtherHeader: String
    let kitOpenOther: String
    let kitOpenOtherCaption: String
    let kitUnreadable: String
    /// `%@` × 2: an identity, a date.
    let kitFoundFor: String
    let kitFileName: String
    let kitFieldType: String
    let kitFieldEndpoint: String
    let kitFieldObserved: String
    let kitFieldBucket: String
    let kitFieldPrefix: String
    let kitFieldRegion: String
    let kitFieldAccessKey: String
    let kitFieldUniqueID: String
    let kitFieldIdentity: String
    let kitFieldKopia: String
    let kitFieldPassword: String
    let kitFieldSecretKey: String
    /// `%@` × 2: the app, a date.
    let kitPDFSubtitle: String
    let kitPDFRepository: String
    let kitPDFSecrets: String
    let kitPDFSecretsNote: String
    /// `%@`: the app.
    let kitPDFWithout: String
    let kitStepDownload: String
    let kitStepConnect: String
    let kitStepList: String
    let kitStepRestore: String
    /// `%@`: a SHA-256.
    let kitPDFChecksum: String
    /// `%@`: the app.
    let kitPDFWith: String
    /// `%@`: the app.
    let kitPDFWithSteps: String
    let kitPDFKeepAway: String
    /// `%@`: a fingerprint.
    let kitPDFFingerprint: String
    let kitRestoredFolder: String

    // MARK: Wizard
    let wizardTitle: String
    let wizardStepStart: String
    let wizardStepServer: String
    let wizardStepRepository: String
    let wizardStepIdentity: String
    let wizardStepKit: String
    let wizardCaptionStart: String
    let wizardCaptionServer: String
    let wizardCaptionRepository: String
    let wizardCaptionIdentity: String
    let wizardCaptionKit: String
    let startExisting: String
    let startProfile: String
    let startProfileCaption: String
    let startBran: String
    let startBranCaption: String
    let startManual: String
    let startManualCaption: String
    let startOther: String
    let startNew: String
    let startNewCaption: String
    let startOtherMac: String
    let startOtherMacCaption: String
    let branReading: String
    let branMissing: String
    let branFailed: String
    let branProfileName: String
    /// `%@`: the address it replaces.
    let branMagicDNS: String
    /// `%@` × 2: the bucket, the identity.
    let branDetails: String
    /// `%d` × 2: rules as presets, rules kept as free rules.
    let branRules: String
    /// `%d`: hours.
    let branRhythm: String
    let branSecretsRead: String
    let branSecretsMissing: String
    let branStillRuns: String
    let branStillRunsCaption: String
    let stopBran: String
    let stopBranTitle: String
    let stopBranMessage: String
    let branStopped: String
    let branStopFailed: String
    let serverHeader: String
    let serverType: String
    let serverGenericS3: String
    let serverAddress: String
    let serverAddressPrompt: String
    let serverPort: String
    let serverTLS: String
    let serverTLSCaption: String
    let serverTLSTailscale: String
    let tailscaleSuggestions: String
    /// `%@`: a peer's name.
    let tailscalePeerLabel: String
    let storageHeader: String
    let serverBucket: String
    let serverRegion: String
    let serverPrefix: String
    let keysHeader: String
    let serverAccessKey: String
    let serverSecretKey: String
    let keysFooter: String
    let issueAddress: String
    let issuePort: String
    let issueBucket: String
    let issueRegion: String
    let issueAccessKey: String
    let issueSecretKey: String
    let repositoryHeader: String
    let repositoryPassword: String
    let repositoryPasswordCaption: String
    let repositoryPasswordNew: String
    let testHeader: String
    let testConnection: String
    let testSkipped: String
    let testEngineMissing: String
    let testTailscaleOff: String
    let testPeerOnline: String
    let testPeerOffline: String
    let testPeerMissing: String
    let testNetworkOK: String
    let testTimeout: String
    let testServerUnreachable: String
    let testAuthentication: String
    let thisRepository: String
    let uniqueIDLabel: String
    let machinesFound: String
    let machinesNone: String
    let snapshotOne: String
    let snapshotFew: String
    let snapshotMany: String
    let lockCaption: String
    let lockButton: String
    let locked: String
    let lockedExpected: String
    let otherMacHeader: String
    let otherMacBrowse: String
    let otherMacBrowseCaption: String
    let otherMacTakeOver: String
    let otherMacTakeOverCaption: String
    let identityHeader: String
    /// `%@`: an identity, « user@host ».
    let identityContinue: String
    let identityNew: String
    let identityUser: String
    let identityHost: String
    let identityFooter: String
    /// `%@` × 2: an identity, when (« il y a 3 h »).
    let identityStillUsed: String
    let doneTitle: String
    let doneCaption: String
    let doneBrowseTitle: String
    let doneBrowseCaption: String
    let keychainFailed: String

    static func strings(_ language: AppLanguage) -> ForkMacBackupSettingsStrings {
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
}

// MARK: - Words for values

extension ForkMacBackupSettingsStrings {
    private func counted(_ count: Int, _ language: AppLanguage, _ one: String, _ few: String, _ many: String) -> String {
        ForkMacBackupStrings.counted(count, language: language, one: one, few: few, many: many)
    }

    func folderCount(_ count: Int, language: AppLanguage) -> String {
        counted(count, language, folderOne, folderFew, folderMany)
    }

    func exclusionCount(_ count: Int, language: AppLanguage) -> String {
        counted(count, language, exclusionOne, exclusionFew, exclusionMany)
    }

    func matchCount(_ count: Int, language: AppLanguage) -> String {
        counted(count, language, matchOne, matchFew, matchMany)
    }

    func measuredOver(_ count: Int, language: AppLanguage) -> String {
        counted(count, language, measuredOne, measuredFew, measuredMany)
    }

    func ruleCount(_ count: Int, language: AppLanguage) -> String {
        counted(count, language, ruleOne, ruleFew, ruleMany)
    }

    func snapshotCount(_ count: Int, language: AppLanguage) -> String {
        counted(count, language, snapshotOne, snapshotFew, snapshotMany)
    }

    func stepTitle(_ step: ForkMacBackupSetupStep) -> String {
        switch step {
        case .engine: return stepEngine
        case .diskAccess: return stepDiskAccess
        case .background: return stepBackground
        case .repository: return stepRepository
        case .kit: return stepKit
        }
    }

    func presetTitle(_ preset: ForkMacBackupPreset) -> String {
        switch preset {
        case .trash: return presetTrash
        case .caches: return presetCaches
        case .docker: return presetDocker
        case .appleContainer: return presetAppleContainer
        case .sparseDiskImages: return presetSparse
        case .virtualMachines: return presetVirtualMachines
        case .devFolders: return presetDevFolders
        case .genericBuildNames: return presetGenericBuild
        case .cloudStorage: return presetCloudStorage
        case .cacheDirTag: return presetCacheTag
        case .logs: return presetLogs
        case .secrets: return presetSecrets
        }
    }

    func presetCaption(_ preset: ForkMacBackupPreset) -> String {
        switch preset {
        case .trash: return presetTrashCaption
        case .caches: return presetCachesCaption
        case .docker: return presetDockerCaption
        case .appleContainer: return presetAppleContainerCaption
        case .sparseDiskImages: return sparseExplain
        case .virtualMachines: return presetVirtualMachinesCaption
        case .devFolders: return presetDevFoldersCaption
        case .genericBuildNames: return presetGenericBuildCaption
        case .cloudStorage: return presetCloudStorageCaption
        case .cacheDirTag: return presetCacheTagCaption
        case .logs: return presetLogsCaption
        case .secrets: return presetSecretsCaption
        }
    }

    func iCloudMode(_ mode: ForkMacBackupICloudMode) -> String {
        switch mode {
        case .local: return iCloudModeLocal
        case .materialize: return iCloudModeMaterialize
        case .exclude: return iCloudModeExclude
        }
    }

    func iCloudCaption(_ mode: ForkMacBackupICloudMode) -> String {
        switch mode {
        case .local: return iCloudCaptionLocal
        case .materialize: return iCloudCaptionMaterialize
        case .exclude: return iCloudCaptionExclude
        }
    }

    func scheduleMode(_ mode: ForkMacBackupScheduleMode) -> String {
        switch mode {
        case .auto: return scheduleAuto
        case .interval: return scheduleInterval
        case .times: return scheduleTimes
        case .both: return scheduleBoth
        }
    }

    func optionsTab(_ tab: ForkMacBackupOptionsTab) -> String {
        switch tab {
        case .retention: return optionsTabRetention
        case .verifications: return optionsTabVerifications
        case .notifications: return optionsTabNotifications
        case .advanced: return optionsTabAdvanced
        }
    }

    func notifyEventTitle(_ event: ForkMacBackupNotifyEvent) -> String {
        switch event {
        case .start: return eventStart
        case .complete: return eventComplete
        case .partial: return eventPartial
        case .failure: return eventFailure
        case .late: return eventLate
        case .chainBroken: return eventChainBroken
        case .chainRestored: return eventChainRestored
        case .nasLow: return eventNASLow
        case .verifyFailed: return eventVerifyFailed
        case .restoreDone: return eventRestoreDone
        case .kitStale: return eventKitStale
        }
    }

    func outcome(_ outcome: ForkMacBackupRunRecord.Outcome) -> String {
        switch outcome {
        case .complete: return outcomeComplete
        case .partial: return outcomePartial
        case .failed: return outcomeFailed
        case .canceled: return outcomeCanceled
        case .nothingToDo: return outcomeNothing
        }
    }

    func retentionPresetName(_ preset: ForkMacBackupRetention.Preset) -> String {
        switch preset {
        case .balanced: return retentionBalanced
        case .economical: return retentionEconomical
        case .long: return retentionLong
        case .custom: return retentionCustom
        }
    }

    func verifyLevelTitle(_ level: ForkMacBackupVerifyPlan.Level) -> String {
        switch level {
        case .references: return verifyReferences
        case .contentSample: return verifyContent
        case .restoreTest: return verifyRestore
        }
    }

    func verifyLevelCaption(_ level: ForkMacBackupVerifyPlan.Level) -> String {
        switch level {
        case .references: return verifyReferencesCaption
        case .contentSample: return verifyContentCaption
        case .restoreTest: return verifyRestoreCaption
        }
    }

    func about(_ kind: ForkMacBackupChainNode.Kind) -> String {
        switch kind {
        case .mac: return aboutMac
        case .network: return aboutNetwork
        case .tailscale: return aboutTailscale
        case .name: return aboutName
        case .s3: return aboutS3
        case .repository: return aboutRepository
        case .proxmox: return aboutProxmox
        case .nas: return aboutNAS
        case .cloud: return aboutCloud
        }
    }

    func remedy(_ kind: ForkMacBackupChainNode.Kind) -> String {
        switch kind {
        case .mac: return remedyMac
        case .network: return remedyNetwork
        case .tailscale: return remedyTailscale
        case .name: return remedyName
        case .s3: return remedyS3
        case .repository: return remedyRepository
        case .proxmox: return remedyProxmox
        case .nas: return remedyNAS
        case .cloud: return remedyCloud
        }
    }

    func wizardStepName(_ step: ForkMacBackupWizardStep) -> String {
        switch step {
        case .start: return wizardStepStart
        case .server: return wizardStepServer
        case .repository: return wizardStepRepository
        case .identity: return wizardStepIdentity
        case .kit: return wizardStepKit
        }
    }

    func wizardStepCaption(_ step: ForkMacBackupWizardStep) -> String {
        switch step {
        case .start: return wizardCaptionStart
        case .server: return wizardCaptionServer
        case .repository: return wizardCaptionRepository
        case .identity: return wizardCaptionIdentity
        case .kit: return wizardCaptionKit
        }
    }

    func issue(_ issue: ForkMacBackupServerForm.Issue) -> String {
        switch issue {
        case .address: return issueAddress
        case .port: return issuePort
        case .bucket: return issueBucket
        case .region: return issueRegion
        case .accessKey: return issueAccessKey
        case .secretKey: return issueSecretKey
        }
    }

    /// The four rescue commands' titles, in order.
    func kitStep(_ index: Int) -> String {
        [kitStepDownload, kitStepConnect, kitStepList, kitStepRestore][min(max(index, 0), 3)]
    }

    /// A verification's period: never, every day, week, month, or « every N ».
    func period(_ hours: Int?, locale: Locale) -> String {
        guard let hours, hours > 0 else { return periodNever }
        switch hours {
        case 24: return periodDaily
        case 7 * 24: return periodWeekly
        case 30 * 24: return periodMonthly
        default:
            let unit: NSCalendar.Unit = hours % 24 == 0 ? .day : .hour
            return String(format: periodEvery, Self.span(hours % 24 == 0 ? hours / 24 : hours, unit, locale: locale))
        }
    }

    /// « 10 dernières · 48 h · 30 j · 8 sem. · 12 mois · 3 ans ».
    func retentionShort(_ retention: ForkMacBackupRetention, language: AppLanguage,
                        locale: Locale) -> String {
        var parts: [String] = []
        if retention.latest > 0 { parts.append(counted(retention.latest, language, latestOne, latestFew, latestMany)) }
        let spans: [(Int, NSCalendar.Unit)] = [(retention.hourly, .hour), (retention.daily, .day),
                                               (retention.weekly, .weekOfMonth), (retention.monthly, .month),
                                               (retention.annual, .year)]
        for (value, unit) in spans where value > 0 {
            parts.append(Self.span(value, unit, locale: locale, style: .abbreviated))
        }
        return parts.joined(separator: " · ")
    }

    /// The retention in a sentence: what is kept, and that a backup can
    /// count for several rules (plan §7.2).
    func retentionExplain(_ retention: ForkMacBackupRetention, language: AppLanguage, locale: Locale) -> String {
        var parts: [String] = []
        if retention.latest > 0 {
            parts.append(counted(retention.latest, language, keepTheLatestOne, keepTheLatestFew, keepTheLatestMany))
        }
        let rules: [(Int, NSCalendar.Unit, String)] = [
            (retention.hourly, .hour, retentionHourly), (retention.daily, .day, retentionDaily),
            (retention.weekly, .weekOfMonth, retentionWeekly), (retention.monthly, .month, retentionMonthly),
            (retention.annual, .year, retentionAnnual),
        ]
        for (value, unit, format) in rules where value > 0 {
            parts.append(String(format: format, Self.span(value, unit, locale: locale)))
        }
        guard !parts.isEmpty else { return retentionNothing }
        return String(format: retentionLead, parts.joined(separator: ", ")) + " " + retentionTail
    }

    /// What a free rule does, in words.
    func ruleExplain(_ rule: ForkMacBackupIgnoreRule) -> String {
        if rule.anchored { return String(format: ruleExplainAnchored, rule.pattern) }
        return String(format: rule.directoryOnly ? ruleExplainAnywhereFolder : ruleExplainAnywhere, rule.pattern)
    }

    /// « 48 heures », « 3 ans », « 8 sem. »: plurals by the system.
    static func span(_ value: Int, _ unit: NSCalendar.Unit, locale: Locale,
                     style: DateComponentsFormatter.UnitsStyle = .full) -> String {
        let formatter = DateComponentsFormatter()
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        formatter.calendar = calendar
        formatter.unitsStyle = style
        formatter.allowedUnits = [unit]
        formatter.maximumUnitCount = 1
        var components = DateComponents()
        switch unit {
        case .hour: components.hour = value
        case .day: components.day = value
        case .weekOfMonth: components.weekOfMonth = value
        case .month: components.month = value
        case .year: components.year = value
        default: components.hour = value
        }
        return formatter.string(from: components) ?? String(value)
    }
}

// MARK: - English

extension ForkMacBackupSettingsStrings {
    static let enUS = ForkMacBackupSettingsStrings(
        done: "Done",
        cancel: "Cancel",
        apply: "Apply",
        back: "Back",
        continueAction: "Continue",
        finish: "Finish",
        later: "Later",
        tryAgain: "Try Again",
        allow: "Allow…",
        connect: "Connect…",
        optional: "Optional",
        openSystemSettings: "Open System Settings",
        showInFinder: "Show in Finder",
        fileNotSaved: "The file could not be saved.",
        folderMissing: "This folder does not exist yet.",
        andMore: "and %d more",
        savedOnThisMac: "Saved on this Mac",
        engineUnavailable: "The backup engine is not available yet.",
        latencyMs: "%d ms",
        minutesValue: "%d min",
        secondsValue: "%d s",
        megabytesPerSecond: "%d MB/s",
        duration: "Duration",
        homeFolder: "Home folder",
        folderOne: "1 folder",
        folderFew: "%d folders",
        folderMany: "%d folders",
        exclusionOne: "1 exclusion",
        exclusionFew: "%d exclusions",
        exclusionMany: "%d exclusions",
        contentTitle: "Content",
        rhythmTitle: "Rhythm",
        kitTitle: "Recovery Kit",
        optionsTitle: "Options",
        optionsSummary: "verifications, notifications…",
        kitNeedsConnection: "After connecting a repository",
        kitMissing: "Not created yet",
        kitUpToDate: "Up to date · made %@",
        kitStaleChanged: "To redo: the connection changed",
        kitStaleOld: "To check: made %@",
        nextAround: "Next around %@",
        bannerNodeDown: "%@ unreachable",
        editConnection: "Edit Connection…",
        updatePassword: "Update Password…",
        reinstallEngine: "Reinstall the Engine",
        chainTitle: "My Chain",
        explainDirect: "This Mac encrypts everything before it leaves, then sends it straight to %@.",
        explainTailscale: "This Mac encrypts everything, then sends it through Tailscale to %@.",
        explainTailscaleStorage: "This Mac encrypts everything, sends it through Tailscale to %@, which stores the blocks on %@.",
        nodeDetailHint: "Shows the details of this step",
        detailAddress: "Address",
        detailObservedIPs: "Addresses seen",
        detailLastCheck: "Last check",
        detailFree: "Free",
        detailUniqueID: "Unique ID",
        detailProbe: "Check",
        detailNotProbed: "Drawn only, never checked",
        beyondBreak: "Can’t be checked while an earlier step is down.",
        aboutMac: "Reads your files, encrypts them and sends only what changed.",
        aboutNetwork: "The Wi-Fi or Ethernet connection of this Mac.",
        aboutTailscale: "A private, encrypted tunnel to the server, wherever you are.",
        aboutName: "The server’s name, turned into its address.",
        aboutS3: "Receives the encrypted blocks over S3.",
        aboutRepository: "The Kopia repository, recognized by its unique ID.",
        aboutProxmox: "The machine that runs the server.",
        aboutNAS: "Keeps the blocks on its disks.",
        aboutCloud: "Storage at a provider.",
        remedyMac: "Finish the Getting Started steps on this page.",
        remedyNetwork: "Connect this Mac to a network.",
        remedyTailscale: "Open Tailscale and check that it is connected and that the server is online.",
        remedyName: "The name no longer leads to the server: check the address in the connection.",
        remedyS3: "Check that the server is on and that its S3 service is running.",
        remedyRepository: "Check the password and the keys, or that this is the right repository.",
        remedyProxmox: "Check that the machine and the server’s container are running.",
        remedyNAS: "Check that the NAS is on and that its share is mounted.",
        remedyCloud: "Check the provider’s status page.",
        profilesMenu: "Profiles",
        profilesKnown: "On this Mac",
        profileImport: "Import a Profile…",
        profileExport: "Export This Profile…",
        profileCreate: "Create a Profile…",
        profileNone: "Stop Using a Profile",
        profileNoneLabel: "No profile",
        profileNamed: "Profile “%@”",
        profileUnreadable: "This file is not a backup profile.",
        profileDefaultName: "My server (%@)",
        setupTitle: "Protect this Mac",
        setupProgress: "%d of %d steps done",
        setupSwitchHint: "Turn Mac Backup on above so it starts once these steps are done.",
        stepDone: "Done",
        stepToDo: "To do",
        stepEngine: "Install the backup engine",
        stepDiskAccess: "Allow Full Disk Access",
        stepBackground: "Allow running in the background",
        stepRepository: "Connect your repository",
        stepKit: "Create the recovery kit",
        stepEngineCaption: "Kopia 0.23.1, checked against its fingerprint before use.",
        stepDiskAccessCaption: "In System Settings › Privacy & Security › Full Disk Access, turn on “%@”, then relaunch it.",
        stepBackgroundCaption: "So backups run even when the app is closed.",
        stepBackgroundAfterSwitch: "Asked for when Mac Backup is turned on.",
        stepBackgroundFailed: "macOS refused to register the background agent.",
        stepRepositoryCaption: "Your MinIO or S3 server, tested before anything is saved.",
        stepKitCaption: "To get your backups back without this Mac.",
        engineInstall: "Install",
        engineDownloading: "Downloading… %@",
        engineVerifying: "Checking the download…",
        engineFailed: "The installation failed.",
        engineNotInstalled: "Not installed",
        relaunch: "Relaunch",
        kitCreate: "Create the Kit…",
        contentSubtitle: "What goes into the backup, with the real size of each part.",
        sourcesTitle: "Folders backed up",
        sourceAdd: "Add a Folder…",
        sourceRemove: "Remove This Folder",
        sourceDropHint: "or drop folders here",
        previewTitle: "Preview",
        previewRun: "Measure",
        previewRefresh: "Measure Again",
        previewNever: "Measure what would be kept and left out, with the space it really takes.",
        previewScanning: "Measuring… %@ files",
        previewKept: "%@ kept",
        previewLeftOut: "%@ left out",
        previewMeasured: "Measured %@ · %@ files kept",
        previewFooter: "Real sizes on disk, never the size a file announces.",
        presetsTitle: "Left out",
        presetsFooter: "On means left out of the backup. Nothing is deleted from your Mac.",
        presetTrash: "Trash",
        presetTrashCaption: "What you already threw away.",
        presetCaches: "macOS caches",
        presetCachesCaption: "Apps rebuild them on their own.",
        presetDocker: "Docker Desktop",
        presetDockerCaption: "Its virtual disk. Your project folders are still backed up.",
        presetAppleContainer: "Apple containers",
        presetAppleContainerCaption: "The disk images of Linux containers (such as kali).",
        presetSparse: "Sparse disk images",
        presetVirtualMachines: "Virtual machines",
        presetVirtualMachinesCaption: "Parallels, UTM… A running VM may not be copied consistently.",
        presetDevFolders: "Rebuildable dev folders",
        presetDevFoldersCaption: "node_modules, .venv, DerivedData… your tools recreate them.",
        presetGenericBuild: "Folders named build, dist, out…",
        presetGenericBuildCaption: "May hold real work: look at the paths before ticking.",
        presetCloudStorage: "Other clouds",
        presetCloudStorageCaption: "Dropbox, Google Drive… Their provider keeps a copy, not this history.",
        presetCacheTag: "Folders marked as cache",
        presetCacheTagCaption: "Those holding a CACHEDIR.TAG file.",
        presetLogs: "Log files",
        presetLogsCaption: "Files ending in .log.",
        presetSecrets: "Private keys",
        presetSecretsCaption: ".ssh, .gnupg and keychains.",
        secretsIncluded: "Your private keys are in the backup, encrypted on this Mac before they leave.",
        vmWarning: "Shut virtual machines down before a backup for a consistent copy.",
        matchOne: "1 match",
        matchFew: "%d matches",
        matchMany: "%d matches",
        sparseTitle: "Sparse disk images",
        sparseExplain: "Docker, containers and any file of 10 GB or more less than half written: they announce far more than they hold. Left out, never deleted or resized.",
        sparseExplainMeasured: "%@ announces %@ but really takes %@ on the disk: it is left out, never deleted or resized.",
        sparseSizes: "announces %@ · holds %@",
        iCloudHeader: "iCloud Drive",
        iCloudTitle: "Files only in iCloud",
        iCloudModeLocal: "Back up the files on this Mac",
        iCloudModeMaterialize: "Download everything first",
        iCloudModeExclude: "Leave iCloud Drive out",
        iCloudCaptionLocal: "Files kept only in iCloud are listed apart and don’t make a backup partial.",
        iCloudCaptionMaterialize: "Downloads them before each backup: it takes space on this Mac.",
        iCloudCaptionExclude: "iCloud keeps its own copy, but not this history.",
        iCloudCloudOnly: "%@ files only in iCloud (%@)",
        rulesTitle: "Custom rules",
        ruleOne: "1 rule",
        ruleFew: "%d rules",
        ruleMany: "%d rules",
        ruleField: "New rule",
        rulePlaceholder: "e.g. Movies/Exports/",
        ruleAdd: "Add",
        ruleRemove: "Remove This Rule",
        ruleNoMatch: "Matches nothing at the last measure",
        rulesSyntax: "One rule per line, as in .gitignore: “name” anywhere, “/name” at the top of the folder, “name/” folders only, * and ? as wildcards.",
        ruleExplainAnywhereFolder: "Leaves out every folder named “%@”, wherever it is.",
        ruleExplainAnywhere: "Leaves out every file or folder named “%@”, wherever it is.",
        ruleExplainAnchored: "Leaves out “%@” from the top of each folder backed up.",
        rhythmSubtitle: "When backups run, and what they wait for.",
        scheduleAuto: "Automatic",
        scheduleInterval: "Interval",
        scheduleTimes: "Fixed times",
        scheduleBoth: "Both",
        autoExplain: "Backs up once enough has changed, at least an hour apart and at most 4 hours on power (8 on battery). Paced by what a backup really costs on this Mac.",
        autoNotMeasured: "Measured after the first backups.",
        measuredOne: "Measured over 1 backup",
        measuredFew: "Measured over %d backups",
        measuredMany: "Measured over %d backups",
        every: "Every",
        atTimes: "At",
        timeAdd: "Add a Time",
        timeRemove: "Remove This Time",
        catchUp: "Catch up after waking",
        catchUpCaption: "A missed backup starts this long after the Mac wakes up or you log in.",
        powerHeader: "Power",
        powerTitle: "Back up",
        powerAlways: "Always",
        powerAC: "On power only",
        powerThreshold: "On battery above a level",
        powerMinimum: "Battery at least",
        forceAfter: "Anyway after",
        lowPowerWaits: "Wait while Low Power Mode is on",
        keepAwake: "Keep the Mac awake",
        keepAwakeNever: "Never",
        keepAwakeAC: "On power",
        keepAwakeAlways: "Always",
        keepAwakeCaption: "Prevents idle sleep during a backup. The Mac must stay open and on.",
        conditionsHeader: "Conditions",
        limitedNetwork: "On a limited network",
        limitedNetworkCaption: "A personal hotspot or a network marked as limited.",
        conditionWait: "Wait",
        conditionSlow: "Slow down",
        conditionIgnore: "Back up anyway",
        meetingTitle: "During a recorded meeting",
        meetingPause: "Pause",
        meetingNothing: "Nothing",
        earlyTitle: "Back up early after many changes",
        earlyCaption: "When %d files change in Documents or Desktop, without waiting for the next slot.",
        earlyThreshold: "Files changed",
        speedHeader: "Speed",
        slowLimit: "“Slow Down” limit",
        slowLimitCaption: "Used during meetings, on a limited network and by the island’s Slow Down button.",
        windowTitle: "Slower during part of the day",
        windowFrom: "From",
        windowTo: "to",
        windowLimit: "Limit",
        priorityTitle: "Priority",
        priorityLow: "Low (the Mac stays smooth)",
        priorityNormal: "Normal",
        priorityCaption: "A backup started by hand always runs at normal priority.",
        optionsTabRetention: "Retention",
        optionsTabVerifications: "Verifications",
        optionsTabNotifications: "Notifications",
        optionsTabAdvanced: "Advanced",
        retentionHeader: "What is kept",
        retentionBalanced: "Balanced",
        retentionEconomical: "Thrifty",
        retentionLong: "Long",
        retentionCustom: "Custom",
        latestOne: "1 latest",
        latestFew: "%d latest",
        latestMany: "%d latest",
        keepTheLatestOne: "the latest one",
        keepTheLatestFew: "the %d latest",
        keepTheLatestMany: "the %d latest",
        retentionHourly: "one per hour for %@",
        retentionDaily: "one per day for %@",
        retentionWeekly: "one per week for %@",
        retentionMonthly: "one per month for %@",
        retentionAnnual: "one per year for %@",
        retentionLead: "Keeps %@.",
        retentionTail: "These are not extra copies: one backup can count for several rules.",
        retentionNothing: "Keeps nothing: every backup would be deleted.",
        keepLatest: "Latest",
        keepHourly: "Hourly",
        keepDaily: "Daily",
        keepWeekly: "Weekly",
        keepMonthly: "Monthly",
        keepAnnual: "Yearly",
        retentionPreviewHeader: "Before applying",
        retentionPreviewCaption: "See which backups this setting would delete.",
        retentionPreviewButton: "Show",
        retentionLoading: "Reading the backups…",
        retentionKeepsAll: "All kept · %d",
        retentionWouldDelete: "Would delete %d of %d",
        retentionConfirmTitle: "Delete these backups?",
        retentionConfirmMessage: "%d backups will be deleted at the end of the next backup. The space comes back after the full maintenance.",
        maintenanceHeader: "Maintenance",
        maintenanceLast: "Last full maintenance",
        maintenanceFooter: "Space only comes back after the full maintenance, about two days after a backup is deleted. It runs at night, on power.",
        repositorySizeLabel: "Repository on the server",
        outcomeComplete: "done",
        outcomePartial: "partial",
        outcomeFailed: "failed",
        outcomeCanceled: "canceled",
        outcomeNothing: "nothing to do",
        verifyPlanHeader: "Planned checks",
        verifyPlanFooter: "Each level proves a little more. They run in the background, on power.",
        verifyReferences: "Every block is there",
        verifyReferencesCaption: "Checks that the content of each backup exists on the server.",
        verifyContent: "Sample read back",
        verifyContentCaption: "Downloads and decrypts 1% of the files: about 98% covered in a year.",
        verifyRestore: "Test restore",
        verifyRestoreCaption: "Restores 50 random files and compares them byte for byte.",
        periodNever: "Never",
        periodDaily: "Every day",
        periodWeekly: "Every week",
        periodMonthly: "Every month",
        periodEvery: "Every %@",
        verifyLastOK: "Passed %@",
        verifyLastFailed: "Failed %@",
        verifyNever: "Never run yet",
        verifyNowHeader: "Now",
        verifyNow: "Verify Now",
        verifyFull: "Everything (long)",
        verifyFullCaption: "“Everything” reads the whole repository back: hours for a big one.",
        openVerifications: "Open the Verifications History",
        notifyHeader: "What tells you",
        notifyEvent: "Event",
        notifyIsland: "Island",
        notifySystem: "Notification",
        notifyNothing: "Nothing",
        eventStart: "Backup starts",
        eventComplete: "Backup complete",
        eventPartial: "Partial backup",
        eventFailure: "Backup failed",
        eventLate: "No backup for too long",
        eventChainBroken: "Chain broken",
        eventChainRestored: "Chain back",
        eventNASLow: "Storage almost full",
        eventVerifyFailed: "Verification failed",
        eventRestoreDone: "Restore finished",
        eventKitStale: "Kit to redo",
        notifyFooter: "By default nothing leaves the island’s section but the end-of-backup notice.",
        thresholdsHeader: "Thresholds",
        lateThreshold: "Late after",
        nasThreshold: "Storage free below",
        notifyPermissionHeader: "System notifications",
        notifyGranted: "Allowed",
        notifyDenied: "Turned off in System Settings",
        notifyUndetermined: "Not asked yet",
        engineHeader: "Engine",
        engineVersion: "Version",
        cacheSize: "Local cache",
        timeoutsHeader: "Time limits",
        watchdog: "No progress for",
        repositoryTimeout: "Opening the repository",
        probeTimeout: "Checking a step",
        toolsHeader: "Tools",
        openLogs: "Show the Logs",
        exportDiagnostic: "Export a Diagnostic…",
        openTerminal: "Open a Configured Terminal",
        openTerminalCaption: "Kopia set up for this repository; it asks for the password, nothing secret is written.",
        terminalPasswordPrompt: "Repository password:",
        terminalSecretPrompt: "S3 secret key:",
        terminalBanner: "Kopia is ready for this repository. Try: kopia snapshot list",
        connectionHeader: "Connection",
        importBran: "Import from Bran…",
        importBranCaption: "Reads Bran’s settings when you click, and asks before stopping it.",
        disconnect: "Disconnect This Mac",
        disconnectCaption: "Forgets the repository and its secrets on this Mac. Nothing is erased on the server.",
        disconnectConfirmTitle: "Disconnect this Mac?",
        kitSubtitle: "Everything it takes to reach your backups without this Mac.",
        kitWhy: "Without this Mac you need the address, the password and the repository’s ID. The kit puts them together.",
        kitStaleChangedCaption: "The address, the keys or the identity changed since: the old kit would lead nowhere.",
        kitCreateHeader: "Create",
        kitIncludeSecrets: "Include the secrets, sealed by a passphrase",
        kitIncludeSecretsCaption: "Only in the file. Keep the passphrase somewhere else: without it they don’t open.",
        passphrase: "Passphrase",
        passphraseConfirm: "Confirm",
        passphraseTooShort: "At least 8 characters.",
        passphraseMismatch: "The two don’t match.",
        passphraseWrong: "Wrong passphrase, or a damaged file.",
        kitSavePDF: "Save the PDF…",
        kitPrint: "Print…",
        kitSaveFile: "Save the Kit File…",
        kitCopyFields: "Copy the fields for a password manager",
        kitCopied: "Copied, without the secrets.",
        kitSaved: "Saved: %@",
        kitInsideBackup: "This folder is itself backed up: keep another copy on a USB key or in a password manager.",
        kitSecretsUnavailable: "The secrets could not be read from the Keychain.",
        kitWhereFooter: "Keep it away from this Mac: a USB key, a printed page, a password manager.",
        kitReminderHeader: "Reminder",
        kitNextReminder: "Next reminder",
        kitChecked: "I Checked That I Can Open My Kit",
        kitReminderFooter: "Every 180 days, and whenever the address or the password changes.",
        kitOtherHeader: "From another Mac",
        kitOpenOther: "Open Another Mac’s Kit…",
        kitOpenOtherCaption: "To browse and restore its backups, read only.",
        kitUnreadable: "This file is not a recovery kit.",
        kitFoundFor: "Kit of %@, made %@",
        kitFileName: "Recovery Kit",
        kitFieldType: "Type",
        kitFieldEndpoint: "Address",
        kitFieldObserved: "Addresses seen",
        kitFieldBucket: "Bucket",
        kitFieldPrefix: "Prefix",
        kitFieldRegion: "Region",
        kitFieldAccessKey: "S3 access key",
        kitFieldUniqueID: "Repository ID",
        kitFieldIdentity: "This Mac’s identity",
        kitFieldKopia: "Kopia version",
        kitFieldPassword: "Repository password",
        kitFieldSecretKey: "S3 secret key",
        kitPDFSubtitle: "Mac Backup · %@ · %@",
        kitPDFRepository: "Your repository",
        kitPDFSecrets: "Also needed",
        kitPDFSecretsNote: "Never printed here. Write them by hand only if this page stays somewhere safe.",
        kitPDFWithout: "Without %@",
        kitStepDownload: "Download Kopia and check its fingerprint",
        kitStepConnect: "Connect, read only (the password is asked for)",
        kitStepList: "List the backups",
        kitStepRestore: "Restore one into a folder",
        kitPDFChecksum: "Expected SHA-256: %@",
        kitPDFWith: "With %@ on another Mac",
        kitPDFWithSteps: "Install %@, turn Mac Backup on, choose “Open another Mac’s repository” and open the kit file. You browse and restore without touching this Mac’s backups.",
        kitPDFKeepAway: "Keep this page away from this Mac.",
        kitPDFFingerprint: "Kit %@",
        kitRestoredFolder: "Restored",
        wizardTitle: "Connect a Repository",
        wizardStepStart: "Start",
        wizardStepServer: "Server",
        wizardStepRepository: "Repository",
        wizardStepIdentity: "This Mac",
        wizardStepKit: "Kit",
        wizardCaptionStart: "Where are you starting from?",
        wizardCaptionServer: "Where your backups are stored.",
        wizardCaptionRepository: "The password, then a test of every step.",
        wizardCaptionIdentity: "Who this Mac is in the repository.",
        wizardCaptionKit: "Connected. One more thing.",
        startExisting: "I already have a repository",
        startProfile: "Import a profile",
        startProfileCaption: "A .swishsaint-backup-profile file fills in everything but the secrets.",
        startBran: "Import from Bran",
        startBranCaption: "Takes over Bran’s backup on this Mac: same repository, same history.",
        startManual: "Type in my server",
        startManualCaption: "MinIO, Backblaze B2, Wasabi, AWS… any S3.",
        startOther: "Other",
        startNew: "New repository",
        startNewCaption: "An empty bucket becomes an encrypted repository.",
        startOtherMac: "Open another Mac’s repository",
        startOtherMacCaption: "With its kit, read only, to restore its files here.",
        branReading: "Reading Bran’s settings… macOS may ask to unlock its Keychain items.",
        branMissing: "Bran’s backup settings were not found on this Mac.",
        branFailed: "Bran’s settings could not be read.",
        branProfileName: "From Bran",
        branMagicDNS: "Its MagicDNS name replaces the address %@: an address change will break nothing.",
        branDetails: "Bucket %@ · identity %@",
        branRules: "%d rules become presets, %d stay custom rules",
        branRhythm: "Bran backed up every %d h; the Automatic rhythm is offered instead.",
        branSecretsRead: "Password and key read from Bran’s Keychain",
        branSecretsMissing: "Secrets not read: type them in the next steps",
        branStillRuns: "Bran also backs up this Mac",
        branStillRunsCaption: "Two engines on one repository get in each other’s way. Bran stays installed.",
        stopBran: "Stop Bran",
        stopBranTitle: "Stop Bran’s backup?",
        stopBranMessage: "Its background agent is stopped for this session. Nothing is uninstalled or deleted.",
        branStopped: "Stopped",
        branStopFailed: "Bran’s agent could not be stopped.",
        serverHeader: "Server",
        serverType: "Type",
        serverGenericS3: "Other S3",
        serverAddress: "Address",
        serverAddressPrompt: "minio.tailnet.ts.net or s3.eu-west-3.amazonaws.com",
        serverPort: "Port",
        serverTLS: "Encrypt with HTTPS",
        serverTLSCaption: "Needed over the internet.",
        serverTLSTailscale: "Tailscale already encrypts: plain HTTP is fine inside it.",
        tailscaleSuggestions: "On your tailnet",
        tailscalePeerLabel: "Use %@",
        storageHeader: "Storage",
        serverBucket: "Bucket",
        serverRegion: "Region",
        serverPrefix: "Prefix",
        keysHeader: "S3 keys",
        serverAccessKey: "Access key ID",
        serverSecretKey: "Secret key",
        keysFooter: "Saved in this Mac’s Keychain, only after a successful test.",
        issueAddress: "An address such as server.name, with its port if needed.",
        issuePort: "A port between 1 and 65535.",
        issueBucket: "3 to 63 lower-case letters, digits, dots or dashes.",
        issueRegion: "A region such as us-east-1.",
        issueAccessKey: "The access key ID is needed.",
        issueSecretKey: "The secret key is needed.",
        repositoryHeader: "Repository password",
        repositoryPassword: "Password",
        repositoryPasswordCaption: "The one chosen when the repository was created.",
        repositoryPasswordNew: "Choose it well and keep it: without it nobody can read the backup, not even you.",
        testHeader: "Test",
        testConnection: "Test the Connection",
        testSkipped: "not tested",
        testEngineMissing: "Engine not installed",
        testTailscaleOff: "Tailscale is off",
        testPeerOnline: "online",
        testPeerOffline: "offline",
        testPeerMissing: "not in the tailnet",
        testNetworkOK: "connected",
        testTimeout: "no answer",
        testServerUnreachable: "The server does not answer at this address.",
        testAuthentication: "Password or keys refused.",
        thisRepository: "This repository",
        uniqueIDLabel: "Unique ID",
        machinesFound: "Macs already in it",
        machinesNone: "No backup in it yet.",
        snapshotOne: "1 backup",
        snapshotFew: "%d backups",
        snapshotMany: "%d backups",
        lockCaption: "Locks this ID: another repository behind the same address will be refused.",
        lockButton: "It’s My Repository",
        locked: "Locked on this repository",
        lockedExpected: "The repository the profile expects",
        otherMacHeader: "Another Mac’s repository",
        otherMacBrowse: "Browse and restore only",
        otherMacBrowseCaption: "Read only: nothing is written to the repository.",
        otherMacTakeOver: "Continue its backups on this Mac",
        otherMacTakeOverCaption: "This Mac takes over its identity, for one continuous history.",
        identityHeader: "Identity",
        identityContinue: "Continue %@",
        identityNew: "A new identity for this Mac",
        identityUser: "User",
        identityHost: "Computer",
        identityFooter: "Continuing keeps one history: the next backup only sends what changed.",
        identityStillUsed: "%@ backed up %@: two Macs under one identity mix their histories.",
        doneTitle: "This Mac is connected",
        doneCaption: "The first backup starts on its own. Now, the recovery kit.",
        doneBrowseTitle: "Opened in the Backups window",
        doneBrowseCaption: "Browse and restore its files there. This Mac’s own settings did not change.",
        keychainFailed: "The Keychain refused the secrets: nothing was saved."
    )
}

// MARK: - French

extension ForkMacBackupSettingsStrings {
    static let fr = ForkMacBackupSettingsStrings(
        done: "OK",
        cancel: "Annuler",
        apply: "Appliquer",
        back: "Retour",
        continueAction: "Continuer",
        finish: "Terminer",
        later: "Plus tard",
        tryAgain: "Réessayer",
        allow: "Autoriser…",
        connect: "Connecter…",
        optional: "Facultatif",
        openSystemSettings: "Ouvrir Réglages Système",
        showInFinder: "Afficher dans le Finder",
        fileNotSaved: "Le fichier n’a pas pu être enregistré.",
        folderMissing: "Ce dossier n’existe pas encore.",
        andMore: "et %d autres",
        savedOnThisMac: "Enregistré sur ce Mac",
        engineUnavailable: "Le moteur de sauvegarde n’est pas encore disponible.",
        latencyMs: "%d\u{00A0}ms",
        minutesValue: "%d\u{00A0}min",
        secondsValue: "%d\u{00A0}s",
        megabytesPerSecond: "%d\u{00A0}Mo/s",
        duration: "Durée",
        homeFolder: "Dossier personnel",
        folderOne: "1 dossier",
        folderFew: "%d dossiers",
        folderMany: "%d dossiers",
        exclusionOne: "1 exclusion",
        exclusionFew: "%d exclusions",
        exclusionMany: "%d exclusions",
        contentTitle: "Contenu",
        rhythmTitle: "Rythme",
        kitTitle: "Kit de récupération",
        optionsTitle: "Options",
        optionsSummary: "vérifications, notifications…",
        kitNeedsConnection: "Après la connexion d’un dépôt",
        kitMissing: "Pas encore créé",
        kitUpToDate: "À jour · créé le %@",
        kitStaleChanged: "À refaire\u{00A0}: la connexion a changé",
        kitStaleOld: "À vérifier\u{00A0}: créé le %@",
        nextAround: "Prochaine vers %@",
        bannerNodeDown: "%@ injoignable",
        editConnection: "Modifier la connexion…",
        updatePassword: "Mettre à jour le mot de passe…",
        reinstallEngine: "Réinstaller le moteur",
        chainTitle: "Ma chaîne",
        explainDirect: "Ce Mac chiffre tout avant l’envoi, puis l’envoie directement à %@.",
        explainTailscale: "Ce Mac chiffre tout, puis l’envoie par Tailscale à %@.",
        explainTailscaleStorage: "Ce Mac chiffre tout, l’envoie par Tailscale à %@, qui range les blocs sur %@.",
        nodeDetailHint: "Affiche le détail de cette étape",
        detailAddress: "Adresse",
        detailObservedIPs: "Adresses vues",
        detailLastCheck: "Dernière mesure",
        detailFree: "Libre",
        detailUniqueID: "Identifiant",
        detailProbe: "Sonde",
        detailNotProbed: "Dessinée, jamais sondée",
        beyondBreak: "Impossible à vérifier tant qu’une étape avant elle est coupée.",
        aboutMac: "Lit vos fichiers, les chiffre et n’envoie que ce qui a changé.",
        aboutNetwork: "La connexion Wi-Fi ou Ethernet de ce Mac.",
        aboutTailscale: "Un tunnel privé et chiffré jusqu’au serveur, où que vous soyez.",
        aboutName: "Le nom du serveur, traduit en adresse.",
        aboutS3: "Reçoit les blocs chiffrés par S3.",
        aboutRepository: "Le dépôt Kopia, reconnu par son identifiant unique.",
        aboutProxmox: "La machine qui fait tourner le serveur.",
        aboutNAS: "Garde les blocs sur ses disques.",
        aboutCloud: "Un stockage chez un fournisseur.",
        remedyMac: "Terminez les étapes de la mise en route sur cette page.",
        remedyNetwork: "Connectez ce Mac à un réseau.",
        remedyTailscale: "Ouvrez Tailscale, vérifiez qu’il est connecté et que le serveur est en ligne.",
        remedyName: "Le nom ne mène plus au serveur\u{00A0}: vérifiez l’adresse dans la connexion.",
        remedyS3: "Vérifiez que le serveur est allumé et que son service S3 tourne.",
        remedyRepository: "Vérifiez le mot de passe et les clés, ou qu’il s’agit bien du bon dépôt.",
        remedyProxmox: "Vérifiez que la machine et le conteneur du serveur tournent.",
        remedyNAS: "Vérifiez que le NAS est allumé et que son partage est monté.",
        remedyCloud: "Consultez la page d’état du fournisseur.",
        profilesMenu: "Profils",
        profilesKnown: "Sur ce Mac",
        profileImport: "Importer un profil…",
        profileExport: "Exporter ce profil…",
        profileCreate: "Créer un profil…",
        profileNone: "Ne plus utiliser de profil",
        profileNoneLabel: "Sans profil",
        profileNamed: "Profil «\u{00A0}%@\u{00A0}»",
        profileUnreadable: "Ce fichier n’est pas un profil de sauvegarde.",
        profileDefaultName: "Mon serveur (%@)",
        setupTitle: "Protégez ce Mac",
        setupProgress: "%d étapes sur %d faites",
        setupSwitchHint: "Activez la sauvegarde ci-dessus pour qu’elle démarre une fois ces étapes faites.",
        stepDone: "Fait",
        stepToDo: "À faire",
        stepEngine: "Installer le moteur de sauvegarde",
        stepDiskAccess: "Autoriser l’Accès complet au disque",
        stepBackground: "Autoriser l’exécution en arrière-plan",
        stepRepository: "Connecter votre dépôt",
        stepKit: "Créer le kit de récupération",
        stepEngineCaption: "Kopia 0.23.1, vérifié par son empreinte avant usage.",
        stepDiskAccessCaption: "Dans Réglages Système › Confidentialité et sécurité › Accès complet au disque, activez «\u{00A0}%@\u{00A0}», puis relancez-le.",
        stepBackgroundCaption: "Pour sauvegarder même quand l’app est fermée.",
        stepBackgroundAfterSwitch: "Demandé à l’activation de la sauvegarde.",
        stepBackgroundFailed: "macOS a refusé d’enregistrer l’agent d’arrière-plan.",
        stepRepositoryCaption: "Votre serveur MinIO ou S3, testé avant d’enregistrer quoi que ce soit.",
        stepKitCaption: "Pour retrouver vos sauvegardes sans ce Mac.",
        engineInstall: "Installer",
        engineDownloading: "Téléchargement… %@",
        engineVerifying: "Vérification du téléchargement…",
        engineFailed: "L’installation a échoué.",
        engineNotInstalled: "Non installé",
        relaunch: "Relancer",
        kitCreate: "Créer le kit…",
        contentSubtitle: "Ce qui part dans la sauvegarde, avec la taille réelle de chaque partie.",
        sourcesTitle: "Dossiers sauvegardés",
        sourceAdd: "Ajouter un dossier…",
        sourceRemove: "Retirer ce dossier",
        sourceDropHint: "ou glissez des dossiers ici",
        previewTitle: "Aperçu",
        previewRun: "Mesurer",
        previewRefresh: "Mesurer à nouveau",
        previewNever: "Mesurez ce qui serait gardé et laissé de côté, avec la place réellement occupée.",
        previewScanning: "Mesure… %@ fichiers",
        previewKept: "%@ gardés",
        previewLeftOut: "%@ laissés de côté",
        previewMeasured: "Mesuré %@ · %@ fichiers gardés",
        previewFooter: "Tailles réelles sur le disque, jamais la taille annoncée par un fichier.",
        presetsTitle: "Laissé de côté",
        presetsFooter: "Coché = laissé hors de la sauvegarde. Rien n’est supprimé de votre Mac.",
        presetTrash: "Corbeille",
        presetTrashCaption: "Ce que vous avez déjà jeté.",
        presetCaches: "Caches de macOS",
        presetCachesCaption: "Les apps les reconstruisent toutes seules.",
        presetDocker: "Docker Desktop",
        presetDockerCaption: "Son disque virtuel. Vos dossiers de projets restent sauvegardés.",
        presetAppleContainer: "Conteneurs Apple",
        presetAppleContainerCaption: "Les images disque des conteneurs Linux (comme kali).",
        presetSparse: "Disques virtuels creux",
        presetVirtualMachines: "Machines virtuelles",
        presetVirtualMachinesCaption: "Parallels, UTM… Une VM allumée peut être copiée de façon incohérente.",
        presetDevFolders: "Dossiers de dev régénérables",
        presetDevFoldersCaption: "node_modules, .venv, DerivedData… vos outils les recréent.",
        presetGenericBuild: "Dossiers nommés build, dist, out…",
        presetGenericBuildCaption: "Peuvent contenir du vrai travail\u{00A0}: regardez les chemins avant de cocher.",
        presetCloudStorage: "Autres nuages",
        presetCloudStorageCaption: "Dropbox, Google Drive… Leur fournisseur en garde une copie, pas cet historique.",
        presetCacheTag: "Dossiers marqués comme cache",
        presetCacheTagCaption: "Ceux qui contiennent un fichier CACHEDIR.TAG.",
        presetLogs: "Fichiers journaux",
        presetLogsCaption: "Les fichiers en .log.",
        presetSecrets: "Clés privées",
        presetSecretsCaption: ".ssh, .gnupg et trousseaux.",
        secretsIncluded: "Vos clés privées sont dans la sauvegarde, chiffrées sur ce Mac avant l’envoi.",
        vmWarning: "Éteignez vos machines virtuelles avant une sauvegarde pour une copie cohérente.",
        matchOne: "1 correspondance",
        matchFew: "%d correspondances",
        matchMany: "%d correspondances",
        sparseTitle: "Disques virtuels creux",
        sparseExplain: "Docker, les conteneurs et tout fichier de 10\u{00A0}Go ou plus écrit à moins de moitié\u{00A0}: ils annoncent bien plus qu’ils ne contiennent. Laissés de côté, jamais supprimés ni redimensionnés.",
        sparseExplainMeasured: "%@ annonce %@ mais n’occupe que %@ sur le disque\u{00A0}: il est laissé de côté, jamais supprimé ni redimensionné.",
        sparseSizes: "annonce %@ · occupe %@",
        iCloudHeader: "iCloud Drive",
        iCloudTitle: "Fichiers seulement dans iCloud",
        iCloudModeLocal: "Sauvegarder les fichiers présents sur ce Mac",
        iCloudModeMaterialize: "Tout télécharger avant",
        iCloudModeExclude: "Laisser iCloud Drive de côté",
        iCloudCaptionLocal: "Les fichiers restés dans iCloud sont listés à part et ne rendent pas la sauvegarde partielle.",
        iCloudCaptionMaterialize: "Les télécharge avant chaque sauvegarde\u{00A0}: cela prend de la place sur ce Mac.",
        iCloudCaptionExclude: "iCloud en garde sa copie, mais pas cet historique.",
        iCloudCloudOnly: "%@ fichiers seulement dans iCloud (%@)",
        rulesTitle: "Règles personnalisées",
        ruleOne: "1 règle",
        ruleFew: "%d règles",
        ruleMany: "%d règles",
        ruleField: "Nouvelle règle",
        rulePlaceholder: "ex. Movies/Exports/",
        ruleAdd: "Ajouter",
        ruleRemove: "Retirer cette règle",
        ruleNoMatch: "Ne touche rien à la dernière mesure",
        rulesSyntax: "Une règle par ligne, comme .gitignore\u{00A0}: «\u{00A0}nom\u{00A0}» partout, «\u{00A0}/nom\u{00A0}» à la racine du dossier, «\u{00A0}nom/\u{00A0}» seulement les dossiers, * et ? comme jokers.",
        ruleExplainAnywhereFolder: "Laisse de côté tout dossier nommé «\u{00A0}%@\u{00A0}», où qu’il soit.",
        ruleExplainAnywhere: "Laisse de côté tout fichier ou dossier nommé «\u{00A0}%@\u{00A0}», où qu’il soit.",
        ruleExplainAnchored: "Laisse de côté «\u{00A0}%@\u{00A0}» à partir de la racine de chaque dossier sauvegardé.",
        rhythmSubtitle: "Quand la sauvegarde part, et ce qu’elle attend.",
        scheduleAuto: "Automatique",
        scheduleInterval: "Intervalle",
        scheduleTimes: "Heures fixes",
        scheduleBoth: "Les deux",
        autoExplain: "Sauvegarde dès que assez de choses ont changé, à au moins une heure d’écart et au plus 4\u{00A0}h sur secteur (8 sur batterie). Calé sur ce que coûte vraiment une sauvegarde sur ce Mac.",
        autoNotMeasured: "Mesuré après les premières sauvegardes.",
        measuredOne: "Mesuré sur 1 sauvegarde",
        measuredFew: "Mesuré sur %d sauvegardes",
        measuredMany: "Mesuré sur %d sauvegardes",
        every: "Toutes les",
        atTimes: "À",
        timeAdd: "Ajouter une heure",
        timeRemove: "Retirer cette heure",
        catchUp: "Rattrapage au réveil",
        catchUpCaption: "Une sauvegarde manquée part ce délai après le réveil ou l’ouverture de session.",
        powerHeader: "Alimentation",
        powerTitle: "Sauvegarder",
        powerAlways: "Toujours",
        powerAC: "Sur secteur seulement",
        powerThreshold: "Sur batterie au-dessus d’un seuil",
        powerMinimum: "Batterie au moins",
        forceAfter: "Quand même après",
        lowPowerWaits: "Attendre pendant le mode Économie d’énergie",
        keepAwake: "Garder le Mac éveillé",
        keepAwakeNever: "Jamais",
        keepAwakeAC: "Sur secteur",
        keepAwakeAlways: "Toujours",
        keepAwakeCaption: "Empêche la veille d’inactivité pendant une sauvegarde. Le Mac doit rester ouvert et allumé.",
        conditionsHeader: "Conditions",
        limitedNetwork: "Sur un réseau limité",
        limitedNetworkCaption: "Partage de connexion ou réseau marqué comme limité.",
        conditionWait: "Attendre",
        conditionSlow: "Ralentir",
        conditionIgnore: "Sauvegarder quand même",
        meetingTitle: "Pendant une réunion enregistrée",
        meetingPause: "Mettre en pause",
        meetingNothing: "Rien",
        earlyTitle: "Sauvegarder plus tôt après beaucoup de changements",
        earlyCaption: "Quand %d fichiers changent dans Documents ou Bureau, sans attendre le prochain créneau.",
        earlyThreshold: "Fichiers modifiés",
        speedHeader: "Débit",
        slowLimit: "Limite de «\u{00A0}Ralentir\u{00A0}»",
        slowLimitCaption: "Utilisée pendant les réunions, sur un réseau limité et par le bouton Ralentir de l’île.",
        windowTitle: "Plus lent sur une plage horaire",
        windowFrom: "De",
        windowTo: "à",
        windowLimit: "Limite",
        priorityTitle: "Priorité",
        priorityLow: "Basse (le Mac reste fluide)",
        priorityNormal: "Normale",
        priorityCaption: "Une sauvegarde lancée à la main part toujours en priorité normale.",
        optionsTabRetention: "Conservation",
        optionsTabVerifications: "Vérifications",
        optionsTabNotifications: "Notifications",
        optionsTabAdvanced: "Avancé",
        retentionHeader: "Ce qui est gardé",
        retentionBalanced: "Équilibrée",
        retentionEconomical: "Économe",
        retentionLong: "Longue",
        retentionCustom: "Personnalisée",
        latestOne: "1 dernière",
        latestFew: "%d dernières",
        latestMany: "%d dernières",
        keepTheLatestOne: "la dernière",
        keepTheLatestFew: "les %d dernières",
        keepTheLatestMany: "les %d dernières",
        retentionHourly: "une par heure pendant %@",
        retentionDaily: "une par jour pendant %@",
        retentionWeekly: "une par semaine pendant %@",
        retentionMonthly: "une par mois pendant %@",
        retentionAnnual: "une par an pendant %@",
        retentionLead: "Garde %@.",
        retentionTail: "Ce ne sont pas des copies en plus\u{00A0}: une même sauvegarde peut compter pour plusieurs règles.",
        retentionNothing: "Ne garde rien\u{00A0}: toutes les sauvegardes seraient supprimées.",
        keepLatest: "Dernières",
        keepHourly: "Par heure",
        keepDaily: "Par jour",
        keepWeekly: "Par semaine",
        keepMonthly: "Par mois",
        keepAnnual: "Par an",
        retentionPreviewHeader: "Avant d’appliquer",
        retentionPreviewCaption: "Voyez quelles sauvegardes ce réglage supprimerait.",
        retentionPreviewButton: "Afficher",
        retentionLoading: "Lecture des sauvegardes…",
        retentionKeepsAll: "Toutes gardées · %d",
        retentionWouldDelete: "En supprimerait %d sur %d",
        retentionConfirmTitle: "Supprimer ces sauvegardes\u{00A0}?",
        retentionConfirmMessage: "%d sauvegardes seront supprimées à la fin de la prochaine sauvegarde. La place revient après l’entretien complet.",
        maintenanceHeader: "Entretien",
        maintenanceLast: "Dernier entretien complet",
        maintenanceFooter: "La place ne revient qu’après l’entretien complet, environ deux jours après la suppression d’une sauvegarde. Il tourne la nuit, sur secteur.",
        repositorySizeLabel: "Dépôt sur le serveur",
        outcomeComplete: "fait",
        outcomePartial: "partiel",
        outcomeFailed: "échoué",
        outcomeCanceled: "annulé",
        outcomeNothing: "rien à faire",
        verifyPlanHeader: "Contrôles planifiés",
        verifyPlanFooter: "Chaque niveau prouve un peu plus. Ils tournent en arrière-plan, sur secteur.",
        verifyReferences: "Tous les blocs sont là",
        verifyReferencesCaption: "Vérifie que le contenu de chaque sauvegarde existe sur le serveur.",
        verifyContent: "Échantillon relu",
        verifyContentCaption: "Télécharge et déchiffre 1\u{00A0}% des fichiers\u{00A0}: environ 98\u{00A0}% couverts en un an.",
        verifyRestore: "Restauration test",
        verifyRestoreCaption: "Restaure 50 fichiers au hasard et les compare octet par octet.",
        periodNever: "Jamais",
        periodDaily: "Chaque jour",
        periodWeekly: "Chaque semaine",
        periodMonthly: "Chaque mois",
        periodEvery: "Toutes les %@",
        verifyLastOK: "Réussie %@",
        verifyLastFailed: "Échouée %@",
        verifyNever: "Jamais lancée",
        verifyNowHeader: "Maintenant",
        verifyNow: "Vérifier maintenant",
        verifyFull: "Tout (long)",
        verifyFullCaption: "«\u{00A0}Tout\u{00A0}» relit le dépôt entier\u{00A0}: des heures pour un gros dépôt.",
        openVerifications: "Ouvrir l’historique des vérifications",
        notifyHeader: "Ce qui vous prévient",
        notifyEvent: "Événement",
        notifyIsland: "Île",
        notifySystem: "Notification",
        notifyNothing: "Rien",
        eventStart: "Début d’une sauvegarde",
        eventComplete: "Sauvegarde terminée",
        eventPartial: "Sauvegarde partielle",
        eventFailure: "Sauvegarde échouée",
        eventLate: "Pas de sauvegarde depuis trop longtemps",
        eventChainBroken: "Chaîne coupée",
        eventChainRestored: "Chaîne rétablie",
        eventNASLow: "Stockage presque plein",
        eventVerifyFailed: "Vérification échouée",
        eventRestoreDone: "Restauration terminée",
        eventKitStale: "Kit à refaire",
        notifyFooter: "Par défaut, rien ne sort de la section de l’île, sauf la notice de fin de sauvegarde.",
        thresholdsHeader: "Seuils",
        lateThreshold: "En retard après",
        nasThreshold: "Stockage libre sous",
        notifyPermissionHeader: "Notifications système",
        notifyGranted: "Autorisées",
        notifyDenied: "Désactivées dans Réglages Système",
        notifyUndetermined: "Pas encore demandées",
        engineHeader: "Moteur",
        engineVersion: "Version",
        cacheSize: "Cache local",
        timeoutsHeader: "Délais",
        watchdog: "Sans progression pendant",
        repositoryTimeout: "Ouverture du dépôt",
        probeTimeout: "Sonde d’une étape",
        toolsHeader: "Outils",
        openLogs: "Afficher les journaux",
        exportDiagnostic: "Exporter un diagnostic…",
        openTerminal: "Ouvrir un Terminal configuré",
        openTerminalCaption: "Kopia prêt pour ce dépôt\u{00A0}; il demande le mot de passe, aucun secret n’est écrit.",
        terminalPasswordPrompt: "Mot de passe du dépôt\u{00A0}:",
        terminalSecretPrompt: "Clé secrète S3\u{00A0}:",
        terminalBanner: "Kopia est prêt pour ce dépôt. Essayez\u{00A0}: kopia snapshot list",
        connectionHeader: "Connexion",
        importBran: "Importer depuis Bran…",
        importBranCaption: "Lit les réglages de Bran au clic, et demande avant de l’arrêter.",
        disconnect: "Déconnecter ce Mac",
        disconnectCaption: "Oublie le dépôt et ses secrets sur ce Mac. Rien n’est effacé sur le serveur.",
        disconnectConfirmTitle: "Déconnecter ce Mac\u{00A0}?",
        kitSubtitle: "Tout ce qu’il faut pour retrouver vos sauvegardes sans ce Mac.",
        kitWhy: "Sans ce Mac, il faut l’adresse, le mot de passe et l’identifiant du dépôt. Le kit les réunit.",
        kitStaleChangedCaption: "L’adresse, les clés ou l’identité ont changé depuis\u{00A0}: l’ancien kit ne mènerait nulle part.",
        kitCreateHeader: "Créer",
        kitIncludeSecrets: "Inclure les secrets, scellés par une phrase de passe",
        kitIncludeSecretsCaption: "Seulement dans le fichier. Gardez la phrase ailleurs\u{00A0}: sans elle, ils ne s’ouvrent pas.",
        passphrase: "Phrase de passe",
        passphraseConfirm: "Confirmer",
        passphraseTooShort: "Au moins 8 caractères.",
        passphraseMismatch: "Les deux ne correspondent pas.",
        passphraseWrong: "Mauvaise phrase de passe, ou fichier abîmé.",
        kitSavePDF: "Enregistrer le PDF…",
        kitPrint: "Imprimer…",
        kitSaveFile: "Enregistrer le fichier kit…",
        kitCopyFields: "Copier les champs pour un gestionnaire de mots de passe",
        kitCopied: "Copié, sans les secrets.",
        kitSaved: "Enregistré\u{00A0}: %@",
        kitInsideBackup: "Ce dossier est lui-même sauvegardé\u{00A0}: gardez une autre copie sur une clé USB ou dans un gestionnaire de mots de passe.",
        kitSecretsUnavailable: "Les secrets n’ont pas pu être lus dans le Trousseau.",
        kitWhereFooter: "Gardez-le hors de ce Mac\u{00A0}: une clé USB, une feuille imprimée, un gestionnaire de mots de passe.",
        kitReminderHeader: "Rappel",
        kitNextReminder: "Prochain rappel",
        kitChecked: "J’ai vérifié que je peux ouvrir mon kit",
        kitReminderFooter: "Tous les 180 jours, et à chaque changement d’adresse ou de mot de passe.",
        kitOtherHeader: "Depuis un autre Mac",
        kitOpenOther: "Ouvrir le kit d’un autre Mac…",
        kitOpenOtherCaption: "Pour parcourir et restaurer ses sauvegardes, en lecture seule.",
        kitUnreadable: "Ce fichier n’est pas un kit de récupération.",
        kitFoundFor: "Kit de %@, créé le %@",
        kitFileName: "Kit de récupération",
        kitFieldType: "Type",
        kitFieldEndpoint: "Adresse",
        kitFieldObserved: "Adresses vues",
        kitFieldBucket: "Bucket",
        kitFieldPrefix: "Préfixe",
        kitFieldRegion: "Région",
        kitFieldAccessKey: "Clé d’accès S3",
        kitFieldUniqueID: "Identifiant du dépôt",
        kitFieldIdentity: "Identité de ce Mac",
        kitFieldKopia: "Version de Kopia",
        kitFieldPassword: "Mot de passe du dépôt",
        kitFieldSecretKey: "Clé secrète S3",
        kitPDFSubtitle: "Sauvegarde du Mac · %@ · %@",
        kitPDFRepository: "Votre dépôt",
        kitPDFSecrets: "Il faut aussi",
        kitPDFSecretsNote: "Jamais imprimés ici. Écrivez-les à la main seulement si cette page reste en lieu sûr.",
        kitPDFWithout: "Sans %@",
        kitStepDownload: "Télécharger Kopia et vérifier son empreinte",
        kitStepConnect: "Se connecter en lecture seule (le mot de passe est demandé)",
        kitStepList: "Lister les sauvegardes",
        kitStepRestore: "En restaurer une dans un dossier",
        kitPDFChecksum: "SHA-256 attendu\u{00A0}: %@",
        kitPDFWith: "Avec %@ sur un autre Mac",
        kitPDFWithSteps: "Installez %@, activez la Sauvegarde du Mac, choisissez «\u{00A0}Ouvrir le dépôt d’un autre Mac\u{00A0}» et ouvrez le fichier kit. Vous parcourez et restaurez sans toucher aux sauvegardes de ce Mac.",
        kitPDFKeepAway: "Gardez cette page loin de ce Mac.",
        kitPDFFingerprint: "Kit %@",
        kitRestoredFolder: "Restauré",
        wizardTitle: "Connecter un dépôt",
        wizardStepStart: "Départ",
        wizardStepServer: "Serveur",
        wizardStepRepository: "Dépôt",
        wizardStepIdentity: "Ce Mac",
        wizardStepKit: "Kit",
        wizardCaptionStart: "D’où partez-vous\u{00A0}?",
        wizardCaptionServer: "Où vos sauvegardes sont rangées.",
        wizardCaptionRepository: "Le mot de passe, puis un test de chaque étape.",
        wizardCaptionIdentity: "Qui est ce Mac dans le dépôt.",
        wizardCaptionKit: "Connecté. Encore une chose.",
        startExisting: "J’ai déjà un dépôt",
        startProfile: "Importer un profil",
        startProfileCaption: "Un fichier .swishsaint-backup-profile remplit tout sauf les secrets.",
        startBran: "Importer depuis Bran",
        startBranCaption: "Reprend la sauvegarde de Bran sur ce Mac\u{00A0}: même dépôt, même historique.",
        startManual: "Saisir mon serveur",
        startManualCaption: "MinIO, Backblaze B2, Wasabi, AWS… n’importe quel S3.",
        startOther: "Autre",
        startNew: "Nouveau dépôt",
        startNewCaption: "Un bucket vide devient un dépôt chiffré.",
        startOtherMac: "Ouvrir le dépôt d’un autre Mac",
        startOtherMacCaption: "Avec son kit, en lecture seule, pour restaurer ses fichiers ici.",
        branReading: "Lecture des réglages de Bran… macOS peut demander d’ouvrir ses éléments du Trousseau.",
        branMissing: "Les réglages de sauvegarde de Bran sont introuvables sur ce Mac.",
        branFailed: "Les réglages de Bran n’ont pas pu être lus.",
        branProfileName: "Depuis Bran",
        branMagicDNS: "Son nom MagicDNS remplace l’adresse %@\u{00A0}: un changement d’adresse ne cassera rien.",
        branDetails: "Bucket %@ · identité %@",
        branRules: "%d règles deviennent des préréglages, %d restent personnalisées",
        branRhythm: "Bran sauvegardait toutes les %d\u{00A0}h\u{00A0}; le rythme Automatique est proposé à la place.",
        branSecretsRead: "Mot de passe et clé lus dans le Trousseau de Bran",
        branSecretsMissing: "Secrets non lus\u{00A0}: saisissez-les aux étapes suivantes",
        branStillRuns: "Bran sauvegarde aussi ce Mac",
        branStillRunsCaption: "Deux moteurs sur un même dépôt se gênent. Bran reste installé.",
        stopBran: "Arrêter Bran",
        stopBranTitle: "Arrêter la sauvegarde de Bran\u{00A0}?",
        stopBranMessage: "Son agent d’arrière-plan est arrêté pour cette session. Rien n’est désinstallé ni supprimé.",
        branStopped: "Arrêté",
        branStopFailed: "L’agent de Bran n’a pas pu être arrêté.",
        serverHeader: "Serveur",
        serverType: "Type",
        serverGenericS3: "Autre S3",
        serverAddress: "Adresse",
        serverAddressPrompt: "minio.tailnet.ts.net ou s3.eu-west-3.amazonaws.com",
        serverPort: "Port",
        serverTLS: "Chiffrer avec HTTPS",
        serverTLSCaption: "Indispensable par internet.",
        serverTLSTailscale: "Tailscale chiffre déjà\u{00A0}: HTTP suffit à l’intérieur.",
        tailscaleSuggestions: "Sur votre tailnet",
        tailscalePeerLabel: "Utiliser %@",
        storageHeader: "Stockage",
        serverBucket: "Bucket",
        serverRegion: "Région",
        serverPrefix: "Préfixe",
        keysHeader: "Clés S3",
        serverAccessKey: "Identifiant de clé",
        serverSecretKey: "Clé secrète",
        keysFooter: "Enregistrée dans le Trousseau de ce Mac, seulement après un test réussi.",
        issueAddress: "Une adresse comme nom.du.serveur, avec son port s’il le faut.",
        issuePort: "Un port entre 1 et 65535.",
        issueBucket: "3 à 63 minuscules, chiffres, points ou tirets.",
        issueRegion: "Une région comme us-east-1.",
        issueAccessKey: "L’identifiant de clé est nécessaire.",
        issueSecretKey: "La clé secrète est nécessaire.",
        repositoryHeader: "Mot de passe du dépôt",
        repositoryPassword: "Mot de passe",
        repositoryPasswordCaption: "Celui choisi à la création du dépôt.",
        repositoryPasswordNew: "Choisissez-le bien et gardez-le\u{00A0}: sans lui, personne ne peut lire la sauvegarde, pas même vous.",
        testHeader: "Test",
        testConnection: "Tester la connexion",
        testSkipped: "non testé",
        testEngineMissing: "Moteur non installé",
        testTailscaleOff: "Tailscale est éteint",
        testPeerOnline: "en ligne",
        testPeerOffline: "hors ligne",
        testPeerMissing: "absent du tailnet",
        testNetworkOK: "connecté",
        testTimeout: "pas de réponse",
        testServerUnreachable: "Le serveur ne répond pas à cette adresse.",
        testAuthentication: "Mot de passe ou clés refusés.",
        thisRepository: "Ce dépôt",
        uniqueIDLabel: "Identifiant unique",
        machinesFound: "Mac déjà présents",
        machinesNone: "Aucune sauvegarde dedans pour l’instant.",
        snapshotOne: "1 sauvegarde",
        snapshotFew: "%d sauvegardes",
        snapshotMany: "%d sauvegardes",
        lockCaption: "Verrouille cet identifiant\u{00A0}: un autre dépôt derrière la même adresse sera refusé.",
        lockButton: "C’est bien mon dépôt",
        locked: "Verrouillé sur ce dépôt",
        lockedExpected: "Le dépôt attendu par le profil",
        otherMacHeader: "Dépôt d’un autre Mac",
        otherMacBrowse: "Parcourir et restaurer seulement",
        otherMacBrowseCaption: "Lecture seule\u{00A0}: rien n’est écrit dans le dépôt.",
        otherMacTakeOver: "Continuer ses sauvegardes sur ce Mac",
        otherMacTakeOverCaption: "Ce Mac reprend son identité, pour un historique continu.",
        identityHeader: "Identité",
        identityContinue: "Continuer %@",
        identityNew: "Une nouvelle identité pour ce Mac",
        identityUser: "Utilisateur",
        identityHost: "Ordinateur",
        identityFooter: "Continuer garde un seul historique\u{00A0}: la prochaine sauvegarde n’envoie que ce qui a changé.",
        identityStillUsed: "%@ a sauvegardé %@\u{00A0}: deux Mac sous une même identité mélangent leurs historiques.",
        doneTitle: "Ce Mac est connecté",
        doneCaption: "La première sauvegarde partira d’elle-même. Maintenant, le kit de récupération.",
        doneBrowseTitle: "Ouvert dans la fenêtre Sauvegardes",
        doneBrowseCaption: "Parcourez et restaurez ses fichiers là-bas. Les réglages de ce Mac n’ont pas changé.",
        keychainFailed: "Le Trousseau a refusé les secrets\u{00A0}: rien n’a été enregistré."
    )
}

// Until translated: the other languages read English (temporary).
extension ForkMacBackupSettingsStrings {
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
