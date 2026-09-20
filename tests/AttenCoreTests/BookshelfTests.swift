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

    func testNarratingABookWritesOneAudioFilePerChapter() async throws {
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
        XCTAssertEqual(narrated.narrationQueue.count, 3)
        // Numbered so the folder reads in chapter order.
        XCTAssertEqual(
            narrated.chapters.compactMap { $0.audioURL?.lastPathComponent },
            ["001 Pages 1–10.wav", "002 Pages 11–20.wav", "003 Pages 21–25.wav"]
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
        XCTAssertEqual(reloaded.narratedCount, 1)
        XCTAssertFalse(reloaded.chapters[1].isNarrated)
    }

    func testChangingTheVoiceClearsNarrationSoOneBookIsReadInOneVoice() async throws {
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
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: directories.narrations.appendingPathComponent(book.id.uuidString).path
        ))
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
