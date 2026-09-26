import AppKit
import Foundation
import PDFKit

/// Deterministic text, audio and document builders shared by the #90 stress
/// fixtures (`StressFixtures`, test-only) and the `AttenFixtures` QA tool.
/// Kept free of XCTest so an executable target can link it too.
public enum FixtureBuilders {
    public static let vocabulary = """
    the a harbour lantern quietly river morning letter garden stone window \
    remembered across between winter carried whisper ancient summer road \
    evening silver field mountain island voice kept walked under over \
    slowly bright shadow paper candle north south distant familiar house
    """.split(separator: " ").map(String.init)

    // MARK: - Text

    /// Deterministic prose: `count` words in sentences of about a dozen.
    public static func words(_ count: Int, seed: Int) -> String {
        var generator = seed &* 2_654_435_761 &+ 1
        var text = ""
        text.reserveCapacity(count * 8)
        for index in 0..<count {
            generator = generator &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let word = vocabulary[Int(UInt(bitPattern: generator >> 33) % UInt(vocabulary.count))]
            if index % 12 == 0 {
                if index > 0 { text += ". " }
                text += word.prefix(1).uppercased() + word.dropFirst()
            } else {
                text += " " + word
            }
        }
        return text + "."
    }

    // MARK: - Audio

    /// Sixteen-bit mono silence at 24 kHz.
    public static func silentWAV(seconds: Double) -> Data {
        wav(seconds: seconds) { 0 }
    }

    /// Quiet noise, which an encoder cannot squeeze to nearly nothing the way
    /// it can silence.
    public static func noiseWAV(seconds: Double) -> Data {
        var state: UInt32 = 1
        return wav(seconds: seconds) {
            state = state &* 1_664_525 &+ 1_013_904_223
            return Int16(truncatingIfNeeded: state >> 16) / 8
        }
    }

    private static func wav(seconds: Double, sample: () -> Int16) -> Data {
        let sampleCount = UInt32(seconds * 24_000)
        let dataSize = sampleCount * 2
        var data = Data()
        data.reserveCapacity(Int(dataSize) + 44)
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: "RIFF".utf8)
        append(36 + dataSize)
        data.append(contentsOf: "WAVEfmt ".utf8)
        append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(UInt32(24_000)); append(UInt32(48_000)); append(UInt16(2)); append(UInt16(16))
        data.append(contentsOf: "data".utf8)
        append(dataSize)
        for _ in 0..<sampleCount { append(sample()) }
        return data
    }

    // MARK: - Long documents

    /// An EPUB of `pages` pages of about 300 words, split across `files` spine
    /// documents full of the entities real books use. One file makes the
    /// whole book a single document; `wellFormed: false` sends every file
    /// down the tag-stripping fallback.
    public static func epub(pages: Int, files: Int, wellFormed: Bool = true, in directory: URL) throws -> URL {
        let root = directory.appendingPathComponent("epub-\(UUID().uuidString)", isDirectory: true)
        let oebps = root.appendingPathComponent("OEBPS", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("META-INF"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: oebps, withIntermediateDirectories: true)
        try "application/epub+zip".write(to: root.appendingPathComponent("mimetype"), atomically: true, encoding: .utf8)
        try """
        <?xml version="1.0"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles><rootfile full-path="OEBPS/book.opf" media-type="application/oebps-package+xml"/></rootfiles>
        </container>
        """.write(to: root.appendingPathComponent("META-INF/container.xml"), atomically: true, encoding: .utf8)

        let pagesPerFile = max(1, pages / files)
        var manifest = ""
        var spine = ""
        for file in 0..<files {
            var body = "<h1>Chapter \(file + 1)</h1>\n"
            for page in 0..<pagesPerFile {
                // Three paragraphs a page, with the entities and inline markup
                // a typeset book is full of.
                for paragraph in 0..<3 {
                    let text = words(100, seed: file * 10_000 + page * 10 + paragraph)
                        .replacingOccurrences(of: " the ", with: "&nbsp;the&nbsp;")
                        .replacingOccurrences(of: ". ", with: "&mdash;<em>so</em>. ")
                    body += "<p>\(text)&hellip;</p>\n"
                }
            }
            let document = """
            <?xml version="1.0" encoding="utf-8"?>
            <html xmlns="http://www.w3.org/1999/xhtml"><head><title>c\(file)</title></head>
            <body>\(body)\(wellFormed ? "" : "<p>unclosed <b>markup")</body></html>
            """
            try document.write(to: oebps.appendingPathComponent("c\(file).xhtml"), atomically: true, encoding: .utf8)
            manifest += #"<item id="c\#(file)" href="c\#(file).xhtml" media-type="application/xhtml+xml"/>"#
            spine += #"<itemref idref="c\#(file)"/>"#
        }
        try """
        <?xml version="1.0"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>A Long Book</dc:title><dc:creator>Stress</dc:creator></metadata>
          <manifest>\(manifest)</manifest>
          <spine>\(spine)</spine>
        </package>
        """.write(to: oebps.appendingPathComponent("book.opf"), atomically: true, encoding: .utf8)

        let url = directory.appendingPathComponent("long-\(UUID().uuidString).epub")
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        zip.arguments = ["-c", "-k", "--norsrc", root.path, url.path]
        try zip.run()
        zip.waitUntilExit()
        try? FileManager.default.removeItem(at: root)
        guard zip.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown) }
        return url
    }

    /// A PDF of `pages` pages of about 300 words, with a top-level outline
    /// entry every `pagesPerChapter` pages when that is given.
    public static func pdf(pages: Int, pagesPerChapter: Int?, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent("long-\(UUID().uuidString).pdf")
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else { throw CocoaError(.fileWriteUnknown) }
        let font = NSFont.systemFont(ofSize: 10)
        for page in 0..<pages {
            context.beginPDFPage(nil)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            NSAttributedString(string: words(300, seed: page), attributes: [.font: font])
                .draw(in: CGRect(x: 54, y: 54, width: 504, height: 684))
            NSGraphicsContext.restoreGraphicsState()
            context.endPDFPage()
        }
        context.closePDF()

        guard let pagesPerChapter, let document = PDFDocument(url: url) else { return url }
        let root = PDFOutline()
        for (position, start) in stride(from: 0, to: pages, by: pagesPerChapter).enumerated() {
            guard let page = document.page(at: start) else { continue }
            let entry = PDFOutline()
            entry.label = "Chapter \(position + 1)"
            entry.destination = PDFDestination(page: page, at: CGPoint(x: 0, y: 792))
            root.insertChild(entry, at: root.numberOfChildren)
        }
        document.outlineRoot = root
        guard document.write(to: url) else { throw CocoaError(.fileWriteUnknown) }
        return url
    }
}
