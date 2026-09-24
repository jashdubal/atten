import AttenCore
import Foundation
import XCTest

/// The pure bookkeeping behind progressive playback (P5): a virtual,
/// whole-book timeline built the same way `BookAudioAssembler` builds the
/// real one, so a position found here still makes sense once narration
/// finishes and playback hands off to the assembled file.
final class ProgressiveTimelineTests: XCTestCase {
    private func segment(_ index: Int, text: String, start: Double, duration: Double) -> TimedSegment {
        TimedSegment(index: index, text: text, start: start, duration: duration, words: [])
    }

    func testSegmentsWithinAChapterStayAtTheirOwnOffsets() {
        var timeline = ProgressiveTimeline()
        let urlA = URL(fileURLWithPath: "/a.wav")
        let urlB = URL(fileURLWithPath: "/b.wav")
        timeline.append(chapterIndex: 0, url: urlA, timing: segment(0, text: "First sentence.", start: 0, duration: 2))
        timeline.append(chapterIndex: 0, url: urlB, timing: segment(1, text: "Second one.", start: 2, duration: 3))

        XCTAssertEqual(timeline.placed[0].start, 0)
        XCTAssertEqual(timeline.placed[1].start, 2)
        XCTAssertEqual(timeline.duration, 5)
    }

    func testANewChapterStartsWhereThePreviousOneEnds() {
        var timeline = ProgressiveTimeline()
        let url = URL(fileURLWithPath: "/seg.wav")
        timeline.append(chapterIndex: 0, url: url, timing: segment(0, text: "One.", start: 0, duration: 2))
        timeline.append(chapterIndex: 0, url: url, timing: segment(1, text: "Two.", start: 2, duration: 3))
        // Chapter 1's own segment timing restarts at zero, the way each
        // chapter's own stream reports it.
        let placed = timeline.append(chapterIndex: 1, url: url, timing: segment(0, text: "Next chapter.", start: 0, duration: 4))

        XCTAssertEqual(placed.start, 5, "chapter 1 should start exactly where chapter 0's audio ends")
        XCTAssertEqual(timeline.duration, 9)
    }

    func testALaterSegmentInAChapterExtendsItEvenIfShorterOnesArriveOutOfBillingOrder() {
        // `duration` tracks the furthest point any segment of the current
        // chapter reaches, not merely the last one appended.
        var timeline = ProgressiveTimeline()
        let url = URL(fileURLWithPath: "/seg.wav")
        timeline.append(chapterIndex: 0, url: url, timing: segment(0, text: "One.", start: 0, duration: 5))
        timeline.append(chapterIndex: 0, url: url, timing: segment(1, text: "Two.", start: 5, duration: 1))

        XCTAssertEqual(timeline.duration, 6)
    }

    func testWordCountsAccumulateWithinAChapterAndResetAtTheNext() {
        var timeline = ProgressiveTimeline()
        let url = URL(fileURLWithPath: "/seg.wav")
        let first = timeline.append(chapterIndex: 0, url: url, timing: segment(0, text: "Three word sentence.", start: 0, duration: 1))
        let second = timeline.append(chapterIndex: 0, url: url, timing: segment(1, text: "Two words.", start: 1, duration: 1))
        let third = timeline.append(chapterIndex: 1, url: url, timing: segment(0, text: "New chapter now.", start: 0, duration: 1))

        XCTAssertEqual(first.wordsBefore, 0)
        XCTAssertEqual(first.wordCount, 3)
        XCTAssertEqual(second.wordsBefore, 3)
        XCTAssertEqual(second.wordCount, 2)
        XCTAssertEqual(third.wordsBefore, 0, "a new chapter starts its own word count over")
    }

    func testIndexAtFindsTheSegmentSoundingAtAGivenTime() {
        var timeline = ProgressiveTimeline()
        let url = URL(fileURLWithPath: "/seg.wav")
        timeline.append(chapterIndex: 0, url: url, timing: segment(0, text: "One.", start: 0, duration: 2))
        timeline.append(chapterIndex: 0, url: url, timing: segment(1, text: "Two.", start: 2, duration: 3))

        XCTAssertEqual(timeline.index(at: 0), 0)
        XCTAssertEqual(timeline.index(at: 1.9), 0)
        XCTAssertEqual(timeline.index(at: 2), 1)
        XCTAssertEqual(timeline.index(at: 4.9), 1)
    }

    func testIndexAtIsNilBeforeAnythingIsPlaced() {
        let timeline = ProgressiveTimeline()
        XCTAssertNil(timeline.index(at: 0))
    }

    func testNarrationTimingsLocatesTheSameSegmentAsIndexAt() {
        var timeline = ProgressiveTimeline()
        let url = URL(fileURLWithPath: "/seg.wav")
        timeline.append(chapterIndex: 0, url: url, timing: segment(0, text: "One.", start: 0, duration: 2))
        timeline.append(chapterIndex: 0, url: url, timing: segment(1, text: "Two.", start: 2, duration: 3))

        let located = timeline.narrationTimings.locate(time: 2.5)
        XCTAssertEqual(located.segment, timeline.index(at: 2.5))
    }
}
