import Foundation

public struct ModelDownloadProgress: Equatable, Sendable {
    public var percent: Int
    /// Whether the backend supplied a real percentage for this update. A
    /// zero percent value can be a legitimate start, so the value itself is
    /// not enough to decide whether progress is determinate.
    public var hasPercentage: Bool
    public var status: String
    public var speed: String
    public var eta: String
    public var sizeText: String

    public init(
        percent: Int = 0,
        status: String = "",
        speed: String = "",
        eta: String = "",
        sizeText: String = "",
        hasPercentage: Bool? = nil
    ) {
        self.percent = percent
        self.hasPercentage = hasPercentage ?? (percent > 0)
        self.status = status
        self.speed = speed
        self.eta = eta
        self.sizeText = sizeText
    }

    /// A value suitable for a determinate progress view, or nil when the
    /// backend did not report a usable percentage.
    public var fraction: Double? {
        guard hasPercentage, (0...100).contains(percent) else { return nil }
        return Double(percent) / 100
    }
}

public protocol ModelDownloading: Sendable {
    /// Downloads a Hugging Face repository, reporting progress as the backend
    /// streams it. Throws `BackendError.cancelled` when `stop` interrupts it.
    func download(
        _ modelID: String,
        progress: @escaping @Sendable (ModelDownloadProgress) -> Void
    ) async throws
    func stop(_ modelID: String)
}

/// Runs `cli.py --download-model` and streams its JSON progress events. The
/// backend writes `.part` files and resumes them with HTTP ranges, so stopping
/// the process is all that is needed to pause.
public final class ProcessModelDownloader: ModelDownloading, @unchecked Sendable {
    private let installation: BackendInstallation?
    private let environment: [String: String]
    private let lock = NSLock()
    private var processes: [String: Process] = [:]
    private var stopped: Set<String> = []

    public init(
        installation: BackendInstallation? = BackendLocator.locateInstallation(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.installation = installation
        self.environment = environment
    }

    public func download(
        _ modelID: String,
        progress: @escaping @Sendable (ModelDownloadProgress) -> Void
    ) async throws {
        guard let installation else { throw BackendError.backendNotFound }

        let child = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let command = BackendRuntime.command(for: installation, environment: environment)
        child.executableURL = command.executable
        child.currentDirectoryURL = installation.workingDirectory
        child.standardOutput = outputPipe
        child.standardError = errorPipe
        child.environment = BackendRuntime.environment(for: installation, inheriting: environment)
        child.arguments = command.arguments + installation.entrypointArguments
            + ["--download-model", modelID, "--json"]

        lock.withLock {
            stopped.remove(modelID)
            processes[modelID] = child
        }
        defer { lock.withLock { if processes[modelID] === child { processes[modelID] = nil } } }

        // Drain stderr while stdout streams so a chatty backend cannot fill the
        // pipe buffer and stall the download.
        let errorOutput = ErrorBuffer()
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            errorOutput.append(handle.availableData)
        }
        defer { errorPipe.fileHandleForReading.readabilityHandler = nil }

        try await withTaskCancellationHandler {
            try child.run()
            if isStopped(modelID) { child.terminate() }

            var lastError: String?
            for try await line in outputPipe.fileHandleForReading.bytes.lines {
                guard let event = try? JSONDecoder().decode(Event.self, from: Data(line.utf8)) else {
                    continue
                }
                switch event.event {
                case "download_progress":
                    progress(ModelDownloadProgress(
                        percent: event.percent ?? 0,
                        status: event.status ?? "",
                        speed: event.speed ?? "",
                        eta: event.eta ?? "",
                        sizeText: event.sizeText ?? "",
                        hasPercentage: event.percent != nil
                    ))
                case "error":
                    lastError = event.message
                default:
                    break
                }
            }
            child.waitUntilExit()

            if isStopped(modelID) || Task.isCancelled { throw BackendError.cancelled }
            guard child.terminationStatus == 0 else {
                let standardError = errorOutput.text
                throw BackendError.processFailed(
                    lastError ?? (standardError.isEmpty ? "Model download failed." : standardError)
                )
            }
        } onCancel: {
            self.stop(modelID)
        }
    }

    public func stop(_ modelID: String) {
        lock.withLock {
            stopped.insert(modelID)
            guard let process = processes[modelID], process.isRunning else { return }
            process.terminate()
        }
    }

    private func isStopped(_ modelID: String) -> Bool {
        lock.withLock { stopped.contains(modelID) }
    }

    private final class ErrorBuffer: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()

        func append(_ chunk: Data) { lock.withLock { data.append(chunk) } }

        var text: String {
            lock.withLock {
                String(decoding: data.suffix(4_096), as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }

    private struct Event: Decodable {
        let event: String
        let message: String?
        let percent: Int?
        let status: String?
        let speed: String?
        let eta: String?
        let sizeText: String?

        enum CodingKeys: String, CodingKey {
            case event, message, percent, status, speed, eta
            case sizeText = "size_text"
        }
    }
}
