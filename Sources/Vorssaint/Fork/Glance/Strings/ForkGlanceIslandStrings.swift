// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// The words of Glance Focus's island screens that the core strings
/// (`ForkGlanceStrings`, frozen) do not hold: the section's line in the
/// Content tab, what VoiceOver reads of the activity and the map, and the
/// island's own settings (Content and Activity tabs). The states, buttons,
/// zones, modes and notices are the core's, so every screen says them alike.
///
/// Same contract as the official FeatureStrings structs: memberwise init in
/// declaration order, one static per language. Every text fits in 28
/// characters (tested). French: `\u{00A0}` before « : ; ! ? », typographic
/// apostrophes.
struct ForkGlanceIslandStrings {
    /// The section's line in the island's Content tab.
    let sectionSummary: String
    /// The closed island's activity and the tile, read aloud.
    let activityHint: String
    /// The map of the displays, read aloud.
    let mapLabel: String
    /// The mode buttons beside the camera, read aloud.
    let modes: String
    /// « Dernières bascules » before the first one.
    let historyEmpty: String
    /// Content tab: the live gaze dot on the map.
    let showLiveDot: String
    let liveDotCaption: String
    /// Content tab: the last switches (spacious island).
    let showHistory: String
    /// Activity tab.
    let closedIsland: String
    let notices: String
    let noticesCaption: String
    /// The way to the feature's page.
    let allSettings: String
    /// From the feature's page to the island's Content tab.
    let islandSettings: String

    static func strings(_ language: AppLanguage) -> ForkGlanceIslandStrings {
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

// MARK: - Languages

extension ForkGlanceIslandStrings {
    static let enUS = ForkGlanceIslandStrings(
        sectionSummary: "Keyboard follows your gaze",
        activityHint: "Opens the Glance section",
        mapLabel: "Display map",
        modes: "Glance mode",
        historyEmpty: "No recent switches",
        showLiveDot: "Show the gaze dot",
        liveDotCaption: "While the page is open",
        showHistory: "Show recent switches",
        closedIsland: "In the closed island",
        notices: "Island notices",
        noticesCaption: "A click opens the section",
        allSettings: "Glance Focus Settings…",
        islandSettings: "Island Settings…"
    )

    // A copy of the English until its translation (plan §19, package C1).
    static let ptBR = ForkGlanceIslandStrings(
        sectionSummary: "Keyboard follows your gaze",
        activityHint: "Opens the Glance section",
        mapLabel: "Display map",
        modes: "Glance mode",
        historyEmpty: "No recent switches",
        showLiveDot: "Show the gaze dot",
        liveDotCaption: "While the page is open",
        showHistory: "Show recent switches",
        closedIsland: "In the closed island",
        notices: "Island notices",
        noticesCaption: "A click opens the section",
        allSettings: "Glance Focus Settings…",
        islandSettings: "Island Settings…"
    )

    // A copy of the English until its translation (plan §19, package C1).
    static let tr = ForkGlanceIslandStrings(
        sectionSummary: "Keyboard follows your gaze",
        activityHint: "Opens the Glance section",
        mapLabel: "Display map",
        modes: "Glance mode",
        historyEmpty: "No recent switches",
        showLiveDot: "Show the gaze dot",
        liveDotCaption: "While the page is open",
        showHistory: "Show recent switches",
        closedIsland: "In the closed island",
        notices: "Island notices",
        noticesCaption: "A click opens the section",
        allSettings: "Glance Focus Settings…",
        islandSettings: "Island Settings…"
    )

    // A copy of the English until its translation (plan §19, package C1).
    static let ru = ForkGlanceIslandStrings(
        sectionSummary: "Keyboard follows your gaze",
        activityHint: "Opens the Glance section",
        mapLabel: "Display map",
        modes: "Glance mode",
        historyEmpty: "No recent switches",
        showLiveDot: "Show the gaze dot",
        liveDotCaption: "While the page is open",
        showHistory: "Show recent switches",
        closedIsland: "In the closed island",
        notices: "Island notices",
        noticesCaption: "A click opens the section",
        allSettings: "Glance Focus Settings…",
        islandSettings: "Island Settings…"
    )

    // A copy of the English until its translation (plan §19, package C1).
    static let es = ForkGlanceIslandStrings(
        sectionSummary: "Keyboard follows your gaze",
        activityHint: "Opens the Glance section",
        mapLabel: "Display map",
        modes: "Glance mode",
        historyEmpty: "No recent switches",
        showLiveDot: "Show the gaze dot",
        liveDotCaption: "While the page is open",
        showHistory: "Show recent switches",
        closedIsland: "In the closed island",
        notices: "Island notices",
        noticesCaption: "A click opens the section",
        allSettings: "Glance Focus Settings…",
        islandSettings: "Island Settings…"
    )

    // A copy of the English until its translation (plan §19, package C1).
    static let sk = ForkGlanceIslandStrings(
        sectionSummary: "Keyboard follows your gaze",
        activityHint: "Opens the Glance section",
        mapLabel: "Display map",
        modes: "Glance mode",
        historyEmpty: "No recent switches",
        showLiveDot: "Show the gaze dot",
        liveDotCaption: "While the page is open",
        showHistory: "Show recent switches",
        closedIsland: "In the closed island",
        notices: "Island notices",
        noticesCaption: "A click opens the section",
        allSettings: "Glance Focus Settings…",
        islandSettings: "Island Settings…"
    )

    // A copy of the English until its translation (plan §19, package C1).
    static let de = ForkGlanceIslandStrings(
        sectionSummary: "Keyboard follows your gaze",
        activityHint: "Opens the Glance section",
        mapLabel: "Display map",
        modes: "Glance mode",
        historyEmpty: "No recent switches",
        showLiveDot: "Show the gaze dot",
        liveDotCaption: "While the page is open",
        showHistory: "Show recent switches",
        closedIsland: "In the closed island",
        notices: "Island notices",
        noticesCaption: "A click opens the section",
        allSettings: "Glance Focus Settings…",
        islandSettings: "Island Settings…"
    )

    static let fr = ForkGlanceIslandStrings(
        sectionSummary: "Le clavier suit votre regard",
        activityHint: "Ouvre la section Regard",
        mapLabel: "Carte des écrans",
        modes: "Mode du regard",
        historyEmpty: "Aucune bascule récente",
        showLiveDot: "Afficher le point du regard",
        liveDotCaption: "Tant que la page est ouverte",
        showHistory: "Afficher les bascules",
        closedIsland: "Dans l’île fermée",
        notices: "Notices de l’île",
        noticesCaption: "Un clic ouvre la section",
        allSettings: "Réglages du Focus au regard…",
        islandSettings: "Réglages de l’île…"
    )

    // A copy of the English until its translation (plan §19, package C1).
    static let it = ForkGlanceIslandStrings(
        sectionSummary: "Keyboard follows your gaze",
        activityHint: "Opens the Glance section",
        mapLabel: "Display map",
        modes: "Glance mode",
        historyEmpty: "No recent switches",
        showLiveDot: "Show the gaze dot",
        liveDotCaption: "While the page is open",
        showHistory: "Show recent switches",
        closedIsland: "In the closed island",
        notices: "Island notices",
        noticesCaption: "A click opens the section",
        allSettings: "Glance Focus Settings…",
        islandSettings: "Island Settings…"
    )

    // A copy of the English until its translation (plan §19, package C1).
    static let ja = ForkGlanceIslandStrings(
        sectionSummary: "Keyboard follows your gaze",
        activityHint: "Opens the Glance section",
        mapLabel: "Display map",
        modes: "Glance mode",
        historyEmpty: "No recent switches",
        showLiveDot: "Show the gaze dot",
        liveDotCaption: "While the page is open",
        showHistory: "Show recent switches",
        closedIsland: "In the closed island",
        notices: "Island notices",
        noticesCaption: "A click opens the section",
        allSettings: "Glance Focus Settings…",
        islandSettings: "Island Settings…"
    )

    // A copy of the English until its translation (plan §19, package C1).
    static let ko = ForkGlanceIslandStrings(
        sectionSummary: "Keyboard follows your gaze",
        activityHint: "Opens the Glance section",
        mapLabel: "Display map",
        modes: "Glance mode",
        historyEmpty: "No recent switches",
        showLiveDot: "Show the gaze dot",
        liveDotCaption: "While the page is open",
        showHistory: "Show recent switches",
        closedIsland: "In the closed island",
        notices: "Island notices",
        noticesCaption: "A click opens the section",
        allSettings: "Glance Focus Settings…",
        islandSettings: "Island Settings…"
    )

    // A copy of the English until its translation (plan §19, package C1).
    static let uk = ForkGlanceIslandStrings(
        sectionSummary: "Keyboard follows your gaze",
        activityHint: "Opens the Glance section",
        mapLabel: "Display map",
        modes: "Glance mode",
        historyEmpty: "No recent switches",
        showLiveDot: "Show the gaze dot",
        liveDotCaption: "While the page is open",
        showHistory: "Show recent switches",
        closedIsland: "In the closed island",
        notices: "Island notices",
        noticesCaption: "A click opens the section",
        allSettings: "Glance Focus Settings…",
        islandSettings: "Island Settings…"
    )

    // A copy of the English until its translation (plan §19, package C1).
    static let zhHans = ForkGlanceIslandStrings(
        sectionSummary: "Keyboard follows your gaze",
        activityHint: "Opens the Glance section",
        mapLabel: "Display map",
        modes: "Glance mode",
        historyEmpty: "No recent switches",
        showLiveDot: "Show the gaze dot",
        liveDotCaption: "While the page is open",
        showHistory: "Show recent switches",
        closedIsland: "In the closed island",
        notices: "Island notices",
        noticesCaption: "A click opens the section",
        allSettings: "Glance Focus Settings…",
        islandSettings: "Island Settings…"
    )

    // A copy of the English until its translation (plan §19, package C1).
    static let zhTW = ForkGlanceIslandStrings(
        sectionSummary: "Keyboard follows your gaze",
        activityHint: "Opens the Glance section",
        mapLabel: "Display map",
        modes: "Glance mode",
        historyEmpty: "No recent switches",
        showLiveDot: "Show the gaze dot",
        liveDotCaption: "While the page is open",
        showHistory: "Show recent switches",
        closedIsland: "In the closed island",
        notices: "Island notices",
        noticesCaption: "A click opens the section",
        allSettings: "Glance Focus Settings…",
        islandSettings: "Island Settings…"
    )

    // A copy of the English until its translation (plan §19, package C1).
    static let zhHK = ForkGlanceIslandStrings(
        sectionSummary: "Keyboard follows your gaze",
        activityHint: "Opens the Glance section",
        mapLabel: "Display map",
        modes: "Glance mode",
        historyEmpty: "No recent switches",
        showLiveDot: "Show the gaze dot",
        liveDotCaption: "While the page is open",
        showHistory: "Show recent switches",
        closedIsland: "In the closed island",
        notices: "Island notices",
        noticesCaption: "A click opens the section",
        allSettings: "Glance Focus Settings…",
        islandSettings: "Island Settings…"
    )
}
