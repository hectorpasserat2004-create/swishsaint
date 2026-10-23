// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// A minimal HTTP/1.1 client's messages, for Kopia's private server on its
/// unix socket (URLSession does not speak to unix sockets). One request per
/// connection (`Connection: close`), so the reader only has to know where a
/// response ends: `Content-Length`, `chunked`, or the connection's close.
enum ForkMacBackupHTTP {
    struct Request: Equatable {
        var method: String
        /// Path and query, already encoded (`path(_:query:)`).
        var target: String
        var headers: [(name: String, value: String)]
        var body: Data?

        init(method: String, target: String, headers: [(name: String, value: String)] = [], body: Data? = nil) {
            self.method = method
            self.target = target
            self.headers = headers
            self.body = body
        }

        static func == (lhs: Request, rhs: Request) -> Bool {
            lhs.method == rhs.method && lhs.target == rhs.target && lhs.body == rhs.body
                && lhs.headers.map { "\($0.name):\($0.value)" } == rhs.headers.map { "\($0.name):\($0.value)" }
        }

        /// The bytes on the wire.
        func serialized() -> Data {
            var head = "\(method) \(target) HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n"
            for header in headers { head += "\(header.name): \(header.value)\r\n" }
            if let body {
                head += "Content-Length: \(body.count)\r\n"
            } else if method != "GET", method != "HEAD" {
                head += "Content-Length: 0\r\n"
            }
            head += "\r\n"
            var data = Data(head.utf8)
            if let body { data.append(body) }
            return data
        }
    }

    struct Head: Equatable {
        var status: Int
        /// Lower-cased names; a repeated header keeps every value.
        var headers: [String: [String]]

        func value(_ name: String) -> String? { headers[name.lowercased()]?.first }

        var contentLength: Int64? { value("content-length").flatMap { Int64($0.trimmingCharacters(in: .whitespaces)) } }

        var isChunked: Bool { value("transfer-encoding")?.lowercased().contains("chunked") ?? false }

        /// `name=value` of every `Set-Cookie`.
        var cookies: [String: String] {
            var cookies: [String: String] = [:]
            for line in headers["set-cookie"] ?? [] {
                guard let pair = line.split(separator: ";", maxSplits: 1).first,
                      let equals = pair.firstIndex(of: "=") else { continue }
                let name = pair[..<equals].trimmingCharacters(in: .whitespaces)
                let value = pair[pair.index(after: equals)...].trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { cookies[name] = value }
            }
            return cookies
        }
    }

    // MARK: Encoding

    /// `Basic <base64(user:password)>`.
    static func basicAuthorization(user: String, password: String) -> String {
        "Basic " + Data("\(user):\(password)".utf8).base64EncodedString()
    }

    /// RFC 3986 unreserved characters only: a path like `/Users/x y/ü` goes
    /// through any query or path segment intact.
    static func percentEncoded(_ text: String) -> String {
        // ASCII only: `CharacterSet.alphanumerics` holds every Unicode letter,
        // which would go raw into the request line.
        text.addingPercentEncoding(withAllowedCharacters: unreserved) ?? text
    }

    private static let unreserved = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")

    /// `/api/v1/x?a=1&b=2`, every query value encoded.
    static func path(_ path: String, query: [(String, String)] = []) -> String {
        guard !query.isEmpty else { return path }
        return path + "?" + query.map { "\(percentEncoded($0.0))=\(percentEncoded($0.1))" }.joined(separator: "&")
    }

    /// The `<meta name="kopia-csrf-token" content="…">` of the UI page.
    static func csrfToken(inHTML html: String) -> String? {
        guard let name = html.range(of: "kopia-csrf-token") else { return nil }
        let tail = html[name.upperBound...]
        guard let content = tail.range(of: "content=\"") else { return nil }
        let value = tail[content.upperBound...].prefix { $0 != "\"" }
        return value.isEmpty ? nil : String(value)
    }

    // MARK: Response reading

    /// Reads a response as it arrives: the head, then the body's bytes,
    /// de-chunked. Feed it everything received; it tells when the body is
    /// complete. Not thread-safe: one connection's queue owns it.
    struct ResponseReader {
        enum Failure: Error, Equatable {
            case malformedHead
            case malformedChunk
            case headTooLarge
        }

        private(set) var head: Head?
        private var buffer = Data()
        private var remaining: Int64?
        private var chunked = false
        private var chunkRemaining: Int64 = 0
        private var chunkState = ChunkState.size
        private(set) var isComplete = false
        /// Body bytes given out so far.
        private(set) var bodyBytes: Int64 = 0

        private enum ChunkState { case size, data, dataEnd, trailer }

        static let maxHeadBytes = 64 * 1024

        init() {}

        /// Takes `data`, returns the body bytes it completes (de-chunked).
        mutating func consume(_ data: Data) throws -> Data {
            buffer.append(data)
            var body = Data()
            if head == nil {
                guard let end = buffer.range(of: Data("\r\n\r\n".utf8)) else {
                    if buffer.count > Self.maxHeadBytes { throw Failure.headTooLarge }
                    return body
                }
                let headData = buffer.subdata(in: buffer.startIndex..<end.lowerBound)
                buffer = buffer.subdata(in: end.upperBound..<buffer.endIndex)
                let parsed = try Self.parseHead(headData)
                head = parsed
                chunked = parsed.isChunked
                remaining = chunked ? nil : parsed.contentLength
                if parsed.status == 204 || parsed.status == 304 || (!chunked && remaining == 0) {
                    isComplete = true
                    return body
                }
            }
            if chunked {
                try readChunks(into: &body)
            } else if let left = remaining {
                let take = Int(min(Int64(buffer.count), left))
                body.append(buffer.prefix(take))
                buffer.removeFirst(take)
                remaining = left - Int64(take)
                if remaining == 0 { isComplete = true }
            } else {
                body.append(buffer)
                buffer.removeAll()
            }
            bodyBytes += Int64(body.count)
            return body
        }

        /// The connection closed: a body without length ends here.
        mutating func finishAtClose() -> Bool {
            if head != nil, !chunked, remaining == nil { isComplete = true }
            return isComplete
        }

        private mutating func readChunks(into body: inout Data) throws {
            let crlf = Data("\r\n".utf8)
            while !isComplete {
                switch chunkState {
                case .size:
                    guard let end = buffer.range(of: crlf) else { return }
                    let line = String(decoding: buffer.subdata(in: buffer.startIndex..<end.lowerBound), as: UTF8.self)
                    buffer = buffer.subdata(in: end.upperBound..<buffer.endIndex)
                    let hex = line.split(separator: ";").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
                    guard let size = Int64(hex, radix: 16), size >= 0 else { throw Failure.malformedChunk }
                    chunkRemaining = size
                    chunkState = size == 0 ? .trailer : .data
                case .data:
                    guard !buffer.isEmpty else { return }
                    let take = Int(min(Int64(buffer.count), chunkRemaining))
                    body.append(buffer.prefix(take))
                    buffer.removeFirst(take)
                    chunkRemaining -= Int64(take)
                    if chunkRemaining == 0 { chunkState = .dataEnd }
                case .dataEnd:
                    guard buffer.count >= 2 else { return }
                    guard buffer.prefix(2) == crlf else { throw Failure.malformedChunk }
                    buffer.removeFirst(2)
                    chunkState = .size
                case .trailer:
                    guard let end = buffer.range(of: crlf) else { return }
                    let empty = end.lowerBound == buffer.startIndex
                    buffer = buffer.subdata(in: end.upperBound..<buffer.endIndex)
                    if empty { isComplete = true }
                }
            }
        }

        static func parseHead(_ data: Data) throws -> Head {
            let text = String(decoding: data, as: UTF8.self)
            var lines = text.components(separatedBy: "\r\n")
            guard !lines.isEmpty else { throw Failure.malformedHead }
            let status = lines.removeFirst().split(separator: " ")
            guard status.count >= 2, status[0].hasPrefix("HTTP/"), let code = Int(status[1]) else {
                throw Failure.malformedHead
            }
            var headers: [String: [String]] = [:]
            for line in lines where !line.isEmpty {
                guard let colon = line.firstIndex(of: ":") else { continue }
                let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                headers[name, default: []].append(value)
            }
            return Head(status: code, headers: headers)
        }
    }

    // MARK: Errors

    /// `{"code":"NOT_CONNECTED","error":"…"}`, the server's error body.
    struct APIError: Decodable, Equatable {
        var code: String?
        var error: String?
    }

    static func apiError(_ body: Data) -> APIError? {
        guard let error = try? JSONDecoder().decode(APIError.self, from: body),
              error.code != nil || error.error != nil else { return nil }
        return error
    }
}

/// How a call to the private server failed.
enum ForkMacBackupAPIFailure: Error, Equatable {
    case engine(ForkMacBackupEngineError)
    /// The server answered with this status (not 2xx, not handled).
    case status(Int, String)

    /// « policy not found » (400), « no source matching the provided
    /// filters » (404): the thing asked for does not exist (yet).
    var isNotFound: Bool {
        guard case .status(let code, let message) = self else { return false }
        let text = message.lowercased()
        return code == 404 || text.contains("not found") || text.contains("no source matching")
    }

    var engineError: ForkMacBackupEngineError {
        switch self {
        case .engine(let error): return error
        case .status(let code, let message): return .kopia(exitCode: Int32(code), message: message)
        }
    }

    /// A non-2xx answer: « not connected » (400 NOT_CONNECTED), a refused
    /// password (401/403: the server restarted with new ones), or Kopia's
    /// message.
    static func from(status: Int, body: Data) -> ForkMacBackupAPIFailure {
        let apiError = ForkMacBackupHTTP.apiError(body)
        if apiError?.code == "NOT_CONNECTED" { return .engine(.notConnected) }
        if status == 401 || status == 403 { return .engine(.serverUnavailable) }
        let message = apiError?.error ?? String(decoding: body.prefix(300), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return .status(status, message)
    }
}
