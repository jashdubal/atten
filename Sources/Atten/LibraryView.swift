import AttenCore
import SwiftUI
import UniformTypeIdentifiers

enum LibraryRoute: Hashable {
    case book(UUID)
    case reader(UUID)
}

struct LibraryView: View {
    @Bindable var model: AppModel
    @State private var selectedFilter: LibraryFilter = .books
    @State private var isTargeted = false
    @AppStorage("Atten.libraryListView") private var showsList = false
    @AppStorage("Atten.librarySort") private var sortOrder = LibrarySort.recentlyAdded
    @State private var pendingRemoval: BookRecord?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            ScrollView {
                VStack(alignment: .leading, spacing: AttenSpacing.lg) {
                    header
                    LibraryStatusArea(shelf: shelf)
                    if query.isEmpty, selectedFilter == .books,
                       let book = continueBook {
                        ContinueListeningCard(model: model, book: book)
                    }
                    if !shelf.books.isEmpty {
                        searchAndFilters
                    }

                    if filteredBooks.isEmpty {
                        emptyState
                    } else {
                        collection(availableWidth: geometry.size.width)
                    }
                    importHint
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
                .frame(maxWidth: 1440, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .top)
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
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top) {
                pageHeader
                Spacer(minLength: AttenSpacing.md)
                addBookButton
            }
            VStack(alignment: .leading, spacing: AttenSpacing.md) {
                pageHeader
                addBookButton
            }
        }
    }

    private var continueBook: BookRecord? {
        model.playingBook ?? shelf.books.filter { $0.lastListenedAt != nil }
            .max { ($0.lastListenedAt ?? .distantPast) < ($1.lastListenedAt ?? .distantPast) }
    }

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Library").font(AttenTypography.pageTitle)
            Text("Your books and documents, ready when you are.")
                .font(AttenTypography.body).foregroundStyle(AttenColor.textSecondary)
        }
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
            ForEach(LibraryFilter.allCases) { filter in
                Button { selectedFilter = filter } label: {
                    Text(filter == .books ? "All" : filter.title)
                        .font(AttenTypography.control)
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
            if selectedFilter != .recentlyAdded {
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
                .font(AttenTypography.metadata)
                Rectangle().fill(AttenColor.border).frame(width: 1, height: 22)
            }
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

    private var importHint: some View {
        HStack(spacing: AttenSpacing.xs) {
            Image(systemName: "arrow.down.doc")
                .foregroundStyle(AttenColor.textMuted)
            Text("Drop a PDF, EPUB, Kindle, Word, RTF, Markdown, HTML or text file here")
                .font(AttenTypography.caption)
                .foregroundStyle(AttenColor.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Drop a supported document here to add it to your library")
    }

    private var searchField: some View {
        AttenSearchField(prompt: "Search your library…", text: $model.libraryQuery, height: 34)
            .frame(maxWidth: 640)
    }

    private var emptyState: some View {
        let isFiltering = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || selectedFilter != .books
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
                columns: [GridItem(.adaptive(minimum: availableWidth >= 1100 ? 210 : 170, maximum: 260), spacing: 20)],
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
            progress: shelf.progress,
            isList: showsList,
            open: { model.openInLibrary(.book(book.id)) },
            read: { model.openInLibrary(.reader(book.id)) },
            remove: { pendingRemoval = book }
        )
        .task(id: book.id) { await shelf.covers.load(book) }
        .contextMenu {
            Button("Open", systemImage: "book") { model.openInLibrary(.book(book.id)) }
            Button("Read", systemImage: "text.alignleft") { model.openInLibrary(.reader(book.id)) }
            Divider()
            Button("Remove from Library", systemImage: "trash", role: .destructive) {
                pendingRemoval = book
            }
        }
    }

    private var filteredBooks: [BookRecord] {
        shelf.books(for: selectedFilter, query: query, sort: sortOrder)
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
    let progress: BookshelfModel.NarrationProgress?
    let isList: Bool
    let open: () -> Void
    let read: () -> Void
    let remove: () -> Void

    @State private var isHovering = false

    private var isNarrating: Bool { progress?.bookID == book.id }
    private var isFullyNarrated: Bool {
        book.hasBookAudio && !book.needsPreparation
    }

    /// Matches whichever caption or meter the card is showing, so VoiceOver
    /// reports the same state a sighted reader sees.
    private var narrationStatus: String {
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
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(book.title)
                            .font(AttenTypography.control.weight(.semibold))
                            .foregroundStyle(AttenColor.textPrimary)
                            .lineLimit(2)
                        Text(book.author ?? book.format.displayName)
                            .font(AttenTypography.metadata)
                            .foregroundStyle(AttenColor.textSecondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Group {
                    if isNarrating || (narrated > 0 && !isFullyNarrated) {
                        NarrationMeter(narrated: narrated, total: book.chapters.count, isRunning: isNarrating)
                    } else {
                        Label(isFullyNarrated ? "Ready to listen" : "Audio not prepared",
                              systemImage: isFullyNarrated ? "headphones" : "waveform")
                            .font(AttenTypography.caption)
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
        .onHover { isHovering = $0 }
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
    }

    private var jacket: some View {
        Color.clear
            .aspectRatio(0.72, contentMode: .fit)
            .overlay {
                GeometryReader { geometry in
                    if let cover {
                        Image(nsImage: cover)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped()
                    } else {
                        blankBoard
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isHovering ? AttenColor.textSecondary.opacity(0.5) : AttenColor.border, lineWidth: 1)
            }
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

    /// A quiet typeset jacket for documents without embedded artwork.
    /// All text comes from the imported record, including the format label.
    private var blankBoard: some View {
        VStack(alignment: .leading, spacing: isList ? 6 : 18) {
            Text(book.format.displayName.uppercased())
                .font(.system(size: isList ? 5 : 8, weight: .medium))
                .tracking(isList ? 1 : 2.8)
                .foregroundStyle(AttenColor.textSecondary)
            Text(book.title)
                .font(.system(size: isList ? 9 : 23, weight: .regular, design: .serif))
                .lineLimit(isList ? 3 : 5)
                .multilineTextAlignment(.leading)
                .foregroundStyle(AttenColor.textPrimary)
            Rectangle().fill(AttenColor.separator).frame(width: isList ? 12 : 26, height: 1)
            Spacer(minLength: 0)
            if !isList, let author = book.author {
                Text(author)
                    .font(.system(size: 9, weight: .medium))
                    .tracking(2)
                    .lineLimit(2)
                    .foregroundStyle(AttenColor.textSecondary)
            }
        }
        .padding(isList ? 8 : 26)
        .padding(.top, isList ? 0 : 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AttenColor.surfaceElevated)
    }
}

struct NarrationMeter: View {
    let narrated: Int
    let total: Int
    let isRunning: Bool

    private var fraction: Double { total > 0 ? min(1, max(0, Double(narrated) / Double(total))) : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: AttenSpacing.xxs) {
            GeometryReader { geometry in
                Capsule().fill(AttenColor.progressTrack)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(narrated >= total && total > 0 ? AttenColor.success : AttenColor.accent)
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
            .font(AttenTypography.caption)
            .foregroundStyle(AttenColor.textSecondary)
            .padding(.top, 4)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
    }

    private var label: String {
        if isRunning { return "Narrating… \(narrated) of \(total) chapters" }
        if total == 0 { return "No chapters" }
        if narrated == total { return "Audiobook · \(total) chapters" }
        return "\(narrated) of \(total) chapters narrated"
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

private struct ContinueListeningCard: View {
    @Bindable var model: AppModel
    let book: BookRecord

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "headphones").font(.title2).foregroundStyle(AttenColor.accent)
            VStack(alignment: .leading, spacing: 4) {
                Text("Continue listening").font(AttenTypography.caption).foregroundStyle(AttenColor.textSecondary)
                Text(book.title).font(.headline).lineLimit(1)
                Text(book.hasBookAudio ? "Resume where you left off" : "Audio unavailable — open this book to prepare it again")
                    .font(AttenTypography.caption).foregroundStyle(AttenColor.textSecondary)
            }
            Spacer()
            Button("Open Book") { model.openInLibrary(.book(book.id)) }
                .buttonStyle(AttenSecondaryButtonStyle())
            if book.hasBookAudio {
                Button(model.playingBook?.id == book.id && model.isPlaying ? "Pause" : "Listen") { model.listen(to: book) }
                    .buttonStyle(AttenPrimaryButtonStyle())
            }
        }
        .padding(20)
        .background(AttenColor.surface, in: RoundedRectangle(cornerRadius: 10))
    }
}
