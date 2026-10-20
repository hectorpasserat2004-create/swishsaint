// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// The video call of an appointment in the island's calendar: the one link
/// that joins it, read from a calendar event's address, place and notes, or
/// from a CRM appointment's own meeting link.
///
/// - Only a link to a call counts: Google Meet, Zoom (`zoommtg://` too, its
///   password kept), Microsoft Teams, Webex, Whereby, Jitsi, FaceTime. An
///   invitation's other links (help pages, dial-in numbers, the meeting's
///   options, a map, a host's start link) are never one, nor a look-alike
///   host, nor a link carrying a user name.
/// - One link per appointment, the likeliest: the event's address first,
///   then its place, then its notes, the first call link of each. An
///   Outlook safe link or a Google redirect is read as the web link it wraps.
/// - Kept in memory only, like the rest of an event's text.
struct ForkCalendarVideoLink: Equatable, Sendable {
    enum Provider: String, CaseIterable, Sendable {
        case meet, zoom, teams, webex, whereby, jitsi, facetime
        /// A CRM's own meeting link, of a service not listed here.
        case other

        /// The service's own name, the same in every language; `nil` for
        /// another one, which the island calls a video call.
        var name: String? {
            switch self {
            case .meet: return "Google Meet"
            case .zoom: return "Zoom"
            case .teams: return "Microsoft Teams"
            case .webex: return "Webex"
            case .whereby: return "Whereby"
            case .jitsi: return "Jitsi Meet"
            case .facetime: return "FaceTime"
            case .other: return nil
            }
        }
    }

    let provider: Provider
    /// The link as written, unwrapped (a Zoom app link rebuilt with its
    /// meeting's fields only): what Copy Link copies.
    let url: URL
    /// What says two links join the same call: the Meet code, the Zoom
    /// meeting number, else the address without its query, lowercased.
    let key: String

    /// Notes past this are not searched: an invitation's link comes early.
    static let searchedCharacters = 20_000

    /// The event's link: its address, then its place, then its notes.
    static func find(url: URL?, location: String?, notes: String?) -> ForkCalendarVideoLink? {
        for text in [url?.absoluteString, location, notes] {
            if let text, let link = first(in: text) { return link }
        }
        return nil
    }

    /// The first call link of a free text. A link glued to the word before
    /// it ("Lien:https://…") is read from its scheme; invisible characters
    /// (zero-width spaces, joiners) end it.
    static func first(in text: String) -> ForkCalendarVideoLink? {
        let searched = text.count > searchedCharacters ? String(text.prefix(searchedCharacters)) : text
        let separators = Set<Character>("<>\"'()[]{}|\\^`\u{200B}\u{200C}\u{200D}\u{2060}\u{FEFF}")
        for word in searched.split(whereSeparator: { $0.isWhitespace || separators.contains($0) }) {
            if let link = link(fromScheme(String(word))) { return link }
        }
        return nil
    }

    /// A CRM appointment's meeting link: a call link it recognizes, else
    /// any HTTPS address on a named host (the CRM says it is the meeting's),
    /// else nothing.
    static func meetingLink(_ text: String?) -> ForkCalendarVideoLink? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        if let link = first(in: text) {
            // Never a plain-text address for a link the CRM gives.
            return ["https", "zoommtg"].contains(link.url.scheme?.lowercased() ?? "") ? link : nil
        }
        guard !text.contains(where: \.isWhitespace), let url = URL(string: trimmed(text)),
              url.scheme?.lowercased() == "https", isPlain(url), let host = url.host, host.contains(".") else {
            return nil
        }
        return ForkCalendarVideoLink(provider: .other, url: url, key: plainKey(url))
    }

    /// One word of a text, as a call link, or `nil`.
    static func link(_ word: String) -> ForkCalendarVideoLink? {
        let cleaned = trimmed(word.replacingOccurrences(of: "&amp;", with: "&"))
        guard cleaned.count >= 8, cleaned.contains(":"), let url = unwrapped(URL(string: cleaned)), isPlain(url) else {
            return nil
        }
        let scheme = url.scheme?.lowercased() ?? ""
        let host = url.host?.lowercased() ?? ""
        let path = url.path
        let parts = path.split(separator: "/").map(String.init)
        if scheme == "zoommtg" || scheme == "zoomus" { return zoomApp(url, host: host) }
        guard scheme == "https" || scheme == "http" else { return nil }
        if host == "meet.google.com" {
            // The code is the path, never something further in the query.
            guard parts.count == 1, parts[0].count == 12, let code = ForkMeetingTitleRules.meetCode(in: parts[0]) else {
                return nil
            }
            return ForkCalendarVideoLink(provider: .meet, url: url, key: "meet:" + code)
        }
        if isZoom(host) { return zoom(url, parts: parts) }
        if ["teams.microsoft.com", "teams.cloud.microsoft"].contains(host)
            && (path.hasPrefix("/l/meetup-join/") || path.hasPrefix("/meet/"))
            || host == "teams.live.com" && path.hasPrefix("/meet/") {
            return ForkCalendarVideoLink(provider: .teams, url: url, key: plainKey(url))
        }
        if host == "webex.com" || host.hasSuffix(".webex.com"), !webexOwnHosts.contains(host) {
            if path.lowercased().hasSuffix("/j.php"), let id = query(url, "MTID"), !id.isEmpty {
                return ForkCalendarVideoLink(provider: .webex, url: url, key: plainKey(url) + "?mtid=" + id.lowercased())
            }
            guard parts.count >= 2, ["meet", "join"].contains(parts[0].lowercased()) else { return nil }
            return ForkCalendarVideoLink(provider: .webex, url: url, key: plainKey(url))
        }
        if host == "whereby.com" || host.hasSuffix(".whereby.com") {
            guard parts.count == 1, !wherebyPages.contains(parts[0].lowercased()) else { return nil }
            return ForkCalendarVideoLink(provider: .whereby, url: url, key: plainKey(url))
        }
        if host == "meet.jit.si" || host == "8x8.vc" {
            guard let room = parts.last, !room.contains("."), !jitsiPaths.contains(parts[0].lowercased()) else { return nil }
            return ForkCalendarVideoLink(provider: .jitsi, url: url, key: plainKey(url))
        }
        if host == "facetime.apple.com", path.lowercased() == "/join", !(url.fragment ?? "").isEmpty {
            // The call is named after the `#`, which Copy Link keeps.
            return ForkCalendarVideoLink(provider: .facetime, url: url, key: url.absoluteString.lowercased())
        }
        return nil
    }

    /// What Join opens: the Zoom or Teams app itself when it is on this Mac
    /// (the browser would only hand over to it), else the link.
    static func joinURL(_ link: ForkCalendarVideoLink, zoomApp: Bool, teamsApp: Bool) -> URL {
        let url = link.url
        let web = ["https", "http"].contains(url.scheme?.lowercased() ?? "")
        switch link.provider {
        case .zoom where zoomApp && web:
            let parts = url.path.lowercased().split(separator: "/").map(String.init)
            guard let host = url.host, let number = zoomNumber(parts) else { return url }
            var items = [URLQueryItem(name: "action", value: "join"), URLQueryItem(name: "confno", value: number)]
            if let pwd = query(url, "pwd") { items.append(URLQueryItem(name: "pwd", value: pwd)) }
            // A webinar's registration token.
            if parts.first == "w", let token = query(url, "tk") { items.append(URLQueryItem(name: "tk", value: token)) }
            var components = URLComponents()
            components.scheme = "zoommtg"
            components.host = host
            components.path = "/join"
            components.queryItems = items
            return components.url ?? url
        case .teams where teamsApp && web:
            // The desktop app takes the same path and query after `msteams:`.
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let app = URL(string: "msteams:" + components.percentEncodedPath
                                + (components.percentEncodedQuery.map { "?" + $0 } ?? "")) else { return url }
            return app
        default:
            return url
        }
    }

    // MARK: - Underneath

    /// Whereby's own pages, which are not rooms.
    private static let wherebyPages: Set<String> = [
        "user", "information", "login", "signup", "org", "pricing", "blog", "download", "support", "embed", "terms",
        "privacy", "legal", "about", "contact", "careers", "security", "cookies", "help", "features", "integrations",
    ]
    /// Jitsi's own files and pages, which are not rooms.
    private static let jitsiPaths: Set<String> = ["static", "libs", "css", "images", "sounds", "fonts", "lang", "http-bind"]
    /// Webex's own sites, which hold no meeting.
    private static let webexOwnHosts: Set<String> = ["help.webex.com", "www.webex.com", "developer.webex.com", "blog.webex.com"]

    private static func isZoom(_ host: String) -> Bool {
        ["zoom.us", "zoomgov.com"].contains { host == $0 || host.hasSuffix("." + $0) }
    }

    /// A web address of a call never carries a user name nor a password.
    private static func isPlain(_ url: URL) -> Bool {
        url.user == nil && url.password == nil
    }

    /// `/j/<n>` (a meeting), `/w/<n>` (a webinar), `/my/<name>` (a personal
    /// room); never `/s/`, the host's start link, which carries the host's own key.
    private static func zoom(_ url: URL, parts: [String]) -> ForkCalendarVideoLink? {
        let lowered = parts.map { $0.lowercased() }
        if let number = zoomNumber(lowered) {
            return ForkCalendarVideoLink(provider: .zoom, url: url, key: "zoom:" + number)
        }
        guard lowered.count == 2, lowered[0] == "my" else { return nil }
        return ForkCalendarVideoLink(provider: .zoom, url: url, key: "zoom:my/" + lowered[1])
    }

    private static func zoomNumber(_ parts: [String]) -> String? {
        guard parts.count == 2, parts[0] == "j" || parts[0] == "w" else { return nil }
        let number = parts[1]
        guard number.count >= 9, number.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return number
    }

    /// A `zoommtg://` or `zoomus://` link on a Zoom host, rebuilt with its
    /// meeting's own fields only.
    private static func zoomApp(_ url: URL, host: String) -> ForkCalendarVideoLink? {
        guard isZoom(host), url.path.lowercased() == "/join", let number = query(url, "confno"),
              number.count >= 9, number.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        var components = URLComponents()
        components.scheme = "zoommtg"
        components.host = host
        components.path = "/join"
        components.queryItems = [URLQueryItem(name: "action", value: "join"), URLQueryItem(name: "confno", value: number)]
            + (query(url, "pwd").map { [URLQueryItem(name: "pwd", value: $0)] } ?? [])
        guard let rebuilt = components.url else { return nil }
        return ForkCalendarVideoLink(provider: .zoom, url: rebuilt, key: "zoom:" + number)
    }

    /// A word from the first scheme it holds: "Lien:https://…" is the link.
    private static func fromScheme(_ word: String) -> String {
        let lowered = word.lowercased()
        let starts = ["https://", "http://", "zoommtg://", "zoomus://"].compactMap { lowered.range(of: $0)?.lowerBound }
        guard let start = starts.min(), start != lowered.startIndex else { return word }
        let offset = lowered.distance(from: lowered.startIndex, to: start)
        return String(word.dropFirst(offset))
    }

    /// A word without the punctuation a sentence puts around a link.
    private static func trimmed(_ word: String) -> String {
        var text = Substring(word)
        while let last = text.last, ".,;:!?)]}>*".contains(last) { text = text.dropLast() }
        while let first = text.first, "([{<*".contains(first) { text = text.dropFirst() }
        return String(text)
    }

    /// The web link an Outlook safe link or a Google redirect wraps, else
    /// the link; a wrapped link of any other kind is nothing.
    private static func unwrapped(_ url: URL?) -> URL? {
        guard let url, let host = url.host?.lowercased() else { return url }
        let wrapped: String?
        if host.hasSuffix(".safelinks.protection.outlook.com") {
            wrapped = query(url, "url")
        } else if (host == "google.com" || host == "www.google.com") && url.path == "/url" {
            wrapped = query(url, "q")
        } else {
            return url
        }
        guard let wrapped, let inner = URL(string: trimmed(wrapped)),
              ["https", "http"].contains(inner.scheme?.lowercased() ?? ""), inner.host != nil else { return nil }
        return inner
    }

    private static func query(_ url: URL, _ name: String) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
            .first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    private static func plainKey(_ url: URL) -> String {
        let path = url.path.hasSuffix("/") ? String(url.path.dropLast()) : url.path
        return ((url.host ?? "") + path).lowercased()
    }
}
