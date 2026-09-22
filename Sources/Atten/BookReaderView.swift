import AppKit
import AttenCore
import SwiftUI

/// The reader.
///
/// A centered reading canvas with contents, bookmarks and search in collapsible
/// tools. A PDF keeps its own typesetting because that is the book; an EPUB has
/// none, so Atten sets the text it extracted — the same text it reads aloud —
/// on a page of its own.
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
    @State private var pdfZoom: ReaderPDFZoom?
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
    @State private var isToolsPresented = false
    @State private var isChromeHovered = false
    @State private var isShowingAppearance = false
    /// The brightness the page is drawn at right now. Held here as well as in
    /// settings so dragging the slider shows on the page as it moves, while
    /// only the level the reader let go of is written to disk.
    @State private var brightness = 1.0
    @FocusState private var isSearchFocused: Bool
    @AppStorage("Atten.readerFontSize") private var fontSize = 17.0

    private static let fontRange = 13.0...30.0

    private var chapter: BookChapter? {
        book.chapters.indices.contains(chapterIndex) ? book.chapters[chapterIndex] : nil
    }

    private var paragraphIndex: Int { max(0, position?.index ?? 0) }

    private var isFocusMode: Bool { model.isReaderFocused }

    var body: some View {
        VStack(spacing: 0) {
            progressLine
            readerCanvas
            Divider().overlay(AttenColor.separator)
            controls
                .opacity(isFocusMode && !isChromeHovered ? 0.35 : 1)
                .animation(
                    reduceMotion ? nil : .easeOut(duration: AttenMotion.standard),
                    value: isChromeHovered
                )
                .onHover { isChromeHovered = $0 }
        }
        .background(AttenColor.appBackground)
        .navigationTitle(book.title)
        .attenScreenTitle(book.title)
        .onExitCommand {
            if isToolsPresented {
                closeTools()
            } else if isFocusMode {
                model.setReaderFocus(false)
            } else {
                // Escape remains a useful, explicit close action when the
                // reader is already in its normal shell. In focus mode it
                // only exits focus, so a single accidental press cannot close
                // the book.
                model.goBack()
            }
        }
        .task(id: book.id) { restore() }
        .onChange(of: query) { _, value in search(value) }
        .onChange(of: isFocusMode) { _, focused in
            guard focused else { return }
            // Tools are a deliberate reading aid, not part of Zen. Closing
            // them here also handles focus entered by a menu or command,
            // rather than only the visible button.
            closeTools()
            isChromeHovered = false
        }
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
            isToolsPresented = false
            isShowingAppearance = false
            // Idempotent, and the window is put back a run loop later, so
            // closing the book never fights the transition that closed it.
            model.setReaderFocus(false)
        }
        .onChange(of: model.section) { _, section in
            // The reader can disappear because the sidebar or player route was
            // chosen while a popover/scrim was open. Close local overlays with
            // the route so no stale panel survives the destination transition.
            guard section == .library else {
                closeTools()
                isShowingAppearance = false
                return
            }
        }
    }

    /// The page gets the whole reader width when the tools are closed. On a
    /// wide display it is capped so a PDF or a spread does not become a tiny
    /// strip of content at the far edges, and the EPUB readers remain centered
    /// in the same calm measure.
    private var readerCanvas: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Color(hex: palette.background)
                page
                    .frame(maxWidth: 1280)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if isToolsPresented {
                    toolsOverlay(availableWidth: geometry.size.width)
                }
            }
        }
    }

    private func toolsOverlay(availableWidth: CGFloat) -> some View {
        let panelWidth = ReaderToolsLayout.panelWidth(for: availableWidth)
        return ZStack(alignment: .leading) {
            AttenColor.scrim
                .opacity(0.22)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { closeTools() }

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
                onClose: closeTools,
                isSearchFocused: $isSearchFocused
            )
            .frame(width: panelWidth)
            .padding(.leading, AttenSpacing.sm)
            .padding(.vertical, AttenSpacing.sm)
            .transition(
                AttenMotion.transition(
                    .overlay(edge: .leading),
                    reduceMotion: reduceMotion
                )
            )
        }
        .animation(
            AttenMotion.transitionAnimation(
                AttenMotion.panel,
                reduceMotion: reduceMotion
            ),
            value: isToolsPresented
        )
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
            .background(Color(hex: palette.background))
        } else if book.format == .pdf {
            ReaderPDFView(
                url: book.sourceURL,
                jump: pdfJump,
                zoom: pdfZoom,
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
            .background(Color(hex: palette.background))
        }
    }

    private var viewMode: ReaderViewMode { model.settings.readerViewMode }

    /// The colours the page is printed in. `Automatic` is resolved here, where
    /// the appearance the window is actually drawn in is known.
    ///
    /// Dimmed ink only reaches a book Atten sets itself. A PDF's text is in the
    /// document, so the only thing quieter ink could change there is the colour
    /// behind it — which would lighten the page rather than soften the words.
    private var palette: ReaderPagePalette {
        guard book.format.isTypeset else { return themePalette }
        return themePalette.dimmingInk(to: brightness)
    }

    private var themePalette: ReaderPagePalette {
        let theme = AttenColor.palette
        let dark = colorScheme == .dark
        func value(_ color: AttenThemeColor) -> UInt { dark ? color.dark : color.light }
        return ReaderPagePalette(
            background: value(theme.readerBackground),
            ink: value(theme.readerInk),
            inkMuted: value(theme.readerInkMuted),
            accent: value(theme.readerAccent),
            highlight: value(theme.readerHighlight),
            isDark: dark
        )
    }

    // MARK: - Controls

    private var controls: some View {
        ViewThatFits(in: .horizontal) {
            fullControls
            compactControls
        }
        .padding(.horizontal, AttenSpacing.md)
        .padding(.vertical, AttenSpacing.xs)
        .background(AttenColor.surface)
        .overlay {
            // Keyboard equivalents remain available even when the compact
            // layout moves their visible counterparts behind a menu.
            readerKeyboardShortcuts
        }
        .popover(isPresented: $isShowingAppearance, arrowEdge: .bottom) {
            appearancePanel
                .padding(AttenSpacing.md)
                .frame(width: 280)
        }
    }

    private var fullControls: some View {
        HStack(spacing: AttenSpacing.sm) {
            AttenBackButton(title: book.title) { model.goBack() }

            Divider().frame(height: 18).overlay(AttenColor.separator)

            pageTurnButton(.backward)
            pageTurnButton(.forward)

            narrationButton

            if isFocusMode, model.playerTitle != nil {
                // Root chrome folds away in Zen; the compact player remains
                // discoverable here and inherits the reader's reveal-on-hover
                // transport treatment.
                GlobalPlayer(model: model)
            }

            Spacer(minLength: 0)

            Text(readout)
                .font(AttenTypography.caption)
                .monospacedDigit()
                .foregroundStyle(AttenColor.textSecondary)
                .lineLimit(1)
                .accessibilityLabel(spokenReadout)

            Spacer(minLength: 0)

            zoomControls
            appearanceButton
            readerToolsButton

            bookmarkButton
            focusButton
        }
    }

    /// At a narrow width the reader keeps the thing being read and the page
    /// turn/readout visible, while grouping secondary actions behind labeled
    /// menus. This avoids a horizontally clipped toolbar without hiding any
    /// keyboard equivalent or VoiceOver action.
    private var compactControls: some View {
        HStack(spacing: AttenSpacing.xs) {
            ToolbarIconButton(title: "Back to library", systemImage: "chevron.backward") {
                model.goBack()
            }
            compactNavigationMenu
            Spacer(minLength: AttenSpacing.xs)
            Text(readout)
                .font(AttenTypography.caption)
                .monospacedDigit()
                .foregroundStyle(AttenColor.textSecondary)
                .lineLimit(1)
            .accessibilityLabel(spokenReadout)
            Spacer(minLength: AttenSpacing.xs)
            readerToolsButton
            if isFocusMode, model.playerTitle != nil {
                // Keep the same transport in both responsive layouts. It is
                // faded with the rest of the Zen chrome until the pointer or
                // keyboard reaches it, but never removed from accessibility.
                GlobalPlayer(model: model)
            }
            compactMoreMenu
        }
    }

    @ViewBuilder private var compactNavigationMenu: some View {
        Menu {
            Button("Previous \(turnLabel)", systemImage: "chevron.left") {
                turnPage(.backward)
            }
            .disabled(!canTurnBack)
            Button("Next \(turnLabel)", systemImage: "chevron.right") {
                turnPage(.forward)
            }
            .disabled(!canTurnForward)
            Divider()
            Button("Previous chapter", systemImage: "arrow.left.to.line") {
                go(toChapter: chapterIndex - 1)
            }
            .disabled(chapterIndex == 0)
            Button("Next chapter", systemImage: "arrow.right.to.line") {
                go(toChapter: chapterIndex + 1)
            }
            .disabled(chapterIndex >= book.chapters.count - 1)
        } label: {
            Image(systemName: "chevron.left.chevron.right")
                .font(AttenTypography.control)
                .frame(width: 30, height: 30)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help("Reader navigation")
        .accessibilityLabel("Reader navigation")
    }

    private var compactMoreMenu: some View {
        Menu {
            if book.chapters.indices.contains(chapterIndex) {
                Menu("Narration", systemImage: "waveform") {
                    narrationMenuItems
                }
            }
            Button(
                isBookmarked ? "Remove bookmark" : "Bookmark this page",
                systemImage: isBookmarked ? "bookmark.fill" : "bookmark"
            ) {
                toggleBookmark()
            }
            Divider()
            Button("Page appearance", systemImage: "textformat.size") {
                isShowingAppearance = true
            }
            Button(
                isFocusMode ? "Leave focus mode" : "Focus mode",
                systemImage: isFocusMode
                    ? "arrow.down.right.and.arrow.up.left"
                    : "arrow.up.left.and.arrow.down.right"
            ) {
                model.setReaderFocus(!isFocusMode)
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(AttenTypography.control)
                .frame(width: 30, height: 30)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help("More reader tools")
        .accessibilityLabel("More reader tools")
    }

    @ViewBuilder private var narrationMenuItems: some View {
        if model.bookshelf.progress?.bookID == book.id {
            Button("Stop narration", systemImage: "stop.fill") {
                model.bookshelf.cancelNarration()
            }
        } else if playingChapterIndex == chapterIndex {
            Button(model.isPlaying ? "Pause narration" : "Resume narration", systemImage: model.isPlaying ? "pause.fill" : "play.fill") {
                model.toggleActivePlayback()
            }
        } else if let chapter, chapter.isNarrated, let url = chapter.audioURL {
            Button("Play chapter", systemImage: "play.fill") {
                let tracks = book.narrationTracks
                model.play(
                    tracks: tracks,
                    startingAt: tracks.firstIndex { $0.url == url } ?? 0
                )
            }
        } else {
            Button("Narrate this chapter", systemImage: "waveform") {
                model.bookshelf.narrate(
                    book.id,
                    chapters: [chapterIndex],
                    useMPS: model.settings.useMPS
                )
            }
            .disabled(model.bookshelf.isNarrating)
        }
    }

    private func pageTurnButton(_ direction: ReaderTurn) -> some View {
        Button { turnPage(direction) } label: {
            Image(systemName: direction == .backward ? "chevron.left" : "chevron.right")
        }
        .buttonStyle(AttenSecondaryButtonStyle())
        .disabled(direction == .backward ? !canTurnBack : !canTurnForward)
        // Given up while the caret is in the search field, where the arrow
        // keys mean what they mean in every other text field.
        .help("\(direction == .backward ? "Previous" : "Next") \(turnLabel)")
        .accessibilityLabel("\(direction == .backward ? "Previous" : "Next") \(turnLabel)")
    }

    private var readerToolsButton: some View {
        ToolbarIconButton(
            title: isToolsPresented ? "Hide reader tools" : "Show reader tools",
            systemImage: isToolsPresented ? "sidebar.leading" : "sidebar.leading"
        ) {
            toggleTools()
        }
        .accessibilityValue(isToolsPresented ? "Expanded" : "Collapsed")
        .accessibilityHint("Shows search, contents and bookmarks")
    }

    private func toggleTools() {
        if isFocusMode { model.setReaderFocus(false) }
        isToolsPresented.toggle()
        if !isToolsPresented { isSearchFocused = false }
    }

    private func closeTools() {
        isToolsPresented = false
        isSearchFocused = false
    }

    private var bookmarkButton: some View {
        Button(action: toggleBookmark) {
            Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                .font(AttenTypography.control)
                .frame(width: 30, height: 30)
                .foregroundStyle(
                    isBookmarked ? AttenColor.accentSecondary : AttenColor.textPrimary
                )
        }
        .buttonStyle(.plain)
        .help(isBookmarked ? "Remove bookmark (⌘D)" : "Bookmark this page (⌘D)")
        .accessibilityLabel(isBookmarked ? "Remove bookmark" : "Bookmark this page")
    }

    private var focusButton: some View {
        ToolbarIconButton(
            title: isFocusMode ? "Leave focus mode (⌃⌘F)" : "Focus mode (⌃⌘F)",
            systemImage: isFocusMode
                ? "arrow.down.right.and.arrow.up.left"
                : "arrow.up.left.and.arrow.down.right"
        ) {
            model.setReaderFocus(!isFocusMode)
        }
        .accessibilityLabel(isFocusMode ? "Leave focus mode" : "Enter focus mode")
        .accessibilityHint(
            isFocusMode
                ? "Restores the sidebar and reader tools"
                : "Hides the sidebar and reader tools"
        )
    }

    /// Keep shortcuts independent from the responsive toolbar. A shortcut
    /// should not disappear merely because a narrow window moved its visible
    /// button into a menu.
    @ViewBuilder private var readerKeyboardShortcuts: some View {
        textSizeShortcuts
        Button("Previous \(turnLabel)") { turnPage(.backward) }
            .keyboardShortcut(
                isSearchFocused ? nil : KeyboardShortcut(.leftArrow, modifiers: [])
            )
            .hidden()
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        Button("Next \(turnLabel)") { turnPage(.forward) }
            .keyboardShortcut(
                isSearchFocused ? nil : KeyboardShortcut(.rightArrow, modifiers: [])
            )
            .hidden()
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        Button("Previous chapter") { go(toChapter: chapterIndex - 1) }
            .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
            .hidden()
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        Button("Next chapter") { go(toChapter: chapterIndex + 1) }
            .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            .hidden()
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        Button("Bookmark this page") { toggleBookmark() }
            .keyboardShortcut("d", modifiers: .command)
            .hidden()
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        Button("Toggle focus mode") { model.setReaderFocus(!isFocusMode) }
            .keyboardShortcut("f", modifiers: [.command, .control])
            .hidden()
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        Button("Find in book") {
            openSearch()
        }
        .keyboardShortcut("f", modifiers: .command)
        .hidden()
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
        Button("Fit page") { zoom(.fit) }
            .keyboardShortcut("0", modifiers: .command)
            .hidden()
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
    }

    private func openSearch() {
        // Search needs the reader tools surface. Leaving Zen first keeps the
        // sidebar/tools/chrome relationship coherent and makes the search
        // field reachable to keyboard and assistive technology.
        model.setReaderFocus(false)
        isToolsPresented = true
        isSearchFocused = true
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
    ///
    /// A popover rather than a menu, because brightness is a slider and a
    /// slider is a thing to drag: a menu closes on the drag that is meant to
    /// be setting it. Everything else moved along with it so the panel stays
    /// one place rather than two.
    private var appearanceButton: some View {
        ToolbarIconButton(title: "Page appearance and layout", systemImage: "textformat.size") {
            isShowingAppearance.toggle()
        }
        .accessibilityLabel("Page appearance")
        .accessibilityValue(viewMode.displayName)
    }

    private var appearancePanel: some View {
        VStack(alignment: .leading, spacing: AttenSpacing.md) {
            panelLabel("Layout")
            Picker("Layout", selection: viewModeBinding) {
                ForEach(ReaderViewMode.allCases) { mode in
                    Image(systemName: mode.icon)
                        .help(mode.displayName)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if book.format == .pdf {
                Divider().overlay(AttenColor.separator)
                panelLabel("Zoom")
                HStack(spacing: AttenSpacing.xs) {
                    Button("Zoom Out", systemImage: "minus.magnifyingglass") { zoom(.smaller) }
                        .labelStyle(.iconOnly)
                        .buttonStyle(AttenSecondaryButtonStyle())
                    Button("Fit Page") { zoom(.fit) }
                        .buttonStyle(AttenSecondaryButtonStyle())
                    Button("Zoom In", systemImage: "plus.magnifyingglass") { zoom(.larger) }
                        .labelStyle(.iconOnly)
                        .buttonStyle(AttenSecondaryButtonStyle())
                }
            }

            if book.format.isTypeset {
                Divider().overlay(AttenColor.separator)
                Picker("Typeface", selection: readerFontBinding) {
                    ForEach(ReaderFont.allCases) { font in
                        Text(font.displayName).tag(font)
                    }
                }

                panelLabel("Text size")
                HStack(spacing: AttenSpacing.xs) {
                    Button("Smaller Text", systemImage: "textformat.size.smaller") {
                        setFontSize(fontSize - 1)
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(AttenSecondaryButtonStyle())
                    .disabled(fontSize <= Self.fontRange.lowerBound)

                    Text("\(Int(fontSize)) pt")
                        .font(AttenTypography.caption)
                        .monospacedDigit()
                        .foregroundStyle(AttenColor.textSecondary)
                        .frame(maxWidth: .infinity)

                    Button("Larger Text", systemImage: "textformat.size.larger") {
                        setFontSize(fontSize + 1)
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(AttenSecondaryButtonStyle())
                    .disabled(fontSize >= Self.fontRange.upperBound)
                }

                brightnessSlider

                Toggle("Justify Text", isOn: justifyBinding)
                    .font(AttenTypography.body)
            }
        }
    }

    /// The ink, not the screen: the page keeps its colour and its marks, and
    /// only the words soften. The percentage is there because a slider with no
    /// number on it cannot be put back where it was.
    private var brightnessSlider: some View {
        VStack(alignment: .leading, spacing: AttenSpacing.xxs) {
            HStack {
                panelLabel("Text brightness")
                Spacer()
                Text("\(Int((brightness * 100).rounded()))%")
                    .font(AttenTypography.caption)
                    .monospacedDigit()
                    .foregroundStyle(AttenColor.textSecondary)
            }
            HStack(spacing: AttenSpacing.xs) {
                Image(systemName: "sun.min")
                    .foregroundStyle(AttenColor.textSecondary)
                Slider(
                    value: $brightness,
                    in: ReaderPagePalette.inkBrightnessRange,
                    step: 0.01,
                    // Written down when the drag ends. Saving on every tick
                    // would rewrite the settings file a few dozen times for
                    // one sweep of the thumb.
                    onEditingChanged: { editing in
                        if !editing { model.setReaderTextBrightness(brightness) }
                    }
                )
                .controlSize(.small)
                Image(systemName: "sun.max")
                    .foregroundStyle(AttenColor.textSecondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Text brightness")
            .accessibilityValue("\(Int((brightness * 100).rounded())) percent")
        }
    }

    private func panelLabel(_ text: String) -> some View {
        Text(text)
            .font(AttenTypography.caption)
            .foregroundStyle(AttenColor.textSecondary)
    }

    /// Zoom where a reader looks for it — on the page, not inside a menu.
    /// A PDF is the one book Atten cannot set bigger by changing the type, so
    /// this is the only way in and it should not have to be found.
    @ViewBuilder private var zoomControls: some View {
        if book.format == .pdf {
            Button { zoom(.smaller) } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .buttonStyle(AttenSecondaryButtonStyle())
            .keyboardShortcut("-", modifiers: .command)
            .help("Zoom out (⌘−)")
            .accessibilityLabel("Zoom out")

            Button { zoom(.larger) } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .buttonStyle(AttenSecondaryButtonStyle())
            .keyboardShortcut("+", modifiers: .command)
            .help("Zoom in (⌘+)")
            .accessibilityLabel("Zoom in")

            // Fit has no button of its own: it is the one of the three that is
            // asked for once, and the panel is where it lives.
            Button("Fit page") { zoom(.fit) }
                .keyboardShortcut("0", modifiers: .command)
                .hidden()
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
    }

    /// ⌘+ and ⌘− set the type on a book Atten typesets itself — the same keys
    /// that zoom a PDF, because to the reader they are the same request: make
    /// the words bigger. Hidden, because the panel already shows the controls.
    @ViewBuilder private var textSizeShortcuts: some View {
        if book.format.isTypeset {
            Button("Larger text") { setFontSize(fontSize + 1) }
                .keyboardShortcut("+", modifiers: .command)
                .hidden()
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
            Button("Smaller text") { setFontSize(fontSize - 1) }
                .keyboardShortcut("-", modifiers: .command)
                .hidden()
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
    }

    private func setFontSize(_ size: Double) {
        fontSize = min(max(Self.fontRange.lowerBound, size), Self.fontRange.upperBound)
    }

    private func zoom(_ step: ReaderPDFZoom.Step) {
        pdfZoom = ReaderPDFZoom(step: step)
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
        Group {
            if model.bookshelf.progress?.bookID == book.id {
                Button("Stop", systemImage: "stop.fill") { model.bookshelf.cancelNarration() }
                    .buttonStyle(AttenSecondaryButtonStyle())
            } else if playingChapterIndex == chapterIndex {
                // The chapter on screen is the one playing. The reader used to put
                // its own skip/play/time row here, which meant two sets of
                // controls for one sound; the transport lives in the top chrome
                // now, so this only says which chapter you are hearing.
                playingIndicator
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
                    model.openNowPlaying()
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
        .frame(minHeight: 38, alignment: .leading)
    }

    /// Not a control. The chapter on screen is the one playing, and the
    /// transport that acts on it is in the top chrome. It is also a compact
    /// route into the full Now Playing screen, so a reader does not have to
    /// aim for the small player in the window chrome.
    private var playingIndicator: some View {
        Button {
            model.openNowPlaying()
        } label: {
            HStack(spacing: AttenSpacing.xxs) {
                Image(systemName: "waveform")
                    .font(.system(size: 11, weight: .semibold))
                Text("Playing")
                    .font(AttenTypography.control)
            }
            .foregroundStyle(AttenColor.accent)
            .padding(.horizontal, AttenSpacing.sm)
            .frame(height: 30)
            .background(AttenColor.accent.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: AttenRadius.control))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("This chapter is playing")
        .accessibilityHint("Open Now Playing")
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
        brightness = model.settings.readerTextBrightness
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
        persistLocation()
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
        persistLocation()
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
