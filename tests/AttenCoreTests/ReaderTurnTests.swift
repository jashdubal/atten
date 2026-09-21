import Foundation
import SwiftUI
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

/// Where a leaf lands.
///
/// A leaf is drawn in the slot it lifts from and rotated a half-turn, so where
/// it comes to rest is decided entirely by the point it pivots on. Pivoting on
/// its own inner edge landed it a whole gutter away from the facing page, and
/// the page jumped sideways when the leaf was swapped for the real one at the
/// end of the turn.
/// Main-actor bound because a SwiftUI view is, and building one to ask where
/// it would land is still building one.
@MainActor
final class TurningLeafGeometryTests: XCTestCase {
    private let width: CGFloat = 420
    private let gutter: CGFloat = 40

    /// Reflects the leaf about its pivot, in the coordinates of the slot it is
    /// drawn in: the leaf spans 0...width, and the facing page is a gutter
    /// away on the other side.
    private func landed(_ turn: ReaderTurn) -> ClosedRange<CGFloat> {
        let leaf = TurningLeaf(progress: 1, turn: turn, gutter: gutter, width: width) {
            Color.clear
        } back: {
            Color.clear
        }
        let pivot = leaf.anchor.x * width
        let ends = [0, width].map { 2 * pivot - $0 }
        return ends.min()!...ends.max()!
    }

    func testAForwardLeafLandsExactlyOnTheFacingPage() {
        // The page to the left of this one ends a gutter before it begins.
        XCTAssertEqual(landed(.forward).upperBound, -gutter, accuracy: 0.001)
        XCTAssertEqual(landed(.forward).lowerBound, -gutter - width, accuracy: 0.001)
    }

    func testABackwardLeafLandsExactlyOnTheFacingPage() {
        // The page to the right of this one begins a gutter after it ends.
        XCTAssertEqual(landed(.backward).lowerBound, width + gutter, accuracy: 0.001)
        XCTAssertEqual(landed(.backward).upperBound, width * 2 + gutter, accuracy: 0.001)
    }

    /// A leaf always lands a whole page away, never overlapping the page it
    /// lifted from and never leaving a gap beside it.
    func testALandedLeafIsStillAPageWide() {
        for turn in [ReaderTurn.forward, .backward] {
            let landed = landed(turn)
            XCTAssertEqual(landed.upperBound - landed.lowerBound, width, accuracy: 0.001)
        }
    }

    /// Without a width to measure the spine against there is nothing sensible
    /// to pivot on, and the leaf falls back to its own edge rather than
    /// dividing by zero.
    func testALeafWithNoWidthPivotsOnItsEdge() {
        let leaf = TurningLeaf(progress: 0.5, turn: .forward, gutter: gutter, width: 0) {
            Color.clear
        } back: {
            Color.clear
        }
        XCTAssertEqual(leaf.anchor, .leading)
    }
}
