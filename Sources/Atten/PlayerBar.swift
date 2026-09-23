import SwiftUI

private enum PlayerColor {
    static let text = AttenColor.textSecondary
}

/// How playback times and rates are written, wherever they are written.
enum PlaybackFormat {
    static let rates: [Double] = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

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

/// A floating bottom transport with chapter metadata and direct seeking. The queue,
/// expanded controls open the shared Now Playing destination.
struct GlobalPlayer: View {
    @Bindable var model: AppModel
    @Binding var isCollapsed: Bool
    var compact = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let title = model.playerTitle {
            HStack(spacing: 14) {
                HStack(spacing: 0) {
                    if !compact && !isCollapsed {
                        TransportButton(
                            systemImage: "backward.end.fill", size: 12,
                            help: "Previous chapter", label: "Previous chapter",
                            isEnabled: model.hasPreviousChapter || model.playbackPosition > 3,
                            action: model.playPrevious
                        )
                    }
                    playPause
                    if !compact && !isCollapsed {
                        TransportButton(
                            systemImage: "forward.end.fill", size: 12,
                            help: "Next chapter", label: "Next chapter",
                            isEnabled: model.hasNextChapter,
                            action: model.playNext
                        )
                    }
                }

                if !isCollapsed {
                    Rectangle().fill(AttenColor.separator.opacity(0.6))
                        .frame(width: 1, height: 30)

                    VStack(alignment: .leading, spacing: 0) {
                        Button { model.openNowPlaying() } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(title)
                                    .font(AttenTypography.control.weight(.semibold))
                                    .foregroundStyle(AttenColor.textPrimary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                if !compact, !subtitle.isEmpty {
                                    Text(subtitle)
                                        .font(AttenTypography.caption)
                                        .foregroundStyle(AttenColor.textMuted)
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
                    .frame(minWidth: compact ? 100 : 160, maxWidth: .infinity)

                    Text("-" + PlaybackFormat.timeText(model.playbackRemaining))
                        .font(AttenTypography.timecode)
                        .foregroundStyle(AttenColor.textMuted)
                        .accessibilityLabel("\(PlaybackFormat.timeText(model.playbackRemaining)) remaining")

                    expandButton
                }
                collapseButton
            }
            .padding(.horizontal, isCollapsed ? 10 : (compact ? 12 : 18))
            .frame(height: isCollapsed ? 48 : (compact ? 54 : 72))
            .background(AttenColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: AttenRadius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AttenRadius.card, style: .continuous)
                    .strokeBorder(AttenColor.separator, lineWidth: 1)
            }
            .shadow(
                color: AttenColor.shadow.opacity(AttenElevation.raised.shadowOpacity),
                radius: AttenElevation.raised.shadowRadius,
                y: AttenElevation.raised.shadowY
            )
            .tint(PlayerColor.text)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Player: \(title), \(subtitle)")
        }
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
                .foregroundStyle(AttenColor.textPrimary)
                .frame(width: 40, height: 40)
                .background(AttenColor.textPrimary.opacity(0.08), in: Circle())
                .contentShape(Rectangle())
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .help(model.isPlaying ? "Pause (⌥Space)" : "Play (⌥Space)")
        .accessibilityLabel(model.isPlaying ? "Pause" : "Play")
    }

    private var collapseButton: some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: AttenMotion.standard)) {
                isCollapsed.toggle()
            }
        } label: {
            Image(systemName: isCollapsed ? "chevron.up" : "chevron.down")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(PlayerColor.text)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isCollapsed ? "Expand player" : "Collapse player")
        .accessibilityLabel(isCollapsed ? "Expand player" : "Collapse player")
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

    @State private var dragged: TimeInterval?
    @State private var isHovering = false
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

    private func time(at x: CGFloat, width: CGFloat) -> TimeInterval {
        guard duration > 0 else { return 0 }
        return min(max(0, Double(x / width) * duration), duration)
    }
}
