import AttenCore
import Foundation
import XCTest

/// Confirms, against the real Kokoro engine rather than the fake serve
/// script, that Studio and the bookshelf sharing one `PersistentBackendClient`
/// really do keep a single `serve` process resident while both generate.
final class SharedBackendClientRealEngineTests: XCTestCase {
    func testInterleavedOwnersKeepOneResidentProcess() async throws {
        guard ProcessInfo.processInfo.environment["ATTEN_REAL_BACKEND_TESTS"] == "1" else {
            throw XCTSkip("Set ATTEN_REAL_BACKEND_TESTS=1 with a locally available Kokoro model")
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AttenSharedBackend-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var environment = ProcessInfo.processInfo.environment
        environment["HF_HUB_OFFLINE"] = "1"

        let engine = PersistentBackendClient(environment: environment)
        let studio = SharedBackendClient(sharing: engine)
        let bookshelf = SharedBackendClient(sharing: engine)

        func request(_ name: String) -> GenerationRequest {
            GenerationRequest(
                text: "Testing \(name).", voiceID: "af_heart", speed: 1, format: .wav,
                outputDirectory: root, filename: name, useMPS: false
            )
        }

        // Two rounds of interleaved use, so a process spawned for the first
        // owner is still the one answering the second.
        let firstStudioRequest = request("studio-1")
        let firstBookshelfRequest = request("bookshelf-1")
        async let first = studio.generate(firstStudioRequest)
        async let second = bookshelf.generate(firstBookshelfRequest)
        _ = try await (first, second)

        let secondStudioRequest = request("studio-2")
        let secondBookshelfRequest = request("bookshelf-2")
        async let third = studio.generate(secondStudioRequest)
        async let fourth = bookshelf.generate(secondBookshelfRequest)
        _ = try await (third, fourth)

        let resident = try Self.residentServeProcessCount(parentPID: ProcessInfo.processInfo.processIdentifier)
        XCTAssertEqual(resident, 1, "Studio and the bookshelf must share one resident engine process")

        engine.shutdown()
    }

    /// Counts this test process's own `cli.py serve` children, so a stray
    /// `serve` process left over from another session never taints the count.
    private static func residentServeProcessCount(parentPID: Int32) throws -> Int {
        let ps = Process()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-eo", "pid=,ppid=,command="]
        let pipe = Pipe()
        ps.standardOutput = pipe
        try ps.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        ps.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self)
        return output.split(separator: "\n").filter { line in
            let fields = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard fields.count == 3, let ppid = Int32(fields[1]) else { return false }
            return ppid == parentPID && fields[2].contains("cli.py") && fields[2].contains("serve")
        }.count
    }
}
