import AppKit
import AttenCore
import SwiftUI

/// The sidebar's quiet word that narration is under way, which opens the
/// queue behind it. Only a narration actually generating lights it.
struct NarrationQueueIndicator: View {
    let model: AppModel

    @State private var isShowingQueue = false
    @State private var isHovering = false

    private var shelf: BookshelfModel { model.bookshelf }

    var body: some View {
        if !shelf.queue.isEmpty {
            Button { isShowingQueue.toggle() } label: {
                HStack(spacing: AttenSpacing.xs) {
                    Image(systemName: "waveform")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(shelf.isNarrating ? AttenColor.signal : AttenColor.text3)
                        .frame(width: 18)
                    Text(status)
                    Spacer(minLength: 0)
                    Text("\(shelf.queue.count)")
                }
                .attenText(.label)
                .foregroundStyle(AttenColor.text2)
                .padding(.horizontal, AttenSpacing.sm)
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                .background(
                    AttenColor.textPrimary.opacity(isShowingQueue || isHovering ? AttenState.hoverFill / 2 : 0),
                    in: RoundedRectangle(cornerRadius: AttenRadius.control, style: .continuous)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }
            .popover(isPresented: $isShowingQueue, arrowEdge: .trailing) {
                NarrationQueuePanel(model: model)
            }
            .accessibilityLabel("Narration queue, \(status), \(shelf.queue.count) \(shelf.queue.count == 1 ? "book" : "books")")
        }
    }

    private var status: String {
        if shelf.isNarrating { return "Generating" }
        return shelf.queue.allSatisfy(\.isPaused) ? "Paused" : "Queued"
    }
}

/// Every narration waiting for the engine, in the order it will get it.
/// Rows drag to reorder.
struct NarrationQueuePanel: View {
    let model: AppModel

    @Environment(\.attenIsOffscreenRender) private var isOffscreenRender

    private var shelf: BookshelfModel { model.bookshelf }
    private static let rowHeight: CGFloat = 60

    var body: some View {
        VStack(alignment: .leading, spacing: AttenSpacing.xs) {
            Text("Queue")
                .attenText(.label)
                .foregroundStyle(AttenColor.text2)
                .padding(.horizontal, AttenSpacing.sm)
                .accessibilityAddTraits(.isHeader)
            // A `List` draws nothing offscreen, so a render lays the rows
            // out flat.
            if isOffscreenRender {
                VStack(spacing: 0) {
                    ForEach(shelf.queue) { row($0) }
                }
            } else {
                List {
                    ForEach(shelf.queue) { row($0) }
                        .onMove { shelf.moveQueue(fromOffsets: $0, toOffset: $1) }
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .frame(height: min(CGFloat(shelf.queue.count) * Self.rowHeight, 360))
            }
        }
        .padding(.vertical, AttenSpacing.sm)
        .padding(.horizontal, AttenSpacing.xxs)
        .frame(width: 380)
    }

    @ViewBuilder private func row(_ entry: QueuedNarration) -> some View {
        if let book = shelf.book(id: entry.bookID) {
            NarrationQueueRow(
                shelf: shelf,
                book: book,
                isPaused: entry.isPaused,
                estimator: model.settings.listenEstimator
            )
            .frame(height: Self.rowHeight)
        }
    }
}

private struct NarrationQueueRow: View {
    let shelf: BookshelfModel
    let book: BookRecord
    let isPaused: Bool
    let estimator: ListenEstimator

    private var progress: BookshelfModel.NarrationProgress? {
        shelf.narratingBookID == book.id ? shelf.progress : nil
    }
    private var isRunning: Bool { progress != nil }
    private var completed: Int { progress?.completed ?? shelf.narratedCount(of: book) }

    private var eta: String {
        if progress?.isCombining == true { return "Finishing" }
        let seconds = estimator.generationTime(
            audioSeconds: estimator.listenDuration(words: shelf.remainingWords(for: book.id), voiceID: book.voiceID)
        )
        return ListenEstimator.remainingLabel(seconds)
    }

    var body: some View {
        HStack(spacing: AttenSpacing.sm) {
            thumbnail
            VStack(alignment: .leading, spacing: AttenSpacing.xxs) {
                Text(book.title)
                    .font(AttenTypography.callout.weight(.semibold))
                    .foregroundStyle(AttenColor.textPrimary)
                    .lineLimit(1)
                Text("\(completed) of \(book.chapters.count) chapters · \(isPaused ? "Paused" : eta)")
                    .font(AttenTypography.callout)
                    .foregroundStyle(AttenColor.text2)
                    .lineLimit(1)
                if isRunning {
                    GeometryReader { geometry in
                        Capsule().fill(AttenColor.progressTrack)
                            .overlay(alignment: .leading) {
                                Capsule().fill(AttenColor.signal)
                                    .frame(width: geometry.size.width * (progress?.fraction ?? 0))
                            }
                    }
                    .frame(height: 3)
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                Button {
                    if isPaused { shelf.resumeNarration(book.id) } else { shelf.pauseNarration(book.id) }
                } label: {
                    Image(systemName: isPaused ? "play.fill" : "pause.fill")
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .disabled(isPaused && !shelf.canStartNarration)
                .accessibilityLabel(isPaused ? "Resume \(book.title)" : "Pause \(book.title)")
                Button { shelf.removeFromQueue(book.id) } label: {
                    Image(systemName: "xmark")
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Remove \(book.title) from the queue")
            }
        }
        .buttonStyle(.plain)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(AttenColor.text2)
        .padding(.horizontal, AttenSpacing.sm)
        .contentShape(Rectangle())
        .task(id: book.id) { await shelf.covers.load(book) }
    }

    /// Only the book generating keeps its colour.
    private var thumbnail: some View {
        Group {
            if let cover = shelf.covers.cover(for: book.id) {
                Image(nsImage: cover).resizable().aspectRatio(contentMode: .fill)
            } else {
                GeneratedCover(
                    title: book.title,
                    contentHash: AttenCore.LibraryItem.book(book).coverSeedKey,
                    state: AttenCore.LibraryItem.book(book).state
                )
            }
        }
        .frame(width: 30, height: 30 / AttenMetrics.coverAspectRatio)
        .clipShape(RoundedRectangle(cornerRadius: AttenRadius.small / 2, style: .continuous))
        .grayscale(isRunning ? 0 : 1)
        .opacity(isRunning ? 1 : 0.7)
    }
}
