import Foundation
import Observation

/// Stops the voice after a while, or at the end of the chapter, for someone
/// listening themselves to sleep.
///
/// Only time spent playing counts: a pause holds the countdown where it is.
/// The last ten seconds fade out rather than cut off, which would wake the
/// listener it was meant to leave asleep. Nothing about it is saved — a timer
/// still set the next morning would be a surprise.
@MainActor
@Observable
final class SleepTimer {
    enum Choice: Hashable, Sendable {
        case minutes(Int)
        case endOfChapter

        static let all: [Choice] = [.minutes(15), .minutes(30), .minutes(45), .minutes(60), .endOfChapter]

        var title: String {
            switch self {
            case let .minutes(minutes): "\(minutes) Minutes"
            case .endOfChapter: "End of Chapter"
            }
        }
    }

    /// What is playing, as far as the timer cares.
    struct Playback: Equatable {
        var isPlaying: Bool
        /// Seconds of listening, at the current rate, to the end of the
        /// chapter. Nil while that end has not been narrated yet.
        var secondsToChapterEnd: TimeInterval?
        /// Changes when playback moves into another chapter.
        var chapter: String?
    }

    nonisolated static let fadeDuration: TimeInterval = 10

    private(set) var choice: Choice?
    /// Whole seconds left, for the readout. Nil when the end of the chapter
    /// is not known yet.
    private(set) var remaining: TimeInterval?

    /// Read on every tick.
    @ObservationIgnored var observe: () -> Playback = { Playback(isPlaying: false) }
    @ObservationIgnored var setVolume: (Float) -> Void = { _ in }
    @ObservationIgnored var pause: () -> Void = {}

    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private var listened: TimeInterval = 0
    @ObservationIgnored private var lastTick: Date?
    @ObservationIgnored private var lastPlayback: Playback?
    @ObservationIgnored private var loop: Task<Void, Never>?

    init(clock: @escaping () -> Date = Date.init) {
        self.clock = clock
    }

    /// Sets the timer, or turns it off with nil.
    func set(_ choice: Choice?, ticking: Bool = true) {
        loop?.cancel()
        loop = nil
        self.choice = choice
        listened = 0
        lastTick = nil
        lastPlayback = nil
        remaining = nil
        setVolume(1)
        guard choice != nil else { return }
        tick()
        guard ticking else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self else { return }
                tick()
            }
        }
    }

    func tick() {
        guard let choice else { return }
        let now = clock()
        let playback = observe()
        if playback.isPlaying, let lastTick { listened += max(0, now.timeIntervalSince(lastTick)) }
        lastTick = playback.isPlaying ? now : nil

        let left: TimeInterval?
        switch choice {
        case let .minutes(minutes):
            left = TimeInterval(minutes * 60) - listened
        case .endOfChapter:
            // The chapter can end between two ticks, and the next one reads
            // the new chapter's whole length. Moving on from a chapter that
            // was all but over is its end; moving elsewhere by hand is not.
            if let previous = lastPlayback, previous.chapter != nil, previous.chapter != playback.chapter,
               previous.secondsToChapterEnd.map({ $0 <= Self.fadeDuration + 1 }) ?? true {
                left = 0
            } else {
                left = playback.secondsToChapterEnd
            }
        }
        lastPlayback = playback

        if let left, left <= 0 {
            pause()
            set(nil)
            return
        }
        setVolume(left.map(Self.volume(remaining:)) ?? 1)
        let shown = left.map { $0.rounded(.up) }
        if remaining != shown { remaining = shown }
    }

    /// Full volume until the last ten seconds, then down to silence.
    nonisolated static func volume(remaining: TimeInterval) -> Float {
        Float(min(1, max(0, remaining / fadeDuration)))
    }
}
