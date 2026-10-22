// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation
import Network

/// HTTP/1.1 over the private server's unix socket (`NWConnection` with
/// `NWEndpoint.unix`; URLSession does not reach unix sockets). One
/// connection per request: the server is local, a connection costs nothing,
/// and no state survives a server restart.
///
/// Each request has its own serial queue; its completion runs once on the
/// caller's queue, also after `cancel()` (`.canceled`).
final class ForkMacBackupSocketHTTP {
    struct Response {
        var head: ForkMacBackupHTTP.Head
        /// Empty when the body went to a sink.
        var body: Data

        var status: Int { head.status }
    }

    enum Failure: Error, Equatable {
        /// No server on the socket (missing, refused), or it hung up early.
        case unavailable(String)
        /// Nothing received for the idle timeout.
        case timeout
        case canceled
        case malformed
        /// A JSON body over `maxBodyBytes`.
        case tooLarge
        /// The sink refused bytes (disk full…).
        case sink
    }

    static let maxBodyBytes = 64 * 1024 * 1024

    let socketPath: String

    init(socketPath: String) {
        self.socketPath = socketPath
    }

    /// Sends `request`. `idleTimeout`: the longest wait for the next bytes.
    /// `sink`: the body's bytes go there as they arrive (a download); it
    /// returns false to stop.
    @discardableResult
    func send(_ request: ForkMacBackupHTTP.Request, idleTimeout: TimeInterval, callbackQueue: DispatchQueue,
              sink: ((ForkMacBackupHTTP.Head, Data) -> Bool)? = nil,
              completion: @escaping (Result<Response, Failure>) -> Void) -> ForkMacBackupCancellable {
        let exchange = Exchange(socketPath: socketPath, request: request, idleTimeout: idleTimeout,
                                callbackQueue: callbackQueue, sink: sink, completion: completion)
        exchange.start()
        return exchange
    }

    private final class Exchange: ForkMacBackupCancellable {
        private let queue = DispatchQueue(label: "fork.macbackup.http", qos: .utility)
        private let connection: NWConnection
        private let request: ForkMacBackupHTTP.Request
        private let idleTimeout: TimeInterval
        private let callbackQueue: DispatchQueue
        private let sink: ((ForkMacBackupHTTP.Head, Data) -> Bool)?
        private var completion: ((Result<Response, Failure>) -> Void)?
        private var reader = ForkMacBackupHTTP.ResponseReader()
        private var body = Data()
        private var done = false
        private var idle: DispatchWorkItem?
        private var keepAlive: Exchange?

        init(socketPath: String, request: ForkMacBackupHTTP.Request, idleTimeout: TimeInterval,
             callbackQueue: DispatchQueue, sink: ((ForkMacBackupHTTP.Head, Data) -> Bool)?,
             completion: @escaping (Result<Response, Failure>) -> Void) {
            connection = NWConnection(to: .unix(path: socketPath), using: .tcp)
            self.request = request
            self.idleTimeout = idleTimeout
            self.callbackQueue = callbackQueue
            self.sink = sink
            self.completion = completion
        }

        func start() {
            queue.async { [self] in
                keepAlive = self
                connection.stateUpdateHandler = { [weak self] state in self?.stateChanged(state) }
                armIdle()
                connection.start(queue: queue)
            }
        }

        func cancel() {
            queue.async { [self] in finish(.failure(.canceled)) }
        }

        private func stateChanged(_ state: NWConnection.State) {
            guard !done else { return }
            switch state {
            case .ready:
                connection.send(content: request.serialized(), completion: .contentProcessed { [weak self] error in
                    guard let self, let error else { return }
                    self.finish(.failure(.unavailable(error.localizedDescription)))
                })
                receive()
            case .waiting(let error):
                // A unix socket that refuses does not come back by itself.
                finish(.failure(.unavailable(error.localizedDescription)))
            case .failed(let error):
                finish(.failure(.unavailable(error.localizedDescription)))
            case .cancelled:
                finish(.failure(.canceled))
            default:
                break
            }
        }

        private func receive() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { [weak self] data, _, isComplete, error in
                guard let self, !self.done else { return }
                if let data, !data.isEmpty {
                    self.armIdle()
                    do {
                        let chunk = try self.reader.consume(data)
                        if !chunk.isEmpty, !self.deliver(chunk) { return }
                    } catch {
                        return self.finish(.failure(.malformed))
                    }
                }
                if self.reader.isComplete {
                    return self.succeed()
                }
                if isComplete {
                    if self.reader.finishAtClose() { return self.succeed() }
                    return self.finish(.failure(self.reader.head == nil ? .malformed : .unavailable("closed early")))
                }
                if let error {
                    return self.finish(.failure(.unavailable(error.localizedDescription)))
                }
                self.receive()
            }
        }

        /// False when the exchange ended (too large, sink refused).
        private func deliver(_ chunk: Data) -> Bool {
            if let sink, let head = reader.head {
                guard sink(head, chunk) else {
                    finish(.failure(.sink))
                    return false
                }
                return true
            }
            guard body.count + chunk.count <= ForkMacBackupSocketHTTP.maxBodyBytes else {
                finish(.failure(.tooLarge))
                return false
            }
            body.append(chunk)
            return true
        }

        private func succeed() {
            guard let head = reader.head else { return finish(.failure(.malformed)) }
            finish(.success(Response(head: head, body: body)))
        }

        private func armIdle() {
            idle?.cancel()
            let item = DispatchWorkItem { [weak self] in self?.finish(.failure(.timeout)) }
            idle = item
            queue.asyncAfter(deadline: .now() + idleTimeout, execute: item)
        }

        private func finish(_ result: Result<Response, Failure>) {
            guard !done else { return }
            done = true
            idle?.cancel()
            idle = nil
            connection.stateUpdateHandler = nil
            connection.cancel()
            let completion = self.completion
            self.completion = nil
            callbackQueue.async {
                completion?(result)
            }
            keepAlive = nil
        }
    }
}
