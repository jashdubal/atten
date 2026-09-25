import AttenCore
import AVFoundation
import Foundation
import Observation

/// Plays narration as it is generated, segment by segment, so listening can
/// start before the whole book — or even the whole chapter — is done.
///
/// It schedules each segment's own WAV file onto an `AVAudioPlayerNode` as
/// `BookshelfModel` reports it ready, keeping a `ProgressiveTimeline` in step.
/// Once narration finishes, `handoff()` hands the ordinary `AVAudioPlayer`
/// path the exact position to pick up from.
@MainActor
@Observable
final class ProgressivePlayer {
    enum State: Equatable {
        case idle
        case playing
        case paused
        /// Playback has reached the end of what has been generated so far and
        /// is waiting for more — not an error.
        case catchingUp
    }

    private(set) var state: State = .idle
    private(set) var position: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    /// The book this player is following. Nil once idle.
    private(set) var bookID: UUID?
    /// Fires whenever anything a listener (Now Playing, the mini player)
    /// would want to know about changes.
    var onChange: (() -> Void)?

    var isPlaying: Bool { state == .playing || state == .catchingUp }

    struct ActiveSentence {
        let chapterIndex: Int
        let wordsBefore: Int
        let wordCount: Int
    }

    /// The sentence sounding right now, placed by `NarrationTimings` rather
    /// than the running word count the generation sweep uses.
    var activeSentence: ActiveSentence? {
        guard !timeline.placed.isEmpty else { return nil }
        let located = timeline.narrationTimings.locate(time: position)
        guard located.segment >= 0, timeline.placed.indices.contains(located.segment) else { return nil }
        let entry = timeline.placed[located.segment]
        return ActiveSentence(chapterIndex: entry.chapterIndex, wordsBefore: entry.wordsBefore, wordCount: entry.wordCount)
    }

    /// Where the chapter being heard ends, once the next one has begun.
    var chapterEnd: TimeInterval? { timeline.chapterEnd(at: position) }

    /// The sleep timer's fade.
    var volume: Float {
        get { node.volume }
        set { node.volume = newValue }
    }

    private var timeline = ProgressiveTimeline()
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private var format: AVAudioFormat?
    /// The last segment appended to the node's own queue — used to tell a
    /// stale completion (from before a seek moved the queue) from the one
    /// that means the queue has genuinely run dry.
    private var lastScheduledIndex = -1
    /// The timeline position at which the node's own clock last restarted —
    /// only a seek moves this, since a pause leaves the node's sample clock
    /// where it was.
    private var anchor: TimeInterval = 0
    private var poll: Timer?

    /// Starts (or continues) following `bookID`. A segment for a different
    /// book means narration moved on; this player starts over for it.
    func receive(bookID: UUID, chapterIndex: Int, segment: SegmentReady) {
        if self.bookID != bookID {
            reset()
            self.bookID = bookID
        }
        if format == nil, let file = try? AVAudioFile(forReading: segment.url) {
            let fileFormat = file.processingFormat
            format = fileFormat
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: fileFormat)
            engine.prepare()
        }
        timeline.append(chapterIndex: chapterIndex, url: segment.url, timing: segment.timing)
        duration = timeline.duration
        let index = timeline.placed.count - 1
        lastScheduledIndex = index
        scheduleSegment(at: index)
        if state == .catchingUp {
            node.play()
            state = .playing
            startPolling()
        }
        onChange?()
    }

    /// Plays from the current position — the start, if nothing has played
    /// yet, or wherever a pause or a catch-up left off.
    func play() {
        guard bookID != nil, !timeline.placed.isEmpty, state != .playing else { return }
        if !engine.isRunning { try? engine.start() }
        node.play()
        state = .playing
        startPolling()
        onChange?()
    }

    func pause() {
        guard state == .playing || state == .catchingUp else { return }
        node.pause()
        state = .paused
        stopPolling()
        onChange?()
    }

    func toggle() {
        isPlaying ? pause() : play()
    }

    /// Moves to `time`, clamped to what has been generated so far.
    func seek(to time: TimeInterval) {
        guard bookID != nil, !timeline.placed.isEmpty else { return }
        let target = min(max(0, time), duration)
        guard let index = timeline.index(at: target) else { return }
        let resume = isPlaying
        node.stop()
        let entry = timeline.placed[index]
        if let file = try? AVAudioFile(forReading: entry.url) {
            let offset = max(0, target - entry.start)
            let startFrame = AVAudioFramePosition((offset * file.processingFormat.sampleRate).rounded())
            let remaining = file.length - startFrame
            if remaining > 0 {
                node.scheduleSegment(
                    file, startingFrame: startFrame, frameCount: AVAudioFrameCount(remaining), at: nil,
                    completionCallbackType: .dataPlayedBack
                ) { [weak self] _ in
                    Task { @MainActor in self?.handleFinished(index: index) }
                }
            }
        }
        for later in (index + 1)..<timeline.placed.count { scheduleSegment(at: later) }
        lastScheduledIndex = timeline.placed.count - 1
        anchor = target
        position = target
        if resume {
            if !engine.isRunning { try? engine.start() }
            node.play()
            state = .playing
            startPolling()
        } else {
            state = .paused
        }
        onChange?()
    }

    /// Ends progressive playback and returns where to resume — for the
    /// ordinary `AVAudioPlayer` to pick up seamlessly once the assembled file
    /// exists.
    func handoff() -> (position: TimeInterval, wasPlaying: Bool) {
        let result = (position, isPlaying)
        reset()
        return result
    }

    /// Stops the engine unconditionally: narration was cancelled, failed, or
    /// the app is quitting. Safe to call whether or not this player is
    /// currently following anything.
    func stop() {
        reset()
    }

    private func scheduleSegment(at index: Int) {
        guard let file = try? AVAudioFile(forReading: timeline.placed[index].url) else { return }
        node.scheduleFile(file, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in self?.handleFinished(index: index) }
        }
    }

    private func handleFinished(index: Int) {
        guard index == lastScheduledIndex, state == .playing else { return }
        node.pause()
        position = duration
        state = .catchingUp
        stopPolling()
        onChange?()
    }

    private func startPolling() {
        stopPolling()
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshPosition() }
        }
        RunLoop.main.add(timer, forMode: .common)
        poll = timer
    }

    private func stopPolling() {
        poll?.invalidate()
        poll = nil
    }

    private func refreshPosition() {
        guard state == .playing, let last = node.lastRenderTime,
              let playerTime = node.playerTime(forNodeTime: last) else { return }
        position = min(anchor + Double(playerTime.sampleTime) / playerTime.sampleRate, duration)
        onChange?()
    }

    private func reset() {
        stopPolling()
        node.stop()
        if engine.isRunning { engine.stop() }
        if format != nil {
            engine.disconnectNodeOutput(node)
            engine.detach(node)
        }
        timeline = ProgressiveTimeline()
        lastScheduledIndex = -1
        anchor = 0
        position = 0
        duration = 0
        format = nil
        state = .idle
        bookID = nil
        onChange?()
    }
}
