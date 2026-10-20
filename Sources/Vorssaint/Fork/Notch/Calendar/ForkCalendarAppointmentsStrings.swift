// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// The texts of the video links and the CRM's appointments in the island's
/// calendar, and of their setting, in the app's fifteen languages. Every
/// other word of the calendar is the official one (`NotchCalendarStrings`).
///
/// The ones the island shows (buttons, the link's line) are written for its
/// room, 28 characters at most, never cut.
struct ForkCalendarAppointmentsStrings {
    /// Before the person or the company, where a calendar's name goes.
    let crmMark: String
    let join: String
    let copyLink: String
    let linkCopied: String
    /// A meeting link of a service the island does not name.
    let videoCall: String
    let settingTitle: String
    /// "%@" is the CRM's name.
    let settingCaptionFormat: String
    let hiddenInCaptures: String
    let hideFromCaptures: String

    func settingCaption(_ name: String) -> String { String(format: settingCaptionFormat, name) }

    static var current: ForkCalendarAppointmentsStrings { strings(L10n.shared.language) }

    static func strings(_ language: AppLanguage) -> ForkCalendarAppointmentsStrings {
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

extension ForkCalendarAppointmentsStrings {
    static let enUS = ForkCalendarAppointmentsStrings(
        crmMark: "CRM",
        join: "Join",
        copyLink: "Copy Link",
        linkCopied: "Link Copied",
        videoCall: "Video Call",
        settingTitle: "Show CRM appointments in the island’s calendar",
        settingCaptionFormat: "Your upcoming appointments in %@ join the Dynamic Island’s calendar, with their video link. They are read while the calendar is open, at most every 5 minutes, and nothing of them is kept on this Mac.",
        hiddenInCaptures: "Hidden while the Dynamic Island shows in screenshots and videos, so that a shared screen never shows them.",
        hideFromCaptures: "Hide the Island From Captures")

    static let ptBR = ForkCalendarAppointmentsStrings(
        crmMark: "CRM",
        join: "Entrar",
        copyLink: "Copiar link",
        linkCopied: "Link copiado",
        videoCall: "Videochamada",
        settingTitle: "Mostrar compromissos do CRM no calendário da ilha",
        settingCaptionFormat: "Seus próximos compromissos no %@ aparecem no calendário da Dynamic Island, com o link da videochamada. Eles são lidos enquanto o calendário está aberto, no máximo a cada 5 minutos, e nada deles fica guardado neste Mac.",
        hiddenInCaptures: "Ocultos enquanto a Dynamic Island aparece em capturas de tela e vídeos, para que uma tela compartilhada nunca os mostre.",
        hideFromCaptures: "Ocultar a ilha das capturas")

    static let tr = ForkCalendarAppointmentsStrings(
        crmMark: "CRM",
        join: "Katıl",
        copyLink: "Bağlantıyı Kopyala",
        linkCopied: "Bağlantı kopyalandı",
        videoCall: "Görüntülü görüşme",
        settingTitle: "CRM randevularını adanın takviminde göster",
        settingCaptionFormat: "%@ içindeki yaklaşan randevularınız, görüntülü görüşme bağlantılarıyla birlikte Dynamic Island takviminde görünür. Takvim açıkken en fazla 5 dakikada bir okunurlar ve hiçbir bilgileri bu Mac’te saklanmaz.",
        hiddenInCaptures: "Dynamic Island ekran görüntülerinde ve videolarda göründüğü sürece gizlenir; böylece paylaşılan bir ekran onları asla göstermez.",
        hideFromCaptures: "Adayı yakalamalarda gizle")

    static let ru = ForkCalendarAppointmentsStrings(
        crmMark: "CRM",
        join: "Войти",
        copyLink: "Скопировать ссылку",
        linkCopied: "Ссылка скопирована",
        videoCall: "Видеозвонок",
        settingTitle: "Показывать встречи из CRM в календаре острова",
        settingCaptionFormat: "Ваши предстоящие встречи из %@ появляются в календаре Dynamic Island вместе со ссылкой на видеозвонок. Они читаются, пока календарь открыт, не чаще раза в 5 минут, и ничего из них не хранится на этом Mac.",
        hiddenInCaptures: "Скрыты, пока Dynamic Island видна на снимках экрана и в видео, чтобы общий экран никогда их не показал.",
        hideFromCaptures: "Скрыть остров из снимков")

    static let es = ForkCalendarAppointmentsStrings(
        crmMark: "CRM",
        join: "Unirse",
        copyLink: "Copiar enlace",
        linkCopied: "Enlace copiado",
        videoCall: "Videollamada",
        settingTitle: "Mostrar las citas del CRM en el calendario de la isla",
        settingCaptionFormat: "Tus próximas citas de %@ aparecen en el calendario de la Dynamic Island, con su enlace de videollamada. Se leen mientras el calendario está abierto, como mucho cada 5 minutos, y no se guarda nada de ellas en este Mac.",
        hiddenInCaptures: "Ocultas mientras la Dynamic Island aparece en capturas de pantalla y vídeos, para que una pantalla compartida nunca las muestre.",
        hideFromCaptures: "Ocultar la isla de las capturas")

    static let sk = ForkCalendarAppointmentsStrings(
        crmMark: "CRM",
        join: "Pripojiť sa",
        copyLink: "Kopírovať odkaz",
        linkCopied: "Odkaz skopírovaný",
        videoCall: "Videohovor",
        settingTitle: "Zobraziť stretnutia z CRM v kalendári ostrova",
        settingCaptionFormat: "Vaše nadchádzajúce stretnutia z %@ sa zobrazia v kalendári Dynamic Island aj s odkazom na videohovor. Načítavajú sa, kým je kalendár otvorený, najviac raz za 5 minút, a nič z nich sa v tomto Macu neuchováva.",
        hiddenInCaptures: "Skryté, kým sa Dynamic Island zobrazuje na snímkach obrazovky a vo videách, aby ich zdieľaná obrazovka nikdy neukázala.",
        hideFromCaptures: "Skryť ostrov zo záznamov")

    static let de = ForkCalendarAppointmentsStrings(
        crmMark: "CRM",
        join: "Beitreten",
        copyLink: "Link kopieren",
        linkCopied: "Link kopiert",
        videoCall: "Videoanruf",
        settingTitle: "CRM-Termine im Kalender der Insel anzeigen",
        settingCaptionFormat: "Deine nächsten Termine in %@ erscheinen im Kalender der Dynamic Island, mit ihrem Videolink. Sie werden gelesen, solange der Kalender offen ist, höchstens alle 5 Minuten, und nichts davon bleibt auf diesem Mac.",
        hiddenInCaptures: "Ausgeblendet, solange die Dynamic Island in Screenshots und Videos erscheint, damit ein geteilter Bildschirm sie nie zeigt.",
        hideFromCaptures: "Insel in Aufnahmen ausblenden")

    static let fr = ForkCalendarAppointmentsStrings(
        crmMark: "CRM",
        join: "Rejoindre",
        copyLink: "Copier le lien",
        linkCopied: "Lien copié",
        videoCall: "Visio",
        settingTitle: "Afficher les RDV du CRM dans le calendrier de l’île",
        settingCaptionFormat: "Vos prochains rendez-vous de %@ rejoignent le calendrier de la Dynamic Island, avec leur lien de visio. Ils sont lus pendant que le calendrier est affiché, au plus toutes les 5\u{00A0}minutes, et rien d’eux n’est gardé sur ce Mac.",
        hiddenInCaptures: "Masqués tant que la Dynamic Island apparaît dans les captures d’écran et les vidéos, pour qu’un écran partagé ne les montre jamais.",
        hideFromCaptures: "Masquer l’île des captures")

    static let it = ForkCalendarAppointmentsStrings(
        crmMark: "CRM",
        join: "Partecipa",
        copyLink: "Copia link",
        linkCopied: "Link copiato",
        videoCall: "Videochiamata",
        settingTitle: "Mostra gli appuntamenti del CRM nel calendario dell’isola",
        settingCaptionFormat: "I tuoi prossimi appuntamenti in %@ compaiono nel calendario della Dynamic Island, con il link della videochiamata. Vengono letti mentre il calendario è aperto, al massimo ogni 5 minuti, e nulla di loro resta su questo Mac.",
        hiddenInCaptures: "Nascosti finché la Dynamic Island appare nelle schermate e nei video, perché uno schermo condiviso non li mostri mai.",
        hideFromCaptures: "Nascondi l’isola dalle catture")

    static let ja = ForkCalendarAppointmentsStrings(
        crmMark: "CRM",
        join: "参加",
        copyLink: "リンクをコピー",
        linkCopied: "リンクをコピーしました",
        videoCall: "ビデオ通話",
        settingTitle: "CRMの予定をアイランドのカレンダーに表示",
        settingCaptionFormat: "%@の今後の予定が、ビデオ通話のリンクとともにDynamic Islandのカレンダーに表示されます。カレンダーを開いている間に最大5分ごとに読み込まれ、このMacには何も保存されません。",
        hiddenInCaptures: "画面共有で表示されないよう、Dynamic Islandがスクリーンショットと動画に表示される設定の間は非表示になります。",
        hideFromCaptures: "アイランドをキャプチャから隠す")

    static let ko = ForkCalendarAppointmentsStrings(
        crmMark: "CRM",
        join: "참가",
        copyLink: "링크 복사",
        linkCopied: "링크를 복사함",
        videoCall: "영상 통화",
        settingTitle: "아일랜드 캘린더에 CRM 일정 표시",
        settingCaptionFormat: "%@의 다가오는 일정이 영상 통화 링크와 함께 Dynamic Island 캘린더에 표시됩니다. 캘린더가 열려 있는 동안 최대 5분마다 읽으며, 이 Mac에는 아무것도 저장하지 않습니다.",
        hiddenInCaptures: "공유된 화면에 나타나지 않도록, Dynamic Island가 스크린샷 및 동영상에 표시되는 동안에는 숨겨집니다.",
        hideFromCaptures: "캡처에서 아일랜드 숨기기")

    static let uk = ForkCalendarAppointmentsStrings(
        crmMark: "CRM",
        join: "Приєднатися",
        copyLink: "Скопіювати посилання",
        linkCopied: "Посилання скопійовано",
        videoCall: "Відеодзвінок",
        settingTitle: "Показувати зустрічі з CRM у календарі острова",
        settingCaptionFormat: "Ваші найближчі зустрічі з %@ з’являються в календарі Dynamic Island разом із посиланням на відеодзвінок. Вони читаються, поки календар відкритий, не частіше ніж раз на 5 хвилин, і нічого з них не зберігається на цьому Mac.",
        hiddenInCaptures: "Приховані, поки Dynamic Island видно на знімках і відео, щоб спільний екран ніколи їх не показав.",
        hideFromCaptures: "Приховати острів зі знімків")

    static let zhHans = ForkCalendarAppointmentsStrings(
        crmMark: "CRM",
        join: "加入",
        copyLink: "拷贝链接",
        linkCopied: "已拷贝链接",
        videoCall: "视频通话",
        settingTitle: "在灵动岛日历中显示 CRM 预约",
        settingCaptionFormat: "你在 %@ 中即将到来的预约会连同视频通话链接一起显示在 Dynamic Island 的日历中。仅在日历打开时读取，最多每 5 分钟一次，不会在这台 Mac 上保留任何内容。",
        hiddenInCaptures: "当 Dynamic Island 显示在截图和视频中时隐藏，以免共享屏幕时被看到。",
        hideFromCaptures: "从截图中隐藏灵动岛")

    static let zhTW = ForkCalendarAppointmentsStrings(
        crmMark: "CRM",
        join: "加入",
        copyLink: "拷貝連結",
        linkCopied: "已拷貝連結",
        videoCall: "視訊通話",
        settingTitle: "在動態島行事曆中顯示 CRM 預約",
        settingCaptionFormat: "你在 %@ 中即將到來的預約會連同視訊通話連結一起顯示在 Dynamic Island 的行事曆中。僅在行事曆打開時讀取，最多每 5 分鐘一次，不會在這部 Mac 上保留任何內容。",
        hiddenInCaptures: "當 Dynamic Island 顯示在截圖與影片中時隱藏，以免共享螢幕時被看到。",
        hideFromCaptures: "從截圖中隱藏動態島")

    static let zhHK = ForkCalendarAppointmentsStrings(
        crmMark: "CRM",
        join: "加入",
        copyLink: "拷貝連結",
        linkCopied: "已拷貝連結",
        videoCall: "視像通話",
        settingTitle: "在動態島日曆中顯示 CRM 預約",
        settingCaptionFormat: "你在 %@ 中即將到來的預約會連同視像通話連結一起顯示在 Dynamic Island 的日曆中。只在日曆打開時讀取，最多每 5 分鐘一次，不會在這部 Mac 上保留任何內容。",
        hiddenInCaptures: "當 Dynamic Island 顯示在截圖與影片中時隱藏，以免共享螢幕時被看到。",
        hideFromCaptures: "從截圖中隱藏動態島")
}
