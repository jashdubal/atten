import SwiftUI

/// Playback controls for whatever Atten is playing.
///
/// A book is narrated one file per chapter, so the thing being listened to is
/// usually a queue rather than a file: the bar names the chapter and the book
/// it belongs to, says where in the book it is, and can move either way through
/// it. Ten seconds back is the control people actually reach for — a sentence
/// missed while looking away — so it sits next to play rather than in a menu.
struct PlayerBar: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: AttenSpacing.sm) {
            transport
            Divider().frame(height: 22).overlay(AttenColor.separator)
            nowPlaying
            scrubber
            rateMenu

            Button(action: model.closePlayer) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .foregroundStyle(AttenColor.textSecondary)
            .help("Stop and close the player")
            .accessibilityLabel("Close player")
        }
        .padding(.horizontal, AttenSpacing.md)
        .frame(height: 56)
        .background(AttenColor.surfaceElevated)
        .overlay(alignment: .top) {
            Divider().overlay(AttenColor.separator)
        }
    }

    // MARK: - Transport

    private var transport: some View {
        HStack(spacing: AttenSpacing.xxs) {
            TransportButton(
                systemImage: "backward.end.fill",
                size: 12,
                help: "Previous",
                label: "Previous",
                isEnabled: model.queue.hasPrevious || model.playbackPosition > 3,
                action: model.playPrevious
            )

            TransportButton(
                systemImage: "gobackward.10",
                size: 15,
                help: "Back 10 seconds",
                label: "Back ten seconds"
            ) {
                model.skip(by: -NowPlayingCenter.skipInterval)
            }

            Button(action: model.toggleActivePlayback) {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AttenColor.onAccent)
                    .frame(width: 32, height: 32)
                    .background(AttenColor.accent)
                    .clipShape(Circle())
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .help(model.isPlaying ? "Pause (⌥Space)" : "Play (⌥Space)")
            .accessibilityLabel(model.isPlaying ? "Pause" : "Play")

            TransportButton(
                systemImage: "goforward.10",
                size: 15,
                help: "Forward 10 seconds",
                label: "Forward ten seconds"
            ) {
                model.skip(by: NowPlayingCenter.skipInterval)
            }

            TransportButton(
                systemImage: "forward.end.fill",
                size: 12,
                help: "Next",
                label: "Next",
                isEnabled: model.queue.hasNext,
                action: model.playNext
            )
        }
    }

    // MARK: - What is playing

    private var nowPlaying: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(model.playerTitle ?? "")
                .font(AttenTypography.control)
                .foregroundStyle(AttenColor.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(subtitle)
                .font(AttenTypography.caption)
                .foregroundStyle(AttenColor.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(width: 190, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Now playing: \(model.playerTitle ?? ""), \(subtitle)")
    }

    private var subtitle: String {
        [model.playerSubtitle, model.queue.position]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    // MARK: - Where in it

    private var scrubber: some View {
        HStack(spacing: AttenSpacing.xs) {
            Text(Self.timeText(model.playbackPosition))
                .font(AttenTypography.caption)
                .monospacedDigit()
                .foregroundStyle(AttenColor.textSecondary)
                .frame(width: 44, alignment: .trailing)

            ScrubBar(
                position: model.playbackPosition,
                duration: model.playbackDuration,
                seek: model.seek(to:)
            )
            .frame(minWidth: 120)

            Text("-" + Self.timeText(model.playbackRemaining))
                .font(AttenTypography.caption)
                .monospacedDigit()
                .foregroundStyle(AttenColor.textSecondary)
                .frame(width: 48, alignment: .leading)
        }
    }

    // MARK: - How fast

    private var rateMenu: some View {
        Menu {
            Picker("Speed", selection: rateBinding) {
                ForEach(Self.rates, id: \.self) { rate in
                    Text(Self.rateText(rate)).tag(rate)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Text(Self.rateText(model.playbackRate))
                .font(AttenTypography.caption.weight(.semibold))
                .monospacedDigit()
                .frame(width: 38, height: 22)
                .background(AttenColor.surfaceMuted)
                .clipShape(RoundedRectangle(cornerRadius: AttenRadius.small))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Listening speed")
        .accessibilityLabel("Listening speed")
        .accessibilityValue(Self.rateText(model.playbackRate))
    }

    private var rateBinding: Binding<Double> {
        Binding(get: { model.playbackRate }, set: { model.setPlaybackRate($0) })
    }

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

// MARK: - Pieces

private struct TransportButton: View {
    let systemImage: String
    let size: CGFloat
    let help: String
    let label: String
    var isEnabled = true
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size, weight: .medium))
                .frame(width: 28, height: 28)
                .foregroundStyle(isHovering ? AttenColor.accentHover : AttenColor.textPrimary)
                .background(isHovering ? AttenColor.surfaceMuted : .clear)
                .clipShape(RoundedRectangle(cornerRadius: AttenRadius.small))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .onHover { isHovering = $0 }
        .help(help)
        .accessibilityLabel(label)
    }
}

/// The track, and where in it.
///
/// A stock `Slider` is a control for choosing a number; this is a picture of a
/// recording that happens to be draggable. It stays a thin line until the
/// pointer is over it, so a player sitting at the bottom of every screen reads
/// as a status line rather than as a row of knobs.
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
                    .fill(AttenColor.separator.opacity(0.7))
                    .frame(height: thickness)
                Capsule()
                    .fill(AttenColor.accent)
                    .frame(width: width * fraction, height: thickness)
                if isActive {
                    Circle()
                        .fill(AttenColor.accent)
                        .frame(width: 11, height: 11)
                        .offset(x: width * fraction - 5.5)
                        .shadow(color: .black.opacity(0.22), radius: 2, y: 1)
                }
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .animation(
                reduceMotion ? nil : .easeOut(duration: AttenMotion.fast),
                value: isActive
            )
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
        .accessibilityValue(PlayerBar.timeText(shown))
        .accessibilityAdjustableAction { direction in
            seek(shown + (direction == .increment ? 10 : -10))
        }
    }

    private func time(at x: CGFloat, width: CGFloat) -> TimeInterval {
        guard duration > 0 else { return 0 }
        return min(max(0, Double(x / width) * duration), duration)
    }
}
