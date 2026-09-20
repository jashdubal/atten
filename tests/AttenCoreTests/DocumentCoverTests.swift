import AttenCore
import Foundation
import XCTest

/// EPUBs name their cover in three different ways depending on how old they
/// are, and books in the wild use all three.
final class DocumentCoverTests: XCTestCase {
    private var workspace: URL!

    override func setUpWithError() throws {
        workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttenCoverTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: workspace)
    }

    func testFindsACoverMarkedTheEPUB3Way() throws {
        let url = try makeEPUB(
            manifest: """
            <item id="cover" href="jacket.png" media-type="image/png" properties="cover-image"/>
            """
        )

        XCTAssertEqual(EPUBTextExtractor.coverImageData(from: url), Self.artwork)
    }

    func testFindsACoverMarkedTheEPUB2Way() throws {
        let url = try makeEPUB(
            metadata: #"<meta name="cover" content="jacketImage"/>"#,
            manifest: #"<item id="jacketImage" href="jacket.png" media-type="image/png"/>"#
        )

        XCTAssertEqual(EPUBTextExtractor.coverImageData(from: url), Self.artwork)
    }

    /// Some books only say so in the file name.
    func testFallsBackOnAnImageThatCallsItselfACover() throws {
        let url = try makeEPUB(
            manifest: #"<item id="img1" href="cover.png" media-type="image/png"/>"#,
            imageName: "cover.png"
        )

        XCTAssertEqual(EPUBTextExtractor.coverImageData(from: url), Self.artwork)
    }

    /// A book with no cover gets no cover, rather than the first picture in it.
    func testABookWithNoCoverHasNone() throws {
        let url = try makeEPUB(
            manifest: #"<item id="fig1" href="diagram.png" media-type="image/png"/>"#,
            imageName: "diagram.png"
        )

        XCTAssertNil(EPUBTextExtractor.coverImageData(from: url))
    }

    func testAnUnreadableFileHasNoCoverAndDoesNotThrow() throws {
        let url = workspace.appendingPathComponent("torn.epub")
        try Data("not a zip".utf8).write(to: url)

        XCTAssertNil(EPUBTextExtractor.coverImageData(from: url))
    }

    /// A manifest can name any path it likes, and this is a read of a file
    /// nobody chose to open.
    func testACoverCannotBeReadFromOutsideTheBook() throws {
        let secret = workspace.appendingPathComponent("secret.png")
        try Data("not yours".utf8).write(to: secret)
        let url = try makeEPUB(
            manifest: #"<item id="c" href="../../../secret.png" media-type="image/png" properties="cover-image"/>"#
        )

        XCTAssertNil(EPUBTextExtractor.coverImageData(from: url))
    }

    // MARK: - Fixture

    /// A one-pixel PNG. The bytes only have to come back unchanged.
    private static let artwork = Data(base64Encoded: """
    iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==
    """)!

    private func makeEPUB(
        metadata: String = "",
        manifest: String,
        imageName: String = "jacket.png"
    ) throws -> URL {
        let root = workspace.appendingPathComponent("epub-\(UUID().uuidString)", isDirectory: true)
        let oebps = root.appendingPathComponent("OEBPS", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("META-INF"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: oebps, withIntermediateDirectories: true)

        try Data("application/epub+zip".utf8)
            .write(to: root.appendingPathComponent("mimetype"))
        try Data("""
        <?xml version="1.0"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles>
            <rootfile full-path="OEBPS/book.opf" media-type="application/oebps-package+xml"/>
          </rootfiles>
        </container>
        """.utf8).write(to: root.appendingPathComponent("META-INF/container.xml"))

        try Data("""
        <?xml version="1.0"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:title>A Short Voyage</dc:title>
            \(metadata)
          </metadata>
          <manifest>
            <item id="c1" href="ch1.xhtml" media-type="application/xhtml+xml"/>
            \(manifest)
          </manifest>
          <spine><itemref idref="c1"/></spine>
        </package>
        """.utf8).write(to: oebps.appendingPathComponent("book.opf"))

        try Data("""
        <?xml version="1.0" encoding="utf-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml"><body><p>Words.</p></body></html>
        """.utf8).write(to: oebps.appendingPathComponent("ch1.xhtml"))
        try Self.artwork.write(to: oebps.appendingPathComponent(imageName))

        let url = workspace.appendingPathComponent("\(UUID().uuidString).epub")
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        zip.arguments = ["-c", "-k", "--norsrc", root.path, url.path]
        try zip.run()
        zip.waitUntilExit()
        XCTAssertEqual(zip.terminationStatus, 0, "could not build the EPUB fixture")
        return url
    }
}
