@testable import AttenCore
import Foundation
import XCTest
@testable import Atten

/// Thousand-page books: how long importing one takes and how much memory it
/// needs, whether its chapters are found, and what counting its words costs.
/// Prints a `STRESS |` table.
@MainActor
final class LongDocumentStressTests: XCTestCase {
    private var root: URL!

    override func setUp() async throws {
        try StressFixtures.skipUnlessEnabled()
        root = try StressFixtures.dataDirectory("documents")
    }

    override func tearDown() async throws {
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    func testAThousandPageEPUBImports() async throws {
        let chaptered = try StressFixtures.epub(pages: 1_000, files: 50, in: root)
        try await measureImport(chaptered, label: "EPUB 1,000 pages, 50 files", expectedChapters: 50)

        // The whole book in one spine document: one chapter, a megabyte of text.
        let single = try StressFixtures.epub(pages: 1_000, files: 1, in: root)
        try await measureImport(single, label: "EPUB 1,000 pages, 1 file", expectedChapters: 1)

        // Not well-formed, so every file goes through the tag-stripping fallback.
        let broken = try StressFixtures.epub(pages: 1_000, files: 1, wellFormed: false, in: root)
        try await measureImport(broken, label: "EPUB 1,000 pages, 1 malformed file", expectedChapters: 1)
    }

    func testAThousandPagePDFImports() async throws {
        let (outlined, buildTime) = try StressFixtures.time {
            try StressFixtures.pdf(pages: 1_000, pagesPerChapter: 20, in: root)
        }
        StressFixtures.report("fixture: PDF 1,000 pages", buildTime)
        let plain = try StressFixtures.pdf(pages: 1_000, pagesPerChapter: nil, in: root)
        // No outline, so it is cut every ten pages.
        try await measureImport(plain, label: "PDF 1,000 pages, no outline", expectedChapters: 100)
        try await measureImport(outlined, label: "PDF 1,000 pages, outline", expectedChapters: 50)
    }

    /// Doubling the text should double the time. Splicing each match back
    /// into the string instead quadruples it.
    func testEntityAndTagCleanupScaleLinearly() throws {
        let paragraph = "<p>Call me&nbsp;Ishmael&mdash;<em>never</em> mind&hellip; how &amp; long.</p>\n"
        var previous: Double?
        for copies in [20_000, 40_000, 80_000] {
            let html = String(repeating: paragraph, count: copies)
            let (_, entityTime) = StressFixtures.time { _ = HTMLEntities.decodeRemaining(in: html) }
            let (_, readTime) = StressFixtures.time { _ = XHTMLText.read(html + "<unclosed") }
            StressFixtures.report("entities + fallback read, \(html.utf8.count / 1_024) KB", entityTime + readTime,
                                  String(format: "entities %.0f ms, tag-stripping read %.0f ms", entityTime * 1_000, readTime * 1_000))
            if let previous { XCTAssertLessThan(entityTime + readTime, previous * 3, "cleanup grew faster than the text") }
            previous = entityTime + readTime
        }
    }

    func testCountingTheWordsOfAThousandPagesIsCheap() {
        let text = StressFixtures.words(300_000, seed: 1)
        let (count, seconds) = StressFixtures.time { ListenEstimator.wordCount(text) }
        XCTAssertEqual(count, text.split(whereSeparator: \.isWhitespace).count)
        StressFixtures.report("ListenEstimator.wordCount, 300,000 words", seconds)

        // How far narration has reached, recomputed on each progress tick of a
        // thousand-page draft that Create cut into even parts.
        let draft = (0..<3_000).map { StressFixtures.words(100, seed: $0) }.joined(separator: "\n\n")
        let chapters = ChapterDetection.auto.chapters(in: draft, title: "Draft").map(\.text)
        let (extent, extentTime) = StressFixtures.time {
            SpokenExtent(text: draft, chapters: chapters, chapterIndex: chapters.count - 1, spokenWords: 10)
        }
        XCTAssertGreaterThan(extent.words, 290_000)
        StressFixtures.report("SpokenExtent at the last of \(chapters.count) parts", extentTime)
    }

    private func measureImport(_ url: URL, label: String, expectedChapters: Int) async throws {
        let directories = AppDirectories(applicationSupport: root.appendingPathComponent(UUID().uuidString))
        try directories.prepare()
        let shelf = BookshelfModel(directories: directories, generator: ImmediateGenerator())
        let baseline = StressFixtures.footprintMB()
        let sampler = FootprintSampler()
        let (_, importTime) = await StressFixtures.time {
            await shelf.importBook(from: url, defaults: AppSettings(outputDirectory: root.path))
        }
        let grown = sampler.stop() - baseline
        XCTAssertNil(shelf.importErrorMessage, label)
        let book = try XCTUnwrap(shelf.books.first, label)
        XCTAssertEqual(book.chapters.count, expectedChapters, label)
        let (words, countTime) = StressFixtures.time { book.wordCount }
        XCTAssertGreaterThan(words, 250_000, label)
        let estimate = ListenEstimator().listenDuration(words: words, voiceID: book.voiceID)
        StressFixtures.report("\(label): import", importTime,
            String(format: "%d chapters, %d words, ≈%.0f h listen, peak +%.0f MB during import",
                   book.chapters.count, words, estimate / 3_600, grown))
        StressFixtures.report("\(label): word count", countTime)
        XCTAssertLessThan(importTime, 60, label)
    }
}
