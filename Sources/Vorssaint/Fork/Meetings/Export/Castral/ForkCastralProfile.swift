// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// The imported profile of a CRM that speaks the recorder contract
/// (`castral-recorder/1`): where it is, where its storage takes the sound,
/// the header its token goes in, who may sign a report, and how it names
/// the files and links a record.
///
/// **Nothing of any installation is in the code** (D5): no domain, no
/// storage host, no header, no author. The person who has such a CRM imports
/// its profile once, a JSON file; for anyone else the Meetings page shows
/// nothing but its generic "Import a Profile…".
///
/// - **Kept in the Keychain**, with the token, never in the preferences: a
///   process that rewrites the preferences cannot send the token or the
///   sound anywhere else.
/// - **Checked at the import and at every read**: HTTPS, an ASCII host, no
///   user or fragment (`ForkMeetingOriginPolicy`); a header that cannot pass
///   for one the system sets; a file name prefix and a link path that stay
///   what they say. A profile refused names its field and changes nothing.
struct ForkCastralProfile: Equatable {
    static let kind = "castral-recorder/1"
    /// The extension of the file the person imports.
    static let fileExtension = "swishsaint-profile"
    /// Larger is not a profile.
    static let maximumFileBytes = 64 << 10
    /// What the server's storage takes when the profile says nothing: the
    /// lower of the two caps measured (50 000 000 bytes, under the
    /// 52 428 800 the server checks).
    static let defaultMaximumUploadBytes: Int64 = 50_000_000
    static let uploadBytesRange: ClosedRange<Int64> = 1_000_000...500_000_000

    /// The CRM's address, without a final slash: the contract's paths
    /// (`/api/transcriptions…`) follow it.
    let baseURL: URL
    /// Where the CRM may send the sound, as `host` or `host:port`, exactly:
    /// an upload address anywhere else is refused before a byte leaves.
    let uploadHost: String
    /// The header the token goes in.
    let tokenHeader: String
    /// Who may sign a report (`created_by`), in the profile's order.
    let authors: [String]
    /// The start of the file's name in the CRM ("Call_").
    let filenamePrefix: String
    /// The path of a company's record, `{company}` standing for its id; the
    /// id goes at the end without it.
    let dashboardPath: String
    /// What the page and the notices call it; the host when the profile has
    /// no name.
    let name: String?
    let maximumUploadBytes: Int64

    var origin: ForkMeetingOriginPolicy.Origin {
        ForkMeetingOriginPolicy.origin(of: baseURL) ?? ForkMeetingOriginPolicy.Origin(host: "")
    }

    var uploadOrigin: ForkMeetingOriginPolicy.Origin? { ForkMeetingOriginPolicy.Origin(name: uploadHost) }

    var displayName: String { name ?? origin.name }

    /// Why a profile is refused: the field, as the file names it.
    enum Refusal: Error, Equatable {
        case unreadable
        case kind
        case field(String)

        var field: String {
            switch self {
            case .unreadable: return "JSON"
            case .kind: return "kind"
            case let .field(name): return name
            }
        }
    }

    /// The headers the system sets or a proxy reads: never a token's.
    static let reservedHeaders: Set<String> = [
        "authorization", "proxy-authorization", "cookie", "set-cookie", "host", "content-type", "content-length",
        "content-encoding", "transfer-encoding", "connection", "keep-alive", "upgrade", "te", "trailer", "expect",
        "user-agent", "accept", "accept-encoding", "accept-language", "origin", "referer", "range",
    ]

    /// Reads a profile file. Any field out of shape refuses the whole: a
    /// half-read profile would send somewhere half-approved.
    static func parse(_ data: Data) -> Result<ForkCastralProfile, Refusal> {
        guard !data.isEmpty, data.count <= maximumFileBytes,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure(.unreadable)
        }
        guard object["kind"] as? String == kind else { return .failure(.kind) }

        guard let base = object["baseURL"] as? String,
              case let .approved(approved, _) = ForkMeetingOriginPolicy.destination(base),
              approved.query == nil, let baseURL = trimmedBase(approved) else { return .failure(.field("baseURL")) }

        guard let upload = (object["uploadHost"] as? String)?.trimmingCharacters(in: .whitespaces),
              let uploadOrigin = ForkMeetingOriginPolicy.Origin(name: upload.lowercased()) else {
            return .failure(.field("uploadHost"))
        }

        guard let header = object["tokenHeader"] as? String, isHeaderName(header),
              !reservedHeaders.contains(header.lowercased()) else { return .failure(.field("tokenHeader")) }

        guard let list = object["authors"] as? [Any], (1...12).contains(list.count) else {
            return .failure(.field("authors"))
        }
        var authors: [String] = []
        for item in list {
            guard let author = (item as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  isPlainText(author, maximum: 40), !authors.contains(author) else { return .failure(.field("authors")) }
            authors.append(author)
        }

        let prefix = object["filenamePrefix"] as? String ?? ""
        guard object["filenamePrefix"] == nil || object["filenamePrefix"] is String, prefix.count <= 40,
              prefix.unicodeScalars.allSatisfy(isFileNameScalar) else { return .failure(.field("filenamePrefix")) }

        guard let path = object["dashboardPath"] as? String, isLinkPath(path) else {
            return .failure(.field("dashboardPath"))
        }

        var name: String?
        if let value = object["name"] {
            guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  isPlainText(text, maximum: 16) else { return .failure(.field("name")) }
            name = text
        }

        var maximum = defaultMaximumUploadBytes
        if let value = object["maxUploadBytes"] {
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                  number.doubleValue == number.doubleValue.rounded(),
                  uploadBytesRange.contains(number.int64Value) else { return .failure(.field("maxUploadBytes")) }
            maximum = number.int64Value
        }

        return .success(ForkCastralProfile(baseURL: baseURL, uploadHost: uploadOrigin.name, tokenHeader: header,
                                           authors: authors, filenamePrefix: prefix, dashboardPath: path, name: name,
                                           maximumUploadBytes: maximum))
    }

    /// What the Keychain keeps: the same fields, in a stable order, read
    /// back through `parse`.
    func encoded() -> Data {
        var object: [String: Any] = [
            "kind": Self.kind, "baseURL": baseURL.absoluteString, "uploadHost": uploadHost, "tokenHeader": tokenHeader,
            "authors": authors, "filenamePrefix": filenamePrefix, "dashboardPath": dashboardPath,
            "maxUploadBytes": NSNumber(value: maximumUploadBytes),
        ]
        if let name { object["name"] = name }
        return (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
    }

    // MARK: - Addresses

    /// A contract path ("api/transcriptions/targets") under the base.
    func endpoint(_ path: String, query: [URLQueryItem] = []) -> URL? {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        let base = components?.path ?? ""
        components?.path = (base.hasSuffix("/") ? base : base + "/") + path
        components?.queryItems = query.isEmpty ? nil : query
        guard let url = components?.url, ForkMeetingOriginPolicy.origin(of: url) == origin else { return nil }
        return url
    }

    /// The company's record in the CRM, on its own origin only; `nil` for
    /// an id that is not one.
    func dashboardURL(companyID: String) -> URL? {
        guard ForkCastralContract.isID(companyID) else { return nil }
        let id = companyID.lowercased()
        let path = dashboardPath.contains("{company}")
            ? dashboardPath.replacingOccurrences(of: "{company}", with: id)
            : (dashboardPath.hasSuffix("/") ? dashboardPath : dashboardPath + "/") + id
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        let base = components?.path ?? ""
        components?.path = (base.hasSuffix("/") ? String(base.dropLast()) : base) + path
        guard let url = components?.url, ForkMeetingOriginPolicy.origin(of: url) == origin else { return nil }
        return url
    }

    /// May the sound go to this upload address? HTTPS, on the profile's
    /// upload host or the CRM itself, exactly; never another project of a
    /// shared storage domain.
    func allowsUpload(to url: URL) -> Bool {
        var rules: [ForkMeetingOriginPolicy.Rule] = [.exactly(origin)]
        if let uploadOrigin { rules.append(.exactly(uploadOrigin)) }
        return ForkMeetingOriginPolicy.destination(url.absoluteString, within: rules).url != nil
    }

    /// "Call_2026-10-19_example.org.flac": the prefix, the meeting's day,
    /// then who it was with, in the characters a storage path keeps.
    func fileName(day: Date, who: String?, extension ext: String, calendar: Calendar = .current) -> String {
        var calendar = calendar
        calendar.locale = Locale(identifier: "en_US_POSIX")
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        let date = String(format: "%04d-%02d-%02d", parts.year ?? 1970, parts.month ?? 1, parts.day ?? 1)
        let folded = (who ?? "").folding(options: [.diacriticInsensitive, .widthInsensitive], locale: nil)
        var cleaned = String(String.UnicodeScalarView(folded.unicodeScalars.map { Self.isFileNameScalar($0) ? $0 : "-" }))
        while cleaned.contains("--") { cleaned = cleaned.replacingOccurrences(of: "--", with: "-") }
        cleaned = String(cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "-.")).prefix(60))
        return "\(filenamePrefix)\(date)_\(cleaned.isEmpty ? "meeting" : cleaned).\(ext)"
    }

    // MARK: - Shapes

    private static func trimmedBase(_ url: URL) -> URL? {
        var text = url.absoluteString
        while text.hasSuffix("/") { text.removeLast() }
        return URL(string: text)
    }

    /// An HTTP token (RFC 9110): letters, digits and `-`, as a header's name.
    private static func isHeaderName(_ name: String) -> Bool {
        (1...64).contains(name.count) && name.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || scalar == "-")
        } && !name.hasPrefix("-")
    }

    private static func isPlainText(_ text: String, maximum: Int) -> Bool {
        !text.isEmpty && text.count <= maximum
            && !text.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) || $0 == "\u{2028}" || $0 == "\u{2029}" }
    }

    private static func isFileNameScalar(_ scalar: Unicode.Scalar) -> Bool {
        scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || scalar == "." || scalar == "_" || scalar == "-")
    }

    /// `/a/b/{company}`: ASCII, no space, no query, no fragment, no `..`.
    private static func isLinkPath(_ path: String) -> Bool {
        guard path.hasPrefix("/"), path.count <= 200, !path.contains(".."), !path.contains("//") else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~/{}")
        guard path.unicodeScalars.allSatisfy(allowed.contains) else { return false }
        let braces = path.replacingOccurrences(of: "{company}", with: "")
        return !braces.contains("{") && !braces.contains("}")
    }

    private init(baseURL: URL, uploadHost: String, tokenHeader: String, authors: [String], filenamePrefix: String,
                 dashboardPath: String, name: String?, maximumUploadBytes: Int64) {
        self.baseURL = baseURL
        self.uploadHost = uploadHost
        self.tokenHeader = tokenHeader
        self.authors = authors
        self.filenamePrefix = filenamePrefix
        self.dashboardPath = dashboardPath
        self.name = name
        self.maximumUploadBytes = maximumUploadBytes
    }
}
