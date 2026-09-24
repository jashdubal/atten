import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// Reads anything that is one flat run of text: a note, a paper, a report.
///
/// A book arrives already divided — an EPUB has a spine, a PDF has an outline
/// — but a report is one file with headings in it, and those headings are the
/// only division it has. Finding them is what makes it readable a piece at a
/// time and narratable a piece at a time, which is the whole reason the reader
/// works in chapters at all.
enum FlatDocumentExtractor {
    /// Words per section when a document has no headings to divide it by.
    /// Long enough to be worth generating narration for in one go, short
    /// enough that one failed generation is cheap to retry.
    private static let fallbackSectionLength = 900

    static func extract(from url: URL) throws -> ExtractedDocument {
        let name = url.deletingPathExtension().lastPathComponent
        let raw = try read(url, name: name)
        let text = DocumentText.normalize(raw)
        guard !text.isEmpty else { throw DocumentImportError.noText(name) }

        let (title, body) = titleAndBody(in: text, fallback: name)
        let sections = divide(body)
        guard !sections.isEmpty else { throw DocumentImportError.noText(name) }
        return ExtractedDocument(title: title, author: nil, chapters: sections)
    }

    // MARK: - Getting the text out

    private static func read(_ url: URL, name: String) throws -> String {
        switch url.pathExtension.lowercased() {
        case "txt", "text", "md", "markdown":
            guard let text = plainText(at: url) else {
                throw DocumentImportError.unreadable(name)
            }
            return stripMarkdown(text)
        default:
            #if canImport(AppKit)
            // RTF, Word and HTML are all formats AppKit already knows how to
            // read. Taking the plain string out of what it returns loses the
            // styling, which is the right thing to lose: the page is set in
            // the reader's chosen face, not the document's.
            guard let attributed = try? NSAttributedString(
                url: url,
                options: [.documentType: documentType(for: url)],
                documentAttributes: nil
            ) else {
                throw DocumentImportError.unreadable(name)
            }
            return attributed.string
            #else
            throw DocumentImportError.unsupportedFormat(url.pathExtension)
            #endif
        }
    }

    #if canImport(AppKit)
    private static func documentType(for url: URL) -> NSAttributedString.DocumentType {
        switch url.pathExtension.lowercased() {
        case "rtf": .rtf
        case "rtfd": .rtfd
        case "html", "htm": .html
        // Word is read through the same reader that opens it in TextEdit.
        default: .officeOpenXML
        }
    }
    #endif

    /// Text files carry no encoding with them, so the encoding has to be
    /// guessed. UTF-8 first because that is what everything writes now; the
    /// rest is for files that predate that being true.
    private static func plainText(at url: URL) -> String? {
        if let text = try? String(contentsOf: url, encoding: .utf8) { return text }
        var encoding = String.Encoding.utf8
        return try? String(contentsOf: url, usedEncoding: &encoding)
    }

    /// Markdown is meant to be readable as it stands, so this takes off the
    /// marks that are not words rather than rendering it. What is left is what
    /// someone reading the file in a plain editor would read aloud — with the
    /// heading hashes kept, because those are the document's divisions.
    private static func stripMarkdown(_ text: String) -> String {
        var result = text
        for (pattern, replacement) in [
            // Fenced code is not prose and cannot be read aloud.
            ("(?m)^```[\\s\\S]*?^```\\s*$", ""),
            ("!\\[[^\\]]*\\]\\([^)]*\\)", ""),
            ("\\[([^\\]]+)\\]\\([^)]*\\)", "$1"),
            ("(?m)^[ \\t]*>[ \\t]?", ""),
            ("(?m)^[ \\t]*[-*+][ \\t]+", "• "),
            ("`([^`]+)`", "$1"),
            ("\\*\\*([^*]+)\\*\\*", "$1"),
            ("(?<![*\\w])\\*([^*]+)\\*(?!\\w)", "$1"),
            ("(?m)^[ \\t]*([-*_])[ \\t]*(\\1[ \\t]*){2,}$", ""),
        ] {
            result = result.replacingOccurrences(
                of: pattern, with: replacement, options: .regularExpression
            )
        }
        return result
    }

    // MARK: - Finding its shape

    /// The document's own title, if its first line is one. A report usually
    /// opens with its title; a note usually does not, and then the file name
    /// is the best name anyone has given it.
    private static func titleAndBody(in text: String, fallback: String) -> (String, String) {
        let lines = text.components(separatedBy: "\n")
        guard let first = lines.first else { return (fallback, text) }
        let heading = headingText(in: first)
        guard let heading, headingLevel(of: first) <= 1 else { return (fallback, text) }
        return (heading, lines.dropFirst().joined(separator: "\n"))
    }

    private static func divide(_ body: String) -> [DocumentChapter] {
        let divided = sections(in: body)
        // One heading at the top is not a division; it is a title. A document
        // with nothing to divide it by is cut into even pieces instead, the
        // way a PDF with no outline is.
        return divided.count > 1 ? divided : chunk(DocumentText.normalize(body))
    }

    /// The text cut at its headings, each heading naming the section under it.
    static func sections(in body: String) -> [DocumentChapter] {
        let lines = body.components(separatedBy: "\n")
        var sections: [(title: String?, lines: [String])] = []
        for line in lines {
            if let heading = headingText(in: line) {
                sections.append((heading, []))
            } else if sections.isEmpty {
                sections.append((nil, [line]))
            } else {
                sections[sections.count - 1].lines.append(line)
            }
        }

        return sections.compactMap { section -> DocumentChapter? in
            let text = DocumentText.normalize(section.lines.joined(separator: "\n"))
            guard !text.isEmpty else { return nil }
            return DocumentChapter(title: section.title ?? "Beginning", text: text)
        }
    }

    /// Splits on paragraph boundaries so a section never begins mid-sentence.
    static func chunk(_ text: String) -> [DocumentChapter] {
        guard !text.isEmpty else { return [] }
        let paragraphs = text.components(separatedBy: "\n").filter { !$0.isEmpty }
        guard !paragraphs.isEmpty else { return [] }

        var sections: [DocumentChapter] = []
        var current: [String] = []
        var words = 0
        for paragraph in paragraphs {
            current.append(paragraph)
            words += paragraph.split(separator: " ").count
            if words >= fallbackSectionLength {
                sections.append(DocumentChapter(
                    title: "Part \(sections.count + 1)",
                    text: current.joined(separator: "\n")
                ))
                current = []
                words = 0
            }
        }
        if !current.isEmpty {
            sections.append(DocumentChapter(
                title: sections.isEmpty ? "Beginning" : "Part \(sections.count + 1)",
                text: current.joined(separator: "\n")
            ))
        }
        return sections
    }

    /// How deep a Markdown heading is, or a large number for a line that is
    /// not one, so callers can compare without unwrapping.
    private static func headingLevel(of line: String) -> Int {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let hashes = trimmed.prefix { $0 == "#" }.count
        guard hashes >= 1, hashes <= 6 else { return .max }
        guard trimmed.dropFirst(hashes).first == " " else { return .max }
        return hashes
    }

    static func headingText(in line: String) -> String? {
        guard headingLevel(of: line) != .max else { return nil }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let text = trimmed
            .drop { $0 == "#" }
            .trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : text
    }
}
