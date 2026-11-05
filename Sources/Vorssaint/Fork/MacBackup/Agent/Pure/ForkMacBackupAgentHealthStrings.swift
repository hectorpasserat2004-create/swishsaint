// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// The words for the agent's health (`ForkMacBackupAgentLinkHealth`), shown
/// in the window's « Agent et moteur » card, and the mark of a partial
/// « Dernière » in the island.
struct ForkMacBackupAgentHealthStrings {
    /// Registered, macOS did not start it: registered again, waiting.
    let repairing: String
    /// Still not started after that: the person allows it again.
    let reauthorize: String
    /// The button that opens System Settings › Login Items.
    let openLoginItems: String
    /// After « Dernière : aujourd’hui à 17:37 »: the snapshot is partial.
    let partialMark: String

    static func strings(_ language: AppLanguage) -> ForkMacBackupAgentHealthStrings {
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

    func line(_ health: ForkMacBackupAgentLinkHealth) -> String? {
        switch health {
        case .repairing: return repairing
        case .stoppedBySystem: return reauthorize
        case .unknown, .running: return nil
        }
    }
}

extension ForkMacBackupAgentHealthStrings {
    static let enUS = ForkMacBackupAgentHealthStrings(
        repairing: "Agent stopped by macOS — registering it again…",
        reauthorize: "Agent stopped by macOS — allow it again",
        openLoginItems: "Open Login Items",
        partialMark: "partial")

    static let ptBR = ForkMacBackupAgentHealthStrings(
        repairing: "Agente parado pelo macOS — registrando de novo…",
        reauthorize: "Agente parado pelo macOS — permita de novo",
        openLoginItems: "Abrir Itens de Início",
        partialMark: "parcial")

    static let tr = ForkMacBackupAgentHealthStrings(
        repairing: "Aracı macOS tarafından durduruldu — yeniden kaydediliyor…",
        reauthorize: "Aracı macOS tarafından durduruldu — yeniden izin verin",
        openLoginItems: "Giriş Öğelerini Aç",
        partialMark: "kısmi")

    static let ru = ForkMacBackupAgentHealthStrings(
        repairing: "Агент остановлен macOS — повторная регистрация…",
        reauthorize: "Агент остановлен macOS — разрешите его снова",
        openLoginItems: "Открыть объекты входа",
        partialMark: "частичная")

    static let es = ForkMacBackupAgentHealthStrings(
        repairing: "macOS detuvo el agente — registrándolo de nuevo…",
        reauthorize: "macOS detuvo el agente — vuelve a permitirlo",
        openLoginItems: "Abrir ítems de inicio",
        partialMark: "parcial")

    static let sk = ForkMacBackupAgentHealthStrings(
        repairing: "macOS zastavil agenta — znova sa registruje…",
        reauthorize: "macOS zastavil agenta — znova ho povoľte",
        openLoginItems: "Otvoriť položky po prihlásení",
        partialMark: "čiastočná")

    static let de = ForkMacBackupAgentHealthStrings(
        repairing: "Agent von macOS gestoppt — wird neu registriert …",
        reauthorize: "Agent von macOS gestoppt — erneut erlauben",
        openLoginItems: "Anmeldeobjekte öffnen",
        partialMark: "unvollständig")

    static let fr = ForkMacBackupAgentHealthStrings(
        repairing: "Agent arrêté par macOS — réenregistrement…",
        reauthorize: "Agent arrêté par macOS — à réautoriser",
        openLoginItems: "Ouvrir les éléments de connexion",
        partialMark: "partielle")

    static let it = ForkMacBackupAgentHealthStrings(
        repairing: "Agente fermato da macOS — nuova registrazione…",
        reauthorize: "Agente fermato da macOS — consentilo di nuovo",
        openLoginItems: "Apri Elementi login",
        partialMark: "parziale")

    static let ja = ForkMacBackupAgentHealthStrings(
        repairing: "macOSがエージェントを停止 — 再登録中…",
        reauthorize: "macOSがエージェントを停止 — 再度許可してください",
        openLoginItems: "ログイン項目を開く",
        partialMark: "一部のみ")

    static let ko = ForkMacBackupAgentHealthStrings(
        repairing: "macOS가 에이전트를 중지함 — 다시 등록하는 중…",
        reauthorize: "macOS가 에이전트를 중지함 — 다시 허용하세요",
        openLoginItems: "로그인 항목 열기",
        partialMark: "일부")

    static let uk = ForkMacBackupAgentHealthStrings(
        repairing: "macOS зупинила агента — повторна реєстрація…",
        reauthorize: "macOS зупинила агента — дозвольте його знову",
        openLoginItems: "Відкрити об’єкти входу",
        partialMark: "часткова")

    static let zhHans = ForkMacBackupAgentHealthStrings(
        repairing: "代理已被 macOS 停止 — 正在重新注册…",
        reauthorize: "代理已被 macOS 停止 — 请重新允许",
        openLoginItems: "打开登录项",
        partialMark: "部分")

    static let zhTW = ForkMacBackupAgentHealthStrings(
        repairing: "代理程式已被 macOS 停止 — 正在重新註冊…",
        reauthorize: "代理程式已被 macOS 停止 — 請重新允許",
        openLoginItems: "打開登入項目",
        partialMark: "部分")

    static let zhHK = ForkMacBackupAgentHealthStrings(
        repairing: "代理程式已被 macOS 停止 — 正在重新註冊…",
        reauthorize: "代理程式已被 macOS 停止 — 請重新允許",
        openLoginItems: "打開登入項目",
        partialMark: "部分")
}
