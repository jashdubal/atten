import AppKit
import Foundation
import XCTest
@testable import Atten
@testable import AttenCore

final class ReaderFontTests: XCTestCase {
    func testFontSurvivesASettingsRoundTrip() throws {
        let settings = AppSettings(outputDirectory: "/tmp/atten", readerFont: .charter)

        let decoded = try JSONDecoder().decode(
            AppSettings.self,
            from: try JSONEncoder().encode(settings)
        )

        XCTAssertEqual(decoded.readerFont, .charter)
    }

    func testSettingsWrittenBeforeTypefacesExistedOpenInTheDefault() throws {
        let json = #"{ "outputDirectory": "/tmp/atten" }"#

        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))

        XCTAssertEqual(settings.readerFont, .iowan)
    }

    /// A face offered in the menu that is not installed falls back to the
    /// system face, which is legible but is not what the reader asked for. The
    /// list is deliberately fonts macOS ships, so assert they are all really
    /// there rather than finding out one at a time.
    func testEveryOfferedFaceIsInstalled() {
        let system = NSFont.systemFont(ofSize: 18, weight: .regular).familyName
        for choice in ReaderFont.allCases where choice != .system {
            guard let family = choice.familyName else {
                return XCTFail("\(choice.rawValue) offers no family to ask for")
            }
            let resolved = ReaderTypesetter.face(choice, size: 18, weight: .regular)
            XCTAssertEqual(
                resolved.familyName, family,
                "\(choice.displayName) is not installed; it fell back to \(resolved.familyName ?? "?")"
            )
            XCTAssertNotEqual(resolved.familyName, system)
        }
    }

    func testTheSystemFaceIsTheSystemFace() {
        XCTAssertEqual(
            ReaderTypesetter.face(.system, size: 18, weight: .regular).familyName,
            NSFont.systemFont(ofSize: 18, weight: .regular).familyName
        )
    }

    /// The complaint the typeface picker answers is that the page did not look
    /// like a book. The system serif is a UI face with serifs added, so the
    /// default has to be one of the real book faces instead.
    func testTheDefaultIsABookFaceAndNotTheSystemOne() {
        XCTAssertTrue(ReaderFont.default.isSerif)
        XCTAssertNotEqual(ReaderFont.default, .system)
        XCTAssertNotNil(ReaderFont.default.familyName)
    }

    /// A sans page is set with more air between its lines than a serif one.
    func testASansPageIsLeadedMoreThanASerifOne() {
        func spacing(_ font: ReaderFont) -> Double {
            ReaderPageStyle(
                fontSize: 18,
                pageSize: CGSize(width: 400, height: 600),
                palette: ReaderPageTheme.paper.palette(inDarkMode: false),
                font: font,
                isJustified: true
            ).lineSpacing
        }

        XCTAssertGreaterThan(spacing(.seravek), spacing(.iowan))
    }

    /// The chapter line is the reader's own words, not a hard-coded "CHAPTER
    /// N" — a report has sections, not chapters.
    func testTheChapterLineIsWhateverItIsGiven() {
        let layout = ReaderTypesetter.layout(
            eyebrow: "Section 2",
            title: "Findings",
            paragraphs: ["Revenue grew."],
            style: ReaderPageStyle(
                fontSize: 18,
                pageSize: CGSize(width: 400, height: 600),
                palette: ReaderPageTheme.paper.palette(inDarkMode: false),
                font: .iowan,
                isJustified: false
            )
        )

        XCTAssertTrue(layout.text.string.hasPrefix("SECTION 2\n"))
        XCTAssertFalse(layout.text.string.contains("CHAPTER"))
    }

    /// Everything on the page is set in the chosen face. A heading in one face
    /// over a body in another is the thing that made the old page look
    /// assembled rather than printed.
    func testTheWholePageIsSetInOneFace() {
        let layout = ReaderTypesetter.layout(
            eyebrow: "Chapter 1",
            title: "The Period",
            paragraphs: ["It was the best of times."],
            style: ReaderPageStyle(
                fontSize: 18,
                pageSize: CGSize(width: 400, height: 600),
                palette: ReaderPageTheme.paper.palette(inDarkMode: false),
                font: .charter,
                isJustified: true
            )
        )

        var families: Set<String> = []
        layout.text.enumerateAttribute(
            .font, in: NSRange(location: 0, length: layout.text.length)
        ) { value, _, _ in
            if let font = value as? NSFont, let family = font.familyName { families.insert(family) }
        }

        XCTAssertEqual(families, ["Charter"])
    }
}
