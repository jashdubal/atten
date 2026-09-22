@testable import AttenCore
import Foundation
import XCTest

/// Reading Kindle books. The fixtures here are built byte by byte rather than
/// checked in, because a Kindle book is a binary container and a test that
/// cannot say what is in every field of it is not saying much.
final class MOBIImportTests: XCTestCase {
    private var workspace: URL!

    override func setUpWithError() throws {
        workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttenMOBITests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: workspace)
    }

    // MARK: - Telling the formats apart

    /// The reason any of this exists: Kindle books are handed around named
    /// `.epub`, and the extension is the one thing about them that is wrong.
    func testAKindleBookNamedEPUBIsStillReadAsAKindleBook() throws {
        let url = try write(makeMOBI(parts: ["<p>Chapter one.</p>"]), named: "book.epub")
        XCTAssertEqual(BookFormat.resolve(for: url), .mobi)

        let document = try DocumentImporter.extract(from: url)
        XCTAssertEqual(document.chapters.map(\.text), ["Chapter one."])
    }

    func testAnEPUBNamedAsAKindleBookIsStillReadAsAnEPUB() throws {
        let zip = Data([0x50, 0x4B, 0x03, 0x04]) + Data(repeating: 0, count: 64)
        let url = try write(zip, named: "book.azw3")
        XCTAssertEqual(BookFormat.resolve(for: url), .epub)
    }

    /// A Word document is a zip too, and it is a document whatever its bytes
    /// begin with. Only the two book containers are sniffed.
    func testAWordDocumentIsNotMistakenForABook() throws {
        let zip = Data([0x50, 0x4B, 0x03, 0x04]) + Data(repeating: 0, count: 64)
        let url = try write(zip, named: "report.docx")
        XCTAssertEqual(BookFormat.resolve(for: url), .document)
    }

    func testAFileThatIsNeitherKeepsItsExtension() throws {
        let url = try write(Data(repeating: 0x20, count: 200), named: "notes.txt")
        XCTAssertEqual(BookFormat.resolve(for: url), .document)
    }

    // MARK: - The book itself

    func testTitleAuthorAndChaptersComeOffTheHeaders() throws {
        let data = makeMOBI(
            parts: ["<p>The first part.</p>", "<p>The second part.</p>"],
            title: "A Kindle Book",
            author: "Someone Else"
        )
        let document = try DocumentImporter.extract(from: try write(data, named: "book.mobi"))

        XCTAssertEqual(document.title, "A Kindle Book")
        XCTAssertEqual(document.author, "Someone Else")
        XCTAssertEqual(document.chapters.map(\.text), ["The first part.", "The second part."])
    }

    /// KF8 stamps the whole book's `<head>` onto every part. Read out loud that
    /// is the title recited before each chapter.
    func testTheRepeatedHeadIsNotReadOutLoud() throws {
        let data = makeMOBI(parts: ["<p>Just the body.</p>"], title: "A Kindle Book")
        let document = try DocumentImporter.extract(from: try write(data, named: "book.mobi"))

        XCTAssertEqual(document.chapters.map(\.text), ["Just the body."])
    }

    /// A heading names the chapter, exactly as it does in an EPUB.
    func testAChapterIsNamedAfterItsHeading() throws {
        let data = makeMOBI(parts: [
            "<h1>Landfall</h1><p>They arrived at dawn.</p>",
            "<p>No heading here.</p>",
        ])
        let document = try DocumentImporter.extract(from: try write(data, named: "book.mobi"))

        XCTAssertEqual(document.chapters.map(\.title), ["Landfall", "Chapter 2"])
    }

    /// The chapter openings of a typeset book are often a styled paragraph
    /// rather than a heading element, and then the ordinal Atten falls back on
    /// contradicts the number the book prints on the page.
    func testAChapterIsNamedAfterItsOpeningLinesWhenThereIsNoHeading() throws {
        let data = makeMOBI(parts: [
            "<p><strong>CHAPTER 1</strong></p><p>Mindset Changes</p><p>The body.</p>",
            "<p>PRAISE FOR THE BOOK</p><p>Someone liked it.</p>",
        ])
        let document = try DocumentImporter.extract(from: try write(data, named: "book.mobi"))

        XCTAssertEqual(
            document.chapters.map(\.title),
            ["CHAPTER 1: Mindset Changes", "PRAISE FOR THE BOOK"]
        )
    }

    /// A part that opens on prose has no title to take, and the ordinal is
    /// still the honest answer.
    func testAPartThatOpensOnASentenceKeepsItsOrdinal() throws {
        let data = makeMOBI(parts: [
            "<p>Founding Sales is dedicated to my brother, Michael T. Kazanjy,</p>"
                + "<p>and my son.</p>",
        ])
        let document = try DocumentImporter.extract(from: try write(data, named: "book.mobi"))

        XCTAssertEqual(document.chapters.map(\.title), ["Chapter 1"])
    }

    /// A publisher who put a part divider and the chapter after it in one file
    /// would otherwise leave that chapter with no entry of its own.
    func testAPartHoldingADividerAndAChapterBecomesTwo() throws {
        let data = makeMOBI(parts: [
            "<p>PART II</p><p>Scaling Mode</p>"
                + "<p>CHAPTER 10</p><p>Early Sales Management</p><p>The body.</p>",
        ])
        let document = try DocumentImporter.extract(from: try write(data, named: "book.mobi"))

        XCTAssertEqual(
            document.chapters.map(\.title),
            ["PART II: Scaling Mode", "CHAPTER 10: Early Sales Management"]
        )
    }

    /// A book refers to its own chapters in passing, and a reference is written
    /// in ordinary capitals where an opening is not. Cutting on one would split
    /// a chapter down the middle of a sentence.
    func testACrossReferenceIsNotMistakenForAChapterOpening() throws {
        let data = makeMOBI(parts: [
            "<p>CHAPTER 8</p><p>Down Funnel Selling</p>"
                + "<p>As covered in <a href=\"x\">Chapter 1</a>, this matters.</p>",
        ])
        let document = try DocumentImporter.extract(from: try write(data, named: "book.mobi"))

        XCTAssertEqual(document.chapters.count, 1)
        XCTAssertEqual(document.chapters[0].title, "CHAPTER 8: Down Funnel Selling")
    }

    /// The parts of a Kindle book are not well-formed on their own, so this
    /// text is stripped of its tags rather than parsed. A link or an emphasis
    /// sits inside a sentence, and a line break in its place is a pause read
    /// out in the middle of a thought.
    func testInlineMarkupDoesNotBreakAParagraph() throws {
        let data = makeMOBI(parts: [
            "<p>Scaling up to a larger <em>market</em> <a href=\"x\">development</a> apparatus.</p>",
        ])
        let document = try DocumentImporter.extract(from: try write(data, named: "book.mobi"))

        XCTAssertEqual(
            document.chapters.map(\.text),
            ["Scaling up to a larger market development apparatus."]
        )
    }

    /// Mobipocket keeps the book in one document and marks its page breaks.
    func testAMobipocketBookIsCutAtItsPageBreaks() throws {
        let markup = "<html><body><p>Before.</p><mbp:pagebreak/><p>After.</p>"
            + "<mbp:pagebreak/><p>Last.</p></body></html>"
        let data = makeMOBI(markup: markup)
        let document = try DocumentImporter.extract(from: try write(data, named: "book.mobi"))

        XCTAssertEqual(document.chapters.map(\.text), ["Before.", "After.", "Last."])
    }

    func testABookThatNeverDividedItselfIsOneChapter() throws {
        let data = makeMOBI(markup: "<p>All of it, in one run.</p>")
        let document = try DocumentImporter.extract(from: try write(data, named: "book.mobi"))

        XCTAssertEqual(document.chapters.map(\.text), ["All of it, in one run."])
    }

    func testAnEncryptedBookIsReportedAsUnreadableRatherThanEmpty() throws {
        let data = makeMOBI(parts: ["<p>Locked away.</p>"], encryption: 1)
        let url = try write(data, named: "book.mobi")

        XCTAssertThrowsError(try DocumentImporter.extract(from: url)) { error in
            XCTAssertEqual(error as? DocumentImportError, .unreadable("book.mobi"))
        }
    }

    func testTheCoverIsFoundByCountingForwardFromTheFirstImage() throws {
        let cover = Data([0xFF, 0xD8, 0xFF, 0xE0]) + Data(repeating: 0x7F, count: 40)
        let data = makeMOBI(parts: ["<p>A book with a cover.</p>"], images: [Data(repeating: 1, count: 8), cover])
        let url = try write(data, named: "book.mobi")

        XCTAssertEqual(MOBITextExtractor.coverImageData(from: url), cover)
    }

    /// Anything that is not a picture is not a cover, however the header counts.
    func testAMiscountedCoverIsNoCover() throws {
        let data = makeMOBI(
            parts: ["<p>A book.</p>"],
            images: [Data(repeating: 1, count: 8)],
            coverOffset: 0
        )
        let url = try write(data, named: "book.mobi")

        XCTAssertNil(MOBITextExtractor.coverImageData(from: url))
    }

    // MARK: - The two compressions

    /// PalmDOC repeats itself by pointing backwards at what it already wrote,
    /// and a run can overlap the text it is still writing.
    func testPalmDOCBackReferencesAreFollowed() throws {
        let markup = "<html><body><p>Ahoy there. Ahoy there. Ahoy there.</p></body></html>"
        let data = makeMOBI(markup: markup, compression: 2)
        let document = try DocumentImporter.extract(from: try write(data, named: "book.mobi"))

        XCTAssertEqual(document.chapters.map(\.text), ["Ahoy there. Ahoy there. Ahoy there."])
    }

    /// HUFF/CDIC is what the Kindle actually ships, and the tables it decodes
    /// through are indexed by code length — an off-by-one there still produces
    /// text of exactly the right length, made of the wrong words.
    func testHuffCDICDecodesThroughTheCodeLengthTables() throws {
        let phrases = ["<html><body><p>Hello ", "world.</p></body></html>"]
        // Three nine-bit codes, which are non-terminal and so are resolved
        // against the length tables rather than off the first byte alone. The
        // third repeats the first, which is what a phrase dictionary is for,
        // and opens a second document as it does so.
        let data = makeHuffMOBI(phrases: phrases, codes: [1, 0, 1])
        let document = try DocumentImporter.extract(from: try write(data, named: "book.mobi"))

        XCTAssertEqual(document.chapters.map(\.text), ["Hello world.", "Hello"])
    }

    // MARK: - Fixtures

    private func write(_ data: Data, named name: String) throws -> URL {
        let url = workspace.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    /// A Kindle book whose parts are each wrapped as their own KF8 document.
    private func makeMOBI(
        parts: [String],
        title: String = "Untitled",
        author: String? = nil,
        images: [Data] = [],
        coverOffset: Int? = nil,
        encryption: Int = 0
    ) -> Data {
        let markup = parts.map {
            "<html><head><title>\(title)</title></head><body>\($0)</body></html>"
        }.joined()
        return makeMOBI(
            markup: markup,
            title: title,
            author: author,
            images: images,
            coverOffset: coverOffset,
            encryption: encryption
        )
    }

    private func makeMOBI(
        markup: String,
        title: String = "Untitled",
        author: String? = nil,
        images: [Data] = [],
        coverOffset: Int? = nil,
        encryption: Int = 0,
        compression: Int = 1
    ) -> Data {
        let text = Data(markup.utf8)
        let records: [Data]
        switch compression {
        case 2: records = [MOBIImportTests.palmDOCCompress(text)]
        default: records = [text]
        }
        return assemble(
            textRecords: records,
            textLength: text.count,
            compression: compression,
            title: title,
            author: author,
            trailing: images,
            firstImageIndex: images.isEmpty ? 0 : 1 + records.count,
            coverOffset: coverOffset ?? (images.isEmpty ? nil : images.count - 1),
            encryption: encryption
        )
    }

    /// A book compressed the way the Kindle really does it, with a Huffman
    /// dictionary carried in its own records.
    private func makeHuffMOBI(phrases: [String], codes: [Int]) -> Data {
        let huff = MOBIImportTests.makeHuffRecord()
        let cdic = MOBIImportTests.makeCDICRecord(phrases: phrases.map { Data($0.utf8) })
        let packed = MOBIImportTests.pack(codes: codes, width: 9)
        // Each nine-bit code numbered n selects the phrase the tables map it to.
        let decoded = codes.map { phrases[$0 == 0 ? 1 : 0] }.joined()

        return assemble(
            textRecords: [packed],
            textLength: Data(decoded.utf8).count,
            compression: 17480,
            title: "Untitled",
            author: nil,
            trailing: [huff, cdic],
            huffmanRecord: 2,
            huffmanCount: 2
        )
    }

    private func assemble(
        textRecords: [Data],
        textLength: Int,
        compression: Int,
        title: String,
        author: String?,
        trailing: [Data],
        firstImageIndex: Int = 0,
        coverOffset: Int? = nil,
        huffmanRecord: Int = 0,
        huffmanCount: Int = 0,
        encryption: Int = 0
    ) -> Data {
        var exth: [(UInt32, Data)] = [(503, Data(title.utf8))]
        if let author { exth.append((100, Data(author.utf8))) }
        if let coverOffset { exth.append((201, be32(UInt32(coverOffset)))) }

        let mobiHeaderLength = 248
        var header = Data(repeating: 0, count: 16 + mobiHeaderLength)
        header.poke16(0, compression)
        header.poke32(4, textLength)
        header.poke16(8, textRecords.count)
        header.poke16(10, 4096)
        header.poke16(12, encryption)
        header.replaceSubrange(16..<20, with: Data("MOBI".utf8))
        header.poke32(20, mobiHeaderLength)
        header.poke32(24, 2)
        header.poke32(28, 65001)
        header.poke32(108, firstImageIndex)
        header.poke32(112, huffmanRecord)
        header.poke32(116, huffmanCount)
        header.poke32(128, 0x40)
        header.poke16(242, 0)

        var table = Data("EXTH".utf8)
        let body = exth.reduce(Data()) { $0 + be32($1.0) + be32(UInt32(8 + $1.1.count)) + $1.1 }
        table += be32(UInt32(12 + body.count)) + be32(UInt32(exth.count)) + body
        header += table

        return MOBIImportTests.palmDatabase(records: [header] + textRecords + trailing)
    }

    private func be32(_ value: UInt32) -> Data {
        Data([UInt8(value >> 24 & 0xFF), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)])
    }

    /// The Palm container: a 78 byte header, one eight byte entry per record
    /// saying where it starts, then the records.
    private static func palmDatabase(records: [Data]) -> Data {
        var header = Data(repeating: 0, count: 78)
        header.replaceSubrange(0..<5, with: Data("Atten".utf8))
        header.replaceSubrange(60..<68, with: Data("BOOKMOBI".utf8))
        header.poke16(76, records.count)

        var offset = 78 + records.count * 8
        var table = Data()
        for (index, record) in records.enumerated() {
            table += Data([
                UInt8(offset >> 24 & 0xFF), UInt8(offset >> 16 & 0xFF),
                UInt8(offset >> 8 & 0xFF), UInt8(offset & 0xFF),
                0, 0, 0, UInt8(index & 0xFF),
            ])
            offset += record.count
        }
        return header + table + records.reduce(Data(), +)
    }

    /// Naive LZ77 in PalmDOC's shape: a back reference where one pays, and a
    /// literal byte otherwise.
    private static func palmDOCCompress(_ text: Data) -> Data {
        let input = Array(text)
        var out: [UInt8] = []
        var index = 0
        while index < input.count {
            var bestDistance = 0
            var bestLength = 0
            let earliest = max(0, index - 2047)
            if index > 0 {
                for start in earliest..<index {
                    var length = 0
                    while length < 10,
                          index + length < input.count,
                          input[start + length] == input[index + length] {
                        length += 1
                    }
                    if length > bestLength { bestLength = length; bestDistance = index - start }
                }
            }
            if bestLength >= 3 {
                let pair = 0x8000 | (bestDistance << 3) | (bestLength - 3)
                out += [UInt8(pair >> 8 & 0xFF), UInt8(pair & 0xFF)]
                index += bestLength
            } else {
                let byte = input[index]
                // 0x00 and 0x09...0x7F stand for themselves; anything else has
                // to be escaped as a literal run.
                if byte == 0 || (byte >= 0x09 && byte <= 0x7F) {
                    out.append(byte)
                } else {
                    out += [1, byte]
                }
                index += 1
            }
        }
        return Data(out)
    }

    /// A Huffman table where byte 0x00 opens a nine bit non-terminal code and
    /// every other byte is an eight bit terminal one, so decoding has to go
    /// through the per-length tables to find the phrase.
    private static func makeHuffRecord() -> Data {
        var record = Data(repeating: 0, count: 24)
        record.replaceSubrange(0..<4, with: Data("HUFF".utf8))
        record.poke32(4, 0x18)
        record.poke32(8, 24)
        record.poke32(12, 24 + 1024)

        var dictionary = Data(repeating: 0, count: 1024)
        // Length 9, non-terminal.
        dictionary.poke32(0, 9)
        for index in 1..<256 {
            // Length 8, terminal, resolving to phrase 0.
            dictionary.poke32(index * 4, (index << 8) | 0x80 | 8)
        }

        var ranges = Data(repeating: 0, count: 256)
        // The nine bit codes run from 0 to 1.
        ranges.poke32((9 - 1) * 8, 0)
        ranges.poke32((9 - 1) * 8 + 4, 1)

        return record + dictionary + ranges
    }

    private static func makeCDICRecord(phrases: [Data]) -> Data {
        var record = Data(repeating: 0, count: 16)
        record.replaceSubrange(0..<4, with: Data("CDIC".utf8))
        record.poke32(4, 0x10)
        record.poke32(8, phrases.count)
        // One bit of index, which is enough for the two phrases here.
        record.poke32(12, 1)

        var offsets = Data(repeating: 0, count: phrases.count * 2)
        var entries = Data()
        for (index, phrase) in phrases.enumerated() {
            // Offsets are counted from the end of the sixteen byte header.
            offsets.poke16(index * 2, phrases.count * 2 + entries.count)
            entries += Data([
                UInt8((0x8000 | phrase.count) >> 8 & 0xFF),
                UInt8(phrase.count & 0xFF),
            ]) + phrase
        }
        return record + offsets + entries
    }

    private static func pack(codes: [Int], width: Int) -> Data {
        var bits: [UInt8] = []
        for code in codes {
            for shift in stride(from: width - 1, through: 0, by: -1) {
                bits.append(UInt8((code >> shift) & 1))
            }
        }
        var out: [UInt8] = []
        for start in stride(from: 0, to: bits.count, by: 8) {
            var byte: UInt8 = 0
            for offset in 0..<8 {
                byte = (byte << 1) | (start + offset < bits.count ? bits[start + offset] : 0)
            }
            out.append(byte)
        }
        return Data(out)
    }
}

private extension Data {
    mutating func poke16(_ offset: Int, _ value: Int) {
        self[startIndex + offset] = UInt8(value >> 8 & 0xFF)
        self[startIndex + offset + 1] = UInt8(value & 0xFF)
    }

    mutating func poke32(_ offset: Int, _ value: Int) {
        self[startIndex + offset] = UInt8(value >> 24 & 0xFF)
        self[startIndex + offset + 1] = UInt8(value >> 16 & 0xFF)
        self[startIndex + offset + 2] = UInt8(value >> 8 & 0xFF)
        self[startIndex + offset + 3] = UInt8(value & 0xFF)
    }
}
