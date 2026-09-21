import Foundation
import Observation
import XCTest
@testable import Atten
@testable import AttenCore

final class ThemeTests: XCTestCase {
    func testThemeSurvivesASettingsRoundTrip() throws {
        let settings = AppSettings(theme: .sepia, outputDirectory: "/tmp/atten")

        let decoded = try JSONDecoder().decode(
            AppSettings.self,
            from: try JSONEncoder().encode(settings)
        )

        XCTAssertEqual(decoded.theme, .sepia)
        XCTAssertEqual(decoded, settings)
    }

    /// A theme added by a later Atten must not cost this one the rest of its
    /// preferences, the way an unknown appearance or format already does not.
    func testUnknownThemeFallsBackWithoutLosingOtherPreferences() throws {
        let json = """
        {
            "theme": "holographic",
            "appearance": "dark",
            "outputDirectory": "/tmp/atten",
            "defaultFormat": "wav",
            "defaultSpeed": 1.25,
            "selectedVoiceID": "bf_emma",
            "favoriteVoiceIDs": ["bf_emma"],
            "useMPS": false,
            "pendingDownloadModelIDs": [],
            "checksForUpdates": false
        }
        """

        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))

        XCTAssertEqual(settings.theme, .terminal)
        XCTAssertEqual(settings.appearance, .dark)
        XCTAssertEqual(settings.defaultFormat, .wav)
        XCTAssertEqual(settings.selectedVoiceID, "bf_emma")
        XCTAssertFalse(settings.checksForUpdates)
    }

    func testSettingsWrittenBeforeThemesExistedOpenInTheOriginalTheme() throws {
        let json = """
        { "outputDirectory": "/tmp/atten" }
        """

        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))

        XCTAssertEqual(settings.theme, .terminal)
    }

    func testStoreSwapsPaletteWhenTheThemeChanges() {
        let store = ThemeStore(theme: .terminal)
        XCTAssertEqual(store.palette, AttenTheme.terminal.palette)

        store.theme = .matrix

        XCTAssertEqual(store.palette, AttenTheme.matrix.palette)
        XCTAssertNotEqual(store.palette, AttenTheme.terminal.palette)
    }

    /// Appearance and theme are meant to combine, not override each other, so
    /// every theme has to be a real pair rather than one palette reused in both
    /// appearances — and the dark side has to actually be the darker one.
    func testEveryThemeIsADistinctLightAndDarkPair() {
        let surfaces: [KeyPath<AttenPalette, AttenThemeColor>] = [
            \.appBackground, \.sidebar, \.surface, \.surfaceElevated,
        ]

        for theme in AttenTheme.allCases {
            let palette = theme.palette
            for surface in surfaces {
                let color = palette[keyPath: surface]
                XCTAssertNotEqual(
                    color.light,
                    color.dark,
                    "\(theme.rawValue) uses one colour for both appearances"
                )
                XCTAssertGreaterThan(
                    relativeLuminance(color.light),
                    relativeLuminance(color.dark),
                    "\(theme.rawValue) has a dark variant that is lighter than its light one"
                )
            }
        }
    }

    /// Views never mention `ThemeStore`; they read `AttenColor`. SwiftUI only
    /// repaints them on a theme change if reading through that static accessor
    /// registers as an observed access, so assert exactly that.
    func testReadingASemanticColourObservesTheTheme() {
        let original = ThemeStore.shared.theme
        defer { ThemeStore.shared.theme = original }
        ThemeStore.shared.theme = .terminal

        let notified = expectation(description: "theme change reaches AttenColor readers")
        withObservationTracking {
            _ = AttenColor.accent
        } onChange: {
            notified.fulfill()
        }

        ThemeStore.shared.theme = .vaporwave

        wait(for: [notified], timeout: 1)
    }

    func testEveryThemeHasItsOwnPalette() {
        let palettes = AttenTheme.allCases.map(\.palette)

        for (index, palette) in palettes.enumerated() {
            for other in palettes[palettes.index(after: index)...] {
                XCTAssertNotEqual(palette, other, "Two themes resolve to the same palette")
            }
        }
    }

    /// Every theme has to stay readable in both appearances. Text is held to
    /// WCAG AAA (7:1) and secondary text to AA (4.5:1); accent and status
    /// colours, which carry chrome rather than prose, are held to the 3:1 bar
    /// WCAG sets for interface components.
    func testEveryThemeIsReadableInBothAppearances() {
        let surfaces: [(String, KeyPath<AttenPalette, AttenThemeColor>)] = [
            ("appBackground", \.appBackground),
            ("sidebar", \.sidebar),
            ("surface", \.surface),
            ("surfaceElevated", \.surfaceElevated),
        ]

        var requirements: [(String, KeyPath<AttenPalette, AttenThemeColor>, KeyPath<AttenPalette, AttenThemeColor>, Double)] = [
            ("onAccent on accent", \.onAccent, \.accent, 4.5),
            ("readerText on surface", \.readerText, \.surface, 7.0),
            ("readerText on readerHighlight", \.readerText, \.readerHighlight, 4.5),
            ("separator on appBackground", \.separator, \.appBackground, 1.3),
        ]
        for (name, surface) in surfaces {
            requirements.append(("textPrimary on \(name)", \.textPrimary, surface, 7.0))
            requirements.append(("textSecondary on \(name)", \.textSecondary, surface, 4.5))
            for (label, chrome) in chromeColors {
                requirements.append(("\(label) on \(name)", chrome, surface, 3.0))
            }
        }

        for theme in AttenTheme.allCases {
            let palette = theme.palette
            for (description, foreground, background, minimum) in requirements {
                for appearance in Appearance.allCases {
                    let ratio = contrastRatio(
                        appearance.value(palette[keyPath: foreground]),
                        appearance.value(palette[keyPath: background])
                    )
                    XCTAssertGreaterThanOrEqual(
                        ratio,
                        minimum,
                        """
                        \(theme.rawValue) \(appearance.rawValue): \(description) \
                        is \(String(format: "%.2f", ratio)):1, under \(minimum):1
                        """
                    )
                }
            }
        }
    }

    private let chromeColors: [(String, KeyPath<AttenPalette, AttenThemeColor>)] = [
        ("accent", \.accent),
        ("accentHover", \.accentHover),
        ("accentSecondary", \.accentSecondary),
        ("success", \.success),
        ("warning", \.warning),
        ("destructive", \.destructive),
    ]

    private enum Appearance: String, CaseIterable {
        case light
        case dark

        func value(_ color: AttenThemeColor) -> UInt {
            switch self {
            case .light: color.light
            case .dark: color.dark
            }
        }
    }

    /// WCAG 2.1 relative luminance and contrast ratio.
    private func contrastRatio(_ first: UInt, _ second: UInt) -> Double {
        let (high, low) = {
            let a = relativeLuminance(first)
            let b = relativeLuminance(second)
            return (max(a, b), min(a, b))
        }()
        return (high + 0.05) / (low + 0.05)
    }

    private func relativeLuminance(_ hex: UInt) -> Double {
        func channel(_ raw: UInt) -> Double {
            let value = Double(raw) / 255
            return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel((hex >> 16) & 0xff)
            + 0.7152 * channel((hex >> 8) & 0xff)
            + 0.0722 * channel(hex & 0xff)
    }
}

/// A page built from a theme, for tests that need one.
extension ReaderPagePalette {
    static func of(_ theme: AttenTheme, dark: Bool = false) -> ReaderPagePalette {
        let palette = theme.palette
        func value(_ color: AttenThemeColor) -> UInt { dark ? color.dark : color.light }
        return ReaderPagePalette(
            background: value(palette.readerBackground),
            ink: value(palette.readerInk),
            inkMuted: value(palette.readerInkMuted),
            accent: value(palette.readerAccent),
            highlight: value(palette.readerHighlight),
            isDark: dark
        )
    }
}
