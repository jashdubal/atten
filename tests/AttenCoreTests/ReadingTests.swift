import AttenCore
import Foundation
import XCTest

final class ReadingTests: XCTestCase {

    // MARK: - Paragraphs

    func testAChapterIsReadAsTheParagraphsItWasWrittenIn() {
        let chapter = BookChapter(
            title: "One",
            text: "First line.\n\nSecond line.\n\n\n   \n\nThird line.\n\n"
        )

        XCTAssertEqual(chapter.paragraphs, ["First line.", "Second line.", "Third line."])
        XCTAssertEqual(chapter.wordCount, 6)
    }

    // MARK: - Pages

    func testAnEPUBIsLaidOutAtASteadyNumberOfWordsPerPage() {
        // 250 words is one page, 500 is two, and a ten-word chapter is still a
        // page of its own rather than sharing a number with its neighbour.
        let pagination = ReaderPagination(epubChapterWordCounts: [250, 500, 10])

        XCTAssertEqual(pagination.pageCount, 4)
        XCTAssertEqual(pagination.startPage(ofChapter: 0), 1)
        XCTAssertEqual(pagination.endPage(ofChapter: 0), 1)
        XCTAssertEqual(pagination.startPage(ofChapter: 1), 2)
        XCTAssertEqual(pagination.endPage(ofChapter: 1), 3)
        XCTAssertEqual(pagination.startPage(ofChapter: 2), 4)
        XCTAssertEqual(pagination.endPage(ofChapter: 2), 4)
    }

    func testAPositionInsideAnEPUBChapterLandsOnAPageOfIt() {
        let pagination = ReaderPagination(epubChapterWordCounts: [250, 500, 10])

        XCTAssertEqual(pagination.page(chapter: 1, wordsIntoChapter: 0), 2)
        XCTAssertEqual(pagination.page(chapter: 1, wordsIntoChapter: 249), 2)
        XCTAssertEqual(pagination.page(chapter: 1, wordsIntoChapter: 300), 3)
    }

    func testAPDFKeepsItsOwnPagesAndEveryChapterStillHasAnEnd() {
        let pagination = ReaderPagination(
            pdfChapterPageIndexes: [0, 9, 24],
            pageCount: 30
        )

        XCTAssertEqual(pagination.pageCount, 30)
        XCTAssertEqual(pagination.startPage(ofChapter: 0), 1)
        XCTAssertEqual(pagination.endPage(ofChapter: 0), 9)
        XCTAssertEqual(pagination.startPage(ofChapter: 1), 10)
        XCTAssertEqual(pagination.endPage(ofChapter: 1), 24)
        XCTAssertEqual(pagination.startPage(ofChapter: 2), 25)
        XCTAssertEqual(pagination.endPage(ofChapter: 2), 30)
    }

    /// An outline that runs backwards, or points past the end of the file, must
    /// not produce a chapter that ends before it starts or a page number larger
    /// than the book.
    func testADisorderedOutlineStillProducesPagesInOrder() {
        let pagination = ReaderPagination(
            pdfChapterPageIndexes: [4, 1, nil, 400],
            pageCount: 10
        )

        let starts = (0..<4).map { pagination.startPage(ofChapter: $0) }
        XCTAssertEqual(starts, starts.sorted())
        XCTAssertTrue(starts.allSatisfy { $0 >= 1 && $0 <= 10 })
        for chapter in 0..<4 {
            XCTAssertGreaterThanOrEqual(
                pagination.endPage(ofChapter: chapter),
                pagination.startPage(ofChapter: chapter)
            )
        }
    }

    func testABookWithNoChaptersStillHasAPage() {
        XCTAssertEqual(ReaderPagination(epubChapterWordCounts: []).pageCount, 1)
        XCTAssertEqual(ReaderPagination.empty.pageCount, 1)
        XCTAssertEqual(ReaderPagination(pdfChapterPageIndexes: [], pageCount: 0).pageCount, 1)
    }

    func testProgressIsTheShareOfTheBookAlreadyRead() {
        let pagination = ReaderPagination(epubChapterWordCounts: [250, 250, 250, 250])

        XCTAssertEqual(pagination.fraction(ofPage: 1), 0.25, accuracy: 0.001)
        XCTAssertEqual(pagination.fraction(ofPage: 4), 1, accuracy: 0.001)
        XCTAssertEqual(pagination.fraction(ofPage: 99), 1, accuracy: 0.001)
    }

    func testAPDFPageBelongsToTheChapterItOpensIn() {
        let book = record(chapters: [
            BookChapter(title: "Front matter", text: "a", pageIndex: 0),
            BookChapter(title: "One", text: "b", pageIndex: 5),
            BookChapter(title: "Two", text: "c", pageIndex: 20),
        ])

        XCTAssertEqual(book.chapterIndex(forPage: 0), 0)
        XCTAssertEqual(book.chapterIndex(forPage: 4), 0)
        XCTAssertEqual(book.chapterIndex(forPage: 5), 1)
        XCTAssertEqual(book.chapterIndex(forPage: 19), 1)
        XCTAssertEqual(book.chapterIndex(forPage: 900), 2)
    }

    // MARK: - Search

    func testSearchFindsEveryMatchInReadingOrder() {
        let chapters = [
            BookChapter(title: "One", text: "The whale surfaced.\n\nNothing here."),
            BookChapter(title: "Two", text: "A whale, and then another whale."),
        ]

        let hits = BookSearch.run("whale", in: chapters)

        XCTAssertEqual(hits.map(\.chapterIndex), [0, 1, 1])
        XCTAssertEqual(hits.map(\.paragraphIndex), [0, 0, 0])
        XCTAssertEqual(Set(hits.map(\.id)).count, 3)
    }

    func testSearchIgnoresCaseAndAccents() {
        let chapters = [BookChapter(title: "One", text: "She left the Café early.")]

        XCTAssertEqual(BookSearch.run("cafe", in: chapters).first?.match, "Café")
        XCTAssertEqual(BookSearch.run("CAFÉ", in: chapters).first?.match, "Café")
    }

    func testAResultCarriesEnoughOfTheSentenceToRecogniseIt() throws {
        let padding = String(repeating: "x", count: 200)
        let chapters = [BookChapter(title: "One", text: "\(padding) needle \(padding)")]

        let hit = try XCTUnwrap(BookSearch.run("needle", in: chapters).first)

        XCTAssertEqual(hit.match, "needle")
        XCTAssertTrue(hit.before.hasPrefix("…"))
        XCTAssertTrue(hit.after.hasSuffix("…"))
        XCTAssertLessThanOrEqual(hit.before.count, BookSearch.contextLength + 1)
        XCTAssertLessThanOrEqual(hit.after.count, BookSearch.contextLength + 1)
        XCTAssertTrue(hit.snippet.contains("needle"))
    }

    func testAShortPassageIsQuotedWhole() throws {
        let chapters = [BookChapter(title: "One", text: "Call me Ishmael.")]

        let hit = try XCTUnwrap(BookSearch.run("me", in: chapters).first)

        XCTAssertEqual(hit.before, "Call ")
        XCTAssertEqual(hit.after, " Ishmael.")
    }

    func testSearchStopsAtItsLimitSoAVeryCommonWordCannotHangTheReader() {
        let chapters = [BookChapter(title: "One", text: String(repeating: "the ", count: 5_000))]

        XCTAssertEqual(BookSearch.run("the", in: chapters, limit: 25).count, 25)
    }

    func testAnEmptyQueryMatchesNothing() {
        let chapters = [BookChapter(title: "One", text: "Call me Ishmael.")]

        XCTAssertTrue(BookSearch.run("", in: chapters).isEmpty)
        XCTAssertTrue(BookSearch.run("   ", in: chapters).isEmpty)
    }

    // MARK: - Positions

    func testTwoPositionsAreTheSameSpotWhenTheyNameTheSamePageOrParagraph() {
        let page = ReadingLocation(chapterIndex: 1, paragraphIndex: 0, pageIndex: 12)
        // The same page reached from a chapter the reader had scrolled past.
        XCTAssertTrue(page.isAt(ReadingLocation(chapterIndex: 2, pageIndex: 12)))
        XCTAssertFalse(page.isAt(ReadingLocation(chapterIndex: 1, pageIndex: 13)))

        let paragraph = ReadingLocation(chapterIndex: 3, paragraphIndex: 7)
        XCTAssertTrue(paragraph.isAt(ReadingLocation(chapterIndex: 3, paragraphIndex: 7)))
        XCTAssertFalse(paragraph.isAt(ReadingLocation(chapterIndex: 3, paragraphIndex: 8)))
        XCTAssertFalse(paragraph.isAt(ReadingLocation(chapterIndex: 4, paragraphIndex: 7)))
    }

    func testPositionsSortIntoReadingOrder() {
        let positions = [
            ReadingLocation(chapterIndex: 2, paragraphIndex: 1),
            ReadingLocation(chapterIndex: 0, paragraphIndex: 9),
            ReadingLocation(chapterIndex: 2, paragraphIndex: 0),
        ]

        let sorted = positions.sorted { $0.precedes($1) }

        XCTAssertEqual(sorted.map(\.chapterIndex), [0, 2, 2])
        XCTAssertEqual(sorted.map(\.paragraphIndex), [9, 0, 1])
    }

    // MARK: - Helpers

    private func record(chapters: [BookChapter]) -> BookRecord {
        BookRecord(
            title: "Book",
            format: .pdf,
            sourcePath: "/tmp/book.pdf",
            chapters: chapters,
            voiceID: "af_heart",
            speed: 1,
            audioFormat: .mp3
        )
    }
}
