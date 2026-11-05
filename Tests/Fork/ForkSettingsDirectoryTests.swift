// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

enum ForkSettingsDirectoryTests {
    private static func row(_ page: SettingsPage) -> SettingsDirectoryItem {
        SettingsDirectoryItem(page: page, title: "test", icon: "test")
    }

    static func run(_ suite: TestSuite) {
        let official = [
            (title: "Windows", items: [row(.mouse), row(.switcher)]),
            (title: "Utilities", items: [row(.screenshot), row(.urlCleaner)]),
            (title: "App", items: [row(.advanced), row(.about)]),
        ]
        let result = ForkSettingsDirectory.inserting(official,
            mouse: [row(.fork("gestures")), row(.fork("glance-focus"))],
            utilitiesAfterCapture: [row(.fork("meetings"))],
            utilitiesAtEnd: [row(.fork("dictation")), row(.fork("macbackup"))],
            app: [row(.extras)])
        suite.expect(result.map(\.title) == official.map(\.title)
                        && result[0].items.map(\.page) == [.mouse, .fork("gestures"), .fork("glance-focus"), .switcher]
                        && result[1].items.map(\.page) == [.screenshot, .fork("meetings"), .urlCleaner, .fork("dictation"), .fork("macbackup")]
                        && result[2].items.map(\.page) == [.advanced, .extras, .about],
                     "sidebar and search keep every official row and insert each fork page in its original group")
        suite.expect(official[0].items.map(\.page) == [.mouse, .switcher],
                     "decorating the directory leaves the official input untouched")
        let empty = ForkSettingsDirectory.inserting([], mouse: [], utilitiesAfterCapture: [], utilitiesAtEnd: [], app: [])
        suite.expect(empty.isEmpty, "an absent official directory creates no spurious groups")
        let unrelated = [(title: "Other", items: [row(.general)])]
        let unchanged = ForkSettingsDirectory.inserting(unrelated, mouse: [row(.fork("gestures"))],
            utilitiesAfterCapture: [row(.fork("meetings"))], utilitiesAtEnd: [row(.fork("dictation"))], app: [row(.extras)])
        suite.expect(unchanged[0].items.map(\.page) == [.general], "unrelated groups receive no fork rows")
        meetingsPlacement(suite)
    }

    static func meetingsPlacement(_ suite: TestSuite) {
        let sections = [(title: "Utilities", items: [row(.screenshot), row(.urlCleaner)])]
        let result = ForkSettingsDirectory.inserting(sections, mouse: [],
            utilitiesAfterCapture: [row(.fork("meetings"))], utilitiesAtEnd: [], app: [])
        suite.expect(result[0].items.map(\.page) == [.screenshot, .fork("meetings"), .urlCleaner],
                     "the Meetings row sits right after Screen Capture in the Settings sidebar, once")
    }
}
