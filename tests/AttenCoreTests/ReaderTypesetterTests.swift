import AppKit
import AttenCore
import XCTest
@testable import Atten

/// The reader used to count words and call every two hundred and fifty of them
/// a page. These are the properties a real page has that a guessed one does not.
@MainActor
final class ReaderTypesetterTests: XCTestCase {
    private let paragraphs = (1...40).map { index in
        "Paragraph \(index). " + String(
            repeating: "The boy walked on through the fields towards the village. ",
            count: 12
        )
    }

    private func style(width: Double, height: Double = 560) -> ReaderPageStyle {
        ReaderPageStyle(
            fontSize: 17,
            pageSize: CGSize(width: width, height: height),
            palette: .of(),
            font: .default,
            isJustified: true
        )
    }

    private func layout(width: Double, height: Double = 560) -> ReaderChapterLayout {
        ReaderTypesetter.layout(
            eyebrow: "Chapter 3",
            title: "The Shepherd",
            paragraphs: paragraphs,
            style: style(width: width, height: height)
        )
    }

    func testEveryCharacterOfTheChapterLandsOnExactlyOnePage() {
        let result = layout(width: 480)

        XCTAssertGreaterThan(result.pages.count, 1)
        var expected = 0
        for page in result.pages {
            XCTAssertEqual(page.location, expected, "Pages must not overlap or skip text")
            expected = NSMaxRange(page)
        }
        XCTAssertEqual(expected, result.text.length, "The last page must reach the end")
    }

    func testANarrowerPageHoldsLessAndSoTakesMorePages() {
        let wide = layout(width: 720)
        let narrow = layout(width: 480)

        XCTAssertGreaterThan(
            narrow.pages.count,
            wide.pages.count,
            "A page half the width cannot hold as much text"
        )
    }

    func testAShorterPageHoldsLessAndSoTakesMorePages() {
        let tall = layout(width: 560, height: 700)
        let short = layout(width: 560, height: 360)

        XCTAssertGreaterThan(short.pages.count, tall.pages.count)
    }

    /// Pages are remade whenever the window or the type changes, so the place
    /// the reader had got to is kept as a paragraph and found again.
    func testAParagraphCanBeFoundOnWhateverPageItNowFallsOn() {
        let wide = layout(width: 720)
        let narrow = layout(width: 420)

        let paragraph = 25
        let widePage = wide.page(containing: wide.character(ofParagraph: paragraph))
        let narrowPage = narrow.page(containing: narrow.character(ofParagraph: paragraph))

        XCTAssertEqual(wide.paragraph(atCharacter: wide.range(ofPage: widePage).location) <= paragraph, true)
        XCTAssertEqual(narrow.paragraph(atCharacter: narrow.range(ofPage: narrowPage).location) <= paragraph, true)
        // The same paragraph is further into a book set in narrower pages.
        XCTAssertGreaterThan(narrowPage, widePage)
    }
}
