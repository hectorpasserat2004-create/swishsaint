// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// Who speaks in a file, as the person says before sending it to the Studio:
/// "auto" lets it find the voices, "1" is a monologue, "2"…"8" a number of
/// people at most. Parakeet on this Mac hears no voices at all.
enum ForkTranscribeSpeakers {
    static let auto = "auto"
    static let choices = ["auto", "1", "2", "3", "4", "5", "6", "7", "8"]

    /// The Studio's `voix_max`: nil lets it guess.
    static func most(_ stored: String?) -> Int? {
        guard let stored, let count = Int(stored), (1...8).contains(count) else { return nil }
        return count
    }
}

/// When a file is sent as it is, and when only its sound is, re-encoded
/// light (AAC, 16 kHz mono, 32 kbit/s: 14.4 MB an hour).
enum ForkTranscribeUpload {
    static let bitRate = 32_000
    static let bytesPerSecond = Double(bitRate) / 8 + 50
    static let compressedAudio: Set<String> = ["mp3", "m4a", "aac", "ogg", "oga", "opus"]

    /// Sent as it is: compressed sound, small enough for the server. A video,
    /// lossless sound or a big file is lightened first.
    static func sendsAsIs(extension ext: String, bytes: Int64, limit: Int64, accepted: Set<String>) -> Bool {
        let ext = ext.lowercased()
        return compressedAudio.contains(ext) && accepted.contains(ext) && bytes <= limit
    }

    /// The pieces a lightened sound is cut into so each fits under `limit`
    /// bytes: (start, length) in seconds, the last one to the end.
    static func pieces(duration: TimeInterval, limit: Int64) -> [(start: TimeInterval, length: TimeInterval)] {
        guard duration > 0 else { return [(0, 0)] }
        let longest = max(60, (Double(limit) * 0.9 / bytesPerSecond).rounded(.down))
        guard duration > longest else { return [(0, duration)] }
        var pieces: [(TimeInterval, TimeInterval)] = []
        var start: TimeInterval = 0
        while start < duration {
            let length = min(longest, duration - start)
            pieces.append((start, length))
            start += length
        }
        return pieces
    }
}

/// The Studio's transcriber, as its own client (`transcrire`) speaks to it:
/// a job API, not OpenAI's. `GET /v1/sante`, `POST /v1/transcrire` with the
/// file as body, then `GET /v1/travaux/<id>` until done; `DELETE` cancels.
enum ForkTranscribeStudioAPI {
    static let defaultURL = "https://studio-m2.tailef3e9f.ts.net:8792"
    static let byteLimit: Int64 = 400 * 1024 * 1024
    static let longest: TimeInterval = 2 * 3600
    static let vocabularyLimit = 60
    /// Whatever ffmpeg reads: every format the page takes.
    static let accepted = ForkTranscribeRules.acceptedExtensions
    /// How long a sleeping transcriber may take to wake.
    static let wakeLimit: TimeInterval = 240
    /// The CLI's own patience with a full server.
    static let busyLimit: TimeInterval = 30 * 60

    struct Health: Decodable {
        struct Engine: Decodable {
            var etat: String?
            var version: String?
        }

        var transcripteur: Engine?
    }

    enum State: Equatable {
        case ready
        case waking
        case stopping
        case unknown
    }

    static func state(_ data: Data) -> State {
        guard let health = try? JSONDecoder().decode(Health.self, from: data) else { return .unknown }
        switch health.transcripteur?.etat {
        case "pret": return .ready
        case "demarrage": return .waking
        case "vidange": return .stopping
        default: return .unknown
        }
    }

    static func version(_ data: Data) -> String? {
        (try? JSONDecoder().decode(Health.self, from: data))?.transcripteur?.version
    }

    /// `/v1/transcrire?…`, every value encoded.
    static func submitPath(name: String, language: ForkTranscribeLanguage, key: String, speakers: Int?,
                           vocabulary: [String]) -> String {
        var items = [URLQueryItem(name: "nom", value: name),
                     URLQueryItem(name: "langue", value: language.rawValue),
                     URLQueryItem(name: "cle", value: key)]
        if let speakers { items.append(URLQueryItem(name: "voix_max", value: String(speakers))) }
        let words = Array(vocabulary.prefix(vocabularyLimit))
        if !words.isEmpty { items.append(URLQueryItem(name: "vocabulaire", value: words.joined(separator: ","))) }
        var components = URLComponents()
        components.path = "/v1/transcrire"
        components.queryItems = items
        // `+` and `,` stay as they are in a query: the server would read a
        // `+` as a space.
        components.percentEncodedQuery = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
        return components.string ?? "/v1/transcrire"
    }

    /// The dictation's words (one per line), as the Studio takes them: no
    /// comma inside a word, no duplicate, 60 at most.
    static func vocabulary(_ dictation: String) -> [String] {
        var seen = Set<String>()
        return dictation.split(whereSeparator: \.isNewline)
            .map { $0.replacingOccurrences(of: ",", with: " ").trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
            .prefix(vocabularyLimit).map { $0 }
    }

    struct Answer: Decodable {
        var travail: String?
        var etat: String?
        var progression: Double?
        var code: String?
        var reessayable: Bool?
        var resultat: Result?
    }

    struct Result: Decodable {
        struct Turn: Decodable {
            var voix: String?
            var debut_s: Double
            var fin_s: Double
            var texte: String
        }

        var langue: String?
        var tours: [Turn]
    }

    static func answer(_ data: Data) -> Answer? {
        try? JSONDecoder().decode(Answer.self, from: data)
    }

    /// A job's state as the poll reads it.
    enum Job: Equatable {
        case queued
        case running(Double?)
        case done(ForkTranscribeDocument)
        case failed(ForkTranscribeFailure)
    }

    static func job(_ data: Data, duration: TimeInterval) -> Job? {
        guard let answer = answer(data) else { return nil }
        switch answer.etat {
        case "en_file": return .queued
        case "en_cours": return .running(answer.progression)
        case "fini":
            guard let result = answer.resultat else { return .failed(.remoteFailed) }
            return .done(document(result, duration: duration))
        case "echec": return .failed(failure(status: 200, code: answer.code))
        default: return nil
        }
    }

    static func document(_ result: Result, duration: TimeInterval) -> ForkTranscribeDocument {
        let segments = result.tours
            .sorted { $0.debut_s < $1.debut_s }
            .compactMap { turn -> ForkTranscribeDocument.Segment? in
                let text = turn.texte.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                return .init(start: turn.debut_s, end: max(turn.fin_s, turn.debut_s), speaker: turn.voix, text: text)
            }
        return ForkTranscribeDocument(segments: segments, duration: max(duration, segments.last?.end ?? 0),
                                      language: result.langue)
    }

    /// What a refusal means. `expired` and `unknown` mean the server no
    /// longer has the job: the caller sends the file again.
    static func failure(status: Int, code: String?) -> ForkTranscribeFailure {
        switch code {
        case "jeton": return .unauthorized
        case "trop_gros": return .tooLarge
        case "trop_long": return .tooLong
        case "decodage": return .unreadable
        case "trop_de_travaux", "trop_de_travaux_distants", "trop_d_envois", "demarrage", "memoire", "vidange",
             "transcripteur_injoignable":
            return .serverBusy
        default:
            if status == 401 || status == 403 { return .unauthorized }
            if status == 413 { return .tooLarge }
            return .remoteFailed
        }
    }

    static func isGone(_ code: String?) -> Bool { code == "expire" || code == "inconnu" }
}

/// OpenAI's `POST …/audio/transcriptions`, which many services speak: OpenAI,
/// Groq, and the Whisper servers one runs oneself. One multipart request per
/// piece of 25 MB at most; `verbose_json` gives the timed passages, plain
/// `json` (newer models) only the text.
enum ForkTranscribeOpenAIAPI {
    static let defaultURL = "https://api.openai.com/v1"
    static let defaultModel = "whisper-1"
    /// OpenAI's limit is 25 MB a request.
    static let byteLimit: Int64 = 24 * 1000 * 1000
    static let accepted: Set<String> = ["mp3", "mp4", "mpeg", "mpga", "m4a", "wav", "webm", "ogg", "flac"]

    /// `…/v1` + `/audio/transcriptions`; nil for an address that is not one.
    static func endpoint(_ base: String, path: String = "audio/transcriptions") -> URL? {
        var text = base.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix("/") { text.removeLast() }
        guard let url = URL(string: text + "/" + path), let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http", url.host != nil else { return nil }
        return url
    }

    /// The vocabulary as Whisper's prompt: the words it should spell so.
    static func prompt(_ words: [String]) -> String? {
        let kept = words.prefix(60)
        return kept.isEmpty ? nil : kept.joined(separator: ", ")
    }

    /// The form's fields before the file; the file's part head, and its end.
    static func multipart(boundary: String, fields: [(String, String)], fileName: String,
                          mime: String) -> (head: Data, tail: Data) {
        var head = ""
        for (name, value) in fields {
            head += "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n"
        }
        let safeName = fileName.replacingOccurrences(of: "\"", with: "")
        head += "--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(safeName)\"\r\n"
        head += "Content-Type: \(mime)\r\n\r\n"
        return (Data(head.utf8), Data("\r\n--\(boundary)--\r\n".utf8))
    }

    static func mime(_ ext: String) -> String {
        switch ext.lowercased() {
        case "mp3", "mpeg", "mpga": return "audio/mpeg"
        case "wav": return "audio/wav"
        case "ogg": return "audio/ogg"
        case "flac": return "audio/flac"
        case "webm": return "audio/webm"
        default: return "audio/mp4"
        }
    }

    private struct Verbose: Decodable {
        struct Segment: Decodable {
            var start: Double
            var end: Double
            var text: String
            var speaker: String?
        }

        var text: String?
        var language: String?
        var duration: Double?
        var segments: [Segment]?
    }

    /// One piece's answer, its times moved by `offset` (where the piece starts
    /// in the file). Plain text without times gives one passage for the piece.
    static func segments(_ data: Data, offset: TimeInterval, length: TimeInterval)
        -> (segments: [ForkTranscribeDocument.Segment], language: String?)? {
        guard let answer = try? JSONDecoder().decode(Verbose.self, from: data) else { return nil }
        let language = code(answer.language)
        if let timed = answer.segments, !timed.isEmpty {
            let segments = timed.compactMap { part -> ForkTranscribeDocument.Segment? in
                let text = part.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                return .init(start: offset + part.start, end: offset + max(part.end, part.start), speaker: part.speaker,
                             text: text)
            }
            return (segments, language)
        }
        let text = (answer.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return (text.isEmpty ? [] : [.init(start: offset, end: offset + length, speaker: nil, text: text)], language)
    }

    /// Whisper names the language ("french"); others give its code.
    static func code(_ language: String?) -> String? {
        guard let language = language?.lowercased(), !language.isEmpty else { return nil }
        let names = ["french": "fr", "english": "en", "german": "de", "spanish": "es", "italian": "it",
                     "portuguese": "pt", "dutch": "nl", "russian": "ru", "japanese": "ja", "chinese": "zh",
                     "korean": "ko", "turkish": "tr", "ukrainian": "uk", "slovak": "sk"]
        if let code = names[language] { return code }
        return language.count == 2 ? language : nil
    }

    /// Whether a refusal says the model does not do `verbose_json`: the
    /// request is made again with plain `json`.
    static func refusesVerbose(status: Int, body: Data) -> Bool {
        guard status == 400 else { return false }
        let text = String(data: body, encoding: .utf8)?.lowercased() ?? ""
        return text.contains("response_format") || text.contains("verbose_json")
    }

    static func failure(status: Int) -> ForkTranscribeFailure {
        switch status {
        case 401, 403: return .unauthorized
        case 404: return .notConfigured
        case 413: return .tooLarge
        case 429, 503: return .serverBusy
        case 400, 415, 422: return .unreadable
        default: return .remoteFailed
        }
    }
}
