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
}
