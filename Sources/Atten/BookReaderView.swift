import AppKit
import AttenCore
import SwiftUI

/// The reader.
///
/// Contents, bookmarks, and search on the left; the book on the right; where
/// you are and what you can do with it along the bottom. A PDF keeps its own
/// typesetting because that is the book; an EPUB has none, so Atten sets the
/// text it extracted — the same text it reads aloud — on a page of its own.
struct BookReaderView: View {
    @Bindable var model: AppModel
    let book: BookRecord

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    @State private var chapterIndex = 0
    @State private var position: ReaderParagraphID?
    @State private var paragraphs: [String] = []
    @State private var pdfPage = 0
    @State private var pdfPageCount = 0
    @State private var pdfPageText = ""
    @State private var pdfJump: ReaderPDFJump?
    @State private var pagination = ReaderPagination.empty
    /// Where the paged reader is, reported back as it turns.
    @State private var pageInChapter = 0
    @State private var pagesInChapter = 1
    @State private var opening = ReaderOpening.first
    @State private var turnRequest: ReaderTurnRequest?
    @State private var jumpRequest: ReaderJumpRequest?
    /// The chapter the reading position was last written down for. Writing it
    /// on every page turn would rewrite the whole shelf a page at a time.
    @State private var persistedChapter = -1
    @State private var query = ""
    @State private var hits: [ReaderHit] = []
    @State private var selectedHitID: String?
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var panelTab = ReaderPanelTab.contents
    @State private var isChromeHovered = false
    @FocusState private var isSearchFocused: Bool
    @AppStorage("Atten.readerFontSize") private var fontSize = 17.0

    private static let fontRange = 13.0...30.0

    private var chapter: BookChapter? {
        book.chapters.indices.contains(chapterIndex) ? book.chapters[chapterIndex] : nil
    }

    private var paragraphIndex: Int { max(0, position?.index ?? 0) }

    private var isFocusMode: Bool { model.isReaderFocused }

    var body: some View {
        HStack(spacing: 0) {
            if !isFocusMode {
                ReaderSidePanel(
                    book: book,
                    chapterIndex: chapterIndex,
                    pagination: pagination,
                    currentLocation: currentLocation,
                    tab: $panelTab,
                    query: $query,
                    hits: hits,
                    isSearching: isSearching,
                    selectedHitID: selectedHitID,
                    playingChapterIndex: playingChapterIndex,
                    selectChapter: { go(toChapter: $0) },
                    selectHit: select(_:),
                    selectBookmark: { go(
                        toChapter: $0.location.chapterIndex,
                        paragraph: $0.location.paragraphIndex,
                        page: $0.location.pageIndex
                    ) },
                    removeBookmark: { model.bookshelf.removeBookmark($0.id, from: book.id) },
                    isSearchFocused: $isSearchFocused
                )
                .transition(.move(edge: .leading).combined(with: .opacity))
                Divider().overlay(AttenColor.separator)
            }

            VStack(spacing: 0) {
                progressLine
                page
                Divider().overlay(AttenColor.separator)
                controls
                    .opacity(isFocusMode && !isChromeHovered ? 0.35 : 1)
                    .animation(
                        reduceMotion ? nil : .easeOut(duration: AttenMotion.standard),
                        value: isChromeHovered
                    )
                    .onHover { isChromeHovered = $0 }
            }
        }
        .background(AttenColor.appBackground)
        // The side panel's transition needs an animation of its own: focus mode
        // is decided on the model now, and a model has no business animating.
        .animation(
            reduceMotion ? nil : .easeInOut(duration: AttenMotion.standard),
            value: isFocusMode
        )
        .navigationTitle(book.title)
        .onExitCommand { model.setReaderFocus(false) }
        .task(id: book.id) { restore() }
        .onChange(of: query) { _, value in search(value) }
        // Scrolling reports where it is through the position binding rather
        // than through the paged reader, so switching to pages afterwards
        // opens where the scrolling left off.
        .onChange(of: position) { _, new in
            guard !viewMode.isPaged, let new, new.chapter == chapterIndex else { return }
            opening = .paragraph(new.index)
        }
        .onDisappear {
            persistLocation()
            searchTask?.cancel()
            // Idempotent, and the window is put back a run loop later, so
            // closing the book never fights the transition that closed it.
            model.setReaderFocus(false)
        }
    }

    // MARK: - The page

    private var progressLine: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                AttenColor.separator.opacity(0.4)
                AttenColor.accent
                    .frame(width: geometry.size.width * progressFraction)
                    .animation(
                        reduceMotion ? nil : .easeOut(duration: AttenMotion.standard),
                        value: progressFraction
                    )
            }
        }
        .frame(height: 2)
        .accessibilityHidden(true)
    }

    @ViewBuilder private var page: some View {
        if !book.sourceExists {
            AttenEmptyState(
                title: "Source file missing",
                systemImage: "questionmark.folder",
                detail: "Atten's copy of this book is gone. Remove it and add the book again."
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(hex: palette.well))
        } else if book.format == .pdf {
            ReaderPDFView(
                url: book.sourceURL,
                jump: pdfJump,
                highlights: hits,
                palette: palette,
                mode: viewMode,
                onOpen: { count in
                    pdfPageCount = count
                    rebuildPagination()
                },
                onPageChange: { page, text in
                    pdfPage = page
                    pdfPageText = text
                    let chapter = book.chapterIndex(forPage: page)
                    if chapter != chapterIndex { chapterIndex = chapter }
                }
            )
        } else if let chapter, !paragraphs.isEmpty {
            if viewMode.isPaged {
                ReaderPagedText(
                    chapterID: chapter.id,
                    chapterIndex: chapterIndex,
                    chapterNumber: chapterIndex + 1,
                    sectionNoun: book.format.sectionNoun,
                    title: chapter.title,
                    paragraphs: paragraphs,
                    fontSize: fontSize,
                    font: model.settings.readerFont,
                    isJustified: model.settings.readerJustifiesText,
                    palette: palette,
                    mode: viewMode,
                    query: query,
                    opening: opening,
                    turnRequest: turnRequest,
                    jumpRequest: jumpRequest,
                    onPage: { page, count, paragraph in
                        pageInChapter = page
                        pagesInChapter = count
                        position = ReaderParagraphID(chapter: chapterIndex, index: paragraph)
                        // Pages are remade whenever the window or the type
                        // changes, so where to reopen is kept as the paragraph
                        // being read rather than as a page number that will not
                        // mean the same thing next time.
                        opening = .paragraph(paragraph)
                        if persistedChapter != chapterIndex {
                            persistedChapter = chapterIndex
                            persistLocation()
                        }
                    },
                    runOff: moveChapter
                )
            } else {
                ReaderTextView(
                    chapterIndex: chapterIndex,
                    chapterNumber: chapterIndex + 1,
                    sectionNoun: book.format.sectionNoun,
                    title: chapter.title,
                    paragraphs: paragraphs,
                    fontSize: fontSize,
                    font: model.settings.readerFont,
                    query: query,
                    isFocusMode: isFocusMode,
                    palette: palette,
                    position: $position
                )
            }
        } else {
            AttenEmptyState(
                title: "Nothing to read",
                systemImage: "text.alignleft",
                detail: "This book has no chapters Atten could read."
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(hex: palette.well))
        }
    }

    private var viewMode: ReaderViewMode { model.settings.readerViewMode }

    /// The colours the page is printed in. `Automatic` is resolved here, where
    /// the appearance the window is actually drawn in is known.
    private var palette: ReaderPagePalette {
        model.settings.readerPageTheme.palette(inDarkMode: colorScheme == .dark)
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: AttenSpacing.sm) {
            AttenBackButton(title: book.title) { model.goBack() }

            Divider().frame(height: 18).overlay(AttenColor.separator)

            // Pages, not chapters. A chapter is still reachable — from the
            // contents, or with ⌘⌥ — but the thing under the reader's hand
            // turns one page, which is what a reader reaches for.
            Button { turnPage(.backward) } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(AttenSecondaryButtonStyle())
            .disabled(!canTurnBack)
            // Given up while the caret is in the search field, where the arrow
            // keys mean what they mean in every other text field.
            .keyboardShortcut(isSearchFocused ? nil : KeyboardShortcut(.leftArrow, modifiers: []))
            .help("Previous \(turnLabel) (←)")
            .accessibilityLabel("Previous \(turnLabel)")

            Button { turnPage(.forward) } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(AttenSecondaryButtonStyle())
            .disabled(!canTurnForward)
            .keyboardShortcut(isSearchFocused ? nil : KeyboardShortcut(.rightArrow, modifiers: []))
            .help("Next \(turnLabel) (→)")
            .accessibilityLabel("Next \(turnLabel)")

            // Whole chapters keep their own keys, out of the way of the ones
            // that turn pages.
            Button("Previous chapter") { go(toChapter: chapterIndex - 1) }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                .disabled(chapterIndex == 0)
                .hidden()
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
            Button("Next chapter") { go(toChapter: chapterIndex + 1) }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                .disabled(chapterIndex >= book.chapters.count - 1)
                .hidden()
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)

            narrationButton

            Spacer(minLength: 0)

            Text(readout)
                .font(AttenTypography.caption)
                .monospacedDigit()
                .foregroundStyle(AttenColor.textSecondary)
                .lineLimit(1)
                .accessibilityLabel(spokenReadout)

            Spacer(minLength: 0)

            ToolbarIconButton(title: "Find in book (⌘F)", systemImage: "magnifyingglass") {
                model.setReaderFocus(false)
                isSearchFocused = true
            }
            .keyboardShortcut("f", modifiers: .command)

            appearanceMenu

            Button(action: toggleBookmark) {
                Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                    .font(AttenTypography.control)
                    .frame(width: 30, height: 30)
                    .foregroundStyle(
                        isBookmarked ? AttenColor.accentSecondary : AttenColor.textPrimary
                    )
            }
            .buttonStyle(.plain)
            .keyboardShortcut("d", modifiers: .command)
            .help(isBookmarked ? "Remove bookmark (⌘D)" : "Bookmark this page (⌘D)")
            .accessibilityLabel(isBookmarked ? "Remove bookmark" : "Bookmark this page")

            ToolbarIconButton(
                title: isFocusMode ? "Leave focus mode (⌃⌘F)" : "Focus mode (⌃⌘F)",
                systemImage: isFocusMode
                    ? "arrow.down.right.and.arrow.up.left"
                    : "arrow.up.left.and.arrow.down.right"
            ) {
                model.setReaderFocus(!isFocusMode)
            }
            .keyboardShortcut("f", modifiers: [.command, .control])
        }
        .padding(.horizontal, AttenSpacing.md)
        .padding(.vertical, AttenSpacing.xs)
        .background(AttenColor.surface)
    }

    private var playingChapterIndex: Int? {
        guard let playing = model.activeAudioURL else { return nil }
        return book.chapters.firstIndex { $0.audioURL == playing }
    }

    /// Everything about how the book looks, behind one button.
    ///
    /// These used to be three controls in a row — a layout menu and a pair of
    /// text-size steppers — which is three things to recognise for one idea.
    /// A book reader has one of these, marked Aa, and everything about the
    /// look of the page is inside it.
    private var appearanceMenu: some View {
        Menu {
            Picker("Page", selection: pageThemeBinding) {
                ForEach(ReaderPageTheme.allCases) { theme in
                    Text(theme.displayName).tag(theme)
                }
            }
            .pickerStyle(.inline)

            Divider()

            Picker("Layout", selection: viewModeBinding) {
                ForEach(ReaderViewMode.allCases) { mode in
                    Label(mode.displayName, systemImage: mode.icon).tag(mode)
                }
            }
            .pickerStyle(.inline)

            if book.format.isTypeset {
                Divider()

                Picker("Typeface", selection: readerFontBinding) {
                    ForEach(ReaderFont.allCases) { font in
                        Text(font.displayName).tag(font)
                    }
                }
                .pickerStyle(.inline)

                Divider()

                Button("Smaller Text", systemImage: "textformat.size.smaller") {
                    fontSize = max(Self.fontRange.lowerBound, fontSize - 1)
                }
                .disabled(fontSize <= Self.fontRange.lowerBound)
                Button("Larger Text", systemImage: "textformat.size.larger") {
                    fontSize = min(Self.fontRange.upperBound, fontSize + 1)
                }
                .disabled(fontSize >= Self.fontRange.upperBound)
                Toggle("Justify Text", isOn: justifyBinding)
            }
        } label: {
            Image(systemName: "textformat.size")
                .font(AttenTypography.control)
                .frame(width: 30, height: 30)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Page appearance and layout")
        .accessibilityLabel("Page appearance")
        .accessibilityValue(
            "\(model.settings.readerPageTheme.displayName), \(viewMode.displayName)"
        )
    }

    private var pageThemeBinding: Binding<ReaderPageTheme> {
        Binding(
            get: { model.settings.readerPageTheme },
            set: { model.selectReaderPageTheme($0) }
        )
    }

    private var readerFontBinding: Binding<ReaderFont> {
        Binding(
            get: { model.settings.readerFont },
            set: { model.selectReaderFont($0) }
        )
    }

    private var viewModeBinding: Binding<ReaderViewMode> {
        Binding(
            get: { model.settings.readerViewMode },
            set: { model.selectReaderViewMode($0) }
        )
    }

    private var justifyBinding: Binding<Bool> {
        Binding(
            get: { model.settings.readerJustifiesText },
            set: { model.setReaderJustifiesText($0) }
        )
    }

    @ViewBuilder private var narrationButton: some View {
        if model.bookshelf.progress?.bookID == book.id {
            Button("Stop", systemImage: "stop.fill") { model.bookshelf.cancelNarration() }
                .buttonStyle(AttenSecondaryButtonStyle())
        } else if playingChapterIndex == chapterIndex {
            // Only for the chapter actually on screen: every other chapter
            // still needs its own "Listen", or its offer to be narrated.
            // The full player runs along the bottom of the window already, so
            // the reader carries only what someone reaches for without looking
            // away from the page.
            readerTransport
        } else if let chapter, chapter.isNarrated, let url = chapter.audioURL {
            Button {
                // Playing from here continues into the rest of the book, the
                // way turning a page would — and keeps what came before it in
                // the queue, so the player can go back a chapter.
                let tracks = book.narrationTracks
                model.play(
                    tracks: tracks,
                    startingAt: tracks.firstIndex { $0.url == url } ?? 0
                )
            } label: {
                Label(
                    model.isPlaying && model.activeAudioURL == url ? "Playing" : "Listen",
                    systemImage: "play.fill"
                )
            }
            .buttonStyle(AttenPrimaryButtonStyle())
        } else {
            Button {
                model.bookshelf.narrate(
                    book.id,
                    chapters: [chapterIndex],
                    useMPS: model.settings.useMPS
                )
            } label: {
                Label("Narrate this chapter", systemImage: "waveform")
            }
            .buttonStyle(AttenPrimaryButtonStyle())
            .disabled(chapter == nil || model.bookshelf.isNarrating)
        }
    }

    private var readerTransport: some View {
        HStack(spacing: 2) {
            ToolbarIconButton(title: "Back 10 seconds", systemImage: "gobackward.10") {
                model.skip(by: -NowPlayingCenter.skipInterval)
            }
            Button(action: model.toggleActivePlayback) {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AttenColor.onAccent)
                    .frame(width: 26, height: 26)
                    .background(AttenColor.accent)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help(model.isPlaying ? "Pause narration" : "Resume narration")
            .accessibilityLabel(model.isPlaying ? "Pause narration" : "Resume narration")

            ToolbarIconButton(title: "Forward 10 seconds", systemImage: "goforward.10") {
                model.skip(by: NowPlayingCenter.skipInterval)
            }

            Text("-" + PlayerBar.timeText(model.playbackRemaining))
                .font(AttenTypography.caption)
                .monospacedDigit()
                .foregroundStyle(AttenColor.textSecondary)
                .padding(.leading, AttenSpacing.xxs)
                .accessibilityLabel("Time left in this chapter")
                .accessibilityValue(PlayerBar.timeText(model.playbackRemaining))
        }
    }

    // MARK: - Where the reader is

    /// How much of the book is behind the reader, for the line along the top.
    ///
    /// Chapters are the only thing a book has that does not change when the
    /// window does, so progress is counted in chapters with the current one
    /// filled in by however far through it the reader is.
    private var progressFraction: Double {
        if book.format == .pdf {
            guard pdfPageCount > 0 else { return 0 }
            return Double(pdfPage + 1) / Double(pdfPageCount)
        }
        guard !book.chapters.isEmpty else { return 0 }
        return min(1, (Double(chapterIndex) + fractionThroughChapter) / Double(book.chapters.count))
    }

    /// How far through the open chapter the reader is — counted in pages where
    /// there are pages, and in paragraphs where there are not.
    private var fractionThroughChapter: Double {
        guard viewMode.isPaged else {
            guard paragraphs.count > 1 else { return 1 }
            return Double(paragraphIndex) / Double(paragraphs.count - 1)
        }
        guard pagesInChapter > 1 else { return 1 }
        return Double(pageInChapter) / Double(pagesInChapter - 1)
    }

    private var pagesLeftInChapter: Int {
        max(0, pagesInChapter - pageInChapter - viewMode.pagesPerTurn)
    }

    private var readout: String {
        guard !book.chapters.isEmpty else { return "" }
        let chapter = "CH \(chapterIndex + 1)/\(book.chapters.count)"
        if book.format == .pdf {
            return [chapter, "PAGE \(pdfPage + 1) OF \(max(pdfPageCount, pdfPage + 1))"]
                .joined(separator: "  ·  ")
        }
        guard viewMode.isPaged else {
            // Nothing is laid out in pages while the chapter is one column, so
            // there is no page number to give that would mean anything.
            return [chapter, "SCROLLING"].joined(separator: "  ·  ")
        }
        let left = pagesLeftInChapter
        return [
            chapter,
            "PAGE \(pageInChapter + 1) OF \(pagesInChapter)",
            left == 0 ? "END OF CHAPTER" : "\(left) PAGE\(left == 1 ? "" : "S") LEFT",
        ].joined(separator: "  ·  ")
    }

    private var spokenReadout: String {
        guard !book.chapters.isEmpty else { return "" }
        let chapter = "Chapter \(chapterIndex + 1) of \(book.chapters.count)"
        if book.format == .pdf {
            return "\(chapter), page \(pdfPage + 1) of \(max(pdfPageCount, pdfPage + 1))"
        }
        guard viewMode.isPaged else { return "\(chapter), scrolling" }
        let left = pagesLeftInChapter
        return """
        \(chapter), page \(pageInChapter + 1) of \(pagesInChapter) in this chapter, \
        \(left == 0 ? "the last page of it" : "\(left) pages left in it")
        """
    }

    private var currentLocation: ReadingLocation {
        ReadingLocation(
            chapterIndex: chapterIndex,
            paragraphIndex: paragraphIndex,
            pageIndex: book.format == .pdf ? pdfPage : nil
        )
    }

    // MARK: - Turning pages

    /// Turning past the last page of a chapter is a page turn like any other.
    ///
    /// Chapters used to be the unit of travel: the only way forward was a
    /// button that jumped a whole chapter and dropped the reader at the top of
    /// it. A book does not work that way. Running off the end of a chapter
    /// opens the next one at its first page, and running off the beginning
    /// opens the one before at its last.
    private func turnPastChapter(_ direction: ReaderTurn) {
        switch direction {
        case .forward:
            guard chapterIndex + 1 < book.chapters.count else { return }
            opening = .first
            chapterIndex += 1
        case .backward:
            guard chapterIndex > 0 else { return }
            opening = .last
            chapterIndex -= 1
        }
        // Not written down here: the paged reader answers with the paragraph
        // it landed on, and that is the one worth remembering.
        loadChapter(startingAt: 0, reopen: false)
    }

    /// Answers whether the reader moved, so a turn is never set going towards a
    /// chapter that does not exist.
    @discardableResult
    private func moveChapter(_ direction: ReaderTurn) -> Bool {
        switch direction {
        case .forward:
            guard chapterIndex + 1 < book.chapters.count else { return false }
        case .backward:
            guard chapterIndex > 0 else { return false }
        }
        turnPastChapter(direction)
        return true
    }

    private func turnPage(_ direction: ReaderTurn) {
        if book.format == .pdf {
            // A PDF is already in pages; PDFKit turns them.
            pdfJump = ReaderPDFJump(page: direction == .forward ? pdfPage + 1 : pdfPage - 1)
            return
        }
        guard viewMode.isPaged else {
            // Nothing is laid out in pages while the chapter is one long
            // column, so the only move left is a whole chapter.
            moveChapter(direction)
            return
        }
        turnRequest = ReaderTurnRequest(direction: direction)
    }

    private var canTurnBack: Bool {
        if book.format == .pdf { return pdfPage > 0 }
        guard viewMode.isPaged else { return chapterIndex > 0 }
        return pageInChapter > 0 || chapterIndex > 0
    }

    private var canTurnForward: Bool {
        if book.format == .pdf { return pdfPage + 1 < pdfPageCount }
        guard viewMode.isPaged else { return chapterIndex + 1 < book.chapters.count }
        return pageInChapter + viewMode.pagesPerTurn < pagesInChapter
            || chapterIndex + 1 < book.chapters.count
    }

    private var turnLabel: String {
        viewMode.isPaged || book.format == .pdf
            ? "page"
            : book.format.sectionNoun.lowercased()
    }

    // MARK: - Moving about

    private func restore() {
        let saved = book.lastLocation
        chapterIndex = min(max(0, saved?.chapterIndex ?? 0), max(0, book.chapters.count - 1))
        rebuildPagination()
        opening = .paragraph(saved?.paragraphIndex ?? 0)
        loadChapter(startingAt: saved?.paragraphIndex ?? 0)
        if book.format == .pdf {
            pdfPage = saved?.pageIndex ?? chapter?.pageIndex ?? 0
            pdfJump = ReaderPDFJump(page: pdfPage)
        }
    }

    /// Every deliberate move through the book goes through here, so the page
    /// on screen, the contents, and the saved place can never disagree. A PDF
    /// scrolled by hand reports itself separately and must not land here, or
    /// every scroll would fight a jump back to the top of the chapter.
    private func go(toChapter index: Int, paragraph: Int = 0, page: Int? = nil) {
        guard !book.chapters.isEmpty else { return }
        chapterIndex = min(max(0, index), book.chapters.count - 1)
        opening = .paragraph(paragraph)
        jumpRequest = ReaderJumpRequest(paragraph: paragraph)
        loadChapter(startingAt: paragraph)
        if book.format == .pdf {
            let target = page ?? chapter?.pageIndex ?? pdfPage
            pdfPage = target
            pdfJump = ReaderPDFJump(page: target)
        }
        persistLocation()
    }

    private func select(_ hit: ReaderHit) {
        selectedHitID = hit.id
        guard !book.chapters.isEmpty else { return }
        chapterIndex = min(max(0, hit.chapterIndex), book.chapters.count - 1)
        if let page = hit.pageIndex {
            pdfPage = page
            pdfJump = ReaderPDFJump(
                page: page,
                matchLocation: hit.matchLocation,
                matchLength: hit.matchLength
            )
        } else {
            let paragraph = hit.paragraphIndex ?? 0
            opening = .paragraph(paragraph)
            jumpRequest = ReaderJumpRequest(paragraph: paragraph)
            loadChapter(startingAt: paragraph)
        }
    }

    /// Splitting a chapter into paragraphs is work, and doing it while the
    /// view redraws would do it on every frame. It happens once, when the
    /// chapter opens; breaking those paragraphs into pages happens after, off
    /// the main thread, in the typesetter.
    private func loadChapter(startingAt paragraph: Int, reopen: Bool = true) {
        guard book.format.isTypeset, let chapter else {
            paragraphs = []
            return
        }
        paragraphs = chapter.paragraphs
        guard reopen else { return }
        let index = paragraphs.indices.contains(paragraph) ? paragraph : 0
        position = ReaderParagraphID(chapter: chapterIndex, index: index)
    }

    private func rebuildPagination() {
        pagination = book.format == .pdf
            ? ReaderPagination(
                pdfChapterPageIndexes: book.chapters.map(\.pageIndex),
                pageCount: pdfPageCount
            )
            : ReaderPagination(epubChapterWordCounts: book.chapters.map(\.wordCount))
    }

    private func persistLocation() {
        model.bookshelf.updateReadingLocation(currentLocation, for: book.id)
    }

    // MARK: - Bookmarks

    private var isBookmarked: Bool {
        book.bookmarks.contains { $0.location.isAt(currentLocation) }
    }

    private func toggleBookmark() {
        model.bookshelf.toggleBookmark(
            at: currentLocation,
            excerpt: currentExcerpt,
            in: book.id
        )
    }

    /// The words the mark lands on, so the bookmark list reads like the book.
    private var currentExcerpt: String {
        let source = book.format == .pdf
            ? pdfPageText
            : (paragraphs.indices.contains(paragraphIndex) ? paragraphs[paragraphIndex] : "")
        let clean = source
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return clean.isEmpty ? (chapter?.title ?? book.title) : String(clean.prefix(160))
    }

    // MARK: - Search

    /// Searching a book means reading all of it, so it happens off the main
    /// actor, and only once the typing pauses.
    private func search(_ raw: String) {
        searchTask?.cancel()
        let needle = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard needle.count >= 2 else {
            hits = []
            selectedHitID = nil
            isSearching = false
            return
        }
        isSearching = true
        let record = book
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            let found = await Task.detached(priority: .userInitiated) {
                record.format == .pdf
                    ? ReaderPDFSearch.run(needle, in: record.sourceURL, book: record)
                    : BookSearch.run(needle, in: record.chapters).map(ReaderHit.init)
            }.value
            guard !Task.isCancelled else { return }
            hits = found
            isSearching = false
        }
    }
}
