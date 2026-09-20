import AttenCore
import SwiftUI
import UniformTypeIdentifiers

enum LibraryRoute: Hashable {
    case book(UUID)
    case reader(UUID)
}

struct LibraryView: View {
    @Bindable var model: AppModel
    @State private var query = ""
    @State private var isTargeted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shelf: BookshelfModel { model.bookshelf }

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
                .transition(slide(forward: model.libraryMovedForward))
        }
        .animation(
            reduceMotion ? nil : .easeOut(duration: AttenMotion.standard),
            value: model.libraryPath
        )
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            receive(providers)
        }
        .task { shelf.refreshNarrationCounts() }
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

    /// A push, but a short one. Sliding a whole window-sized screen in from the
    /// edge reads as the window itself moving; a small offset with a fade reads
    /// as a page turning.
    private func slide(forward: Bool) -> AnyTransition {
        .asymmetric(
            insertion: .offset(x: forward ? 26 : -26).combined(with: .opacity),
            removal: .offset(x: forward ? -26 : 26).combined(with: .opacity)
        )
    }

    private var shelfPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AttenSpacing.lg) {
                header
                LibraryStatusArea(shelf: shelf)
                if !shelf.books.isEmpty { searchField }

                if filteredBooks.isEmpty {
                    emptyState
                } else {
                    grid
                }
            }
            .padding(.horizontal, AttenSpacing.xl)
            .padding(.vertical, AttenSpacing.lg)
            .frame(maxWidth: 1120, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
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
        HStack(alignment: .bottom) {
            PageHeader(
                eyebrow: "Library",
                title: "Books and documents",
                detail: "Add a PDF or EPUB, read it here, and narrate it chapter by chapter."
            )
            Spacer()
            Button {
                model.openBookImportPanel()
            } label: {
                Label("Add book", systemImage: "plus")
            }
            .buttonStyle(AttenPrimaryButtonStyle())
            .disabled(shelf.isImporting)
            .fixedSize()
        }
    }

    private var searchField: some View {
        AttenSearchField(prompt: "Search library", text: $query)
            .frame(maxWidth: 280)
    }

    private var emptyState: some View {
        VStack(spacing: AttenSpacing.md) {
            AttenEmptyState(
                title: query.isEmpty ? "Your library is empty" : "No matching books",
                systemImage: "books.vertical",
                detail: query.isEmpty
                    ? "Add a PDF or EPUB — or drop one here — and Atten reads it into chapters you can listen to."
                    : "Try a different search term."
            )
            if query.isEmpty {
                Button("Add a Book") { model.openBookImportPanel() }
                    .buttonStyle(AttenPrimaryButtonStyle())
                    .fixedSize()
                    .padding(.bottom, AttenSpacing.lg)
            }
        }
        .attenSurface()
    }

    private var grid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: AttenSpacing.lg)],
            spacing: AttenSpacing.lg
        ) {
            ForEach(filteredBooks) { book in
                BookCard(
                    book: book,
                    narrated: shelf.narratedCount(of: book),
                    cover: shelf.covers.cover(for: book.id),
                    progress: shelf.progress
                ) {
                    model.openInLibrary(.book(book.id))
                }
                .task(id: book.id) { await shelf.covers.load(book) }
                .contextMenu {
                    Button("Open", systemImage: "book") { model.openInLibrary(.book(book.id)) }
                    Button("Read", systemImage: "text.alignleft") { model.openInLibrary(.reader(book.id)) }
                    Divider()
                    Button("Remove from Library", systemImage: "trash", role: .destructive) {
                        shelf.remove(book.id)
                    }
                }
            }
        }
    }

    private var filteredBooks: [BookRecord] {
        guard !query.isEmpty else { return shelf.books }
        return shelf.books.filter {
            "\($0.title) \($0.author ?? "")".localizedCaseInsensitiveContains(query)
        }
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

    var body: some View {
        if let message = shelf.successMessage {
            StatusBanner(kind: .success, message: message, dismiss: shelf.dismissStatus)
        }
        if let message = shelf.errorMessage {
            StatusBanner(kind: .error, message: message, dismiss: shelf.dismissStatus)
        }
        if shelf.isImporting {
            HStack(spacing: AttenSpacing.xs) {
                ProgressView().controlSize(.small)
                Text("Reading the book into chapters…")
                    .font(AttenTypography.metadata)
                    .foregroundStyle(AttenColor.textSecondary)
            }
        }
    }
}

/// A book on the shelf.
///
/// Books are recognised by their covers long before their titles are read, and
/// a shelf that shows none is a list with rounded corners on it. Both formats
/// carry a cover — a PDF's first page, an EPUB's named artwork — and a book
/// with none gets a plain board with its title on it, which is what a book with
/// no jacket looks like.
private struct BookCard: View {
    let book: BookRecord
    let narrated: Int
    let cover: NSImage?
    let progress: BookshelfModel.NarrationProgress?
    let open: () -> Void

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isNarrating: Bool { progress?.bookID == book.id }

    private var isFullyNarrated: Bool {
        !book.chapters.isEmpty && narrated == book.chapters.count
    }

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: AttenSpacing.sm) {
                jacket
                VStack(alignment: .leading, spacing: 2) {
                    Text(book.title)
                        .font(AttenTypography.control.weight(.semibold))
                        .foregroundStyle(AttenColor.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(book.author ?? "Unknown author")
                        .font(AttenTypography.metadata)
                        .foregroundStyle(AttenColor.textSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                NarrationMeter(
                    narrated: narrated,
                    total: book.chapters.count,
                    isRunning: isNarrating
                )
                .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        // The card is one thing to press, and it says what it is. The progress
        // meter inside it makes an element of its own, which was the only part
        // of the card VoiceOver could find; hidden, the button speaks for the
        // whole card and can still be pressed.
        .accessibilityLabel(book.title)
        .accessibilityValue(
            "\(book.author ?? "Unknown author"), \(narrated) of \(book.chapters.count) chapters narrated"
        )
        .accessibilityHint("Open this book")
    }

    private var jacket: some View {
        ZStack {
            if let cover {
                Image(nsImage: cover)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                blankBoard
            }
        }
        .frame(maxWidth: .infinity)
        // The shape of a book rather than the shape of a window.
        .aspectRatio(2.0 / 3.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: AttenRadius.card))
        .overlay {
            RoundedRectangle(cornerRadius: AttenRadius.card)
                .stroke(AttenColor.separator.opacity(0.9), lineWidth: 1)
        }
        .overlay(alignment: .topTrailing) {
            if isFullyNarrated {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(AttenColor.success)
                    .padding(6)
                    .shadow(color: .black.opacity(0.35), radius: 3)
                    .help("Fully narrated")
            }
        }
        .shadow(
            color: .black.opacity(isHovering ? 0.28 : 0.16),
            radius: isHovering ? 12 : 5,
            y: isHovering ? 5 : 2
        )
        .offset(y: isHovering ? -3 : 0)
        .animation(
            reduceMotion ? nil : .easeOut(duration: AttenMotion.standard),
            value: isHovering
        )
    }

    /// A book with no jacket: boards, and the title stamped on them.
    private var blankBoard: some View {
        ZStack {
            LinearGradient(
                colors: [AttenColor.surfaceElevated, AttenColor.surfaceMuted],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(spacing: AttenSpacing.xs) {
                Image(systemName: book.format.icon)
                    .font(.system(size: 20))
                    .foregroundStyle(AttenColor.accent.opacity(0.75))
                Text(book.title)
                    .font(.system(size: 13, weight: .medium, design: .serif))
                    .foregroundStyle(AttenColor.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
            }
            .padding(AttenSpacing.sm)
        }
    }
}

struct NarrationMeter: View {
    let narrated: Int
    let total: Int
    let isRunning: Bool

    private var fraction: Double { total > 0 ? Double(narrated) / Double(total) : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: AttenSpacing.xxs) {
            ProgressView(value: fraction)
                .progressViewStyle(.linear)
                .tint(narrated == total && total > 0 ? AttenColor.success : AttenColor.accent)
            Text(label)
                .font(AttenTypography.caption)
                .foregroundStyle(AttenColor.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
    }

    private var label: String {
        if isRunning { return "Narrating… \(narrated) of \(total) chapters" }
        if total == 0 { return "No chapters" }
        if narrated == total { return "\(total) chapters narrated" }
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
