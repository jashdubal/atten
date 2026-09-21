import Foundation
import XCTest
@testable import Atten
@testable import AttenCore

/// The page follows the theme, and the themes have to actually differ.
final class ReaderPaletteTests: XCTestCase {
    /// The complaint: every page looked the same, because warmth had been
    /// applied to all of them at once. A theme's page has to be that theme's.
    func testNoTwoThemesReadTheSame() {
        for dark in [false, true] {
            let pages = AttenTheme.allCases.map { ReaderPagePalette.of($0, dark: dark) }
            for (index, page) in pages.enumerated() {
                for other in pages[pages.index(after: index)...] {
                    XCTAssertNotEqual(page, other, "two themes read identically in \(dark ? "dark" : "light")")
                }
            }
        }
    }

    /// Quiet is the one the reader named: warm text on a neutral black ground,
    /// not the warm-on-warm every page had become. Warmth belongs in the ink.
    func testQuietIsWarmInkOnNeutralBlack() {
        let page = ReaderPagePalette.of(.quiet, dark: true)

        let (red, green, blue) = channels(page.background)
        XCTAssertEqual(red, green, "Quiet's ground is tinted, and it must be neutral")
        XCTAssertEqual(green, blue, "Quiet's ground is tinted, and it must be neutral")
        XCTAssertLessThanOrEqual(luminance(page.background), luminance(0x0A0A0A), "Quiet's ground is grey, not black")

        let ink = channels(page.ink)
        XCTAssertGreaterThan(ink.red, ink.blue, "Quiet's ink is not warm")
        XCTAssertGreaterThanOrEqual(ink.green, ink.blue)
    }

    /// Warmth is a property of the ink. A theme whose ink is warm may have a
    /// neutral or a warm ground, but a theme with warm ground and cold ink
    /// reads as a screen showing a picture of paper.
    func testNoThemeSetsWarmPaperUnderColdInk() {
        for theme in AttenTheme.allCases {
            for dark in [false, true] {
                let page = ReaderPagePalette.of(theme, dark: dark)
                let ground = channels(page.background)
                let ink = channels(page.ink)
                guard ground.red > ground.blue else { continue }
                XCTAssertGreaterThanOrEqual(
                    ink.red, ink.blue,
                    "\(theme.rawValue) \(dark ? "dark" : "light") puts cold ink on warm ground"
                )
            }
        }
    }

    /// Body text clears AAA on its own page; the folio and the chapter line
    /// clear AA; and a search match never hides the word it found.
    func testEveryPageIsReadable() {
        for theme in AttenTheme.allCases {
            for dark in [false, true] {
                let page = ReaderPagePalette.of(theme, dark: dark)
                let where_ = "\(theme.rawValue) \(dark ? "dark" : "light")"
                XCTAssertGreaterThanOrEqual(contrast(page.ink, page.background), 7.0, "\(where_): body text is under AAA")
                XCTAssertGreaterThanOrEqual(contrast(page.inkMuted, page.background), 4.5, "\(where_): the folio is under AA")
                XCTAssertGreaterThanOrEqual(contrast(page.accent, page.background), 4.5, "\(where_): the chapter line is under AA")
                XCTAssertGreaterThanOrEqual(contrast(page.ink, page.highlight), 4.5, "\(where_): a search match hides its word")
            }
        }
    }

    /// A dark page has to be the darker of the pair, or the theme's two
    /// appearances are the wrong way round.
    func testADarkPageIsTheDarkerOne() {
        for theme in AttenTheme.allCases {
            XCTAssertGreaterThan(
                luminance(ReaderPagePalette.of(theme, dark: false).background),
                luminance(ReaderPagePalette.of(theme, dark: true).background),
                "\(theme.rawValue) has a dark page lighter than its light one"
            )
        }
    }

    // MARK: - Dimmed ink

    /// Full brightness is the theme's own page, untouched.
    func testFullBrightnessChangesNothing() {
        for theme in AttenTheme.allCases {
            for dark in [false, true] {
                let page = ReaderPagePalette.of(theme, dark: dark)
                XCTAssertEqual(page.dimmingInk(to: 1.0), page)
            }
        }
    }

    /// The point of the control: less contrast between the words and the page.
    func testDimmingQuietensTheInkAndLeavesThePageAlone() {
        for theme in AttenTheme.allCases {
            for dark in [false, true] {
                let page = ReaderPagePalette.of(theme, dark: dark)
                let dim = page.dimmingInk(to: ReaderPagePalette.inkBrightnessRange.lowerBound)
                let where_ = "\(theme.rawValue) \(dark ? "dark" : "light")"
                XCTAssertLessThan(
                    contrast(dim.ink, dim.background),
                    contrast(page.ink, page.background),
                    "\(where_): dimming did not quieten the ink"
                )
                XCTAssertEqual(dim.background, page.background, "\(where_): dimming moved the page")
                XCTAssertEqual(dim.highlight, page.highlight, "\(where_): dimming moved a search match")
                XCTAssertEqual(dim.accent, page.accent, "\(where_): dimming moved the accent")
            }
        }
    }

    /// A brightness control that can make a book unreadable is a trap. The
    /// dimmest setting still clears AA on every page.
    func testTheDimmestPageIsStillReadable() {
        for theme in AttenTheme.allCases {
            for dark in [false, true] {
                let dim = ReaderPagePalette.of(theme, dark: dark)
                    .dimmingInk(to: ReaderPagePalette.inkBrightnessRange.lowerBound)
                XCTAssertGreaterThanOrEqual(
                    contrast(dim.ink, dim.background), 4.5,
                    "\(theme.rawValue) \(dark ? "dark" : "light"): the dimmest body text is under AA"
                )
            }
        }
    }

    /// Asking for more than the range allows is held at its ends rather than
    /// taken literally — a level arriving from stored settings is not trusted.
    func testBrightnessIsHeldInsideItsRange() {
        let page = ReaderPagePalette.of(.quiet, dark: true)
        let range = ReaderPagePalette.inkBrightnessRange
        XCTAssertEqual(page.dimmingInk(to: 0), page.dimmingInk(to: range.lowerBound))
        XCTAssertEqual(page.dimmingInk(to: 5), page)
    }

    // MARK: -

    private func channels(_ hex: UInt) -> (red: UInt, green: UInt, blue: UInt) {
        ((hex >> 16) & 0xff, (hex >> 8) & 0xff, hex & 0xff)
    }

    private func contrast(_ first: UInt, _ second: UInt) -> Double {
        let a = luminance(first)
        let b = luminance(second)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    private func luminance(_ hex: UInt) -> Double {
        func channel(_ raw: UInt) -> Double {
            let value = Double(raw) / 255
            return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel((hex >> 16) & 0xff)
            + 0.7152 * channel((hex >> 8) & 0xff)
            + 0.0722 * channel(hex & 0xff)
    }
}
