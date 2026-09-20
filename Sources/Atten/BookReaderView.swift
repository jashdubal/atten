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

    @State private var chapterIndex = 0
    @State private var position: ReaderParagraphID?
    @State private var paragraphs: [String] = []
    /// Words before each paragraph of the open chapter, which is what turns a
    /// scroll position into a page number.
    @State private var wordsBefore: [Int] = []
    @State private var pdfPage = 0
    @State private var pdfPageCount = 0
    @State private var pdfPageText = ""
    @State private var pdfJump: ReaderPDFJump?
    @State private var pagination = ReaderPagination.empty
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
                    .frame(width: geometry.size.width * pagination.fraction(ofPage: currentPage))
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
            .background(AttenColor.readerSurface)
        } else if book.format == .pdf {
            ReaderPDFView(
                url: book.sourceURL,
                jump: pdfJump,
                highlights: hits,
                theme: ThemeStore.shared.theme,
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
            ReaderTextView(
                chapterIndex: chapterIndex,
                chapterNumber: chapterIndex + 1,
                title: chapter.title,
                paragraphs: paragraphs,
                fontSize: fontSize,
                query: query,
                isFocusMode: isFocusMode,
                position: $position
            )
        } else {
            AttenEmptyState(
                title: "Nothing to read",
                systemImage: "text.alignleft",
                detail: "This book has no chapters Atten could read."
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AttenColor.readerSurface)
        }
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: AttenSpacing.sm) {
            AttenBackButton(title: book.title) { model.goBack() }

            Divider().frame(height: 18).overlay(AttenColor.separator)

            Button { go(toChapter: chapterIndex - 1) } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(AttenSecondaryButtonStyle())
            .disabled(chapterIndex == 0)
            .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
            .help("Previous chapter (⌘⌥←)")
            .accessibilityLabel("Previous chapter")

            Button { go(toChapter: chapterIndex + 1) } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(AttenSecondaryButtonStyle())
            .disabled(chapterIndex >= book.chapters.count - 1)
            .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            .help("Next chapter (⌘⌥→)")
            .accessibilityLabel("Next chapter")

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

            if book.format == .epub {
                ToolbarIconButton(title: "Smaller text", systemImage: "textformat.size.smaller") {
                    fontSize = max(Self.fontRange.lowerBound, fontSize - 1)
                }
                .disabled(fontSize <= Self.fontRange.lowerBound)

                ToolbarIconButton(title: "Larger text", systemImage: "textformat.size.larger") {
                    fontSize = min(Self.fontRange.upperBound, fontSize + 1)
                }
                .disabled(fontSize >= Self.fontRange.upperBound)
            }

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

    private var currentPage: Int {
        guard book.format != .pdf else {
            return min(max(1, pdfPage + 1), pagination.pageCount)
        }
        let words = wordsBefore.indices.contains(paragraphIndex) ? wordsBefore[paragraphIndex] : 0
        return min(
            pagination.endPage(ofChapter: chapterIndex),
            pagination.page(chapter: chapterIndex, wordsIntoChapter: words)
        )
    }

    private var pagesLeftInChapter: Int {
        max(0, pagination.endPage(ofChapter: chapterIndex) - currentPage)
    }

    private var readout: String {
        guard !book.chapters.isEmpty else { return "" }
        let left = pagesLeftInChapter
        return [
            "CH \(chapterIndex + 1)/\(book.chapters.count)",
            "PAGE \(currentPage) OF \(pagination.pageCount)",
            left == 0 ? "END OF CHAPTER" : "\(left) PAGE\(left == 1 ? "" : "S") LEFT IN CHAPTER",
        ].joined(separator: "  ·  ")
    }

    private var spokenReadout: String {
        guard !book.chapters.isEmpty else { return "" }
        let left = pagesLeftInChapter
        return """
        Chapter \(chapterIndex + 1) of \(book.chapters.count), \
        page \(currentPage) of \(pagination.pageCount), \
        \(left == 0 ? "last page of this chapter" : "\(left) pages left in this chapter")
        """
    }

    private var currentLocation: ReadingLocation {
        ReadingLocation(
            chapterIndex: chapterIndex,
            paragraphIndex: paragraphIndex,
            pageIndex: book.format == .pdf ? pdfPage : nil
        )
    }

    // MARK: - Moving about

    private func restore() {
        let saved = book.lastLocation
        chapterIndex = min(max(0, saved?.chapterIndex ?? 0), max(0, book.chapters.count - 1))
        rebuildPagination()
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
            loadChapter(startingAt: hit.paragraphIndex ?? 0)
        }
    }

    /// Splitting a chapter into paragraphs and counting its words is work, and
    /// doing it while the view redraws would do it on every frame. It happens
    /// once, when the chapter opens.
    private func loadChapter(startingAt paragraph: Int) {
        guard book.format == .epub, let chapter else {
            paragraphs = []
            wordsBefore = []
            return
        }
        let list = chapter.paragraphs
        var prefix: [Int] = []
        var running = 0
        for text in list {
            prefix.append(running)
            running += text.split(whereSeparator: \.isWhitespace).count
        }
        paragraphs = list
        wordsBefore = prefix
        let index = list.indices.contains(paragraph) ? paragraph : 0
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
