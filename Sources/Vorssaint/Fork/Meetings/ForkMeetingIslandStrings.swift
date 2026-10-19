// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// The texts of the island's Meetings page and of its settings in the
/// Dynamic Island's tabs, in the app's fifteen languages. Kept apart from
/// `ForkMeetingStrings`, which the page reuses for every word the rest of
/// the feature already says (Record, Show in Finder, Exported…).
///
/// The short ones (statuses, titles, buttons) are written for the island's
/// room, 28 characters at most, never cut.
struct ForkMeetingIslandStrings {
    // MARK: W2 G
    /// One line under the section's name, in the Content tab.
    let sectionSummary: String
    let idleTitle: String
    let idleCaption: String
    /// "Or press ⌃⌥⌘R."
    let idleShortcutFormat: String
    let recordMeeting: String
    let detectedTitle: String
    let detectedCaption: String
    let recentTitle: String
    let historyEmpty: String
    let statusTranscript: String
    let statusTranscriptQueued: String
    let statusSummary: String
    let statusSummarizing: String
    let actionOpen: String
    let openInWindow: String
    let filesTitle: String
    let fileVideo: String
    let fileAudio: String
    let fileSubtitles: String
    let previewLabel: String
    let islandSettingsLink: String
    /// The Activity tab's line on the meeting's messages: "%@" is the
    /// official Captures indicator, in the Indicators card above.
    let noticesCaptionFormat: String
    let showDetails: String
    let hideDetails: String

    func idleShortcut(_ shortcut: String) -> String { String(format: idleShortcutFormat, shortcut) }
    func noticesCaption(_ card: String) -> String { String(format: noticesCaptionFormat, card) }

    static var current: ForkMeetingIslandStrings { strings(L10n.shared.language) }

    static func strings(_ language: AppLanguage) -> ForkMeetingIslandStrings {
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

extension ForkMeetingIslandStrings {
    static let enUS = ForkMeetingIslandStrings(
        // MARK: W2 G
        sectionSummary: "The meeting being recorded, the call detected and your recent meetings.",
        idleTitle: "No meeting being recorded",
        idleCaption: "A call is offered for recording as soon as it starts.",
        idleShortcutFormat: "Or press %@.",
        recordMeeting: "Record a Meeting",
        detectedTitle: "Call detected",
        detectedCaption: "Not being recorded",
        recentTitle: "Recent",
        historyEmpty: "Your recorded meetings will appear here.",
        statusTranscript: "Transcribed",
        statusTranscriptQueued: "Transcript queued",
        statusSummary: "Summarized",
        statusSummarizing: "Summarizing…",
        actionOpen: "Open",
        openInWindow: "Open in the Meetings window",
        filesTitle: "Files",
        fileVideo: "Video",
        fileAudio: "Audio",
        fileSubtitles: "Subtitles",
        previewLabel: "Preview of what is being filmed",
        islandSettingsLink: "Dynamic Island Settings",
        noticesCaptionFormat: "Its messages (recording started, meeting saved) show while the “%@” indicator above is on.",
        showDetails: "Show Details",
        hideDetails: "Hide Details")

    static let ptBR = ForkMeetingIslandStrings(
        // MARK: W2 G
        sectionSummary: "A reunião em gravação, a chamada detectada e suas reuniões recentes.",
        idleTitle: "Nenhuma gravação",
        idleCaption: "Uma chamada é proposta para gravação assim que começa.",
        idleShortcutFormat: "Ou pressione %@.",
        recordMeeting: "Gravar uma reunião",
        detectedTitle: "Chamada detectada",
        detectedCaption: "Não está sendo gravada",
        recentTitle: "Recentes",
        historyEmpty: "Suas reuniões gravadas aparecerão aqui.",
        statusTranscript: "Transcrita",
        statusTranscriptQueued: "Transcrição na fila",
        statusSummary: "Resumida",
        statusSummarizing: "Resumindo…",
        actionOpen: "Abrir",
        openInWindow: "Abrir na janela Reuniões",
        filesTitle: "Arquivos",
        fileVideo: "Vídeo",
        fileAudio: "Áudio",
        fileSubtitles: "Legendas",
        previewLabel: "Prévia do que está sendo filmado",
        islandSettingsLink: "Ajustes da Dynamic Island",
        noticesCaptionFormat: "Suas mensagens (gravação iniciada, reunião salva) aparecem enquanto o indicador “%@” acima estiver ativado.",
        showDetails: "Mostrar detalhes",
        hideDetails: "Ocultar detalhes")

    static let tr = ForkMeetingIslandStrings(
        // MARK: W2 G
        sectionSummary: "Kaydedilen toplantı, algılanan görüşme ve son toplantılarınız.",
        idleTitle: "Kayıt yok",
        idleCaption: "Bir görüşme başlar başlamaz kaydetmeniz önerilir.",
        idleShortcutFormat: "Ya da %@ tuşlarına basın.",
        recordMeeting: "Toplantı kaydet",
        detectedTitle: "Görüşme algılandı",
        detectedCaption: "Kaydedilmiyor",
        recentTitle: "Son toplantılar",
        historyEmpty: "Kaydettiğiniz toplantılar burada görünür.",
        statusTranscript: "Döküm hazır",
        statusTranscriptQueued: "Döküm sırada",
        statusSummary: "Özetlendi",
        statusSummarizing: "Özetleniyor…",
        actionOpen: "Aç",
        openInWindow: "Toplantılar penceresinde aç",
        filesTitle: "Dosyalar",
        fileVideo: "Video",
        fileAudio: "Ses",
        fileSubtitles: "Altyazılar",
        previewLabel: "Kaydedilen görüntünün önizlemesi",
        islandSettingsLink: "Dynamic Island ayarları",
        noticesCaptionFormat: "Mesajları (kayıt başladı, toplantı kaydedildi), yukarıdaki “%@” göstergesi açıkken görünür.",
        showDetails: "Ayrıntıları göster",
        hideDetails: "Ayrıntıları gizle")

    static let ru = ForkMeetingIslandStrings(
        // MARK: W2 G
        sectionSummary: "Идущая запись, найденный звонок и ваши недавние встречи.",
        idleTitle: "Запись не идёт",
        idleCaption: "Запись звонка предлагается, как только он начинается.",
        idleShortcutFormat: "Или нажмите %@.",
        recordMeeting: "Записать встречу",
        detectedTitle: "Обнаружен звонок",
        detectedCaption: "Не записывается",
        recentTitle: "Недавние",
        historyEmpty: "Здесь появятся записанные встречи.",
        statusTranscript: "Расшифрована",
        statusTranscriptQueued: "Расшифровка в очереди",
        statusSummary: "Есть сводка",
        statusSummarizing: "Сводка…",
        actionOpen: "Открыть",
        openInWindow: "Открыть в окне «Встречи»",
        filesTitle: "Файлы",
        fileVideo: "Видео",
        fileAudio: "Аудио",
        fileSubtitles: "Субтитры",
        previewLabel: "Предпросмотр того, что снимается",
        islandSettingsLink: "Настройки Dynamic Island",
        noticesCaptionFormat: "Её сообщения (запись начата, встреча сохранена) показываются, пока включён индикатор «%@» выше.",
        showDetails: "Показать подробности",
        hideDetails: "Скрыть подробности")

    static let es = ForkMeetingIslandStrings(
        // MARK: W2 G
        sectionSummary: "La reunión que se graba, la llamada detectada y tus reuniones recientes.",
        idleTitle: "Ninguna grabación",
        idleCaption: "Se te propone grabar una llamada en cuanto empieza.",
        idleShortcutFormat: "O pulsa %@.",
        recordMeeting: "Grabar una reunión",
        detectedTitle: "Llamada detectada",
        detectedCaption: "No se está grabando",
        recentTitle: "Recientes",
        historyEmpty: "Tus reuniones grabadas aparecerán aquí.",
        statusTranscript: "Transcrita",
        statusTranscriptQueued: "Transcripción en cola",
        statusSummary: "Resumida",
        statusSummarizing: "Resumiendo…",
        actionOpen: "Abrir",
        openInWindow: "Abrir en la ventana Reuniones",
        filesTitle: "Archivos",
        fileVideo: "Vídeo",
        fileAudio: "Audio",
        fileSubtitles: "Subtítulos",
        previewLabel: "Vista previa de lo que se graba",
        islandSettingsLink: "Ajustes de la Dynamic Island",
        noticesCaptionFormat: "Sus mensajes (grabación iniciada, reunión guardada) se muestran mientras el indicador «%@» de arriba esté activado.",
        showDetails: "Mostrar detalles",
        hideDetails: "Ocultar detalles")

    static let sk = ForkMeetingIslandStrings(
        // MARK: W2 G
        sectionSummary: "Nahrávané stretnutie, zistený hovor a vaše nedávne stretnutia.",
        idleTitle: "Žiadne nahrávanie",
        idleCaption: "Nahrávanie hovoru sa ponúkne hneď, ako sa začne.",
        idleShortcutFormat: "Alebo stlačte %@.",
        recordMeeting: "Nahrať stretnutie",
        detectedTitle: "Zistený hovor",
        detectedCaption: "Nenahráva sa",
        recentTitle: "Nedávne",
        historyEmpty: "Tu sa zobrazia vaše nahrané stretnutia.",
        statusTranscript: "Prepísané",
        statusTranscriptQueued: "Prepis čaká",
        statusSummary: "Zhrnuté",
        statusSummarizing: "Zhŕňa sa…",
        actionOpen: "Otvoriť",
        openInWindow: "Otvoriť v okne Stretnutia",
        filesTitle: "Súbory",
        fileVideo: "Video",
        fileAudio: "Zvuk",
        fileSubtitles: "Titulky",
        previewLabel: "Náhľad nahrávaného obrazu",
        islandSettingsLink: "Nastavenia Dynamic Island",
        noticesCaptionFormat: "Jeho správy (nahrávanie spustené, stretnutie uložené) sa zobrazujú, kým je zapnutý indikátor „%@“ vyššie.",
        showDetails: "Zobraziť podrobnosti",
        hideDetails: "Skryť podrobnosti")

    static let de = ForkMeetingIslandStrings(
        // MARK: W2 G
        sectionSummary: "Die laufende Aufnahme, der erkannte Anruf und Ihre letzten Besprechungen.",
        idleTitle: "Keine Aufnahme",
        idleCaption: "Ein Anruf wird zur Aufnahme angeboten, sobald er beginnt.",
        idleShortcutFormat: "Oder drücken Sie %@.",
        recordMeeting: "Besprechung aufnehmen",
        detectedTitle: "Anruf erkannt",
        detectedCaption: "Wird nicht aufgenommen",
        recentTitle: "Zuletzt",
        historyEmpty: "Hier erscheinen Ihre aufgenommenen Besprechungen.",
        statusTranscript: "Transkribiert",
        statusTranscriptQueued: "Transkript wartet",
        statusSummary: "Zusammengefasst",
        statusSummarizing: "Wird zusammengefasst…",
        actionOpen: "Öffnen",
        openInWindow: "Im Fenster „Besprechungen“ öffnen",
        filesTitle: "Dateien",
        fileVideo: "Video",
        fileAudio: "Audio",
        fileSubtitles: "Untertitel",
        previewLabel: "Vorschau des aufgenommenen Bilds",
        islandSettingsLink: "Dynamic Island-Einstellungen",
        noticesCaptionFormat: "Ihre Hinweise (Aufnahme gestartet, Besprechung gesichert) erscheinen, solange die Anzeige „%@“ oben aktiv ist.",
        showDetails: "Details einblenden",
        hideDetails: "Details ausblenden")

    static let fr = ForkMeetingIslandStrings(
        // MARK: W2 G
        sectionSummary: "La réunion en cours, l’appel détecté et vos réunions récentes.",
        idleTitle: "Aucun enregistrement",
        idleCaption: "Un appel vous est proposé à l’enregistrement dès qu’il commence.",
        idleShortcutFormat: "Ou appuyez sur %@.",
        recordMeeting: "Enregistrer une réunion",
        detectedTitle: "Appel détecté",
        detectedCaption: "Non enregistré",
        recentTitle: "Récentes",
        historyEmpty: "Vos réunions enregistrées apparaîtront ici.",
        statusTranscript: "Transcrite",
        statusTranscriptQueued: "Transcription en attente",
        statusSummary: "Résumée",
        statusSummarizing: "Résumé en cours…",
        actionOpen: "Ouvrir",
        openInWindow: "Ouvrir dans la fenêtre Réunions",
        filesTitle: "Fichiers",
        fileVideo: "Vidéo",
        fileAudio: "Audio",
        fileSubtitles: "Sous-titres",
        previewLabel: "Aperçu de ce qui est filmé",
        islandSettingsLink: "Réglages de la Dynamic Island",
        noticesCaptionFormat: "Ses messages (enregistrement démarré, réunion enregistrée) s’affichent tant que l’indicateur «\u{00A0}%@\u{00A0}» ci-dessus est activé.",
        showDetails: "Afficher les détails",
        hideDetails: "Masquer les détails")

    static let it = ForkMeetingIslandStrings(
        // MARK: W2 G
        sectionSummary: "La riunione in registrazione, la chiamata rilevata e le riunioni recenti.",
        idleTitle: "Nessuna registrazione",
        idleCaption: "Ti viene proposto di registrare una chiamata appena inizia.",
        idleShortcutFormat: "Oppure premi %@.",
        recordMeeting: "Registra una riunione",
        detectedTitle: "Chiamata rilevata",
        detectedCaption: "Non in registrazione",
        recentTitle: "Recenti",
        historyEmpty: "Qui compariranno le riunioni registrate.",
        statusTranscript: "Trascritta",
        statusTranscriptQueued: "Trascrizione in coda",
        statusSummary: "Riassunta",
        statusSummarizing: "Riassunto in corso…",
        actionOpen: "Apri",
        openInWindow: "Apri nella finestra Riunioni",
        filesTitle: "File",
        fileVideo: "Video",
        fileAudio: "Audio",
        fileSubtitles: "Sottotitoli",
        previewLabel: "Anteprima di ciò che viene ripreso",
        islandSettingsLink: "Impostazioni della Dynamic Island",
        noticesCaptionFormat: "I suoi messaggi (registrazione avviata, riunione salvata) compaiono finché l’indicatore «%@» qui sopra è attivo.",
        showDetails: "Mostra dettagli",
        hideDetails: "Nascondi dettagli")

    static let ja = ForkMeetingIslandStrings(
        // MARK: W2 G
        sectionSummary: "録画中のミーティング、検出した通話、最近のミーティング。",
        idleTitle: "録画中ではありません",
        idleCaption: "通話が始まるとすぐに録画を提案します。",
        idleShortcutFormat: "または %@ を押します。",
        recordMeeting: "ミーティングを録画",
        detectedTitle: "通話を検出",
        detectedCaption: "録画していません",
        recentTitle: "最近",
        historyEmpty: "録画したミーティングがここに表示されます。",
        statusTranscript: "文字起こし済み",
        statusTranscriptQueued: "文字起こし待ち",
        statusSummary: "要約済み",
        statusSummarizing: "要約中…",
        actionOpen: "開く",
        openInWindow: "ミーティングウインドウで開く",
        filesTitle: "ファイル",
        fileVideo: "ビデオ",
        fileAudio: "オーディオ",
        fileSubtitles: "字幕",
        previewLabel: "録画中の映像のプレビュー",
        islandSettingsLink: "Dynamic Island の設定",
        noticesCaptionFormat: "メッセージ（録画の開始、ミーティングの保存）は、上の「%@」インジケータがオンのあいだ表示されます。",
        showDetails: "詳細を表示",
        hideDetails: "詳細を隠す")

    static let ko = ForkMeetingIslandStrings(
        // MARK: W2 G
        sectionSummary: "녹화 중인 회의, 감지된 통화, 최근 회의.",
        idleTitle: "녹화 중인 회의 없음",
        idleCaption: "통화가 시작되면 바로 녹화를 제안합니다.",
        idleShortcutFormat: "또는 %@ 키를 누르세요.",
        recordMeeting: "회의 녹화",
        detectedTitle: "통화 감지됨",
        detectedCaption: "녹화 중 아님",
        recentTitle: "최근",
        historyEmpty: "녹화한 회의가 여기에 표시됩니다.",
        statusTranscript: "전사됨",
        statusTranscriptQueued: "전사 대기 중",
        statusSummary: "요약됨",
        statusSummarizing: "요약 중…",
        actionOpen: "열기",
        openInWindow: "회의 윈도우에서 열기",
        filesTitle: "파일",
        fileVideo: "비디오",
        fileAudio: "오디오",
        fileSubtitles: "자막",
        previewLabel: "녹화 중인 화면 미리 보기",
        islandSettingsLink: "Dynamic Island 설정",
        noticesCaptionFormat: "메시지(녹화 시작, 회의 저장)는 위의 ‘%@’ 표시기가 켜져 있는 동안 표시됩니다.",
        showDetails: "세부 정보 보기",
        hideDetails: "세부 정보 가리기")

    static let uk = ForkMeetingIslandStrings(
        // MARK: W2 G
        sectionSummary: "Поточний запис, виявлений дзвінок і ваші нещодавні зустрічі.",
        idleTitle: "Запис не ведеться",
        idleCaption: "Запис дзвінка пропонується, щойно він починається.",
        idleShortcutFormat: "Або натисніть %@.",
        recordMeeting: "Записати зустріч",
        detectedTitle: "Виявлено дзвінок",
        detectedCaption: "Не записується",
        recentTitle: "Нещодавні",
        historyEmpty: "Тут з’являться записані зустрічі.",
        statusTranscript: "Розшифровано",
        statusTranscriptQueued: "Розшифрування в черзі",
        statusSummary: "Є підсумок",
        statusSummarizing: "Підсумок…",
        actionOpen: "Відкрити",
        openInWindow: "Відкрити у вікні «Зустрічі»",
        filesTitle: "Файли",
        fileVideo: "Відео",
        fileAudio: "Аудіо",
        fileSubtitles: "Субтитри",
        previewLabel: "Попередній перегляд того, що знімається",
        islandSettingsLink: "Параметри Dynamic Island",
        noticesCaptionFormat: "Її повідомлення (запис розпочато, зустріч збережено) з’являються, доки ввімкнено індикатор «%@» вище.",
        showDetails: "Показати подробиці",
        hideDetails: "Сховати подробиці")

    static let zhHans = ForkMeetingIslandStrings(
        // MARK: W2 G
        sectionSummary: "正在录制的会议、检测到的通话和最近的会议。",
        idleTitle: "没有正在录制的会议",
        idleCaption: "通话一开始就会提示你录制。",
        idleShortcutFormat: "或按 %@。",
        recordMeeting: "录制会议",
        detectedTitle: "检测到通话",
        detectedCaption: "未在录制",
        recentTitle: "最近",
        historyEmpty: "录制的会议会显示在这里。",
        statusTranscript: "已转写",
        statusTranscriptQueued: "等待转写",
        statusSummary: "已摘要",
        statusSummarizing: "正在摘要…",
        actionOpen: "打开",
        openInWindow: "在“会议”窗口中打开",
        filesTitle: "文件",
        fileVideo: "视频",
        fileAudio: "音频",
        fileSubtitles: "字幕",
        previewLabel: "正在录制画面的预览",
        islandSettingsLink: "Dynamic Island 设置",
        noticesCaptionFormat: "其消息（录制已开始、会议已存储）会在上方“%@”提示打开时显示。",
        showDetails: "显示详细信息",
        hideDetails: "隐藏详细信息")

    static let zhTW = ForkMeetingIslandStrings(
        // MARK: W2 G
        sectionSummary: "正在錄製的會議、偵測到的通話和最近的會議。",
        idleTitle: "沒有正在錄製的會議",
        idleCaption: "通話一開始就會提示你錄製。",
        idleShortcutFormat: "或按 %@。",
        recordMeeting: "錄製會議",
        detectedTitle: "偵測到通話",
        detectedCaption: "未在錄製",
        recentTitle: "最近",
        historyEmpty: "錄製的會議會顯示在這裡。",
        statusTranscript: "已轉寫",
        statusTranscriptQueued: "等待轉寫",
        statusSummary: "已摘要",
        statusSummarizing: "正在摘要…",
        actionOpen: "打開",
        openInWindow: "在「會議」視窗中打開",
        filesTitle: "檔案",
        fileVideo: "影片",
        fileAudio: "音訊",
        fileSubtitles: "字幕",
        previewLabel: "正在錄製畫面的預覽",
        islandSettingsLink: "Dynamic Island 設定",
        noticesCaptionFormat: "其訊息（錄製已開始、會議已儲存）會在上方「%@」提示開啟時顯示。",
        showDetails: "顯示詳細資訊",
        hideDetails: "隱藏詳細資訊")

    static let zhHK = ForkMeetingIslandStrings(
        // MARK: W2 G
        sectionSummary: "正在錄製的會議、偵測到的通話和最近的會議。",
        idleTitle: "沒有正在錄製的會議",
        idleCaption: "通話一開始就會提示你錄製。",
        idleShortcutFormat: "或按 %@。",
        recordMeeting: "錄製會議",
        detectedTitle: "偵測到通話",
        detectedCaption: "未在錄製",
        recentTitle: "最近",
        historyEmpty: "錄製的會議會在這裡顯示。",
        statusTranscript: "已轉寫",
        statusTranscriptQueued: "等待轉寫",
        statusSummary: "已摘要",
        statusSummarizing: "正在摘要…",
        actionOpen: "開啟",
        openInWindow: "在「會議」視窗中開啟",
        filesTitle: "檔案",
        fileVideo: "影片",
        fileAudio: "音訊",
        fileSubtitles: "字幕",
        previewLabel: "正在錄製畫面的預覽",
        islandSettingsLink: "Dynamic Island 設定",
        noticesCaptionFormat: "其訊息（錄製已開始、會議已儲存）會在上方「%@」提示開啟時顯示。",
        showDetails: "顯示詳細資料",
        hideDetails: "隱藏詳細資料")
}
