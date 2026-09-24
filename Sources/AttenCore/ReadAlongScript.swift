import Foundation

/// One sentence of a narration, as the read-along player lays it out.
public struct ReadAlongSentence: Identifiable, Equatable, Sendable {
    public let id: Int
    public let text: String
    /// When it starts being spoken, in seconds from the top of the track.
    public let start: Double
    /// Sentences of one paragraph share this, so the player can space
    /// paragraphs apart without a row of its own for each gap.
    public let paragraph: Int
}

/// Where the playhead is: the sentence being spoken, and the word within it
/// as a range of `Character` offsets into the sentence's text.
public struct ReadAlongPlace: Equatable, Sendable {
    public let sentence: Int
    public let word: Range<Int>?

    public init(sentence: Int, word: Range<Int>? = nil) {
        self.sentence = sentence
        self.word = word
    }
}

/// A narration broken into sentences, with each timed word placed inside the
/// sentence it belongs to.
///
/// Timed narration comes as segments — a paragraph, or part of a long one —
/// each with its own word times. A segment is too coarse to highlight and a
/// word is too fine to read by, so the sentence is the unit the player shows,
/// and a word is only ever underlined inside one.
public struct ReadAlongScript: Equatable, Sendable {
    public let sentences: [ReadAlongSentence]
    /// Nil when the words were never timed and sentence times are estimated
    /// from their length; the player then highlights sentences alone.
    public let timings: NarrationTimings?
    /// For each segment of `timings`, where each of its words landed.
    private let places: [[ReadAlongPlace?]]

    public var hasWordTimings: Bool { timings != nil }

    public static let empty = ReadAlongScript(sentences: [], timings: nil, places: [])

    private init(sentences: [ReadAlongSentence], timings: NarrationTimings?, places: [[ReadAlongPlace?]]) {
        self.sentences = sentences
        self.timings = timings
        self.places = places
    }

    /// From word timings: segment times are exact, and a sentence starts on
    /// its first word.
    public init(timings: NarrationTimings) {
        var sentences: [ReadAlongSentence] = []
        var places: [[ReadAlongPlace?]] = []
        for (paragraph, segment) in timings.segments.enumerated() {
            let text = Array(segment.text)
            // Lowered once here rather than a character at a time in `find`.
            let lowered = Array(segment.text.lowercased())
            let haystack = lowered.count == text.count ? lowered : text
            let spans = Self.sentenceSpans(segment.text)
            let first = sentences.count
            var starts = spans.map {
                // Until a word says otherwise, a sentence starts as far into
                // the segment as its first character is into the text.
                segment.start + segment.duration * Double($0.lowerBound) / Double(max(1, text.count))
            }
            var cursor = 0
            var segmentPlaces: [ReadAlongPlace?] = []
            var timed: Set<Int> = []
            for word in segment.words {
                guard let found = Self.find(word.text, in: haystack, from: cursor),
                      let span = spans.firstIndex(where: { $0.contains(found.lowerBound) }) else {
                    segmentPlaces.append(nil)
                    continue
                }
                cursor = found.upperBound
                let offset = spans[span].lowerBound
                if timed.insert(span).inserted { starts[span] = segment.start + word.start }
                segmentPlaces.append(ReadAlongPlace(
                    sentence: first + span,
                    word: (found.lowerBound - offset)..<(min(found.upperBound, spans[span].upperBound) - offset)
                ))
            }
            for (index, span) in spans.enumerated() {
                let start = max(starts[index], sentences.last?.start ?? 0)
                sentences.append(ReadAlongSentence(
                    id: sentences.count, text: String(text[span]), start: start, paragraph: paragraph
                ))
            }
            places.append(segmentPlaces)
        }
        self.init(sentences: sentences, timings: timings, places: places)
    }

    /// Without word timings: each passage is spread over its stretch of the
    /// recording by length, which is close enough to follow by the sentence.
    public init(estimating passages: [(text: String, start: Double, end: Double)]) {
        var sentences: [ReadAlongSentence] = []
        var paragraph = 0
        for passage in passages {
            let paragraphs = passage.text.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            let total = paragraphs.reduce(0) { $0 + $1.count }
            guard total > 0 else { continue }
            let duration = max(0, passage.end - passage.start)
            var consumed = 0
            for text in paragraphs {
                let characters = Array(text)
                for span in Self.sentenceSpans(text) {
                    let start = passage.start + duration * Double(consumed + span.lowerBound) / Double(total)
                    sentences.append(ReadAlongSentence(
                        id: sentences.count, text: String(characters[span]), start: start, paragraph: paragraph
                    ))
                }
                consumed += characters.count
                paragraph += 1
            }
        }
        self.init(sentences: sentences, timings: nil, places: [])
    }

    /// The sentence at `time`, and the word being spoken in it. Both are
    /// binary searches, so this is cheap enough to run every frame.
    public func locate(time: Double) -> ReadAlongPlace? {
        guard !sentences.isEmpty, time.isFinite else { return nil }
        if let timings {
            let found = timings.locate(time: time)
            if let word = found.word, places.indices.contains(found.segment),
               places[found.segment].indices.contains(word), let place = places[found.segment][word] {
                return place
            }
        }
        var lower = 0, upper = sentences.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if sentences[middle].start <= time { lower = middle + 1 } else { upper = middle }
        }
        return ReadAlongPlace(sentence: max(0, lower - 1))
    }

    /// Sentence ranges in `Character` offsets, with the space around each
    /// trimmed off.
    static func sentenceSpans(_ text: String) -> [Range<Int>] {
        var spans: [Range<Int>] = []
        var offset = 0
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .bySentences) { sentence, _, enclosing, _ in
            let length = text[enclosing].count
            defer { offset += length }
            guard let sentence else { return }
            let leading = text[enclosing].prefix { $0.isWhitespace }.count
            let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines).count
            guard trimmed > 0 else { return }
            spans.append((offset + leading)..<(offset + leading + trimmed))
        }
        if spans.isEmpty, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let characters = Array(text)
            let start = characters.firstIndex { !$0.isWhitespace } ?? 0
            let end = (characters.lastIndex { !$0.isWhitespace } ?? characters.count - 1) + 1
            spans = [start..<end]
        }
        return spans
    }

    /// A timed word in the text, near the cursor. Punctuation the engine
    /// timed as a token of its own is not a word to underline, and a word
    /// that cannot be found close by is skipped rather than allowed to drag
    /// the cursor somewhere far ahead.
    private static func find(_ word: String, in text: [Character], from cursor: Int) -> Range<Int>? {
        let needle = Array(word.lowercased())
        guard needle.contains(where: { $0.isLetter || $0.isNumber }), cursor < text.count else { return nil }
        let limit = min(text.count - needle.count, cursor + 64)
        guard limit >= cursor else { return nil }
        for start in cursor...limit where text[start..<(start + needle.count)].elementsEqual(needle) {
            return start..<(start + needle.count)
        }
        return nil
    }
}
