import AttenCore
import Foundation
import XCTest

/// What a book's page prints beside each section (#102): how long that
/// section runs, never where it starts — a narrated five-second section
/// once read "0:00:00".
final class SectionDurationTests: XCTestCase {
    func testASectionRunsFromItsStartToItsEnd() {
        var first = BookChapter(title: "The creek is bright", text: "The creek is bright this morning.")
        first.startTime = 0
        first.endTime = 5.2
        var third = BookChapter(title: "Landfall", text: "Land.")
        third.startTime = 228
        third.endTime = 323

        XCTAssertEqual(first.narratedDuration ?? 0, 5.2, accuracy: 0.001)
        XCTAssertEqual(third.narratedDuration ?? 0, 95, accuracy: 0.001)
        XCTAssertEqual(ListenEstimator.durationLabel(first.narratedDuration!), "5 s")
        XCTAssertEqual(ListenEstimator.durationLabel(third.narratedDuration!), "2 min")
    }

    func testASectionNotPlacedInARecordingHasNoDuration() {
        var chapter = BookChapter(title: "Letter 1", text: "Dear all.")
        XCTAssertNil(chapter.narratedDuration)
        chapter.startTime = 12
        XCTAssertNil(chapter.narratedDuration, "a start alone is not a length")
        chapter.endTime = 12
        XCTAssertNil(chapter.narratedDuration, "an empty span is not a length")
    }
}
