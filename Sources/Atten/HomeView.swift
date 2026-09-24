import AppKit
import AttenCore
import SwiftUI

/// The shell's Home destination: what you were in the middle of, and the
/// shelf it came from.
///
/// The wireframe puts one thing at the top of this screen and it is not a
/// menu — it is the book you are already listening to, large enough to press
/// without aiming. Everything here is drawn from the real shelf and the real
/// player: Home has no library of its own and no second playback engine, so
/// the hero's play button and the compact player in the top chrome are the
/// same button wearing different clothes.
struct HomeView: View {
    @Bindable var model: AppModel

    private var shelf: BookshelfModel { model.bookshelf }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AttenSpacing.xl) {
                if !shelf.books.isEmpty { search }

                if let book = heroBook {
                    ContinueHero(model: model, book: book)
                        .task(id: book.id) { await shelf.covers.load(book) }
                } else {
                    FirstBookInvitation { model.openBookImportPanel() }
                }

                LibraryRow(model: model)
            }
            // Padding goes on before the width cap, not after it. The other
            // way round, the capped frame is handed the column's full width
            // and the padding pushes its contents past the edge — which at
            // the minimum window size overlapped the two route cards.
            .padding(.horizontal, AttenSpacing.page)
            .padding(.bottom, AttenSpacing.xl)
            .attenScrollPadding()
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Home's greeting *is* its title, so it goes up into the shared top
        // chrome rather than being drawn again underneath it.
        .attenScreenTitle(greeting, subtitle: shelfSummary, prominent: true)
    }

    private var search: some View {
        AttenSearchField(prompt: "Search your library", text: $model.libraryQuery)
            .frame(maxWidth: 320)
            // Home has nowhere to show results, and inventing a second list
            // of them would be a second copy of the shelf's filtering rules.
            // Typing here goes to the shelf, which already knows how.
            .onSubmit { model.searchLibrary(for: model.libraryQuery) }
    }

    private var greeting: String {
        let name = NSFullUserName().split(separator: " ").first.map(String.init)
        let hour = Calendar.current.component(.hour, from: Date())
        let time = switch hour {
        case 0..<12: "Good morning"
        case 12..<18: "Good afternoon"
        default: "Good evening"
        }
        return name.map { "\(time), \($0)." } ?? "\(time)."
    }

    private var shelfSummary: String {
        switch shelf.books.count {
        case 0: "Add your first book to get started."
        case 1: "One book on your shelf."
        default: "\(shelf.books.count) books on your shelf."
        }
    }

    /// What the hero is about, in the order the user would answer it
    /// themselves: whatever is playing, then whatever they last opened, then
    /// — for a shelf that has been imported and never read — the newest book.
    /// Nothing at all only when there is nothing at all.
    private var heroBook: BookRecord? {
        model.playingBook ?? shelf.recentlyOpened.first ?? shelf.books.first
    }
}

// MARK: - Continue

/// The one large card: cover, where you are, and the controls to carry on.
private struct ContinueHero: View {
    @Bindable var model: AppModel
    let book: BookRecord

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shelf: BookshelfModel { model.bookshelf }

    /// Whether the player is on *this* book, which is what decides between
    /// showing the live timeline and showing where reading stopped.
    private var isLoaded: Bool { model.playingBook?.id == book.id }

    private var narratedCount: Int { shelf.narratedCount(of: book) }

    private var isNarrating: Bool { shelf.progress?.bookID == book.id }

    var body: some View {
        HStack(alignment: .top, spacing: AttenSpacing.lg) {
            BookJacket(
                book: book,
                cover: shelf.covers.cover(for: book.id),
                height: 168,
                dominantColor: shelf.covers.dominantColor(for: book.id),
                isPlaying: isLoaded && model.isPlaying
            )

            VStack(alignment: .leading, spacing: AttenSpacing.sm) {
                Text(eyebrow)
                    .font(AttenTypography.metadata.weight(.semibold))
                    .tracking(2.0)
                    .foregroundStyle(AttenColor.accent)

                VStack(alignment: .leading, spacing: AttenSpacing.xxs) {
                    Text(book.title)
                        .font(AttenTypography.pageTitle)
                        .foregroundStyle(AttenColor.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(positionLine)
                        .font(AttenTypography.metadata)
                        .foregroundStyle(AttenColor.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: AttenSpacing.xs)

                timeline
                controls
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(AttenSpacing.lg)
        .attenElevated(.raised, fill: AttenColor.surface)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(eyebrow.capitalized): \(book.title). \(positionLine)")
    }

    private var eyebrow: String {
        if isNarrating { return "PREPARING NARRATION" }
        if isLoaded { return model.isPlaying ? "NOW PLAYING" : "CONTINUE LISTENING" }
        if narratedCount > 0 { return "CONTINUE LISTENING" }
        return "CONTINUE READING"
    }

    /// Where the user is, said in whichever terms Atten actually knows. A book
    /// in the player has a chapter and a clock; a book only ever read has a
    /// chapter and nothing more; a book never opened has neither, and says so
    /// rather than claiming chapter one.
    private var positionLine: String {
        if isNarrating, let progress = shelf.progress {
            return "Narrating \(progress.chapterTitle) — \(progress.completed) of \(progress.total) \(noun.lowercased())s ready"
        }
        if isLoaded, let title = model.playerTitle {
            return [title, model.queue.position].compactMap { $0 }.joined(separator: " · ")
        }
        if let location = book.lastLocation,
           book.chapters.indices.contains(location.chapterIndex) {
            let chapter = book.chapters[location.chapterIndex]
            return "\(noun) \(location.chapterIndex + 1) of \(book.chapters.count) · \(chapter.title)"
        }
        if book.chapters.isEmpty { return book.author ?? "No sections yet" }
        return "Not started · \(book.chapters.count) \(noun.lowercased())s"
    }

    private var noun: String { book.format.sectionNoun }

    /// The live timeline when this book is the one in the player, and the
    /// share of the book read otherwise. Both are measured; neither is a
    /// decoration filled in to make the card look finished.
    @ViewBuilder private var timeline: some View {
        Group {
            if isLoaded {
                VStack(spacing: 2) {
                    ScrubBar(
                        position: model.playbackPosition,
                        duration: model.playbackDuration,
                        seek: model.seek(to:)
                    )
                    HStack {
                        Text(PlaybackFormat.timeText(model.playbackPosition))
                        Spacer()
                        Text("-" + PlaybackFormat.timeText(model.playbackRemaining))
                    }
                    .font(AttenTypography.timecode)
                    .foregroundStyle(AttenColor.textSecondary)
                }
            } else if isNarrating, let progress = shelf.progress {
                ProgressView(value: progress.fraction)
                    .progressViewStyle(.linear)
                    .tint(AttenColor.accent)
            } else if !book.chapters.isEmpty {
                NarrationMeter(
                    narrated: narratedCount,
                    total: book.chapters.count,
                    isRunning: false
                )
            }
        }
        // Keep Read/Listen/Play controls anchored when a book starts or stops.
        // The contents change; the card's geometry does not jump with it.
        .frame(minHeight: 28, alignment: .top)
    }

    private var readButton: some View {
        Button {
            model.section = .library
            model.openInLibrary(.reader(book.id))
        } label: {
            Label("Read", systemImage: "text.alignleft")
        }
    }

    @ViewBuilder private var controls: some View {
        HStack(spacing: AttenSpacing.xs) {
            if isLoaded {
                Button(action: model.toggleActivePlayback) {
                    Label(
                        model.isPlaying ? "Pause" : "Play",
                        systemImage: model.isPlaying ? "pause.fill" : "play.fill"
                    )
                }
                .buttonStyle(AttenPrimaryButtonStyle())
                .accessibilityLabel(model.isPlaying ? "Pause" : "Play")
                Button("Now Playing", systemImage: "waveform") {
                    model.openNowPlaying()
                }
                .buttonStyle(AttenSecondaryButtonStyle())
            } else if narratedCount > 0 {
                Button {
                    model.listen(to: book)
                } label: {
                    Label("Listen", systemImage: "play.fill")
                }
                .buttonStyle(AttenPrimaryButtonStyle())
                .accessibilityHint("Play the narrated \(noun.lowercased())s of this book")
            }

            if narratedCount > 0 || isLoaded {
                readButton.buttonStyle(AttenSecondaryButtonStyle())
            } else {
                readButton.buttonStyle(AttenPrimaryButtonStyle())
            }

            Button {
                model.section = .library
                model.openInLibrary(.book(book.id))
            } label: {
                Label("Details", systemImage: "info.circle")
            }
            .buttonStyle(AttenSecondaryButtonStyle())

            Spacer(minLength: 0)
        }
        .animation(AttenMotion.fade(reduceMotion: reduceMotion), value: isLoaded)
    }
}

/// A shelf with nothing on it says what to do about it, rather than showing an
/// empty hero-shaped hole where a book is supposed to be.
private struct FirstBookInvitation: View {
    let add: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AttenSpacing.sm) {
            Text("NOTHING ON THE SHELF YET")
                .font(AttenTypography.metadata.weight(.semibold))
                .tracking(2.0)
                .foregroundStyle(AttenColor.accent)
            Text("Add your first book")
                .font(AttenTypography.pageTitle)
                .foregroundStyle(AttenColor.textPrimary)
            Text("A PDF, an EPUB, a Kindle book, a paper, a report. Atten reads it into sections, and narrates them in a voice you pick — all on this machine.")
                .font(AttenTypography.body)
                .foregroundStyle(AttenColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Add a Book", systemImage: "plus", action: add)
                .buttonStyle(AttenPrimaryButtonStyle())
                .fixedSize()
                .padding(.top, AttenSpacing.xxs)
        }
        .frame(maxWidth: 520, alignment: .leading)
        .padding(AttenSpacing.lg)
        .attenElevated(.raised, fill: AttenColor.surface)
    }
}

// MARK: - The shelf, in one row

/// Covers, in the order they were last opened, and somewhere to add another.
///
/// The wireframe's lower band is the shelf seen edge-on: enough of it to
/// recognise a book by its jacket, and a way through to the rest. It is a row
/// rather than a grid because Home is about resuming, and the grid already
/// exists one click away.
private struct LibraryRow: View {
    @Bindable var model: AppModel

    private var shelf: BookshelfModel { model.bookshelf }

    /// Recently opened first, then the rest by import date, so the row starts
    /// with the books in play and still reaches everything. Capped, because a
    /// shelf of four hundred books is a scroll view nobody uses horizontally.
    private var books: [BookRecord] {
        let recent = shelf.recentlyOpened
        let seen = Set(recent.map(\.id))
        return Array((recent + shelf.books.filter { !seen.contains($0.id) }).prefix(18))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AttenSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text("Your library")
                    .font(AttenTypography.sectionTitle)
                    .foregroundStyle(AttenColor.textPrimary)
                Spacer()
                if !shelf.books.isEmpty {
                    Button("See all") {
                        model.libraryQuery = ""
                        model.section = .library
                    }
                    .buttonStyle(.plain)
                    .font(AttenTypography.control)
                    .foregroundStyle(AttenColor.accent)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: AttenSpacing.md) {
                    ForEach(books) { book in
                        ShelfTile(
                            book: book,
                            cover: shelf.covers.cover(for: book.id),
                            dominantColor: shelf.covers.dominantColor(for: book.id),
                            narrated: shelf.narratedCount(of: book)
                        ) {
                            model.section = .library
                            model.openInLibrary(.book(book.id))
                        }
                        .task(id: book.id) { await shelf.covers.load(book) }
                    }
                    AddBookTile(isImporting: shelf.isImporting) {
                        model.openBookImportPanel()
                    }
                }
                // A scroll view clips its contents to its bounds, and the
                // jackets' shadows live outside theirs. Without the room they
                // were sliced off square along the bottom of the row.
                .padding(.vertical, AttenSpacing.xs)
                .padding(.horizontal, 2)
            }
        }
    }
}

private struct ShelfTile: View {
    let book: BookRecord
    let cover: NSImage?
    let dominantColor: OKLCHColor?
    let narrated: Int
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: AttenSpacing.xs) {
                BookJacket(book: book, cover: cover, height: 132, dominantColor: dominantColor)
                Text(book.title)
                    .font(AttenTypography.metadata.weight(.medium))
                    .foregroundStyle(AttenColor.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 132 * AttenMetrics.coverAspectRatio, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(book.title)
        .accessibilityValue(narrated > 0
            ? "\(narrated) of \(book.chapters.count) narrated"
            : "not narrated")
        .accessibilityHint("Open this book")
    }
}

/// The wireframe's Add Book tile: the same size and shape as a book, at the
/// end of the row where the next one would go.
private struct AddBookTile: View {
    let isImporting: Bool
    let add: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: add) {
            VStack(spacing: AttenSpacing.xs) {
                if isImporting {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .light))
                }
                Text(isImporting ? "Reading…" : "Add book")
                    .font(AttenTypography.metadata)
            }
            .foregroundStyle(isHovering ? AttenColor.accent : AttenColor.textSecondary)
            .frame(
                width: 132 * AttenMetrics.coverAspectRatio,
                height: 132
            )
            .background {
                RoundedRectangle(cornerRadius: AttenRadius.cover, style: .continuous)
                    .fill(AttenColor.surfaceMuted.opacity(isHovering ? 0.9 : 0.5))
            }
            .overlay {
                RoundedRectangle(cornerRadius: AttenRadius.cover, style: .continuous)
                    .strokeBorder(
                        isHovering ? AttenColor.accent : AttenColor.separator,
                        style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                    )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isImporting)
        .onHover { isHovering = $0 }
        .accessibilityLabel("Add a book")
    }
}

// MARK: - Pieces

/// The 2:3 board a book is recognised by, at whatever size the caller wants.
/// A book with no artwork of its own gets a generated cover rather than a
/// blank rectangle, which is what an unjacketed book looks like on a real
/// shelf.
struct BookJacket: View {
    let book: BookRecord
    let cover: NSImage?
    let height: CGFloat
    var dominantColor: OKLCHColor?
    var isPlaying = false

    private var seed: CoverSeed { CoverSeed(contentHash: AttenCore.LibraryItem.book(book).coverSeedKey) }

    /// A real cover's shadow is tinted by its own dominant colour; a
    /// generated one is tinted by the same seed its blobs are drawn from, so
    /// neither ever falls back to a flat black shadow.
    private var shadowTint: OKLCHColor {
        dominantColor ?? OKLCHColor(lightness: 0.6, chroma: 0.1, hue: seed.hue)
    }

    var body: some View {
        Group {
            if let cover {
                Image(nsImage: cover)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                GeneratedCover(
                    title: book.title,
                    contentHash: AttenCore.LibraryItem.book(book).coverSeedKey,
                    sourceLabel: book.author ?? book.format.displayName,
                    state: AttenCore.LibraryItem.book(book).state,
                    isPlaying: isPlaying
                )
            }
        }
        .frame(width: height * AttenMetrics.coverAspectRatio, height: height)
        .attenCoverFrame(tint: shadowTint)
        .accessibilityHidden(true)
    }
}
