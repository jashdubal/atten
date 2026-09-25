import Foundation

/// The virtual, whole-book timeline progressive playback plays against.
///
/// It is built the same way `BookAudioAssembler` builds the real one: each
/// chapter's contribution is exactly the sum of its segments' durations, so a
/// position found here lines up with the assembled book's once narration
/// finishes and playback hands off to it.
public struct ProgressiveTimeline: Sendable {
    public struct Placed: Sendable {
        public let chapterIndex: Int
        public let url: URL
        public let timing: TimedSegment
        /// Where this segment starts in the whole-book timeline.
        public let start: TimeInterval
        /// Words of `chapterIndex` already placed before this segment.
        public let wordsBefore: Int
        public let wordCount: Int
    }

    public private(set) var placed: [Placed] = []
    public private(set) var duration: TimeInterval = 0

    private var committedDuration: TimeInterval = 0
    private var currentChapterIndex: Int?
    private var currentChapterDuration: TimeInterval = 0
    private var currentChapterWords = 0

    public init() {}

    /// Places `segment` at the end of what has been placed for `chapterIndex`
    /// so far. Chapters are expected in non-decreasing order, the way
    /// `BookshelfModel.narrate` produces them.
    @discardableResult
    public mutating func append(chapterIndex: Int, url: URL, timing: TimedSegment) -> Placed {
        if chapterIndex != currentChapterIndex {
            committedDuration += currentChapterDuration
            currentChapterDuration = 0
            currentChapterWords = 0
            currentChapterIndex = chapterIndex
        }
        let wordCount = timing.text.split(whereSeparator: \.isWhitespace).count
        let entry = Placed(
            chapterIndex: chapterIndex, url: url, timing: timing,
            start: committedDuration + timing.start, wordsBefore: currentChapterWords, wordCount: wordCount
        )
        placed.append(entry)
        currentChapterDuration = max(currentChapterDuration, timing.start + timing.duration)
        currentChapterWords += wordCount
        duration = committedDuration + currentChapterDuration
        return entry
    }

    /// The last segment starting at or before `time` — for seeking, and for
    /// finding what a given moment falls in.
    public func index(at time: TimeInterval) -> Int? {
        placed.lastIndex { $0.start <= time }
    }

    /// Where the chapter playing at `time` ends: where the next chapter's
    /// first segment starts. Nil while nothing after it has been narrated.
    public func chapterEnd(at time: TimeInterval) -> TimeInterval? {
        guard let index = index(at: time) else { return nil }
        let chapter = placed[index].chapterIndex
        return placed[(index + 1)...].first { $0.chapterIndex != chapter }?.start
    }

    /// The same segments, as `NarrationTimings` sees them, for finding the
    /// exact word sounding at a moment rather than only the sentence.
    public var narrationTimings: NarrationTimings {
        NarrationTimings(segments: placed.enumerated().map { index, entry in
            TimedSegment(
                index: index, text: entry.timing.text, start: entry.start,
                duration: entry.timing.duration, words: entry.timing.words
            )
        })
    }
}
