import Foundation

public struct TimedWord: Codable, Equatable, Sendable {
    public let text: String
    public let start: Double
    public let end: Double

    public init(text: String, start: Double, end: Double) {
        self.text = text
        self.start = start
        self.end = end
    }
}

public struct TimedSegment: Codable, Equatable, Sendable {
    public let index: Int
    public let text: String
    public let start: Double
    public let duration: Double
    /// Word times are relative to this segment, even in a combined book.
    public let words: [TimedWord]

    public init(index: Int, text: String, start: Double, duration: Double, words: [TimedWord]) {
        self.index = index
        self.text = text
        self.start = start
        self.duration = duration
        self.words = words
    }

    public func estimatingMissingWords() -> TimedSegment {
        guard words.isEmpty, duration > 0 else { return self }
        var sentences: [String] = []
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .bySentences) {
            sentence, _, _, _ in
            if let sentence { sentences.append(sentence) }
        }
        if sentences.isEmpty { sentences = [text] }
        let totalCharacters = sentences.reduce(0) { $0 + $1.count }
        guard totalCharacters > 0 else { return self }
        var estimated: [TimedWord] = []
        var sentenceStart = 0.0
        for sentence in sentences {
            let sentenceDuration = duration * Double(sentence.count) / Double(totalCharacters)
            var tokens: [String] = []
            sentence.enumerateSubstrings(in: sentence.startIndex..<sentence.endIndex, options: .byWords) {
                word, _, _, _ in
                if let word { tokens.append(word) }
            }
            let characters = tokens.reduce(0) { $0 + $1.count }
            var offset = sentenceStart
            for word in tokens {
                let end = offset + sentenceDuration * Double(word.count) / Double(characters)
                estimated.append(TimedWord(text: word, start: offset, end: end))
                offset = end
            }
            sentenceStart += sentenceDuration
        }
        return TimedSegment(index: index, text: text, start: start, duration: duration, words: estimated)
    }
}

public struct NarrationTimings: Codable, Equatable, Sendable {
    public let segments: [TimedSegment]

    public init(segments: [TimedSegment]) {
        self.segments = segments.sorted { $0.start < $1.start }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(segments: try container.decode([TimedSegment].self, forKey: .segments))
    }

    /// Returns array positions, with -1 for an empty timeline. In silence or
    /// outside the recording, the nearest preceding segment has no active word.
    public func locate(time: Double) -> (segment: Int, word: Int?) {
        guard !segments.isEmpty, !time.isNaN else { return (-1, nil) }
        let segmentIndex = max(0, Self.precedingIndex(in: segments, time: time, start: { $0.start }))
        let segment = segments[segmentIndex]
        let relative = time - segment.start
        guard relative >= 0, relative < segment.duration else { return (segmentIndex, nil) }
        let wordIndex = Self.precedingIndex(in: segment.words, time: relative, start: { $0.start })
        guard wordIndex >= 0, relative < segment.words[wordIndex].end else { return (segmentIndex, nil) }
        return (segmentIndex, wordIndex)
    }

    private static func precedingIndex<T>(in values: [T], time: Double, start: (T) -> Double) -> Int {
        var lower = 0
        var upper = values.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if start(values[middle]) <= time { lower = middle + 1 }
            else { upper = middle }
        }
        return lower - 1
    }

    public func offset(by seconds: Double, startingAt index: Int = 0) -> NarrationTimings {
        NarrationTimings(segments: segments.enumerated().map { position, segment in
            TimedSegment(index: index + position, text: segment.text, start: segment.start + seconds,
                         duration: segment.duration, words: segment.words)
        })
    }

    public static func sidecarURL(for audioURL: URL) -> URL {
        audioURL.deletingLastPathComponent().appendingPathComponent("timings.json")
    }

    public static func load(beside audioURL: URL) throws -> NarrationTimings? {
        let url = sidecarURL(for: audioURL)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }

    public func save(beside audioURL: URL) throws {
        try JSONEncoder().encode(self).write(to: Self.sidecarURL(for: audioURL), options: .atomic)
    }
}
