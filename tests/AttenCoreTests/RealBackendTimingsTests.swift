import AttenCore
import AVFoundation
import XCTest
@testable import Atten

@MainActor
final class RealBackendTimingsTests: XCTestCase {
    func testRealBookNarrationTimingsAndPlayback() async throws {
        guard ProcessInfo.processInfo.environment["ATTEN_REAL_BACKEND_TESTS"] == "1" else {
            throw XCTSkip("Set ATTEN_REAL_BACKEND_TESTS=1 with a locally available Kokoro model")
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AttenRealBackend-\(UUID().uuidString)")
        let directories = AppDirectories(applicationSupport: root)
        try directories.prepare()
        defer { try? FileManager.default.removeItem(at: root) }
        var environment = ProcessInfo.processInfo.environment
        environment["ATTEN_DATA_DIRECTORY"] = root.path
        environment["HF_HUB_OFFLINE"] = "1"
        let generator = ProcessBackendClient(environment: environment)
        let shelf = BookshelfModel(directories: directories, generator: generator)
        defer { shelf.cancelNarration() }
        let book = BookRecord(title: "Timing validation", format: .document, sourcePath: "/unused.txt",
            chapters: [BookChapter(title: "Morning", text: "The morning was quiet. A bird sang outside."),
                       BookChapter(title: "Evening", text: "The sun went down. We turned another page.")],
            voiceID: "af_heart", speed: 1, audioFormat: .wav)
        try await BookLibraryStore(fileURL: directories.booksFile).save([book])
        await shelf.load()
        shelf.narrate(book.id, useMPS: false)
        let deadline = ContinuousClock.now + .seconds(180)
        while shelf.isNarrating && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertFalse(shelf.isNarrating, "Real narration timed out")
        XCTAssertNil(shelf.narrationErrorMessage)
        let narrated = try XCTUnwrap(shelf.book(id: book.id))
        XCTAssertTrue(narrated.hasBookAudio)
        let audio = try XCTUnwrap(narrated.audioURL)
        let timings = try XCTUnwrap(NarrationTimings.load(beside: audio))
        XCTAssertEqual(timings.segments.count, 2)
        for index in narrated.chapters.indices {
            let start = try XCTUnwrap(narrated.chapters[index].startTime)
            XCTAssertEqual(timings.segments[index].start, start, accuracy: 0.0001)
            let words = timings.segments[index].words
            XCTAssertFalse(words.isEmpty)
            var previousEnd = 0.0
            for word in words {
                XCTAssertGreaterThanOrEqual(word.start, previousEnd)
                XCTAssertGreaterThanOrEqual(word.end, word.start)
                XCTAssertLessThanOrEqual(word.end, timings.segments[index].duration)
                previousEnd = word.end
            }
            print("Real chapter \(index): start=\(start), words=\(words.count), monotonic timings verified")
        }
        let folder = directories.narrations.appendingPathComponent(book.id.uuidString)
        let children = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        // Chapter folders, segment WAVs and their sidecars are retired once the
        // book file commits; the book-level timings carry every chapter's words.
        XCTAssertEqual(children.filter { $0.lastPathComponent.hasPrefix("chapter-") }, [])
        let player = try AVAudioPlayer(contentsOf: audio)
        player.volume = 0
        XCTAssertTrue(player.prepareToPlay())
        XCTAssertTrue(player.play())
        XCTAssertTrue(player.isPlaying)
        player.stop()
        print("Real book: book timings.json verified, chapter folders retired; combined CAF playback succeeded")
    }
}
