import AttenCore
import SwiftUI
import UniformTypeIdentifiers

enum LibraryRoute: Hashable {
    case book(UUID)
    case reader(UUID)
}

private extension AttenCore.LibraryItemFilter {
    var title: String {
        switch self {
        case .all: "All"
        case .listening: "Listening"
        case .drafts: "Drafts"
        case .audiobooks: "Audiobooks"
        }
    }
}

/// `ImageRenderer` draws nothing for a `ScrollView`'s content, so an offscreen
/// render sets this to swap the shelf's `ScrollView` for a plain `VStack` —
/// same content, no scrolling. Never set outside a render test.
private struct OffscreenRenderKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var attenIsOffscreenRender: Bool {
        get { self[OffscreenRenderKey.self] }
        set { self[OffscreenRenderKey.self] = newValue }
    }
}

struct LibraryView: View {
    @Bindable var model: AppModel
    @State private var selectedFilter: AttenCore.LibraryItemFilter = .all
    @State private var isTargeted = false
    @AppStorage("Atten.libraryListView") private var showsList = false
    @AppStorage("Atten.librarySort") private var sortOrder = LibrarySort.recentlyAdded
    @State private var pendingRemoval: BookRecord?
    @State private var pendingExport: ExportTarget?
    /// The item a dedupe toast points at: shown while non-nil, and where the
    /// shelf scrolls to and briefly highlights.
    @State private var duplicateBookID: UUID?
    @FocusState private var isSearchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.attenIsOffscreenRender) private var isOffscreenRender

    private var shelf: BookshelfModel { model.bookshelf }

    /// The search term lives on the model so Home can set it on the way here.
    private var query: String { model.libraryQuery }

    /// The Library is three screens deep — shelf, book, reader — and shows one
    /// at a time.
    ///
    /// It used to be a `NavigationStack` inside the split view's detail column,
    /// which is where the interface got stuck: once a book was pushed, that
    /// column belonged to the stack, and picking Studio or Voices in the
    /// sidebar changed the selection without changing anything on screen. The
    /// screen to show is read from the path instead, so nothing between the
    /// sidebar and the page can hold a stale view open.
    var body: some View {
        ZStack {
            page
                .transition(
                    AttenMotion.transition(
                        .destination(forward: model.libraryMovedForward),
                        reduceMotion: reduceMotion
                    )
                )
            if model.libraryPath.isEmpty {
                Button("Search Library") { isSearchFocused = true }
                    .keyboardShortcut("f", modifiers: .command)
                    .opacity(0)
                    .accessibilityHidden(true)
            }
        }
        .animation(
            AttenMotion.transitionAnimation(
                AttenMotion.standard,
                reduceMotion: reduceMotion
            ),
            value: model.libraryPath
        )
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            receive(providers)
        }
        .task { shelf.refreshNarrationCounts() }
        .onChange(of: shelf.duplicateImport) { _, event in
            guard let event else { return }
            duplicateBookID = event.bookID
        }
        .sheet(item: $pendingExport) { target in
            ExportSheet(model: model, target: target)
        }
        .confirmationDialog(
            "Remove “\(pendingRemoval?.title ?? "")” from Library?",
            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
            titleVisibility: .visible,
            presenting: pendingRemoval
        ) { book in
            Button("Remove", role: .destructive) { shelf.remove(book.id) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This deletes the imported file and any narration for this book. This can't be undone.")
        }
    }

    @ViewBuilder private var page: some View {
        switch model.libraryPath.last {
        case .none:
            shelfPage
        case let .book(id):
            openBook(id) { book in
                BookDetailView(model: model, book: book) {
                    model.openInLibrary(.reader(id))
                }
            }
        case let .reader(id):
            openBook(id) { book in
                BookReaderView(model: model, book: book)
            }
        }
    }

    /// A book can be removed while it is open — from its own menu, or from
    /// another window. Rather than stranding the reader on a screen about a
    /// book that no longer exists, the Library goes back to the shelf.
    @ViewBuilder private func openBook(
        _ id: UUID,
        @ViewBuilder content: (BookRecord) -> some View
    ) -> some View {
        if let book = shelf.book(id: id) {
            content(book)
        } else {
            AttenEmptyState(
                title: "Book removed",
                systemImage: "book.closed",
                detail: "This book is no longer in your library."
            )
            .task { model.returnToShelf() }
        }
    }

    private var shelfPage: some View {
        GeometryReader { geometry in
            if isOffscreenRender {
                // A `GeometryReader` always proposes its own full size to its
                // child, unlike the `ScrollView` below, which proposes an
                // effectively unbounded height and lets the content size
                // itself — without `fixedSize`, every `Spacer` in here would
                // stretch to fill the render canvas instead of collapsing to
                // its `minLength` the way it does on the real, scrolled page.
                shelfContent(availableWidth: geometry.size.width)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        shelfContent(availableWidth: geometry.size.width)
                    }
                    .onChange(of: duplicateBookID) { _, id in
                        guard let id else { return }
                        withAnimation(AttenMotion.animation(.large, reduceMotion: reduceMotion)) {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                }
            }
        }
        .background(AttenBackdrop())
        .overlay {
            if isTargeted {
                RoundedRectangle(cornerRadius: AttenRadius.card)
                    .stroke(AttenColor.accent, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .padding(AttenSpacing.md)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottom) {
            if let duplicateBookID, let title = shelf.book(id: duplicateBookID)?.title {
                DedupeToast(title: title) { self.duplicateBookID = nil }
                    .padding(.bottom, AttenSpacing.lg)
                    .transition(.opacity)
            }
        }
        .animation(AttenMotion.fade(reduceMotion: reduceMotion), value: duplicateBookID)
        .task(id: duplicateBookID) {
            guard duplicateBookID != nil else { return }
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { duplicateBookID = nil }
        }
    }

    /// The shelf's content, without the `ScrollView` around it — pulled out
    /// so `shelfPage` can swap the scroll container for a plain `VStack`
    /// under `isOffscreenRender` without duplicating everything inside it.
    private func shelfContent(availableWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: AttenSpacing.lg) {
            header
            LibraryStatusArea(shelf: shelf)
            if query.isEmpty, selectedFilter == .all,
               let book = continueBook {
                ContinueListeningHero(model: model, book: book)
            }
            if !shelf.books.isEmpty || !model.projects.isEmpty {
                searchAndFilters
            }

            if filteredBooks.isEmpty && projectItems.isEmpty {
                emptyState
            } else if !filteredBooks.isEmpty {
                collection(availableWidth: availableWidth)
            }
            if !projectItems.isEmpty {
                LibraryProjectsSection(
                    model: model,
                    items: projectItems,
                    isWide: availableWidth >= 820
                )
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .attenScrollPadding()
        .frame(maxWidth: 1440, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top) {
                pageHeader
                Spacer(minLength: AttenSpacing.md)
                actions
            }
            VStack(alignment: .leading, spacing: AttenSpacing.md) {
                pageHeader
                actions
            }
        }
    }

    private var continueBook: BookRecord? {
        model.playingBook ?? shelf.books.filter { $0.lastListenedAt != nil }
            .max { ($0.lastListenedAt ?? .distantPast) < ($1.lastListenedAt ?? .distantPast) }
    }

    private var pageHeader: some View {
        Text("Library").font(AttenTypography.title2)
    }

    private var addBookButton: some View {
        Button {
            model.openBookImportPanel()
        } label: {
            Label("Add to Library", systemImage: "plus")
        }
        .buttonStyle(AttenSecondaryButtonStyle())
        .disabled(shelf.isImporting)
        .fixedSize()
    }

    private var actions: some View {
        HStack(spacing: AttenSpacing.xs) {
            addBookButton
            newButton
        }
    }

    /// Create is a verb, so it starts here rather than living in the sidebar.
    private var newButton: some View {
        Button {
            model.newDraft()
            model.section = .studio
        } label: {
            Label("New", systemImage: "plus")
        }
        .buttonStyle(AttenPrimaryButtonStyle())
        .help("New (⌘N)")
        .fixedSize()
    }

    private var searchAndFilters: some View {
        VStack(alignment: .leading, spacing: 24) {
            searchField
            Rectangle().fill(AttenColor.border).frame(height: 1)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 20) {
                    filterPicker
                    Spacer(minLength: 16)
                    displayControls
                }
                VStack(alignment: .leading, spacing: 12) {
                    filterPicker
                    HStack { Spacer(); displayControls }
                }
            }
        }
    }

    private var filterPicker: some View {
        HStack(spacing: 6) {
            ForEach(AttenCore.LibraryItemFilter.allCases, id: \.rawValue) { filter in
                Button { selectedFilter = filter } label: {
                    Text(filter.title)
                        .font(AttenTypography.callout)
                        .padding(.horizontal, 16)
                        .frame(height: 32)
                }
                .buttonStyle(AttenTertiaryButtonStyle(isSelected: selectedFilter == filter))
                .accessibilityAddTraits(selectedFilter == filter ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Library filter")
    }

    private var displayControls: some View {
        HStack(spacing: 16) {
            HStack(spacing: 8) {
                Text("Sort by")
                    .foregroundStyle(AttenColor.textMuted)
                Menu {
                    Picker("Sort by", selection: $sortOrder) {
                        ForEach(LibrarySort.allCases) { order in
                            Text(order.rawValue).tag(order)
                        }
                    }
                } label: {
                    Text(sortOrder.rawValue)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Sort books")
            }
            .font(AttenTypography.callout)
            Rectangle().fill(AttenColor.border).frame(width: 1, height: 22)
            HStack(spacing: 4) {
                layoutButton(list: false, icon: "square.grid.2x2.fill", title: "Grid view")
                layoutButton(list: true, icon: "list.bullet", title: "List view")
            }
        }
    }

    private func layoutButton(list: Bool, icon: String, title: String) -> some View {
        Button { showsList = list } label: {
            Image(systemName: icon).frame(width: 38, height: 32)
        }
        .buttonStyle(AttenTertiaryButtonStyle(isSelected: showsList == list))
        .help(title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(showsList == list ? .isSelected : [])
    }

    private var searchField: some View {
        AttenSearchField(
            prompt: "Search your library…",
            text: $model.libraryQuery,
            height: 34,
            externalFocus: $isSearchFocused
        )
        .frame(maxWidth: 640)
    }

    private var emptyState: some View {
        let isFiltering = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || selectedFilter != .all
        return VStack(spacing: AttenSpacing.md) {
            AttenEmptyState(
                title: isFiltering ? "No books found" : "Your library is empty",
                systemImage: isFiltering ? "line.3.horizontal.decrease.circle" : "books.vertical",
                detail: !isFiltering
                    ? "Add a PDF, EPUB, Word, Markdown or text file — or drop one here — and Atten reads it into sections you can listen to."
                    : "Try another search or filter, or add a supported document."
            )
            if !isFiltering {
                Button("Add a Book") { model.openBookImportPanel() }
                    .buttonStyle(AttenSecondaryButtonStyle())
                    .fixedSize()
                    .padding(.bottom, AttenSpacing.lg)
            }
        }
    }

    @ViewBuilder private func collection(availableWidth: CGFloat) -> some View {
        if showsList {
            LazyVStack(spacing: 0) {
                ForEach(filteredBooks) { book in
                    shelfItem(book)
                        .padding(.vertical, 14)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(AttenColor.border).frame(height: 1)
                        }
                }
            }
        } else {
            LazyVGrid(
                // Without `alignment: .top`, a `GridItem` centers each cell in
                // its row — cards with a narration meter or "Ready to listen"
                // line are taller than one with neither, so the shorter
                // covers above them would drift down instead of lining up.
                columns: [GridItem(
                    .adaptive(minimum: availableWidth >= 1100 ? 210 : 170, maximum: 260),
                    spacing: 20,
                    alignment: .top
                )],
                alignment: .leading,
                spacing: 32
            ) {
                ForEach(filteredBooks) { book in shelfItem(book) }
            }
        }
    }

    private func shelfItem(_ book: BookRecord) -> some View {
        BookCard(
            book: book,
            narrated: shelf.narratedCount(of: book),
            cover: shelf.covers.cover(for: book.id),
            dominantColor: shelf.covers.dominantColor(for: book.id),
            progress: shelf.progress,
            queued: shelf.isQueued(book.id) ? (shelf.isPaused(book.id) ? "Paused" : "Queued") : nil,
            isList: showsList,
            isPlaying: model.playingBook?.id == book.id && model.isPlaying,
            isHighlighted: duplicateBookID == book.id,
            open: { model.openInLibrary(.book(book.id)) },
            read: { model.openInLibrary(.reader(book.id)) },
            remove: { pendingRemoval = book },
            export: { pendingExport = ExportTarget(book: book) }
        )
        .id(book.id)
        .task(id: book.id) { await shelf.covers.load(book) }
        .contextMenu {
            Button("Open", systemImage: "book") { model.openInLibrary(.book(book.id)) }
            Button("Read", systemImage: "text.alignleft") { model.openInLibrary(.reader(book.id)) }
            Divider()
            Button("Export…", systemImage: "square.and.arrow.up") {
                pendingExport = ExportTarget(book: book)
            }
            .disabled(!book.hasBookAudio)
            Divider()
            Button("Remove from Library", systemImage: "trash", role: .destructive) {
                pendingRemoval = book
            }
        }
    }

    private var filteredBooks: [BookRecord] {
        shelf.books(for: selectedFilter, query: query, sort: sortOrder)
    }

    /// Legacy projects are always voiced and never listening, so this only
    /// ever puts them under All and Audiobooks — the same rule `LibraryItem`
    /// applies to a book.
    private var projectItems: [AttenCore.LibraryItem] {
        let items = AttenCore.LibraryItem.filter(model.projects.map(AttenCore.LibraryItem.project), by: selectedFilter)
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return items }
        return items.filter { $0.title.localizedCaseInsensitiveContains(term) }
    }

    /// Dropping a book onto the shelf is the same import as the panel. Books
    /// are read one at a time, because a drop of ten would otherwise start ten
    /// imports and the shelf accepts only one at a time.
    private func receive(_ providers: [NSItemProvider]) -> Bool {
        let supported = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }
        guard !supported.isEmpty else { return false }
        Task { @MainActor in
            for provider in supported {
                guard let url = await provider.fileURL(),
                      DocumentImporter.supportedExtensions
                          .contains(url.pathExtension.lowercased()) else { continue }
                await shelf.importBook(from: url, defaults: model.settings)
            }
        }
        return true
    }
}

struct LibraryStatusArea: View {
    let shelf: BookshelfModel
    var showsPreparation = true

    var body: some View {
        VStack(alignment: .leading, spacing: AttenSpacing.xs) {
            if shelf.isImporting {
                AttenProgressStatus(
                    title: "Importing document",
                    detail: "Reading the source into chapters. This may take a moment.",
                    phase: .active
                )
            }

            if showsPreparation, let progress = shelf.progress, let book = shelf.book(id: progress.bookID) {
                AttenProgressStatus(
                    title: "Narrating \(book.title)",
                    detail: progress.isCombining ? "Combining chapters into one audio file" : "Chapter \(min(progress.completed + 1, progress.total)) of \(progress.total): \(progress.chapterTitle)",
                    phase: .active,
                    progress: progress.total > 0 ? progress.fraction : nil,
                    progressLabel: progress.eta,
                    actionTitle: "Stop",
                    action: shelf.cancelNarration
                )
            }

            if let message = shelf.importSuccessMessage {
                StatusBanner(kind: .success, message: message, dismiss: shelf.dismissStatus)
            }
            if let message = shelf.narrationSuccessMessage {
                StatusBanner(kind: .success, message: message, dismiss: shelf.dismissStatus)
            }
            if let message = shelf.cancelledMessage {
                StatusBanner(kind: .cancelled, message: message, dismiss: shelf.dismissStatus)
            }
            if let message = shelf.importErrorMessage {
                StatusBanner(kind: .error, message: message, dismiss: shelf.dismissStatus)
            }
            if let message = shelf.narrationErrorMessage {
                StatusBanner(kind: .error, message: message, dismiss: shelf.dismissStatus)
            }
            if let message = shelf.successMessage,
               message != shelf.importSuccessMessage,
               message != shelf.narrationSuccessMessage {
                StatusBanner(kind: .success, message: message, dismiss: shelf.dismissStatus)
            }
            if let message = shelf.errorMessage,
               message != shelf.importErrorMessage,
               message != shelf.narrationErrorMessage {
                StatusBanner(kind: .error, message: message, dismiss: shelf.dismissStatus)
            }
        }
    }
}

/// The cover and metadata open the book; the menu remains a separate control.
private struct BookCard: View {
    let book: BookRecord
    let narrated: Int
    let cover: NSImage?
    let dominantColor: OKLCHColor?
    let progress: BookshelfModel.NarrationProgress?
    /// "Queued" or "Paused" while the book waits in the narration queue.
    let queued: String?
    let isList: Bool
    let isPlaying: Bool
    let isHighlighted: Bool
    let open: () -> Void
    let read: () -> Void
    let remove: () -> Void
    let export: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isNarrating: Bool { progress?.bookID == book.id }
    private var isFullyNarrated: Bool {
        book.hasBookAudio && !book.needsPreparation
    }

    private var libraryItem: AttenCore.LibraryItem { .book(book) }

    /// Matches whichever caption or meter the card is showing, so VoiceOver
    /// reports the same state a sighted reader sees.
    private var narrationStatus: String {
        if let queued { return "\(queued), \(narrated) of \(book.chapters.count) chapters narrated" }
        if isNarrating || (narrated > 0 && !isFullyNarrated) {
            return "\(narrated) of \(book.chapters.count) chapters narrated"
        }
        return isFullyNarrated ? "ready to listen" : "audio not prepared"
    }

    var body: some View {
        Button(action: open) {
            let layout = isList
                ? AnyLayout(HStackLayout(alignment: .center, spacing: 20))
                : AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            layout {
                jacket.frame(width: isList ? 64 : nil)
                    // Waiting is not generating: no colour until its turn.
                    .grayscale(queued == nil ? 0 : 1)
                    .opacity(queued == nil ? 1 : 0.7)
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(book.title)
                            .font(AttenTypography.callout.weight(.semibold))
                            .foregroundStyle(AttenColor.textPrimary)
                            .lineLimit(2)
                        // A cover with no art of its own already prints this
                        // same fallback on its face (`GeneratedCover`'s
                        // `sourceLabel`) — repeating it here would just be the
                        // format name twice for a book with no author.
                        if let author = book.author {
                            Text(author)
                                .font(AttenTypography.callout)
                                .foregroundStyle(AttenColor.textSecondary)
                                .lineLimit(1)
                        } else if cover != nil {
                            Text(book.format.displayName)
                                .font(AttenTypography.callout)
                                .foregroundStyle(AttenColor.textSecondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Group {
                    if isNarrating || queued != nil || (narrated > 0 && !isFullyNarrated) {
                        NarrationMeter(narrated: narrated, total: book.chapters.count, isRunning: isNarrating, queued: queued)
                    } else if isFullyNarrated {
                        Label("Ready to listen", systemImage: "headphones")
                            .font(AttenTypography.callout)
                            .foregroundStyle(AttenColor.textSecondary)
                    }
                    }
                        .frame(maxWidth: isList ? 360 : nil)
                        .accessibilityHidden(true)
                }
                .padding(.trailing, isList ? 40 : 0)
            }
            .multilineTextAlignment(.leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(book.title)
        .accessibilityValue(
            "\(book.author ?? "Unknown author"), \(narrationStatus)"
                + (book.sourceExists ? "" : ", source file unavailable")
        )
        .accessibilityHint("Open this book")
        .overlay(alignment: .topTrailing) {
            Menu {
                Button("Open", systemImage: "book", action: open)
                Button("Read", systemImage: "text.alignleft", action: read)
                Divider()
                Button("Export…", systemImage: "square.and.arrow.up", action: export)
                    .disabled(!book.hasBookAudio)
                Divider()
                Button("Remove from Library", systemImage: "trash", role: .destructive, action: remove)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AttenColor.textPrimary)
                    .frame(width: 28, height: 24)
                    .background(AttenColor.surface.opacity(0.92), in: RoundedRectangle(cornerRadius: 4))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .background(cover != nil && !isList ? AttenColor.surface.opacity(0.92) : .clear,
                        in: RoundedRectangle(cornerRadius: 4))
            .padding(8)
            .accessibilityLabel("Actions for \(book.title)")
        }
        .overlay {
            if isHighlighted {
                RoundedRectangle(cornerRadius: AttenRadius.card, style: .continuous)
                    .stroke(AttenColor.signal, lineWidth: 2)
                    .padding(-4)
                    .allowsHitTesting(false)
            }
        }
        .animation(AttenMotion.animation(AttenMotion.state, reduceMotion: reduceMotion), value: isHighlighted)
    }

    private var jacket: some View {
        Color.clear
            .aspectRatio(AttenMetrics.coverAspectRatio, contentMode: .fit)
            .overlay {
                GeometryReader { geometry in
                    if let cover {
                        Image(nsImage: cover)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped()
                    } else {
                        GeneratedCover(
                            title: book.title,
                            contentHash: libraryItem.coverSeedKey,
                            sourceLabel: book.author ?? book.format.displayName,
                            state: libraryItem.state,
                            isPlaying: isPlaying
                        )
                    }
                }
            }
            .attenCoverFrame(tint: dominantColor ?? OKLCHColor(lightness: 0.6, chroma: 0.1, hue: CoverSeed(contentHash: libraryItem.coverSeedKey).hue))
            .attenMatchedCover(book.id)
            .overlay(alignment: .bottomTrailing) {
                if !book.sourceExists {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(AttenColor.warning)
                        .padding(8)
                        .help("Source file unavailable")
                } else if isFullyNarrated {
                    Circle().fill(AttenColor.success)
                        .frame(width: 7, height: 7)
                        .padding(10)
                        .help("Fully narrated")
                }
            }
    }
}

struct NarrationMeter: View {
    let narrated: Int
    let total: Int
    let isRunning: Bool
    var queued: String?

    private var fraction: Double { total > 0 ? min(1, max(0, Double(narrated) / Double(total))) : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: AttenSpacing.xxs) {
            GeometryReader { geometry in
                Capsule().fill(AttenColor.progressTrack)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(narrated >= total && total > 0 ? AttenColor.success : (queued == nil ? AttenColor.accent : AttenColor.text3))
                            .frame(width: geometry.size.width * fraction)
                    }
            }
            .frame(height: 5)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(label)
                Spacer(minLength: 0)
                Text("\(Int(fraction * 100))%")
                    .monospacedDigit()
            }
            .font(AttenTypography.callout)
            .foregroundStyle(AttenColor.textSecondary)
            .padding(.top, 4)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
    }

    private var label: String {
        if isRunning { return "Narrating… \(narrated) of \(total) chapters" }
        if let queued { return "\(queued) · \(narrated) of \(total) chapters" }
        if total == 0 { return "No chapters" }
        if narrated == total { return "Audiobook · \(total) chapters" }
        return "\(narrated) of \(total) chapters narrated"
    }
}


/// What a duplicate import gets instead of a second copy: a moment of
/// confirmation that it is already here, over the item the shelf has just
/// scrolled to and outlined in `signal`.
private struct DedupeToast: View {
    let title: String
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: AttenSpacing.xs) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(AttenColor.success)
            Text("“\(title)” is already in your library")
                .font(AttenTypography.callout)
                .foregroundStyle(AttenColor.textPrimary)
                .lineLimit(1)
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .foregroundStyle(AttenColor.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, AttenSpacing.md)
        .frame(height: 44)
        .background(AttenColor.surfaceElevated, in: Capsule())
        .overlay { Capsule().stroke(AttenColor.separator, lineWidth: 1) }
        .shadow(color: AttenColor.shadow.opacity(0.12), radius: 8, y: 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Already in Library: \(title)")
    }
}

private extension NSItemProvider {
    /// Main-actor bound because an item provider is not Sendable and this is
    /// only ever reached from a drop on the shelf.
    @MainActor
    func fileURL() async -> URL? {
        await withCheckedContinuation { continuation in
            _ = loadObject(ofClass: URL.self) { url, _ in
                continuation.resume(returning: url)
            }
        }
    }
}

