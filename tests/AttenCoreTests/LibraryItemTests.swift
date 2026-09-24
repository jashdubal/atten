import AttenCore
import Foundation
import XCTest

/// `hasBookAudio` and `BookChapter.isNarrated` both check that their audio
/// path actually exists on disk, so these fixtures write real (empty) files
/// rather than just setting a path string.
final class LibraryItemTests: XCTestCase {
    private var workspace: URL!

    override func setUpWithError() throws {
        workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttenLibraryItemTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: workspace)
    }

    // MARK: - state

    func testASilentBookHasNoAudioAndIsNotRunning() {
        let book = plainBook()
        XCTAssertEqual(LibraryItem.book(book).state, .silent)
    }

    func testAPreparingBookIsGeneratingWithProgress() throws {
        var book = plainBook()
        book.narrationState = .preparing
        book.chapters = [try chapter(narrated: true), try chapter(narrated: false)]
        guard case .generating(let progress) = LibraryItem.book(book).state else {
            return XCTFail("Expected .generating")
        }
        XCTAssertEqual(progress, 0.5, accuracy: 0.001)
    }

    func testABookWithCombinedAudioIsVoicedEvenIfInterrupted() throws {
        var book = try book(withCombinedAudio: true)
        book.narrationState = .interrupted // e.g. a re-voice was cancelled
        XCTAssertEqual(LibraryItem.book(book).state, .voiced)
    }

    func testAProjectIsAlwaysVoiced() {
        XCTAssertEqual(LibraryItem.project(project()).state, .voiced)
    }

    // MARK: - contentHash

    func testAProjectsContentHashIsComputedFromItsText() {
        let project = project(text: "The quick brown fox.")
        XCTAssertEqual(LibraryItem.project(project).contentHash, ContentHash.of("The quick brown fox."))
    }

    func testABooksContentHashComesFromTheRecord() {
        var book = plainBook()
        book.contentHash = "deadbeef"
        XCTAssertEqual(LibraryItem.book(book).contentHash, "deadbeef")
    }

    // MARK: - filtering

    func testFilteringSeparatesDraftsFromAudiobooksAndProjects() throws {
        let silent = LibraryItem.book(plainBook())
        let voiced = LibraryItem.book(try book(withCombinedAudio: true))
        let project = LibraryItem.project(project())
        let items = [silent, voiced, project]

        XCTAssertEqual(LibraryItem.filter(items, by: .all), items)
        XCTAssertEqual(LibraryItem.filter(items, by: .drafts), [silent])
        XCTAssertEqual(Set(LibraryItem.filter(items, by: .audiobooks).map(\.id)), Set([voiced.id, project.id]))
    }

    func testListeningRequiresAPositionAndNotBeingFinished() throws {
        var midway = try book(withCombinedAudio: true)
        midway.listeningPosition = 1
        var finished = try book(withCombinedAudio: true)
        finished.listeningPosition = try XCTUnwrap(finished.playbackChapters.last?.endTime)
        let untouched = try book(withCombinedAudio: true)

        XCTAssertTrue(LibraryItem.book(midway).isListening)
        XCTAssertFalse(LibraryItem.book(finished).isListening)
        XCTAssertFalse(LibraryItem.book(untouched).isListening)
        XCTAssertFalse(LibraryItem.project(project()).isListening)

        let items = [LibraryItem.book(midway), .book(finished), .book(untouched)]
        XCTAssertEqual(LibraryItem.filter(items, by: .listening), [.book(midway)])
    }

    // MARK: - Fixtures
    //
    // Built directly from `BookRecord`/`ProjectRecord`, the way JSON from
    // `main` would decode into them, rather than through import or narration.

    private func writtenAudioPath(_ name: String) throws -> String {
        let url = workspace.appendingPathComponent(name)
        try Data().write(to: url)
        return url.path
    }

    private func chapter(narrated: Bool) throws -> BookChapter {
        BookChapter(
            title: "Chapter", text: "Once upon a time.",
            audioPath: narrated ? try writtenAudioPath("chapter-\(UUID().uuidString).wav") : nil
        )
    }

    private func book(withCombinedAudio combined: Bool = false) throws -> BookRecord {
        var book = plainBook()
        guard combined else { return book }
        let audioPath = try writtenAudioPath("book.wav")
        book.audioPath = audioPath
        book.chapters[0].audioPath = audioPath
        book.chapters[0].startTime = 0
        book.chapters[0].endTime = 120
        return book
    }

    private func plainBook() -> BookRecord {
        BookRecord(
            title: "A Book", format: .document, sourcePath: workspace.appendingPathComponent("book.txt").path,
            chapters: [BookChapter(title: "One", text: "Once upon a time.")],
            voiceID: "af_heart", speed: 1, audioFormat: .wav
        )
    }

    private func project(text: String = "Some project text.") -> ProjectRecord {
        ProjectRecord(
            title: "A Project", text: text, voiceID: "af_heart", speed: 1,
            format: .mp3, audioPath: workspace.appendingPathComponent("project.mp3").path
        )
    }
}
