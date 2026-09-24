import AttenCore
import SwiftUI

/// The Library's own "pick up where you left off," distinct from Home's
/// larger hero: a cover, the sentence being read, and a way back in. Its
/// background is an ambient wash of the cover's own colour — the one place
/// besides a generated cover's blobs that content, not chrome, supplies the
/// colour on screen.
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
    private var ambientColor: Color { Color(CoverPalette.ambientColor(from: rawTint)) }

    private var progress: Double {
        guard let total = book.playbackChapters.last?.endTime, total > 0 else { return 0 }
        return min(1, max(0, book.listeningPosition / total))
    }

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
                    ProgressArc(progress: progress)
                        .frame(width: 22, height: 22)
                    Button(book.hasBookAudio ? (isPlaying ? "Pause" : "Listen") : "Listen") {
                        model.listen(to: book)
                    }
                    .buttonStyle(AttenPrimaryButtonStyle(
                        disabledReason: book.hasBookAudio ? nil : "Prepare this book to listen"
                    ))
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

/// A quiet ring of progress — how far into the book listening has gotten.
private struct ProgressArc: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle().stroke(AttenColor.progressTrack, lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(AttenColor.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .accessibilityHidden(true)
    }
}
