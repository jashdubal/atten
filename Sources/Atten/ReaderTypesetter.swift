import AppKit
import Foundation

/// How a page of a book is set: the type, the measure, and how much of it fits.
///
/// Everything here is a plain value so a chapter can be typeset away from the
/// main thread, which matters because a long chapter is a lot of text to break
/// into lines and the reader should not stop while it happens.
struct ReaderPageStyle: Equatable, Sendable {
    var fontSize: Double
    var pageSize: CGSize
    /// Read off the theme on the main actor and carried here as plain values,
    /// so setting the type never has to reach back for a colour.
    var bodyColor: AttenThemeColor
    var accentColor: AttenThemeColor
    /// A book justifies its text and hyphenates to avoid the gaps that
    /// justification otherwise leaves. A reader who finds that fussy can turn
    /// it off and read ragged-right.
    var isJustified: Bool

    var lineSpacing: Double { fontSize * 0.5 }
    /// A new paragraph is marked by an indent rather than by a blank line,
    /// which is how a book does it and is what lets a page fill.
    var paragraphIndent: Double { fontSize * 1.4 }
}

/// A chapter, broken into pages.
///
/// Unchecked because of the attributed string: it is built once, never written
/// to again, and only ever handed across as a finished thing.
struct ReaderChapterLayout: Equatable, @unchecked Sendable {
    /// The whole chapter, set: heading, then body.
    let text: NSAttributedString
    /// The characters on each page, in order.
    let pages: [NSRange]
    /// Where each paragraph of the chapter begins in `text`.
    ///
    /// Bookmarks, search results, and the place the reader stopped are all
    /// kept as paragraph numbers, because a paragraph is the same paragraph
    /// whatever size the window is. Pages are not: they are remade every time
    /// the type changes. This is how one is turned into the other.
    let paragraphStarts: [Int]

    static let empty = ReaderChapterLayout(
        text: NSAttributedString(),
        pages: [],
        paragraphStarts: []
    )

    var pageCount: Int { max(1, pages.count) }

    func range(ofPage index: Int) -> NSRange {
        pages.indices.contains(index) ? pages[index] : NSRange(location: 0, length: 0)
    }

    /// Which page a character falls on, for coming back to where the reader
    /// left off after the window was resized or the type made larger.
    /// The character a paragraph begins at, for opening a chapter at a
    /// bookmark or a search result.
    func character(ofParagraph index: Int) -> Int {
        paragraphStarts.indices.contains(index) ? paragraphStarts[index] : 0
    }

    /// The paragraph a character falls in, for writing down where the reader
    /// has got to in a form that survives the next resize.
    func paragraph(atCharacter location: Int) -> Int {
        guard !paragraphStarts.isEmpty else { return 0 }
        var result = 0
        for (index, start) in paragraphStarts.enumerated() where start <= location {
            result = index
        }
        return result
    }

    func page(containing location: Int) -> Int {
        pages.firstIndex { NSLocationInRange(location, $0) }
            ?? (location >= (pages.last.map { $0.location + $0.length } ?? 0)
                ? max(0, pages.count - 1)
                : 0)
    }
}

/// Breaks a chapter into pages that really are pages.
///
/// The reader used to guess: it counted words and called every two hundred and
/// fifty of them a page, then scrolled a column of paragraphs past the window.
/// That is a page number with nothing behind it — the text it named was never
/// laid out to fit anything. TextKit breaks the chapter into lines at the size
/// it will actually be drawn, and a page is however many of those lines fit.
enum ReaderTypesetter {
    /// Walks the whole chapter, so it is meant to be called off the main actor.
    nonisolated static func layout(
        chapterNumber: Int,
        title: String,
        paragraphs: [String],
        style: ReaderPageStyle
    ) -> ReaderChapterLayout {
        let (text, starts) = attributedChapter(
            number: chapterNumber,
            title: title,
            paragraphs: paragraphs,
            style: style
        )
        return ReaderChapterLayout(
            text: text,
            pages: breakIntoPages(text, style: style),
            paragraphStarts: starts
        )
    }

    // MARK: - Setting the type

    private nonisolated static func attributedChapter(
        number: Int,
        title: String,
        paragraphs: [String],
        style: ReaderPageStyle
    ) -> (NSAttributedString, [Int]) {
        let result = NSMutableAttributedString()
        var starts: [Int] = []

        let eyebrow = NSMutableParagraphStyle()
        eyebrow.paragraphSpacing = style.fontSize * 0.4
        result.append(NSAttributedString(
            string: "CHAPTER \(number)\n",
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: style.fontSize * 0.62, weight: .semibold),
                .foregroundColor: style.accentColor.nsColor,
                .kern: 1.6,
                .paragraphStyle: eyebrow,
            ]
        ))

        let heading = NSMutableParagraphStyle()
        heading.paragraphSpacing = style.fontSize * 1.6
        heading.lineSpacing = style.fontSize * 0.15
        result.append(NSAttributedString(
            string: "\(title)\n",
            attributes: [
                .font: serif(size: style.fontSize * 1.65, weight: .semibold),
                .foregroundColor: style.bodyColor.nsColor,
                .paragraphStyle: heading,
            ]
        ))

        let body = serif(size: style.fontSize, weight: .regular)
        for (index, paragraph) in paragraphs.enumerated() {
            starts.append(result.length)
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = style.lineSpacing
            paragraphStyle.alignment = style.isJustified ? .justified : .natural
            // Justified text without hyphenation opens rivers of white space
            // down the page; this is the value a book is set with.
            paragraphStyle.hyphenationFactor = style.isJustified ? 0.9 : 0
            // The first paragraph of a chapter is never indented. Every one
            // after it is, because that is what marks it as a new paragraph
            // once the blank lines between them are gone.
            paragraphStyle.firstLineHeadIndent = index == 0 ? 0 : style.paragraphIndent
            result.append(NSAttributedString(
                string: paragraph + (index == paragraphs.count - 1 ? "" : "\n"),
                attributes: [
                    .font: body,
                    .foregroundColor: style.bodyColor.nsColor,
                    .paragraphStyle: paragraphStyle,
                ]
            ))
        }
        return (result, starts)
    }

    nonisolated static func serif(size: Double, weight: NSFont.Weight) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.serif),
              let font = NSFont(descriptor: descriptor, size: size) else { return base }
        return font
    }

    // MARK: - Breaking it into pages

    private nonisolated static func breakIntoPages(
        _ text: NSAttributedString,
        style: ReaderPageStyle
    ) -> [NSRange] {
        guard text.length > 0, style.pageSize.width > 1, style.pageSize.height > 1 else {
            return []
        }
        let storage = NSTextStorage(attributedString: text)
        let manager = NSLayoutManager()
        // Nothing here is drawn; the glyphs only have to be placed.
        manager.usesFontLeading = true
        storage.addLayoutManager(manager)

        var pages: [NSRange] = []
        var consumed = 0
        // A chapter that somehow refuses to advance must not spin forever.
        while consumed < text.length, pages.count < 5_000 {
            let container = NSTextContainer(size: style.pageSize)
            container.lineFragmentPadding = 0
            container.maximumNumberOfLines = 0
            manager.addTextContainer(container)
            let glyphs = manager.glyphRange(for: container)
            guard glyphs.length > 0 else { break }
            let characters = manager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
            guard characters.length > 0 else { break }
            pages.append(characters)
            consumed = characters.location + characters.length
        }
        return pages.isEmpty ? [NSRange(location: 0, length: text.length)] : pages
    }
}
