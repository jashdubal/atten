import SwiftUI

/// Persistent playback controls for whatever audio Atten last played.
struct PlayerBar: View {
    @Bindable var model: AppModel
    @State private var scrubPosition: TimeInterval?

    var body: some View {
        HStack(spacing: AttenSpacing.sm) {
            Button(action: model.toggleActivePlayback) {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.space, modifiers: [.option])
            .help(model.isPlaying ? "Pause (⌥Space)" : "Play (⌥Space)")
            .accessibilityLabel(model.isPlaying ? "Pause" : "Play")

            Text(model.playerTitle ?? "")
                .font(AttenTypography.control)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 220, alignment: .leading)

            Text(Self.timeText(scrubPosition ?? model.playbackPosition))
                .font(AttenTypography.caption)
                .monospacedDigit()
                .foregroundStyle(AttenColor.textSecondary)

            Slider(
                value: Binding(
                    get: { scrubPosition ?? model.playbackPosition },
                    set: { scrubPosition = $0 }
                ),
                in: 0...max(model.playbackDuration, 0.1)
            ) { editing in
                if !editing, let scrubPosition {
                    model.seek(to: scrubPosition)
                    self.scrubPosition = nil
                }
            }
            .accessibilityLabel("Playback position")

            Text(Self.timeText(model.playbackDuration))
                .font(AttenTypography.caption)
                .monospacedDigit()
                .foregroundStyle(AttenColor.textSecondary)

            Button(action: model.closePlayer) {
                Image(systemName: "xmark").frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .help("Stop and close player")
            .accessibilityLabel("Close player")
        }
        .padding(.horizontal, AttenSpacing.md)
        .frame(height: 48)
        .background(AttenColor.surfaceElevated)
        .overlay(alignment: .top) {
            Divider().overlay(AttenColor.separator)
        }
    }

    static func timeText(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "0:00" }
        let total = max(0, Int(seconds.rounded(.down)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
