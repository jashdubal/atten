import Foundation
import Observation
import XCTest
@testable import Atten
@testable import AttenCore

/// Atten had seven named themes and now has one palette drawn light or dark.
/// These cover the two things that has to leave behind: settings files written
/// by the seven-theme versions, and a single palette that still has to be
/// readable in both appearances.
final class ThemeTests: XCTestCase {

    // MARK: - Migrating off the seven themes

    /// The migration, in full: a settings file naming any of the old themes
    /// loads, the name is ignored, and nothing else in the file is lost.
    func testLegacyThemeNamesLoadWithoutLosingOtherPreferences() throws {
        for legacy in ["terminal", "paper", "quiet", "sepia", "slate", "vaporwave", "matrix"] {
            let json = """
            {
                "theme": "\(legacy)",
                "appearance": "dark",
                "outputDirectory": "/tmp/atten",
                "defaultFormat": "wav",
                "defaultSpeed": 1.25,
                "selectedVoiceID": "bf_emma",
                "favoriteVoiceIDs": ["bf_emma"],
                "useMPS": false,
                "pendingDownloadModelIDs": [],
                "checksForUpdates": false,
                "playbackRate": 1.5,
                "readerViewMode": "scroll",
                "readerJustifiesText": false,
                "readerTextBrightness": 0.7
            }
            """

            let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))

            XCTAssertEqual(settings.appearance, .dark, "\(legacy): appearance lost")
            XCTAssertEqual(settings.defaultFormat, .wav, "\(legacy): format lost")
            XCTAssertEqual(settings.defaultSpeed, 1.25, "\(legacy): speed lost")
            XCTAssertEqual(settings.selectedVoiceID, "bf_emma", "\(legacy): voice lost")
            XCTAssertEqual(settings.favoriteVoiceIDs, ["bf_emma"], "\(legacy): favourites lost")
            XCTAssertFalse(settings.useMPS, "\(legacy): MPS lost")
            XCTAssertFalse(settings.checksForUpdates, "\(legacy): update preference lost")
            XCTAssertEqual(settings.playbackRate, 1.5, "\(legacy): playback rate lost")
            XCTAssertEqual(settings.readerViewMode, .scroll, "\(legacy): reader mode lost")
            XCTAssertFalse(settings.readerJustifiesText, "\(legacy): justification lost")
            XCTAssertEqual(settings.readerTextBrightness, 0.7, accuracy: 0.0001, "\(legacy): brightness lost")
        }
    }

    /// A theme name from some later Atten is no more fatal than one of the old
    /// ones, for the same reason: nothing reads the key.
    func testUnknownThemeNameIsHarmless() throws {
        let json = """
        { "theme": "holographic", "appearance": "light", "outputDirectory": "/tmp/atten" }
        """

        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))

        XCTAssertEqual(settings.appearance, .light)
        XCTAssertEqual(settings.outputDirectory, "/tmp/atten")
    }

    /// Settings written before themes existed at all still open.
    func testSettingsWrittenBeforeThemesExistedStillLoad() throws {
        let json = #"{ "outputDirectory": "/tmp/atten" }"#

        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))

        XCTAssertEqual(settings.outputDirectory, "/tmp/atten")
        XCTAssertEqual(settings.appearance, .system)
    }

    /// The migration is one-way: once Atten saves, the dead key is gone rather
    /// than being carried forward forever.
    func testSavingDropsTheLegacyThemeKey() throws {
        let json = #"{ "theme": "matrix", "appearance": "dark", "outputDirectory": "/tmp/atten" }"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))

        let rewritten = try JSONEncoder().encode(settings)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: rewritten) as? [String: Any]
        )

        XCTAssertNil(object["theme"], "the dead theme key was written back out")
        XCTAssertEqual(object["appearance"] as? String, "dark")
    }

    func testSettingsSurviveARoundTrip() throws {
        let settings = AppSettings(appearance: .dark, outputDirectory: "/tmp/atten")

        let decoded = try JSONDecoder().decode(
            AppSettings.self,
            from: try JSONEncoder().encode(settings)
        )

        XCTAssertEqual(decoded, settings)
    }

    // MARK: - One palette, two appearances

    /// Appearance is the only axis left, so every role has to be a real pair
    /// rather than one colour reused — and the dark side has to be the darker.
    func testEveryRoleIsADistinctLightAndDarkPair() {
        let surfaces: [(String, KeyPath<AttenPalette, AttenThemeColor>)] = [
            ("appBackground", \.appBackground),
            ("sidebar", \.sidebar),
            ("surface", \.surface),
            ("surfaceElevated", \.surfaceElevated),
        ]

        for (name, surface) in surfaces {
            let color = AttenPalette.atten[keyPath: surface]
            XCTAssertNotEqual(color.light, color.dark, "\(name) uses one colour for both appearances")
            XCTAssertGreaterThan(
                relativeLuminance(color.light),
                relativeLuminance(color.dark),
                "\(name) has a dark variant lighter than its light one"
            )
        }
    }

    /// The whole point of the foundation: a view that names a semantic role
    /// gets the palette, with no store to go through.
    func testSemanticColoursResolveFromTheOnePalette() {
        XCTAssertEqual(AttenColor.palette, .atten)
    }

    /// Progress and focus are roles rather than call sites reaching for the
    /// accent, so the screens built on this contract stay consistent.
    func testProgressAndFocusHaveRolesOfTheirOwn() {
        XCTAssertEqual(AttenColor.progress, AttenPalette.atten.accent.color)
        XCTAssertEqual(AttenColor.progressTrack, AttenPalette.atten.surfaceMuted.color)
        XCTAssertEqual(AttenColor.focus, AttenPalette.atten.accentHover.color)
    }

    /// Text is held to WCAG AAA (7:1) and secondary text to AA (4.5:1); accent
    /// and status colours, which carry chrome rather than prose, are held to
    /// the 3:1 bar WCAG sets for interface components.
    func testThePaletteIsReadableInBothAppearances() {
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

        let palette = AttenPalette.atten
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
                    \(appearance.rawValue): \(description) \
                    is \(String(format: "%.2f", ratio)):1, under \(minimum):1
                    """
                )
            }
        }
    }

    /// Dark is a cool near-black rather than the neutral grey it replaced —
    /// that is the brief, and it is the one thing about the new palette that a
    /// later well-meaning tidy could undo without noticing.
    func testTheDarkAppearanceIsCoolRatherThanNeutral() {
        for surface in [AttenPalette.atten.appBackground, AttenPalette.atten.sidebar] {
            let (red, _, blue) = channels(surface.dark)
            XCTAssertGreaterThan(blue, red, "the dark chrome has lost its cool cast")
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

    private func channels(_ hex: UInt) -> (red: UInt, green: UInt, blue: UInt) {
        ((hex >> 16) & 0xff, (hex >> 8) & 0xff, hex & 0xff)
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

/// The page as it is printed in one appearance, for tests that need one.
extension ReaderPagePalette {
    static func of(dark: Bool = false) -> ReaderPagePalette {
        let palette = AttenPalette.atten
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
