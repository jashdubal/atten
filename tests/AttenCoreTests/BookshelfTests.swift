import AttenCore
import Foundation
import XCTest
@testable import Atten

@MainActor
final class BookshelfTests: XCTestCase {
    private var workspace: URL!
    private var directories: AppDirectories!
    private var shelf: BookshelfModel!

    override func setUp() async throws {
        workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttenShelfTests-\(UUID().uuidString)")
        directories = AppDirectories(
            applicationSupport: workspace.appendingPathComponent("Application Support")
        )
        try directories.prepare()
        shelf = BookshelfModel(directories: directories, generator: ImmediateGenerator())
    }

    override func tearDown() async throws {
        shelf.cancelNarration()
        try? FileManager.default.removeItem(at: workspace)
    }

    func testImportingABookCopiesItAndSplitsItIntoChapters() async throws {
        let source = try makePDF(pages: (1...12).map { "Page \($0)." })

        await shelf.importBook(from: source, defaults: settings())

        let book = try XCTUnwrap(shelf.books.first)
        XCTAssertNil(shelf.errorMessage)
        XCTAssertEqual(book.chapters.count, 2)
        XCTAssertEqual(book.narratedCount, 0)
        // Atten's copy lives in its own folder, so moving the original later
        // does not break the shelf.
        XCTAssertTrue(book.sourcePath.hasPrefix(directories.bookSources.path))
        XCTAssertTrue(book.sourceExists)
        try FileManager.default.removeItem(at: source)
        XCTAssertTrue(book.sourceExists)
    }

    func testImportingTheSameContentUnderADifferentNameDedupes() async throws {
        let first = try writeText("Once upon a time, in a house on a hill.", named: "story.txt")
        let result = await shelf.importBook(from: first, defaults: settings())
        let original = try XCTUnwrap(shelf.books.first)
        XCTAssertEqual(result, .imported(original))

        let second = try writeText("Once upon a time, in a house on a hill.", named: "story-copy.txt")
        let secondResult = await shelf.importBook(from: second, defaults: settings())

        XCTAssertEqual(secondResult, .alreadyInLibrary(original.id))
        XCTAssertEqual(shelf.books.count, 1)
        // Nothing was left behind for the duplicate: only the first import's copy exists.
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: directories.bookSources.path)
        XCTAssertEqual(leftovers.count, 1)
    }

    func testImportingAWhitespaceOnlyDifferenceDedupes() async throws {
        let first = try writeText("Once upon a time,\nin a house on a hill.", named: "story.txt")
        await shelf.importBook(from: first, defaults: settings())
        let original = try XCTUnwrap(shelf.books.first)

        let second = try writeText("  Once   upon a time,   in a house  on a hill.  ", named: "story-2.txt")
        let secondResult = await shelf.importBook(from: second, defaults: settings())

        XCTAssertEqual(secondResult, .alreadyInLibrary(original.id))
        XCTAssertEqual(shelf.books.count, 1)
    }

    func testImportingDifferentTextDoesNotDedupe() async throws {
        let first = try writeText("Once upon a time, in a house on a hill.", named: "story.txt")
        await shelf.importBook(from: first, defaults: settings())

        let second = try writeText("A completely different book entirely.", named: "other.txt")
        let secondResult = await shelf.importBook(from: second, defaults: settings())

        XCTAssertEqual(shelf.books.count, 2)
        guard case .imported = secondResult else { return XCTFail("Expected a new import") }
    }

    /// A book saved before content hashes existed has none stored; the shelf
    /// fills it in from the book's own chapters rather than treating it as
    /// unrelated to a later import of the same text.
    func testDedupeBackfillsAMissingHashFromAnOlderRecord() async throws {
        let older = BookRecord(
            title: "Older book", format: .document, sourcePath: workspace.appendingPathComponent("older.txt").path,
            chapters: [BookChapter(title: "Older book", text: "Once upon a time, in a house on a hill.")],
            voiceID: "af_heart", speed: 1, audioFormat: .wav
        )
        try Data("Once upon a time, in a house on a hill.".utf8).write(to: URL(fileURLWithPath: older.sourcePath))
        try await BookLibraryStore(fileURL: directories.booksFile).save([older])
        await shelf.load()
        XCTAssertNil(shelf.books.first?.contentHash)

        let duplicate = try writeText("Once upon a time, in a house on a hill.", named: "duplicate.txt")
        let result = await shelf.importBook(from: duplicate, defaults: settings())

        XCTAssertEqual(result, .alreadyInLibrary(older.id))
        XCTAssertEqual(shelf.books.count, 1)
    }

    func testImportingAnUnreadableBookLeavesNoCopyBehind() async throws {
        let source = workspace.appendingPathComponent("torn.epub")
        try Data("not a zip".utf8).write(to: source)

        await shelf.importBook(from: source, defaults: settings())

        XCTAssertTrue(shelf.books.isEmpty)
        XCTAssertNotNil(shelf.errorMessage)
        let leftovers = try FileManager.default.contentsOfDirectory(
            atPath: directories.bookSources.path
        )
        XCTAssertEqual(leftovers, [])
    }

    /// The shelf counts narration for its cards rather than making each card
    /// ask the file system once per chapter while it draws.
    func testNarratedCountsFollowTheShelfAndTheFilesOnDisk() async throws {
        await shelf.importBook(
            from: try makePDF(pages: (1...25).map { "Page \($0)." }),
            defaults: settings()
        )
        let book = try XCTUnwrap(shelf.books.first)
        XCTAssertEqual(shelf.narratedCount(of: book), 0)
        XCTAssertFalse(shelf.isFullyNarrated(book))

        shelf.narrate(book.id, useMPS: false)
        try await waitForNarration()

        let narrated = try XCTUnwrap(shelf.book(id: book.id))
        XCTAssertEqual(shelf.narratedCount(of: narrated), 3)
        XCTAssertTrue(shelf.isFullyNarrated(narrated))

        // Narration deleted behind Atten's back is caught the next time the
        // Library is opened, not left as a play button that does nothing.
        try FileManager.default.removeItem(at: try XCTUnwrap(narrated.chapters[0].audioURL))
        shelf.refreshNarrationCounts()

        XCTAssertEqual(shelf.narratedCount(of: narrated), 0)
        XCTAssertFalse(shelf.isFullyNarrated(narrated))
    }

    func testLibraryFiltersCombineMetadataSearchAndNarrationState() async throws {
        await shelf.importBook(
            from: try makePDF(pages: ["Older book."]),
            defaults: settings()
        )
        let older = try XCTUnwrap(shelf.books.first)
        try await Task.sleep(for: .milliseconds(2))
        await shelf.importBook(
            from: try makePDF(pages: ["Newer book."]),
            defaults: settings()
        )
        let newer = try XCTUnwrap(shelf.books.first)

        XCTAssertEqual(Set(shelf.filteredBooks(for: .all).map(\.id)), Set([newer.id, older.id]))
        XCTAssertTrue(shelf.filteredBooks(for: .audiobooks).isEmpty)
        XCTAssertEqual(Set(shelf.filteredBooks(for: .drafts).map(\.id)), Set([newer.id, older.id]))

        shelf.narrate(newer.id, chapters: [0], useMPS: false)
        try await waitForNarration()

        XCTAssertEqual(shelf.filteredBooks(for: .audiobooks).map(\.id), [newer.id])
        XCTAssertEqual(shelf.filteredBooks(for: .drafts).map(\.id), [older.id])
        XCTAssertEqual(
            shelf.filteredBooks(for: .audiobooks, query: newer.title).map(\.id),
            [newer.id]
        )
        XCTAssertTrue(shelf.filteredBooks(for: .audiobooks, query: older.title).isEmpty)
    }

    func testBooksForFilterAlwaysAppliesTheChosenSort() async throws {
        await shelf.importBook(from: try makePDF(pages: ["First book."]), defaults: settings())
        let first = try XCTUnwrap(shelf.books.first)
        try await Task.sleep(for: .milliseconds(2))
        await shelf.importBook(from: try makePDF(pages: ["Second book."]), defaults: settings())
        let second = try XCTUnwrap(shelf.books.first)

        // A PDF without title metadata falls back to its (randomised) file
        // name, so the expected order is computed the same way the sort does
        // rather than assumed from the page text.
        let byTitle = [first, second]
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            .map(\.id)

        // "All" and "Audiobooks" honour the chosen sort…
        XCTAssertEqual(shelf.books(for: .all, sort: .title).map(\.id), byTitle)

        shelf.narrate(first.id, chapters: [0], useMPS: false)
        try await waitForNarration()
        shelf.narrate(second.id, chapters: [0], useMPS: false)
        try await waitForNarration()
        XCTAssertEqual(shelf.books(for: .audiobooks, sort: .title).map(\.id), byTitle)

        // …and choosing the "Recently added" sort always puts the newest first.
        XCTAssertEqual(
            shelf.books(for: .all, sort: .recentlyAdded).map(\.id),
            [second.id, first.id]
        )

        // A search query still narrows the sorted result.
        XCTAssertEqual(
            shelf.books(for: .all, query: first.title, sort: .title).map(\.id),
            [first.id]
        )
    }

    func testLibrarySortUsesMetadataWithoutMutatingRecords() {
        let first = BookRecord(
            title: "Chapter 10", author: "Adams", format: .pdf,
            sourcePath: "/book.pdf", chapters: [], voiceID: "af_heart",
            speed: 1, audioFormat: .wav, addedAt: Date(timeIntervalSince1970: 1)
        )
        var second = first
        second.id = UUID()
        second.title = "Chapter 2"
        second.author = nil
        second.addedAt = Date(timeIntervalSince1970: 2)
        let records = [first, second]

        XCTAssertEqual(LibrarySort.recentlyAdded.sorted(records), [second, first])
        XCTAssertEqual(LibrarySort.title.sorted(records), [second, first])
        XCTAssertEqual(LibrarySort.author.sorted(records), [first, second])
        XCTAssertEqual(records, [first, second])

        // Equal sort keys must not reshuffle a shelf on each redraw.
        second.title = first.title
        let expected = [first, second].sorted { $0.id.uuidString < $1.id.uuidString }
        XCTAssertEqual(LibrarySort.title.sorted([second, first]), expected)
    }

    func testNarratingABookWritesOneAudioFileWithChapterTimestamps() async throws {
        await shelf.importBook(
            from: try makePDF(pages: (1...25).map { "Page \($0)." }),
            defaults: settings()
        )
        let book = try XCTUnwrap(shelf.books.first)
        XCTAssertEqual(book.chapters.count, 3)

        shelf.narrate(book.id, useMPS: false)
        try await waitForNarration()

        let narrated = try XCTUnwrap(shelf.book(id: book.id))
        XCTAssertTrue(narrated.isFullyNarrated)
        XCTAssertEqual(narrated.narrationQueue.count, 1)
        // All chapter markers refer to the same continuous recording.
        XCTAssertEqual(
            narrated.chapters.compactMap { $0.audioURL?.lastPathComponent },
            Array(repeating: try XCTUnwrap(narrated.audioURL).lastPathComponent, count: 3)
        )
        XCTAssertNil(shelf.errorMessage)
    }

    func testNarrationProgressSurvivesAReloadOfTheShelf() async throws {
        await shelf.importBook(
            from: try makePDF(pages: (1...12).map { "Page \($0)." }),
            defaults: settings()
        )
        let book = try XCTUnwrap(shelf.books.first)

        shelf.narrate(book.id, chapters: [0], useMPS: false)
        try await waitForNarration()

        // A second session reads the same file and must see the finished
        // chapter as finished, so narration resumes rather than restarts.
        let reopened = BookshelfModel(directories: directories, generator: ImmediateGenerator())
        await reopened.load()
        let reloaded = try XCTUnwrap(reopened.book(id: book.id))
        XCTAssertEqual(reloaded.narratedCount, 2)
        XCTAssertTrue(reloaded.hasBookAudio)
        XCTAssertEqual(reloaded.chapters[1].startTime ?? -1, 0.1, accuracy: 0.0001)
    }

    func testExistingChapterFilesAreCombinedOnlyOnRequest() async throws {
        await shelf.importBook(from: try makePDF(pages: (1...12).map { "Page \($0)." }), defaults: settings())
        var oldBook = try XCTUnwrap(shelf.books.first)
        let generator = ImmediateGenerator()
        let directory = directories.narrations.appendingPathComponent(oldBook.id.uuidString)
        for index in oldBook.chapters.indices {
            oldBook.chapters[index].audioPath = try await generator.generate(chapter: "Chapter \(index)", in: directory).path
        }
        let oldURLs = oldBook.chapters.compactMap(\.audioURL)
        try await BookLibraryStore(fileURL: directories.booksFile).save([oldBook])
        let reopened = BookshelfModel(directories: directories, generator: generator)
        await reopened.load()
        XCTAssertFalse(reopened.isNarrating)
        XCTAssertFalse(try XCTUnwrap(reopened.books.first).hasBookAudio)
        reopened.narrate(oldBook.id, useMPS: false)
        for _ in 0..<200 where reopened.isNarrating { try await Task.sleep(for: .milliseconds(10)) }
        let migrated = try XCTUnwrap(reopened.books.first)
        XCTAssertTrue(migrated.hasBookAudio)
        XCTAssertEqual(migrated.narrationTracks.count, 1)
        XCTAssertEqual(migrated.chapters[1].startTime ?? -1, 0.1, accuracy: 0.0001)
        XCTAssertTrue(oldURLs.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
    }

    func testChangingVoiceRetainsPlayableAudioUntilReplacementCommits() async throws {
        await shelf.importBook(
            from: try makePDF(pages: (1...12).map { "Page \($0)." }),
            defaults: settings()
        )
        let book = try XCTUnwrap(shelf.books.first)
        shelf.narrate(book.id, useMPS: false)
        try await waitForNarration()
        XCTAssertEqual(shelf.book(id: book.id)?.narratedCount, 2)

        shelf.updateVoice("bf_emma", for: book.id)

        let changed = try XCTUnwrap(shelf.book(id: book.id))
        XCTAssertEqual(changed.voiceID, "bf_emma")
        XCTAssertEqual(changed.narratedCount, 0)
        XCTAssertTrue(changed.hasBookAudio)
        XCTAssertTrue(changed.needsPreparation)
        let previousURL = try XCTUnwrap(changed.audioURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: previousURL.path))
        shelf.narrate(book.id, useMPS: false)
        try await waitForNarration()
        let replacement = try XCTUnwrap(shelf.book(id: book.id))
        XCTAssertTrue(replacement.hasBookAudio)
        XCTAssertFalse(replacement.needsPreparation)
        XCTAssertNil(replacement.previousChapters)
        XCTAssertNotEqual(replacement.audioURL, previousURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: previousURL.path))
    }

    func testRemovingABookDeletesItsCopyAndItsNarration() async throws {
        await shelf.importBook(
            from: try makePDF(pages: (1...12).map { "Page \($0)." }),
            defaults: settings()
        )
        let book = try XCTUnwrap(shelf.books.first)
        shelf.narrate(book.id, useMPS: false)
        try await waitForNarration()

        shelf.remove(book.id)

        XCTAssertTrue(shelf.books.isEmpty)
        XCTAssertFalse(book.sourceExists)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: directories.narrations.appendingPathComponent(book.id.uuidString).path
        ))
    }

    func testASalvageableShelfKeepsTheBooksThatStillDecode() async throws {
        let good = BookRecord(
            title: "Readable",
            format: .pdf,
            sourcePath: "/tmp/readable.pdf",
            chapters: [BookChapter(title: "One", text: "Text")],
            voiceID: "af_heart",
            speed: 1,
            audioFormat: .mp3
        )
        let encoded = try JSONEncoder().encode([good])
        var array = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [[String: Any]]
        )
        // A record with no sourcePath at all cannot be recovered.
        array.append(["title": "Damaged"])
        try JSONSerialization.data(withJSONObject: array).write(to: directories.booksFile)

        let store = BookLibraryStore(fileURL: directories.booksFile)
        let loaded = try await store.load()

        XCTAssertEqual(loaded.map(\.title), ["Readable"])
    }

    func testABookWrittenByAnOlderAttenStillLoads() throws {
        let json = Data("""
        [{"sourcePath": "/tmp/old.epub", "chapters": [{"text": "Once upon a time."}]}]
        """.utf8)

        let book = try XCTUnwrap(try JSONDecoder().decode([BookRecord].self, from: json).first)

        XCTAssertEqual(book.title, "old")
        XCTAssertEqual(book.format, .epub)
        XCTAssertEqual(book.voiceID, "af_heart")
        XCTAssertEqual(book.audioFormat, .mp3)
        XCTAssertEqual(book.chapters.first?.title, "Chapter")
    }

    // MARK: - Reading

    func testABookmarkIsAddedAndClearedByMarkingTheSameSpotTwice() async throws {
        await shelf.importBook(
            from: try makePDF(pages: (1...12).map { "Page \($0)." }),
            defaults: settings()
        )
        let book = try XCTUnwrap(shelf.books.first)
        let spot = ReadingLocation(chapterIndex: 0, pageIndex: 3)

        shelf.toggleBookmark(at: spot, excerpt: "Page 4.", in: book.id)
        XCTAssertEqual(shelf.book(id: book.id)?.bookmarks.map(\.excerpt), ["Page 4."])

        // The same page reached from anywhere is the same mark, so pressing
        // the button again clears it rather than marking the page twice.
        shelf.toggleBookmark(at: ReadingLocation(chapterIndex: 1, pageIndex: 3), excerpt: "", in: book.id)
        XCTAssertEqual(shelf.book(id: book.id)?.bookmarks, [])
    }

    func testBookmarksAreKeptInReadingOrderAndSurviveAReload() async throws {
        await shelf.importBook(
            from: try makePDF(pages: (1...25).map { "Page \($0)." }),
            defaults: settings()
        )
        let book = try XCTUnwrap(shelf.books.first)

        shelf.toggleBookmark(at: ReadingLocation(chapterIndex: 2, pageIndex: 21), excerpt: "last", in: book.id)
        shelf.toggleBookmark(at: ReadingLocation(chapterIndex: 0, pageIndex: 2), excerpt: "first", in: book.id)
        try await Task.sleep(for: .milliseconds(50))

        let reopened = BookshelfModel(directories: directories, generator: ImmediateGenerator())
        await reopened.load()
        let reloaded = try XCTUnwrap(reopened.book(id: book.id))
        XCTAssertEqual(reloaded.bookmarks.map(\.excerpt), ["first", "last"])
    }

    func testWhereTheReaderStoppedIsRemembered() async throws {
        await shelf.importBook(
            from: try makePDF(pages: (1...12).map { "Page \($0)." }),
            defaults: settings()
        )
        let book = try XCTUnwrap(shelf.books.first)

        shelf.updateReadingLocation(ReadingLocation(chapterIndex: 1, pageIndex: 10), for: book.id)
        try await Task.sleep(for: .milliseconds(50))

        let reopened = BookshelfModel(directories: directories, generator: ImmediateGenerator())
        await reopened.load()
        XCTAssertEqual(reopened.book(id: book.id)?.lastLocation?.pageIndex, 10)
    }

    /// Changing the voice throws away narration, because a book read in two
    /// voices is worse than one that has to be generated again. It must not
    /// throw away the reading, which has nothing to do with how it sounds.
    func testChangingTheVoiceKeepsBookmarksAndTheReadingPosition() async throws {
        await shelf.importBook(
            from: try makePDF(pages: (1...12).map { "Page \($0)." }),
            defaults: settings()
        )
        let book = try XCTUnwrap(shelf.books.first)
        shelf.narrate(book.id, useMPS: false)
        try await waitForNarration()
        shelf.toggleBookmark(at: ReadingLocation(chapterIndex: 0, pageIndex: 3), excerpt: "kept", in: book.id)
        shelf.updateReadingLocation(ReadingLocation(chapterIndex: 1, pageIndex: 10), for: book.id)

        shelf.updateVoice("bf_emma", for: book.id)

        let changed = try XCTUnwrap(shelf.book(id: book.id))
        XCTAssertEqual(changed.narratedCount, 0)
        XCTAssertEqual(changed.bookmarks.map(\.excerpt), ["kept"])
        XCTAssertEqual(changed.lastLocation?.pageIndex, 10)
    }

    // MARK: - Drafts

    func testSavingADraftWritesATextFileAndASilentSingleChapterBook() throws {
        let draft = try shelf.saveDraft(title: "My Draft", text: "Some text to narrate.", voiceID: "af_heart", defaults: settings())

        XCTAssertEqual(shelf.books.map(\.id), [draft.id])
        XCTAssertEqual(draft.format, .document)
        XCTAssertEqual(draft.narrationState, .unprepared)
        XCTAssertEqual(draft.chapters.count, 1)
        XCTAssertEqual(draft.chapters[0].text, "Some text to narrate.")
        XCTAssertEqual(LibraryItem.book(draft).state, .silent)
        XCTAssertEqual(try String(contentsOf: draft.sourceURL, encoding: .utf8), "Some text to narrate.")
    }

    func testSavingADraftAgainWithTheSameIDUpdatesItInPlace() throws {
        let first = try shelf.saveDraft(title: "Draft One", text: "First version.", voiceID: "af_heart", defaults: settings())

        let updated = try shelf.saveDraft(
            id: first.id, title: "Draft One, Revised", text: "Second version.",
            voiceID: "af_heart", defaults: settings()
        )

        XCTAssertEqual(shelf.books.count, 1)
        XCTAssertEqual(updated.id, first.id)
        XCTAssertEqual(updated.title, "Draft One, Revised")
        XCTAssertEqual(try String(contentsOf: updated.sourceURL, encoding: .utf8), "Second version.")
    }

    func testUpdatingADraftKeepsListeningStateAndNewDraftsGenerateAtNormalSpeed() throws {
        var defaults = settings()
        defaults.defaultSpeed = 1.4
        let first = try shelf.saveDraft(title: "Draft", text: "First.", voiceID: "af_heart", defaults: defaults)
        XCTAssertEqual(first.speed, 1.0)

        shelf.saveListeningPosition(42, for: first.id)
        shelf.toggleBookmark(at: ReadingLocation(chapterIndex: 0, paragraphIndex: 0), excerpt: "First.", in: first.id)
        let updated = try shelf.saveDraft(id: first.id, title: "Draft", text: "Second.", voiceID: "af_bella", defaults: defaults)

        XCTAssertEqual(updated.listeningPosition, 42)
        XCTAssertEqual(updated.bookmarks.count, 1)
        XCTAssertEqual(updated.chapters.map(\.id), first.chapters.map(\.id))
        XCTAssertEqual(updated.voiceID, "af_bella")
        XCTAssertEqual(updated.contentHash, ContentHash.of("Second."))
    }

    /// A draft is a book with its own dedicated text file, so `remove(_:)` —
    /// which already deletes only one book's own source file — needs no
    /// special case for drafts.
    func testRemovingADraftDeletesOnlyItsOwnTextFile() throws {
        let keep = try shelf.saveDraft(title: "Keep", text: "Keep me.", voiceID: "af_heart", defaults: settings())
        let discard = try shelf.saveDraft(title: "Discard", text: "Discard me.", voiceID: "af_heart", defaults: settings())

        shelf.remove(discard.id)

        XCTAssertEqual(shelf.books.map(\.id), [keep.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: keep.sourceURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: discard.sourceURL.path))
    }

    func testADraftReloadsWithItsTextIntact() async throws {
        let draft = try shelf.saveDraft(title: "Reload Me", text: "Text that must survive a reload.", voiceID: "af_heart", defaults: settings())
        try await shelf.flushPersistence()

        let reopened = BookshelfModel(directories: directories, generator: ImmediateGenerator())
        await reopened.load()

        let reloaded = try XCTUnwrap(reopened.book(id: draft.id))
        XCTAssertEqual(reloaded.chapters.first?.text, "Text that must survive a reload.")
        XCTAssertEqual(LibraryItem.book(reloaded).state, .silent)
    }

    // MARK: - Helpers

    private func settings() -> AppSettings {
        AppSettings(
            outputDirectory: directories.defaultExports.path,
            defaultFormat: .wav,
            selectedVoiceID: "af_heart"
        )
    }

    private func waitForNarration() async throws {
        for _ in 0..<200 {
            if !shelf.isNarrating { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for narration to finish")
    }

    private func writeText(_ text: String, named name: String) throws -> URL {
        let url = workspace.appendingPathComponent(name)
        try Data(text.utf8).write(to: url)
        return url
    }

    private func makePDF(pages: [String]) throws -> URL {
        let url = workspace.appendingPathComponent("book-\(UUID().uuidString).pdf")
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let context = try XCTUnwrap(CGContext(url as CFURL, mediaBox: &mediaBox, nil))
        for page in pages {
            context.beginPDFPage(nil)
            let graphics = NSGraphicsContext(cgContext: context, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = graphics
            NSAttributedString(
                string: page,
                attributes: [.font: NSFont.systemFont(ofSize: 14)]
            ).draw(in: CGRect(x: 72, y: 72, width: 468, height: 648))
            NSGraphicsContext.restoreGraphicsState()
            context.endPDFPage()
        }
        context.closePDF()
        return url
    }
}
