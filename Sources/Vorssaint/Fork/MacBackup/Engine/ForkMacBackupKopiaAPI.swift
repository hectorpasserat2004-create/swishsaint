// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// The private server's two APIs (SPIKES §2.2), over its unix socket:
///
/// - control (`/api/v1/control/*`): Basic `server-control:<password>`;
/// - UI (`/api/v1/*`, the server runs with `--ui`): Basic
///   `swishsaint:<password>` plus the session cookie and CSRF token the UI
///   page hands out (`GET /`), fetched once and again after a 401;
/// - downloads (`/api/v1/objects/{oid}`): Basic only.
///
/// Completions run on `queue`. Never logs a password or a token.
final class ForkMacBackupKopiaAPI {
    enum Auth {
        case control
        case ui
        /// Basic auth only (`/api/v1/objects`).
        case uiWithoutCSRF
    }

    typealias Failure = ForkMacBackupAPIFailure

    let info: ForkMacBackupServerInfo
    let queue: DispatchQueue
    private let http: ForkMacBackupSocketHTTP
    private let lock = NSLock()
    private var session: (cookie: String, token: String)?

    static let jsonTimeout: TimeInterval = 60

    init(info: ForkMacBackupServerInfo, queue: DispatchQueue) {
        self.info = info
        self.queue = queue
        http = ForkMacBackupSocketHTTP(socketPath: info.socketPath)
    }

    // MARK: Calls

    /// One JSON call; the body (`json`) is any JSON object.
    func call(_ method: String, _ path: String, query: [(String, String)] = [], json: Any? = nil, auth: Auth,
              timeout: TimeInterval = jsonTimeout, completion: @escaping (Result<Data, Failure>) -> Void) {
        var body: Data?
        if let json {
            guard let data = try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys]) else {
                return queue.async { completion(.failure(.engine(.decoding("request body")))) }
            }
            body = data
        }
        let target = ForkMacBackupHTTP.path(path, query: query)
        perform(method, target, body: body, auth: auth, timeout: timeout, retryOn401: true, completion: completion)
    }

    /// A JSON call decoded as `type`.
    func decode<Value: Decodable>(_ type: Value.Type, _ method: String, _ path: String, query: [(String, String)] = [],
                                  json: Any? = nil, auth: Auth, timeout: TimeInterval = jsonTimeout,
                                  completion: @escaping (Result<Value, Failure>) -> Void) {
        call(method, path, query: query, json: json, auth: auth, timeout: timeout) { result in
            completion(result.flatMap { data in
                guard let value = ForkMacBackupKopia.decode(type, from: data) else {
                    return .failure(.engine(.decoding(String(describing: type))))
                }
                return .success(value)
            })
        }
    }

    /// Streams `/api/v1/objects/{oid}` into `sink` (`Range` is not needed:
    /// one go). `progress` gets the bytes received so far.
    @discardableResult
    func download(objectID: String, sink: @escaping (Data) -> Bool, progress: @escaping (Int64) -> Void,
                  completion: @escaping (Result<Int64, Failure>) -> Void) -> ForkMacBackupCancellable {
        let request = ForkMacBackupHTTP.Request(method: "GET",
                                                target: "/api/v1/objects/" + ForkMacBackupHTTP.percentEncoded(objectID),
                                                headers: headers(auth: .uiWithoutCSRF))
        var received: Int64 = 0
        var status = 0
        return http.send(request, idleTimeout: 120, callbackQueue: queue, sink: { head, chunk in
            status = head.status
            guard head.status / 100 == 2 else { return true }
            received += Int64(chunk.count)
            progress(received)
            return sink(chunk)
        }, completion: { result in
            switch result {
            case .success(let response):
                if response.status / 100 == 2 { return completion(.success(received)) }
                completion(.failure(Self.failure(status: response.status == 0 ? status : response.status,
                                                 body: response.body)))
            case .failure(let failure):
                completion(.failure(.engine(Self.engineError(failure))))
            }
        })
    }

    // MARK: Plumbing

    private func perform(_ method: String, _ target: String, body: Data?, auth: Auth, timeout: TimeInterval,
                         retryOn401: Bool, completion: @escaping (Result<Data, Failure>) -> Void) {
        if auth == .ui, currentSession() == nil {
            return openSession { [weak self] error in
                guard let self else { return }
                if let error { return completion(.failure(error)) }
                self.perform(method, target, body: body, auth: auth, timeout: timeout, retryOn401: retryOn401,
                             completion: completion)
            }
        }
        var headers = headers(auth: auth)
        if body != nil { headers.append(("Content-Type", "application/json")) }
        let request = ForkMacBackupHTTP.Request(method: method, target: target, headers: headers, body: body)
        http.send(request, idleTimeout: timeout, callbackQueue: queue) { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let failure):
                completion(.failure(.engine(Self.engineError(failure))))
            case .success(let response) where response.status / 100 == 2:
                completion(.success(response.body))
            case .success(let response) where response.status == 401 && auth == .ui && retryOn401:
                // The session expired (or the server restarted): a new one, once.
                self.clearSession()
                self.perform(method, target, body: body, auth: auth, timeout: timeout, retryOn401: false,
                             completion: completion)
            case .success(let response):
                completion(.failure(Self.failure(status: response.status, body: response.body)))
            }
        }
    }

    private func headers(auth: Auth) -> [(name: String, value: String)] {
        switch auth {
        case .control:
            return [("Authorization", ForkMacBackupHTTP.basicAuthorization(user: info.controlUser,
                                                                          password: info.controlPassword))]
        case .uiWithoutCSRF:
            return [("Authorization", ForkMacBackupHTTP.basicAuthorization(user: info.serverUser,
                                                                          password: info.serverPassword))]
        case .ui:
            var headers = headers(auth: .uiWithoutCSRF)
            if let session = currentSession() {
                headers.append(("Cookie", "Kopia-Session-Cookie=\(session.cookie)"))
                headers.append(("X-Kopia-Csrf-Token", session.token))
            }
            return headers
        }
    }

    /// `GET /` with Basic auth: the session cookie and the page's CSRF token.
    private func openSession(_ completion: @escaping (Failure?) -> Void) {
        let request = ForkMacBackupHTTP.Request(method: "GET", target: "/", headers: headers(auth: .uiWithoutCSRF))
        http.send(request, idleTimeout: Self.jsonTimeout, callbackQueue: queue) { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let failure):
                completion(.engine(Self.engineError(failure)))
            case .success(let response):
                guard response.status / 100 == 2 else {
                    return completion(Self.failure(status: response.status, body: response.body))
                }
                guard let cookie = response.head.cookies["Kopia-Session-Cookie"],
                      let token = ForkMacBackupHTTP.csrfToken(inHTML: String(decoding: response.body, as: UTF8.self))
                else { return completion(.engine(.decoding("UI session"))) }
                self.lock.withLock { self.session = (cookie, token) }
                completion(nil)
            }
        }
    }

    private func currentSession() -> (cookie: String, token: String)? {
        lock.withLock { session }
    }

    private func clearSession() {
        lock.withLock { session = nil }
    }

    static func engineError(_ failure: ForkMacBackupSocketHTTP.Failure) -> ForkMacBackupEngineError {
        switch failure {
        case .unavailable: return .serverUnavailable
        case .timeout: return .timeout
        case .canceled: return .canceled
        case .malformed: return .decoding("HTTP")
        case .tooLarge: return .decoding("response too large")
        case .sink: return .other("write failed")
        }
    }

    static func failure(status: Int, body: Data) -> Failure {
        ForkMacBackupAPIFailure.from(status: status, body: body)
    }
}
