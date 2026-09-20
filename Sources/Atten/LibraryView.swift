import AttenCore
import SwiftUI
import UniformTypeIdentifiers

enum LibraryRoute: Hashable {
    case book(UUID)
    case reader(UUID)
}

struct LibraryView: View {
    @Bindable var model: AppModel
    @State private var path: [LibraryRoute] = []
    @State private var query = ""
    @State private var isTargeted = false

    private var shelf: BookshelfModel { model.bookshelf }

    var body: some View {
        NavigationStack(path: $path) {
            shelfPage
                .navigationDestination(for: LibraryRoute.self) { route in
                    destination(for: route)
                }
        }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            receive(providers)
        }
    }

    @ViewBuilder private func destination(for route: LibraryRoute) -> some View {
        switch route {
        case let .book(id):
            if let book = shelf.book(id: id) {
                BookDetailView(model: model, book: book) { path.append(.reader(id)) }
            } else {
                AttenEmptyState(
                    title: "Book removed",
                    systemImage: "book.closed",
                    detail: "This book is no longer in your library."
                )
            }
        case let .reader(id):
            if let book = shelf.book(id: id) {
                BookReaderView(model: model, book: book)
            } else {
                AttenEmptyState(
                    title: "Book removed",
                    systemImage: "book.closed",
                    detail: "This book is no longer in your library."
                )
            }
        }
    }

    private var shelfPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AttenSpacing.lg) {
                header
                LibraryStatusArea(shelf: shelf)

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
        .searchable(text: $query, placement: .toolbar, prompt: "Search library")
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
            columns: [GridItem(.adaptive(minimum: 240, maximum: 340), spacing: AttenSpacing.md)],
            spacing: AttenSpacing.md
        ) {
            ForEach(filteredBooks) { book in
                BookCard(book: book, progress: shelf.progress) {
                    path.append(.book(book.id))
                }
                .contextMenu {
                    Button("Open", systemImage: "book") { path.append(.book(book.id)) }
                    Button("Read", systemImage: "text.alignleft") { path.append(.reader(book.id)) }
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

private struct BookCard: View {
    let book: BookRecord
    let progress: BookshelfModel.NarrationProgress?
    let open: () -> Void

    @State private var isHovering = false

    private var isNarrating: Bool { progress?.bookID == book.id }

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: AttenSpacing.sm) {
                HStack(spacing: AttenSpacing.xs) {
                    Image(systemName: book.format.icon)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AttenColor.accent)
                    Text(book.format.displayName)
                        .font(AttenTypography.caption)
                        .foregroundStyle(AttenColor.textSecondary)
                    Spacer(minLength: 0)
                    if book.isFullyNarrated {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(AttenColor.success)
                            .help("Fully narrated")
                    }
                }

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

                Spacer(minLength: 0)

                NarrationMeter(
                    narrated: book.narratedCount,
                    total: book.chapters.count,
                    isRunning: isNarrating
                )
            }
            .frame(height: 148, alignment: .topLeading)
            .attenSurface(elevated: isHovering)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel("\(book.title), \(book.narratedCount) of \(book.chapters.count) chapters narrated")
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
