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
///   options, a map) are never one.
/// - One link per appointment, the likeliest: the event's address first,
///   then its place, then its notes, the first call link of each. An
///   Outlook safe link or a Google redirect is read as the link it wraps.
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
    /// The link as written, unwrapped: what Copy Link copies.
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

    /// The first call link of a free text.
    static func first(in text: String) -> ForkCalendarVideoLink? {
        let searched = text.count > searchedCharacters ? String(text.prefix(searchedCharacters)) : text
        for word in searched.split(whereSeparator: { $0.isWhitespace || "<>\"'()[]{}|\\^`".contains($0) }) {
            if let link = link(String(word)) { return link }
        }
        return nil
    }

    /// A CRM appointment's meeting link: a call link it recognizes, else
    /// any web address (the CRM says it is the meeting's), else nothing.
    static func meetingLink(_ text: String?) -> ForkCalendarVideoLink? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        if let link = first(in: text) { return link }
        guard !text.contains(where: \.isWhitespace), let url = URL(string: trimmed(text)),
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""), let host = url.host, !host.isEmpty else {
            return nil
        }
        return ForkCalendarVideoLink(provider: .other, url: url, key: plainKey(url))
    }

    /// One word of a text, as a call link, or `nil`.
    static func link(_ word: String) -> ForkCalendarVideoLink? {
        let cleaned = trimmed(word.replacingOccurrences(of: "&amp;", with: "&"))
        guard cleaned.count >= 8, cleaned.contains(":"), let url = unwrapped(URL(string: cleaned)) else { return nil }
        let scheme = url.scheme?.lowercased() ?? ""
        let host = url.host?.lowercased() ?? ""
        let path = url.path
        if scheme == "zoommtg" || scheme == "zoomus" {
            guard isZoom(host), let number = query(url, "confno"), !number.isEmpty else { return nil }
            return ForkCalendarVideoLink(provider: .zoom, url: url, key: "zoom:" + number.lowercased())
        }
        guard scheme == "https" || scheme == "http" else { return nil }
        if host == "meet.google.com" {
            guard let code = ForkMeetingTitleRules.meetCode(inLink: url.absoluteString) else { return nil }
            return ForkCalendarVideoLink(provider: .meet, url: url, key: "meet:" + code)
        }
        if isZoom(host) { return zoom(url, path: path) }
        if (host == "teams.microsoft.com" && (path.hasPrefix("/l/meetup-join/") || path.hasPrefix("/meet/")))
            || (host == "teams.live.com" && path.hasPrefix("/meet/")) {
            return ForkCalendarVideoLink(provider: .teams, url: url, key: plainKey(url))
        }
        if host == "webex.com" || host.hasSuffix(".webex.com") {
            let lowered = path.lowercased()
            if lowered.hasSuffix("/j.php"), let id = query(url, "MTID") {
                return ForkCalendarVideoLink(provider: .webex, url: url, key: plainKey(url) + "?mtid=" + id.lowercased())
            }
            guard lowered.contains("/meet/") || lowered.contains("/join/") else { return nil }
            return ForkCalendarVideoLink(provider: .webex, url: url, key: plainKey(url))
        }
        if host == "whereby.com" || host.hasSuffix(".whereby.com") {
            let room = path.split(separator: "/").first.map { String($0).lowercased() } ?? ""
            guard !room.isEmpty, !wherebyPages.contains(room) else { return nil }
            return ForkCalendarVideoLink(provider: .whereby, url: url, key: plainKey(url))
        }
        if host == "meet.jit.si" || host == "8x8.vc" {
            guard path.count > 1 else { return nil }
            return ForkCalendarVideoLink(provider: .jitsi, url: url, key: plainKey(url))
        }
        if host == "facetime.apple.com", path.lowercased().hasPrefix("/join") {
            // The call is named after the `#`, which Copy Link keeps.
            return ForkCalendarVideoLink(provider: .facetime, url: url, key: url.absoluteString.lowercased())
        }
        return nil
    }

    /// What Join opens: the Zoom or Teams app itself when it is on this Mac
    /// (the browser would only hand over to it), else the link.
    static func joinURL(_ link: ForkCalendarVideoLink, zoomApp: Bool, teamsApp: Bool) -> URL {
        let url = link.url
        switch link.provider {
        case .zoom where zoomApp:
            let scheme = url.scheme?.lowercased() ?? ""
            guard scheme == "https" || scheme == "http", let host = url.host, let number = zoomNumber(url.path) else {
                return url
            }
            var components = URLComponents()
            components.scheme = "zoommtg"
            components.host = host
            components.path = "/join"
            components.queryItems = [URLQueryItem(name: "action", value: "join"), URLQueryItem(name: "confno", value: number)]
                + (query(url, "pwd").map { [URLQueryItem(name: "pwd", value: $0)] } ?? [])
            return components.url ?? url
        case .teams where teamsApp:
            guard url.host?.lowercased() == "teams.microsoft.com",
                  let rest = url.absoluteString.range(of: "teams.microsoft.com", options: .caseInsensitive),
                  let app = URL(string: "msteams:" + url.absoluteString[rest.upperBound...]) else { return url }
            return app
        default:
            return url
        }
    }

    // MARK: - Underneath

    /// Whereby's own pages, which are not rooms.
    private static let wherebyPages: Set<String> = ["user", "information", "login", "signup", "org", "pricing",
                                                     "blog", "download", "support", "embed"]

    private static func isZoom(_ host: String) -> Bool {
        ["zoom.us", "zoomgov.com"].contains { host == $0 || host.hasSuffix("." + $0) }
    }

    private static func zoom(_ url: URL, path: String) -> ForkCalendarVideoLink? {
        if let number = zoomNumber(path) {
            return ForkCalendarVideoLink(provider: .zoom, url: url, key: "zoom:" + number)
        }
        let lowered = path.lowercased()
        guard lowered.hasPrefix("/my/"), lowered.count > 4 else { return nil }
        return ForkCalendarVideoLink(provider: .zoom, url: url, key: "zoom:" + lowered.dropFirst())
    }

    /// The meeting number of `/j/<n>`, `/w/<n>`, `/s/<n>` or `/wc/join/<n>`.
    private static func zoomNumber(_ path: String) -> String? {
        let parts = path.lowercased().split(separator: "/").map(String.init)
        let number: String?
        switch parts.first {
        case "j", "w", "s": number = parts.count > 1 ? parts[1] : nil
        case "wc": number = parts.count > 2 && parts[1] == "join" ? parts[2] : nil
        default: number = nil
        }
        guard let number, number.count >= 9, number.allSatisfy(\.isASCII), number.allSatisfy(\.isNumber) else { return nil }
        return number
    }

    /// A word without the punctuation a sentence puts around a link.
    private static func trimmed(_ word: String) -> String {
        var text = Substring(word)
        while let last = text.last, ".,;:!?)]}>*".contains(last) { text = text.dropLast() }
        while let first = text.first, "([{<*".contains(first) { text = text.dropFirst() }
        return String(text)
    }

    /// The link an Outlook safe link or a Google redirect wraps, else the link.
    private static func unwrapped(_ url: URL?) -> URL? {
        guard let url, let host = url.host?.lowercased() else { return url }
        let wrapped: String?
        if host.hasSuffix("safelinks.protection.outlook.com") {
            wrapped = query(url, "url")
        } else if (host == "google.com" || host == "www.google.com") && url.path == "/url" {
            wrapped = query(url, "q")
        } else {
            wrapped = nil
        }
        guard let wrapped, let inner = URL(string: trimmed(wrapped)), inner.host != nil else { return url }
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
