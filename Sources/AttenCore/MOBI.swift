import Foundation

/// Reading a Kindle book.
///
/// A Mobipocket file is a Palm database: a header, then a numbered list of
/// records. Record 0 describes the book, the records after it hold its text
/// compressed, and the records after those hold its pictures. Decompressing
/// the text records and joining them gives one long run of HTML — the whole
/// book, files and all, with no file system around it.
///
/// KF8, the format Amazon replaced Mobipocket with, keeps the same container
/// and the same compression. It differs in what the HTML looks like, and that
/// difference is handled where the chapters are cut.
public enum MOBITextExtractor {
    static func extract(from url: URL) throws -> ExtractedDocument {
        guard let data = try? Data(contentsOf: url),
              let book = MOBIBook(data: data) else {
            throw DocumentImportError.unreadable(url.lastPathComponent)
        }
        guard let markup = try? book.readText() else {
            throw DocumentImportError.unreadable(url.lastPathComponent)
        }

        var chapters: [DocumentChapter] = []
        for part in MOBITextExtractor.split(markup) {
            let document = XHTMLText.read(part)
            let text = DocumentText.normalize(document.text)
            guard !text.isEmpty else { continue }
            for (offset, section) in sections(in: text).enumerated() {
                chapters.append(DocumentChapter(
                    // The heading, when there is one, belongs to the part that
                    // carried it, which is the first section cut out of it.
                    title: DocumentText.chapterTitle(
                        heading: offset == 0 ? document.heading : nil,
                        text: section,
                        position: chapters.count + 1
                    ),
                    text: section
                ))
            }
        }
        guard !chapters.isEmpty else { throw DocumentImportError.noText(url.lastPathComponent) }

        return ExtractedDocument(
            title: book.title ?? url.deletingPathExtension().lastPathComponent,
            author: book.author,
            chapters: chapters
        )
    }

    /// The picture on the front of the book, which a Kindle book points at by
    /// counting forward from its first image rather than by naming a file.
    public static func coverImageData(from url: URL) -> Data? {
        guard let data = try? Data(contentsOf: url), let book = MOBIBook(data: data) else {
            return nil
        }
        return book.coverImageData()
    }

    /// A part that holds more than one chapter.
    ///
    /// KF8 divides the book the way the publisher's files did, and a publisher
    /// who put a part divider and the chapter after it in one file leaves that
    /// chapter with no entry of its own. Where the text itself announces an
    /// opening — a line reading "CHAPTER 10" and nothing else — that is where
    /// the reader would turn the page, so that is where this cuts.
    private static func sections(in text: String) -> [String] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        var sections: [String] = []
        var current: [Substring] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !current.isEmpty, DocumentText.isMarker(trimmed) {
                let section = current.joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !section.isEmpty { sections.append(section) }
                current = []
            }
            current.append(line)
        }
        let last = current.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !last.isEmpty { sections.append(last) }
        return sections.isEmpty ? [text] : sections
    }

    /// Where one chapter ends and the next begins.
    ///
    /// KF8 writes a fresh `<html>` for every part of the book, so those are the
    /// seams. Mobipocket has only one, and marks its page breaks instead. A
    /// book with neither is one chapter, which is the honest answer for a file
    /// that never divided itself.
    private static func split(_ markup: String) -> [String] {
        for separator in ["<html", "<mbp:pagebreak"] {
            let parts = markup.components(separatedBy: separator)
            guard parts.count > 1 else { continue }
            var pieces = parts.enumerated().map {
                $0.offset == 0 ? $0.element : separator + $0.element
            }
            // What sits before the first `<html` is nothing; what sits before
            // the first page break is the chapter that break ends.
            if separator == "<html" { pieces.removeFirst() }
            guard pieces.count > 1 else { continue }
            return pieces.map(withoutHead)
        }
        return [withoutHead(markup)]
    }

    /// KF8 repeats the book's `<head>` at the top of every part, and the parts
    /// are not well-formed on their own — the markup a part needs is spliced in
    /// from elsewhere in the file — so the XML parser refuses them and the
    /// fallback that strips tags reads the head out loud. Dropping it here
    /// spares every chapter a recital of the book's own title.
    private static let head = try? NSRegularExpression(
        pattern: "<head[^>]*>.*?</head>",
        options: [.caseInsensitive, .dotMatchesLineSeparators]
    )

    private static func withoutHead(_ part: String) -> String {
        guard let head else { return part }
        return head.stringByReplacingMatches(
            in: part,
            range: NSRange(part.startIndex..<part.endIndex, in: part),
            withTemplate: ""
        )
    }
}

/// The Palm database a Kindle book is stored in, and the headers that say how
/// to read it.
struct MOBIBook {
    private let data: Data
    /// The byte range of each record, in order.
    private let records: [Range<Int>]
    private let header: Data

    let title: String?
    let author: String?

    private let compression: Int
    private let textLength: Int
    private let textRecordCount: Int
    private let encoding: String.Encoding
    /// Bytes some records carry after their text that are not text.
    private let extraDataFlags: Int
    private let firstImageIndex: Int
    private let coverOffset: Int?
    private let huffmanRecord: Int
    private let huffmanCount: Int

    init?(data: Data) {
        // Palm database header: the record count at byte 76, then one eight
        // byte entry per record giving where that record starts.
        guard data.count > 78, data.readUInt32(at: 60) == 0x424F_4F4B else { return nil }
        let count = Int(data.readUInt16(at: 76))
        guard count > 0, data.count >= 78 + count * 8 else { return nil }

        var starts: [Int] = []
        starts.reserveCapacity(count + 1)
        for index in 0..<count {
            starts.append(Int(data.readUInt32(at: 78 + index * 8)))
        }
        starts.append(data.count)
        // A record that runs backwards, or off the end, is a broken file.
        guard zip(starts, starts.dropFirst()).allSatisfy({ $0 <= $1 }),
              let last = starts.last, last <= data.count else { return nil }

        self.data = data
        records = zip(starts, starts.dropFirst()).map { $0..<$1 }

        let header = data[records[0]]
        guard header.count >= 16 else { return nil }
        self.header = header

        compression = Int(header.readUInt16(at: 0))
        textLength = Int(header.readUInt32(at: 4))
        textRecordCount = min(Int(header.readUInt16(at: 8)), count - 1)
        // Encryption is the one thing here that cannot be worked around.
        guard header.readUInt16(at: 12) == 0 else { return nil }

        // The MOBI header sits inside record 0, just past the Palm one.
        let headerLength: Int
        if header.count >= 24, header.readUInt32(at: 16) == 0x4D4F_4249 {
            headerLength = Int(header.readUInt32(at: 20))
        } else {
            headerLength = 0
        }
        let has = { (offset: Int) in headerLength >= offset - 16 + 4 }

        let textEncoding: String.Encoding =
            has(28) && header.readUInt32(at: 28) == 1252 ? .windowsCP1252 : .utf8
        encoding = textEncoding
        firstImageIndex = has(108) ? Int(header.readUInt32(at: 108)) : 0
        huffmanRecord = has(112) ? Int(header.readUInt32(at: 112)) : 0
        huffmanCount = has(116) ? Int(header.readUInt32(at: 116)) : 0
        extraDataFlags = has(242) ? Int(header.readUInt16(at: 242)) : 0

        // EXTH, the table of everything about the book that is not about how to
        // decode it: who wrote it, what it is called, which picture is the cover.
        var exth: [UInt32: Data] = [:]
        if headerLength > 0, has(128), header.readUInt32(at: 128) & 0x40 != 0 {
            exth = MOBIBook.readEXTH(header, at: 16 + headerLength)
        }
        let string = { (key: UInt32) -> String? in
            guard let value = exth[key] else { return nil }
            let text = String(data: value, encoding: textEncoding)
                ?? String(decoding: value, as: UTF8.self)
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        // 503 is the title Amazon last set, which is the one on the device.
        title = string(503)
            ?? MOBIBook.fullName(in: header, headerLength: headerLength, encoding: textEncoding)
        author = string(100)
        coverOffset = exth[201].flatMap { $0.count == 4 ? Int($0.readUInt32(at: 0)) : nil }
    }

    /// The whole book as one run of markup.
    func readText() throws -> String {
        let decompress: (Data) throws -> [UInt8]
        switch compression {
        case 1:
            decompress = { Array($0) }
        case 2:
            decompress = PalmDOC.decompress
        case 17480:
            guard huffmanCount > 0, records.indices.contains(huffmanRecord) else {
                throw MOBIError.unsupported
            }
            let dictionaries = (1..<huffmanCount)
                .map { huffmanRecord + $0 }
                .filter { records.indices.contains($0) }
                .map { data[records[$0]] }
            guard let reader = HuffCDIC(huff: data[records[huffmanRecord]], cdics: dictionaries) else {
                throw MOBIError.unsupported
            }
            decompress = reader.decompress
        default:
            throw MOBIError.unsupported
        }

        var bytes: [UInt8] = []
        bytes.reserveCapacity(textLength)
        for index in 1...max(1, textRecordCount) where records.indices.contains(index) {
            let record = trimTrailingData(data[records[index]])
            bytes += (try? decompress(record)) ?? []
        }
        if bytes.count > textLength { bytes.removeLast(bytes.count - textLength) }
        guard !bytes.isEmpty else { throw MOBIError.unsupported }

        let raw = Data(bytes)
        return String(data: raw, encoding: encoding) ?? String(decoding: raw, as: UTF8.self)
    }

    func coverImageData() -> Data? {
        guard let coverOffset, firstImageIndex > 0 else { return nil }
        let index = firstImageIndex + coverOffset
        guard records.indices.contains(index) else { return nil }
        let bytes = data[records[index]]
        // Only answer with something that is actually a picture.
        guard bytes.count > 4 else { return nil }
        let start = bytes.startIndex
        let isJPEG = bytes[start] == 0xFF && bytes[start + 1] == 0xD8
        let isPNG = bytes[start] == 0x89 && bytes[start + 1] == 0x50
        guard isJPEG || isPNG else { return nil }
        return Data(bytes)
    }

    /// Text records can carry extra bytes on the end — a note of the character
    /// the next record starts in the middle of, and other bookkeeping. They are
    /// counted backwards from the end, one flag at a time, and none of them are
    /// part of the book.
    private func trimTrailingData(_ record: Data) -> Data {
        var size = record.count
        var flags = extraDataFlags >> 1
        while flags != 0, size > 0 {
            if flags & 1 != 0 { size -= MOBIBook.trailingEntrySize(record, size) }
            flags >>= 1
        }
        if extraDataFlags & 1 != 0, size > 0 {
            size -= Int(record[record.startIndex + size - 1] & 0x03) + 1
        }
        guard size > 0 else { return Data() }
        return record.prefix(size)
    }

    /// The length of one trailing entry, written backwards in seven bit pieces
    /// with the top bit marking the last one.
    private static func trailingEntrySize(_ record: Data, _ size: Int) -> Int {
        var size = size
        var shift = 0
        var result = 0
        while true {
            let byte = record[record.startIndex + size - 1]
            result |= Int(byte & 0x7F) << shift
            shift += 7
            size -= 1
            if byte & 0x80 != 0 || shift >= 28 || size == 0 { return result }
        }
    }

    private static func readEXTH(_ header: Data, at offset: Int) -> [UInt32: Data] {
        guard offset + 12 <= header.count, header.readUInt32(at: offset) == 0x4558_5448 else {
            return [:]
        }
        var records: [UInt32: Data] = [:]
        var cursor = offset + 12
        for _ in 0..<Int(header.readUInt32(at: offset + 8)) {
            guard cursor + 8 <= header.count else { break }
            let type = header.readUInt32(at: cursor)
            let length = Int(header.readUInt32(at: cursor + 4))
            guard length >= 8, cursor + length <= header.count else { break }
            let start = header.startIndex + cursor + 8
            records[type] = header[start..<(header.startIndex + cursor + length)]
            cursor += length
        }
        return records
    }

    /// The title the publisher set, kept outside EXTH at its own offset.
    private static func fullName(in header: Data, headerLength: Int, encoding: String.Encoding) -> String? {
        guard headerLength >= 84 - 16 + 8, header.count >= 92 else { return nil }
        let offset = Int(header.readUInt32(at: 84))
        let length = Int(header.readUInt32(at: 88))
        guard length > 0, offset + length <= header.count else { return nil }
        let start = header.startIndex + offset
        let value = header[start..<(start + length)]
        let text = String(data: value, encoding: encoding) ?? String(decoding: value, as: UTF8.self)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum MOBIError: Error {
    case unsupported
}

/// The older of the two compressions: a byte either stands for itself, names a
/// run of bytes already written, or stands for a space and one more character.
enum PalmDOC {
    static func decompress(_ record: Data) -> [UInt8] {
        let input = Array(record)
        var out: [UInt8] = []
        out.reserveCapacity(input.count * 4)
        var index = 0
        while index < input.count {
            let byte = input[index]
            index += 1
            switch byte {
            case 0x01...0x08:
                let count = min(Int(byte), input.count - index)
                out += input[index..<(index + count)]
                index += count
            case 0x00, 0x09...0x7F:
                out.append(byte)
            case 0x80...0xBF:
                guard index < input.count else { return out }
                let pair = (Int(byte) << 8) | Int(input[index])
                index += 1
                let distance = (pair >> 3) & 0x07FF
                let length = (pair & 0x07) + 3
                guard distance > 0, distance <= out.count else { return out }
                // The run can overlap what it is still writing, so it is copied
                // one byte at a time rather than as a slice.
                for _ in 0..<length { out.append(out[out.count - distance]) }
            default:
                out.append(0x20)
                out.append(byte ^ 0x80)
            }
        }
        return out
    }
}

/// The newer compression: a Huffman code per symbol, where a symbol is a
/// phrase from a dictionary carried in the file. Phrases may themselves be
/// compressed, so unpacking one can mean unpacking it again.
final class HuffCDIC {
    private struct Code {
        let length: Int
        let terminal: Bool
        let maxCode: UInt64
    }

    private let codes: [Code]
    private let minCode: [UInt64]
    private let maxCode: [UInt64]
    private var phrases: [(bytes: [UInt8], terminal: Bool)]

    init?(huff: Data, cdics: [Data]) {
        guard huff.count >= 16, huff.readUInt32(at: 0) == 0x4855_4646 else { return nil }
        let codeTable = Int(huff.readUInt32(at: 8))
        let rangeTable = Int(huff.readUInt32(at: 12))
        guard codeTable + 256 * 4 <= huff.count, rangeTable + 64 * 4 <= huff.count else { return nil }

        codes = (0..<256).map { index in
            let value = huff.readUInt32(at: codeTable + index * 4)
            let length = Int(value & 0x1F)
            return Code(
                length: length,
                terminal: value & 0x80 != 0,
                maxCode: length == 0 ? 0 : ((UInt64(value >> 8) + 1) << (32 - length)) - 1
            )
        }
        guard codes.allSatisfy({ $0.length > 0 && ($0.length > 8 || $0.terminal) }) else { return nil }

        // Indexed by code length, so both tables start with an unused entry.
        var minimums: [UInt64] = [0]
        var maximums: [UInt64] = [0]
        for length in 1...32 {
            let low = UInt64(huff.readUInt32(at: rangeTable + (length - 1) * 8))
            let high = UInt64(huff.readUInt32(at: rangeTable + (length - 1) * 8 + 4))
            minimums.append(low << (32 - length))
            maximums.append(((high + 1) << (32 - length)) - 1)
        }
        minCode = minimums
        maxCode = maximums

        phrases = []
        for cdic in cdics {
            guard cdic.count >= 16, cdic.readUInt32(at: 0) == 0x4344_4943 else { return nil }
            let total = Int(cdic.readUInt32(at: 8))
            let bits = Int(cdic.readUInt32(at: 12))
            guard bits < 32 else { return nil }
            let count = min(1 << bits, total - phrases.count)
            guard count > 0, 16 + count * 2 <= cdic.count else { continue }
            for index in 0..<count {
                let offset = Int(cdic.readUInt16(at: 16 + index * 2))
                guard 16 + offset + 2 <= cdic.count else { return nil }
                let marker = Int(cdic.readUInt16(at: 16 + offset))
                let length = marker & 0x7FFF
                let start = cdic.startIndex + 18 + offset
                guard start + length <= cdic.endIndex else { return nil }
                phrases.append((Array(cdic[start..<(start + length)]), marker & 0x8000 != 0))
            }
        }
        guard !phrases.isEmpty else { return nil }
    }

    func decompress(_ record: Data) throws -> [UInt8] {
        try unpack(Array(record), depth: 0)
    }

    /// Reads codes off the front of a 64 bit window that slides four bytes at a
    /// time, so a code up to 32 bits long is always whole inside it.
    private func unpack(_ input: [UInt8], depth: Int) throws -> [UInt8] {
        // A phrase that unpacks to itself would never end.
        guard depth < 8 else { throw MOBIError.unsupported }

        var bitsLeft = input.count * 8
        var position = 0
        var window = HuffCDIC.readUInt64(input, at: 0)
        var available = 32
        var out: [UInt8] = []

        while true {
            if available <= 0 {
                position += 4
                window = HuffCDIC.readUInt64(input, at: position)
                available += 32
            }
            let code = (window >> UInt64(available)) & 0xFFFF_FFFF

            let entry = codes[Int(code >> 24)]
            var length = entry.length
            var ceiling = entry.maxCode
            if !entry.terminal {
                while length < 32, code < minCode[length] { length += 1 }
                guard length <= 32 else { throw MOBIError.unsupported }
                ceiling = maxCode[length]
            }

            available -= length
            bitsLeft -= length
            if bitsLeft < 0 { break }

            guard ceiling >= code else { throw MOBIError.unsupported }
            let index = Int((ceiling - code) >> UInt64(32 - length))
            guard phrases.indices.contains(index) else { throw MOBIError.unsupported }

            let phrase = phrases[index]
            if phrase.terminal {
                out += phrase.bytes
            } else {
                let unpacked = try unpack(phrase.bytes, depth: depth + 1)
                phrases[index] = (unpacked, true)
                out += unpacked
            }
        }
        return out
    }

    /// Eight bytes from the given offset, treating anything past the end as
    /// zero so the last code in a record can still be read whole.
    private static func readUInt64(_ bytes: [UInt8], at offset: Int) -> UInt64 {
        var value: UInt64 = 0
        for index in 0..<8 {
            let position = offset + index
            value = (value << 8) | UInt64(position < bytes.count ? bytes[position] : 0)
        }
        return value
    }
}

private extension Data {
    func readUInt16(at offset: Int) -> UInt16 {
        let start = startIndex + offset
        guard start + 2 <= endIndex else { return 0 }
        return (UInt16(self[start]) << 8) | UInt16(self[start + 1])
    }

    func readUInt32(at offset: Int) -> UInt32 {
        let start = startIndex + offset
        guard start + 4 <= endIndex else { return 0 }
        return (UInt32(self[start]) << 24) | (UInt32(self[start + 1]) << 16)
            | (UInt32(self[start + 2]) << 8) | UInt32(self[start + 3])
    }
}
