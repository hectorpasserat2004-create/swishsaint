// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import SwiftUI

/// One of Glance Focus's app lists (plan §12.6, §5.4): « Ne jamais quitter
/// ces apps », « Ne jamais activer ces apps » and the apps where panes are
/// tried. The official `AppBundleList` draws it, as for Window Layout's
/// ignored apps (the gestures' list); the list itself is the JSON array of
/// bundle ids stored under its `fork.glance.*` key, its only source.
struct ForkGlanceAppList: View {
    let key: String
    let title: String
    let caption: String
    let text: ForkGlanceSettingsStrings
    /// What the list holds before the person ever touched it.
    var fallback: [String] = []
    var changed: () -> Void = {}

    @AppStorage private var stored: String

    init(key: String, title: String, caption: String, text: ForkGlanceSettingsStrings, fallback: [String] = [],
         changed: @escaping () -> Void = {}) {
        self.key = key
        self.title = title
        self.caption = caption
        self.text = text
        self.fallback = fallback
        self.changed = changed
        _stored = AppStorage(wrappedValue: ForkGlanceDefaults.encode(fallback), key)
    }

    private var bundleIDs: [String] { ForkGlanceDefaults.decode(stored) }

    var body: some View {
        AppBundleList(title: title, caption: caption, addTitle: text.addApp, removeLabel: text.removeApp,
                      bundleIDs: bundleIDs, reachesEveryApp: true, acceptsExecutables: false,
                      onAdd: { add($0) }, onRemove: { remove($0) })
    }

    private func add(_ bundleID: String) {
        let trimmed = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !bundleIDs.contains(trimmed) else { return }
        stored = ForkGlanceDefaults.encode(bundleIDs + [trimmed])
        changed()
    }

    private func remove(_ bundleID: String) {
        guard bundleIDs.contains(bundleID) else { return }
        stored = ForkGlanceDefaults.encode(bundleIDs.filter { $0 != bundleID })
        changed()
    }
}

/// The two lists of plan §12.6.
struct ForkGlanceAppLists: View {
    let text: ForkGlanceSettingsStrings
    var changed: () -> Void = {}

    var body: some View {
        ForkGlanceAppList(key: ForkDefaultsKey.glanceNeverLeaveApps, title: text.neverLeaveTitle,
                          caption: text.neverLeaveCaption, text: text, changed: changed)
        ForkGlanceAppList(key: ForkDefaultsKey.glanceNeverFocusApps, title: text.neverFocusTitle,
                          caption: text.neverFocusCaption, text: text, changed: changed)
    }
}
