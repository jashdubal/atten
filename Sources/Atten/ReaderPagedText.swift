import AppKit
import AttenCore
import SwiftUI

/// Asks the reader to turn a leaf. Carries an id so the same direction asked
/// for twice is two turns rather than one.
struct ReaderTurnRequest: Equatable {
    let id = UUID()
    let direction: ReaderTurn
}

/// Asks the reader to go to a particular paragraph — a bookmark, a search
/// result, a chapter picked from the contents. Carries an id because the target
/// is often inside the chapter already open, where nothing else about the view
/// changes and there would otherwise be nothing to notice.
struct ReaderJumpRequest: Equatable {
    let id = UUID()
    let paragraph: Int
}

/// Where to open a chapter that has just been reached, or been laid out again.
enum ReaderOpening: Equatable {
    case first
    case last
    /// A paragraph of the chapter, for coming back to a bookmark, a search
    /// result, or the place the reader stopped.
    case paragraph(Int)
}

/// An EPUB, set in pages and turned like a book.
///
/// The chapter is broken into pages by TextKit at the size it will be drawn,
/// so a page is however many lines actually fit rather than a count of words
/// standing in for one. Turning past the last page of a chapter is a page turn
/// like any other, which is what `runOff` is for: the reader above changes
/// chapter and says which end of it to open at.
struct ReaderPagedText: View {
    /// Identifies the chapter itself, so a reader reused for a different book
    /// at the same chapter number does not keep the old book's pages.
    let chapterID: UUID
    let chapterIndex: Int
    let chapterNumber: Int
    let title: String
    let paragraphs: [String]
    let fontSize: Double
    /// The face the page is set in.
    let font: ReaderFont
    let isJustified: Bool
    /// What the page is printed in. Resolved above, so the reader never has to
    /// work out whether the system is in dark mode.
    let palette: ReaderPagePalette
    let mode: ReaderViewMode
    let query: String
    let opening: ReaderOpening
    let turnRequest: ReaderTurnRequest?
    let jumpRequest: ReaderJumpRequest?
    /// Page shown, pages in the chapter, and the paragraph the page starts in.
    let onPage: (Int, Int, Int) -> Void
    /// Asked to turn past either end of the chapter. Answers whether there was
    /// anywhere to go: at the two ends of the book there is not, and a turn
    /// must not be set going for a chapter that will never arrive.
    let runOff: (ReaderTurn) -> Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var layout = ReaderChapterLayout.empty
    @State private var pageIndex = 0
    @State private var pageSize = CGSize.zero
    @State private var turn: Turn?
    @State private var handledTurnID: UUID?
    @State private var handledJumpID: UUID?
    /// Which turn the running animation belongs to, so a turn interrupted by
    /// the next one does not finish by undoing it.
    @State private var turnToken: UUID?
    /// The chapter being left, kept only long enough to turn away from it.
    @State private var outgoing: Outgoing?
    @State private var pendingRunOff: ReaderTurn?
    @State private var hoveredMargin: ReaderTurn?
    @State private var swipeRequest: ReaderTurnRequest?

    private struct Turn: Equatable {
        let direction: ReaderTurn
        let destination: Int
        var progress: Double
    }

    private struct Outgoing: Equatable {
        let layout: ReaderChapterLayout
        let pageIndex: Int
        let direction: ReaderTurn
    }

    /// Long enough to read as paper moving, short enough that turning several
    /// pages in a row does not feel like waiting.
    private static let turnDuration = 0.42

    var body: some View {
        GeometryReader { geometry in
            let size = pageSize(in: geometry.size)
            ZStack {
                well
                spread(size: size)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .clipped()
            .onAppear { pageSize = size }
            .onChange(of: size) { _, new in pageSize = new }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: palette.well))
        .swipeToTurn(into: $swipeRequest)
        .task(id: TypesetKey(chapter: chapterID, style: style)) { await typeset() }
        .onChange(of: turnRequest) { _, request in
            guard let request, handledTurnID != request.id else { return }
            handledTurnID = request.id
            startTurn(request.direction)
        }
        .onChange(of: swipeRequest) { _, request in
            guard let request else { return }
            startTurn(request.direction)
        }
        .onChange(of: jumpRequest) { _, request in
            guard let request, handledJumpID != request.id else { return }
            handledJumpID = request.id
            jump(toParagraph: request.paragraph)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Page \(pageIndex + 1) of \(layout.pageCount), \(title)")
    }

    // MARK: - What is on screen

    /// What the sheets lie on. Darker than the page at the edges of the
    /// window, so the light in the room appears to be falling on the book
    /// rather than coming out of it.
    private var well: some View {
        Color(hex: palette.well)
            .overlay {
                RadialGradient(
                    colors: [
                        Color(hex: palette.page).opacity(palette.isDark ? 0.10 : 0.35),
                        .clear,
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: 900
                )
            }
    }

    private enum Side {
        case left
        case right
        /// Single-page mode, where the one page is both sides of the spread.
        case only
    }

    @ViewBuilder private func spread(size: CGSize) -> some View {
        HStack(spacing: 0) {
            turnMargin(.backward)
            HStack(spacing: mode == .spread ? Self.gutter : 0) {
                if mode == .spread {
                    slot(.left, size: size)
                    slot(.right, size: size)
                } else {
                    slot(.only, size: size)
                }
            }
            .fixedSize()
            turnMargin(.forward)
        }
    }

    /// How much sheet there is around the text.
    ///
    /// A book leaves more paper at the foot than at the head and more at the
    /// outer edge than at the gutter, because the thumb goes on the outer
    /// edge and the eye reads from the top. The proportions are the
    /// traditional ones, scaled to the type rather than to the window so the
    /// page keeps its shape as the text grows.
    private var sheetMargin: (top: CGFloat, bottom: CGFloat, side: CGFloat) {
        (top: fontSize * 2.4, bottom: fontSize * 2.8, side: fontSize * 2.6)
    }

    /// The margin either side of the text turns the page when it is clicked.
    ///
    /// A book is turned by touching its edge, not by finding a button, and the
    /// margins are the one part of the page with nothing on them to select —
    /// which is why the click lives here rather than over the text, where it
    /// would take the reader's ability to pick out a sentence.
    private func turnMargin(_ direction: ReaderTurn) -> some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .overlay {
                Image(systemName: direction == .forward ? "chevron.right" : "chevron.left")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color(hex: palette.inkMuted))
                    .opacity(hoveredMargin == direction ? 0.7 : 0)
                    .animation(
                        reduceMotion ? nil : .easeOut(duration: AttenMotion.standard),
                        value: hoveredMargin
                    )
                    .allowsHitTesting(false)
            }
            .onHover { hoveredMargin = $0 ? direction : nil }
            .onTapGesture { startTurn(direction) }
            .accessibilityHidden(true)
    }

    /// One half of the spread: the sheet settled there, with a leaf on top of
    /// it when one is being turned over that side.
    @ViewBuilder private func slot(_ side: Side, size: CGSize) -> some View {
        let sheet = sheetSize(forText: size)
        ZStack {
            page(under: side).map { view(of: $0, size: size) }
            if let turn, let leaf = leaf(on: side) {
                TurningLeaf(progress: turn.progress, turn: turn.direction) {
                    view(of: leaf.front, size: size)
                } back: {
                    if let back = leaf.back {
                        view(of: back, size: size)
                    } else {
                        ReaderSheet(palette: palette)
                    }
                }
            }
        }
        .frame(width: sheet.width, height: sheet.height)
    }

    /// The page number at the foot of the page, as a book prints it.
    private func folio(_ number: Int) -> some View {
        Text(String(number))
            .font(Font(ReaderTypesetter.face(font, size: max(9, fontSize * 0.7), weight: .regular)))
            .foregroundStyle(Color(hex: palette.inkMuted))
            .frame(maxWidth: .infinity)
            // The control bar announces the page; a second voice saying the
            // number again is noise.
            .accessibilityHidden(true)
    }

    private struct PageSource: Equatable {
        let layout: ReaderChapterLayout
        let index: Int
    }

    private struct Leaf {
        let front: PageSource
        let back: PageSource?
    }

    /// One whole sheet: the text, its margins, and its folio.
    @ViewBuilder private func view(of source: PageSource, size: CGSize) -> some View {
        let margin = sheetMargin
        ReaderSheet(palette: palette)
            .overlay(alignment: .top) {
                VStack(spacing: 0) {
                    ReaderPage(
                        layout: source.layout,
                        pageIndex: source.index,
                        style: style(pageSize: size),
                        highlight: query
                    )
                    .frame(width: size.width, height: size.height, alignment: .topLeading)
                    .clipped()
                    .allowsHitTesting(turn == nil)

                    Spacer(minLength: 0)
                    folio(source.index + 1)
                        .frame(height: Self.folioHeight)
                }
                .padding(.top, margin.top)
                .padding(.bottom, margin.bottom - Self.folioHeight)
                .padding(.horizontal, margin.side)
            }
            .frame(width: sheetSize(forText: size).width, height: sheetSize(forText: size).height)
    }

    // MARK: - Which page goes where

    /// What is lying in a slot, underneath any leaf being turned over it.
    ///
    /// In a spread, `pageIndex` is the left-hand page and a turn moves two
    /// pages at a time. While a leaf is up, the side it lifted from already
    /// shows the page it is uncovering; the other side keeps what it had until
    /// the leaf comes down over it.
    private func page(under side: Side) -> PageSource? {
        guard !layout.pages.isEmpty else { return nil }
        let settled = turn?.destination ?? pageIndex
        switch (mode, side, turn?.direction) {
        case (.spread, .left, .forward):
            // Uncovered only when the leaf lands, so it keeps the old page.
            return source(pageIndex)
        case (.spread, .left, _):
            return source(settled)
        case (.spread, .right, .backward):
            return source(pageIndex + 1)
        case (.spread, .right, _):
            return source(settled + 1)
        default:
            return source(settled)
        }
    }

    private func source(_ index: Int) -> PageSource? {
        guard layout.pages.indices.contains(index) else { return nil }
        return PageSource(layout: layout, index: index)
    }

    /// The leaf being turned, if it is being turned over this side.
    ///
    /// Forwards it lifts off the right and comes down on the left, so its front
    /// is the page just read and its back is the left-hand page of the spread
    /// arriving. Backwards is the same motion run the other way. In single-page
    /// mode there is nowhere for the back of a leaf to land, so it is plain
    /// paper — which is what the back of a page looks like from the front.
    private func leaf(on side: Side) -> Leaf? {
        guard let turn else { return nil }
        let wanted: Side = mode == .spread
            ? (turn.direction == .forward ? .right : .left)
            : .only
        guard side == wanted else { return nil }

        let front = outgoing.map { PageSource(layout: $0.layout, index: $0.pageIndex) }
            ?? source(leafFrontPage(turn.direction))
        guard let front else { return nil }
        guard mode == .spread else { return Leaf(front: front, back: nil) }
        let backIndex = turn.direction == .forward
            ? turn.destination
            : turn.destination + 1
        return Leaf(front: front, back: source(backIndex))
    }

    /// The face of the leaf that was showing before the turn started.
    private func leafFrontPage(_ direction: ReaderTurn) -> Int {
        guard mode == .spread else { return pageIndex }
        return direction == .forward ? pageIndex + 1 : pageIndex
    }

    // MARK: - Turning

    private func startTurn(_ direction: ReaderTurn) {
        guard !layout.pages.isEmpty, pendingRunOff == nil else { return }
        // Turning again while a leaf is still in the air lands it at once and
        // starts the next one, rather than dropping the press.
        if let turn { settle(on: turn.destination) }

        let step = mode.pagesPerTurn
        let destination = direction == .forward ? pageIndex + step : pageIndex - step
        guard destination >= 0, destination < layout.pageCount else {
            // Off the end of the chapter, which is a page turn too — but only
            // if there is a chapter on the other side of it.
            let keptLayout = layout
            let keptFront = leafFrontPage(direction)
            guard runOff(direction) else { return }
            pendingRunOff = direction
            outgoing = Outgoing(layout: keptLayout, pageIndex: keptFront, direction: direction)
            return
        }
        animate(to: destination, direction: direction)
    }

    /// Straight to a paragraph, without a turn: a bookmark or a search result
    /// is not somewhere the reader travelled to a page at a time.
    private func jump(toParagraph paragraph: Int) {
        guard !layout.pages.isEmpty else { return }
        if turn != nil { settle(on: pageIndex) }
        let page = alignedToSpread(layout.page(containing: layout.character(ofParagraph: paragraph)))
        pageIndex = min(max(0, page), max(0, layout.pageCount - 1))
        report()
    }

    private func animate(to destination: Int, direction: ReaderTurn) {
        guard !reduceMotion else {
            settle(on: destination)
            return
        }
        let token = UUID()
        turnToken = token
        turn = Turn(direction: direction, destination: destination, progress: 0)
        withAnimation(.easeInOut(duration: Self.turnDuration)) {
            turn?.progress = 1
        } completion: {
            // The turn this belongs to may already have been landed by the
            // next one; finishing it now would undo that.
            guard turnToken == token else { return }
            settle(on: destination)
        }
    }

    private func settle(on destination: Int) {
        turnToken = nil
        turn = nil
        outgoing = nil
        pageIndex = min(max(0, destination), max(0, layout.pageCount - 1))
        report()
    }

    private func report() {
        onPage(
            pageIndex,
            layout.pageCount,
            layout.paragraph(atCharacter: layout.range(ofPage: pageIndex).location)
        )
    }

    // MARK: - Setting the type

    private struct TypesetKey: Equatable {
        let chapter: UUID
        let style: ReaderPageStyle
    }

    private var style: ReaderPageStyle { style(pageSize: pageSize) }

    private func style(pageSize: CGSize) -> ReaderPageStyle {
        ReaderPageStyle(
            fontSize: fontSize,
            pageSize: pageSize,
            palette: palette,
            font: font,
            isJustified: isJustified
        )
    }

    private func typeset() async {
        guard pageSize.width > 1, pageSize.height > 1, !paragraphs.isEmpty else { return }
        let style = self.style
        let number = chapterNumber
        let title = self.title
        let paragraphs = self.paragraphs
        // Breaking a long chapter into lines is real work, and the reader
        // should not stop while it happens.
        let fresh = await Task.detached(priority: .userInitiated) {
            ReaderTypesetter.layout(
                eyebrow: "Chapter \(number)",
                title: title,
                paragraphs: paragraphs,
                style: style
            )
        }.value
        guard !Task.isCancelled else { return }

        layout = fresh
        let landing = landingPage(in: fresh)
        if let pending = pendingRunOff, outgoing != nil {
            pendingRunOff = nil
            pageIndex = landing
            // The chapter changed because a page was turned, so it is still a
            // page turn: the leaf being turned belongs to the chapter behind.
            animateArrival(direction: pending, landing: landing)
        } else {
            pageIndex = landing
            report()
        }
    }

    /// A chapter reached by turning back is opened at its last page, and one
    /// resumed is opened where the reader stopped. Resizing the window or
    /// changing the type repaginates, so the page the reader was on is found
    /// again by the character it started with rather than by its number.
    private func landingPage(in fresh: ReaderChapterLayout) -> Int {
        let raw: Int
        switch opening {
        case .first:
            raw = 0
        case .last:
            raw = max(0, fresh.pageCount - 1)
        case let .paragraph(index):
            raw = fresh.page(containing: fresh.character(ofParagraph: index))
        }
        return alignedToSpread(raw)
    }

    /// A spread always begins on an even page, or the two halves would not be
    /// facing pages.
    private func alignedToSpread(_ page: Int) -> Int {
        guard mode == .spread else { return page }
        return page - (page % 2)
    }

    private func animateArrival(direction: ReaderTurn, landing: Int) {
        guard !reduceMotion else {
            outgoing = nil
            report()
            return
        }
        let token = UUID()
        turnToken = token
        turn = Turn(direction: direction, destination: landing, progress: 0)
        withAnimation(.easeInOut(duration: Self.turnDuration)) {
            turn?.progress = 1
        } completion: {
            guard turnToken == token else { return }
            turnToken = nil
            turn = nil
            outgoing = nil
            report()
        }
    }

    // MARK: - The shape of a page

    /// The space between two facing pages.
    private static let gutter: CGFloat = 40
    /// The gap between the sheet and the edge of the window.
    private static let wellMargin: CGFloat = 34
    /// The strip at the foot of the sheet that the page number sits on.
    private static let folioHeight: CGFloat = 18

    /// How wide a page of text is allowed to get.
    ///
    /// A book is set to about sixty-five characters a line because that is how
    /// far the eye can travel and still find the beginning of the next one.
    /// A window is not a book and will happily be two and a half thousand
    /// points wide: left to fill it, a spread on a large screen came out with
    /// pages wider than the single-page view, which is the opposite of what
    /// opening a second page is for. The measure grows with the type and with
    /// nothing else.
    private var measure: CGFloat { fontSize * 31 }

    /// The text box on a page. The sheet around it is this plus its margins.
    private func pageSize(in available: CGSize) -> CGSize {
        let margin = sheetMargin
        let outer = min(Self.wellMargin, available.height * 0.06)
        let sheetHeight = max(120, available.height - outer * 2)
        let height = max(80, sheetHeight - margin.top - margin.bottom)

        let side = max(16, min(Self.wellMargin, available.width * 0.03))
        let usable = max(160, available.width - side * 2)
        let sheetWidth = mode == .spread
            ? max(160, (usable - Self.gutter) / 2)
            : usable
        let width = min(measure, max(120, sheetWidth - margin.side * 2))
        return CGSize(width: width.rounded(.down), height: height.rounded(.down))
    }

    /// The sheet that a text box of this size is printed on.
    private func sheetSize(forText text: CGSize) -> CGSize {
        let margin = sheetMargin
        return CGSize(
            width: text.width + margin.side * 2,
            height: text.height + margin.top + margin.bottom
        )
    }
}
