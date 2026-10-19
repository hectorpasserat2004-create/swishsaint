// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation
import os

/// The recorder contract's calls (`ForkCastralContract`), to the CRM of one
/// profile, with its token.
///
/// - **Only the profile's origins**: the commands go to its address; the
///   sound goes to its exact upload host, checked before a byte leaves
///   (`ForkCastralProfile.allowsUpload`). No redirection is followed: a
///   custom header survives one, unlike `Authorization`, and the token
///   would go along.
/// - Ephemeral sessions (no cookie, no cache, no credential kept), bounded
///   in time, answers read no further than their cap.
/// - The token is never logged, nor the upload address, which lets anyone
///   write the sound for two hours.
struct ForkCastralClient {
    let profile: ForkCastralProfile
    let token: String
    var trust: ForkWebhookExporter.Trust = .system

    private static let log = Logger(subsystem: "fork.meetings", category: "castral")
    static let userAgent = "Swishsaint-Recorder/1"
    static let commandTimeout: TimeInterval = 20
    static let commandResourceTimeout: TimeInterval = 45
    static let maximumAnswerBytes = 4 << 20

    /// A token as a header carries it: visible ASCII, no space, no line.
    static func isToken(_ text: String) -> Bool {
        (8...512).contains(text.count) && text.unicodeScalars.allSatisfy { $0.value > 0x20 && $0.value < 0x7F }
    }

    /// What a call met, beside its answer.
    enum CallFailure: Error, Equatable {
        /// 401: the token is refused, or the server takes none.
        case token(String?)
        /// Another 4xx, with the server's sentence.
        case refused(Int, String?)
        /// 5xx, with the server's sentence.
        case server(Int, String?)
        /// An answer that is not the contract's shape.
        case shape(Int)
        case redirected
        case certificate
        case network
        /// The upload address is outside the profile: nothing left.
        case uploadHost

        var exportFailure: ForkMeetingExportFailure {
            switch self {
            case .token: return .castral(.tokenRefused)
            case .refused: return .castral(.rejected)
            case let .server(status, _): return .status(status)
            case let .shape(status): return .status(status)
            case .redirected: return .redirected
            case .certificate: return .certificate
            case .network: return .network
            case .uploadHost: return .castral(.uploadHost)
            }
        }

        /// The server's own sentence, when it gave one.
        var said: String? {
            switch self {
            case let .token(text), let .refused(_, text), let .server(_, text): return text
            default: return nil
            }
        }
    }

    // MARK: - The calls

    func targets(from: Date, to: Date) async -> Result<[ForkCastralContract.Booking], CallFailure> {
        let formatter = ISO8601DateFormatter()
        let query = [URLQueryItem(name: "from", value: formatter.string(from: from)),
                     URLQueryItem(name: "to", value: formatter.string(from: to))]
        return await command("GET", ForkCastralContract.targetsPath, query: query).flatMap { status, data in
            ForkCastralContract.bookings(data).map { .success($0) } ?? .failure(.shape(status))
        }
    }

    func open(_ opening: ForkCastralContract.Opening) async -> Result<ForkCastralContract.Opened, CallFailure> {
        await command("POST", ForkCastralContract.createPath, body: opening.body()).flatMap { status, data in
            ForkCastralContract.opened(data).map { .success($0) } ?? .failure(.shape(status))
        }
    }

    enum StartOutcome: Equatable {
        case started
        /// 409: the sound is not in the storage.
        case notArrived
        /// 404: no such deposit any more.
        case gone
    }

    func start(_ id: String) async -> Result<StartOutcome, CallFailure> {
        switch await command("POST", ForkCastralContract.startPath(id)) {
        case .success: return .success(.started)
        case .failure(.refused(409, _)): return .success(.notArrived)
        case .failure(.refused(404, _)): return .success(.gone)
        case let .failure(failure): return .failure(failure)
        }
    }

    func status(_ id: String) async -> Result<ForkCastralContract.Status, CallFailure> {
        await command("GET", ForkCastralContract.statusPath(id)).flatMap { status, data in
            ForkCastralContract.status(data).map { .success($0) } ?? .failure(.shape(status))
        }
    }

    func retry(_ id: String) async -> Result<Void, CallFailure> {
        await command("POST", ForkCastralContract.retryPath(id)).map { _ in () }
    }

    /// A deposit left uploading: the server takes it back only in that
    /// state, or failed. Best effort: an orphan costs less than a block.
    func abandon(_ id: String) async {
        if case let .failure(failure) = await command("DELETE", ForkCastralContract.depositPath(id)) {
            Self.log.notice("abandoned deposit not removed: \(String(describing: failure.exportFailure.code), privacy: .public)")
        }
    }

    /// Sends the sound to the deposit's address. The address is checked
    /// against the profile first: anywhere else, nothing leaves.
    func upload(_ file: URL, to address: URL, bytes: Int64,
                progress: @escaping (Double) -> Void) async -> Result<ForkCastralSteps.Upload, CallFailure> {
        guard profile.allowsUpload(to: address) else { return .failure(.uploadHost) }
        var request = URLRequest(url: address)
        request.httpMethod = "PUT"
        request.setValue(ForkCastralAudioPlan.Format.mimeType, forHTTPHeaderField: "Content-Type")
        let configuration = Self.configuration(idle: ForkWebhookLimits.idleTimeout,
                                               resource: ForkWebhookLimits.resourceTimeout(bodyBytes: bytes))
        let transfer = ForkCastralTransfer(origin: address, trust: trust, cap: ForkWebhookLimits.maximumResponseBytes,
                                           bodyBytes: bytes, progress: progress)
        let session = URLSession(configuration: configuration, delegate: transfer, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let ending = await transfer.run(session.uploadTask(with: request, fromFile: file))
        if let failure = Self.transportFailure(ending) { return .failure(failure) }
        guard let status = ending.status else { return .failure(.network) }
        // A 2xx before the whole sound left proves nothing.
        if (200..<300).contains(status), ending.sent < bytes { return .failure(.network) }
        let body = String(data: ending.data.prefix(4096), encoding: .utf8)
        return .success(ForkCastralSteps.upload(status: status, body: body))
    }

    // MARK: - Underneath

    private static func configuration(idle: TimeInterval, resource: TimeInterval) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = idle
        configuration.timeoutIntervalForResource = resource
        configuration.waitsForConnectivity = false
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.httpAdditionalHeaders = ["User-Agent": userAgent, "Accept-Language": "en"]
        return configuration
    }

    private func command(_ method: String, _ path: String, query: [URLQueryItem] = [],
                         body: Data? = nil) async -> Result<(Int, Data), CallFailure> {
        guard let url = profile.endpoint(path, query: query) else { return .failure(.network) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(token, forHTTPHeaderField: profile.tokenHeader)
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        let transfer = ForkCastralTransfer(origin: url, trust: trust, cap: Self.maximumAnswerBytes,
                                           bodyBytes: Int64(body?.count ?? 0), progress: { _ in })
        let session = URLSession(configuration: Self.configuration(idle: Self.commandTimeout,
                                                                   resource: Self.commandResourceTimeout),
                                 delegate: transfer, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let ending = await transfer.run(session.dataTask(with: request))
        if let failure = Self.transportFailure(ending) {
            Self.log.error("\(method, privacy: .public) \(Self.route(path), privacy: .public) failed: \(ending.errorCode ?? 0, privacy: .public)")
            return .failure(failure)
        }
        guard let status = ending.status else { return .failure(.network) }
        let said = ForkCastralContract.errorMessage(ending.data)
        switch status {
        case 200..<300: return .success((status, ending.data))
        case 401: return .failure(.token(said))
        case 400..<500: return .failure(.refused(status, said))
        default:
            Self.log.error("\(method, privacy: .public) \(Self.route(path), privacy: .public): \(status, privacy: .public)")
            return .failure(.server(status, said))
        }
    }

    /// The route without its deposit id, for the log.
    private static func route(_ path: String) -> String {
        path.split(separator: "/").map { ForkCastralContract.isID(String($0)) ? "<id>" : String($0) }.joined(separator: "/")
    }

    private static func transportFailure(_ ending: ForkCastralTransfer.Ending) -> CallFailure? {
        if ending.redirectRefused { return .redirected }
        if ending.trustRefused { return .certificate }
        if let status = ending.status, (300..<400).contains(status) { return .redirected }
        if ending.status == nil {
            if let code = ending.errorCode, ForkWebhookVerdict.certificateErrors.contains(code) { return .certificate }
            return .network
        }
        if ending.truncated { return .shape(ending.status ?? 0) }
        return nil
    }
}

/// One request's delegate: no redirection, the server's trust, the
/// answer's cap, the body sent.
final class ForkCastralTransfer: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    struct Ending: Equatable {
        var status: Int?
        var data = Data()
        var truncated = false
        var redirectRefused = false
        var trustRefused = false
        var errorCode: Int?
        var sent: Int64 = 0
    }

    private let origin: URL
    private let trust: ForkWebhookExporter.Trust
    private let cap: Int
    private let bodyBytes: Int64
    private let progress: (Double) -> Void
    private let lock = NSLock()
    /// Under `lock`.
    private var seen = Ending()
    private var continuation: CheckedContinuation<Ending, Never>?
    private var finished: Ending?

    init(origin: URL, trust: ForkWebhookExporter.Trust, cap: Int, bodyBytes: Int64, progress: @escaping (Double) -> Void) {
        self.origin = origin
        self.trust = trust
        self.cap = cap
        self.bodyBytes = bodyBytes
        self.progress = progress
    }

    func run(_ task: URLSessionTask) async -> Ending {
        await withCheckedContinuation { continuation in
            let done: Ending? = lock.withLock {
                if let finished { return finished }
                self.continuation = continuation
                return nil
            }
            if let done { continuation.resume(returning: done) } else { task.resume() }
        }
    }

    private func finish(_ ending: Ending) {
        let continuation: CheckedContinuation<Ending, Never>? = lock.withLock {
            guard finished == nil else { return nil }
            finished = ending
            defer { self.continuation = nil }
            return self.continuation
        }
        continuation?.resume(returning: ending)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        lock.withLock { seen.redirectRefused = true }
        completionHandler(nil)
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              case let .anchors(certificates) = trust, !certificates.isEmpty,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        SecTrustSetAnchorCertificates(serverTrust, certificates as CFArray)
        SecTrustSetAnchorCertificatesOnly(serverTrust, true)
        if SecTrustEvaluateWithError(serverTrust, nil) {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            lock.withLock { seen.trustRefused = true }
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        lock.withLock { seen.sent = totalBytesSent }
        let total = totalBytesExpectedToSend > 0 ? totalBytesExpectedToSend : bodyBytes
        guard total > 0 else { return }
        progress(min(1, Double(totalBytesSent) / Double(total)))
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let code = (response as? HTTPURLResponse)?.statusCode
        lock.withLock { seen.status = code }
        completionHandler(response.expectedContentLength > Int64(cap) ? .cancel : .allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let over = lock.withLock { () -> Bool in
            guard seen.data.count + data.count <= cap else {
                seen.truncated = true
                return true
            }
            seen.data.append(data)
            return false
        }
        if over { dataTask.cancel() }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let ending = lock.withLock { () -> Ending in
            seen.errorCode = (error as NSError?)?.code
            if seen.status != nil, error != nil, !seen.truncated, (error as NSError?)?.code != NSURLErrorCancelled {
                // The answer began, then the connection dropped.
                seen.status = nil
            }
            return seen
        }
        finish(ending)
    }
}
