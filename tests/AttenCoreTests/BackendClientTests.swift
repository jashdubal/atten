import Foundation
import XCTest
@testable import AttenCore

private actor AttemptState {
    var attempts = 0
    func next() -> Int { attempts += 1; return attempts }
    func count() -> Int { attempts }
}

private struct FlakyGenerator: TTSGenerating {
    let state: AttemptState

    func generate(_ request: GenerationRequest) async throws -> GenerationOutput {
        if await state.next() == 1 {
            throw BackendError.processFailed("temporary failure")
        }
        return GenerationOutput(
            url: request.outputDirectory.appendingPathComponent("done.mp3"),
            segmentCount: 1,
            sampleRate: 24_000
        )
    }

    func cancel() {}
}

private final class CancellableGenerator: TTSGenerating, @unchecked Sendable {
    private let lock = NSLock()
    private var cancellationState = false
    var wasCancelled: Bool { lock.withLock { cancellationState } }

    func generate(_ request: GenerationRequest) async throws -> GenerationOutput {
        try await Task.sleep(for: .seconds(30))
        return GenerationOutput(url: request.outputDirectory, segmentCount: 0, sampleRate: 0)
    }

    func cancel() { lock.withLock { cancellationState = true } }
}

final class BackendClientTests: XCTestCase {
    private var request: GenerationRequest {
        GenerationRequest(
            text: "Hello", voiceID: "af_heart", speed: 1, format: .mp3,
            outputDirectory: URL(fileURLWithPath: "/tmp"), filename: "hello"
        )
    }

    func testRetrySucceedsAfterTransientFailure() async throws {
        let state = AttemptState()
        let client = RetryingBackendClient(
            wrapping: FlakyGenerator(state: state),
            maximumAttempts: 2
        )

        let output = try await client.generate(request)
        let attempts = await state.count()

        XCTAssertEqual(output.url.lastPathComponent, "done.mp3")
        XCTAssertEqual(attempts, 2)
    }

    func testCancellationIsForwardedAndNotRetried() async {
        let generator = CancellableGenerator()
        let client = RetryingBackendClient(wrapping: generator, maximumAttempts: 3)
        let generationRequest = request
        let task = Task { try await client.generate(generationRequest) }
        task.cancel()
        client.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertTrue(generator.wasCancelled)
        }
    }

    func testBackendLocatorHonorsCompatibleEnvironmentOverride() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data().write(to: directory.appendingPathComponent("cli.py"))

        let result = BackendLocator.locate(
            environment: ["ATTEN_BACKEND_ROOT": directory.path],
            currentDirectory: URL(fileURLWithPath: "/")
        )

        XCTAssertEqual(result?.resolvingSymlinksInPath(), directory.resolvingSymlinksInPath())
    }

    func testBackendRuntimePrefersRepositoryVirtualEnvironment() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let python = directory.appendingPathComponent(".venv/bin/python3")
        try FileManager.default.createDirectory(
            at: python.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("#!/bin/sh\n".utf8).write(to: python)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: python.path
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let command = BackendRuntime.command(
            backendRoot: directory,
            environment: ["PATH": "", "HOME": directory.path]
        )

        XCTAssertEqual(command, BackendCommand(executable: python, arguments: []))
    }

    func testBundledBackendTakesPrecedenceAndRunsDirectly() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let helper = directory.appendingPathComponent(
            "Atten.app/Contents/Helpers/atten-backend/atten-backend"
        )
        let modelRoot = directory.appendingPathComponent(
            "Atten.app/Contents/Resources/Models/Kokoro-82M",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: helper.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: modelRoot.appendingPathComponent("voices"),
            withIntermediateDirectories: true
        )
        try Data("#!/bin/sh\n".utf8).write(to: helper)
        try Data().write(to: modelRoot.appendingPathComponent("config.json"))
        try Data().write(to: modelRoot.appendingPathComponent("kokoro-v1_0.pth"))
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: helper.path
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let installation = BackendLocator.locateInstallation(
            environment: ["ATTEN_BACKEND_ROOT": "/not/used"],
            currentDirectory: URL(fileURLWithPath: "/"),
            bundleURL: directory.appendingPathComponent("Atten.app")
        )

        XCTAssertEqual(installation, .bundled(helper: helper, modelRoot: modelRoot))
        XCTAssertEqual(
            installation.map { BackendRuntime.command(for: $0, environment: [:]) },
            BackendCommand(executable: helper, arguments: [])
        )
    }

    func testBundledBackendEnvironmentIsOfflineAndSelfContained() {
        let installation = BackendInstallation.bundled(
            helper: URL(fileURLWithPath: "/Atten.app/Contents/Helpers/atten-backend/atten-backend"),
            modelRoot: URL(fileURLWithPath: "/Atten.app/Contents/Resources/Models/Kokoro-82M")
        )

        let environment = BackendRuntime.environment(
            for: installation,
            inheriting: ["PATH": "/user/bin", "HOME": "/Users/example"]
        )

        XCTAssertEqual(environment["ATTEN_MODEL_ROOT"], "/Atten.app/Contents/Resources/Models/Kokoro-82M")
        XCTAssertEqual(environment["HF_HUB_OFFLINE"], "1")
        XCTAssertEqual(environment["PYTHONNOUSERSITE"], "1")
        XCTAssertEqual(environment["PYTHONDONTWRITEBYTECODE"], "1")
        XCTAssertEqual(environment["PATH"], "/usr/bin:/bin:/usr/sbin:/sbin")
        XCTAssertEqual(environment["HOME"], "/Users/example")
    }
}
