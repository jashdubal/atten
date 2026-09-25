import Foundation

// MARK: - Position

/// Where a reader is in a book.
///
/// A PDF has real pages and an EPUB has none, so the same spot is a page in one
/// format and a paragraph in the other. Both carry the chapter, which is what
/// the table of contents, the page readout, and narration all work in.
public struct ReadingLocation: Codable, Equatable, Hashable, Sendable {
    public var chapterIndex: Int
    /// Paragraph within the chapter, for a book with no fixed pages.
    public var paragraphIndex: Int
    /// Page within the document, for a book that has them. nil for EPUBs.
    public var pageIndex: Int?

    public init(chapterIndex: Int, paragraphIndex: Int = 0, pageIndex: Int? = nil) {
        self.chapterIndex = chapterIndex
        self.paragraphIndex = paragraphIndex
        self.pageIndex = pageIndex
    }

    /// The same spot: the same page of a PDF, or the same paragraph of the same
    /// chapter of an EPUB. Used to tell a bookmarked spot from an unmarked one.
    public func isAt(_ other: ReadingLocation) -> Bool {
        if let pageIndex, let otherPage = other.pageIndex { return pageIndex == otherPage }
        return chapterIndex == other.chapterIndex && paragraphIndex == other.paragraphIndex
    }

    /// Reading order, so a list of bookmarks reads the way the book does
    /// rather than the order they happened to be made in.
    public func precedes(_ other: ReadingLocation) -> Bool {
        if let pageIndex, let otherPage = other.pageIndex, pageIndex != otherPage {
            return pageIndex < otherPage
        }
        if chapterIndex != other.chapterIndex { return chapterIndex < other.chapterIndex }
        return paragraphIndex < other.paragraphIndex
    }
}

/// A place in a book the reader marked to come back to.
public struct Bookmark: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var location: ReadingLocation
    /// The words the mark sits on. A list of page numbers says nothing about
    /// why a reader stopped there; the sentence does.
    public var excerpt: String
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        location: ReadingLocation,
        excerpt: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.location = location
        self.excerpt = excerpt
        self.createdAt = createdAt
    }
}

// MARK: - Chapter text

extension BookChapter {
    /// The chapter in the pieces a reader moves through. Narration takes the
    /// whole text in one go; reading needs somewhere to scroll to, to search
    /// in, and to drop a bookmark on.
    public var paragraphs: [String] {
        text.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    public var wordCount: Int { ListenEstimator.wordCount(text) }
}

extension BookRecord {
    /// The chapter a page of a PDF belongs to, so the contents can follow the
    /// reader as they scroll rather than only when they click a chapter.
    public func chapterIndex(forPage page: Int) -> Int {
        var result = 0
        for (index, chapter) in chapters.enumerated() {
            guard let start = chapter.pageIndex, start <= page else { continue }
            result = index
        }
        return result
    }
}

// MARK: - Pages

/// Page numbers for a book, and where each chapter begins and ends in them.
///
/// A PDF already has pages, so its chapter marks are all this needs. An EPUB
/// has none, so Atten lays one out every `wordsPerPage` words: a page count
/// taken from the window size would change every time the window was resized
/// or the type made larger, and "page 40 of 310" would mean nothing.
public struct ReaderPagination: Equatable, Sendable {
    /// About what a paperback page holds.
    public static let wordsPerPage = 250

    /// The first page of every chapter, 1-based, with one extra entry holding
    /// the page after the last so every chapter has an end.
    private let starts: [Int]

    private init(starts: [Int]) {
        self.starts = starts
    }

    public static let empty = ReaderPagination(starts: [1, 2])

    public init(pdfChapterPageIndexes pages: [Int?], pageCount: Int) {
        let total = max(1, pageCount)
        guard !pages.isEmpty else {
            self.init(starts: [1, total + 1])
            return
        }
        var starts: [Int] = []
        var previous = 1
        for page in pages {
            // Chapters never run backwards, whatever the outline claims, and
            // never begin past the end of the file.
            let start = min(total, max(previous, (page ?? previous - 1) + 1))
            starts.append(start)
            previous = start
        }
        starts.append(total + 1)
        self.init(starts: starts)
    }

    public init(epubChapterWordCounts counts: [Int]) {
        guard !counts.isEmpty else {
            self.init(starts: [1, 2])
            return
        }
        var starts: [Int] = []
        var page = 1
        for count in counts {
            starts.append(page)
            // Even a one-line chapter is a page; otherwise two chapters share
            // a number and the readout jumps about.
            page += max(1, Int((Double(max(0, count)) / Double(Self.wordsPerPage)).rounded(.up)))
        }
        starts.append(page)
        self.init(starts: starts)
    }

    public var pageCount: Int { max(1, (starts.last ?? 2) - 1) }

    public func startPage(ofChapter index: Int) -> Int {
        guard starts.indices.contains(index) else { return 1 }
        return starts[index]
    }

    public func endPage(ofChapter index: Int) -> Int {
        guard index + 1 < starts.count else { return pageCount }
        return max(starts[index], starts[index + 1] - 1)
    }

    /// The page a spot inside an EPUB chapter falls on.
    public func page(chapter index: Int, wordsIntoChapter words: Int) -> Int {
        startPage(ofChapter: index) + max(0, words) / Self.wordsPerPage
    }

    /// How much of the book is behind the reader, for the progress line.
    public func fraction(ofPage page: Int) -> Double {
        min(1, max(0, Double(page) / Double(pageCount)))
    }
}

// MARK: - Search

/// One match, with enough of the sentence around it to recognise the passage
/// without opening it.
public struct BookSearchHit: Identifiable, Equatable, Sendable {
    public let id: String
    public let chapterIndex: Int
    public let paragraphIndex: Int
    public let before: String
    public let match: String
    public let after: String

    public init(
        id: String,
        chapterIndex: Int,
        paragraphIndex: Int,
        before: String,
        match: String,
        after: String
    ) {
        self.id = id
        self.chapterIndex = chapterIndex
        self.paragraphIndex = paragraphIndex
        self.before = before
        self.match = match
        self.after = after
    }

    public var snippet: String { before + match + after }
}

public enum BookSearch {
    /// Characters kept either side of a match. Enough for the phrase, short
    /// enough that a result stays one line in a narrow panel.
    public static let contextLength = 44

    /// Every match in reading order. Walks the whole book, so it is meant to be
    /// called off the main actor.
    public static func run(
        _ rawQuery: String,
        in chapters: [BookChapter],
        limit: Int = 300
    ) -> [BookSearchHit] {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, limit > 0 else { return [] }

        var hits: [BookSearchHit] = []
        for (chapterIndex, chapter) in chapters.enumerated() {
            for (paragraphIndex, paragraph) in chapter.paragraphs.enumerated() {
                var start = paragraph.startIndex
                while start < paragraph.endIndex, let range = paragraph.range(
                    of: query,
                    options: [.caseInsensitive, .diacriticInsensitive],
                    range: start..<paragraph.endIndex
                ) {
                    // Folding accents away can leave a query that matches
                    // nothing at all, such as a lone combining mark. Such a
                    // match cannot advance, so the paragraph is done.
                    guard !range.isEmpty else { break }
                    hits.append(hit(
                        in: paragraph,
                        range: range,
                        chapterIndex: chapterIndex,
                        paragraphIndex: paragraphIndex
                    ))
                    if hits.count >= limit { return hits }
                    start = range.upperBound
                }
            }
        }
        return hits
    }

    private static func hit(
        in paragraph: String,
        range: Range<String.Index>,
        chapterIndex: Int,
        paragraphIndex: Int
    ) -> BookSearchHit {
        let leading = paragraph[paragraph.startIndex..<range.lowerBound]
        let trailing = paragraph[range.upperBound...]
        let before = leading.count > contextLength
            ? "…" + String(leading.suffix(contextLength))
            : String(leading)
        let after = trailing.count > contextLength
            ? String(trailing.prefix(contextLength)) + "…"
            : String(trailing)
        let offset = paragraph.distance(from: paragraph.startIndex, to: range.lowerBound)
        return BookSearchHit(
            id: "\(chapterIndex).\(paragraphIndex).\(offset)",
            chapterIndex: chapterIndex,
            paragraphIndex: paragraphIndex,
            before: before,
            match: String(paragraph[range]),
            after: after
        )
    }
}
