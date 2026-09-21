import Foundation
import XCTest
@testable import Atten
@testable import AttenCore

final class ReaderTurnTests: XCTestCase {
    /// A leaf has two sides, and only a spread has somewhere for both of them
    /// to be. Pivoting a single page sweeps its whole measure of text across
    /// the window and shows the blank back of the sheet on the way, which is
    /// the movement the reader complained was too much.
    func testOnlyASpreadTurnsALeaf() {
        XCTAssertTrue(ReaderViewMode.spread.turnsALeaf)
        XCTAssertFalse(ReaderViewMode.page.turnsALeaf)
        XCTAssertFalse(ReaderViewMode.scroll.turnsALeaf)
    }

    /// Every mode that pivots a leaf has to have two pages to pivot it
    /// between, or the back of the leaf is blank paper.
    func testAnyModeThatTurnsALeafTurnsTwoPagesAtOnce() {
        for mode in ReaderViewMode.allCases where mode.turnsALeaf {
            XCTAssertEqual(mode.pagesPerTurn, 2, "\(mode.rawValue) pivots a leaf over one page")
        }
    }

    // MARK: - Not re-setting a page's text on every frame of a turn

    private let layout = ReaderTypesetter.layout(
        eyebrow: "Chapter 1",
        title: "The Period",
        paragraphs: ["It was the best of times.", "There were a king and a queen."],
        style: ReaderPageStyle(
            fontSize: 17,
            pageSize: CGSize(width: 380, height: 520),
            palette: .of(.paper),
            font: .default,
            isJustified: true
        )
    )

    private func applied(page: Int = 0, highlight: String = "") -> ReaderPage.Coordinator.Applied {
        ReaderPage.Coordinator.Applied(
            text: ObjectIdentifier(layout.text),
            pageIndex: page,
            style: ReaderPageStyle(
                fontSize: 17,
                pageSize: CGSize(width: 380, height: 520),
                palette: .of(.paper),
                font: .default,
                isJustified: true
            ),
            highlight: highlight
        )
    }

    /// A turn animates, so SwiftUI evaluates every page on the spread on every
    /// frame of it. Nothing about a page's text changes while it is being
    /// moved, and rebuilding its text storage sixty times a second is what
    /// made the turn stutter.
    func testAPageThatHasNotChangedIsRecognisedAsUnchanged() {
        XCTAssertEqual(applied(), applied())
    }

    func testAPageIsRebuiltWhenAnythingAboutItChanges() {
        XCTAssertNotEqual(applied(), applied(page: 1))
        XCTAssertNotEqual(applied(), applied(highlight: "king"))

        let elsewhere = ReaderTypesetter.layout(
            eyebrow: "Chapter 2",
            title: "The Mail",
            paragraphs: ["It was the Dover road."],
            style: ReaderPageStyle(
                fontSize: 17,
                pageSize: CGSize(width: 380, height: 520),
                palette: .of(.paper),
                font: .default,
                isJustified: true
            )
        )
        XCTAssertNotEqual(
            applied().text,
            ObjectIdentifier(elsewhere.text),
            "a different chapter must not be mistaken for the one already drawn"
        )
    }

    /// The page theme and the typeface are baked into the text when it is set,
    /// so changing either has to count as a change.
    func testChangingHowThePageLooksRedrawsIt() {
        let dusk = ReaderPageStyle(
            fontSize: 17,
            pageSize: CGSize(width: 380, height: 520),
            palette: .of(.quiet, dark: true),
            font: .default,
            isJustified: true
        )
        XCTAssertNotEqual(applied().style, dusk)

        let charter = ReaderPageStyle(
            fontSize: 17,
            pageSize: CGSize(width: 380, height: 520),
            palette: .of(.paper),
            font: .charter,
            isJustified: true
        )
        XCTAssertNotEqual(applied().style, charter)
    }
}
