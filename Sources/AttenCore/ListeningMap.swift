import Foundation

/// Where each chapter sits in a recording, and how a moment of it and a place
/// in the text stand for each other.
///
/// The Reader marks a paragraph; the player hears a moment. A bookmark is kept
/// as the paragraph, so the one list serves both: the player finds when that
/// paragraph is spoken, and a mark made while listening lands on the
/// paragraph the sentence is in.
public struct ListeningMap: Equatable, Sendable {
    public struct Chapter: Equatable, Sendable {
        /// The chapter's place in the book, which is what a `ReadingLocation`
        /// counts in.
        public let index: Int
        public let title: String
        public let text: String
        /// The PDF page the chapter begins on, when it has one.
        public let pageIndex: Int?
        public let start: Double
        public let end: Double

        public init(index: Int, title: String, text: String, pageIndex: Int?, start: Double, end: Double) {
            self.index = index
            self.title = title
            self.text = text
            self.pageIndex = pageIndex
            self.start = start
            self.end = end
        }

        public var duration: Double { max(0, end - start) }

        /// Split only when asked: the map is built on every tick of the
        /// clock, and a whole book's paragraphs are not cheap.
        public var paragraphs: [String] { BookChapter(title: title, text: text).paragraphs }
    }

    public let chapters: [Chapter]

    public init(chapters: [Chapter]) {
        self.chapters = chapters
    }

    /// A book played as one recording, each chapter on its own stretch of it.
    public init(book: BookRecord, duration: Double) {
        let timeline = book.playbackChapters
        self.init(chapters: timeline.enumerated().map { index, chapter in
            Chapter(
                index: index, title: chapter.title, text: chapter.text,
                pageIndex: chapter.pageIndex,
                start: chapter.startTime ?? 0,
                end: chapter.endTime ?? (index + 1 < timeline.count ? timeline[index + 1].startTime ?? duration : duration)
            )
        })
    }

    /// One chapter narrated to a file of its own.
    public init(chapter index: Int, of book: BookRecord, duration: Double) {
        guard book.chapters.indices.contains(index) else {
            self.init(chapters: [])
            return
        }
        let chapter = book.chapters[index]
        self.init(chapters: [Chapter(
            index: index, title: chapter.title, text: chapter.text,
            pageIndex: chapter.pageIndex, start: 0, end: duration
        )])
    }

    // MARK: - Chapters

    /// The chapter playing at `time`. A chapter owns its first moment and not
    /// its last, which belongs to the next one; before the first chapter is
    /// still the first, and past the end is still the last.
    public func chapterIndex(at time: Double) -> Int? {
        guard !chapters.isEmpty else { return nil }
        var lower = 0, upper = chapters.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if chapters[middle].start <= time { lower = middle + 1 } else { upper = middle }
        }
        return max(0, lower - 1)
    }

    // MARK: - Bookmarks

    /// The paragraph being spoken at `time`. With the sentence spoken there,
    /// the paragraph holding it; without, the one as far into the chapter's
    /// text as `time` is into its recording.
    public func location(at time: Double, sentence: String? = nil) -> ReadingLocation? {
        guard let position = chapterIndex(at: time) else { return nil }
        let chapter = chapters[position]
        let paragraphs = chapter.paragraphs
        let estimate = Self.paragraph(
            atFraction: chapter.duration > 0 ? (time - chapter.start) / chapter.duration : 0,
            of: paragraphs
        )
        var paragraph = estimate
        if let sentence = sentence.map(Self.normalized), !sentence.isEmpty {
            let matches = paragraphs.indices.filter { Self.normalized(paragraphs[$0]).contains(sentence) }
            paragraph = matches.min { abs($0 - estimate) < abs($1 - estimate) } ?? estimate
        }
        return ReadingLocation(chapterIndex: chapter.index, paragraphIndex: paragraph)
    }

    /// When `location` is spoken. Where the script has the words, that is the
    /// start of the sentence the excerpt begins with, or of the paragraph's
    /// sentence nearest the estimate; otherwise it is an estimate from how far
    /// into the chapter's text, or its pages, the place is.
    public func time(
        of location: ReadingLocation,
        excerpt: String? = nil,
        script: ReadAlongScript = .empty
    ) -> Double? {
        guard let position = chapters.lastIndex(where: { $0.index == location.chapterIndex }) else { return nil }
        let chapter = chapters[position]
        let paragraphs = chapter.paragraphs
        let estimate = chapter.start + chapter.duration
            * fraction(of: location, in: chapter, paragraphs: paragraphs, position: position)

        // A PDF's paragraphs are not what its reader counts, so its whole
        // chapter is searched; an EPUB's paragraph is exact.
        let region = location.pageIndex == nil && paragraphs.indices.contains(location.paragraphIndex)
            ? Self.normalized(paragraphs[location.paragraphIndex])
            : nil
        let candidates = script.sentences.filter { sentence in
            sentence.start >= chapter.start && sentence.start < max(chapter.end, chapter.start + 0.001)
                && (region?.contains(Self.normalized(sentence.text)) ?? true)
        }
        let wanted = excerpt.map(Self.normalized) ?? ""
        let preferred = candidates.filter {
            let text = Self.normalized($0.text)
            return !text.isEmpty && wanted.hasPrefix(text)
        }
        let pool = preferred.isEmpty ? (region == nil ? [] : candidates) : preferred
        return pool.min { abs($0.start - estimate) < abs($1.start - estimate) }?.start ?? estimate
    }

    /// How far into the chapter `location` is, from 0 to 1.
    private func fraction(
        of location: ReadingLocation, in chapter: Chapter, paragraphs: [String], position: Int
    ) -> Double {
        if let page = location.pageIndex, let first = chapter.pageIndex,
           chapters.indices.contains(position + 1), let next = chapters[position + 1].pageIndex, next > first {
            return min(1, max(0, Double(page - first) / Double(next - first)))
        }
        let lengths = paragraphs.map(\.count)
        let total = lengths.reduce(0, +)
        guard total > 0 else { return 0 }
        let before = lengths.prefix(max(0, min(location.paragraphIndex, lengths.count))).reduce(0, +)
        return Double(before) / Double(total)
    }

    private static func paragraph(atFraction fraction: Double, of paragraphs: [String]) -> Int {
        let lengths = paragraphs.map(\.count)
        let total = lengths.reduce(0, +)
        guard total > 0 else { return 0 }
        let target = min(1, max(0, fraction)) * Double(total)
        var consumed = 0
        for (index, length) in lengths.enumerated() {
            consumed += length
            if Double(consumed) > target { return index }
        }
        return lengths.count - 1
    }

    /// Text compared the way it reads, whatever line breaks and runs of
    /// spaces it arrived with.
    public static func normalized(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
