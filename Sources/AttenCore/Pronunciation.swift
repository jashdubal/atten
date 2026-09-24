import Foundation

/// A word the voice says differently: every whole-word `match`, in any case,
/// is spoken as `say`.
public struct Pronunciation: Codable, Equatable, Hashable, Sendable {
    public var match: String
    public var say: String

    public init(match: String, say: String) {
        self.match = match
        self.say = say
    }
}

/// How long the voice rests after each paragraph. Normal is the voice's own
/// rest, which is what every book narrated before this existed has.
public enum PauseLength: String, Codable, CaseIterable, Identifiable, Sendable {
    case short, normal, long

    public var id: Self { self }

    public var title: String { rawValue.capitalized }
}

/// A chapter's text as the voice is given it, with a book's pronunciations
/// applied, and the means to put the original words back into what the
/// engine says it spoke.
///
/// Only the engine hears the substitutions. The read-along and the progress
/// through the text are built from the segments the engine returns, so each
/// one is restored — its text and its timed words — before anything sees it.
public struct PronouncedText: Sendable {
    /// What the engine is asked to say.
    public let spoken: String
    /// Each substitution made, in reading order, not yet found in a segment.
    private var pending: ArraySlice<Substitution>

    private struct Substitution: Sendable {
        let original: String
        let say: String
    }

    public init(_ text: String, pronunciations: [Pronunciation]) {
        var says: [String: String] = [:]
        for entry in pronunciations {
            let match = entry.match.trimmingCharacters(in: .whitespacesAndNewlines)
            let say = entry.say.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !match.isEmpty, !say.isEmpty, says[match.lowercased()] == nil else { continue }
            says[match.lowercased()] = say
        }
        // Longest first, so "New York" is taken before "York" can be.
        let alternatives = says.keys.sorted { $0.count > $1.count }
            .map(NSRegularExpression.escapedPattern(for:))
        guard !alternatives.isEmpty, let expression = try? NSRegularExpression(
            pattern: #"(?<![\p{L}\p{N}_])(?:"# + alternatives.joined(separator: "|") + #")(?![\p{L}\p{N}_])"#,
            options: .caseInsensitive
        ) else {
            spoken = text
            pending = []
            return
        }
        var result = ""
        var substitutions: [Substitution] = []
        var cursor = text.startIndex
        for found in expression.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(found.range, in: text),
                  let say = says[text[range].lowercased()] else { continue }
            result += text[cursor..<range.lowerBound] + say
            substitutions.append(Substitution(original: String(text[range]), say: say))
            cursor = range.upperBound
        }
        result += text[cursor...]
        spoken = result
        pending = substitutions[...]
    }

    /// `segment` as it reads in the original text: every substitution it
    /// contains put back, and the words the engine timed for one merged into
    /// a single word spanning them.
    ///
    /// Segments have to be restored in the order they were spoken.
    public mutating func restore(_ segment: TimedSegment) -> TimedSegment {
        guard !pending.isEmpty else { return segment }
        let source = segment.text
        var found: [(range: Range<String.Index>, original: String)] = []
        var cursor = source.startIndex
        while let next = nextSubstitution(in: source, from: cursor) {
            found.append((next.range, pending[next.index].original))
            // One the engine lost — split across segments, say — is skipped
            // rather than left to hold up every one after it.
            pending = pending[(next.index + 1)...]
            cursor = next.range.upperBound
        }
        guard !found.isEmpty else { return segment }

        var text = ""
        var textCursor = source.startIndex
        for substitution in found {
            text += source[textCursor..<substitution.range.lowerBound] + substitution.original
            textCursor = substitution.range.upperBound
        }
        text += source[textCursor...]

        var words: [TimedWord] = []
        var merging: Int?
        var wordCursor = source.startIndex
        for word in segment.words {
            guard let range = source.range(of: word.text, options: .caseInsensitive, range: wordCursor..<source.endIndex) else {
                words.append(word)
                merging = nil
                continue
            }
            wordCursor = range.upperBound
            guard let owner = found.firstIndex(where: { $0.range.overlaps(range) }) else {
                words.append(word)
                merging = nil
                continue
            }
            if merging == owner, let last = words.popLast() {
                words.append(TimedWord(text: last.text, start: last.start, end: max(last.end, word.end)))
            } else {
                words.append(TimedWord(text: found[owner].original, start: word.start, end: word.end))
                merging = owner
            }
        }
        return TimedSegment(index: segment.index, text: text, start: segment.start, duration: segment.duration, words: words)
    }

    /// The earliest waiting substitution that appears in `text` after `start`.
    /// A few are looked at, not just the first, in case the engine lost one.
    private func nextSubstitution(in text: String, from start: String.Index) -> (index: Int, range: Range<String.Index>)? {
        for index in pending.indices.prefix(8) {
            if let range = Self.wholeWord(pending[index].say, in: text, from: start) { return (index, range) }
        }
        return nil
    }

    private static func wholeWord(_ word: String, in text: String, from start: String.Index) -> Range<String.Index>? {
        func isWordCharacter(_ character: Character?) -> Bool {
            character.map { $0.isLetter || $0.isNumber || $0 == "_" } ?? false
        }
        var from = start
        while from < text.endIndex, let range = text.range(of: word, options: .caseInsensitive, range: from..<text.endIndex) {
            let before = range.lowerBound == text.startIndex ? nil : text[text.index(before: range.lowerBound)]
            let after = range.upperBound == text.endIndex ? nil : text[range.upperBound]
            if !isWordCharacter(before), !isWordCharacter(after) { return range }
            from = text.index(after: range.lowerBound)
        }
        return nil
    }
}
