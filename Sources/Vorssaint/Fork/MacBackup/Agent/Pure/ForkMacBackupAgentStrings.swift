// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// The words of the Agent package: the keep-awake assertion's name (shown
/// by `pmset -g assertions` and Activity Monitor) and the lines that say
/// how the background backup runs (`ForkMacBackupAgentLink.mode`), for the
/// Settings page. `%@` is the app's name.
struct ForkMacBackupAgentStrings {
    /// The idle-sleep assertion held during a backup.
    let keepAwakeReason: String
    /// The agent is not allowed to run: the app backs up while it is open.
    let appOnly: String
    /// Waiting for « Autoriser » in System Settings.
    let needsApproval: String
    /// A Developer build: a plain LaunchAgent in ~/Library/LaunchAgents.
    let development: String

    static func strings(_ language: AppLanguage) -> ForkMacBackupAgentStrings {
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

extension ForkMacBackupAgentStrings {
    static let enUS = ForkMacBackupAgentStrings(
        keepAwakeReason: "Mac backup in progress",
        appOnly: "Backs up only while %@ is open.",
        needsApproval: "Allow %@ in System Settings › General › Login Items to back up in the background.",
        development: "Developer build: the background agent is a LaunchAgent in your Library folder.")

    static let ptBR = ForkMacBackupAgentStrings(
        keepAwakeReason: "Backup do Mac em andamento",
        appOnly: "Faz backup somente enquanto o %@ estiver aberto.",
        needsApproval: "Permita o %@ em Ajustes do Sistema › Geral › Itens de Início para fazer backup em segundo plano.",
        development: "Build de desenvolvimento: o agente em segundo plano é um LaunchAgent na sua pasta Biblioteca.")

    static let tr = ForkMacBackupAgentStrings(
        keepAwakeReason: "Mac yedeklemesi sürüyor",
        appOnly: "Yalnızca %@ açıkken yedekler.",
        needsApproval: "Arka planda yedeklemek için Sistem Ayarları › Genel › Giriş Öğeleri'nde %@ uygulamasına izin verin.",
        development: "Geliştirici sürümü: arka plan aracısı Kitaplık klasörünüzde bir LaunchAgent'tır.")

    static let ru = ForkMacBackupAgentStrings(
        keepAwakeReason: "Идёт резервное копирование Mac",
        appOnly: "Резервное копирование выполняется, только пока %@ открыт.",
        needsApproval: "Разрешите %@ в Системных настройках › Основные › Объекты входа, чтобы копировать в фоне.",
        development: "Сборка разработчика: фоновый агент — это LaunchAgent в вашей папке «Библиотеки».")

    static let es = ForkMacBackupAgentStrings(
        keepAwakeReason: "Copia de seguridad del Mac en curso",
        appOnly: "Solo hace copias mientras %@ está abierto.",
        needsApproval: "Permite %@ en Ajustes del Sistema › General › Ítems de inicio para hacer copias en segundo plano.",
        development: "Compilación de desarrollo: el agente en segundo plano es un LaunchAgent de tu carpeta Librería.")

    static let sk = ForkMacBackupAgentStrings(
        keepAwakeReason: "Prebieha záloha Macu",
        appOnly: "Zálohuje, len kým je %@ otvorený.",
        needsApproval: "Povoľte %@ v Nastaveniach systému › Všeobecné › Položky prihlásenia, aby zálohoval na pozadí.",
        development: "Vývojárska verzia: agent na pozadí je LaunchAgent vo vašom priečinku Knižnica.")

    static let de = ForkMacBackupAgentStrings(
        keepAwakeReason: "Mac-Backup läuft",
        appOnly: "Sichert nur, solange %@ geöffnet ist.",
        needsApproval: "Erlaube %@ in Systemeinstellungen › Allgemein › Anmeldeobjekte, um im Hintergrund zu sichern.",
        development: "Entwickler-Build: Der Hintergrund-Agent ist ein LaunchAgent in deinem Library-Ordner.")

    static let fr = ForkMacBackupAgentStrings(
        keepAwakeReason: "Sauvegarde du Mac en cours",
        appOnly: "Ne sauvegarde que tant que %@ est ouvert.",
        needsApproval: "Autorise %@ dans Réglages Système › Général › Ouverture pour sauvegarder en arrière-plan.",
        development: "Build de développement\u{00A0}: l’agent d’arrière-plan est un LaunchAgent de ton dossier Bibliothèque.")

    static let it = ForkMacBackupAgentStrings(
        keepAwakeReason: "Backup del Mac in corso",
        appOnly: "Esegue il backup solo mentre %@ è aperto.",
        needsApproval: "Consenti %@ in Impostazioni di Sistema › Generali › Elementi login per il backup in background.",
        development: "Build di sviluppo: l’agente in background è un LaunchAgent nella tua cartella Libreria.")

    static let ja = ForkMacBackupAgentStrings(
        keepAwakeReason: "Mac をバックアップ中",
        appOnly: "%@ が開いている間だけバックアップします。",
        needsApproval: "バックグラウンドでバックアップするには、システム設定 › 一般 › ログイン項目で %@ を許可してください。",
        development: "開発用ビルド：バックグラウンドエージェントはライブラリフォルダ内の LaunchAgent です。")

    static let ko = ForkMacBackupAgentStrings(
        keepAwakeReason: "Mac 백업 진행 중",
        appOnly: "%@이(가) 열려 있는 동안에만 백업합니다.",
        needsApproval: "백그라운드에서 백업하려면 시스템 설정 › 일반 › 로그인 항목에서 %@을(를) 허용하세요.",
        development: "개발자 빌드: 백그라운드 에이전트는 라이브러리 폴더의 LaunchAgent입니다.")

    static let uk = ForkMacBackupAgentStrings(
        keepAwakeReason: "Триває резервне копіювання Mac",
        appOnly: "Резервне копіювання виконується, лише поки %@ відкрито.",
        needsApproval: "Дозвольте %@ у Системних параметрах › Загальні › Елементи входу, щоб копіювати у фоні.",
        development: "Збірка розробника: фоновий агент — це LaunchAgent у вашій папці «Бібліотеки».")

    static let zhHans = ForkMacBackupAgentStrings(
        keepAwakeReason: "正在备份 Mac",
        appOnly: "仅在 %@ 打开时备份。",
        needsApproval: "请在“系统设置” › “通用” › “登录项”中允许 %@，以便在后台备份。",
        development: "开发版本：后台代理是你的“资源库”文件夹中的 LaunchAgent。")

    static let zhTW = ForkMacBackupAgentStrings(
        keepAwakeReason: "正在備份 Mac",
        appOnly: "僅在 %@ 開啟時備份。",
        needsApproval: "請在「系統設定」›「一般」›「登入項目」中允許 %@，以便在背景備份。",
        development: "開發版本：背景代理程式是你「資源庫」檔案夾中的 LaunchAgent。")

    static let zhHK = ForkMacBackupAgentStrings(
        keepAwakeReason: "正在備份 Mac",
        appOnly: "只在 %@ 開啟時備份。",
        needsApproval: "請在「系統設定」›「一般」›「登入項目」中允許 %@，以便在背景備份。",
        development: "開發版本：背景代理程式是你「資源庫」檔案夾中的 LaunchAgent。")
}
