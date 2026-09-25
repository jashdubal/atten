import AttenCore
import SwiftUI

private enum PlayerColor {
    static let text = AttenColor.textSecondary
}

/// How playback times and rates are written, wherever they are written.
enum PlaybackFormat {
    static let rates: [Double] = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0]

    /// %g rather than %.2g: two significant digits turn 1.25 into "1.2" and
    /// 1.75 into "1.8".
    static func rateText(_ rate: Double) -> String {
        rate == rate.rounded() ? "\(Int(rate))×" : String(format: "%g×", rate)
    }

    static func timeText(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "0:00" }
        let total = max(0, Int(seconds.rounded(.down)))
        if total >= 3_600 {
            return String(format: "%d:%02d:%02d", total / 3_600, (total / 60) % 60, total % 60)
        }
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// The mini player: a glass pill floating at the foot of the content column,
/// with chapter metadata and direct seeking. The title opens Now Playing.
///
/// While Create has the window it shrinks to a ring — play or pause and how
/// far through — so it never sits over the thing being made.
struct GlobalPlayer: View {
    @Bindable var model: AppModel
    /// Create is showing.
    let isCompact: Bool
    let namespace: Namespace.ID

    var body: some View {
        if let title = model.playerTitle {
            if isCompact {
                indicator(title: title)
            } else {
                pill(title: title)
            }
        } else if let bookID = model.progressivePlayer.bookID, let book = model.bookshelf.book(id: bookID) {
            // Nothing has finished yet to hand the ordinary player, but a
            // narration in progress can already be heard.
            if isCompact {
                progressiveIndicator(title: book.title)
            } else {
                progressivePill(title: book.title)
            }
        }
    }

    private func pill(title: String) -> some View {
        HStack(spacing: 14) {
            if PlayingArtwork.Source(model: model) != nil {
                Button { model.openNowPlaying() } label: {
                    PlayingArtwork(model: model, height: 44)
                        .matchedGeometryEffect(id: PlayerMatch.cover, in: namespace)
                }
                .buttonStyle(.plain)
                .help("Open Now Playing")
                .accessibilityLabel("Open Now Playing")
            }
            HStack(spacing: 0) {
                TransportButton(
                    systemImage: "backward.end.fill", size: 12,
                    help: "Previous chapter", label: "Previous chapter",
                    isEnabled: model.hasPreviousChapter || model.playbackPosition > 3,
                    action: model.playPrevious
                )
                playPause
                    .matchedGeometryEffect(id: PlayerMatch.play, in: namespace)
                TransportButton(
                    systemImage: "forward.end.fill", size: 12,
                    help: "Next chapter", label: "Next chapter",
                    isEnabled: model.hasNextChapter,
                    action: model.playNext
                )
            }

            Rectangle().fill(AttenColor.hairline)
                .frame(width: 1, height: 30)

            VStack(alignment: .leading, spacing: 0) {
                Button { model.openNowPlaying() } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(AttenTypography.callout.weight(.semibold))
                            .foregroundStyle(AttenColor.text1)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .matchedGeometryEffect(id: PlayerMatch.title, in: namespace)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if !subtitle.isEmpty {
                            Text(subtitle)
                                .font(AttenTypography.callout)
                                .foregroundStyle(AttenColor.text2)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
                .buttonStyle(.plain)
                .help("Open Now Playing")
                .accessibilityLabel("Open Now Playing for \(title)")
                ScrubBar(
                    position: model.playbackPosition,
                    duration: model.playbackDuration,
                    seek: model.seek(to:),
                    neutral: true
                )
            }
            .frame(minWidth: 120, maxWidth: .infinity)

            Text("-" + PlaybackFormat.timeText(model.playbackRemaining))
                .font(AttenTypography.label)
                .foregroundStyle(AttenColor.text2)
                .accessibilityLabel("\(PlaybackFormat.timeText(model.playbackRemaining)) remaining")

            expandButton
        }
        .padding(.leading, AttenSpacing.sm)
        .padding(.trailing, AttenSpacing.md)
        .frame(height: AttenMetrics.playerHeight)
        .frame(maxWidth: 640)
        .attenGlass(cornerRadius: AttenMetrics.playerHeight / 2)
        .matchedGeometryEffect(id: "player", in: namespace)
        .tint(PlayerColor.text)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Player: \(title), \(subtitle)")
    }

    private func indicator(title: String) -> some View {
        playPause
            .overlay {
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(
                        model.isPlaying ? AttenColor.signal : AttenColor.text3,
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .padding(1)
                    .allowsHitTesting(false)
            }
            .padding(AttenSpacing.xxs)
            .attenGlass(cornerRadius: 24)
            .matchedGeometryEffect(id: "player", in: namespace)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Player: \(title)")
            .accessibilityValue("\(PlaybackFormat.timeText(model.playbackRemaining)) remaining")
    }

    private var fraction: Double {
        guard model.playbackDuration > 0 else { return 0 }
        return min(1, max(0, model.playbackPosition / model.playbackDuration))
    }

    /// The same pill, while a narration has nothing finished yet to hand the
    /// ordinary player but already has something to listen to.
    private func progressivePill(title: String) -> some View {
        let player = model.progressivePlayer
        return HStack(spacing: 14) {
            progressivePlayPause

            VStack(alignment: .leading, spacing: 0) {
                Button { model.openNowPlaying() } label: {
                    Text(title)
                        .font(AttenTypography.callout.weight(.semibold))
                        .foregroundStyle(AttenColor.text1)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .help("Open Now Playing")
                .accessibilityLabel("Open Now Playing for \(title)")
                ScrubBar(position: player.position, duration: player.duration, seek: player.seek(to:), neutral: true)
            }
            .frame(minWidth: 120, maxWidth: .infinity)

            Text(player.state == .catchingUp ? "Catching up…" : PlaybackFormat.timeText(player.position))
                .font(AttenTypography.label)
                .foregroundStyle(AttenColor.text2)

            expandButton
        }
        .padding(.leading, AttenSpacing.sm)
        .padding(.trailing, AttenSpacing.md)
        .frame(height: AttenMetrics.playerHeight)
        .frame(maxWidth: 640)
        .attenGlass(cornerRadius: AttenMetrics.playerHeight / 2)
        .matchedGeometryEffect(id: "player", in: namespace)
        .tint(PlayerColor.text)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Player: \(title), narrating")
    }

    private func progressiveIndicator(title: String) -> some View {
        let player = model.progressivePlayer
        let fraction = player.duration > 0 ? min(1, max(0, player.position / player.duration)) : 0
        return progressivePlayPause
            .overlay {
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(
                        player.isPlaying ? AttenColor.signal : AttenColor.text3,
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .padding(1)
                    .allowsHitTesting(false)
            }
            .padding(AttenSpacing.xxs)
            .attenGlass(cornerRadius: 24)
            .matchedGeometryEffect(id: "player", in: namespace)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Player: \(title), narrating")
    }

    private var progressivePlayPause: some View {
        let player = model.progressivePlayer
        return Button(action: player.toggle) {
            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(AttenColor.text1)
                .frame(width: 40, height: 40)
                .background(AttenColor.text1.opacity(AttenState.hoverFill), in: Circle())
                .contentShape(Circle())
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .help(player.isPlaying ? "Pause" : "Listen as it narrates")
        .accessibilityLabel(player.isPlaying ? "Pause" : "Play narration so far")
    }

    private var subtitle: String {
        [model.playerSubtitle, model.queue.position]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private var playPause: some View {
        Button(action: model.toggleActivePlayback) {
            Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(AttenColor.text1)
                .frame(width: 40, height: 40)
                .background(AttenColor.text1.opacity(AttenState.hoverFill), in: Circle())
                .contentShape(Circle())
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .help(model.isPlaying ? "Pause (⌥Space)" : "Play (⌥Space)")
        .accessibilityLabel(model.isPlaying ? "Pause" : "Play")
    }

    private var expandButton: some View {
        Button { model.openNowPlaying() } label: {
            Image(systemName: "list.bullet")
                .font(.system(size: 14, weight: .regular))
                .frame(width: 26, height: 26)
                .foregroundStyle(PlayerColor.text)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Queue and playback controls")
        .accessibilityLabel("Queue and playback controls")
        .accessibilityHint("Opens seek, skip, speed and the queue")

    }
}

private struct TransportButton: View {
    let systemImage: String
    let size: CGFloat
    let help: String
    let label: String
    var isEnabled = true
    let action: () -> Void

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size, weight: .medium))
                .frame(width: 32, height: 32)
                .foregroundStyle(PlayerColor.text)
                .background(isHovering ? AttenColor.surfaceMuted : .clear)
                .clipShape(RoundedRectangle(cornerRadius: AttenRadius.small))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : AttenState.disabledOpacity)
        .onHover { isHovering = $0 }
        .animation(
            AttenMotion.animation(AttenMotion.fast, reduceMotion: reduceMotion),
            value: isHovering
        )
        .help(help)
        .accessibilityLabel(label)
    }
}

/// The track, and where in it.
///
/// A stock `Slider` is a control for choosing a number; this is a picture of a
/// recording that happens to be draggable.
struct ScrubBar: View {
    let position: TimeInterval
    let duration: TimeInterval
    let seek: (TimeInterval) -> Void
    var neutral = false
    /// Ticked where each begins, and named under the pointer. Empty for
    /// anything with one chapter or none.
    var chapters: [ListeningMap.Chapter] = []

    @State private var dragged: TimeInterval?
    @State private var isHovering = false
    @State private var hovered: CGFloat?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shown: TimeInterval { dragged ?? position }

    private var fraction: Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, shown / duration))
    }

    private var isActive: Bool { isHovering || dragged != nil }

    private var thickness: CGFloat { isActive ? 6 : 4 }

    var body: some View {
        GeometryReader { geometry in
            let width = max(1, geometry.size.width)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(neutral ? AttenColor.textMuted.opacity(0.24) : AttenColor.progressTrack)
                    .frame(height: thickness)
                Capsule()
                    .fill(neutral ? AttenColor.textMuted : AttenColor.progress)
                    .frame(width: width * fraction, height: thickness)
                ForEach(chapters.dropFirst(), id: \.index) { chapter in
                    Capsule()
                        .fill(AttenColor.text3)
                        .frame(width: 2, height: thickness + 6)
                        .offset(x: width * tickFraction(chapter.start) - 1)
                        .allowsHitTesting(false)
                }
                if isActive {
                    Circle()
                        .fill(neutral ? AttenColor.textMuted : AttenColor.progress)
                        .frame(width: 11, height: 11)
                        .offset(x: width * fraction - 5.5)
                        .shadow(color: AttenColor.shadow.opacity(0.22), radius: 2, y: 1)
                }
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .overlay(alignment: .topLeading) { chapterLabel(width: width) }
            .onContinuousHover { phase in
                guard !chapters.isEmpty else { return }
                if case let .active(point) = phase { hovered = point.x } else { hovered = nil }
            }
            .animation(AttenMotion.animation(AttenMotion.fast, reduceMotion: reduceMotion), value: isActive)
            // A click anywhere on the track goes there, which is why the
            // gesture starts at zero distance rather than waiting for a drag.
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        dragged = time(at: value.location.x, width: width)
                    }
                    .onEnded { value in
                        seek(time(at: value.location.x, width: width))
                        dragged = nil
                    }
            )
        }
        .frame(height: 16)
        .onHover { isHovering = $0 }
        .accessibilityElement()
        .accessibilityLabel("Playback position")
        .accessibilityValue(PlaybackFormat.timeText(shown))
        .accessibilityAdjustableAction { direction in
            seek(shown + (direction == .increment ? 10 : -10))
        }
    }

    private func tickFraction(_ time: TimeInterval) -> Double {
        duration > 0 ? min(1, max(0, time / duration)) : 0
    }

    /// The chapter and time under the pointer, or under the thumb while it
    /// is dragged. Below the track, because the glass around the player
    /// clips anything above it.
    @ViewBuilder private func chapterLabel(width: CGFloat) -> some View {
        let time = dragged ?? hovered.map { self.time(at: $0, width: width) }
        if !chapters.isEmpty, let time,
           let index = ListeningMap(chapters: chapters).chapterIndex(at: time) {
            let text = "\(chapters[index].title) · \(PlaybackFormat.timeText(time))"
            let x = width * tickFraction(time)
            Text(text)
                .attenText(.label)
                .foregroundStyle(AttenColor.text1)
                .lineLimit(1)
                .padding(.horizontal, AttenSpacing.xs)
                .padding(.vertical, AttenSpacing.xxs)
                .attenElevated(.floating, radius: AttenRadius.small)
                .fixedSize()
                .alignmentGuide(.leading) { label in
                    // Centred on the pointer, but never off either end.
                    let left = min(max(0, x - label.width / 2), max(0, width - label.width))
                    return -left
                }
                .offset(y: 20)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private func time(at x: CGFloat, width: CGFloat) -> TimeInterval {
        guard duration > 0 else { return 0 }
        return min(max(0, Double(x / width) * duration), duration)
    }
}
