import AppKit
import AttenCore
import Darwin
import Foundation
import PDFKit
import XCTest

/// Builds the large inputs the stress tests run against — a thousand-book
/// shelf, thousand-page books — in a scratch `ATTEN_DATA_DIRECTORY`, so none
/// of it is committed and none of it goes near a real library.
enum StressFixtures {
    /// Whether the slow, large-input tests should run. They build hundreds of
    /// megabytes of fixtures, so they are opt-in.
    static var isEnabled: Bool { ProcessInfo.processInfo.environment["ATTEN_STRESS_TESTS"] == "1" }

    static func skipUnlessEnabled() throws {
        guard isEnabled else { throw XCTSkip("Set ATTEN_STRESS_TESTS=1 to run the large-input stress tests") }
    }

    static func dataDirectory(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttenStress-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - Text

    private static let vocabulary = """
    the a harbour lantern quietly river morning letter garden stone window \
    remembered across between winter carried whisper ancient summer road \
    evening silver field mountain island voice kept walked under over \
    slowly bright shadow paper candle north south distant familiar house
    """.split(separator: " ").map(String.init)

    /// Deterministic prose: `count` words in sentences of about a dozen.
    static func words(_ count: Int, seed: Int) -> String {
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

    // MARK: - A large shelf

    /// A shelf of `count` books, one in `narratedEvery` of them with a short
    /// recording on disk whose chapter timeline matches it, so loading the
    /// shelf has real audio to check.
    static func library(
        count: Int,
        chapters: Int,
        wordsPerChapter: Int,
        narratedEvery: Int,
        in directories: AppDirectories
    ) throws -> [BookRecord] {
        let chapterSeconds = 0.1
        let wav = silentWAV(seconds: chapterSeconds * Double(chapters))
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        return try (0..<count).map { index in
            let id = UUID()
            var book = BookRecord(
                id: id,
                title: "Volume \(index) of the \(vocabulary[index % vocabulary.count]) cycle",
                author: index % 7 == 0 ? nil : "Author \(index % 97)",
                format: [.epub, .pdf, .document, .mobi][index % 4],
                sourcePath: directories.bookSources.appendingPathComponent("\(id.uuidString).txt").path,
                chapters: (0..<chapters).map { chapter in
                    BookChapter(title: "Chapter \(chapter + 1)", text: words(wordsPerChapter, seed: index * 1_000 + chapter))
                },
                voiceID: "af_heart",
                speed: 1,
                audioFormat: .wav,
                addedAt: base.addingTimeInterval(Double(index) * 60),
                contentHash: index % 3 == 0 ? nil : String(format: "%064x", index)
            )
            if index % narratedEvery == 0 {
                let folder = directories.narrations
                    .appendingPathComponent(id.uuidString, isDirectory: true)
                    .appendingPathComponent("Audiobook-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let audio = folder.appendingPathComponent("Audiobook.caf")
                try wav.write(to: audio)
                book.audioPath = audio.path
                book.narrationState = .ready
                for chapter in book.chapters.indices {
                    book.chapters[chapter].audioPath = audio.path
                    book.chapters[chapter].startTime = Double(chapter) * chapterSeconds
                    book.chapters[chapter].endTime = Double(chapter + 1) * chapterSeconds
                }
                if index % (narratedEvery * 2) == 0 {
                    book.listeningPosition = 0.5
                    book.lastListenedAt = base.addingTimeInterval(Double(index))
                }
            }
            return book
        }
    }

    /// Sixteen-bit mono silence at 24 kHz.
    static func silentWAV(seconds: Double) -> Data {
        wav(seconds: seconds) { 0 }
    }

    /// Quiet noise, which an encoder cannot squeeze to nearly nothing the way
    /// it can silence.
    static func noiseWAV(seconds: Double) -> Data {
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

    // MARK: - Long books

    /// An EPUB of `pages` pages of about 300 words, split across `files` spine
    /// documents full of the entities real books use. One file makes the
    /// whole book a single document; `wellFormed: false` sends every file
    /// down the tag-stripping fallback.
    static func epub(pages: Int, files: Int, wellFormed: Bool = true, in directory: URL) throws -> URL {
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
    static func pdf(pages: Int, pagesPerChapter: Int?, in directory: URL) throws -> URL {
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

    // MARK: - Measuring

    /// Wall-clock seconds `body` took, and what it returned.
    static func time<T>(_ body: () throws -> T) rethrows -> (T, Double) {
        let start = ContinuousClock.now
        let value = try body()
        let elapsed = ContinuousClock.now - start
        return (value, Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18)
    }

    static func time<T>(
        isolation: isolated (any Actor)? = #isolation,
        _ body: () async throws -> T
    ) async rethrows -> (T, Double) {
        let start = ContinuousClock.now
        let value = try await body()
        let elapsed = ContinuousClock.now - start
        return (value, Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18)
    }

    /// The process's physical footprint in megabytes — what Activity Monitor
    /// calls its memory.
    static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }


    /// One line of the table the stress tests print, prefixed so it can be
    /// grepped out of `swift test` output.
    static func report(_ label: String, _ seconds: Double, _ detail: String = "") {
        let padded = label.padding(toLength: 52, withPad: " ", startingAt: 0)
        print("STRESS | \(padded) | " + String(format: "%9.1f ms", seconds * 1_000) + " | \(detail)")
    }
}

/// Samples the footprint every few milliseconds on its own thread, so the
/// high-water mark of one operation can be read without the process-lifetime
/// peak that `getrusage` reports.
final class FootprintSampler: @unchecked Sendable {
    private let lock = NSLock()
    private var peak = StressFixtures.footprintMB()
    private var running = true

    init() {
        Thread.detachNewThread { [self] in
            while lock.withLock({ running }) {
                let now = StressFixtures.footprintMB()
                lock.withLock { peak = max(peak, now) }
                usleep(5_000)
            }
        }
    }

    /// Stops sampling and answers the highest footprint seen, in megabytes.
    func stop() -> Double {
        lock.withLock {
            running = false
            return max(peak, StressFixtures.footprintMB())
        }
    }
}
