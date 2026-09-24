import Foundation

/// Transcodes local audio to MP3 by shelling out to the backend's own
/// `transcode` command — the one format AVFoundation on macOS cannot encode
/// to, and the one place the Library's export sheet still needs Atten's
/// speech engine rather than a system framework.
public enum TranscodeService {
    public static func mp3(
        from source: URL,
        to destination: URL,
        installation: BackendInstallation? = BackendLocator.locateInstallation(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) async throws {
        guard let installation else { throw BackendError.backendNotFound }

        let command = BackendRuntime.command(for: installation, environment: environment)
        let child = Process()
        child.executableURL = command.executable
        child.currentDirectoryURL = installation.workingDirectory
        child.environment = BackendRuntime.environment(for: installation, inheriting: environment)
        child.arguments = command.arguments + installation.entrypointArguments + [
            "transcode", "--input", source.path, "--output", destination.path, "--json",
        ]
        let pipe = Pipe()
        child.standardOutput = pipe
        child.standardError = pipe

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try child.run()
                    let output = pipe.fileHandleForReading.readDataToEndOfFile()
                    child.waitUntilExit()
                    guard child.terminationStatus == 0 else {
                        let message = String(data: output, encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        continuation.resume(throwing: BackendError.processFailed(
                            message?.isEmpty == false ? message! : "Transcoding to MP3 failed."
                        ))
                        return
                    }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: BackendError.processFailed(error.localizedDescription))
                }
            }
        }
    }
}
