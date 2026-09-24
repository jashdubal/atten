import Foundation

/// Speaks through one long-lived `cli.py serve` process, so Kokoro loads once
/// instead of in front of every generation, voice preview and sample.
///
/// Requests run one at a time, in the order they arrive. The process starts
/// with the first request, stops after `idleTimeout` without one, and is
/// replaced whenever it dies or ignores a cancel. A backend too old to serve
/// is driven through `ProcessBackendClient` instead.
public final class PersistentBackendClient: TTSGenerating, @unchecked Sendable {
    private let installation: BackendInstallation?
    private let environment: [String: String]
    private let fallback: ProcessBackendClient
    private let idleTimeout: TimeInterval
    private let cancelTimeout: TimeInterval
    private let readyTimeout: TimeInterval
    private let lock = NSLock()
    private var server: ServeProcess?
    private var current: Job?
    private var waiting: [Job] = []
    /// Every job still in flight, keyed by the id a sharing owner cancels by
    /// — including one not yet current or waiting, so a cancel that lands in
    /// that gap is not lost.
    private var jobsByID: [String: Job] = [:]
    private var usesFallback = false
    private var idleToken = 0

    public init(
        installation: BackendInstallation? = BackendLocator.locateInstallation(),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        idleTimeout: TimeInterval = 600,
        cancelTimeout: TimeInterval = 2,
        readyTimeout: TimeInterval = 30
    ) {
        self.installation = installation
        self.environment = environment
        self.fallback = ProcessBackendClient(installation: installation, environment: environment)
        self.idleTimeout = idleTimeout
        self.cancelTimeout = cancelTimeout
        self.readyTimeout = readyTimeout
    }

    public func generateStream(_ request: GenerationRequest) -> AsyncThrowingStream<GenerationEvent, Error> {
        generateStream(request, id: UUID().uuidString)
    }

    /// `id` names this request on the wire, so a caller sharing this client
    /// with another owner can cancel its own request without reaching theirs.
    public func generateStream(
        _ request: GenerationRequest,
        id: String
    ) -> AsyncThrowingStream<GenerationEvent, Error> {
        var request = request
        if request.segmentsDirectory == nil {
            request.segmentsDirectory = request.outputDirectory
                .appendingPathComponent("segments-\(UUID().uuidString)", isDirectory: true)
        }
        let streamingRequest = request
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let output = try await generate(streamingRequest, id: id) { line in
                        guard let event = try? JSONDecoder().decode(ProcessBackendClient.Event.self, from: line)
                        else { return }
                        if let value = event.generationEvent { continuation.yield(value) }
                    }
                    continuation.yield(.completed(output.url))
                    continuation.finish()
                } catch {
                    continuation.yield(.failed(error.localizedDescription))
                    continuation.finish(throwing: error)
                }
            }
            // Cancelling the task cancels this request alone; anything queued
            // behind it still runs.
            continuation.onTermination = { termination in
                if case .cancelled = termination { task.cancel() }
            }
        }
    }

    public func generate(_ request: GenerationRequest) async throws -> GenerationOutput {
        try await generate(request, id: UUID().uuidString)
    }

    /// `id` names this request on the wire, so a caller sharing this client
    /// with another owner can cancel its own request without reaching theirs.
    public func generate(_ request: GenerationRequest, id: String) async throws -> GenerationOutput {
        try await generate(request, id: id, onLine: nil)
    }

    /// Stops the request in progress and every request waiting behind it.
    public func cancel() {
        let (dropped, running, server, usesFallback) = lock.withLock {
            let dropped = waiting
            waiting = []
            for job in dropped + [current].compactMap({ $0 }) { job.cancelled = true }
            return (dropped, current, self.server, self.usesFallback)
        }
        for job in dropped { job.turn?.resume(throwing: BackendError.cancelled) }
        if let running { server?.cancel(running.id) }
        if usesFallback { fallback.cancel() }
    }

    /// Closes the engine's input, so it finishes the segment it is on and exits.
    public func shutdown() {
        let server = lock.withLock {
            defer { self.server = nil }
            return self.server
        }
        server?.close()
    }

    private func generate(
        _ request: GenerationRequest,
        id: String,
        onLine: (@Sendable (Data) -> Void)?
    ) async throws -> GenerationOutput {
        guard !request.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BackendError.invalidRequest("Enter some text before generating speech.")
        }
        guard let installation else { throw BackendError.backendNotFound }

        let job = Job(id: id)
        lock.withLock { jobsByID[id] = job }
        defer { lock.withLock { _ = jobsByID.removeValue(forKey: id) } }
        try await waitForTurn(job)
        defer { finishTurn() }
        if lock.withLock({ usesFallback }) {
            return try await fallback.generate(request, onLine: onLine)
        }

        return try await withTaskCancellationHandler {
            do {
                try Task.checkCancellation()
                if isCancelled(job) { throw BackendError.cancelled }
                let server: ServeProcess
                do {
                    server = try await runningServer(for: installation)
                } catch ServeProcess.Unavailable.unavailable {
                    lock.withLock { usesFallback = true }
                    return try await fallback.generate(request, onLine: onLine)
                }
                let output = try await server.perform(
                    id: job.id,
                    line: try Self.requestLine(for: request, id: job.id),
                    onLine: onLine,
                    isCancelled: { self.isCancelled(job) }
                )
                if isCancelled(job) { throw BackendError.cancelled }
                return output
            } catch where isCancelled(job) || Task.isCancelled {
                throw BackendError.cancelled
            }
        } onCancel: {
            self.cancel(id: job.id)
        }
    }

    private func runningServer(for installation: BackendInstallation) async throws -> ServeProcess {
        if let server = lock.withLock({ self.server }), server.isRunning { return server }
        let command = BackendRuntime.command(for: installation, environment: environment)
        let server = ServeProcess(
            executable: command.executable,
            arguments: command.arguments + installation.entrypointArguments + ["serve"],
            workingDirectory: installation.workingDirectory,
            environment: BackendRuntime.environment(for: installation, inheriting: environment),
            cancelTimeout: cancelTimeout,
            // A signal nobody asked for is Gatekeeper when the engine is still
            // marked as downloaded, and otherwise an engine that died.
            crashError: { process in
                process.terminationReason == .uncaughtSignal && installation.isQuarantined
                    ? .blockedByGatekeeper
                    : .stoppedUnexpectedly
            }
        )
        try await server.start(readyTimeout: readyTimeout)
        lock.withLock { self.server = server }
        return server
    }

    private func waitForTurn(_ job: Job) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (turn: CheckedContinuation<Void, Error>) in
                lock.lock()
                if job.cancelled {
                    lock.unlock()
                    turn.resume(throwing: BackendError.cancelled)
                    return
                }
                idleToken += 1
                if current == nil {
                    current = job
                    lock.unlock()
                    turn.resume()
                } else {
                    job.turn = turn
                    waiting.append(job)
                    lock.unlock()
                }
            }
        } onCancel: {
            self.cancel(id: job.id)
        }
    }

    private func finishTurn() {
        let (next, token): (Job?, Int) = lock.withLock {
            idleToken += 1
            guard !waiting.isEmpty else {
                current = nil
                return (nil, idleToken)
            }
            current = waiting.removeFirst()
            return (current, idleToken)
        }
        if let next {
            next.turn?.resume()
            return
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + idleTimeout) { [weak self] in
            guard let self else { return }
            let idle = lock.withLock { () -> ServeProcess? in
                guard idleToken == token, current == nil else { return nil }
                defer { server = nil }
                return server
            }
            idle?.close()
        }
    }

    /// Cancels one request by id: a waiting one never reaches the engine, and
    /// the running one is asked to stop. A request submitted by another owner
    /// sharing this client is untouched, since its id is never matched.
    public func cancel(id: String) {
        guard let (turn, isCurrent, server, usesFallback) = lock.withLock({
            () -> (CheckedContinuation<Void, Error>?, Bool, ServeProcess?, Bool)? in
            guard let job = jobsByID[id] else { return nil }
            job.cancelled = true
            if let index = waiting.firstIndex(where: { $0 === job }) {
                waiting.remove(at: index)
                return (job.turn, false, nil, false)
            }
            return (nil, current === job, self.server, self.usesFallback)
        }) else { return }
        turn?.resume(throwing: BackendError.cancelled)
        if isCurrent {
            server?.cancel(id)
            if usesFallback { fallback.cancel() }
        }
    }

    private func isCancelled(_ job: Job) -> Bool {
        lock.withLock { job.cancelled }
    }

    static func requestLine(for request: GenerationRequest, id: String) throws -> Data {
        var body: [String: Any] = [
            "id": id,
            "op": "generate",
            "text": request.text,
            "voice": request.voiceID,
            "speed": request.speed,
            "format": request.format.rawValue,
            "output": request.outputDirectory.path,
            "filename": request.filename,
            "device": request.useMPS ? "auto" : "cpu",
        ]
        if let modelID = request.modelID { body["model"] = modelID }
        if let directory = request.segmentsDirectory { body["segments_dir"] = directory.path }
        if let pauseLength = request.pauseLength { body["pause"] = pauseLength.rawValue }
        return try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys, .withoutEscapingSlashes])
            + Data([10])
    }

    /// One request's place in line. Its fields are guarded by the client's lock.
    private final class Job: @unchecked Sendable {
        let id: String
        var cancelled = false
        var turn: CheckedContinuation<Void, Error>?

        init(id: String) { self.id = id }
    }
}

/// One running `serve` process: its pipes, the request it is answering, and
/// how it ends.
private final class ServeProcess: @unchecked Sendable {
    enum Unavailable: Error { case unavailable }

    private struct Pending {
        let id: String
        let onLine: (@Sendable (Data) -> Void)?
        let continuation: CheckedContinuation<GenerationOutput, Error>
    }

    private struct Envelope: Decodable {
        let event: String
        let id: String?
    }

    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let cancelTimeout: TimeInterval
    private let crashError: @Sendable (Process) -> BackendError
    private let lock = NSLock()
    private var readiness: Result<Void, Error>?
    private var readyWaiter: CheckedContinuation<Void, Error>?
    private var pending: Pending?
    private var exited = false
    private var closed = false

    init(
        executable: URL,
        arguments: [String],
        workingDirectory: URL,
        environment: [String: String],
        cancelTimeout: TimeInterval,
        crashError: @escaping @Sendable (Process) -> BackendError
    ) {
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
        process.environment = environment
        process.standardInput = input
        process.standardOutput = output
        self.cancelTimeout = cancelTimeout
        self.crashError = crashError
    }

    var isRunning: Bool {
        lock.withLock { !exited && !closed }
    }

    /// Launches the process and waits for its `ready` event. Anything else
    /// first, an exit, or silence means this backend cannot serve.
    func start(readyTimeout: TimeInterval) async throws {
        // A write to an engine that has died fails instead of killing Atten.
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        process.terminationHandler = { [self] process in handleExit(process) }
        do {
            try process.run()
        } catch {
            throw BackendError.processFailed(error.localizedDescription)
        }
        Thread.detachNewThread { [self] in readLines() }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + readyTimeout) { [self] in
            settleReadiness(.failure(Unavailable.unavailable))
        }
        try await withCheckedThrowingContinuation { (waiter: CheckedContinuation<Void, Error>) in
            lock.lock()
            if let readiness {
                lock.unlock()
                waiter.resume(with: readiness)
            } else {
                readyWaiter = waiter
                lock.unlock()
            }
        }
    }

    func perform(
        id: String,
        line: Data,
        onLine: (@Sendable (Data) -> Void)?,
        isCancelled: @escaping @Sendable () -> Bool
    ) async throws -> GenerationOutput {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if exited {
                lock.unlock()
                continuation.resume(throwing: crashError(process))
                return
            }
            pending = Pending(id: id, onLine: onLine, continuation: continuation)
            lock.unlock()
            do {
                try input.fileHandleForWriting.write(contentsOf: line)
            } catch {
                // The engine is gone or going; its exit fails this request.
                process.terminate()
            }
            if isCancelled() { cancel(id) }
        }
    }

    /// Asks the engine to stop `id` at its next segment, and replaces an
    /// engine that has not stopped within `cancelTimeout`.
    func cancel(_ id: String) {
        guard lock.withLock({ pending?.id == id }) else { return }
        let line = #"{"id":"\#(id)","op":"cancel"}"# + "\n"
        try? input.fileHandleForWriting.write(contentsOf: Data(line.utf8))
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + cancelTimeout) { [self] in
            let unresponsive = lock.withLock { () -> Bool in
                guard pending?.id == id else { return false }
                closed = true
                return true
            }
            if unresponsive { process.terminate() }
        }
    }

    func close() {
        lock.withLock { closed = true }
        try? input.fileHandleForWriting.close()
    }

    private func readLines() {
        let handle = output.fileHandleForReading
        var buffered = Data()
        while true {
            let chunk = handle.availableData
            if chunk.isEmpty { break }
            buffered.append(chunk)
            while let newline = buffered.firstIndex(of: 10) {
                let line = Data(buffered[buffered.startIndex..<newline])
                buffered.removeSubrange(...newline)
                receive(line)
            }
        }
    }

    private func receive(_ line: Data) {
        let envelope = try? JSONDecoder().decode(Envelope.self, from: line)
        if lock.withLock({ readiness == nil }) {
            if envelope?.event == "ready" {
                settleReadiness(.success(()))
            } else {
                // An older backend reads `serve` as text to speak; stop it
                // before it writes anything.
                settleReadiness(.failure(Unavailable.unavailable))
            }
            return
        }
        lock.lock()
        guard let request = pending, let envelope, envelope.id == request.id else {
            lock.unlock()
            return
        }
        let result: Result<GenerationOutput, Error>
        switch envelope.event {
        case "completed":
            if let completed = try? JSONDecoder().decode(ProcessBackendClient.Event.self, from: line),
               let path = completed.path {
                result = .success(GenerationOutput(
                    url: URL(fileURLWithPath: path),
                    segmentCount: completed.segments ?? 0,
                    sampleRate: completed.sampleRate ?? 24_000
                ))
            } else {
                result = .failure(BackendError.malformedResponse)
            }
        case "error":
            let message = (try? JSONDecoder().decode(ProcessBackendClient.Event.self, from: line))?.message
            result = .failure(BackendError.processFailed(message ?? "Speech generation failed."))
        case "cancelled":
            result = .failure(BackendError.cancelled)
        default:
            lock.unlock()
            request.onLine?(line)
            return
        }
        pending = nil
        lock.unlock()
        request.continuation.resume(with: result)
    }

    private func settleReadiness(_ result: Result<Void, Error>) {
        let (settled, waiter) = lock.withLock { () -> (Bool, CheckedContinuation<Void, Error>?) in
            guard readiness == nil else { return (false, nil) }
            readiness = result
            if case .failure = result { closed = true }
            defer { readyWaiter = nil }
            return (true, readyWaiter)
        }
        guard settled else { return }
        if case .failure = result, process.isRunning { process.terminate() }
        waiter?.resume(with: result)
    }

    private func handleExit(_ process: Process) {
        settleReadiness(.failure(Unavailable.unavailable))
        let request = lock.withLock { () -> Pending? in
            exited = true
            defer { pending = nil }
            return pending
        }
        request?.continuation.resume(throwing: crashError(process))
    }
}
