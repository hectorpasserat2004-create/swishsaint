// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// The Engine's own words: why installing the engine failed
/// (`ForkMacBackupEngineInstallFailure.title`), and the suffix of a restored
/// copy kept beside the original (« rapport (restauré).pdf »).
///
/// Same contract as `ForkMacBackupStrings`: memberwise init in declaration
/// order, one static per language, French with `\u{00A0}` before « : ; ! ? »
/// and typographic apostrophes.
struct ForkMacBackupEngineStrings {
    let installNetwork: String
    let installSpace: String
    let installChecksum: String
    let installExtract: String
    let installLaunch: String
    let installIO: String
    /// In parentheses after a restored copy's name; a file name, so no
    /// slash or colon.
    let restoredSuffix: String

    static func strings(_ language: AppLanguage) -> ForkMacBackupEngineStrings {
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

    /// « (restored) », the parenthesised suffix a kept-both copy carries.
    var restoredParenthesized: String { "(\(restoredSuffix))" }

    static let enUS = ForkMacBackupEngineStrings(
        installNetwork: "The download failed. Check the connection and try again.",
        installSpace: "Not enough free space on this Mac to install the engine.",
        installChecksum: "The downloaded file is not the expected engine. It was deleted.",
        installExtract: "The engine archive could not be unpacked.",
        installLaunch: "The engine does not start on this Mac, or is not signed by Kopia.",
        installIO: "The engine could not be written to the disk.",
        restoredSuffix: "restored"
    )

    static let fr = ForkMacBackupEngineStrings(
        installNetwork: "Le téléchargement a échoué. Vérifiez la connexion et réessayez.",
        installSpace: "Pas assez d’espace libre sur ce Mac pour installer le moteur.",
        installChecksum: "Le fichier téléchargé n’est pas le moteur attendu. Il a été supprimé.",
        installExtract: "L’archive du moteur n’a pas pu être décompressée.",
        installLaunch: "Le moteur ne démarre pas sur ce Mac, ou n’est pas signé par Kopia.",
        installIO: "Le moteur n’a pas pu être écrit sur le disque.",
        restoredSuffix: "restauré"
    )

    static let ptBR = ForkMacBackupEngineStrings(
        installNetwork: "O download falhou. Verifique a conexão e tente de novo.",
        installSpace: "Não há espaço livre suficiente neste Mac para instalar o motor.",
        installChecksum: "O arquivo baixado não é o motor esperado. Ele foi apagado.",
        installExtract: "Não foi possível descompactar o arquivo do motor.",
        installLaunch: "O motor não abre neste Mac ou não está assinado pela Kopia.",
        installIO: "Não foi possível gravar o motor no disco.",
        restoredSuffix: "restaurado"
    )

    static let tr = ForkMacBackupEngineStrings(
        installNetwork: "İndirme başarısız oldu. Bağlantıyı kontrol edip yeniden deneyin.",
        installSpace: "Bu Mac'te motoru yüklemek için yeterli boş alan yok.",
        installChecksum: "İndirilen dosya beklenen motor değil. Silindi.",
        installExtract: "Motor arşivi açılamadı.",
        installLaunch: "Motor bu Mac'te başlamıyor veya Kopia tarafından imzalanmamış.",
        installIO: "Motor diske yazılamadı.",
        restoredSuffix: "geri yüklendi"
    )

    static let ru = ForkMacBackupEngineStrings(
        installNetwork: "Загрузка не удалась. Проверьте подключение и повторите попытку.",
        installSpace: "На этом Mac недостаточно места для установки движка.",
        installChecksum: "Загруженный файл не является ожидаемым движком. Он удалён.",
        installExtract: "Не удалось распаковать архив движка.",
        installLaunch: "Движок не запускается на этом Mac или не подписан Kopia.",
        installIO: "Не удалось записать движок на диск.",
        restoredSuffix: "восстановлено"
    )

    static let es = ForkMacBackupEngineStrings(
        installNetwork: "La descarga ha fallado. Comprueba la conexión y vuelve a intentarlo.",
        installSpace: "No hay espacio libre suficiente en este Mac para instalar el motor.",
        installChecksum: "El archivo descargado no es el motor esperado. Se ha eliminado.",
        installExtract: "No se ha podido descomprimir el archivo del motor.",
        installLaunch: "El motor no se inicia en este Mac o no está firmado por Kopia.",
        installIO: "No se ha podido escribir el motor en el disco.",
        restoredSuffix: "restaurado"
    )

    static let sk = ForkMacBackupEngineStrings(
        installNetwork: "Sťahovanie zlyhalo. Skontrolujte pripojenie a skúste to znova.",
        installSpace: "Na tomto Macu nie je dosť voľného miesta na inštaláciu nástroja.",
        installChecksum: "Stiahnutý súbor nie je očakávaný nástroj. Bol vymazaný.",
        installExtract: "Archív nástroja sa nepodarilo rozbaliť.",
        installLaunch: "Nástroj sa na tomto Macu nespustí alebo nie je podpísaný spoločnosťou Kopia.",
        installIO: "Nástroj sa nepodarilo zapísať na disk.",
        restoredSuffix: "obnovené"
    )

    static let de = ForkMacBackupEngineStrings(
        installNetwork: "Der Download ist fehlgeschlagen. Prüfe die Verbindung und versuche es erneut.",
        installSpace: "Auf diesem Mac ist nicht genug Platz frei, um das Modul zu installieren.",
        installChecksum: "Die geladene Datei ist nicht das erwartete Modul. Sie wurde gelöscht.",
        installExtract: "Das Archiv des Moduls konnte nicht entpackt werden.",
        installLaunch: "Das Modul startet auf diesem Mac nicht oder ist nicht von Kopia signiert.",
        installIO: "Das Modul konnte nicht auf die Festplatte geschrieben werden.",
        restoredSuffix: "wiederhergestellt"
    )

    static let it = ForkMacBackupEngineStrings(
        installNetwork: "Il download non è riuscito. Controlla la connessione e riprova.",
        installSpace: "Spazio libero insufficiente su questo Mac per installare il motore.",
        installChecksum: "Il file scaricato non è il motore previsto. È stato eliminato.",
        installExtract: "Impossibile decomprimere l’archivio del motore.",
        installLaunch: "Il motore non si avvia su questo Mac o non è firmato da Kopia.",
        installIO: "Impossibile scrivere il motore sul disco.",
        restoredSuffix: "ripristinato"
    )

    static let ja = ForkMacBackupEngineStrings(
        installNetwork: "ダウンロードに失敗しました。接続を確認して、もう一度お試しください。",
        installSpace: "このMacにはエンジンをインストールするための空き容量が足りません。",
        installChecksum: "ダウンロードしたファイルは想定したエンジンではありません。削除しました。",
        installExtract: "エンジンのアーカイブを展開できませんでした。",
        installLaunch: "エンジンがこのMacで起動しないか、Kopiaによって署名されていません。",
        installIO: "エンジンをディスクに書き込めませんでした。",
        restoredSuffix: "復元済み"
    )

    static let ko = ForkMacBackupEngineStrings(
        installNetwork: "다운로드에 실패했습니다. 연결을 확인하고 다시 시도하세요.",
        installSpace: "이 Mac에 엔진을 설치할 여유 공간이 부족합니다.",
        installChecksum: "다운로드한 파일이 예상한 엔진이 아닙니다. 삭제했습니다.",
        installExtract: "엔진 압축 파일을 풀 수 없습니다.",
        installLaunch: "엔진이 이 Mac에서 실행되지 않거나 Kopia의 서명이 없습니다.",
        installIO: "엔진을 디스크에 쓸 수 없습니다.",
        restoredSuffix: "복원됨"
    )

    static let uk = ForkMacBackupEngineStrings(
        installNetwork: "Не вдалося завантажити. Перевірте з’єднання та спробуйте ще раз.",
        installSpace: "На цьому Mac недостатньо місця, щоб установити рушій.",
        installChecksum: "Завантажений файл не є очікуваним рушієм. Його видалено.",
        installExtract: "Не вдалося розпакувати архів рушія.",
        installLaunch: "Рушій не запускається на цьому Mac або не підписаний Kopia.",
        installIO: "Не вдалося записати рушій на диск.",
        restoredSuffix: "відновлено"
    )

    static let zhHans = ForkMacBackupEngineStrings(
        installNetwork: "下载失败。请检查网络连接后重试。",
        installSpace: "这台 Mac 的可用空间不足，无法安装引擎。",
        installChecksum: "下载的文件不是预期的引擎，已删除。",
        installExtract: "无法解压引擎压缩包。",
        installLaunch: "引擎无法在这台 Mac 上启动，或未经 Kopia 签名。",
        installIO: "无法将引擎写入磁盘。",
        restoredSuffix: "已恢复"
    )

    static let zhTW = ForkMacBackupEngineStrings(
        installNetwork: "下載失敗。請檢查網路連線後再試一次。",
        installSpace: "這部 Mac 的可用空間不足，無法安裝引擎。",
        installChecksum: "下載的檔案不是預期的引擎，已刪除。",
        installExtract: "無法解壓縮引擎封存檔。",
        installLaunch: "引擎無法在這部 Mac 上啟動，或未經 Kopia 簽署。",
        installIO: "無法將引擎寫入磁碟。",
        restoredSuffix: "已回復"
    )

    static let zhHK = ForkMacBackupEngineStrings(
        installNetwork: "下載失敗。請檢查網絡連線後再試一次。",
        installSpace: "這部 Mac 的可用空間不足，無法安裝引擎。",
        installChecksum: "下載的檔案不是預期的引擎，已刪除。",
        installExtract: "無法解壓縮引擎封存檔。",
        installLaunch: "引擎無法在這部 Mac 上啟動，或未經 Kopia 簽署。",
        installIO: "無法將引擎寫入磁碟。",
        restoredSuffix: "已還原"
    )
}
