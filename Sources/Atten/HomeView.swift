import AppKit
import AttenCore
import SwiftUI

/// The shell's Home destination.
///
/// Deliberately small. This issue owns the route, the title and the fact that
/// Home exists at all; the Continue Listening hero and the cover-led library
/// row from the wireframe are #27's, and land here. What is here now is real:
/// the greeting, the book you were last reading if there is one, and the two
/// places you would otherwise go looking for.
struct HomeView: View {
    @Bindable var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AttenSpacing.xl) {
                if let book = continueReading {
                    ContinueReadingCard(
                        book: book,
                        cover: model.bookshelf.covers.cover(for: book.id)
                    ) {
                        model.section = .library
                        model.openInLibrary(.reader(book.id))
                    }
                    .task(id: book.id) { await model.bookshelf.covers.load(book) }
                }

                HStack(spacing: AttenSpacing.md) {
                    HomeRouteCard(
                        title: "Library",
                        detail: libraryDetail,
                        systemImage: "books.vertical"
                    ) {
                        model.section = .library
                    }
                    HomeRouteCard(
                        title: "Studio",
                        detail: "Turn any text into a natural-sounding voice.",
                        systemImage: "waveform"
                    ) {
                        model.section = .studio
                    }
                }
            }
            // Padding goes on before the width cap, not after it. The other
            // way round, the capped frame is handed the column's full width
            // and the padding pushes its contents past the edge — which at
            // the minimum window size overlapped the two route cards.
            .padding(.horizontal, AttenSpacing.page)
            .padding(.bottom, AttenSpacing.xl)
            .frame(maxWidth: 940, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Home's greeting *is* its title, so it goes up into the shared top
        // chrome rather than being drawn again underneath it.
        .attenScreenTitle(greeting, subtitle: "Pick up where you left off.", prominent: true)
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

    /// The book with a stored reading location, most recently added first.
    ///
    /// Atten records *where* you stopped but not *when*, so this cannot claim
    /// to be the last book you opened. Added-order is the honest stand-in
    /// until there is a timestamp to sort on — noted for #27, which needs a
    /// real recency signal for the Continue Listening hero.
    private var continueReading: BookRecord? {
        model.bookshelf.books
            .filter { $0.lastLocation != nil }
            .max { $0.addedAt < $1.addedAt }
    }

    private var libraryDetail: String {
        let count = model.bookshelf.books.count
        return switch count {
        case 0: "Add a book, a paper, or a report."
        case 1: "1 book."
        default: "\(count) books."
        }
    }
}

private struct ContinueReadingCard: View {
    let book: BookRecord
    let cover: NSImage?
    let open: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: open) {
            HStack(spacing: AttenSpacing.md) {
                jacket

                VStack(alignment: .leading, spacing: AttenSpacing.xxs) {
                    Text("CONTINUE READING")
                        .font(AttenTypography.metadata.weight(.semibold))
                        .tracking(1.2)
                        .foregroundStyle(AttenColor.accent)
                    Text(book.title)
                        .font(AttenTypography.sectionTitle)
                        .foregroundStyle(AttenColor.textPrimary)
                        .lineLimit(2)
                    if let author = book.author, !author.isEmpty {
                        Text(author)
                            .font(AttenTypography.metadata)
                            .foregroundStyle(AttenColor.textSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AttenColor.textSecondary)
            }
            .padding(AttenSpacing.md)
            .background(isHovering ? AttenColor.surfaceElevated : AttenColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: AttenRadius.card))
            .overlay {
                RoundedRectangle(cornerRadius: AttenRadius.card)
                    .stroke(AttenColor.separator, lineWidth: 1)
            }
            .contentShape(Rectangle())
            // Without this the focus ring hugs the label's intrinsic width and
            // stops short of the card it is supposed to be outlining.
            .contentShape(.focusEffect, RoundedRectangle(cornerRadius: AttenRadius.card))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel("Continue reading \(book.title)")
    }

    /// The same 2:3 board the shelf draws, at the size a row wants. A book
    /// with no artwork gets its format's glyph rather than a blank rectangle.
    private var jacket: some View {
        ZStack {
            if let cover {
                Image(nsImage: cover)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                AttenColor.surfaceMuted
                Image(systemName: book.format.icon)
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(AttenColor.textSecondary)
            }
        }
        .frame(width: 96 * AttenMetrics.coverAspectRatio, height: 96)
        .clipShape(RoundedRectangle(cornerRadius: AttenRadius.cover))
        .overlay {
            RoundedRectangle(cornerRadius: AttenRadius.cover)
                .stroke(AttenColor.separator, lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}

private struct HomeRouteCard: View {
    let title: String
    let detail: String
    let systemImage: String
    let open: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: AttenSpacing.xs) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(AttenColor.accent)
                Text(title)
                    .font(AttenTypography.sectionTitle)
                    .foregroundStyle(AttenColor.textPrimary)
                Text(detail)
                    .font(AttenTypography.metadata)
                    .foregroundStyle(AttenColor.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AttenSpacing.md)
            .background(isHovering ? AttenColor.surfaceElevated : AttenColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: AttenRadius.card))
            .overlay {
                RoundedRectangle(cornerRadius: AttenRadius.card)
                    .stroke(AttenColor.separator, lineWidth: 1)
            }
            .contentShape(Rectangle())
            // Without this the focus ring hugs the label's intrinsic width and
            // stops short of the card it is supposed to be outlining.
            .contentShape(.focusEffect, RoundedRectangle(cornerRadius: AttenRadius.card))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityHint(detail)
    }
}
