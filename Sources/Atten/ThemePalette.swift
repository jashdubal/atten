import AppKit
import AttenCore
import Observation
import SwiftUI

/// One semantic colour, given as the light-mode and dark-mode hex pair it
/// resolves to. Holding the raw values keeps the palettes readable as a table
/// and lets the accessibility tests measure contrast without a running app.
struct AttenThemeColor: Sendable, Equatable {
    let light: UInt
    let dark: UInt
    /// Built once, when the palette is first touched, so reading a colour
    /// during a view update is a field access rather than an allocation.
    let color: Color

    init(_ light: UInt, _ dark: UInt) {
        self.light = light
        self.dark = dark
        self.color = Color(light: light, dark: dark)
    }

    /// For the few places that hand a colour to AppKit directly.
    var nsColor: NSColor { NSColor(light: light, dark: dark) }
}

/// Every colour the interface draws with. Views never name a hue; they name one
/// of these roles through `AttenColor`, which is what lets a new theme — or a
/// new screen, like the reader — pick up the right colours for free.
struct AttenPalette: Sendable, Equatable {
    let appBackground: AttenThemeColor
    let sidebar: AttenThemeColor
    let surface: AttenThemeColor
    let surfaceElevated: AttenThemeColor
    let surfaceMuted: AttenThemeColor
    let separator: AttenThemeColor

    let textPrimary: AttenThemeColor
    let textSecondary: AttenThemeColor
    let accent: AttenThemeColor
    let accentHover: AttenThemeColor
    let accentSecondary: AttenThemeColor
    let success: AttenThemeColor
    let warning: AttenThemeColor
    let destructive: AttenThemeColor
    let onAccent: AttenThemeColor

    /// The page a book is read on. Kept apart from `surface` so a theme can
    /// give long-form reading a calmer background than the surrounding chrome.
    let readerSurface: AttenThemeColor
    /// Body text on `readerSurface`.
    let readerText: AttenThemeColor
    /// Fill behind a search match or the sentence being spoken.
    let readerHighlight: AttenThemeColor
    /// Drawn at partial opacity over whatever a focused view is dimming.
    let scrim: AttenThemeColor
}

extension AttenTheme {
    var palette: AttenPalette {
        switch self {
        case .terminal: Self.terminalPalette
        case .paper: Self.paperPalette
        case .quiet: Self.quietPalette
        case .sepia: Self.sepiaPalette
        case .slate: Self.slatePalette
        case .vaporwave: Self.vaporwavePalette
        case .matrix: Self.matrixPalette
        }
    }

    // Cool terminal palette: crisp cyan and violet over graphite/navy surfaces.
    private static let terminalPalette = AttenPalette(
        appBackground: AttenThemeColor(0xF3F7FC, 0x080C14),
        sidebar: AttenThemeColor(0xE8EFF8, 0x0C121E),
        surface: AttenThemeColor(0xFFFFFF, 0x101826),
        surfaceElevated: AttenThemeColor(0xF8FBFF, 0x141E2E),
        surfaceMuted: AttenThemeColor(0xDDE8F5, 0x1A2940),
        separator: AttenThemeColor(0xB7C6D9, 0x273852),
        textPrimary: AttenThemeColor(0x101827, 0xE7EEF8),
        textSecondary: AttenThemeColor(0x51647B, 0x8FA2BA),
        accent: AttenThemeColor(0x007EA7, 0x5DDBFF),
        accentHover: AttenThemeColor(0x005F7A, 0x91E8FF),
        accentSecondary: AttenThemeColor(0x6848D8, 0xA78BFA),
        success: AttenThemeColor(0x177A50, 0x4ADE80),
        warning: AttenThemeColor(0xA23E65, 0xF472B6),
        destructive: AttenThemeColor(0xB42346, 0xFB7185),
        // Pure white rather than the near-white it inherited, which left
        // primary button labels at 4.47:1, just under AA.
        onAccent: AttenThemeColor(0xFFFFFF, 0x061018),
        readerSurface: AttenThemeColor(0xFFFFFF, 0x0D141F),
        readerText: AttenThemeColor(0x141B26, 0xDCE6F2),
        readerHighlight: AttenThemeColor(0xC8E9F7, 0x1D4C63),
        scrim: AttenThemeColor(0x0F172A, 0x000000)
    )

    // Muted white over warm neutral greys, with slate-blue ink for accents.
    private static let paperPalette = AttenPalette(
        appBackground: AttenThemeColor(0xF7F6F3, 0x171614),
        sidebar: AttenThemeColor(0xEFEDE8, 0x121110),
        surface: AttenThemeColor(0xFFFFFF, 0x1F1E1B),
        surfaceElevated: AttenThemeColor(0xFBFAF7, 0x262521),
        surfaceMuted: AttenThemeColor(0xE7E4DD, 0x2E2C27),
        separator: AttenThemeColor(0xCFCAC0, 0x3D3A34),
        textPrimary: AttenThemeColor(0x1F1E1B, 0xEDEAE3),
        textSecondary: AttenThemeColor(0x5C584F, 0xAEA89C),
        accent: AttenThemeColor(0x4A5A6B, 0xA8B8C8),
        accentHover: AttenThemeColor(0x33404E, 0xC4D2E0),
        accentSecondary: AttenThemeColor(0x6E5F4B, 0xC9B394),
        success: AttenThemeColor(0x2F6B4F, 0x74C79B),
        warning: AttenThemeColor(0x8A6420, 0xDFB877),
        destructive: AttenThemeColor(0x9E3232, 0xE58B8B),
        onAccent: AttenThemeColor(0xFFFFFF, 0x15140F),
        readerSurface: AttenThemeColor(0xFFFFFF, 0x1C1B18),
        readerText: AttenThemeColor(0x23211D, 0xE8E4DC),
        readerHighlight: AttenThemeColor(0xF0E2B8, 0x4A4227),
        scrim: AttenThemeColor(0x1F1E1B, 0x000000)
    )

    // Neutral greyscale: the quietest the app gets, with no hue at all.
    private static let quietPalette = AttenPalette(
        appBackground: AttenThemeColor(0xF4F4F5, 0x141416),
        sidebar: AttenThemeColor(0xEBEBEC, 0x0F0F11),
        surface: AttenThemeColor(0xFFFFFF, 0x1C1C1F),
        surfaceElevated: AttenThemeColor(0xFAFAFA, 0x232326),
        surfaceMuted: AttenThemeColor(0xE4E4E6, 0x2A2A2E),
        separator: AttenThemeColor(0xC8C8CB, 0x3A3A3F),
        textPrimary: AttenThemeColor(0x18181B, 0xEDEDEF),
        textSecondary: AttenThemeColor(0x56565C, 0xA8A8AF),
        accent: AttenThemeColor(0x3F3F46, 0xD4D4D8),
        accentHover: AttenThemeColor(0x27272A, 0xF2F2F4),
        accentSecondary: AttenThemeColor(0x5F5F66, 0x9A9AA2),
        success: AttenThemeColor(0x2F6B4F, 0x6FCB99),
        warning: AttenThemeColor(0x7A5C12, 0xD9B36A),
        destructive: AttenThemeColor(0x9B2C2C, 0xE58B8B),
        onAccent: AttenThemeColor(0xFFFFFF, 0x16161A),
        readerSurface: AttenThemeColor(0xFFFFFF, 0x1A1A1C),
        readerText: AttenThemeColor(0x18181B, 0xEBEBED),
        readerHighlight: AttenThemeColor(0xE2E2E5, 0x3A3A40),
        scrim: AttenThemeColor(0x18181B, 0x000000)
    )

    // Warm parchment by day, lamp-lit paper by night.
    private static let sepiaPalette = AttenPalette(
        appBackground: AttenThemeColor(0xF3E8D2, 0x1B1510),
        sidebar: AttenThemeColor(0xEBDDC2, 0x15100C),
        surface: AttenThemeColor(0xFBF3E3, 0x241C15),
        surfaceElevated: AttenThemeColor(0xFFF9EC, 0x2C231A),
        surfaceMuted: AttenThemeColor(0xE2D2B4, 0x362B20),
        separator: AttenThemeColor(0xC6B393, 0x493B2C),
        textPrimary: AttenThemeColor(0x32261A, 0xF0E2CB),
        textSecondary: AttenThemeColor(0x6B5942, 0xB8A489),
        accent: AttenThemeColor(0x8A4E14, 0xE0A05A),
        accentHover: AttenThemeColor(0x7A4514, 0xF0BC7E),
        accentSecondary: AttenThemeColor(0x5C5B22, 0xC7B36A),
        success: AttenThemeColor(0x4A6B2A, 0x8DC97A),
        warning: AttenThemeColor(0x76490A, 0xE3B268),
        destructive: AttenThemeColor(0x9E3320, 0xEB9078),
        onAccent: AttenThemeColor(0xFFF7E8, 0x1B1208),
        readerSurface: AttenThemeColor(0xFBF3E3, 0x221A13),
        readerText: AttenThemeColor(0x2B2015, 0xEDDFC7),
        readerHighlight: AttenThemeColor(0xEBD79B, 0x4E3C1F),
        scrim: AttenThemeColor(0x32261A, 0x000000)
    )

    // Restrained steel blue: conservative enough for a shared screen.
    private static let slatePalette = AttenPalette(
        appBackground: AttenThemeColor(0xF2F5F8, 0x121822),
        sidebar: AttenThemeColor(0xE6EBF1, 0x0D121A),
        surface: AttenThemeColor(0xFFFFFF, 0x1A2230),
        surfaceElevated: AttenThemeColor(0xF9FBFD, 0x212B3B),
        surfaceMuted: AttenThemeColor(0xDCE3EC, 0x293446),
        separator: AttenThemeColor(0xBBC6D3, 0x3A4759),
        textPrimary: AttenThemeColor(0x16202B, 0xE6ECF3),
        textSecondary: AttenThemeColor(0x4E5C6C, 0xA3B1C2),
        accent: AttenThemeColor(0x1F5A8C, 0x7FB3DC),
        accentHover: AttenThemeColor(0x16456C, 0xA5CCEC),
        accentSecondary: AttenThemeColor(0x6B5E8A, 0xA8A2D8),
        success: AttenThemeColor(0x1E6B4A, 0x6FC79B),
        warning: AttenThemeColor(0x8A5A12, 0xDDB36B),
        destructive: AttenThemeColor(0xA32B36, 0xEE8C96),
        onAccent: AttenThemeColor(0xFFFFFF, 0x0B1420),
        readerSurface: AttenThemeColor(0xFFFFFF, 0x18202C),
        readerText: AttenThemeColor(0x16202B, 0xE4EAF1),
        readerHighlight: AttenThemeColor(0xCFE0EF, 0x2C4055),
        scrim: AttenThemeColor(0x16202B, 0x000000)
    )

    // Magenta and cyan over deep purple.
    private static let vaporwavePalette = AttenPalette(
        appBackground: AttenThemeColor(0xF6ECF7, 0x140A24),
        sidebar: AttenThemeColor(0xEFE0F3, 0x0F0719),
        surface: AttenThemeColor(0xFFF6FD, 0x1E1033),
        surfaceElevated: AttenThemeColor(0xFFFBFF, 0x27163F),
        surfaceMuted: AttenThemeColor(0xEAD7F0, 0x331D4E),
        separator: AttenThemeColor(0xCFAEDA, 0x4A2C6B),
        textPrimary: AttenThemeColor(0x2A1233, 0xF3E6FF),
        textSecondary: AttenThemeColor(0x6B4478, 0xBB9BD6),
        accent: AttenThemeColor(0xA01E8E, 0xFF6EC7),
        accentHover: AttenThemeColor(0x7C1270, 0xFF9BD9),
        accentSecondary: AttenThemeColor(0x1A5F83, 0x6EE7F0),
        success: AttenThemeColor(0x186049, 0x5FE3B0),
        warning: AttenThemeColor(0x7E4A00, 0xFFC46B),
        destructive: AttenThemeColor(0xB01D48, 0xFF8095),
        onAccent: AttenThemeColor(0xFFF0FC, 0x1A0726),
        readerSurface: AttenThemeColor(0xFFF8FE, 0x1B0F2E),
        readerText: AttenThemeColor(0x2A1233, 0xF0E4FC),
        readerHighlight: AttenThemeColor(0xF4CDEC, 0x4A2360),
        scrim: AttenThemeColor(0x2A1233, 0x000000)
    )

    // Green phosphor on black, and a daylight version of the same idea.
    private static let matrixPalette = AttenPalette(
        appBackground: AttenThemeColor(0xF1F6F1, 0x030703),
        sidebar: AttenThemeColor(0xE5EEE5, 0x000400),
        surface: AttenThemeColor(0xFFFFFF, 0x08120A),
        surfaceElevated: AttenThemeColor(0xF8FCF8, 0x0C1A0E),
        surfaceMuted: AttenThemeColor(0xD9E8D9, 0x122414),
        separator: AttenThemeColor(0xB2C9B2, 0x1E3A22),
        textPrimary: AttenThemeColor(0x0E1A0E, 0xCBF5CF),
        textSecondary: AttenThemeColor(0x46604A, 0x7FBE8A),
        accent: AttenThemeColor(0x156B2E, 0x3BF56A),
        accentHover: AttenThemeColor(0x0D4E1F, 0x7DFF9E),
        accentSecondary: AttenThemeColor(0x1F6B5E, 0x3BE5C0),
        success: AttenThemeColor(0x156B2E, 0x3BF56A),
        warning: AttenThemeColor(0x8A5A12, 0xE8D56B),
        destructive: AttenThemeColor(0xA32424, 0xFF8A7A),
        onAccent: AttenThemeColor(0xF2FFF4, 0x02160A),
        readerSurface: AttenThemeColor(0xFFFFFF, 0x06100A),
        readerText: AttenThemeColor(0x0E1A0E, 0xC8F2CC),
        readerHighlight: AttenThemeColor(0xC6E8C9, 0x174A22),
        scrim: AttenThemeColor(0x0E1A0E, 0x000000)
    )
}

/// Holds the theme the interface is currently drawn in.
///
/// `AttenColor` reads its palette from here, so every view that already names a
/// semantic colour repaints when the theme changes — no call site has to know a
/// theme exists. It is a singleton because colours are read from deep inside
/// button styles and view modifiers that are given no environment to thread.
///
/// Marked `@unchecked Sendable` rather than isolated to the main actor so those
/// reads stay free of actor hops; `theme` is only ever written from the main
/// actor, in response to a person picking one.
@Observable
final class ThemeStore: @unchecked Sendable {
    static let shared = ThemeStore()

    private(set) var palette: AttenPalette

    var theme: AttenTheme {
        didSet {
            guard theme != oldValue else { return }
            palette = theme.palette
        }
    }

    init(theme: AttenTheme = .default) {
        self.theme = theme
        self.palette = theme.palette
    }
}
