import AppKit
import AttenCore
import PDFKit
import SwiftUI

// MARK: - Results

/// One search result, from either kind of book. A PDF is searched by PDFKit so
/// the match can be lit up on the real page; an EPUB is searched in the text
/// Atten extracted, which is the same text it reads aloud.
struct ReaderHit: Identifiable, Equatable, Sendable {
    let id: String
    let chapterIndex: Int
    let before: String
    let match: String
    let after: String
    /// Paragraph of the chapter, for an EPUB.
    let paragraphIndex: Int?
    /// Page of the document, for a PDF, with the match's place on it.
    let pageIndex: Int?
    let matchLocation: Int
    let matchLength: Int

    init(_ hit: BookSearchHit) {
        id = hit.id
        chapterIndex = hit.chapterIndex
        before = hit.before
        match = hit.match
        after = hit.after
        paragraphIndex = hit.paragraphIndex
        pageIndex = nil
        matchLocation = 0
        matchLength = 0
    }

    init(
        id: String,
        chapterIndex: Int,
        before: String,
        match: String,
        after: String,
        pageIndex: Int,
        matchLocation: Int,
        matchLength: Int
    ) {
        self.id = id
        self.chapterIndex = chapterIndex
        self.before = before
        self.match = match
        self.after = after
        self.paragraphIndex = nil
        self.pageIndex = pageIndex
        self.matchLocation = matchLocation
        self.matchLength = matchLength
    }
}

/// Searches the PDF itself rather than the extracted text, so a result carries
/// the page and the exact characters on it. Walks the whole document, so it is
/// meant to be called off the main actor.
enum ReaderPDFSearch {
    static func run(
        _ query: String,
        in url: URL,
        book: BookRecord,
        limit: Int = 300
    ) -> [ReaderHit] {
        guard let document = PDFDocument(url: url), !document.isLocked else { return [] }
        let found = document.findString(query, withOptions: [.caseInsensitive, .diacriticInsensitive])

        var hits: [ReaderHit] = []
        for selection in found.prefix(limit) {
            guard let page = selection.pages.first,
                  selection.numberOfTextRanges(on: page) > 0 else { continue }
            let pageIndex = document.index(for: page)
            guard pageIndex >= 0, pageIndex < document.pageCount else { continue }
            let range = selection.range(at: 0, on: page)
            let text = (page.string ?? "") as NSString
            guard range.location + range.length <= text.length else { continue }

            let start = max(0, range.location - BookSearch.contextLength)
            let end = min(text.length, range.location + range.length + BookSearch.contextLength)
            let before = text.substring(with: NSRange(location: start, length: range.location - start))
            let after = text.substring(with: NSRange(
                location: range.location + range.length,
                length: end - range.location - range.length
            ))
            hits.append(ReaderHit(
                id: "\(pageIndex).\(range.location)",
                chapterIndex: book.chapterIndex(forPage: pageIndex),
                before: (start > 0 ? "…" : "") + tidy(before),
                match: text.substring(with: range),
                after: tidy(after) + (end < text.length ? "…" : ""),
                pageIndex: pageIndex,
                matchLocation: range.location,
                matchLength: range.length
            ))
        }
        return hits
    }

    /// Page text arrives wrapped at the width it was typeset for; a snippet is
    /// one line, so the wrapping has to go.
    private static func tidy(_ text: String) -> String {
        text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
}

// MARK: - PDF

/// A page the reader asked to be shown, optionally with the match to light up.
/// Carrying an id lets the view tell a jump it has not made yet from the page
/// the reader has simply scrolled to, so scrolling is never fought.
struct ReaderPDFJump: Equatable {
    let id = UUID()
    let page: Int
    var matchLocation: Int?
    var matchLength: Int?
}

/// What the reader asked to happen to the zoom. Carries an id for the same
/// reason a jump does: asking to zoom in twice is two steps, not one.
struct ReaderPDFZoom: Equatable {
    let id = UUID()
    let step: Step

    enum Step: Equatable {
        case larger
        case smaller
        /// Back to the whole page in the window, which is where a PDF starts.
        case fit
    }
}

/// PDFKit gives the real page, with its own scrolling, zoom, and selection.
struct ReaderPDFView: NSViewRepresentable {
    let url: URL
    let jump: ReaderPDFJump?
    let zoom: ReaderPDFZoom?
    let highlights: [ReaderHit]
    /// Passed in so a change of page colour reaches AppKit, which keeps the
    /// colour it was last handed.
    let palette: ReaderPagePalette
    /// A PDF is already typeset, so the three view modes are three ways of
    /// arranging pages it already has — which PDFKit does natively, and far
    /// better than anything built on top of it would.
    let mode: ReaderViewMode
    let onOpen: (Int) -> Void
    let onPageChange: (Int, String) -> Void

    @MainActor
    final class Coordinator {
        let observer = PageObserver()
        var openedURL: URL?
        var handledJumpID: UUID?
        var highlightKey: String?
        var appliedPalette: ReaderPagePalette?
        var appliedMode: ReaderViewMode?
        var handledZoomID: UUID?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = NSColor(hex: palette.background)
        context.coordinator.observer.watch(view)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        let coordinator = context.coordinator
        coordinator.observer.report = onPageChange

        if coordinator.appliedMode != mode {
            coordinator.appliedMode = mode
            switch mode {
            case .page:
                view.displayMode = .singlePage
                view.displaysPageBreaks = true
            case .spread:
                view.displayMode = .twoUp
                view.displaysAsBook = true
                view.displaysPageBreaks = true
            case .scroll:
                view.displayMode = .singlePageContinuous
                view.displayDirection = .vertical
                view.displaysPageBreaks = true
            }
            // Only a spread is a book with a spine. Left set, it offsets the
            // first page of every other arrangement too.
            if mode != .spread { view.displaysAsBook = false }
            // Re-fitting after the arrangement changes is what makes a page
            // actually fill the window rather than keeping the zoom it had.
            view.autoScales = true
        }

        if coordinator.appliedPalette != palette {
            coordinator.appliedPalette = palette
            view.backgroundColor = NSColor(hex: palette.background)
            coordinator.highlightKey = nil
        }

        if coordinator.openedURL != url {
            view.document = PDFDocument(url: url)
            coordinator.openedURL = url
            coordinator.handledJumpID = nil
            coordinator.highlightKey = nil
            let pageCount = view.document?.pageCount ?? 0
            // Answering during the update would be changing state while the
            // view is being built, so the reader hears about it just after.
            Task { @MainActor in onOpen(pageCount) }
        }
        guard let document = view.document else { return }

        let key = highlightKey
        if coordinator.highlightKey != key {
            coordinator.highlightKey = key
            view.highlightedSelections = highlightSelections(in: document)
        }

        if let jump, coordinator.handledJumpID != jump.id {
            coordinator.handledJumpID = jump.id
            reveal(jump, in: view, document: document)
        }

        if let zoom, coordinator.handledZoomID != zoom.id {
            coordinator.handledZoomID = zoom.id
            apply(zoom, to: view)
        }
    }

    /// Zooming has to turn auto-scaling off, or PDFKit re-fits the page on the
    /// next relayout and the zoom is silently undone. Fitting turns it back
    /// on, so the page keeps filling the window as it is resized.
    private func apply(_ zoom: ReaderPDFZoom, to view: PDFView) {
        switch zoom.step {
        case .fit:
            view.autoScales = true
        case .larger, .smaller:
            let factor = zoom.step == .larger ? Self.zoomStep : 1 / Self.zoomStep
            view.autoScales = false
            view.scaleFactor = min(
                max(view.minScaleFactor, view.scaleFactor * factor),
                view.maxScaleFactor
            )
        }
    }

    /// A quarter again each press: enough to be worth the press, small enough
    /// that finding the size you wanted takes a press or two rather than a
    /// hunt back and forth.
    private static let zoomStep: CGFloat = 1.25

    /// Rebuilding a few hundred selections on every redraw would stutter, so
    /// the set is only rebuilt when the results themselves changed.
    private var highlightKey: String {
        "\(highlights.count)|\(highlights.first?.id ?? "")|\(highlights.last?.id ?? "")"
    }

    private func highlightSelections(in document: PDFDocument) -> [PDFSelection] {
        highlights.prefix(200).compactMap { hit -> PDFSelection? in
            guard let pageIndex = hit.pageIndex,
                  let page = document.page(at: pageIndex),
                  let selection = page.selection(
                      for: NSRange(location: hit.matchLocation, length: hit.matchLength)
                  ) else { return nil }
            selection.color = NSColor(hex: palette.highlight)
            return selection
        }
    }

    private func reveal(_ jump: ReaderPDFJump, in view: PDFView, document: PDFDocument) {
        let index = min(max(0, jump.page), max(0, document.pageCount - 1))
        guard let page = document.page(at: index) else { return }
        if let location = jump.matchLocation, let length = jump.matchLength,
           let selection = page.selection(for: NSRange(location: location, length: length)) {
            view.setCurrentSelection(selection, animate: true)
            view.go(to: selection)
        } else {
            view.go(to: page)
        }
    }

    /// Reports the page the reader scrolled to, so the contents, the page
    /// number, and the bookmark button all follow along.
    @MainActor
    final class PageObserver: NSObject {
        var report: (Int, String) -> Void = { _, _ in }

        func watch(_ view: PDFView) {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(pageChanged(_:)),
                name: .PDFViewPageChanged,
                object: view
            )
        }

        @objc private func pageChanged(_ note: Notification) {
            guard let view = note.object as? PDFView,
                  let page = view.currentPage,
                  let document = view.document else { return }
            let index = document.index(for: page)
            guard index >= 0, index < document.pageCount else { return }
            report(index, String((page.string ?? "").prefix(240)))
        }

        deinit { NotificationCenter.default.removeObserver(self) }
    }
}

// MARK: - EPUB

/// Identifies a paragraph within the whole book, so scrolling to one in a
/// different chapter is always a move even when the numbers happen to match.
struct ReaderParagraphID: Hashable {
    let chapter: Int
    let index: Int
}

/// An EPUB has no pages of its own, so this is the page: one column of serif
/// text at a comfortable measure, on paper.
struct ReaderTextView: View {
    let chapterIndex: Int
    let chapterNumber: Int
    /// A book has chapters, a report has sections.
    let sectionNoun: String
    let title: String
    let paragraphs: [String]
    let fontSize: Double
    /// The face the column is set in, the same one the paged reader uses.
    let font: ReaderFont
    let query: String
    let isFocusMode: Bool
    let palette: ReaderPagePalette
    @Binding var position: ReaderParagraphID?

    @State private var hovered: ReaderParagraphID?

    private struct Line: Identifiable {
        let id: ReaderParagraphID
        let text: String
    }

    private var lines: [Line] {
        paragraphs.enumerated().map {
            Line(id: ReaderParagraphID(chapter: chapterIndex, index: $0.offset), text: $0.element)
        }
    }

    /// Roughly eighty characters a line — the long end of what still reads as
    /// a column — and it grows with the type rather than leaving long lines
    /// behind. The paged reader is set to the same measure, so switching
    /// between scrolling and pages does not reflow the book into a different
    /// shape.
    private var measure: CGFloat { fontSize * 38 }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: fontSize * 0.9) {
                opener
                ForEach(lines) { line in
                    paragraph(line)
                }
                // Somewhere for the last paragraph to sit other than the very
                // bottom edge of the window.
                Color.clear.frame(height: 200)
            }
            .scrollTargetLayout()
            .frame(maxWidth: measure, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, AttenSpacing.md)
            .padding(.top, AttenSpacing.xxl)
        }
        .scrollPosition(id: $position, anchor: .top)
        .background(Color(hex: palette.background))
        .onHover { if !$0 { hovered = nil } }
    }

    private var eyebrow: String { "\(sectionNoun) \(chapterNumber)" }

    private var opener: some View {
        VStack(alignment: .leading, spacing: AttenSpacing.sm) {
            Text(eyebrow.uppercased())
                .font(Font(ReaderTypesetter.face(font, size: fontSize * 0.66, weight: .medium)))
                .tracking(fontSize * 0.13)
                .foregroundStyle(Color(hex: palette.inkMuted))
            Text(title)
                .font(Font(ReaderTypesetter.face(font, size: fontSize * 1.95, weight: .regular)))
                .foregroundStyle(Color(hex: palette.ink))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, AttenSpacing.md)
        .accessibilityAddTraits(.isHeader)
    }

    private func paragraph(_ line: Line) -> some View {
        Text(highlighted(line.text))
            .font(Font(ReaderTypesetter.face(font, size: fontSize, weight: .regular)))
            .foregroundStyle(Color(hex: palette.ink))
            .lineSpacing(fontSize * (font.isSerif ? 0.45 : 0.52))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(isDimmed(line.id) ? 0.26 : 1)
            // Focus mode changes the ink immediately. Animating every
            // paragraph on pointer movement makes long-form text shimmer.
            .transaction { transaction in transaction.animation = nil }
            .onHover { hovered = $0 ? line.id : (hovered == line.id ? nil : hovered) }
            .id(line.id)
    }

    /// In focus mode the passage under the pointer stays lit and the rest of
    /// the page falls back. Nothing dims until the reader moves the pointer,
    /// so simply scrolling and reading is never interrupted.
    private func isDimmed(_ id: ReaderParagraphID) -> Bool {
        guard isFocusMode, let hovered else { return false }
        return hovered != id
    }

    private func highlighted(_ text: String) -> AttributedString {
        var result = AttributedString(text)
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard needle.count >= 2 else { return result }
        var start = result.startIndex
        while start < result.endIndex, let range = result[start...].range(
            of: needle,
            options: [.caseInsensitive, .diacriticInsensitive]
        ) {
            result[range].backgroundColor = Color(hex: palette.highlight)
            guard range.upperBound > start else { break }
            start = range.upperBound
        }
        return result
    }
}
