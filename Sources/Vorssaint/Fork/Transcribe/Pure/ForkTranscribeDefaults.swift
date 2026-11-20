// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// File Transcription's preference keys. Registered ones follow the person
/// (settings backup); the chosen folder and the list of jobs are this Mac's
/// own and never registered.
extension ForkDefaultsKey {
    static let transcribeEnabled = "fork.transcribe.enabled"
    /// `ForkTranscribeEngine`.
    static let transcribeEngine = "fork.transcribe.engine"
    /// `ForkTranscribeLanguage`.
    static let transcribeLanguage = "fork.transcribe.language"
    /// `ForkTranscribeOutput.kinds`: "md,txt,srt".
    static let transcribeFormats = "fork.transcribe.formats"
    /// On: the texts go into `transcribeFolder`; off: beside each file.
    static let transcribeUsesFolder = "fork.transcribe.usesFolder"
    /// The chosen folder's path. Machine state: not registered.
    static let transcribeFolder = "fork.transcribe.folder"
    /// The dictation's replacements applied to the text.
    static let transcribeReplacements = "fork.transcribe.replacements"
    /// A notice in the island when a file is done or failed.
    static let transcribeNotifies = "fork.transcribe.notifies"
}

enum ForkTranscribeDefaults {
    static let registered: [String: Any] = [
        // On: it does nothing until a file is dropped, and its page is where
        // one is dropped.
        ForkDefaultsKey.transcribeEnabled: true,
        ForkDefaultsKey.transcribeEngine: ForkTranscribeEngine.fallback.rawValue,
        ForkDefaultsKey.transcribeLanguage: ForkTranscribeLanguage.auto.rawValue,
        ForkDefaultsKey.transcribeFormats: ForkTranscribeOutput.stored(ForkTranscribeOutput.Kind.allCases),
        ForkDefaultsKey.transcribeUsesFolder: false,
        ForkDefaultsKey.transcribeReplacements: true,
        ForkDefaultsKey.transcribeNotifies: true,
    ]
}
