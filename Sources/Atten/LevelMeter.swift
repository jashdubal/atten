import AVFoundation
import Foundation

/// How loud the voice is right now, smoothed into something that breathes
/// rather than flickers.
///
/// Read once per frame by the few views that glow with it. Deliberately not
/// observable: a level that changes every frame, published through the model,
/// would re-evaluate every view that touches the model sixty times a second.
@MainActor
final class LevelMeter {
    /// The player being measured. Weak, so a player the model lets go of
    /// stops being measured without anyone having to say so.
    weak var player: AVAudioPlayer?

    /// Where the playhead is, read straight from the player rather than from
    /// the model's five-times-a-second copy.
    var currentTime: TimeInterval { player?.currentTime ?? 0 }

    private var envelope = LevelEnvelope()
    private var lastSample: Date?

    /// The smoothed level, 0…1. Asking twice in one frame gives the same
    /// answer, so two views reading it do not advance it twice.
    func level(at date: Date) -> Double {
        guard date != lastSample else { return envelope.value }
        let elapsed = lastSample.map { date.timeIntervalSince($0) } ?? 0
        lastSample = date
        var input = 0.0
        if let player, player.isPlaying {
            player.updateMeters()
            input = LevelEnvelope.normalized(decibels: Double(player.averagePower(forChannel: 0)))
        }
        return envelope.follow(input, elapsed: elapsed)
    }
}

/// An envelope follower: quick to rise and slow to fall, the way a meter's
/// needle moves, so syllables read as breath rather than as noise.
struct LevelEnvelope: Equatable {
    static let attack = 0.03
    static let release = 0.2
    /// Speech sits well above this; room tone and silence below it.
    static let floor = -50.0

    private(set) var value = 0.0

    /// Maps average power in dBFS onto 0…1.
    static func normalized(decibels: Double) -> Double {
        guard decibels.isFinite else { return 0 }
        return min(1, max(0, (decibels - floor) / -floor))
    }

    mutating func follow(_ input: Double, elapsed: TimeInterval) -> Double {
        let time = input > value ? Self.attack : Self.release
        let coefficient = elapsed > 0 ? 1 - exp(-elapsed / time) : 0
        value += (input - value) * coefficient
        return value
    }
}
