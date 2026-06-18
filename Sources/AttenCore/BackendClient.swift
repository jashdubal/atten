import Foundation

public enum BackendError: LocalizedError, Equatable, Sendable {
    case backendNotFound
    case invalidRequest(String)
    case processFailed(String)
    case malformedResponse
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .backendNotFound:
            "Atten could not find cli.py. Set ATTEN_BACKEND_ROOT to the repository path."
        case let .invalidRequest(message), let .processFailed(message):
            message
        case .malformedResponse:
            "The local speech backend returned an unreadable response."
        case .cancelled:
            "Speech generation was cancelled."
        }
    }
}

public protocol TTSGenerating: Sendable {
    func generate(_ request: GenerationRequest) async throws -> GenerationOutput
    func cancel()
}

public final class ProcessBackendClient: TTSGenerating, @unchecked Sendable {
    private let backendRoot: URL?
    private let environment: [String: String]
    private let lock = NSLock()
    private var process: Process?
    private var cancellationRequested = false

    public init(
        backendRoot: URL? = BackendLocator.locate(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.backendRoot = backendRoot
        self.environment = environment
    }

    public func generate(_ request: GenerationRequest) async throws -> GenerationOutput {
        guard !request.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BackendError.invalidRequest("Enter some text before generating speech.")
        }
        guard let backendRoot else { throw BackendError.backendNotFound }

        let inputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("atten-input-\(UUID().uuidString).txt")
        try request.text.write(to: inputURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: inputURL) }

        let child = Process()
        let outputPipe = Pipe()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        child.currentDirectoryURL = backendRoot
        child.standardOutput = outputPipe
        child.standardError = outputPipe
        child.environment = environment.merging(["PYTHONUNBUFFERED": "1"]) { _, new in new }

        let hasUV = FileManager.default.fileExists(atPath: backendRoot.appendingPathComponent("uv.lock").path)
        var arguments = hasUV ? ["uv", "run", "cli.py"] : ["python3", "cli.py"]
        arguments += [
            "--source", inputURL.path,
            "--voice", request.voiceID,
            "--speed", String(request.speed),
            "--format", request.format.rawValue,
            "--output", request.outputDirectory.path,
            "--filename", request.filename,
            "--json",
        ]
        if request.useMPS { arguments.append("--mps") }
        child.arguments = arguments

        setProcess(child)
        defer { clearProcess(child) }

        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            let outputData: Data
            do {
                outputData = try await ProcessExecution(
                    process: child,
                    output: outputPipe.fileHandleForReading,
                    cancellationRequested: { self.isCancellationRequested }
                ).run()
            } catch {
                throw BackendError.processFailed(error.localizedDescription)
            }

            if Task.isCancelled || isCancellationRequested || child.terminationReason == .uncaughtSignal {
                throw BackendError.cancelled
            }
            guard child.terminationStatus == 0 else {
                let processOutput = String(decoding: outputData, as: UTF8.self)
                let events = Self.events(from: outputData)
                let eventError = events.last { $0.event == "error" }?.message
                throw BackendError.processFailed(
                    eventError ?? processOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }

            guard let completed = Self.events(from: outputData).last(where: { $0.event == "completed" }),
                  let path = completed.path else {
                throw BackendError.malformedResponse
            }
            return GenerationOutput(
                url: URL(fileURLWithPath: path),
                segmentCount: completed.segments ?? 0,
                sampleRate: completed.sampleRate ?? 24_000
            )
        } onCancel: {
            self.cancel()
        }
    }

    public func cancel() {
        lock.withLock {
            cancellationRequested = true
            guard let process, process.isRunning else { return }
            process.terminate()
        }
    }

    private func setProcess(_ newValue: Process) {
        lock.withLock {
            cancellationRequested = false
            process = newValue
        }
    }

    private func clearProcess(_ expected: Process) {
        lock.withLock {
            if process === expected { process = nil }
        }
    }

    private var isCancellationRequested: Bool {
        lock.withLock { cancellationRequested }
    }

    private struct Event: Decodable {
        let event: String
        let message: String?
        let path: String?
        let segments: Int?
        let sampleRate: Int?

        enum CodingKeys: String, CodingKey {
            case event, message, path, segments
            case sampleRate = "sample_rate"
        }
    }

    private static func events(from data: Data) -> [Event] {
        String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
            .compactMap { try? JSONDecoder().decode(Event.self, from: Data($0.utf8)) }
    }
}

private final class ProcessExecution: @unchecked Sendable {
    private let process: Process
    private let output: FileHandle
    private let cancellationRequested: @Sendable () -> Bool

    init(
        process: Process,
        output: FileHandle,
        cancellationRequested: @escaping @Sendable () -> Bool
    ) {
        self.process = process
        self.output = output
        self.cancellationRequested = cancellationRequested
    }

    func run() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                do {
                    try process.run()
                    if cancellationRequested() { process.terminate() }
                    let data = try output.readToEnd() ?? Data()
                    process.waitUntilExit()
                    continuation.resume(returning: data)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

public struct RetryingBackendClient: TTSGenerating {
    private let wrapped: any TTSGenerating
    private let maximumAttempts: Int

    public init(wrapping wrapped: any TTSGenerating, maximumAttempts: Int = 2) {
        self.wrapped = wrapped
        self.maximumAttempts = max(1, maximumAttempts)
    }

    public func generate(_ request: GenerationRequest) async throws -> GenerationOutput {
        var lastError: Error?
        for attempt in 1...maximumAttempts {
            do {
                return try await wrapped.generate(request)
            } catch is CancellationError {
                throw BackendError.cancelled
            } catch BackendError.cancelled {
                throw BackendError.cancelled
            } catch {
                lastError = error
                if attempt < maximumAttempts {
                    try await Task.sleep(for: .milliseconds(250))
                }
            }
        }
        throw lastError ?? BackendError.processFailed("Speech generation failed.")
    }

    public func cancel() { wrapped.cancel() }
}

public enum BackendLocator {
    public static func locate(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        currentDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    ) -> URL? {
        if let override = environment["ATTEN_BACKEND_ROOT"] {
            let url = URL(fileURLWithPath: override)
            if containsBackend(url) { return url }
        }
        if containsBackend(currentDirectory) { return currentDirectory }

        var candidate = Bundle.main.executableURL?.deletingLastPathComponent()
        for _ in 0..<8 {
            guard let url = candidate else { break }
            if containsBackend(url) { return url }
            candidate = url.deletingLastPathComponent()
        }

        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return containsBackend(sourceRoot) ? sourceRoot : nil
    }

    private static func containsBackend(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.appendingPathComponent("cli.py").path)
    }
}
