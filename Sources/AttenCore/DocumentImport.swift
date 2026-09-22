import Foundation
import PDFKit

/// One readable, narratable unit of an imported book.
public struct DocumentChapter: Equatable, Sendable {
    public let title: String
    public let text: String
    /// Page the chapter opens on, so a PDF can be read as well as narrated.
    /// EPUBs have no fixed pagination and leave this nil.
    public let pageIndex: Int?

    public init(title: String, text: String, pageIndex: Int? = nil) {
        self.title = title
        self.text = text
        self.pageIndex = pageIndex
    }
}

public struct ExtractedDocument: Equatable, Sendable {
    public let title: String
    public let author: String?
    public let chapters: [DocumentChapter]

    public init(title: String, author: String?, chapters: [DocumentChapter]) {
        self.title = title
        self.author = author
        self.chapters = chapters
    }
}

public enum DocumentImportError: LocalizedError, Equatable {
    case unsupportedFormat(String)
    case unreadable(String)
    case noText(String)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedFormat(pathExtension):
            """
            Atten reads PDFs, EPUBs, and text, Markdown, Word and RTF \
            documents. It cannot open a .\(pathExtension) file.
            """
        case let .unreadable(name):
            """
            Atten could not open \(name). The file may be damaged, or protected \
            with a password Atten cannot supply.
            """
        case let .noText(name):
            """
            \(name) has no text Atten can read aloud. Scanned documents are images \
            of pages rather than text, so they need to be run through OCR first.
            """
        }
    }
}

public enum DocumentImporter {
    public static let supportedExtensions = BookFormat.supportedExtensions

    /// Reads a document into chapters. This walks every page of the file, so
    /// it is meant to be called off the main actor.
    public static func extract(from url: URL) throws -> ExtractedDocument {
        switch BookFormat.resolve(for: url) {
        case .pdf: try PDFTextExtractor.extract(from: url)
        case .epub: try EPUBTextExtractor.extract(from: url)
        case .mobi: try MOBITextExtractor.extract(from: url)
        case .document: try FlatDocumentExtractor.extract(from: url)
        case nil: throw DocumentImportError.unsupportedFormat(url.pathExtension)
        }
    }
}

// MARK: - Shared text cleanup

public enum DocumentText {
    /// Book text arrives hard-wrapped at the width it was typeset for. Speech
    /// wants sentences, so wrapped lines are rejoined and only blank lines
    /// survive as paragraph breaks. Without this the engine hears a line ending
    /// as a pause and reads a page as a list.
    public static func normalize(_ raw: String) -> String {
        var text = raw.replacingOccurrences(of: "\r\n", with: "\n")
        text = text.replacingOccurrences(of: "\r", with: "\n")
        text = text.replacingOccurrences(of: "\u{00AD}", with: "")
        text = text.replacingOccurrences(of: "\u{00A0}", with: " ")
        // A word broken across a line by a hyphen is one word again.
        text = text.replacingOccurrences(
            of: "(\\p{L})-\\n(\\p{L})",
            with: "$1$2",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: "([^\\n])\\n(?!\\n)",
            with: "$1 ",
            options: .regularExpression
        )
        text = text.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        text = text.replacingOccurrences(of: " *\\n *", with: "\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A line that opens a division of the book and names nothing else:
    /// "CHAPTER 1", "PART II". The title it belongs to is on the line under it.
    static let marker = try? NSRegularExpression(
        pattern: "^(CHAPTER|PART|BOOK|SECTION) +([0-9]+|[IVXLCDM]+)$"
    )

    static func isMarker(_ line: String) -> Bool {
        guard let marker else { return false }
        // Only in the book's own capitals. A cross-reference reads "Chapter 8",
        // and mistaking one for an opening would cut a chapter in half.
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        return marker.firstMatch(in: line, options: [.anchored], range: range) != nil
    }

    /// A line short enough to be a title rather than the first sentence of one.
    /// Trailing punctuation that continues a sentence is the giveaway; a colon
    /// is not, because a title often carries one before its subtitle.
    private static func titleLike(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: CharacterSet(charactersIn: ": "))
        guard !trimmed.isEmpty, trimmed.count <= 90,
              trimmed.split(whereSeparator: \.isWhitespace).count <= 14,
              !",;.".contains(trimmed.last!) else { return nil }
        return trimmed
    }

    /// What to call a chapter. A book that marks its openings with a heading
    /// element says so plainly; one that only styles a paragraph does not, and
    /// then the first line of the chapter is the title printed on the page.
    public static func chapterTitle(heading: String?, text: String, position: Int) -> String {
        if let heading, !heading.isEmpty { return heading }
        let lines = text.split(separator: "\n").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }

        if let first = lines.first {
            if isMarker(first), let subtitle = lines.dropFirst().first.flatMap(titleLike) {
                return "\(first): \(subtitle)"
            }
            if let title = titleLike(first) { return title }
        }
        return "Chapter \(position)"
    }
}

// MARK: - PDF

enum PDFTextExtractor {
    /// Pages per chapter when a PDF carries no outline: long enough to be worth
    /// a chapter, short enough that one failed generation costs little.
    private static let fallbackChapterLength = 10

    private struct Mark {
        let title: String
        let page: Int
    }

    static func extract(from url: URL) throws -> ExtractedDocument {
        guard let document = PDFDocument(url: url), !document.isLocked, document.pageCount > 0 else {
            throw DocumentImportError.unreadable(url.lastPathComponent)
        }
        let pages = (0..<document.pageCount).map {
            DocumentText.normalize(document.page(at: $0)?.string ?? "")
        }
        let marks = outlineMarks(in: document) ?? evenMarks(pageCount: pages.count)

        var chapters: [DocumentChapter] = []
        for (index, mark) in marks.enumerated() {
            let end = index + 1 < marks.count ? marks[index + 1].page : pages.count
            guard mark.page < end else { continue }
            let text = pages[mark.page..<end]
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")
            guard !text.isEmpty else { continue }
            chapters.append(DocumentChapter(title: mark.title, text: text, pageIndex: mark.page))
        }
        guard !chapters.isEmpty else { throw DocumentImportError.noText(url.lastPathComponent) }

        let attributes = document.documentAttributes
        return ExtractedDocument(
            title: nonEmpty(attributes?[PDFDocumentAttribute.titleAttribute] as? String)
                ?? url.deletingPathExtension().lastPathComponent,
            author: nonEmpty(attributes?[PDFDocumentAttribute.authorAttribute] as? String),
            chapters: chapters
        )
    }

    /// Top-level outline entries, which is what a reader thinks of as the table
    /// of contents. Deeper levels are ignored: a chapter per subsection would
    /// produce hundreds of few-second audio files.
    private static func outlineMarks(in document: PDFDocument) -> [Mark]? {
        guard let root = document.outlineRoot, root.numberOfChildren > 1 else { return nil }

        var marks: [Mark] = []
        for index in 0..<root.numberOfChildren {
            guard let child = root.child(at: index),
                  let page = destinationPage(of: child) else { continue }
            // PDFKit answers with NSNotFound for a page it cannot place.
            let pageIndex = document.index(for: page)
            guard pageIndex >= 0, pageIndex < document.pageCount else { continue }
            let label = (child.label ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            marks.append(Mark(
                title: label.isEmpty ? "Section \(index + 1)" : label,
                page: pageIndex
            ))
        }

        marks.sort { $0.page < $1.page }
        // An outline that points every entry at the same page tells us nothing
        // about where chapters begin, so fall back to even slices.
        guard Set(marks.map(\.page)).count > 1 else { return nil }
        if let first = marks.first, first.page > 0 {
            marks.insert(Mark(title: "Front matter", page: 0), at: 0)
        }
        return marks
    }

    private static func destinationPage(of outline: PDFOutline) -> PDFPage? {
        outline.destination?.page ?? (outline.action as? PDFActionGoTo)?.destination.page
    }

    private static func evenMarks(pageCount: Int) -> [Mark] {
        stride(from: 0, to: pageCount, by: fallbackChapterLength).map { start in
            let end = min(start + fallbackChapterLength, pageCount)
            return Mark(title: "Pages \(start + 1)–\(end)", page: start)
        }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - EPUB

public enum EPUBTextExtractor {
    static func extract(from url: URL) throws -> ExtractedDocument {
        let unpacked = try unpack(url)
        defer { try? FileManager.default.removeItem(at: unpacked) }

        let packageURL = try packageURL(in: unpacked, source: url.lastPathComponent)
        let elements = try parse(packageURL, collecting: ["item", "itemref", "title", "creator"])
        let packageDirectory = packageURL.deletingLastPathComponent()

        var manifest: [String: String] = [:]
        for element in elements where element.name == "item" {
            guard let id = element.attributes["id"],
                  let href = element.attributes["href"],
                  isReadable(mediaType: element.attributes["media-type"], href: href) else { continue }
            manifest[id] = href
        }

        var chapters: [DocumentChapter] = []
        for element in elements where element.name == "itemref" {
            guard let href = element.attributes["idref"].flatMap({ manifest[$0] }) else { continue }
            let documentURL = resolve(href: href, against: packageDirectory)
            let document = readDocument(at: documentURL)
            let text = DocumentText.normalize(document.text)
            guard !text.isEmpty else { continue }
            chapters.append(DocumentChapter(
                title: DocumentText.chapterTitle(
                    heading: document.heading,
                    text: text,
                    position: chapters.count + 1
                ),
                text: text
            ))
        }
        guard !chapters.isEmpty else { throw DocumentImportError.noText(url.lastPathComponent) }

        let metadata = { (name: String) -> String? in
            let value = elements.first { $0.name == name }?.text
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return value.isEmpty ? nil : value
        }
        return ExtractedDocument(
            title: metadata("title") ?? url.deletingPathExtension().lastPathComponent,
            author: metadata("creator"),
            chapters: chapters
        )
    }

    /// The picture on the front of the book.
    ///
    /// An EPUB names its cover in one of three ways depending on how old it is,
    /// and books in the wild use all three, so all three are tried before
    /// falling back on an image that simply calls itself a cover. Answers the
    /// file's bytes rather than an image, because this runs nowhere near a
    /// screen and AppKit is not this layer's business.
    public static func coverImageData(from url: URL) -> Data? {
        guard let unpacked = try? unpack(url) else { return nil }
        defer { try? FileManager.default.removeItem(at: unpacked) }
        guard let packageURL = try? packageURL(in: unpacked, source: url.lastPathComponent),
              let elements = try? parse(packageURL, collecting: ["item", "meta"]) else {
            return nil
        }
        let directory = packageURL.deletingLastPathComponent()
        // A crafted href can climb out of the archive with "..", and this is a
        // read of a file the user never chose. Anything that lands outside the
        // unpacked book is not part of the book.
        let read = { (href: String) -> Data? in
            let url = resolve(href: href, against: directory).standardizedFileURL
            guard url.path.hasPrefix(unpacked.standardizedFileURL.path) else { return nil }
            return try? Data(contentsOf: url)
        }
        let images = elements.filter {
            $0.name == "item" && isImage(
                mediaType: $0.attributes["media-type"],
                href: $0.attributes["href"] ?? ""
            )
        }

        // EPUB 3 marks it in the manifest.
        if let href = images.first(where: {
            $0.attributes["properties"]?.contains("cover-image") == true
        })?.attributes["href"] {
            return read(href)
        }
        // EPUB 2 points at a manifest entry from the metadata.
        if let id = elements.first(where: { $0.name == "meta" && $0.attributes["name"] == "cover" })?
            .attributes["content"],
           let href = images.first(where: { $0.attributes["id"] == id })?.attributes["href"] {
            return read(href)
        }
        // And some only say so in the file name.
        if let href = images.first(where: {
            ($0.attributes["href"] ?? "").lowercased().contains("cover")
                || ($0.attributes["id"] ?? "").lowercased().contains("cover")
        })?.attributes["href"] {
            return read(href)
        }
        return nil
    }

    private static func isImage(mediaType: String?, href: String) -> Bool {
        if let mediaType, mediaType.hasPrefix("image/") { return true }
        return ["jpg", "jpeg", "png", "gif", "webp"]
            .contains(URL(fileURLWithPath: href).pathExtension.lowercased())
    }

    /// An EPUB is a zip. `ditto` ships with macOS and refuses paths that escape
    /// the destination, so a malicious archive cannot write outside the
    /// temporary directory this unpacks into.
    private static func unpack(_ url: URL) throws -> URL {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("Atten-epub-\(UUID().uuidString)", isDirectory: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", url.path, destination.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw DocumentImportError.unreadable(url.lastPathComponent)
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            try? FileManager.default.removeItem(at: destination)
            throw DocumentImportError.unreadable(url.lastPathComponent)
        }
        return destination
    }

    /// `META-INF/container.xml` names the package document. Some books in the
    /// wild omit it, so a single `.opf` anywhere in the archive is accepted too.
    private static func packageURL(in root: URL, source: String) throws -> URL {
        let containerURL = root.appendingPathComponent("META-INF/container.xml")
        if let rootfile = try? parse(containerURL, collecting: ["rootfile"]).first,
           let path = rootfile.attributes["full-path"], !path.isEmpty {
            let url = resolve(href: path, against: root)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        let enumerated = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        if let fallback = enumerated?.compactMap({ $0 as? URL })
            .first(where: { $0.pathExtension.lowercased() == "opf" }) {
            return fallback
        }
        throw DocumentImportError.unreadable(source)
    }

    private static func isReadable(mediaType: String?, href: String) -> Bool {
        if let mediaType, !mediaType.isEmpty {
            return mediaType.contains("xhtml") || mediaType.contains("html")
        }
        return ["xhtml", "html", "htm"].contains(
            URL(fileURLWithPath: href).pathExtension.lowercased()
        )
    }

    private static func resolve(href: String, against directory: URL) -> URL {
        let path = href.components(separatedBy: "#").first ?? href
        let decoded = path.removingPercentEncoding ?? path
        return URL(fileURLWithPath: decoded, relativeTo: directory).standardizedFileURL
    }

    // MARK: XHTML

    /// XHTML in the wild uses HTML entity names no XML parser knows, and is now
    /// and then not well-formed at all. Substituting the common names first
    /// fixes the usual case; anything still unparsable falls back to stripping
    /// tags, which reads worse but never loses a chapter.
    private static func readDocument(at url: URL) -> (text: String, heading: String?) {
        guard let data = try? Data(contentsOf: url) else { return ("", nil) }
        return XHTMLText.read(String(decoding: data, as: UTF8.self))
    }

    // MARK: XML helpers

    private static func parse(
        _ url: URL,
        collecting targets: Set<String>
    ) throws -> [ElementCollector.Element] {
        guard let data = try? Data(contentsOf: url) else {
            throw DocumentImportError.unreadable(url.lastPathComponent)
        }
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        let collector = ElementCollector(collecting: targets)
        parser.delegate = collector
        guard parser.parse() else {
            throw DocumentImportError.unreadable(url.lastPathComponent)
        }
        return collector.elements
    }

    /// Records the attributes and text of every element with one of the given
    /// names. Names are compared without their namespace prefix, so `dc:title`
    /// and `title` are the same element.
    private final class ElementCollector: NSObject, XMLParserDelegate {
        struct Element {
            let name: String
            let attributes: [String: String]
            var text: String
        }

        private let targets: Set<String>
        private var openIndex: Int?
        private(set) var elements: [Element] = []

        init(collecting targets: Set<String>) {
            self.targets = targets
        }

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName: String?,
            attributes: [String: String] = [:]
        ) {
            let name = localName(elementName)
            guard targets.contains(name) else { return }
            elements.append(Element(name: name, attributes: attributes, text: ""))
            openIndex = elements.count - 1
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard let openIndex else { return }
            elements[openIndex].text += string
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName: String?
        ) {
            if targets.contains(localName(elementName)) { openIndex = nil }
        }
    }
}

/// Flattening XHTML to the words a voice reads. An EPUB keeps its markup in
/// files and a Kindle book keeps it in one run of text, but past that point
/// they are the same job, so both formats come through here.
enum XHTMLText {
    fileprivate static let skipped: Set<String> = ["script", "style", "head"]
    fileprivate static let blocks: Set<String> = [
        "p", "div", "br", "li", "tr", "td", "blockquote", "section",
        "article", "figcaption", "h1", "h2", "h3", "h4", "h5", "h6",
    ]
    fileprivate static let headings: Set<String> = ["h1", "h2", "h3"]

    /// XHTML in the wild uses HTML entity names no XML parser knows, and is now
    /// and then not well-formed at all. Substituting the common names first
    /// fixes the usual case; anything still unparsable falls back to stripping
    /// tags, which reads worse but never loses a chapter.
    static func read(_ html: String) -> (text: String, heading: String?) {
        let source = HTMLEntities.substituteNamed(in: html)

        let parser = XMLParser(data: Data(source.utf8))
        parser.shouldResolveExternalEntities = false
        let collector = XHTMLTextCollector()
        parser.delegate = collector
        if parser.parse(), !collector.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return (collector.text, collector.heading)
        }

        return (HTMLEntities.decodeRemaining(in: strippingTags(from: source)), nil)
    }

    private static let tag = try? NSRegularExpression(pattern: "<[^>]+>")

    /// Only a block ends a line. An emphasis or a link sits inside a sentence,
    /// and a newline in its place is a paragraph break that splits the sentence
    /// in two — which the voice reads as a pause in the middle of a thought.
    private static func strippingTags(from source: String) -> String {
        guard let tag else { return source }
        var result = source
        let full = NSRange(source.startIndex..<source.endIndex, in: source)
        for match in tag.matches(in: source, range: full).reversed() {
            guard let range = Range(match.range, in: source) else { continue }
            let name = tagName(in: source[range])
            result.replaceSubrange(range, with: blocks.contains(name) ? "\n" : "")
        }
        return result
    }

    /// The element a tag opens or closes, taken off the front of `<p class=…>`
    /// or `</p>` and compared the way every other name here is.
    private static func tagName(in tag: Substring) -> String {
        let name = tag.dropFirst().drop { $0 == "/" }
            .prefix { !$0.isWhitespace && $0 != ">" && $0 != "/" }
        return localName(String(name))
    }

    /// Flattens an XHTML chapter to spoken text and picks up its heading, which
    /// is the chapter title a reader recognizes.
    private final class XHTMLTextCollector: NSObject, XMLParserDelegate {
        private var skipDepth = 0
        private var headingBuffer: String?
        private(set) var text = ""
        private(set) var heading: String?

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName: String?,
            attributes: [String: String] = [:]
        ) {
            let name = localName(elementName)
            if XHTMLText.skipped.contains(name) {
                skipDepth += 1
                return
            }
            guard skipDepth == 0 else { return }
            if XHTMLText.blocks.contains(name) { text += "\n" }
            if XHTMLText.headings.contains(name), heading == nil, headingBuffer == nil {
                headingBuffer = ""
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard skipDepth == 0 else { return }
            text += string
            if headingBuffer != nil { headingBuffer? += string }
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName: String?
        ) {
            let name = localName(elementName)
            if XHTMLText.skipped.contains(name) {
                skipDepth = max(0, skipDepth - 1)
                return
            }
            guard skipDepth == 0 else { return }
            if XHTMLText.headings.contains(name), let buffer = headingBuffer {
                let title = buffer
                    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                heading = title.isEmpty ? nil : title
                headingBuffer = nil
            }
            if XHTMLText.blocks.contains(name) { text += "\n" }
        }
    }
}

private func localName(_ name: String) -> String {
    (name.split(separator: ":").last.map(String.init) ?? name).lowercased()
}

/// The HTML named entities that actually turn up in books. Anything else is
/// dropped rather than left to break the parse.
enum HTMLEntities {
    private static let named: [String: String] = [
        "nbsp": " ", "ensp": " ", "emsp": " ", "thinsp": " ", "shy": "",
        "ndash": "–", "mdash": "—", "minus": "−", "hellip": "…",
        "lsquo": "‘", "rsquo": "’", "sbquo": "‚", "ldquo": "“", "rdquo": "”", "bdquo": "„",
        "laquo": "«", "raquo": "»", "lsaquo": "‹", "rsaquo": "›",
        "copy": "©", "reg": "®", "trade": "™", "sect": "§", "para": "¶",
        "dagger": "†", "Dagger": "‡", "bull": "•", "middot": "·", "deg": "°",
        "times": "×", "divide": "÷", "plusmn": "±", "frac12": "½", "frac14": "¼",
        "euro": "€", "pound": "£", "yen": "¥", "cent": "¢",
        "aacute": "á", "eacute": "é", "iacute": "í", "oacute": "ó", "uacute": "ú",
        "agrave": "à", "egrave": "è", "ccedil": "ç", "ntilde": "ñ", "uuml": "ü",
        "ouml": "ö", "auml": "ä", "szlig": "ß", "aelig": "æ", "oslash": "ø",
    ]
    /// XML defines these itself, so they must survive to the parser untouched.
    private static let reserved: Set<String> = ["amp", "lt", "gt", "quot", "apos"]

    private static let pattern = try? NSRegularExpression(
        pattern: "&([A-Za-z][A-Za-z0-9]{1,31});"
    )

    static func substituteNamed(in source: String) -> String {
        guard let pattern else { return source }
        let full = NSRange(source.startIndex..<source.endIndex, in: source)
        var result = source
        for match in pattern.matches(in: source, range: full).reversed() {
            guard let whole = Range(match.range, in: source),
                  let nameRange = Range(match.range(at: 1), in: source) else { continue }
            let name = String(source[nameRange])
            guard !reserved.contains(name) else { continue }
            result.replaceSubrange(whole, with: named[name] ?? "")
        }
        return result
    }

    private static let numeric = try? NSRegularExpression(pattern: "&#(x?)([0-9A-Fa-f]+);")

    /// Used only on the fallback path, where no XML parser ever sees the text
    /// and the numeric and reserved entities have to be resolved here instead.
    static func decodeRemaining(in source: String) -> String {
        var text = substituteNamed(in: source)
        if let numeric {
            let full = NSRange(text.startIndex..<text.endIndex, in: text)
            for match in numeric.matches(in: text, range: full).reversed() {
                guard let whole = Range(match.range, in: text),
                      let prefix = Range(match.range(at: 1), in: text),
                      let digits = Range(match.range(at: 2), in: text) else { continue }
                let radix = text[prefix].isEmpty ? 10 : 16
                guard let value = UInt32(text[digits], radix: radix),
                      let scalar = Unicode.Scalar(value) else { continue }
                text.replaceSubrange(whole, with: String(Character(scalar)))
            }
        }
        for (entity, replacement) in [
            ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&apos;", "'"), ("&amp;", "&"),
        ] {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        return text
    }
}
