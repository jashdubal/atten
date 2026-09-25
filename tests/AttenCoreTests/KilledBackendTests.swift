import AttenCore
import Darwin
import Foundation
import XCTest
@testable import Atten

/// The speech engine killed with `kill -9` mid-narration and mid-preview, and
/// an engine that has gone missing: nothing is left "generating", and a
/// narration resumes from its last checkpoint. Only processes these tests
/// start are ever killed — each is checked to be a child of this one first.
@MainActor
final class KilledBackendTests: XCTestCase {
    private var root: URL!
    private var directories: AppDirectories!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("AttenKilled-\(UUID().uuidString)")
        directories = AppDirectories(applicationSupport: root.appendingPathComponent("Application Support"))
        try directories.prepare()
        try StressFixtures.silentWAV(seconds: 0.1).write(to: root.appendingPathComponent("template.wav"))
    }

    override func tearDown() async throws {
        // Anything a test left hanging is one of its own children.
        if let pid = try? childPID() { kill(pid, SIGKILL) }
        try? FileManager.default.removeItem(at: root)
    }

    /// A stand-in `serve` engine. It writes a real WAV for each request, logs
    /// every launch and request, and runs `before` first — which can record
    /// its pid and hang, to be killed.
    private func engine(before: String = "") throws -> PersistentBackendClient {
        let helper = root.appendingPathComponent("backend")
        let script = #"""
        #!/bin/sh
        cd "\#(root.path)"
        field() { printf '%s' "$line" | sed -n "s/.*\"$1\":\"\([^\"]*\)\".*/\1/p"; }
        event() { printf '{"id":"%s","event":%s}\n' "$id" "$1"; }
        hang() { echo $$ > pid; event '"progress","message":"Working"'; while :; do sleep 0.05; done; }
        echo launch >> launches
        [ "$1" = serve ] || exit 2
        \#(before)
        echo '{"event":"ready"}'
        while IFS= read -r line; do
            id=$(field id); filename=$(field filename); output=$(field output)
            case "$line" in *'"op":"generate"'*)
                echo "$filename" >> received
                case "$filename" in *002*|preview*) [ -f allow ] || hang ;; esac
                mkdir -p "$output" && cp template.wav "$output/$filename.wav"
                event "\"completed\",\"path\":\"$output/$filename.wav\",\"segments\":1,\"sample_rate\":24000"
            ;; esac
        done
        """#
        try script.write(to: helper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)
        return PersistentBackendClient(installation: .bundled(helper: helper, modelRoot: root), readyTimeout: 5)
    }

    private func lines(_ name: String) -> [String] {
        ((try? String(contentsOf: root.appendingPathComponent(name), encoding: .utf8)) ?? "")
            .split(separator: "\n").map(String.init)
    }

    /// The pid the stand-in engine recorded, once it is certainly a process
    /// this test started.
    private func childPID() throws -> pid_t? {
        guard let text = try? String(contentsOf: root.appendingPathComponent("pid"), encoding: .utf8),
              let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        let ps = Process()
        let pipe = Pipe()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-o", "ppid=", "-p", String(pid)]
        ps.standardOutput = pipe
        try ps.run()
        ps.waitUntilExit()
        let parent = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return pid_t(parent.trimmingCharacters(in: .whitespacesAndNewlines)) == getpid() ? pid : nil
    }

    private func killEngineWhenItHangs() async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while ContinuousClock.now < deadline {
            if let pid = try childPID() {
                XCTAssertEqual(kill(pid, SIGKILL), 0)
                try FileManager.default.removeItem(at: root.appendingPathComponent("pid"))
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("The engine never reached the point it hangs at")
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(condition(), "Timed out")
    }

    private func book() -> BookRecord {
        BookRecord(title: "Three chapters", format: .document, sourcePath: root.appendingPathComponent("book.txt").path,
                   chapters: ["One.", "Two.", "Three."].enumerated().map { BookChapter(title: "Part \($0.offset + 1)", text: $0.element) },
                   voiceID: "af_heart", speed: 1, audioFormat: .wav)
    }

    // MARK: - Mid-narration

    func testAnEngineKilledMidNarrationFailsCleanlyAndTheNextRunResumesFromTheCheckpoint() async throws {
        let book = book()
        try await BookLibraryStore(fileURL: directories.booksFile).save([book])
        let generator = RetryingBackendClient(wrapping: SharedBackendClient(sharing: try engine()))
        let shelf = BookshelfModel(directories: directories, generator: generator)
        await shelf.load()

        shelf.narrate(book.id, useMPS: false)
        try await killEngineWhenItHangs()
        try await waitUntil { !shelf.isNarrating }

        let failed = try XCTUnwrap(shelf.book(id: book.id))
        XCTAssertEqual(failed.narrationState, .failed)
        XCTAssertEqual(failed.narrationFailure, BackendError.stoppedUnexpectedly.errorDescription)
        XCTAssertEqual(AttenCore.LibraryItem.book(failed).state, .silent, "nothing may be left generating")
        XCTAssertFalse(shelf.synthesis.isBusy)
        XCTAssertEqual(failed.chapters.map(\.isNarrated), [true, false, false])
        // The killed chapter left nothing behind; the finished one is kept.
        let folder = directories.narrations.appendingPathComponent(book.id.uuidString)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path).count, 1)
        try await shelf.flushPersistence()
        let reopened = BookshelfModel(directories: directories, generator: ImmediateGenerator())
        await reopened.load()
        XCTAssertEqual(reopened.book(id: book.id)?.narrationState, .failed)
        XCTAssertEqual(reopened.book(id: book.id)?.narratedCount, 1)

        try Data().write(to: root.appendingPathComponent("allow"))
        shelf.narrate(book.id, useMPS: false)
        try await waitUntil { !shelf.isNarrating }

        let finished = try XCTUnwrap(shelf.book(id: book.id))
        XCTAssertEqual(finished.narrationState, .ready)
        XCTAssertTrue(finished.hasBookAudio)
        XCTAssertEqual(lines("received").map { String($0.prefix(3)) }, ["001", "002", "002", "003"],
                       "the second run starts at the chapter the engine died in")
        XCTAssertEqual(lines("launches").count, 2)
    }

    // MARK: - Mid-preview

    func testAnEngineKilledMidPreviewIsReplacedAndThePreviewStillPlays() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "AttenKilled.\(UUID().uuidString)"))
        let model = AppModel(
            directories: directories,
            settingsStore: SettingsStore(defaults: defaults),
            generator: RetryingBackendClient(wrapping: SharedBackendClient(sharing: try engine(
                before: #"[ "$(wc -l < launches | tr -d " ")" -gt 1 ] && touch allow"#
            )))
        )
        let voice = VoiceCatalog.defaultVoice

        model.previewVoice(voice)
        XCTAssertEqual(model.voicePreviewID, voice.id)
        try await killEngineWhenItHangs()
        try await waitUntil { model.voicePreviewID == nil }
        model.levelMeter.player?.volume = 0
        model.pause()

        XCTAssertFalse(model.synthesis.isBusy)
        XCTAssertTrue(FileManager.default.fileExists(atPath: model.voicePreviewURL(voice).path))
        if case .failed(let message) = model.generationState { XCTFail(message) }
        XCTAssertEqual(lines("launches").count, 2)
    }

    // MARK: - Killed before it is ready

    func testAnEngineKilledWhileStartingIsRestartedNotGivenUpOn() async throws {
        // The first launch dies by signal before it is ready — a crash while
        // the model loads, not an engine too old to serve.
        let client = try engine(before: #"[ "$(wc -l < launches | tr -d " ")" -eq 1 ] && kill -9 $$"#)
        try Data().write(to: root.appendingPathComponent("allow"))
        let request = GenerationRequest(text: "hello", voiceID: "af_heart", speed: 1, format: .wav,
                                        outputDirectory: root, filename: "first")

        do {
            _ = try await client.generate(request)
            XCTFail("The killed launch answered")
        } catch {
            XCTAssertEqual(error as? BackendError, .stoppedUnexpectedly)
        }
        var second = request
        second.filename = "second"
        let output = try await client.generate(second)

        XCTAssertEqual(output.url.lastPathComponent, "second.wav")
        // Served by a fresh resident engine, not one process per request.
        XCTAssertEqual(lines("launches").count, 2)
        XCTAssertEqual(lines("received"), ["second"])
    }

    // MARK: - Missing engine

    func testAMissingOrUnrunnableEngineIsNamedAndLeavesNothingGenerating() async throws {
        let book = book()
        try await BookLibraryStore(fileURL: directories.booksFile).save([book])
        let emptyRoot = root.appendingPathComponent("no-backend", isDirectory: true)
        try FileManager.default.createDirectory(at: emptyRoot, withIntermediateDirectories: true)
        let missing = PersistentBackendClient(installation: .development(root: emptyRoot))
        let shelf = BookshelfModel(directories: directories, generator: RetryingBackendClient(wrapping: SharedBackendClient(sharing: missing)))
        await shelf.load()

        shelf.narrate(book.id, useMPS: false)
        try await waitUntil { !shelf.isNarrating }

        let failed = try XCTUnwrap(shelf.book(id: book.id))
        XCTAssertEqual(failed.narrationState, .failed)
        XCTAssertEqual(failed.narrationFailure, BackendError.backendNotFound.errorDescription)
        XCTAssertFalse(shelf.synthesis.isBusy)

        // A cli.py that cannot be read, and a helper that cannot be run.
        let unreadable = emptyRoot.appendingPathComponent("cli.py")
        try Data("print('hi')".utf8).write(to: unreadable)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: unreadable.path)
        let request = GenerationRequest(text: "hello", voiceID: "af_heart", speed: 1, format: .wav,
                                        outputDirectory: root, filename: "hello")
        for client in [PersistentBackendClient(installation: .development(root: emptyRoot)) as any TTSGenerating,
                       ProcessBackendClient(installation: .development(root: emptyRoot))] {
            do {
                _ = try await client.generate(request)
                XCTFail("An unreadable cli.py ran")
            } catch {
                XCTAssertEqual(error as? BackendError, .backendNotFound)
            }
        }

        let helper = try engine()
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: root.appendingPathComponent("backend").path)
        do {
            _ = try await helper.generate(request)
            XCTFail("A helper that is not executable ran")
        } catch {
            XCTAssertEqual(error as? BackendError, .backendNotFound)
        }
        // Put back, the same client serves again: nothing was given up on.
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.appendingPathComponent("backend").path)
        let output = try await helper.generate(request)
        XCTAssertEqual(output.url.lastPathComponent, "hello.wav")
        try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: unreadable.path)
    }
}
