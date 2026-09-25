import AttenCore
import Foundation
import XCTest
@testable import Atten

/// The full player follows a narration while it is still being generated
/// (P5), not only what the ordinary queue has loaded — and keeps its place
/// when the narration hands off to its finished recording.
@MainActor
final class ProgressiveReadAlongTests: XCTestCase {
    private let chapterOne = "Rain fell on the harbour. The boats knocked together.\n\nNobody came down to the water."
    private let chapterTwo = "Morning came grey and slow."

    // MARK: - Source

    func testNothingPlayingHasNoSource() throws {
        let (model, _) = try makeModel()
        XCTAssertNil(ReadAlongSession(model: model).source)
    }

    func testTheQueueIsFollowedWhenSomethingIsQueued() async throws {
        let (model, directory) = try makeModel()
        let book = try await shelve(in: model, directory: directory, withAudio: true)
        model.listen(to: book, chapter: book.chapters[0])
        model.pause()
        defer { model.closePlayer() }

        let session = ReadAlongSession(model: model)
        XCTAssertEqual(session.source, .queue(track: book.id))
        XCTAssertFalse(session.isProgressive)
        XCTAssertEqual(session.book?.id, book.id)
    }

    func testANarrationInProgressIsFollowedWhenNothingIsQueued() async throws {
        let (model, directory) = try makeModel()
        let book = try await shelve(in: model, directory: directory)
        try narrate(model, book: book, directory: directory)
        defer { model.progressivePlayer.stop() }

        let session = ReadAlongSession(model: model)
        XCTAssertEqual(session.source, .progressive(book: book.id))
        XCTAssertEqual(session.book?.id, book.id)
        XCTAssertEqual(session.title, book.title)
        XCTAssertEqual(session.subtitle, "Narrating…")
    }

    func testTheQueueWinsWhenBothAreActive() async throws {
        let (model, directory) = try makeModel()
        let book = try await shelve(in: model, directory: directory, withAudio: true)
        try narrate(model, book: book, directory: directory)
        model.listen(to: book, chapter: book.chapters[0])
        model.pause()
        defer {
            model.closePlayer()
            model.progressivePlayer.stop()
        }

        XCTAssertEqual(ReadAlongSession(model: model).source, .queue(track: book.id))
    }

    /// The narration finishing hands the open player straight to the
    /// assembled recording, at the same place, with no moment between them
    /// where it has nothing to show — even paused.
    func testHandoffKeepsTheFullPlayerOnTheSameBookAndPlace() async throws {
        let (model, directory) = try makeModel()
        let book = try await shelve(in: model, directory: directory, withAudio: true)
        try narrate(model, book: book, directory: directory)
        model.progressivePlayer.seek(to: 3.5)
        model.openNowPlaying()
        XCTAssertEqual(ReadAlongSession(model: model).source, .progressive(book: book.id))
        defer { model.closePlayer() }

        model.bookshelf.onNarrationFinished?(BookshelfModel.NarrationRun(
            bookID: book.id, voiceID: book.voiceID, words: 20, audioSeconds: 6, wallSeconds: 1
        ))

        let session = ReadAlongSession(model: model)
        XCTAssertEqual(session.source, .queue(track: book.id))
        XCTAssertEqual(session.book?.id, book.id)
        XCTAssertEqual(session.position, 3.5, accuracy: 0.01)
        XCTAssertFalse(session.isPlaying, "a paused narration stays paused")
        XCTAssertNil(model.progressivePlayer.bookID)
    }

    /// Away from the full player, a paused narration still lets go without
    /// loading anything, as before.
    func testHandoffAwayFromTheFullPlayerLeavesAPausedListenerAlone() async throws {
        let (model, directory) = try makeModel()
        let book = try await shelve(in: model, directory: directory, withAudio: true)
        try narrate(model, book: book, directory: directory)
        model.section = .library

        model.bookshelf.onNarrationFinished?(BookshelfModel.NarrationRun(
            bookID: book.id, voiceID: book.voiceID, words: 20, audioSeconds: 6, wallSeconds: 1
        ))

        XCTAssertNil(ReadAlongSession(model: model).source)
    }

    // MARK: - Scrubber and chapters

    func testTheScrubberReachesOnlyWhatHasBeenGenerated() async throws {
        let (model, directory) = try makeModel()
        let book = try await shelve(in: model, directory: directory)
        try narrate(model, book: book, directory: directory)
        defer { model.progressivePlayer.stop() }

        let session = ReadAlongSession(model: model)
        XCTAssertEqual(session.duration, 6, accuracy: 0.001)
        session.seek(to: 60)
        XCTAssertEqual(session.position, 6, accuracy: 0.001)
        XCTAssertEqual(session.remaining, 0, accuracy: 0.001)
        session.skip(by: -15)
        XCTAssertEqual(session.position, 0, accuracy: 0.001)
    }

    func testChaptersNarratedSoFarAreTickedWhereTheyBegin() async throws {
        let (model, directory) = try makeModel()
        let book = try await shelve(in: model, directory: directory)
        try narrate(model, book: book, directory: directory)
        defer { model.progressivePlayer.stop() }

        let map = try XCTUnwrap(ReadAlongSession(model: model).listeningMap)
        XCTAssertEqual(map.chapters.map(\.index), [0, 1])
        XCTAssertEqual(map.chapters.map(\.title), ["The Harbour", "Morning"])
        XCTAssertEqual(map.chapters.map(\.start), [0, 4])
        XCTAssertEqual(map.chapters.map(\.end), [4, 6])
    }

    func testABookmarkWhileNarratingMarksTheSentenceHeard() async throws {
        let (model, directory) = try makeModel()
        let book = try await shelve(in: model, directory: directory)
        try narrate(model, book: book, directory: directory)
        defer { model.progressivePlayer.stop() }
        let script = ReadAlongSession.script(for: model.progressivePlayer.timeline)
        let heard = try XCTUnwrap(script.sentences.firstIndex { $0.text == "Nobody came down to the water." })

        ReadAlongSession(model: model).addBookmark(sentence: heard, of: script)

        let bookmark = try XCTUnwrap(model.bookshelf.book(id: book.id)?.bookmarks.first)
        XCTAssertEqual(bookmark.location, ReadingLocation(chapterIndex: 0, paragraphIndex: 1))
        XCTAssertEqual(bookmark.excerpt, "Nobody came down to the water.")
        XCTAssertEqual(ReadAlongSession(model: model).time(of: bookmark, script: script) ?? -1, script.sentences[heard].start, accuracy: 0.001)
    }

    // MARK: - Text

    /// An engine that times no words still gets a word to underline.
    func testTheScriptEstimatesWordsTheEngineDidNotTime() async throws {
        let (model, directory) = try makeModel()
        let book = try await shelve(in: model, directory: directory)
        try narrate(model, book: book, directory: directory)
        defer { model.progressivePlayer.stop() }

        let script = ReadAlongSession.script(for: model.progressivePlayer.timeline)
        XCTAssertTrue(script.hasWordTimings)
        XCTAssertEqual(script.sentences.map(\.text), [
            "Rain fell on the harbour.", "The boats knocked together.", "Nobody came down to the water.",
            "Morning came grey and slow.",
        ])
        XCTAssertNotNil(script.locate(time: 0.1)?.word)
    }

    func testWhatIsNotGeneratedYetWaitsAfterIt() async throws {
        let (model, directory) = try makeModel()
        let book = try await shelve(in: model, directory: directory, chapters: 3)
        let url = try ListeningTests.silentAudio(seconds: 0.1, in: directory)
        model.progressivePlayer.receive(bookID: book.id, chapterIndex: 0, segment: SegmentReady(
            url: url, timing: TimedSegment(index: 0, text: "Rain fell on the harbour.", start: 0, duration: 2, words: [])
        ))
        defer { model.progressivePlayer.stop() }

        let rest = ReadAlongSession.remainder(of: book, after: model.progressivePlayer.timeline)
        XCTAssertEqual(rest.map(\.text), [
            "The boats knocked together.", "Nobody came down to the water.", chapterTwo, chapterTwo,
        ])
        XCTAssertEqual(rest.map(\.heading), [nil, nil, "Morning", "Evening"])
    }

    // MARK: - Fixtures

    private func makeModel() throws -> (AppModel, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttenProgressiveReadAlongTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let suite = "AttenProgressiveReadAlongTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        let model = AppModel(
            directories: AppDirectories(applicationSupport: directory),
            settingsStore: SettingsStore(defaults: defaults),
            generator: ImmediateGenerator()
        )
        return (model, directory)
    }

    /// A book on the shelf, with its finished recording when asked for —
    /// what a narration hands off to.
    private func shelve(
        in model: AppModel, directory: URL, withAudio: Bool = false, chapters: Int = 2
    ) async throws -> BookRecord {
        let titles = ["The Harbour", "Morning", "Evening"]
        var book = BookRecord(
            title: "The Harbour Year", author: "M. Aldous", format: .epub,
            sourcePath: directory.appendingPathComponent("harbour.epub").path,
            chapters: (0..<chapters).map { BookChapter(title: titles[$0], text: $0 == 0 ? chapterOne : chapterTwo) },
            voiceID: "af_heart", speed: 1, audioFormat: .wav
        )
        try Data("book".utf8).write(to: book.sourceURL)
        if withAudio {
            book.audioPath = try ListeningTests.silentAudio(seconds: 6, in: directory).path
            let bounds = [0.0, 4, 6]
            for index in book.chapters.indices {
                book.chapters[index].startTime = bounds[index]
                book.chapters[index].endTime = bounds[index + 1]
            }
        }
        try await BookLibraryStore(fileURL: AppDirectories(applicationSupport: directory).booksFile).save([book])
        await model.bookshelf.load()
        return try XCTUnwrap(model.bookshelf.book(id: book.id))
    }

    /// Both chapters narrated so far, as the engine reports them: chapter
    /// one in two segments, chapter two in one, none of them word-timed.
    private func narrate(_ model: AppModel, book: BookRecord, directory: URL) throws {
        let segments: [(Int, String, Double, Double)] = [
            (0, "Rain fell on the harbour. The boats knocked together.", 0, 2.5),
            (0, "Nobody came down to the water.", 2.5, 1.5),
            (1, chapterTwo, 0, 2),
        ]
        for (index, segment) in segments.enumerated() {
            let url = try ListeningTests.silentAudio(seconds: segment.3, in: directory)
            model.progressivePlayer.receive(bookID: book.id, chapterIndex: segment.0, segment: SegmentReady(
                url: url, timing: TimedSegment(index: index, text: segment.1, start: segment.2, duration: segment.3, words: [])
            ))
        }
    }
}
