import AttenCore
import Foundation
import XCTest

final class WordTimingsTests: XCTestCase {
    func testBinarySearchEdgesGapsAndRelativeWordTimes() {
        let words = [TimedWord(text: "one", start: 0.2, end: 0.5), TimedWord(text: "two", start: 0.7, end: 1)]
        let timings = NarrationTimings(segments: [
            TimedSegment(index: 0, text: "one two", start: 0, duration: 1, words: words),
            TimedSegment(index: 1, text: "one two", start: 2, duration: 1, words: words)
        ])
        for (time, segment, word) in [( -1.0, 0, nil), (0, 0, nil), (0.2, 0, 0),
            (0.5, 0, nil), (0.7, 0, 1), (1, 0, nil), (1.5, 0, nil),
            (2, 1, nil), (2.3, 1, 0), (3, 1, nil), (100, 1, nil)] as [(Double, Int, Int?)] {
            let location = timings.locate(time: time)
            XCTAssertEqual(location.segment, segment, "time: \(time)")
            XCTAssertEqual(location.word, word, "time: \(time)")
        }
        XCTAssertEqual(NarrationTimings(segments: []).locate(time: 0).segment, -1)
        XCTAssertNil(timings.locate(time: .nan).word)
    }

    func testSentenceAndWordCharacterProportionsAndEmptyText() throws {
        let timing = TimedSegment(index: 0, text: "A bee. Two!", start: 10, duration: 11, words: [])
            .estimatingMissingWords()
        XCTAssertEqual(timing.words.map(\.text), ["A", "bee", "Two"])
        XCTAssertEqual(timing.words[1].end - timing.words[1].start,
                       (timing.words[0].end - timing.words[0].start) * 3, accuracy: 0.00001)
        XCTAssertEqual(try XCTUnwrap(timing.words.last).end, 11, accuracy: 0.00001)
        XCTAssertEqual(timing.words[0].start, 0)
        XCTAssertEqual(timing.estimatingMissingWords(), timing)
        XCTAssertTrue(TimedSegment(index: 0, text: "  ", start: 0, duration: 3, words: [])
            .estimatingMissingWords().words.isEmpty)
        XCTAssertTrue(TimedSegment(index: 0, text: "hello", start: 0, duration: 0, words: [])
            .estimatingMissingWords().words.isEmpty)
    }

    func testRoundTripMissingSidecarAndOffsets() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let audio = directory.appendingPathComponent("chapter.wav")
        XCTAssertNil(try NarrationTimings.load(beside: audio))
        let timing = NarrationTimings(segments: [TimedSegment(index: 0, text: "hello", start: 1,
            duration: 2, words: [TimedWord(text: "hello", start: 0, end: 2)])])
        try timing.save(beside: audio)
        XCTAssertEqual(try NarrationTimings.load(beside: audio), timing)
        let offset = timing.offset(by: 10, startingAt: 5)
        XCTAssertEqual(offset.segments[0].index, 5)
        XCTAssertEqual(offset.segments[0].start, 11)
        XCTAssertEqual(offset.segments[0].words, timing.segments[0].words)
    }
}
