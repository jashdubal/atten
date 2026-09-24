import AttenCore
import Foundation
import XCTest

final class PersistentBackendClientTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    /// A fake backend whose `serve` answers each generate with `generate`, a
    /// shell body that sees the request's `$id` and `$filename`. It logs every
    /// launch to `launches`, every request it reads to `received`, and its exit
    /// to `exits`.
    private func makeClient(
        generate: String,
        serve: String? = nil,
        idleTimeout: TimeInterval = 600,
        cancelTimeout: TimeInterval = 2
    ) throws -> PersistentBackendClient {
        let helper = directory.appendingPathComponent("backend")
        let script = #"""
        #!/bin/sh
        field() { printf '%s' "$line" | sed -n "s/.*\"$1\":\"\([^\"]*\)\".*/\1/p"; }
        event() { printf '{"id":"%s","event":%s}\n' "$id" "$1"; }
        progress() { event '"progress","message":"Working"'; }
        segment() { event '"segment","index":0,"path":"/tmp/seg.wav","text":"hi","start":0,"duration":1,"words":[]'; }
        complete() { event "\"completed\",\"path\":\"\#(directory.path)/$filename.wav\",\"segments\":1,\"sample_rate\":24000"; }
        launches() { wc -l < launches | tr -d ' '; }
        if [ "$1" != serve ]; then
            printf '{"event":"completed","path":"%s/one-shot.wav","segments":2,"sample_rate":24000}\n' "\#(directory.path)"
            exit 0
        fi
        echo launch >> launches
        \#(serve ?? "")
        echo '{"event":"ready"}'
        answer() {
        \#(generate)
        }
        while IFS= read -r line; do
            id=$(field id)
            filename=$(field filename)
            case "$line" in
                *'"op":"generate"'*) echo "$filename" >> received; answer ;;
            esac
        done
        echo exit >> exits
        """#
        try script.write(to: helper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)
        return PersistentBackendClient(
            installation: .bundled(helper: helper, modelRoot: directory),
            idleTimeout: idleTimeout,
            cancelTimeout: cancelTimeout
        )
    }

    private func request(_ filename: String) -> GenerationRequest {
        GenerationRequest(text: "hello", voiceID: "af_heart", speed: 1, format: .wav,
                          outputDirectory: directory, filename: filename)
    }

    private func output(_ filename: String) -> URL {
        directory.appendingPathComponent("\(filename).wav")
    }

    private func lines(_ name: String) -> [String] {
        let text = (try? String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)) ?? ""
        return text.split(separator: "\n").map(String.init)
    }

    private func waitUntil(_ condition: () -> Bool, timeout: Duration = .seconds(5)) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            guard ContinuousClock.now < deadline else { return XCTFail("Timed out waiting") }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    private func assertThrows(
        _ expected: BackendError,
        _ body: () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await body()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? BackendError, expected, file: file, line: line)
        }
    }

    func testRequestsShareOneProcessAndOnlyHearTheirOwnEvents() async throws {
        let client = try makeClient(generate: #"""
        printf '{"id":"someone-else","event":"completed","path":"/wrong.wav"}\n'
        segment
        complete
        """#)

        let first = try await client.generate(request("first"))
        var events: [GenerationEvent] = []
        for try await event in client.generateStream(request("second")) { events.append(event) }

        XCTAssertEqual(first, GenerationOutput(url: output("first"), segmentCount: 1, sampleRate: 24_000))
        XCTAssertEqual(events.count, 2)
        if case let .segment(segment) = events.first {
            XCTAssertEqual(segment.timing.text, "hi")
        } else {
            XCTFail("Expected a segment first, got \(events)")
        }
        XCTAssertEqual(events.last, .completed(output("second")))
        XCTAssertEqual(lines("launches").count, 1)

        client.shutdown()
        try await waitUntil { lines("exits").count == 1 }
    }

    func testRequestsRunOneAtATimeAndACancelledWaitingRequestNeverReachesTheEngine() async throws {
        let client = try makeClient(generate: #"""
        while [ ! -f "release-$filename" ]; do sleep 0.02; done
        complete
        """#)
        let a = request("a")
        let first = Task { try await client.generate(a) }
        try await waitUntil { lines("received") == ["a"] }
        let b = request("b")
        let second = Task { try await client.generate(b) }
        try await Task.sleep(for: .milliseconds(100))
        let c = request("c")
        let third = Task { try await client.generate(c) }
        try await Task.sleep(for: .milliseconds(100))
        third.cancel()
        await assertThrows(.cancelled) { _ = try await third.value }

        try Data().write(to: directory.appendingPathComponent("release-a"))
        let firstURL = try await first.value.url
        XCTAssertEqual(firstURL, output("a"))
        try await waitUntil { lines("received") == ["a", "b"] }
        try Data().write(to: directory.appendingPathComponent("release-b"))
        let secondURL = try await second.value.url
        XCTAssertEqual(secondURL, output("b"))
        XCTAssertEqual(lines("received"), ["a", "b"])
        XCTAssertEqual(lines("launches").count, 1)
    }

    func testCancelStopsTheRunningRequestAndKeepsTheProcess() async throws {
        let client = try makeClient(generate: #"""
        [ "$filename" = after ] && { complete; return; }
        progress
        IFS= read -r line
        case "$line" in *'"op":"cancel"'*) event '"cancelled"' ;; esac
        """#)
        var failure: String?
        await assertThrows(.cancelled) {
            for try await event in client.generateStream(request("long")) {
                if case .progress = event { client.cancel() }
                if case let .failed(message) = event { failure = message }
            }
        }
        XCTAssertEqual(failure, BackendError.cancelled.localizedDescription)

        let after = try await client.generate(request("after"))
        XCTAssertEqual(after.url, output("after"))
        XCTAssertEqual(lines("launches").count, 1)
    }

    func testAnEngineThatIgnoresCancelIsReplaced() async throws {
        let client = try makeClient(generate: #"""
        [ "$(launches)" -gt 1 ] && { complete; return; }
        progress
        while :; do sleep 0.05; done
        """#, cancelTimeout: 0.3)
        let started = ContinuousClock.now
        await assertThrows(.cancelled) {
            for try await event in client.generateStream(request("stuck")) {
                if case .progress = event { client.cancel() }
            }
        }
        XCTAssertLessThan(ContinuousClock.now - started, .seconds(3))

        let after = try await client.generate(request("after"))
        XCTAssertEqual(after.url, output("after"))
        XCTAssertEqual(lines("launches").count, 2)
    }

    func testACrashFailsTheRequestAndTheNextOneStartsAFreshProcess() async throws {
        let client = try makeClient(generate: #"""
        [ "$(launches)" -gt 1 ] && { complete; return; }
        progress
        kill -9 $$
        """#)
        await assertThrows(.stoppedUnexpectedly) { _ = try await client.generate(request("doomed")) }

        let after = try await client.generate(request("after"))
        XCTAssertEqual(after.url, output("after"))
        XCTAssertEqual(lines("launches").count, 2)
    }

    func testAnErrorEventFailsOnlyThatRequest() async throws {
        let client = try makeClient(generate: #"""
        [ "$filename" = bad ] && { event '"error","message":"Voice is missing"'; return; }
        complete
        """#)
        await assertThrows(.processFailed("Voice is missing")) { _ = try await client.generate(request("bad")) }
        let good = try await client.generate(request("good"))
        XCTAssertEqual(good.url, output("good"))
        XCTAssertEqual(lines("launches").count, 1)
    }

    func testAnIdleProcessShutsDownAndTheNextRequestRestartsIt() async throws {
        let client = try makeClient(generate: "complete", idleTimeout: 0.3)
        _ = try await client.generate(request("first"))
        try await waitUntil { lines("exits").count == 1 }

        let second = try await client.generate(request("second"))
        XCTAssertEqual(second.url, output("second"))
        XCTAssertEqual(lines("launches").count, 2)
    }

    // MARK: - Sharing one engine across two owners

    func testTwoSharedClientsUseOneProcess() async throws {
        let engine = try makeClient(generate: "complete")
        let studio = SharedBackendClient(sharing: engine)
        let bookshelf = SharedBackendClient(sharing: engine)

        let first = try await studio.generate(request("first"))
        let second = try await bookshelf.generate(request("second"))

        XCTAssertEqual(first.url, output("first"))
        XCTAssertEqual(second.url, output("second"))
        XCTAssertEqual(lines("launches").count, 1)
    }

    func testCancellingASharedClientsQueuedRequestLeavesTheOtherClientsRequestRunning() async throws {
        let engine = try makeClient(generate: #"""
        while [ ! -f "release-$filename" ]; do sleep 0.02; done
        complete
        """#)
        let studio = SharedBackendClient(sharing: engine)
        let bookshelf = SharedBackendClient(sharing: engine)

        let runningRequest = request("running")
        let running = Task { try await studio.generate(runningRequest) }
        try await waitUntil { lines("received") == ["running"] }
        let queuedRequest = request("queued")
        let queued = Task { try await bookshelf.generate(queuedRequest) }
        try await Task.sleep(for: .milliseconds(100))

        bookshelf.cancel()
        await assertThrows(.cancelled) { _ = try await queued.value }
        XCTAssertEqual(lines("received"), ["running"], "a request cancelled while still queued never reaches the engine")

        try Data().write(to: directory.appendingPathComponent("release-running"))
        let runningURL = try await running.value.url
        XCTAssertEqual(runningURL, output("running"))
        XCTAssertEqual(lines("launches").count, 1)
    }

    func testCancellingASharedClientsRunningRequestLetsTheOtherClientsQueuedRequestRunNext() async throws {
        let engine = try makeClient(generate: #"""
        [ "$filename" = current ] || { complete; return; }
        progress
        IFS= read -r line
        case "$line" in *'"op":"cancel"'*) event '"cancelled"' ;; esac
        """#)
        let studio = SharedBackendClient(sharing: engine)
        let bookshelf = SharedBackendClient(sharing: engine)

        let currentRequest = request("current")
        let current = Task { try await studio.generate(currentRequest) }
        try await waitUntil { lines("received") == ["current"] }
        let queuedRequest = request("queued")
        let queued = Task { try await bookshelf.generate(queuedRequest) }
        try await Task.sleep(for: .milliseconds(100))

        studio.cancel()
        await assertThrows(.cancelled) { _ = try await current.value }

        let queuedURL = try await queued.value.url
        XCTAssertEqual(queuedURL, output("queued"))
        XCTAssertEqual(lines("launches").count, 1)
    }

    func testABackendThatCannotServeFallsBackToOneProcessPerRequest() async throws {
        // An older backend reads `serve` as text to speak and starts talking.
        let client = try makeClient(generate: "complete", serve: #"""
        echo 'Generating audio...'
        while :; do sleep 0.05; done
        """#)
        let started = ContinuousClock.now
        let first = try await client.generate(request("first"))
        var events: [GenerationEvent] = []
        for try await event in client.generateStream(request("second")) { events.append(event) }

        let oneShot = directory.appendingPathComponent("one-shot.wav")
        XCTAssertEqual(first, GenerationOutput(url: oneShot, segmentCount: 2, sampleRate: 24_000))
        XCTAssertEqual(events, [.completed(oneShot)])
        XCTAssertLessThan(ContinuousClock.now - started, .seconds(10))
        XCTAssertEqual(lines("launches").count, 1, "serve is tried once, then left alone")
    }
}
