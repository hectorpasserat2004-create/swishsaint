// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// Adds fork pages without changing the official directory used by its tests.
enum ForkSettingsDirectory {
    static func inserting(_ sections: [(title: String, items: [SettingsDirectoryItem])],
                          mouse: [SettingsDirectoryItem],
                          utilitiesAfterCapture: [SettingsDirectoryItem],
                          utilitiesAtEnd: [SettingsDirectoryItem],
                          app: [SettingsDirectoryItem]) -> [(title: String, items: [SettingsDirectoryItem])] {
        sections.map { section in
            var items = section.items
            if let index = items.firstIndex(where: { $0.page == .switcher }) {
                items.insert(contentsOf: mouse, at: index)
            }
            if let index = items.firstIndex(where: { $0.page == .screenshot }) {
                items.insert(contentsOf: utilitiesAfterCapture, at: index + 1)
                items.append(contentsOf: utilitiesAtEnd)
            }
            if let index = items.firstIndex(where: { $0.page == .about }) {
                items.insert(contentsOf: app, at: index)
            }
            return (section.title, items)
        }
    }
}
