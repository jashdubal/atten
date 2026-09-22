import SwiftUI

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

/// The one player, in the top chrome.
///
/// Playback used to live in a 56 pt bar pinned under every screen, which cost
/// the reader a strip of page on every book and still left the reader drawing
/// its own transport — two sets of controls for one sound. This is the only
/// one now: compact enough to sit beside a page title, and holding the rest
/// behind a single expand affordance rather than putting nine controls in the
/// chrome of a reading app.
///
/// It draws nothing when nothing is playing, so a screen with no audio has no
/// player and loses no room to it.
struct GlobalPlayer: View {
    @Bindable var model: AppModel

    @State private var isExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let title = model.playerTitle {
            HStack(spacing: AttenSpacing.xs) {
                playPause

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: AttenSpacing.xs) {
                        Button { model.openNowPlaying() } label: {
                            Text(title)
                                .font(AttenTypography.control)
                                .foregroundStyle(AttenColor.textPrimary)
                                .lineLimit(1)
                                // A chapter's title is distinguished by both ends
                                // of it — "CHAPTER 9: …Ongoing Success" — so the
                                // middle is what goes.
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .help("Open Now Playing")
                        .accessibilityLabel("Open Now Playing for \(title)")
                        Spacer(minLength: AttenSpacing.xxs)
                        Text("-" + PlaybackFormat.timeText(model.playbackRemaining))
                            .font(AttenTypography.timecode)
                            .foregroundStyle(AttenColor.textSecondary)
                    }
                    progressLine
                }
                .frame(minWidth: 120, idealWidth: 210, maxWidth: 260)

                expandButton
            }
            .padding(.horizontal, AttenSpacing.sm)
            .frame(height: AttenMetrics.compactPlayerHeight)
            .attenElevated(
                .raised,
                radius: AttenRadius.player,
                fill: AttenColor.surfaceElevated
            )
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Player: \(title), \(subtitle)")
            .onChange(of: model.playerTitle) { _, title in
                // Playback can stop while the popover is open. Its anchor then
                // disappears; close the local state with it to avoid a stale
                // overlay being restored when another track starts.
                if title == nil { isExpanded = false }
            }
            .onDisappear { isExpanded = false }
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
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AttenColor.onAccent)
                .frame(width: 28, height: 28)
                .background(Circle().fill(AttenColor.accent))
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .buttonStyle(AttenFeedbackButtonStyle())
        .help(model.isPlaying ? "Pause (⌥Space)" : "Play (⌥Space)")
        .accessibilityLabel(model.isPlaying ? "Pause" : "Play")
    }

    /// A status line, not a control. Seeking is in the expanded panel, where
    /// there is room to hit it.
    private var progressLine: some View {
        GeometryReader { geometry in
            let fraction = model.playbackDuration > 0
                ? min(1, max(0, model.playbackPosition / model.playbackDuration))
                : 0
            ZStack(alignment: .leading) {
                Capsule().fill(AttenColor.progressTrack)
                Capsule()
                    .fill(AttenColor.progress)
                    .frame(width: geometry.size.width * fraction)
            }
        }
        .frame(height: 3)
        .accessibilityHidden(true)
    }

    private var expandButton: some View {
        Button { isExpanded.toggle() } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .semibold))
                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                .frame(width: 26, height: 26)
                .foregroundStyle(AttenColor.textSecondary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .buttonStyle(AttenFeedbackButtonStyle())
        .animation(
            AttenMotion.animation(AttenMotion.fast, reduceMotion: reduceMotion),
            value: isExpanded
        )
        .help("Playback controls")
        .accessibilityLabel("Playback controls")
        .accessibilityHint("Opens seek, skip, speed and the queue")
        .popover(isPresented: $isExpanded, arrowEdge: .bottom) {
            ExpandedPlayerPanel(model: model, close: { isExpanded = false })
        }
    }
}

/// Everything the compact player does not show.
///
/// A popover rather than a sheet: it is dismissed by Escape and by clicking
/// away without either being wired up here, and it does not take the window
/// hostage while a chapter is playing.
struct ExpandedPlayerPanel: View {
    @Bindable var model: AppModel
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AttenSpacing.md) {
            heading
            scrubber
            transport
            Divider().overlay(AttenColor.separator)
            speed
            if model.queue.tracks.count > 1 { queue }
            stop
        }
        .padding(AttenSpacing.md)
        .frame(width: AttenMetrics.expandedPlayerWidth)
        .background(AttenColor.surface)
        .background(.ultraThinMaterial)
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(model.playerTitle ?? "Nothing playing")
                .font(AttenTypography.sectionTitle)
                .foregroundStyle(AttenColor.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if let source = model.playerSubtitle {
                Text(source)
                    .font(AttenTypography.metadata)
                    .foregroundStyle(AttenColor.textSecondary)
                    .lineLimit(1)
            }
            if let position = model.queue.position {
                Text(position)
                    .font(AttenTypography.metadata)
                    .foregroundStyle(AttenColor.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var scrubber: some View {
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
    }

    private var transport: some View {
        HStack(spacing: AttenSpacing.xs) {
            Spacer(minLength: 0)
            if model.queue.tracks.count > 1 {
                TransportButton(
                    systemImage: "backward.end.fill",
                    size: 12,
                    help: "Previous chapter",
                    label: "Previous chapter",
                    isEnabled: model.queue.hasPrevious || model.playbackPosition > 3,
                    action: model.playPrevious
                )
            }
            TransportButton(
                systemImage: "gobackward.10",
                size: 16,
                help: "Back 10 seconds",
                label: "Back ten seconds"
            ) {
                model.skip(by: -NowPlayingCenter.skipInterval)
            }
            Button(action: model.toggleActivePlayback) {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AttenColor.onAccent)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(AttenColor.accent))
                    .shadow(color: .black.opacity(0.35), radius: 10, y: 3)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .buttonStyle(AttenFeedbackButtonStyle())
            .help(model.isPlaying ? "Pause (⌥Space)" : "Play (⌥Space)")
            .accessibilityLabel(model.isPlaying ? "Pause" : "Play")
            TransportButton(
                systemImage: "goforward.10",
                size: 16,
                help: "Forward 10 seconds",
                label: "Forward ten seconds"
            ) {
                model.skip(by: NowPlayingCenter.skipInterval)
            }
            if model.queue.tracks.count > 1 {
                TransportButton(
                    systemImage: "forward.end.fill",
                    size: 12,
                    help: "Next chapter",
                    label: "Next chapter",
                    isEnabled: model.queue.hasNext,
                    action: model.playNext
                )
            }
            Spacer(minLength: 0)
        }
    }

    private var speed: some View {
        HStack {
            Text("Speed")
                .font(AttenTypography.control)
                .foregroundStyle(AttenColor.textPrimary)
            Spacer()
            Picker("Speed", selection: rateBinding) {
                ForEach(PlaybackFormat.rates, id: \.self) { rate in
                    Text(PlaybackFormat.rateText(rate)).tag(rate)
                }
            }
            .labelsHidden()
            .fixedSize()
            .accessibilityLabel("Listening speed")
            .accessibilityValue(PlaybackFormat.rateText(model.playbackRate))
        }
    }

    /// The rest of the book, when there is a rest of the book. A one-off
    /// Studio render has a queue of one and gets no list.
    private var queue: some View {
        VStack(alignment: .leading, spacing: AttenSpacing.xs) {
            Text("UP NEXT")
                .font(AttenTypography.metadata.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(AttenColor.textSecondary)

            ScrollView {
                VStack(spacing: 1) {
                    ForEach(Array(model.queue.tracks.enumerated()), id: \.element.id) { index, track in
                        QueueRow(
                            track: track,
                            number: index + 1,
                            isCurrent: index == model.queue.index
                        ) {
                            model.play(tracks: model.queue.tracks, startingAt: index)
                        }
                    }
                }
            }
            .frame(maxHeight: 168)
        }
    }

    private var stop: some View {
        Button {
            model.closePlayer()
            close()
        } label: {
            Label("Stop and close", systemImage: "stop.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(AttenSecondaryButtonStyle())
        .accessibilityLabel("Stop and close the player")
    }

    private var rateBinding: Binding<Double> {
        Binding(get: { model.playbackRate }, set: { model.setPlaybackRate($0) })
    }
}

private struct QueueRow: View {
    let track: PlaybackTrack
    let number: Int
    let isCurrent: Bool
    let play: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: play) {
            HStack(spacing: AttenSpacing.xs) {
                Text("\(number)")
                    .font(AttenTypography.timecode)
                    .foregroundStyle(AttenColor.textSecondary)
                    .frame(width: 20, alignment: .trailing)
                Text(track.title)
                    .font(AttenTypography.metadata)
                    .foregroundStyle(isCurrent ? AttenColor.accent : AttenColor.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                if isCurrent {
                    Image(systemName: "waveform")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AttenColor.accent)
                }
            }
            .padding(.horizontal, AttenSpacing.xs)
            .frame(height: 26)
            .background(rowBackground)
            .clipShape(RoundedRectangle(cornerRadius: AttenRadius.small))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .buttonStyle(AttenFeedbackButtonStyle())
        .onHover { isHovering = $0 }
        .accessibilityLabel("Chapter \(number), \(track.title)")
        .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)
    }

    private var rowBackground: Color {
        if isCurrent { return AttenColor.accent.opacity(0.12) }
        return isHovering ? AttenColor.surfaceMuted : .clear
    }
}

// MARK: - Pieces

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
                .foregroundStyle(isHovering ? AttenColor.accentHover : AttenColor.textPrimary)
                .background(isHovering ? AttenColor.surfaceMuted : .clear)
                .clipShape(RoundedRectangle(cornerRadius: AttenRadius.small))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .buttonStyle(AttenFeedbackButtonStyle())
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
                    .fill(AttenColor.progressTrack)
                    .frame(height: thickness)
                Capsule()
                    .fill(AttenColor.progress)
                    .frame(width: width * fraction, height: thickness)
                if isActive {
                    Circle()
                        .fill(AttenColor.progress)
                        .frame(width: 11, height: 11)
                        .offset(x: width * fraction - 5.5)
                        .shadow(color: .black.opacity(0.22), radius: 2, y: 1)
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
