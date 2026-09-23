import AppKit
import AttenCore
import SwiftUI

/// The audio-first destination. It is deliberately a view over `AppModel`,
/// not another player: the timeline, transport, and queue all address the
/// same `AVAudioPlayer` that powers the compact player and system commands.
struct NowPlayingView: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var track: PlaybackTrack? { model.queue.current }
    private var book: BookRecord? { model.playingBook }
    private var project: ProjectRecord? { model.playingProject }
    private var isBookAudio: Bool { book != nil }
    private var hasChapterQueue: Bool {
        isBookAudio && (book?.playbackChapters.count ?? 0) > 1
    }

    var body: some View {
        Group {
            if track == nil {
                emptyState
            } else {
                player
            }
        }
        .attenScreenTitle("Now Playing", subtitle: track?.subtitle)
    }

    private var emptyState: some View {
        VStack(spacing: AttenSpacing.md) {
            AttenEmptyState(
                title: "Nothing playing",
                systemImage: "waveform",
                detail: "Prepare a book or create audio and its controls will appear here."
            )
            Button("Go to Library", systemImage: "books.vertical") {
                model.returnToShelf()
            }
            .buttonStyle(AttenPrimaryButtonStyle())
            .fixedSize()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(AttenSpacing.xl)
        .background(AttenBackdrop())
    }

    private var player: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: AttenSpacing.xl) {
                    if proxy.size.width >= 760 {
                        HStack(alignment: .top, spacing: AttenSpacing.xl) {
                            artwork
                            details
                        }
                    } else {
                        VStack(alignment: .leading, spacing: AttenSpacing.lg) {
                            artwork
                            details
                        }
                    }

                    if hasChapterQueue {
                        chapterQueue
                            .transition(
                                AttenMotion.transition(
                                    .fade,
                                    reduceMotion: reduceMotion
                                )
                            )
                    }
                }
                .padding(.horizontal, proxy.size.width < 700 ? AttenSpacing.lg : AttenSpacing.xl)
                .padding(.vertical, AttenSpacing.xl)
                .frame(maxWidth: 1080, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .background(AttenBackdrop())
        .animation(
            AttenMotion.transitionAnimation(
                AttenMotion.standard,
                reduceMotion: reduceMotion
            ),
            value: hasChapterQueue
        )
    }

    private var artwork: some View {
        Group {
            if let book {
                BookJacket(
                    book: book,
                    cover: model.bookshelf.covers.cover(for: book.id),
                    height: 280
                )
                .task(id: book.id) {
                    await model.bookshelf.covers.load(book)
                }
                .accessibilityLabel("Cover for \(book.title)")
            } else {
                audioPlaceholder
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var audioPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [AttenColor.surfaceElevated, AttenColor.surfaceMuted],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "waveform")
                .font(.system(size: 72, weight: .light))
                .foregroundStyle(AttenColor.accent)
        }
        .frame(
            width: 280 * AttenMetrics.coverAspectRatio,
            height: 280
        )
        .clipShape(RoundedRectangle(cornerRadius: AttenRadius.cover, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AttenRadius.cover, style: .continuous)
                .strokeBorder(AttenColor.separator, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Audio artwork placeholder")
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: AttenSpacing.lg) {
            VStack(alignment: .leading, spacing: AttenSpacing.xs) {
                Text(book == nil ? "AUDIO" : "BOOK AUDIO")
                    .font(AttenTypography.metadata.weight(.semibold))
                    .tracking(2)
                    .foregroundStyle(AttenColor.accent)
                Text(track?.title ?? "Nothing playing")
                    .font(AttenTypography.displayTitle)
                    .foregroundStyle(AttenColor.textPrimary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                metadata
            }

            timeline
            transport
            speed
            actions
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var metadata: some View {
        if let book {
            Text([
                book.title,
                book.author,
                book.format.displayName,
                model.queue.position,
            ].compactMap { $0 }.joined(separator: " · "))
            .font(AttenTypography.body)
            .foregroundStyle(AttenColor.textSecondary)
            .lineLimit(2)
        } else if let project {
            let voice = VoiceCatalog.voice(id: project.voiceID)?.name ?? project.voiceID
            Text(["Create", voice, project.format.displayName]
                .joined(separator: " · "))
                .font(AttenTypography.body)
                .foregroundStyle(AttenColor.textSecondary)
                .lineLimit(2)
        } else if let subtitle = track?.subtitle {
            Text(subtitle)
                .font(AttenTypography.body)
                .foregroundStyle(AttenColor.textSecondary)
        }
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: AttenSpacing.xs) {
            ScrubBar(
                position: model.playbackPosition,
                duration: model.playbackDuration,
                seek: model.seek(to:)
            )
            .frame(minHeight: 20)
            HStack {
                Text(PlaybackFormat.timeText(model.playbackPosition))
                Spacer()
                Text("-" + PlaybackFormat.timeText(model.playbackRemaining))
            }
            .font(AttenTypography.timecode)
            .foregroundStyle(AttenColor.textSecondary)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Playback timeline")
        .accessibilityValue("\(PlaybackFormat.timeText(model.playbackPosition)) elapsed, \(PlaybackFormat.timeText(model.playbackRemaining)) remaining")
    }

    private var transport: some View {
        HStack(spacing: AttenSpacing.sm) {
            Spacer(minLength: 0)
            if hasChapterQueue {
                nowPlayingTransportButton(
                    systemImage: "backward.end.fill",
                    label: "Previous chapter",
                    isEnabled: model.hasPreviousChapter,
                    action: model.playPrevious
                )
            }
            nowPlayingTransportButton(
                systemImage: "gobackward.10",
                label: "Back ten seconds",
                action: { model.skip(by: -NowPlayingCenter.skipInterval) }
            )
            Button(action: model.toggleActivePlayback) {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(AttenColor.onAccent)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(AttenColor.accent))
                    .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .buttonStyle(AttenFeedbackButtonStyle())
            .help(model.isPlaying ? "Pause" : "Play")
            .accessibilityLabel(model.isPlaying ? "Pause" : "Play")
            nowPlayingTransportButton(
                systemImage: "goforward.10",
                label: "Forward ten seconds",
                action: { model.skip(by: NowPlayingCenter.skipInterval) }
            )
            if hasChapterQueue {
                nowPlayingTransportButton(
                    systemImage: "forward.end.fill",
                    label: "Next chapter",
                    isEnabled: model.hasNextChapter,
                    action: model.playNext
                )
            }
            Spacer(minLength: 0)
        }
    }

    private func nowPlayingTransportButton(
        systemImage: String,
        label: String,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 40, height: 40)
                .foregroundStyle(isEnabled ? AttenColor.textPrimary : AttenColor.textSecondary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .buttonStyle(AttenFeedbackButtonStyle())
        .disabled(!isEnabled)
        .help(label)
        .accessibilityLabel(label)
    }

    private var speed: some View {
        HStack {
            Text("Listening speed")
                .font(AttenTypography.control)
                .foregroundStyle(AttenColor.textPrimary)
            Spacer()
            Picker("Listening speed", selection: rateBinding) {
                ForEach(PlaybackFormat.rates, id: \.self) { rate in
                    Text(PlaybackFormat.rateText(rate)).tag(rate)
                }
            }
            .labelsHidden()
            .fixedSize()
            .accessibilityValue(PlaybackFormat.rateText(model.playbackRate))
        }
    }

    @ViewBuilder private var actions: some View {
        HStack(spacing: AttenSpacing.sm) {
            if let book {
                Button("Read", systemImage: "text.alignleft") {
                    model.section = .library
                    model.openInLibrary(.reader(book.id))
                }
                .buttonStyle(AttenSecondaryButtonStyle())
                .help("Read this book")
                Button("Book Details", systemImage: "book.closed") { model.openInLibrary(.book(book.id)) }
                    .buttonStyle(AttenSecondaryButtonStyle())
                Button("Export…", systemImage: "square.and.arrow.up") { model.exportBook(book) }
                    .buttonStyle(AttenSecondaryButtonStyle())
                    .disabled(model.isExportingBook)
            }
            if project != nil {
                Button("Open Create", systemImage: "waveform") {
                    model.section = .studio
                }
                .buttonStyle(AttenSecondaryButtonStyle())
            }
            Spacer(minLength: 0)
        }
    }

    private func timestamp(_ time: Double) -> String {
        let seconds = Int(time)
        return String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
    }

    private var chapterQueue: some View {
        VStack(alignment: .leading, spacing: AttenSpacing.sm) {
            Text("CHAPTERS")
                .font(AttenTypography.metadata.weight(.semibold))
                .tracking(1.4)
                .foregroundStyle(AttenColor.textSecondary)

            VStack(spacing: 1) {
                if let book {
                    ForEach(Array(book.playbackChapters.enumerated()), id: \.element.id) { index, chapter in
                        Button { model.listen(to: book, chapter: chapter) } label: {
                            HStack {
                                Text("\(index + 1). \(chapter.title)")
                                    .lineLimit(1)
                                Spacer()
                                Text(timestamp(chapter.startTime ?? 0))
                                    .monospacedDigit()
                            }
                            .padding(AttenSpacing.sm)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .background(AttenColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: AttenRadius.card))
            .overlay {
                RoundedRectangle(cornerRadius: AttenRadius.card)
                    .stroke(AttenColor.separator.opacity(0.72), lineWidth: 1)
            }
        }
    }

    private var rateBinding: Binding<Double> {
        Binding(get: { model.playbackRate }, set: { model.setPlaybackRate($0) })
    }
}
