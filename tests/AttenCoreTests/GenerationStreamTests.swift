import AttenCore
import Foundation
import XCTest

final class GenerationStreamTests: XCTestCase {
    private func fixture(_ script: String) throws -> (URL, ProcessBackendClient, GenerationRequest) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let helper = directory.appendingPathComponent("backend")
        try ("#!/bin/sh\n" + script).write(to: helper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)
        let client = ProcessBackendClient(installation: .bundled(helper: helper, modelRoot: directory))
        let request = GenerationRequest(text: "hello", voiceID: "af_heart", speed: 1, format: .wav,
                                       outputDirectory: directory, filename: "output")
        return (directory, client, request)
    }

    func testSegmentsArriveBeforeExitAndSplitLinesAreReassembled() async throws {
        let (directory, client, request) = try fixture("""
        printf 'diagnostic chatter\\n{"event":"progress","message":"Starting"}\\n'
        printf '{"event":"segment","index":0,"path":"/tmp/seg.wav","text":"héllo",'
        sleep 0.05
        printf '"start":0,"duration":1,"words":[{"text":"héllo","start":0.1,"end":0.9}]}\\n'
        for attempt in 1 2 3 4 5 6 7 8 9 10; do
            if test -f received; then
                printf '{"event":"completed","path":"/tmp/done.wav","segments":1,"sample_rate":24000}'
                exit 0
            fi
            sleep 0.1
        done
        printf '{"event":"error","message":"Consumer did not see live segment"}\\n'
        exit 1
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        var events: [GenerationEvent] = []
        for try await event in client.generateStream(request) {
            events.append(event)
            if case let .segment(segment) = event {
                XCTAssertEqual(segment.timing.words.first?.text, "héllo")
                try Data().write(to: directory.appendingPathComponent("received"))
            }
        }
        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(events.first, .progress("Starting"))
        XCTAssertEqual(events.last, .completed(URL(fileURLWithPath: "/tmp/done.wav")))
    }

    func testStreamFailureAndMalformedCompletion() async throws {
        for script in ["echo '{\"event\":\"error\",\"message\":\"model failed\"}'; exit 1", "echo noise"] {
            let (directory, client, request) = try fixture(script)
            defer { try? FileManager.default.removeItem(at: directory) }
            var failure: String?
            do {
                for try await event in client.generateStream(request) {
                    if case let .failed(message) = event { failure = message }
                    if case .completed = event { XCTFail("Failed process completed") }
                }
                XCTFail("Expected a thrown error")
            } catch { XCTAssertEqual(failure, error.localizedDescription) }
        }
    }

    func testCancellingStreamTerminatesProcess() async throws {
        let (directory, client, request) = try fixture("""
        trap 'echo stopped > stopped; exit 0' TERM
        echo '{"event":"progress","message":"Running"}'
        while true; do sleep 0.05; done
        """)
        defer { client.cancel(); try? FileManager.default.removeItem(at: directory) }
        let ready = expectation(description: "process started")
        let task = Task {
            for try await event in client.generateStream(request) {
                if case .progress = event { ready.fulfill() }
            }
        }
        await fulfillment(of: [ready], timeout: 3)
        task.cancel()
        _ = await task.result
        let stopped = directory.appendingPathComponent("stopped")
        for _ in 0..<100 {
            if FileManager.default.fileExists(atPath: stopped.path) { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: stopped.path))
    }

    func testNonStreamingRetainsCompletedMetadata() async throws {
        let (directory, client, request) = try fixture("""
        echo '{"event":"segment","count":3}'
        echo '{"event":"completed","path":"/tmp/old.mp3","segments":3,"sample_rate":44100}'
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = try await client.generate(request)
        XCTAssertEqual(output, GenerationOutput(url: URL(fileURLWithPath: "/tmp/old.mp3"), segmentCount: 3, sampleRate: 44100))
    }
}
