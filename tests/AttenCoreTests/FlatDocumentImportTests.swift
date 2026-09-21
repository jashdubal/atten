import Foundation
import XCTest
@testable import AttenCore

/// The reader was built for books, and the ask was that a report work in it
/// too. These are the shapes a report actually arrives in.
final class FlatDocumentImportTests: XCTestCase {
    private var directory = URL(fileURLWithPath: NSTemporaryDirectory())

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func write(_ text: String, as name: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testEveryOfferedExtensionIsRecognised() {
        for expected in [BookFormat.pdf, .epub, .document] {
            for pathExtension in expected.extensions {
                XCTAssertEqual(BookFormat.forExtension(pathExtension), expected)
                XCTAssertEqual(BookFormat.forExtension(pathExtension.uppercased()), expected)
            }
        }
        XCTAssertNil(BookFormat.forExtension("key"))
    }

    /// Whatever the shelf will accept, the importer has to be able to open.
    func testTheShelfAcceptsNothingTheImporterCannotOpen() {
        XCTAssertEqual(
            Set(DocumentImporter.supportedExtensions),
            Set(BookFormat.supportedExtensions)
        )
        XCTAssertTrue(DocumentImporter.supportedExtensions.allSatisfy {
            BookFormat.forExtension($0) != nil
        })
    }

    /// A PDF is already typeset; everything else Atten sets itself.
    func testOnlyAPDFKeepsItsOwnTypesetting() {
        XCTAssertFalse(BookFormat.pdf.isTypeset)
        XCTAssertTrue(BookFormat.epub.isTypeset)
        XCTAssertTrue(BookFormat.document.isTypeset)
    }

    func testAReportIsDividedByItsHeadings() throws {
        let url = try write("""
        # Quarterly Report

        ## Summary

        Revenue grew by eleven per cent.

        ## Risks

        Two suppliers remain single-sourced.

        ## Outlook

        We expect the trend to hold.
        """, as: "report.md")

        let document = try DocumentImporter.extract(from: url)

        XCTAssertEqual(document.title, "Quarterly Report")
        XCTAssertEqual(document.chapters.map(\.title), ["Summary", "Risks", "Outlook"])
        XCTAssertEqual(document.chapters[0].text, "Revenue grew by eleven per cent.")
    }

    /// A single heading at the top of a file is its title, not a division of
    /// it. Treating it as one would open the reader on a document of one
    /// chapter called the same thing as the document.
    func testASingleHeadingIsATitleRatherThanASection() throws {
        let url = try write("""
        # Notes on the Migration

        The move happened over a weekend.

        Nothing was lost.
        """, as: "notes.md")

        let document = try DocumentImporter.extract(from: url)

        XCTAssertEqual(document.title, "Notes on the Migration")
        XCTAssertEqual(document.chapters.count, 1)
        XCTAssertFalse(document.chapters[0].title == "Notes on the Migration")
        XCTAssertTrue(document.chapters[0].text.contains("over a weekend"))
    }

    /// A file with no headings still has to be readable, and a name — the file
    /// is the only name anyone has given it.
    func testAPlainFileIsNamedAfterItselfAndStillOpens() throws {
        let url = try write(
            "The meeting ran long.\n\nWe agreed to revisit it.",
            as: "standup.txt"
        )

        let document = try DocumentImporter.extract(from: url)

        XCTAssertEqual(document.title, "standup")
        XCTAssertEqual(document.chapters.count, 1)
        XCTAssertTrue(document.chapters[0].text.contains("revisit"))
    }

    /// Nothing in a document may be dropped on the way in: it is going to be
    /// read aloud, and a missing paragraph is a paragraph nobody hears.
    func testALongFileWithNoHeadingsKeepsEveryParagraph() throws {
        let paragraphs = (1...60).map { index in
            "Paragraph \(index). " + String(repeating: "word ", count: 40)
        }
        let url = try write(paragraphs.joined(separator: "\n\n"), as: "long.txt")

        let document = try DocumentImporter.extract(from: url)

        XCTAssertGreaterThan(document.chapters.count, 1, "a long file was not divided at all")
        let readBack = document.chapters.map(\.text).joined(separator: "\n")
        for index in 1...60 {
            XCTAssertTrue(
                readBack.contains("Paragraph \(index)."),
                "paragraph \(index) was lost on the way in"
            )
        }
    }

    /// Markdown's marks are not words, so they must not be read aloud — but
    /// the words inside them must survive.
    func testMarkdownMarksAreNotReadAloud() throws {
        let url = try write("""
        # Doc

        ## One

        This is **important** and *urgent*, see [the plan](https://example.com/plan).

        - first point
        - second point

        ```
        let x = 1
        ```

        ## Two

        Done.
        """, as: "marks.md")

        let document = try DocumentImporter.extract(from: url)
        let text = document.chapters[0].text

        XCTAssertTrue(text.contains("important"))
        XCTAssertTrue(text.contains("urgent"))
        XCTAssertTrue(text.contains("the plan"))
        XCTAssertFalse(text.contains("**"))
        XCTAssertFalse(text.contains("https://"))
        XCTAssertFalse(text.contains("let x = 1"), "a code block is not prose")
        XCTAssertTrue(text.contains("• first point"))
    }

    func testAnRTFReportOpens() throws {
        let rtf = try NSAttributedString(string: "Revenue grew.\n\nCosts fell.")
            .data(
                from: NSRange(location: 0, length: 26),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
            )
        let url = directory.appendingPathComponent("report.rtf")
        try rtf.write(to: url)

        let document = try DocumentImporter.extract(from: url)

        XCTAssertEqual(document.title, "report")
        XCTAssertTrue(document.chapters[0].text.contains("Revenue grew."))
    }

    func testAFileAttenCannotReadSaysSoByName() throws {
        let url = try write("slides", as: "deck.key")

        XCTAssertThrowsError(try DocumentImporter.extract(from: url)) { error in
            XCTAssertEqual(error as? DocumentImportError, .unsupportedFormat("key"))
        }
    }

    func testAnEmptyDocumentIsRefusedRatherThanOpenedBlank() throws {
        let url = try write("   \n\n  ", as: "empty.txt")

        XCTAssertThrowsError(try DocumentImporter.extract(from: url)) { error in
            XCTAssertEqual(error as? DocumentImportError, .noText("empty"))
        }
    }
}
