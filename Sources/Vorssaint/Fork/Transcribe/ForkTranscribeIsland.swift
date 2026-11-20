// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import AppKit

/// A file's end in the closed island: "Transcription done · meeting.mp3",
/// or failed. A click on it opens the page on that transcription (seam
/// `notch-notice-activate`, hook set in `ForkBootstrap`). Nothing is shown
/// while the page is in front: the line already says it.
enum ForkTranscribeIsland {
    private static var lastShown: (notice: NotchNotice, job: UUID)?

    static var isAvailable: Bool {
        let island = NotchService.shared
        return NotchSupport.routes(.capture) && island.showsSystemFeedback
            && !island.expanded && !island.dragPlaceholder && island.captureControls == nil
            && ForkDictationPresenter.shared.presentation == .hidden
    }

    /// Main thread, at a job's end.
    static func tell(_ job: ForkTranscribeJob) {
        guard UserDefaults.standard.bool(forKey: ForkDefaultsKey.transcribeNotifies), !pageInFront else { return }
        let text = ForkTranscribeStrings.strings(L10n.shared.language)
        let notice: NotchNotice
        switch job.stage {
        case .done:
            notice = NotchNotice(event: .capture, title: text.noticeDone, detail: job.name, symbol: "text.bubble")
        case .failed:
            notice = NotchNotice(event: .capture, title: text.noticeFailed, detail: job.name,
                                 symbol: "exclamationmark.bubble")
        default:
            return
        }
        guard isAvailable, NotchService.shared.show(notice) else { return }
        lastShown = (notice, job.id)
    }

    /// A click on the island's notice: true when it was ours.
    static func activate(_ notice: NotchNotice) -> Bool {
        guard let shown = lastShown, notice == shown.notice else { return false }
        ForkTranscribeQueue.shared.reading = shown.job
        ForkSettingsPages.open(.fileTranscription)
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    /// The Settings window is the key window and shows this feature's page.
    private static var pageInFront: Bool {
        guard NSApp.isActive, let window = NSApp.keyWindow else { return false }
        return ForkTranscribePageTracker.isShown && window.isVisible
    }
}

/// Whether the page is on screen, set by the page itself.
enum ForkTranscribePageTracker {
    static var isShown = false
}

/// File Transcription's rows in the Command Bar (seam
/// `command-bar-transcribe`): "Transcribe a File…" opens the file panel,
/// "Open File Transcriptions" the page. With the feature off, both answer
/// and say it needs turning on.
enum ForkTranscribeCommandBar {
    static let transcribeID = "action.forkTranscribe.file"
    static let openID = "action.forkTranscribe.open"

    static func entries() -> [CommandBarEntry] {
        let language = L10n.shared.language
        let text = ForkTranscribeStrings.strings(language)
        let area = ForkExtrasStrings.strings(language).transcribeTitle
        let keywords = [text.barKeywords, ForkTranscribeStrings.enUS.barKeywords, area,
                        ForkExtrasStrings.strings(.enUS).transcribeTitle].joined(separator: ", ")
        let enabled = ForkFeature.fileTranscription.isEnabled
        let setup: CommandBarEntry.Trouble? = enabled ? nil
            : .needsSetup(featureTitle: area, page: ForkFeature.fileTranscription.settingsPage)
        return [
            CommandBarEntry(id: transcribeID, title: text.barTranscribe, subtitle: area, keywords: keywords,
                            icon: .symbol("waveform.badge.plus"), trouble: setup,
                            run: { _ in afterBeat { chooseFiles() } }),
            CommandBarEntry(id: openID, title: text.barOpen, subtitle: area, keywords: keywords,
                            icon: .symbol("text.bubble"), trouble: setup,
                            run: { _ in afterBeat { ForkSettingsPages.open(.fileTranscription) } }),
        ]
    }

    /// The open panel, then the page with the files queued.
    static func chooseFiles() {
        NSApp.activate(ignoringOtherApps: true)
        guard let urls = ForkTranscribePanel.choose(), !urls.isEmpty else { return }
        ForkTranscribeQueue.shared.add(urls)
        ForkSettingsPages.open(.fileTranscription)
    }

    /// The Command Bar closes first: the panel then takes the keyboard.
    private static func afterBeat(_ body: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: body)
    }
}

/// "Choose Files…": audio, video and folders, several at once.
enum ForkTranscribePanel {
    static func choose() -> [URL]? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.audiovisualContent, .folder]
        return panel.runModal() == .OK ? panel.urls : nil
    }
}
