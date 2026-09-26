import AppKit
import AttenCore
import Foundation
import XCTest

final class DocumentImportTests: XCTestCase {
    private var workspace: URL!

    override func setUpWithError() throws {
        workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttenImportTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: workspace)
    }

    // MARK: - Normalization

    func testNormalizeRejoinsWrappedAndHyphenatedLines() {
        let raw = "The whale was pre-\nsently gone,\nleaving nothing.\n\nA new paragraph."
        XCTAssertEqual(
            DocumentText.normalize(raw),
            "The whale was presently gone, leaving nothing.\n\nA new paragraph."
        )
    }

    func testNormalizeCollapsesRunsOfBlankLinesAndNonBreakingSpaces() {
        XCTAssertEqual(
            DocumentText.normalize("One\u{00A0}two\n\n\n\nThree   four  "),
            "One two\n\nThree four"
        )
    }

    // MARK: - PDF

    func testPDFWithoutAnOutlineIsSlicedIntoReadableChapters() throws {
        let url = try makePDF(pages: (1...23).map { "Page \($0) of the survey report." })

        let document = try DocumentImporter.extract(from: url)

        // 23 pages at ten per slice.
        XCTAssertEqual(document.chapters.count, 3)
        XCTAssertEqual(document.chapters.map(\.pageIndex), [0, 10, 20])
        XCTAssertTrue(document.chapters[0].text.contains("Page 1 of the survey report."))
        XCTAssertTrue(document.chapters[2].text.contains("Page 23 of the survey report."))
        XCTAssertEqual(document.chapters[2].title, "Pages 21–23")
    }

    func testPDFChapterTextCarriesEveryPageInItsRange() throws {
        let url = try makePDF(pages: ["Alpha page.", "Beta page.", "Gamma page."])

        let chapters = try DocumentImporter.extract(from: url).chapters

        XCTAssertEqual(chapters.count, 1)
        for word in ["Alpha", "Beta", "Gamma"] {
            XCTAssertTrue(chapters[0].text.contains(word), "missing \(word)")
        }
    }

    func testAPDFWithNoTextIsRejectedRatherThanImportedEmpty() throws {
        let url = try makePDF(pages: ["", "", ""])

        XCTAssertThrowsError(try DocumentImporter.extract(from: url)) { error in
            XCTAssertEqual(error as? DocumentImportError, .noText(url.lastPathComponent))
        }
    }

    // MARK: - EPUB

    func testEPUBIsReadInSpineOrderWithHeadingsAsChapterTitles() throws {
        let url = try makeEPUB()

        let document = try DocumentImporter.extract(from: url)

        XCTAssertEqual(document.title, "A Short Voyage")
        XCTAssertEqual(document.author, "Ada Mariner")
        XCTAssertEqual(document.chapters.map(\.title), ["Loomings", "The Carpet-Bag"])
        XCTAssertNil(document.chapters[0].pageIndex)
    }

    func testEPUBTextDropsMarkupAndResolvesHTMLEntities() throws {
        let text = try DocumentImporter.extract(from: makeEPUB()).chapters[0].text

        XCTAssertTrue(text.contains("Call me Ishmael."), text)
        // &mdash;, &hellip;, a hyphen split across a line, and a wrapped line.
        XCTAssertTrue(text.contains("Some years ago—never mind how long precisely…"), text)
        XCTAssertTrue(text.contains("Second paragraph."), text)
        XCTAssertFalse(text.contains("color:red"), "stylesheet text leaked into the chapter")
        XCTAssertFalse(text.contains("<"), "markup leaked into the chapter")
    }

    func testEPUBSurvivesMarkupThatIsNotWellFormedXML() throws {
        let url = try makeEPUB(chapterOne: """
        <html><body><h1>Broken</h1><p>Unclosed <b>bold and a bare & ampersand.<p></body></html>
        """)

        let chapters = try DocumentImporter.extract(from: url).chapters

        XCTAssertTrue(chapters[0].text.contains("bold and a bare & ampersand."), chapters[0].text)
    }

    /// A text file used to be refused here. It is now a document Atten reads,
    /// so the thing being tested is a format it really has no reader for.
    func testAFileAttenHasNoReaderForIsRefusedByExtension() throws {
        let url = workspace.appendingPathComponent("slides.key")
        try "hello".write(to: url, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try DocumentImporter.extract(from: url)) { error in
            XCTAssertEqual(error as? DocumentImportError, .unsupportedFormat("key"))
        }
    }

    func testImportErrorsAreOneShortLine() {
        XCTAssertEqual(DocumentImportError.unsupportedFormat("key").localizedDescription,
                       "Atten can’t open .key files.")
        XCTAssertEqual(DocumentImportError.unreadable("Notes.pdf").localizedDescription,
                       "Notes.pdf couldn’t be opened. It may be damaged or password-protected.")
        XCTAssertEqual(DocumentImportError.noText("Scan.pdf").localizedDescription,
                       "Scan.pdf has no readable text. Scanned pages need OCR first.")
    }

    func testADamagedEPUBReportsItselfRatherThanCrashing() throws {
        let url = workspace.appendingPathComponent("torn.epub")
        try Data("not a zip at all".utf8).write(to: url)

        XCTAssertThrowsError(try DocumentImporter.extract(from: url)) { error in
            XCTAssertEqual(error as? DocumentImportError, .unreadable("torn.epub"))
        }
    }

    // MARK: - Fixtures

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

    private func makeEPUB(chapterOne: String? = nil) throws -> URL {
        let root = workspace.appendingPathComponent("epub-\(UUID().uuidString)", isDirectory: true)
        let oebps = root.appendingPathComponent("OEBPS", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("META-INF"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: oebps, withIntermediateDirectories: true)

        try write("application/epub+zip", to: root.appendingPathComponent("mimetype"))
        try write(
            """
            <?xml version="1.0"?>
            <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
              <rootfiles>
                <rootfile full-path="OEBPS/book.opf" media-type="application/oebps-package+xml"/>
              </rootfiles>
            </container>
            """,
            to: root.appendingPathComponent("META-INF/container.xml")
        )
        try write(
            """
            <?xml version="1.0"?>
            <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">
              <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
                <dc:title>A Short Voyage</dc:title>
                <dc:creator>Ada Mariner</dc:creator>
              </metadata>
              <manifest>
                <item id="c1" href="ch1.xhtml" media-type="application/xhtml+xml"/>
                <item id="c2" href="ch2.xhtml" media-type="application/xhtml+xml"/>
                <item id="css" href="style.css" media-type="text/css"/>
              </manifest>
              <spine><itemref idref="c1"/><itemref idref="c2"/></spine>
            </package>
            """,
            to: oebps.appendingPathComponent("book.opf")
        )
        try write("p { color:red }", to: oebps.appendingPathComponent("style.css"))
        try write(
            chapterOne ?? """
            <?xml version="1.0" encoding="utf-8"?>
            <html xmlns="http://www.w3.org/1999/xhtml">
            <head><title>Ignored</title><style>p{color:red}</style></head>
            <body><h1>Loomings</h1><p>Call me&nbsp;Ishmael. Some years
            ago&mdash;never mind how long pre-
            cisely&hellip;</p><p>Second paragraph.</p></body></html>
            """,
            to: oebps.appendingPathComponent("ch1.xhtml")
        )
        try write(
            """
            <?xml version="1.0" encoding="utf-8"?>
            <html xmlns="http://www.w3.org/1999/xhtml"><body>
            <h2>The Carpet-Bag</h2><p>I stuffed a shirt or two.</p></body></html>
            """,
            to: oebps.appendingPathComponent("ch2.xhtml")
        )

        let url = workspace.appendingPathComponent("voyage-\(UUID().uuidString).epub")
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        zip.arguments = ["-c", "-k", "--norsrc", root.path, url.path]
        try zip.run()
        zip.waitUntilExit()
        XCTAssertEqual(zip.terminationStatus, 0, "could not build the EPUB fixture")
        return url
    }

    private func write(_ contents: String, to url: URL) throws {
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }
}
