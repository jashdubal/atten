import AppKit
import AttenCore
import SwiftUI

/// The cover of whatever is playing, at any size: the book's own artwork
/// when it has some, and otherwise the generated cover it is shown with
/// everywhere else.
struct PlayingArtwork: View {
    /// What the artwork is of. Nil for audio with no record behind it — a
    /// voice preview, a playground sample — which has no cover to show.
    struct Source {
        let id: String
        let title: String
        let book: BookRecord?
        private let project: ProjectRecord?

        @MainActor
        init?(model: AppModel) {
            if let book = model.playingBook {
                id = book.id.uuidString
                title = book.title
                self.book = book
                project = nil
            } else if let project = model.playingProject {
                id = project.id.uuidString
                title = project.title
                book = nil
                self.project = project
            } else {
                return nil
            }
        }

        /// The same seed the Library draws a generated cover from.
        var seed: String {
            if let book { return book.contentHash ?? book.title }
            return project.map { ContentHash.of($0.text) } ?? id
        }
    }

    @Bindable var model: AppModel
    let height: CGFloat

    var body: some View {
        let width = height * AttenMetrics.coverAspectRatio
        Group {
            if let source = Source(model: model) {
                if let book = source.book, let cover = model.bookshelf.covers.cover(for: book.id) {
                    Image(nsImage: cover)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    GeneratedCover(title: source.title, contentHash: source.seed)
                }
            } else {
                ZStack {
                    AttenColor.surfaceMuted
                    Image(systemName: "waveform")
                        .font(.system(size: height / 4, weight: .light))
                        .foregroundStyle(AttenColor.text3)
                }
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: AttenRadius.cover, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AttenRadius.cover, style: .continuous)
                .strokeBorder(AttenColor.glassHighlight, lineWidth: 0.5)
        }
        .task(id: model.playingBook?.id) {
            if let book = model.playingBook { await model.bookshelf.covers.load(book) }
        }
        .accessibilityHidden(true)
    }
}
