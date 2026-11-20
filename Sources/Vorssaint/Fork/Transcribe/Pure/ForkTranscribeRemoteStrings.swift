// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// File Transcription's texts for the remote engines (the Studio, an
/// OpenAI-compatible API) and the voices. Same contract as
/// `ForkTranscribeStrings`.
struct ForkTranscribeRemoteStrings {
    let engineStudio: String
    let engineStudioDetail: String
    let engineOpenAI: String
    let engineOpenAIDetail: String
    let addressTitle: String
    let tokenTitle: String
    let keyTitle: String
    let modelTitle: String
    let secretSaved: String
    let secretPlaceholder: String
    let save: String
    let forget: String
    let importToken: String
    let importFailed: String
    let test: String
    let testOK: String
    let testWaking: String
    let speakersTitle: String
    let speakersAuto: String
    let speakersOne: String
    /// %d: people.
    let speakersCount: String
    let speakersLocalNote: String
    let voicesTitle: String
    let voicesHint: String
    let stagePreparing: String
    let stageWaking: String
    let stageUploading: String
    let stageWaitingForServer: String
    let stageRemoteQueued: String
    let failureNotConfigured: String
    let failureUnauthorized: String
    let failureNetwork: String
    let failureServerBusy: String
    let failureTooLarge: String
    let failureTooLong: String
    let failureRemoteFailed: String
    /// %1$@: the length, %2$@: the date, %3$@: the engine.
    let fileSummaryRemote: String
    let engineNameStudio: String
    /// %@: the model.
    let engineNameOpenAI: String
    let tryOnStudio: String

    static func strings(_ language: AppLanguage) -> ForkTranscribeRemoteStrings {
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

    /// Nil for a failure the local strings say.
    func failure(_ failure: ForkTranscribeFailure) -> String? {
        switch failure {
        case .notConfigured: return failureNotConfigured
        case .unauthorized: return failureUnauthorized
        case .network: return failureNetwork
        case .serverBusy: return failureServerBusy
        case .tooLarge: return failureTooLarge
        case .tooLong: return failureTooLong
        case .remoteFailed: return failureRemoteFailed
        default: return nil
        }
    }

    func speakers(_ stored: String) -> String {
        switch ForkTranscribeSpeakers.most(stored) {
        case nil: return speakersAuto
        case 1: return speakersOne
        case let count?: return String(format: speakersCount, count)
        }
    }
}

extension ForkTranscribeRemoteStrings {
    static let enUS = ForkTranscribeRemoteStrings(
        engineStudio: "Studio · with voices",
        engineStudioDetail: "Sent to the Studio over Tailscale and transcribed by Whisper, which tells who speaks. A Studio that slept wakes in 30 to 60 seconds.",
        engineOpenAI: "OpenAI-compatible API",
        engineOpenAIDetail: "Sent to the service below: OpenAI, Groq, or a Whisper server of your own. The sound leaves this Mac.",
        addressTitle: "Address",
        tokenTitle: "Token",
        keyTitle: "API key",
        modelTitle: "Model",
        secretSaved: "Saved",
        secretPlaceholder: "Paste it here",
        save: "Save",
        forget: "Forget",
        importToken: "Use the transcrire tool’s token",
        importFailed: "No token from the transcrire tool on this Mac",
        test: "Test",
        testOK: "Connected",
        testWaking: "Connected · the transcriber is waking up",
        speakersTitle: "Who speaks",
        speakersAuto: "Find the voices",
        speakersOne: "One person (monologue)",
        speakersCount: "%d people at most",
        speakersLocalNote: "On this Mac, voices are not told apart: choose the Studio for that.",
        voicesTitle: "Voices",
        voicesHint: "Name each voice: the files are written again with its name.",
        stagePreparing: "Preparing the sound",
        stageWaking: "Waking the Studio (30 to 60 s)",
        stageUploading: "Sending",
        stageWaitingForServer: "Server busy, trying again in a moment",
        stageRemoteQueued: "Waiting its turn on the server",
        failureNotConfigured: "Set its address and key on this page",
        failureUnauthorized: "The server refused the token or the key",
        failureNetwork: "The server could not be reached (is Tailscale on?)",
        failureServerBusy: "The server stayed busy: try again later",
        failureTooLarge: "Too big for the server",
        failureTooLong: "Over 2 hours of sound: transcribe it on this Mac",
        failureRemoteFailed: "The server could not transcribe it",
        fileSummaryRemote: "%1$@ · transcribed on %2$@ with %3$@",
        engineNameStudio: "the Studio (Whisper)",
        engineNameOpenAI: "an OpenAI-compatible API (%@)",
        tryOnStudio: "Try on the Studio"
    )

    static let fr = ForkTranscribeRemoteStrings(
        engineStudio: "Studio · avec les voix",
        engineStudioDetail: "Envoyé au Studio par Tailscale et transcrit par Whisper, qui dit qui parle. Un Studio endormi se réveille en 30 à 60 secondes.",
        engineOpenAI: "API compatible OpenAI",
        engineOpenAIDetail: "Envoyé au service ci-dessous : OpenAI, Groq, ou un serveur Whisper à toi. Le son sort du Mac.",
        addressTitle: "Adresse",
        tokenTitle: "Jeton",
        keyTitle: "Clé d’API",
        modelTitle: "Modèle",
        secretSaved: "Enregistré",
        secretPlaceholder: "Colle-le ici",
        save: "Enregistrer",
        forget: "Oublier",
        importToken: "Reprendre le jeton de l’outil transcrire",
        importFailed: "Aucun jeton de l’outil transcrire sur ce Mac",
        test: "Tester",
        testOK: "Connecté",
        testWaking: "Connecté · le transcripteur se réveille",
        speakersTitle: "Qui parle",
        speakersAuto: "Trouver les voix",
        speakersOne: "Une seule personne (monologue)",
        speakersCount: "%d personnes au plus",
        speakersLocalNote: "Sur ce Mac, les voix ne sont pas distinguées : choisis le Studio pour ça.",
        voicesTitle: "Voix",
        voicesHint: "Nomme chaque voix : les fichiers sont réécrits avec son nom.",
        stagePreparing: "Préparation du son",
        stageWaking: "Réveil du Studio (30 à 60 s)",
        stageUploading: "Envoi",
        stageWaitingForServer: "Serveur occupé, nouvel essai dans un instant",
        stageRemoteQueued: "Attend son tour sur le serveur",
        failureNotConfigured: "Indique son adresse et sa clé sur cette page",
        failureUnauthorized: "Le serveur a refusé le jeton ou la clé",
        failureNetwork: "Serveur injoignable (Tailscale est-il connecté ?)",
        failureServerBusy: "Le serveur est resté occupé : réessaie plus tard",
        failureTooLarge: "Trop gros pour le serveur",
        failureTooLong: "Plus de 2 h de son : transcris-le sur ce Mac",
        failureRemoteFailed: "Le serveur n’a pas pu le transcrire",
        fileSummaryRemote: "%1$@ · transcrit le %2$@ avec %3$@",
        engineNameStudio: "le Studio (Whisper)",
        engineNameOpenAI: "une API compatible OpenAI (%@)",
        tryOnStudio: "Essayer au Studio"
    )

    static let ptBR = ForkTranscribeRemoteStrings(
        engineStudio: "Studio · com as vozes",
        engineStudioDetail: "Enviado ao Studio pelo Tailscale e transcrito pelo Whisper, que diz quem fala. Um Studio adormecido acorda em 30 a 60 segundos.",
        engineOpenAI: "API compatível com OpenAI",
        engineOpenAIDetail: "Enviado ao serviço abaixo: OpenAI, Groq ou um servidor Whisper seu. O som sai deste Mac.",
        addressTitle: "Endereço",
        tokenTitle: "Token",
        keyTitle: "Chave de API",
        modelTitle: "Modelo",
        secretSaved: "Salvo",
        secretPlaceholder: "Cole aqui",
        save: "Salvar",
        forget: "Esquecer",
        importToken: "Usar o token da ferramenta transcrire",
        importFailed: "Nenhum token da ferramenta transcrire neste Mac",
        test: "Testar",
        testOK: "Conectado",
        testWaking: "Conectado · o transcritor está acordando",
        speakersTitle: "Quem fala",
        speakersAuto: "Encontrar as vozes",
        speakersOne: "Uma só pessoa (monólogo)",
        speakersCount: "%d pessoas no máximo",
        speakersLocalNote: "Neste Mac as vozes não são distinguidas: escolha o Studio para isso.",
        voicesTitle: "Vozes",
        voicesHint: "Dê um nome a cada voz: os arquivos são regravados com ele.",
        stagePreparing: "Preparando o som",
        stageWaking: "Acordando o Studio (30 a 60 s)",
        stageUploading: "Enviando",
        stageWaitingForServer: "Servidor ocupado, nova tentativa em instantes",
        stageRemoteQueued: "Aguardando a vez no servidor",
        failureNotConfigured: "Informe o endereço e a chave nesta página",
        failureUnauthorized: "O servidor recusou o token ou a chave",
        failureNetwork: "Servidor inacessível (o Tailscale está ligado?)",
        failureServerBusy: "O servidor continuou ocupado: tente mais tarde",
        failureTooLarge: "Grande demais para o servidor",
        failureTooLong: "Mais de 2 h de som: transcreva neste Mac",
        failureRemoteFailed: "O servidor não conseguiu transcrever",
        fileSummaryRemote: "%1$@ · transcrito em %2$@ com %3$@",
        engineNameStudio: "o Studio (Whisper)",
        engineNameOpenAI: "uma API compatível com OpenAI (%@)",
        tryOnStudio: "Tentar no Studio"
    )

    static let tr = ForkTranscribeRemoteStrings(
        engineStudio: "Studio · seslerle",
        engineStudioDetail: "Tailscale üzerinden Studio’ya gönderilir ve kimin konuştuğunu da söyleyen Whisper ile dökülür. Uyuyan Studio 30–60 saniyede uyanır.",
        engineOpenAI: "OpenAI uyumlu API",
        engineOpenAIDetail: "Aşağıdaki servise gönderilir: OpenAI, Groq veya kendi Whisper sunucunuz. Ses bu Mac’ten çıkar.",
        addressTitle: "Adres",
        tokenTitle: "Belirteç",
        keyTitle: "API anahtarı",
        modelTitle: "Model",
        secretSaved: "Kaydedildi",
        secretPlaceholder: "Buraya yapıştırın",
        save: "Kaydet",
        forget: "Unut",
        importToken: "transcrire aracının belirtecini kullan",
        importFailed: "Bu Mac’te transcrire aracının belirteci yok",
        test: "Dene",
        testOK: "Bağlandı",
        testWaking: "Bağlandı · döküm motoru uyanıyor",
        speakersTitle: "Kim konuşuyor",
        speakersAuto: "Sesleri bul",
        speakersOne: "Tek kişi (monolog)",
        speakersCount: "En çok %d kişi",
        speakersLocalNote: "Bu Mac’te sesler ayırt edilmez: bunun için Studio’yu seçin.",
        voicesTitle: "Sesler",
        voicesHint: "Her sese bir ad verin: dosyalar bu adla yeniden yazılır.",
        stagePreparing: "Ses hazırlanıyor",
        stageWaking: "Studio uyandırılıyor (30–60 sn)",
        stageUploading: "Gönderiliyor",
        stageWaitingForServer: "Sunucu meşgul, birazdan yeniden denenecek",
        stageRemoteQueued: "Sunucuda sırasını bekliyor",
        failureNotConfigured: "Bu sayfada adresini ve anahtarını girin",
        failureUnauthorized: "Sunucu belirteci ya da anahtarı reddetti",
        failureNetwork: "Sunucuya ulaşılamadı (Tailscale açık mı?)",
        failureServerBusy: "Sunucu meşgul kaldı: daha sonra yeniden deneyin",
        failureTooLarge: "Sunucu için fazla büyük",
        failureTooLong: "2 saatten uzun ses: bu Mac’te dökün",
        failureRemoteFailed: "Sunucu yazıya dökemedi",
        fileSummaryRemote: "%1$@ · %2$@ tarihinde %3$@ ile döküldü",
        engineNameStudio: "Studio (Whisper)",
        engineNameOpenAI: "OpenAI uyumlu bir API (%@)",
        tryOnStudio: "Studio’da dene"
    )

    static let ru = ForkTranscribeRemoteStrings(
        engineStudio: "Studio · с голосами",
        engineStudioDetail: "Отправляется на Studio через Tailscale и расшифровывается Whisper, который различает говорящих. Спящий Studio просыпается за 30–60 секунд.",
        engineOpenAI: "API, совместимый с OpenAI",
        engineOpenAIDetail: "Отправляется в сервис ниже: OpenAI, Groq или ваш собственный сервер Whisper. Звук покидает этот Mac.",
        addressTitle: "Адрес",
        tokenTitle: "Токен",
        keyTitle: "Ключ API",
        modelTitle: "Модель",
        secretSaved: "Сохранено",
        secretPlaceholder: "Вставьте сюда",
        save: "Сохранить",
        forget: "Забыть",
        importToken: "Взять токен инструмента transcrire",
        importFailed: "На этом Mac нет токена инструмента transcrire",
        test: "Проверить",
        testOK: "Подключено",
        testWaking: "Подключено · расшифровщик просыпается",
        speakersTitle: "Кто говорит",
        speakersAuto: "Найти голоса",
        speakersOne: "Один человек (монолог)",
        speakersCount: "Не больше %d человек",
        speakersLocalNote: "На этом Mac голоса не различаются: для этого выберите Studio.",
        voicesTitle: "Голоса",
        voicesHint: "Назовите каждый голос: файлы будут перезаписаны с этим именем.",
        stagePreparing: "Подготовка звука",
        stageWaking: "Пробуждение Studio (30–60 с)",
        stageUploading: "Отправка",
        stageWaitingForServer: "Сервер занят, скоро новая попытка",
        stageRemoteQueued: "Ждёт очереди на сервере",
        failureNotConfigured: "Укажите адрес и ключ на этой странице",
        failureUnauthorized: "Сервер отклонил токен или ключ",
        failureNetwork: "Сервер недоступен (включён ли Tailscale?)",
        failureServerBusy: "Сервер остался занят: повторите позже",
        failureTooLarge: "Слишком большой файл для сервера",
        failureTooLong: "Больше 2 ч звука: расшифруйте на этом Mac",
        failureRemoteFailed: "Сервер не смог расшифровать",
        fileSummaryRemote: "%1$@ · расшифровано %2$@ с помощью %3$@",
        engineNameStudio: "Studio (Whisper)",
        engineNameOpenAI: "API, совместимого с OpenAI (%@)",
        tryOnStudio: "Попробовать на Studio"
    )

    static let es = ForkTranscribeRemoteStrings(
        engineStudio: "Studio · con las voces",
        engineStudioDetail: "Se envía al Studio por Tailscale y lo transcribe Whisper, que dice quién habla. Un Studio dormido despierta en 30 a 60 segundos.",
        engineOpenAI: "API compatible con OpenAI",
        engineOpenAIDetail: "Se envía al servicio de abajo: OpenAI, Groq o un servidor Whisper propio. El sonido sale de este Mac.",
        addressTitle: "Dirección",
        tokenTitle: "Token",
        keyTitle: "Clave de API",
        modelTitle: "Modelo",
        secretSaved: "Guardado",
        secretPlaceholder: "Pégalo aquí",
        save: "Guardar",
        forget: "Olvidar",
        importToken: "Usar el token de la herramienta transcrire",
        importFailed: "Ningún token de la herramienta transcrire en este Mac",
        test: "Probar",
        testOK: "Conectado",
        testWaking: "Conectado · el transcriptor se está despertando",
        speakersTitle: "Quién habla",
        speakersAuto: "Encontrar las voces",
        speakersOne: "Una sola persona (monólogo)",
        speakersCount: "%d personas como máximo",
        speakersLocalNote: "En este Mac no se distinguen las voces: elige el Studio para eso.",
        voicesTitle: "Voces",
        voicesHint: "Pon nombre a cada voz: los archivos se reescriben con él.",
        stagePreparing: "Preparando el sonido",
        stageWaking: "Despertando el Studio (30 a 60 s)",
        stageUploading: "Enviando",
        stageWaitingForServer: "Servidor ocupado, nuevo intento en un momento",
        stageRemoteQueued: "Esperando su turno en el servidor",
        failureNotConfigured: "Indica su dirección y su clave en esta página",
        failureUnauthorized: "El servidor rechazó el token o la clave",
        failureNetwork: "Servidor inalcanzable (¿está Tailscale conectado?)",
        failureServerBusy: "El servidor siguió ocupado: inténtalo más tarde",
        failureTooLarge: "Demasiado grande para el servidor",
        failureTooLong: "Más de 2 h de sonido: transcríbelo en este Mac",
        failureRemoteFailed: "El servidor no pudo transcribirlo",
        fileSummaryRemote: "%1$@ · transcrito el %2$@ con %3$@",
        engineNameStudio: "el Studio (Whisper)",
        engineNameOpenAI: "una API compatible con OpenAI (%@)",
        tryOnStudio: "Probar en el Studio"
    )

    static let sk = ForkTranscribeRemoteStrings(
        engineStudio: "Studio · s hlasmi",
        engineStudioDetail: "Odošle sa do Studia cez Tailscale a prepíše ho Whisper, ktorý povie, kto hovorí. Uspaté Studio sa zobudí za 30 až 60 sekúnd.",
        engineOpenAI: "API kompatibilné s OpenAI",
        engineOpenAIDetail: "Odošle sa do služby nižšie: OpenAI, Groq alebo váš vlastný server Whisper. Zvuk opustí tento Mac.",
        addressTitle: "Adresa",
        tokenTitle: "Token",
        keyTitle: "Kľúč API",
        modelTitle: "Model",
        secretSaved: "Uložené",
        secretPlaceholder: "Vložte ho sem",
        save: "Uložiť",
        forget: "Zabudnúť",
        importToken: "Použiť token nástroja transcrire",
        importFailed: "Na tomto Macu nie je token nástroja transcrire",
        test: "Otestovať",
        testOK: "Pripojené",
        testWaking: "Pripojené · prepisovač sa prebúdza",
        speakersTitle: "Kto hovorí",
        speakersAuto: "Nájsť hlasy",
        speakersOne: "Jedna osoba (monológ)",
        speakersCount: "Najviac %d osôb",
        speakersLocalNote: "Na tomto Macu sa hlasy nerozlišujú: na to vyberte Studio.",
        voicesTitle: "Hlasy",
        voicesHint: "Pomenujte každý hlas: súbory sa prepíšu s jeho menom.",
        stagePreparing: "Pripravuje sa zvuk",
        stageWaking: "Prebúdza sa Studio (30 až 60 s)",
        stageUploading: "Odosiela sa",
        stageWaitingForServer: "Server je zaneprázdnený, o chvíľu nový pokus",
        stageRemoteQueued: "Čaká na rad na serveri",
        failureNotConfigured: "Zadajte jeho adresu a kľúč na tejto stránke",
        failureUnauthorized: "Server odmietol token alebo kľúč",
        failureNetwork: "Server je nedostupný (je Tailscale pripojený?)",
        failureServerBusy: "Server zostal zaneprázdnený: skúste to neskôr",
        failureTooLarge: "Príliš veľké pre server",
        failureTooLong: "Viac ako 2 h zvuku: prepíšte ho na tomto Macu",
        failureRemoteFailed: "Server to nedokázal prepísať",
        fileSummaryRemote: "%1$@ · prepísané %2$@ pomocou %3$@",
        engineNameStudio: "Studia (Whisper)",
        engineNameOpenAI: "API kompatibilného s OpenAI (%@)",
        tryOnStudio: "Skúsiť v Studiu"
    )

    static let de = ForkTranscribeRemoteStrings(
        engineStudio: "Studio · mit Stimmen",
        engineStudioDetail: "Über Tailscale ans Studio gesendet und von Whisper transkribiert, das erkennt, wer spricht. Ein schlafendes Studio wacht in 30 bis 60 Sekunden auf.",
        engineOpenAI: "OpenAI-kompatible API",
        engineOpenAIDetail: "An den Dienst unten gesendet: OpenAI, Groq oder ein eigener Whisper-Server. Der Ton verlässt diesen Mac.",
        addressTitle: "Adresse",
        tokenTitle: "Token",
        keyTitle: "API-Schlüssel",
        modelTitle: "Modell",
        secretSaved: "Gespeichert",
        secretPlaceholder: "Hier einfügen",
        save: "Speichern",
        forget: "Vergessen",
        importToken: "Token des Tools transcrire übernehmen",
        importFailed: "Kein Token des Tools transcrire auf diesem Mac",
        test: "Testen",
        testOK: "Verbunden",
        testWaking: "Verbunden · der Transkriptor wacht auf",
        speakersTitle: "Wer spricht",
        speakersAuto: "Stimmen finden",
        speakersOne: "Eine Person (Monolog)",
        speakersCount: "Höchstens %d Personen",
        speakersLocalNote: "Auf diesem Mac werden Stimmen nicht unterschieden: Wähle dafür das Studio.",
        voicesTitle: "Stimmen",
        voicesHint: "Gib jeder Stimme einen Namen: Die Dateien werden damit neu geschrieben.",
        stagePreparing: "Ton wird vorbereitet",
        stageWaking: "Studio wird geweckt (30 bis 60 s)",
        stageUploading: "Wird gesendet",
        stageWaitingForServer: "Server ausgelastet, gleich neuer Versuch",
        stageRemoteQueued: "Wartet auf dem Server, bis es dran ist",
        failureNotConfigured: "Gib Adresse und Schlüssel auf dieser Seite an",
        failureUnauthorized: "Der Server hat Token oder Schlüssel abgelehnt",
        failureNetwork: "Server nicht erreichbar (ist Tailscale verbunden?)",
        failureServerBusy: "Der Server blieb ausgelastet: versuch es später",
        failureTooLarge: "Zu groß für den Server",
        failureTooLong: "Über 2 Std. Ton: auf diesem Mac transkribieren",
        failureRemoteFailed: "Der Server konnte es nicht transkribieren",
        fileSummaryRemote: "%1$@ · transkribiert am %2$@ mit %3$@",
        engineNameStudio: "dem Studio (Whisper)",
        engineNameOpenAI: "einer OpenAI-kompatiblen API (%@)",
        tryOnStudio: "Im Studio versuchen"
    )

    static let it = ForkTranscribeRemoteStrings(
        engineStudio: "Studio · con le voci",
        engineStudioDetail: "Inviato allo Studio tramite Tailscale e trascritto da Whisper, che dice chi parla. Uno Studio addormentato si sveglia in 30-60 secondi.",
        engineOpenAI: "API compatibile con OpenAI",
        engineOpenAIDetail: "Inviato al servizio qui sotto: OpenAI, Groq o un tuo server Whisper. L’audio esce da questo Mac.",
        addressTitle: "Indirizzo",
        tokenTitle: "Token",
        keyTitle: "Chiave API",
        modelTitle: "Modello",
        secretSaved: "Salvato",
        secretPlaceholder: "Incollalo qui",
        save: "Salva",
        forget: "Dimentica",
        importToken: "Usa il token dello strumento transcrire",
        importFailed: "Nessun token dello strumento transcrire su questo Mac",
        test: "Prova",
        testOK: "Connesso",
        testWaking: "Connesso · il trascrittore si sta svegliando",
        speakersTitle: "Chi parla",
        speakersAuto: "Trova le voci",
        speakersOne: "Una sola persona (monologo)",
        speakersCount: "Al massimo %d persone",
        speakersLocalNote: "Su questo Mac le voci non vengono distinte: scegli lo Studio per questo.",
        voicesTitle: "Voci",
        voicesHint: "Dai un nome a ogni voce: i file vengono riscritti con quel nome.",
        stagePreparing: "Preparazione dell’audio",
        stageWaking: "Risveglio dello Studio (30-60 s)",
        stageUploading: "Invio",
        stageWaitingForServer: "Server occupato, nuovo tentativo tra poco",
        stageRemoteQueued: "In attesa del turno sul server",
        failureNotConfigured: "Indica indirizzo e chiave in questa pagina",
        failureUnauthorized: "Il server ha rifiutato il token o la chiave",
        failureNetwork: "Server irraggiungibile (Tailscale è connesso?)",
        failureServerBusy: "Il server è rimasto occupato: riprova più tardi",
        failureTooLarge: "Troppo grande per il server",
        failureTooLong: "Oltre 2 ore di audio: trascrivilo su questo Mac",
        failureRemoteFailed: "Il server non è riuscito a trascriverlo",
        fileSummaryRemote: "%1$@ · trascritto il %2$@ con %3$@",
        engineNameStudio: "lo Studio (Whisper)",
        engineNameOpenAI: "un’API compatibile con OpenAI (%@)",
        tryOnStudio: "Prova sullo Studio"
    )

    static let ja = ForkTranscribeRemoteStrings(
        engineStudio: "Studio · 話者付き",
        engineStudioDetail: "Tailscale 経由で Studio に送り、話者も区別する Whisper で文字起こしします。スリープ中の Studio は 30〜60 秒で起動します。",
        engineOpenAI: "OpenAI 互換 API",
        engineOpenAIDetail: "下のサービス（OpenAI、Groq、自前の Whisper サーバ）に送信します。音声はこのMacの外に出ます。",
        addressTitle: "アドレス",
        tokenTitle: "トークン",
        keyTitle: "API キー",
        modelTitle: "モデル",
        secretSaved: "保存済み",
        secretPlaceholder: "ここにペースト",
        save: "保存",
        forget: "削除",
        importToken: "transcrire ツールのトークンを使う",
        importFailed: "このMacに transcrire ツールのトークンがありません",
        test: "テスト",
        testOK: "接続しました",
        testWaking: "接続しました · 文字起こしエンジンを起動中",
        speakersTitle: "話者",
        speakersAuto: "話者を検出",
        speakersOne: "1人（独話）",
        speakersCount: "最大 %d 人",
        speakersLocalNote: "このMacでは話者を区別しません。区別するには Studio を選択してください。",
        voicesTitle: "話者",
        voicesHint: "各話者に名前を付けると、その名前でファイルが書き直されます。",
        stagePreparing: "音声を準備中",
        stageWaking: "Studio を起動中（30〜60 秒）",
        stageUploading: "送信中",
        stageWaitingForServer: "サーバが混雑中。まもなく再試行します",
        stageRemoteQueued: "サーバで順番待ち",
        failureNotConfigured: "このページでアドレスとキーを設定してください",
        failureUnauthorized: "サーバがトークンまたはキーを拒否しました",
        failureNetwork: "サーバに接続できません（Tailscale は接続されていますか？）",
        failureServerBusy: "サーバが混雑したままです。あとでもう一度お試しください",
        failureTooLarge: "サーバには大きすぎます",
        failureTooLong: "2時間を超える音声です。このMacで文字起こししてください",
        failureRemoteFailed: "サーバで文字起こしできませんでした",
        fileSummaryRemote: "%1$@ · %2$@に%3$@で文字起こし",
        engineNameStudio: "Studio（Whisper）",
        engineNameOpenAI: "OpenAI 互換 API（%@）",
        tryOnStudio: "Studio で試す"
    )

    static let ko = ForkTranscribeRemoteStrings(
        engineStudio: "Studio · 화자 포함",
        engineStudioDetail: "Tailscale로 Studio에 보내 화자도 구분하는 Whisper로 받아씁니다. 잠든 Studio는 30~60초 후 깨어납니다.",
        engineOpenAI: "OpenAI 호환 API",
        engineOpenAIDetail: "아래 서비스(OpenAI, Groq, 직접 운영하는 Whisper 서버)로 보냅니다. 소리가 이 Mac 밖으로 나갑니다.",
        addressTitle: "주소",
        tokenTitle: "토큰",
        keyTitle: "API 키",
        modelTitle: "모델",
        secretSaved: "저장됨",
        secretPlaceholder: "여기에 붙여넣기",
        save: "저장",
        forget: "삭제",
        importToken: "transcrire 도구의 토큰 사용",
        importFailed: "이 Mac에 transcrire 도구의 토큰이 없습니다",
        test: "테스트",
        testOK: "연결됨",
        testWaking: "연결됨 · 받아쓰기 엔진이 깨어나는 중",
        speakersTitle: "화자",
        speakersAuto: "화자 찾기",
        speakersOne: "한 사람(독백)",
        speakersCount: "최대 %d명",
        speakersLocalNote: "이 Mac에서는 화자를 구분하지 않습니다. 구분하려면 Studio를 선택하세요.",
        voicesTitle: "화자",
        voicesHint: "각 화자에 이름을 붙이면 그 이름으로 파일을 다시 씁니다.",
        stagePreparing: "소리 준비 중",
        stageWaking: "Studio 깨우는 중(30~60초)",
        stageUploading: "보내는 중",
        stageWaitingForServer: "서버가 바쁩니다. 곧 다시 시도합니다",
        stageRemoteQueued: "서버에서 차례를 기다리는 중",
        failureNotConfigured: "이 페이지에서 주소와 키를 입력하세요",
        failureUnauthorized: "서버가 토큰 또는 키를 거부했습니다",
        failureNetwork: "서버에 연결할 수 없습니다(Tailscale이 켜져 있나요?)",
        failureServerBusy: "서버가 계속 바쁩니다. 나중에 다시 시도하세요",
        failureTooLarge: "서버에 비해 너무 큽니다",
        failureTooLong: "2시간이 넘는 소리입니다. 이 Mac에서 받아쓰세요",
        failureRemoteFailed: "서버가 받아쓰지 못했습니다",
        fileSummaryRemote: "%1$@ · %2$@에 %3$@(으)로 받아씀",
        engineNameStudio: "Studio(Whisper)",
        engineNameOpenAI: "OpenAI 호환 API(%@)",
        tryOnStudio: "Studio에서 시도"
    )

    static let uk = ForkTranscribeRemoteStrings(
        engineStudio: "Studio · з голосами",
        engineStudioDetail: "Надсилається на Studio через Tailscale і розшифровується Whisper, який розрізняє мовців. Сплячий Studio прокидається за 30–60 секунд.",
        engineOpenAI: "API, сумісний з OpenAI",
        engineOpenAIDetail: "Надсилається до сервісу нижче: OpenAI, Groq або ваш власний сервер Whisper. Звук залишає цей Mac.",
        addressTitle: "Адреса",
        tokenTitle: "Токен",
        keyTitle: "Ключ API",
        modelTitle: "Модель",
        secretSaved: "Збережено",
        secretPlaceholder: "Вставте сюди",
        save: "Зберегти",
        forget: "Забути",
        importToken: "Узяти токен інструмента transcrire",
        importFailed: "На цьому Mac немає токена інструмента transcrire",
        test: "Перевірити",
        testOK: "Під’єднано",
        testWaking: "Під’єднано · розшифровувач прокидається",
        speakersTitle: "Хто говорить",
        speakersAuto: "Знайти голоси",
        speakersOne: "Одна людина (монолог)",
        speakersCount: "Не більше %d осіб",
        speakersLocalNote: "На цьому Mac голоси не розрізняються: для цього виберіть Studio.",
        voicesTitle: "Голоси",
        voicesHint: "Назвіть кожен голос: файли буде перезаписано з цим іменем.",
        stagePreparing: "Підготовка звуку",
        stageWaking: "Пробудження Studio (30–60 с)",
        stageUploading: "Надсилання",
        stageWaitingForServer: "Сервер зайнятий, невдовзі нова спроба",
        stageRemoteQueued: "Чекає черги на сервері",
        failureNotConfigured: "Вкажіть адресу та ключ на цій сторінці",
        failureUnauthorized: "Сервер відхилив токен або ключ",
        failureNetwork: "Сервер недоступний (чи під’єднано Tailscale?)",
        failureServerBusy: "Сервер лишився зайнятим: спробуйте пізніше",
        failureTooLarge: "Завеликий для сервера",
        failureTooLong: "Понад 2 год звуку: розшифруйте на цьому Mac",
        failureRemoteFailed: "Сервер не зміг розшифрувати",
        fileSummaryRemote: "%1$@ · розшифровано %2$@ за допомогою %3$@",
        engineNameStudio: "Studio (Whisper)",
        engineNameOpenAI: "API, сумісного з OpenAI (%@)",
        tryOnStudio: "Спробувати на Studio"
    )

    static let zhHans = ForkTranscribeRemoteStrings(
        engineStudio: "Studio · 区分说话人",
        engineStudioDetail: "通过 Tailscale 发送到 Studio，由能区分说话人的 Whisper 转写。休眠的 Studio 会在 30 到 60 秒内唤醒。",
        engineOpenAI: "兼容 OpenAI 的 API",
        engineOpenAIDetail: "发送到下方的服务：OpenAI、Groq 或你自己的 Whisper 服务器。声音会离开这台 Mac。",
        addressTitle: "地址",
        tokenTitle: "令牌",
        keyTitle: "API 密钥",
        modelTitle: "模型",
        secretSaved: "已保存",
        secretPlaceholder: "粘贴到这里",
        save: "保存",
        forget: "忘记",
        importToken: "使用 transcrire 工具的令牌",
        importFailed: "这台 Mac 上没有 transcrire 工具的令牌",
        test: "测试",
        testOK: "已连接",
        testWaking: "已连接 · 转写引擎正在唤醒",
        speakersTitle: "说话人",
        speakersAuto: "自动识别说话人",
        speakersOne: "一个人（独白）",
        speakersCount: "最多 %d 人",
        speakersLocalNote: "在这台 Mac 上不区分说话人：如需区分请选择 Studio。",
        voicesTitle: "说话人",
        voicesHint: "为每个说话人命名：文件会用这个名字重新写入。",
        stagePreparing: "正在准备声音",
        stageWaking: "正在唤醒 Studio（30 到 60 秒）",
        stageUploading: "正在发送",
        stageWaitingForServer: "服务器繁忙，稍后重试",
        stageRemoteQueued: "正在服务器上排队",
        failureNotConfigured: "请在此页面填写地址和密钥",
        failureUnauthorized: "服务器拒绝了令牌或密钥",
        failureNetwork: "无法连接服务器（Tailscale 是否已连接？）",
        failureServerBusy: "服务器一直繁忙：请稍后再试",
        failureTooLarge: "对服务器来说太大",
        failureTooLong: "超过 2 小时的声音：请在这台 Mac 上转写",
        failureRemoteFailed: "服务器无法转写",
        fileSummaryRemote: "%1$@ · %2$@ 用%3$@转写",
        engineNameStudio: "Studio（Whisper）",
        engineNameOpenAI: "兼容 OpenAI 的 API（%@）",
        tryOnStudio: "在 Studio 上尝试"
    )

    static let zhTW = ForkTranscribeRemoteStrings(
        engineStudio: "Studio · 區分說話者",
        engineStudioDetail: "透過 Tailscale 傳送到 Studio，由能區分說話者的 Whisper 轉寫。休眠的 Studio 會在 30 到 60 秒內喚醒。",
        engineOpenAI: "相容 OpenAI 的 API",
        engineOpenAIDetail: "傳送到下方的服務：OpenAI、Groq 或你自己的 Whisper 伺服器。聲音會離開這台 Mac。",
        addressTitle: "位址",
        tokenTitle: "權杖",
        keyTitle: "API 金鑰",
        modelTitle: "模型",
        secretSaved: "已儲存",
        secretPlaceholder: "貼到這裡",
        save: "儲存",
        forget: "忘記",
        importToken: "使用 transcrire 工具的權杖",
        importFailed: "這台 Mac 上沒有 transcrire 工具的權杖",
        test: "測試",
        testOK: "已連線",
        testWaking: "已連線 · 轉寫引擎正在喚醒",
        speakersTitle: "說話者",
        speakersAuto: "自動找出說話者",
        speakersOne: "一個人（獨白）",
        speakersCount: "最多 %d 人",
        speakersLocalNote: "在這台 Mac 上不區分說話者：如需區分請選擇 Studio。",
        voicesTitle: "說話者",
        voicesHint: "為每位說話者命名：檔案會以這個名字重新寫入。",
        stagePreparing: "正在準備聲音",
        stageWaking: "正在喚醒 Studio（30 到 60 秒）",
        stageUploading: "正在傳送",
        stageWaitingForServer: "伺服器忙碌，稍後重試",
        stageRemoteQueued: "正在伺服器上排隊",
        failureNotConfigured: "請在此頁面填寫位址和金鑰",
        failureUnauthorized: "伺服器拒絕了權杖或金鑰",
        failureNetwork: "無法連線伺服器（Tailscale 是否已連線？）",
        failureServerBusy: "伺服器一直忙碌：請稍後再試",
        failureTooLarge: "對伺服器來說太大",
        failureTooLong: "超過 2 小時的聲音：請在這台 Mac 上轉寫",
        failureRemoteFailed: "伺服器無法轉寫",
        fileSummaryRemote: "%1$@ · %2$@ 以%3$@轉寫",
        engineNameStudio: "Studio（Whisper）",
        engineNameOpenAI: "相容 OpenAI 的 API（%@）",
        tryOnStudio: "在 Studio 上嘗試"
    )

    static let zhHK = ForkTranscribeRemoteStrings(
        engineStudio: "Studio · 區分說話者",
        engineStudioDetail: "透過 Tailscale 傳送到 Studio，由能區分說話者的 Whisper 轉寫。休眠的 Studio 會在 30 到 60 秒內喚醒。",
        engineOpenAI: "相容 OpenAI 的 API",
        engineOpenAIDetail: "傳送到下方的服務：OpenAI、Groq 或你自己的 Whisper 伺服器。聲音會離開這部 Mac。",
        addressTitle: "位址",
        tokenTitle: "權杖",
        keyTitle: "API 金鑰",
        modelTitle: "模型",
        secretSaved: "已儲存",
        secretPlaceholder: "貼到這裡",
        save: "儲存",
        forget: "忘記",
        importToken: "使用 transcrire 工具的權杖",
        importFailed: "這部 Mac 上沒有 transcrire 工具的權杖",
        test: "測試",
        testOK: "已連線",
        testWaking: "已連線 · 轉寫引擎正在喚醒",
        speakersTitle: "說話者",
        speakersAuto: "自動找出說話者",
        speakersOne: "一個人（獨白）",
        speakersCount: "最多 %d 人",
        speakersLocalNote: "在這部 Mac 上不區分說話者：如需區分請選擇 Studio。",
        voicesTitle: "說話者",
        voicesHint: "為每位說話者命名：檔案會以這個名字重新寫入。",
        stagePreparing: "正在準備聲音",
        stageWaking: "正在喚醒 Studio（30 到 60 秒）",
        stageUploading: "正在傳送",
        stageWaitingForServer: "伺服器忙碌，稍後重試",
        stageRemoteQueued: "正在伺服器上排隊",
        failureNotConfigured: "請在此頁面填寫位址和金鑰",
        failureUnauthorized: "伺服器拒絕了權杖或金鑰",
        failureNetwork: "無法連線伺服器（Tailscale 是否已連線？）",
        failureServerBusy: "伺服器一直忙碌：請稍後再試",
        failureTooLarge: "對伺服器來說太大",
        failureTooLong: "超過 2 小時的聲音：請在這部 Mac 上轉寫",
        failureRemoteFailed: "伺服器無法轉寫",
        fileSummaryRemote: "%1$@ · %2$@ 以%3$@轉寫",
        engineNameStudio: "Studio（Whisper）",
        engineNameOpenAI: "相容 OpenAI 的 API（%@）",
        tryOnStudio: "在 Studio 上嘗試"
    )
}
