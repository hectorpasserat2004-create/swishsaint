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

    static let ptBR = ForkGlanceIslandStrings(
        sectionSummary: "O teclado segue o seu olhar",
        activityHint: "Abre a seção Olhar",
        mapLabel: "Mapa das telas",
        modes: "Modo do olhar",
        historyEmpty: "Nenhuma troca recente",
        showLiveDot: "Mostrar o ponto do olhar",
        liveDotCaption: "Com a página aberta",
        showHistory: "Mostrar as trocas recentes",
        closedIsland: "Na ilha fechada",
        notices: "Avisos da ilha",
        noticesCaption: "Um clique abre a seção",
        allSettings: "Ajustes do Foco pelo olhar…",
        islandSettings: "Ajustes da ilha…"
    )

    static let tr = ForkGlanceIslandStrings(
        sectionSummary: "Klavye bakışınızı izler",
        activityHint: "Bakış bölümünü açar",
        mapLabel: "Ekran haritası",
        modes: "Bakış modu",
        historyEmpty: "Yakın zamanda geçiş yok",
        showLiveDot: "Bakış noktasını göster",
        liveDotCaption: "Sayfa açıkken",
        showHistory: "Son geçişleri göster",
        closedIsland: "Kapalı adada",
        notices: "Ada bildirimleri",
        noticesCaption: "Bir tık bölümü açar",
        allSettings: "Bakışla Odak ayarları…",
        islandSettings: "Ada ayarları…"
    )

    static let ru = ForkGlanceIslandStrings(
        sectionSummary: "Клавиатура — за взглядом",
        activityHint: "Открывает раздел «Взгляд»",
        mapLabel: "Карта экранов",
        modes: "Режим взгляда",
        historyEmpty: "Нет недавних переключений",
        showLiveDot: "Показывать точку взгляда",
        liveDotCaption: "Пока страница открыта",
        showHistory: "Показывать переключения",
        closedIsland: "В закрытом острове",
        notices: "Уведомления острова",
        noticesCaption: "Нажатие открывает раздел",
        allSettings: "Настройки фокуса взглядом…",
        islandSettings: "Настройки острова…"
    )

    static let es = ForkGlanceIslandStrings(
        sectionSummary: "El teclado sigue tu mirada",
        activityHint: "Abre la sección Mirada",
        mapLabel: "Mapa de pantallas",
        modes: "Modo de la mirada",
        historyEmpty: "Sin cambios recientes",
        showLiveDot: "Mostrar el punto de mirada",
        liveDotCaption: "Con la página abierta",
        showHistory: "Mostrar cambios recientes",
        closedIsland: "En la isla cerrada",
        notices: "Avisos de la isla",
        noticesCaption: "Un clic abre la sección",
        allSettings: "Todos los ajustes…",
        islandSettings: "Ajustes de la isla…"
    )

    static let sk = ForkGlanceIslandStrings(
        sectionSummary: "Klávesnica sleduje pohľad",
        activityHint: "Otvorí sekciu Pohľad",
        mapLabel: "Mapa obrazoviek",
        modes: "Režim pohľadu",
        historyEmpty: "Žiadne nedávne prepnutia",
        showLiveDot: "Zobraziť bod pohľadu",
        liveDotCaption: "Kým je stránka otvorená",
        showHistory: "Zobraziť nedávne prepnutia",
        closedIsland: "V zatvorenom ostrove",
        notices: "Oznámenia ostrova",
        noticesCaption: "Kliknutie otvorí sekciu",
        allSettings: "Nastavenia Fokusu pohľadom…",
        islandSettings: "Nastavenia ostrova…"
    )

    static let de = ForkGlanceIslandStrings(
        sectionSummary: "Tastatur folgt deinem Blick",
        activityHint: "Öffnet den Bereich Blick",
        mapLabel: "Bildschirmkarte",
        modes: "Blickmodus",
        historyEmpty: "Keine letzten Wechsel",
        showLiveDot: "Blickpunkt anzeigen",
        liveDotCaption: "Solange die Seite offen ist",
        showHistory: "Letzte Wechsel anzeigen",
        closedIsland: "In der geschlossenen Insel",
        notices: "Hinweise der Insel",
        noticesCaption: "Ein Klick öffnet den Bereich",
        allSettings: "Blickfokus-Einstellungen…",
        islandSettings: "Einstellungen der Insel…"
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

    static let it = ForkGlanceIslandStrings(
        sectionSummary: "La tastiera segue lo sguardo",
        activityHint: "Apre la sezione Sguardo",
        mapLabel: "Mappa degli schermi",
        modes: "Modalità sguardo",
        historyEmpty: "Nessun passaggio recente",
        showLiveDot: "Mostra il punto guardato",
        liveDotCaption: "Mentre la pagina è aperta",
        showHistory: "Mostra i passaggi recenti",
        closedIsland: "Nell’isola chiusa",
        notices: "Avvisi dell’isola",
        noticesCaption: "Un clic apre la sezione",
        allSettings: "Tutte le impostazioni…",
        islandSettings: "Impostazioni dell’isola…"
    )

    static let ja = ForkGlanceIslandStrings(
        sectionSummary: "キーボードが視線を追います",
        activityHint: "視線セクションを開きます",
        mapLabel: "画面のマップ",
        modes: "視線のモード",
        historyEmpty: "最近の切り替えはありません",
        showLiveDot: "視線の点を表示",
        liveDotCaption: "ページを開いている間",
        showHistory: "最近の切り替えを表示",
        closedIsland: "閉じたアイランド",
        notices: "アイランドの通知",
        noticesCaption: "クリックでセクションが開きます",
        allSettings: "視線フォーカスの設定…",
        islandSettings: "アイランドの設定…"
    )

    static let ko = ForkGlanceIslandStrings(
        sectionSummary: "키보드가 시선을 따라갑니다",
        activityHint: "시선 섹션을 엽니다",
        mapLabel: "화면 지도",
        modes: "시선 모드",
        historyEmpty: "최근 전환 없음",
        showLiveDot: "시선 점 표시",
        liveDotCaption: "페이지가 열려 있는 동안",
        showHistory: "최근 전환 표시",
        closedIsland: "닫힌 아일랜드에서",
        notices: "아일랜드 알림",
        noticesCaption: "클릭하면 섹션이 열립니다",
        allSettings: "시선 포커스 설정…",
        islandSettings: "아일랜드 설정…"
    )

    static let uk = ForkGlanceIslandStrings(
        sectionSummary: "Клавіатура — за поглядом",
        activityHint: "Відкриває розділ «Погляд»",
        mapLabel: "Карта екранів",
        modes: "Режим погляду",
        historyEmpty: "Немає недавніх перемикань",
        showLiveDot: "Показувати точку погляду",
        liveDotCaption: "Поки сторінка відкрита",
        showHistory: "Показувати перемикання",
        closedIsland: "У закритому острові",
        notices: "Сповіщення острова",
        noticesCaption: "Натискання відкриває розділ",
        allSettings: "Усі налаштування…",
        islandSettings: "Налаштування острова…"
    )

    static let zhHans = ForkGlanceIslandStrings(
        sectionSummary: "键盘跟随你的目光",
        activityHint: "打开目光部分",
        mapLabel: "屏幕地图",
        modes: "目光模式",
        historyEmpty: "最近没有切换",
        showLiveDot: "显示目光点",
        liveDotCaption: "页面打开期间",
        showHistory: "显示最近的切换",
        closedIsland: "在关闭的灵动岛中",
        notices: "灵动岛通知",
        noticesCaption: "点按可打开该部分",
        allSettings: "目光焦点设置…",
        islandSettings: "灵动岛设置…"
    )

    static let zhTW = ForkGlanceIslandStrings(
        sectionSummary: "鍵盤跟隨你的目光",
        activityHint: "打開目光區塊",
        mapLabel: "螢幕地圖",
        modes: "目光模式",
        historyEmpty: "最近沒有切換",
        showLiveDot: "顯示目光點",
        liveDotCaption: "頁面開啟期間",
        showHistory: "顯示最近的切換",
        closedIsland: "在關閉的動態島中",
        notices: "動態島通知",
        noticesCaption: "按一下可打開該區塊",
        allSettings: "目光焦點設定…",
        islandSettings: "動態島設定…"
    )

    static let zhHK = ForkGlanceIslandStrings(
        sectionSummary: "鍵盤跟隨你的目光",
        activityHint: "打開目光部分",
        mapLabel: "螢幕地圖",
        modes: "目光模式",
        historyEmpty: "最近沒有切換",
        showLiveDot: "顯示目光點",
        liveDotCaption: "頁面開啟期間",
        showHistory: "顯示最近的切換",
        closedIsland: "在關閉的動態島中",
        notices: "動態島通知",
        noticesCaption: "按一下可打開該部分",
        allSettings: "目光焦點設定…",
        islandSettings: "動態島設定…"
    )
}
