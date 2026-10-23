// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Darwin
import Foundation

/// One Kopia child (modelled on `HomebrewManager.runStreaming` and
/// `BoundedProcessRunner`): stdout collected (bounded), stderr streamed line
/// by line (Kopia redraws its progress with `\r`, both end a line), an
/// overall timeout and a silence timeout, and a cancel that sends SIGTERM,
/// then SIGKILL 3 s later.
///
/// Event-driven: no thread waits for the child (a termination handler and
/// the pipes' readability handlers feed one serial queue), so a long verify
/// or the long-lived server parks nothing. Exactly one completion, on that
/// queue, also after `cancel()`.
final class ForkMacBackupKopiaProcess: ForkMacBackupCancellable {
    struct Outcome {
        /// The exit code, or the signal that ended the child; -1 when it did
        /// not start.
        var status: Int32
        var stdout: Data
        /// The end of stderr (bounded), for the error line.
        var stderr: String
        var timedOut: Bool
        var canceled: Bool
        var launchFailed: Bool
        /// stdout went over the bound and was cut.
        var truncated: Bool

        var succeeded: Bool { status == 0 && !timedOut && !canceled && !launchFailed }
    }

    static let maxStdoutBytes = 128 * 1024 * 1024
    static let maxStderrTail = 256 * 1024
    static let killGrace: TimeInterval = 3

    let invocation: ForkMacBackupKopiaInvocation
    private let binary: URL
    private let queue: DispatchQueue
    private let onStderrLine: ((String) -> Void)?
    private let withStdinPipe: Bool

    private let process = Process()
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()
    private var stdinPipe: Pipe?
    private var completion: ((Outcome) -> Void)?

    // Owned by `queue`.
    private var stdout = Data()
    private var truncated = false
    private var stderrTail = ""
    private var stderrLine = Data()
    private var stdoutClosed = false
    private var stderrClosed = false
    private var exited = false
    private var finished = false
    private var timedOut = false
    private var canceled = false
    private var started = Date()
    private var lastOutput = Date()
    private var timer: DispatchSourceTimer?
    private var exitGrace: DispatchWorkItem?
    /// Held from `start` to the completion: a caller may drop its handle.
    private var keepAlive: ForkMacBackupKopiaProcess?

    /// `stdinPipe`: the child's stdin is a pipe the caller closes
    /// (`closeStdin()`), for `server start --shutdown-on-stdin`; else
    /// `/dev/null`.
    init(binary: URL, invocation: ForkMacBackupKopiaInvocation, queue: DispatchQueue,
         stdinPipe: Bool = false, onStderrLine: ((String) -> Void)? = nil) {
        self.binary = binary
        self.invocation = invocation
        self.queue = queue
        self.withStdinPipe = stdinPipe
        self.onStderrLine = onStderrLine
    }

    var processIdentifier: Int32? {
        process.isRunning ? process.processIdentifier : nil
    }

    /// Starts the child; `completion` runs once on the queue.
    func start(completion: @escaping (Outcome) -> Void) {
        queue.async { [self] in
            self.completion = completion
            keepAlive = self
            process.executableURL = binary
            process.arguments = invocation.arguments
            process.environment = invocation.environment
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            if withStdinPipe {
                let pipe = Pipe()
                stdinPipe = pipe
                process.standardInput = pipe
            } else {
                process.standardInput = FileHandle.nullDevice
            }
            switch invocation.priority {
            case .normal: process.qualityOfService = .default
            case .utility: process.qualityOfService = .utility
            case .background: process.qualityOfService = .background
            }
            stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                self?.queue.async { self?.receiveStdout(data) }
            }
            stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                self?.queue.async { self?.receiveStderr(data) }
            }
            process.terminationHandler = { [weak self] _ in
                self?.queue.async { self?.childExited() }
            }
            started = Date()
            lastOutput = started
            if canceled {
                return finish(launchFailed: false)
            }
            do {
                // The cloud-only files: downloaded only when the invocation says so.
                try ForkMacBackupDatalessPolicy.spawning(materialize: invocation.materializeDataless) {
                    try process.run()
                }
            } catch {
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                stderrTail = error.localizedDescription
                return finish(launchFailed: true)
            }
            // Only the child keeps the write ends: its exit closes them.
            try? stdoutPipe.fileHandleForWriting.close()
            try? stderrPipe.fileHandleForWriting.close()
            try? stdinPipe?.fileHandleForReading.close()
            startTimer()
        }
    }

    /// SIGTERM now, SIGKILL after `killGrace`; the completion reports
    /// `canceled`.
    func cancel() {
        queue.async { [self] in
            guard !finished, !canceled else { return }
            canceled = true
            stop()
        }
    }

    /// Closes the child's stdin (the server's shutdown signal).
    func closeStdin() {
        queue.async { [self] in
            try? stdinPipe?.fileHandleForWriting.close()
        }
    }

    // MARK: Events (on `queue`)

    private func receiveStdout(_ data: Data) {
        guard !data.isEmpty else {
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stdoutClosed = true
            return finishIfDone()
        }
        lastOutput = Date()
        let room = Self.maxStdoutBytes - stdout.count
        if room > 0 { stdout.append(data.prefix(room)) }
        if data.count > room { truncated = true }
    }

    private func receiveStderr(_ data: Data) {
        guard !data.isEmpty else {
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            stderrClosed = true
            flushStderrLine()
            return finishIfDone()
        }
        lastOutput = Date()
        for byte in data {
            if byte == 0x0A || byte == 0x0D {
                flushStderrLine()
            } else {
                stderrLine.append(byte)
                if stderrLine.count > 64 * 1024 { flushStderrLine() }
            }
        }
    }

    private func flushStderrLine() {
        guard !stderrLine.isEmpty else { return }
        let line = String(decoding: stderrLine, as: UTF8.self)
        stderrLine.removeAll(keepingCapacity: true)
        stderrTail += line + "\n"
        if stderrTail.utf8.count > Self.maxStderrTail {
            stderrTail = String(stderrTail.suffix(Self.maxStderrTail / 2))
        }
        onStderrLine?(line)
    }

    private func childExited() {
        exited = true
        timer?.cancel()
        timer = nil
        // A grandchild may keep the pipes open: wait a moment for EOF, then
        // finish without it.
        let grace = DispatchWorkItem { [weak self] in self?.finish(launchFailed: false) }
        exitGrace = grace
        queue.asyncAfter(deadline: .now() + 0.5, execute: grace)
        finishIfDone()
    }

    private func finishIfDone() {
        guard exited, stdoutClosed, stderrClosed else { return }
        finish(launchFailed: false)
    }

    private func finish(launchFailed: Bool) {
        guard !finished else { return }
        finished = true
        exitGrace?.cancel()
        timer?.cancel()
        timer = nil
        // The read ends are NOT closed here: a readability handler may be
        // inside `availableData` on another thread, which raises on a closed
        // descriptor (or reads a reused one). Their handlers stop now; the
        // pipes close when this process object goes.
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        try? stdinPipe?.fileHandleForWriting.close()
        flushStderrLine()
        let status: Int32 = launchFailed || !exited ? -1 : process.terminationStatus
        let outcome = Outcome(status: status, stdout: stdout, stderr: stderrTail, timedOut: timedOut,
                              canceled: canceled, launchFailed: launchFailed, truncated: truncated)
        let completion = self.completion
        self.completion = nil
        completion?(outcome)
        keepAlive = nil
    }

    // MARK: Timeouts

    private func startTimer() {
        let total = invocation.timeout
        let silence = invocation.silenceTimeout
        guard total.isFinite && total > 0 || silence != nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 1, leeway: .milliseconds(200))
        timer.setEventHandler { [weak self] in
            guard let self, !self.finished, !self.exited else { return }
            let now = Date()
            let overall = total.isFinite && total > 0 && now.timeIntervalSince(self.started) >= total
            let quiet = silence.map { now.timeIntervalSince(self.lastOutput) >= $0 } ?? false
            if overall || quiet {
                self.timedOut = true
                self.timer?.cancel()
                self.timer = nil
                self.stop()
            }
        }
        self.timer = timer
        timer.resume()
    }

    private func stop() {
        guard process.isRunning else {
            if !exited { finish(launchFailed: false) }
            return
        }
        let pid = process.processIdentifier
        process.terminate()
        queue.asyncAfter(deadline: .now() + Self.killGrace) { [weak self] in
            guard let self, !self.exited else { return }
            kill(pid, SIGKILL)
        }
    }
}
