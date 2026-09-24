import AttenCore
import SwiftUI

/// The Library's own "pick up where you left off": a cover, the sentence
/// being read, and a way back in. Its background is an ambient wash of the
/// cover's own colour — the one place besides a generated cover's blobs that
/// content, not chrome, supplies the colour on screen.
struct ContinueListeningHero: View {
    @Bindable var model: AppModel
    let book: BookRecord

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shelf: BookshelfModel { model.bookshelf }
    private var isLoaded: Bool { model.playingBook?.id == book.id }
    private var isPlaying: Bool { isLoaded && model.isPlaying }

    private var seed: CoverSeed { CoverSeed(contentHash: AttenCore.LibraryItem.book(book).coverSeedKey) }

    private var rawTint: OKLCHColor {
        shelf.covers.dominantColor(for: book.id) ?? OKLCHColor(lightness: 0.6, chroma: 0.12, hue: seed.hue)
    }
    private var ambientColor: Color { AttenColor.cover(CoverPalette.ambientColor(from: rawTint)) }

    var body: some View {
        HStack(alignment: .top, spacing: AttenSpacing.lg) {
            BookJacket(
                book: book,
                cover: shelf.covers.cover(for: book.id),
                height: 148,
                dominantColor: shelf.covers.dominantColor(for: book.id),
                isPlaying: isPlaying
            )

            VStack(alignment: .leading, spacing: AttenSpacing.sm) {
                Text("Continue listening")
                    .attenText(.label)
                    .foregroundStyle(AttenColor.text2)
                Text(book.title)
                    .attenText(.title2)
                    .foregroundStyle(AttenColor.text1)
                    .lineLimit(1)
                Text(currentSentence)
                    .attenText(.reading)
                    .foregroundStyle(AttenColor.text1.opacity(0.85))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: AttenSpacing.xs)

                HStack(spacing: AttenSpacing.sm) {
                    Button(book.hasBookAudio ? (isPlaying ? "Pause" : "Listen") : "Listen") {
                        model.listen(to: book)
                    }
                    .buttonStyle(AttenSecondaryButtonStyle())
                    .disabled(!book.hasBookAudio)
                    Button("Open") { model.openInLibrary(.book(book.id)) }
                        .buttonStyle(AttenSecondaryButtonStyle())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(AttenSpacing.lg)
        .background(ambientColor.opacity(0.16))
        .background(AttenColor.surface1)
        .clipShape(RoundedRectangle(cornerRadius: AttenRadius.panel, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AttenRadius.panel, style: .continuous)
                .strokeBorder(AttenColor.hairline, lineWidth: 1)
        }
        .animation(AttenMotion.animation(reduceMotion ? AttenMotion.reducedFade : AttenMotion.ambient, reduceMotion: false), value: rawTint)
        .task(id: book.id) { await shelf.covers.load(book) }
    }

    /// From `timings.json` when the book has one, else the first sentence of
    /// whichever chapter the listening position falls in.
    private var currentSentence: String {
        if let audioURL = book.audioURL,
           let timings = try? NarrationTimings.load(beside: audioURL) {
            let (segmentIndex, _) = timings.locate(time: book.listeningPosition)
            if segmentIndex >= 0, segmentIndex < timings.segments.count {
                return Self.firstSentence(of: timings.segments[segmentIndex].text)
            }
        }
        return Self.firstSentence(of: currentChapter.text)
    }

    private var currentChapter: BookChapter {
        book.playbackChapters.first {
            book.listeningPosition >= ($0.startTime ?? 0) && book.listeningPosition < ($0.endTime ?? .infinity)
        } ?? book.playbackChapters.first ?? book.chapters[0]
    }

    private static func firstSentence(of text: String) -> String {
        var sentence: String?
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .bySentences) { substring, _, _, stop in
            sentence = substring
            stop = true
        }
        return sentence?.trimmingCharacters(in: .whitespacesAndNewlines) ?? text
    }
}

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
