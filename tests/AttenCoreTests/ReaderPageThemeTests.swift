import Foundation
import XCTest
@testable import AttenCore

final class ReaderPageThemeTests: XCTestCase {
    /// The setting is what makes the page independent of the app's theme, so
    /// it has to survive being written down.
    func testPageThemeSurvivesASettingsRoundTrip() throws {
        let settings = AppSettings(outputDirectory: "/tmp/atten", readerPageTheme: .dusk)

        let decoded = try JSONDecoder().decode(
            AppSettings.self,
            from: try JSONEncoder().encode(settings)
        )

        XCTAssertEqual(decoded.readerPageTheme, .dusk)
    }

    /// Settings written before the page had a theme of its own open on the
    /// automatic one rather than refusing to decode.
    func testSettingsWrittenBeforePageThemesExistedOpenAutomatic() throws {
        let json = #"{ "outputDirectory": "/tmp/atten" }"#

        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))

        XCTAssertEqual(settings.readerPageTheme, .automatic)
    }

    func testAutomaticFollowsTheAppearanceAndNothingElseDoes() {
        XCTAssertEqual(
            ReaderPageTheme.automatic.palette(inDarkMode: true),
            ReaderPageTheme.dusk.palette(inDarkMode: false)
        )
        XCTAssertEqual(
            ReaderPageTheme.automatic.palette(inDarkMode: false),
            ReaderPageTheme.paper.palette(inDarkMode: true)
        )
        for theme in ReaderPageTheme.allCases where theme != .automatic {
            XCTAssertEqual(
                theme.palette(inDarkMode: true),
                theme.palette(inDarkMode: false),
                "\(theme.rawValue) is a choice, so the appearance must not override it"
            )
        }
    }

    /// The complaint this type was written for: a page that reads as grey and
    /// dull rather than as paper. Warmth is measurable — red above green above
    /// blue — and it has to hold for the ink as well as for the sheet, because
    /// warm paper under cold ink still looks like a screen.
    func testEveryPageIsWarmerThanItIsCold() {
        for theme in ReaderPageTheme.allCases {
            let palette = theme.palette(inDarkMode: theme == .automatic)
            for (name, hex) in [
                ("page", palette.page),
                ("pageFoot", palette.pageFoot),
                ("ink", palette.ink),
                ("inkMuted", palette.inkMuted),
                ("accent", palette.accent),
            ] {
                let red = (hex >> 16) & 0xff
                let green = (hex >> 8) & 0xff
                let blue = hex & 0xff
                XCTAssertGreaterThanOrEqual(
                    red, green,
                    "\(theme.rawValue) \(name) has more green than red, which reads cold"
                )
                XCTAssertGreaterThanOrEqual(
                    green, blue,
                    "\(theme.rawValue) \(name) has more blue than green, which reads cold"
                )
            }
        }
    }

    /// A page is only a page if it stands off what it is lying on, and only a
    /// dark page is lighter than its well — a light one casts onto it.
    func testTheSheetStandsOffTheWell() {
        for theme in ReaderPageTheme.allCases {
            let palette = theme.palette(inDarkMode: theme == .automatic)
            let page = luminance(palette.page)
            let well = luminance(palette.well)
            XCTAssertGreaterThan(page, well, "\(theme.rawValue) page is darker than its well")
            XCTAssertGreaterThan(
                luminance(palette.page), luminance(palette.pageFoot),
                "\(theme.rawValue) is lit from below"
            )
        }
    }

    /// Body text has to clear WCAG AAA on its own page, and the muted ink used
    /// for folios and running heads has to clear AA.
    func testEveryPageIsReadable() {
        for theme in ReaderPageTheme.allCases {
            let palette = theme.palette(inDarkMode: theme == .automatic)
            XCTAssertGreaterThanOrEqual(
                contrast(palette.ink, palette.page), 7.0,
                "\(theme.rawValue): body text is under AAA on its own page"
            )
            XCTAssertGreaterThanOrEqual(
                contrast(palette.inkMuted, palette.pageFoot), 4.5,
                "\(theme.rawValue): folio is under AA at the foot of the page"
            )
            XCTAssertGreaterThanOrEqual(
                contrast(palette.accent, palette.page), 4.5,
                "\(theme.rawValue): the chapter line is under AA"
            )
            XCTAssertGreaterThanOrEqual(
                contrast(palette.ink, palette.highlight), 4.5,
                "\(theme.rawValue): a search match hides the word it found"
            )
        }
    }

    // MARK: - WCAG 2.1

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
