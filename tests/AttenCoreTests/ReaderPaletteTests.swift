import Foundation
import XCTest
@testable import Atten
@testable import AttenCore

/// The page, in each of the two appearances it is printed in.
final class ReaderPaletteTests: XCTestCase {
    /// Warm ink on a cool near-black ground is the reading comfort the old
    /// Quiet theme was kept for, and the one part of it the new palette keeps
    /// verbatim. Warmth belongs in the ink; warming the ground as well is what
    /// made every old theme look alike.
    func testTheDarkPageUsesTheSameGroundAsTheApp() {
        let page = ReaderPagePalette.of(dark: true)
        XCTAssertEqual(page.background, AttenPalette.atten.bg.dark)
        let ink = channels(page.ink)
        XCTAssertEqual(ink.red, ink.green)
        XCTAssertEqual(ink.green, ink.blue)
    }

    /// A page with a warm ground and cold ink reads as a screen showing a
    /// picture of paper rather than as paper.
    func testNoPageSetsWarmPaperUnderColdInk() {
        for dark in [false, true] {
            let page = ReaderPagePalette.of(dark: dark)
            let ground = channels(page.background)
            let ink = channels(page.ink)
            guard ground.red > ground.blue else { continue }
            XCTAssertGreaterThanOrEqual(
                ink.red, ink.blue,
                "\(dark ? "dark" : "light") puts cold ink on warm ground"
            )
        }
    }

    /// Body text clears AAA on its own page; the folio and the chapter line
    /// clear AA; and a search match never hides the word it found.
    func testEveryPageIsReadable() {
        for dark in [false, true] {
            let page = ReaderPagePalette.of(dark: dark)
            let where_ = dark ? "dark" : "light"
            XCTAssertGreaterThanOrEqual(contrast(page.ink, page.background), 7.0, "\(where_): body text is under AAA")
            XCTAssertGreaterThanOrEqual(contrast(page.inkMuted, page.background), 4.5, "\(where_): the folio is under AA")
            XCTAssertGreaterThanOrEqual(contrast(page.accent, page.background), 4.5, "\(where_): the chapter line is under AA")
            XCTAssertGreaterThanOrEqual(contrast(page.ink, page.highlight), 4.5, "\(where_): a search match hides its word")
        }
    }

    /// A dark page has to be the darker of the pair, or the two appearances
    /// are the wrong way round.
    func testADarkPageIsTheDarkerOne() {
        XCTAssertGreaterThan(
            luminance(ReaderPagePalette.of(dark: false).background),
            luminance(ReaderPagePalette.of(dark: true).background),
            "the dark page is lighter than the light one"
        )
    }

    // MARK: - Dimmed ink

    /// Full brightness is the page itself, untouched.
    func testFullBrightnessChangesNothing() {
        for dark in [false, true] {
            let page = ReaderPagePalette.of(dark: dark)
            XCTAssertEqual(page.dimmingInk(to: 1.0), page)
        }
    }

    /// The point of the control: less contrast between the words and the page.
    func testDimmingQuietensTheInkAndLeavesThePageAlone() {
        for dark in [false, true] {
            let page = ReaderPagePalette.of(dark: dark)
            let dim = page.dimmingInk(to: ReaderPagePalette.inkBrightnessRange.lowerBound)
            let where_ = dark ? "dark" : "light"
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

    /// The dimmest setting goes under AA on purpose — that is what a reader
    /// asking for dimmer text at night is asking for. What it must not do is
    /// let the words vanish into the page, so it is held above 2:1 at the
    /// bottom of the range: soft, not gone.
    func testTheDimmestPageStillHasWordsOnIt() {
        for dark in [false, true] {
            let dim = ReaderPagePalette.of(dark: dark)
                .dimmingInk(to: ReaderPagePalette.inkBrightnessRange.lowerBound)
            XCTAssertGreaterThanOrEqual(
                contrast(dim.ink, dim.background), 2.0,
                "\(dark ? "dark" : "light"): the dimmest body text is lost in the page"
            )
        }
    }

    /// The range has to be worth having: the dimmest page is a long way from
    /// the brightest, or the slider is a control that does nothing.
    func testTheRangeIsWorthHaving() {
        for dark in [false, true] {
            let page = ReaderPagePalette.of(dark: dark)
            let dim = page.dimmingInk(to: ReaderPagePalette.inkBrightnessRange.lowerBound)
            XCTAssertLessThan(
                contrast(dim.ink, dim.background),
                contrast(page.ink, page.background) / 1.5,
                "\(dark ? "dark" : "light"): the dimmest setting is barely dimmer"
            )
        }
    }

    /// Asking for more than the range allows is held at its ends rather than
    /// taken literally — a level arriving from stored settings is not trusted.
    func testBrightnessIsHeldInsideItsRange() {
        let page = ReaderPagePalette.of(dark: true)
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
