import AppKit
import AttenCore
import AttenFixtureKit
import Foundation
import XCTest
@testable import Atten

/// A book's cover is art it actually carries. A PDF's first page counts only
/// when it is a picture of a jacket; a page of text gets a generated cover.
@MainActor
final class BookCoverChoiceTests: XCTestCase {
    private var workspace: URL!

    override func setUpWithError() throws {
        workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttenCoverChoiceTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: workspace)
    }

    func testATextOnlyPDFHasNoCover() throws {
        let url = try FixtureBuilders.pdf(pages: 3, pagesPerChapter: nil, in: workspace)

        XCTAssertNil(BookCoverStore.extract(from: url, format: .pdf))
    }

    func testAScannedJacketIsTheCover() throws {
        let url = try makePDF(imageRect: CGRect(x: 0, y: 0, width: 612, height: 792))

        let data = try XCTUnwrap(BookCoverStore.extract(from: url, format: .pdf))
        XCTAssertNotNil(NSImage(data: data))
    }

    /// A title page with a publisher's logo on it is still a page, not a cover.
    func testASmallPictureOnAPageIsNotACover() throws {
        let url = try makePDF(imageRect: CGRect(x: 256, y: 600, width: 100, height: 100), text: "A Short Voyage")

        XCTAssertNil(BookCoverStore.extract(from: url, format: .pdf))
    }

    /// A scanned page of reading, with the text layer OCR leaves behind it.
    func testAScannedPageOfTextIsNotACover() throws {
        let url = try makePDF(
            imageRect: CGRect(x: 0, y: 0, width: 612, height: 792),
            text: String(repeating: "The tide was out and the harbour was quiet. ", count: 30)
        )

        XCTAssertNil(BookCoverStore.extract(from: url, format: .pdf))
    }

    /// Covers cached before this rule, when any first page counted, are
    /// thrown away rather than shown.
    func testAPageRenderCachedEarlierIsDiscarded() async throws {
        let source = try FixtureBuilders.pdf(pages: 2, pagesPerChapter: nil, in: workspace)
        let book = BookRecord(
            title: "Long Report", format: .pdf, sourcePath: source.path,
            chapters: [BookChapter(title: "One", text: "Words.")],
            voiceID: "af_heart", speed: 1, audioFormat: .wav
        )
        let covers = workspace.appendingPathComponent("Covers", isDirectory: true)
        try FileManager.default.createDirectory(at: covers, withIntermediateDirectories: true)
        let stale = covers.appendingPathComponent("\(book.id.uuidString).png")
        try Self.png.write(to: stale)

        let store = BookCoverStore(directory: covers)
        await store.load(book)

        XCTAssertNil(store.cover(for: book.id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path))
    }

    // MARK: - Fixture

    /// A one-page PDF with a flat-coloured image over `imageRect`, and `text`
    /// set in the top margin when given.
    private func makePDF(imageRect: CGRect, text: String? = nil) throws -> URL {
        let url = workspace.appendingPathComponent("\(UUID().uuidString).pdf")
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let context = try XCTUnwrap(CGContext(url as CFURL, mediaBox: &mediaBox, nil))
        let image = try XCTUnwrap(NSBitmapImageRep(data: Self.png)?.cgImage)
        context.beginPDFPage(nil)
        context.draw(image, in: imageRect)
        if let text {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 10)])
                .draw(in: CGRect(x: 54, y: 54, width: 504, height: 540))
            NSGraphicsContext.restoreGraphicsState()
        }
        context.endPDFPage()
        context.closePDF()
        return url
    }

    /// An 8×8 block of one colour.
    private static let png: Data = {
        let image = NSImage(size: NSSize(width: 8, height: 8), flipped: false) { rect in
            NSColor.systemTeal.setFill()
            rect.fill()
            return true
        }
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        return bitmap.representation(using: .png, properties: [:])!
    }()
}
