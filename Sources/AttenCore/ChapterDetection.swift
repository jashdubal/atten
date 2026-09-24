import Foundation

/// How text written or pasted in Create is divided into chapters when it is
/// narrated. A chapter is the unit narration checkpoints and reports progress
/// in, so this is the one structural choice a draft has.
public enum ChapterDetection: String, CaseIterable, Identifiable, Sendable {
    /// At headings when the text has them, otherwise in even parts — exactly
    /// how an imported document is divided.
    case auto
    /// At headings only; text without them stays one chapter.
    case headings
    /// One chapter, however long.
    case none

    public var id: Self { self }

    public var title: String {
        switch self {
        case .auto: "Auto"
        case .headings: "Headings"
        case .none: "None"
        }
    }

    /// The chapters `text` is narrated as. When the text is not divided, its
    /// one chapter is named `title`.
    public func chapters(in text: String, title: String) -> [DocumentChapter] {
        let whole = [DocumentChapter(title: title, text: Self.unmarked(text))]
        switch self {
        case .none:
            return whole
        case .headings:
            let sections = FlatDocumentExtractor.sections(in: text)
            return sections.count > 1 ? sections : whole
        case .auto:
            let sections = FlatDocumentExtractor.sections(in: text)
            if sections.count > 1 { return sections }
            let parts = FlatDocumentExtractor.chunk(DocumentText.normalize(Self.unmarked(text)))
            return parts.count > 1 ? parts : whole
        }
    }

    /// The text of the first line that is a Markdown heading, if the text
    /// opens with one — what a pasted document most likely calls itself.
    public static func openingHeading(in text: String) -> String? {
        let first = text.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init)
        return first.flatMap(FlatDocumentExtractor.headingText(in:))
    }

    /// Heading marks divide text; they are not read aloud.
    static func unmarked(_ text: String) -> String {
        text.components(separatedBy: "\n")
            .map { FlatDocumentExtractor.headingText(in: $0) ?? $0 }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// How far narration has reached through a draft, for showing it as it
/// happens. Narration reports words spoken within the chapter it is on; this
/// finds where each chapter begins in the text as written, so the count lands
/// on the right word even though chapter text has been normalized and had
/// its headings taken out.
public struct SpokenExtent: Equatable, Sendable {
    /// Words of `text` spoken so far.
    public let words: Int
    /// Words in `text` altogether.
    public let totalWords: Int
    /// UTF-16 offset in `text` just past the last word spoken — the unit
    /// `NSTextView` ranges are in.
    public let utf16Offset: Int

    public var fraction: Double { totalWords > 0 ? min(1, Double(words) / Double(totalWords)) : 0 }

    public init(text: String, chapters: [String], chapterIndex: Int, spokenWords: Int) {
        let tokens = text.split(whereSeparator: \.isWhitespace)
            .filter { !$0.allSatisfy { $0 == "#" } }
        var cursor = 0
        for index in chapters.indices where index <= chapterIndex {
            let chapterWords = chapters[index].split(whereSeparator: \.isWhitespace)
            // Matched on a few opening words, which normalizing never changes.
            let opening = Array(chapterWords.prefix(4))
            if !opening.isEmpty, cursor <= tokens.count - opening.count,
               let start = (cursor...(tokens.count - opening.count)).first(where: { position in
                   opening.indices.allSatisfy { tokens[position + $0] == opening[$0] }
               }) {
                cursor = start
            }
            cursor += index < chapterIndex ? chapterWords.count : min(spokenWords, chapterWords.count)
        }
        words = min(cursor, tokens.count)
        totalWords = tokens.count
        utf16Offset = words > 0 ? tokens[words - 1].endIndex.utf16Offset(in: text) : 0
    }
}
