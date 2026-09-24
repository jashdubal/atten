import Foundation
import MediaPlayer

/// Puts what Atten is playing where macOS expects to find it.
///
/// Without this the play/pause key on the keyboard starts Music instead,
/// Control Center shows nothing, and a pair of headphones cannot skip a
/// chapter. Every app that plays audio for longer than a notification sound is
/// expected to answer here, and a text-to-speech app that reads whole books is
/// squarely one of those.
@MainActor
final class NowPlayingCenter {
    struct Commands {
        var play: () -> Void = {}
        var pause: () -> Void = {}
        var toggle: () -> Void = {}
        var next: () -> Void = {}
        var previous: () -> Void = {}
        var skip: (TimeInterval) -> Void = { _ in }
        var seek: (TimeInterval) -> Void = { _ in }
    }

    /// How far the keyboard and Control Center jump. The same interval the
    /// player's own buttons use, so the two never disagree.
    static let skipInterval: TimeInterval = 15

    private var commands = Commands()
    private var isListening = false

    func start(_ commands: Commands) {
        self.commands = commands
        guard !isListening else { return }
        isListening = true

        let centre = MPRemoteCommandCenter.shared()
        centre.playCommand.addTarget { [weak self] _ in
            self?.commands.play()
            return .success
        }
        centre.pauseCommand.addTarget { [weak self] _ in
            self?.commands.pause()
            return .success
        }
        centre.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.commands.toggle()
            return .success
        }
        centre.nextTrackCommand.addTarget { [weak self] _ in
            self?.commands.next()
            return .success
        }
        centre.previousTrackCommand.addTarget { [weak self] _ in
            self?.commands.previous()
            return .success
        }
        centre.skipForwardCommand.preferredIntervals = [NSNumber(value: Self.skipInterval)]
        centre.skipForwardCommand.addTarget { [weak self] _ in
            self?.commands.skip(Self.skipInterval)
            return .success
        }
        centre.skipBackwardCommand.preferredIntervals = [NSNumber(value: Self.skipInterval)]
        centre.skipBackwardCommand.addTarget { [weak self] _ in
            self?.commands.skip(-Self.skipInterval)
            return .success
        }
        centre.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            self?.commands.seek(event.positionTime)
            return .success
        }
    }

    func update(
        track: PlaybackTrack?,
        isPlaying: Bool,
        position: TimeInterval,
        duration: TimeInterval,
        rate: Double,
        hasNext: Bool,
        hasPrevious: Bool
    ) {
        guard let track else {
            clear()
            return
        }
        let centre = MPRemoteCommandCenter.shared()
        centre.nextTrackCommand.isEnabled = hasNext
        centre.previousTrackCommand.isEnabled = hasPrevious

        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.subtitle ?? "Atten",
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            // Zero while paused is what tells the system to stop the clock it
            // runs between updates.
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? rate : 0,
        ]
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
    }

    func clear() {
        let centre = MPRemoteCommandCenter.shared()
        centre.nextTrackCommand.isEnabled = false
        centre.previousTrackCommand.isEnabled = false
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
    }
}
