import AttenCore
import Foundation
import XCTest
@testable import Atten

/// `ProgressivePlayer` schedules real (if silent) segment WAVs onto an
/// `AVAudioEngine` as they land — these cover the state machine that lets
/// Create's inspector and the mini player listen while a narration is still
/// being generated (P5).
@MainActor
final class ProgressivePlayerTests: XCTestCase {
    func testPlayIsPossibleAssoonAsTheFirstSegmentArrives() async throws {
        let player = ProgressivePlayer()
        let bookID = UUID()
        let generator = ImmediateGenerator()
        let directory = try makeDirectory()

        XCTAssertFalse(player.isPlaying)

        let segment = try await makeSegment(generator, in: directory, text: "First sentence.", start: 0, duration: 0.1)
        player.receive(bookID: bookID, chapterIndex: 0, segment: segment)

        XCTAssertEqual(player.bookID, bookID)
        XCTAssertEqual(player.duration, 0.1, accuracy: 0.001)
        player.play()
        XCTAssertTrue(player.isPlaying)
        player.pause()
    }

    func testDurationGrowsAcrossChaptersInOneContinuousTimeline() async throws {
        let player = ProgressivePlayer()
        let bookID = UUID()
        let generator = ImmediateGenerator()
        let directory = try makeDirectory()

        player.receive(bookID: bookID, chapterIndex: 0, segment: try await makeSegment(generator, in: directory, text: "One.", start: 0, duration: 0.1))
        player.receive(bookID: bookID, chapterIndex: 0, segment: try await makeSegment(generator, in: directory, text: "Two.", start: 0.1, duration: 0.1))
        XCTAssertEqual(player.duration, 0.2, accuracy: 0.001)

        // A new chapter's own segment timing restarts at zero; the virtual
        // timeline should still run on from where chapter 0 left off.
        player.receive(bookID: bookID, chapterIndex: 1, segment: try await makeSegment(generator, in: directory, text: "Next chapter.", start: 0, duration: 0.1))
        XCTAssertEqual(player.duration, 0.3, accuracy: 0.001)
    }

    func testSeekingBeyondWhatHasBeenGeneratedClampsToTheEnd() async throws {
        let player = ProgressivePlayer()
        let bookID = UUID()
        let generator = ImmediateGenerator()
        let directory = try makeDirectory()
        player.receive(bookID: bookID, chapterIndex: 0, segment: try await makeSegment(generator, in: directory, text: "Only sentence.", start: 0, duration: 0.1))

        player.seek(to: 10)

        XCTAssertEqual(player.position, player.duration, accuracy: 0.001)
    }

    func testPausingFreezesPositionUntilResumed() async throws {
        let player = ProgressivePlayer()
        let bookID = UUID()
        let generator = ImmediateGenerator()
        let directory = try makeDirectory()
        player.receive(bookID: bookID, chapterIndex: 0, segment: try await makeSegment(generator, in: directory, text: "One.", start: 0, duration: 2))

        player.play()
        try await Task.sleep(for: .milliseconds(150))
        player.pause()
        let frozen = player.position
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(player.position, frozen, accuracy: 0.001, "position moved while paused")
    }

    /// Reaching the end of what has been generated shows a "catching up"
    /// state, not an error, and it resumes the moment more audio arrives.
    func testRunningOutOfGeneratedAudioCatchesUpRatherThanErroring() async throws {
        let player = ProgressivePlayer()
        let bookID = UUID()
        let generator = ImmediateGenerator()
        let directory = try makeDirectory()
        player.receive(bookID: bookID, chapterIndex: 0, segment: try await makeSegment(generator, in: directory, text: "Short.", start: 0, duration: 0.1))

        player.play()
        try await Task.sleep(for: .milliseconds(400))

        XCTAssertEqual(player.state, .catchingUp)
        XCTAssertTrue(player.isPlaying, "catching up should still read as playing, not stopped")

        player.receive(bookID: bookID, chapterIndex: 0, segment: try await makeSegment(generator, in: directory, text: "More.", start: 0.1, duration: 0.1))

        XCTAssertEqual(player.state, .playing)
    }

    func testHandoffReportsPositionAndClearsTheEngine() async throws {
        let player = ProgressivePlayer()
        let bookID = UUID()
        let generator = ImmediateGenerator()
        let directory = try makeDirectory()
        player.receive(bookID: bookID, chapterIndex: 0, segment: try await makeSegment(generator, in: directory, text: "One.", start: 0, duration: 1))
        player.seek(to: 0.4)

        let handoff = player.handoff()

        XCTAssertEqual(handoff.position, 0.4, accuracy: 0.001)
        XCTAssertFalse(handoff.wasPlaying)
        XCTAssertNil(player.bookID)
        XCTAssertEqual(player.duration, 0)
    }

    func testASegmentForADifferentBookStartsOver() async throws {
        let player = ProgressivePlayer()
        let generator = ImmediateGenerator()
        let directory = try makeDirectory()
        player.receive(bookID: UUID(), chapterIndex: 0, segment: try await makeSegment(generator, in: directory, text: "Old book.", start: 0, duration: 5))

        let newBook = UUID()
        player.receive(bookID: newBook, chapterIndex: 0, segment: try await makeSegment(generator, in: directory, text: "New book.", start: 0, duration: 0.1))

        XCTAssertEqual(player.bookID, newBook)
        XCTAssertEqual(player.duration, 0.1, accuracy: 0.001)
    }

    func testStopClearsAnInProgressFollow() async throws {
        let player = ProgressivePlayer()
        let generator = ImmediateGenerator()
        let directory = try makeDirectory()
        player.receive(bookID: UUID(), chapterIndex: 0, segment: try await makeSegment(generator, in: directory, text: "Text.", start: 0, duration: 1))

        player.stop()

        XCTAssertNil(player.bookID)
        XCTAssertEqual(player.state, .idle)
        XCTAssertFalse(player.isPlaying)
    }

    // MARK: -

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttenProgressivePlayerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    /// A real (if silent) segment WAV, wrapped with the timing metadata a
    /// test wants — the file's own length does not need to match `duration`
    /// for the player's virtual timeline to be exercised.
    private func makeSegment(
        _ generator: ImmediateGenerator, in directory: URL, text: String, start: Double, duration: Double
    ) async throws -> SegmentReady {
        let url = try await generator.generate(chapter: "seg-\(UUID().uuidString)", in: directory)
        return SegmentReady(url: url, timing: TimedSegment(index: 0, text: text, start: start, duration: duration, words: []))
    }
}
