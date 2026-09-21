import Foundation

/// The colours one page of reading is printed in.
///
/// Held as plain hex so a page can be set on a background thread and so the
/// values can be checked for contrast without a running app.
public struct ReaderPagePalette: Equatable, Sendable {
    /// The sheet itself, at the top of the page.
    public let page: UInt
    /// The sheet at its foot. Paper under a lamp is not one flat colour, and
    /// the fall from `page` to this is what keeps a large dark page from
    /// reading as a hole cut in the window.
    public let pageFoot: UInt
    /// Behind the sheet, and darker than it, so the page has an edge.
    public let well: UInt
    public let ink: UInt
    /// Running heads, folios, and anything else that is not the text.
    public let inkMuted: UInt
    /// The chapter line and the rule under a heading.
    public let accent: UInt
    public let highlight: UInt
    /// Whether the page is a light one, for deciding how heavy its shadow is
    /// and which way its edge is lit.
    public let isDark: Bool
}

/// What the page looks like, chosen apart from the rest of the app.
///
/// The interface has themes of its own, but a page is not a window: someone
/// who wants the app in Terminal green still wants to read on paper. Apple
/// Books settled this years ago by making the page its own setting, and this
/// is the same decision — the sidebar and the controls follow ``AttenTheme``,
/// the sheet follows this.
///
/// Every option is warm. A page lit by a lamp is warm, a page in daylight is
/// warm, and a neutral grey page reads as a switched-off screen rather than as
/// something to spend an evening with.
public enum ReaderPageTheme: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Paper by day, lamplight after dark.
    case automatic
    /// Warm white.
    case paper
    /// Aged paper.
    case sepia
    /// Warm near-black with ivory ink: a book under a reading lamp.
    case dusk
    /// As dark as it goes, for a room with no other light in it.
    case night

    public static let `default` = ReaderPageTheme.automatic

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .automatic: "Automatic"
        case .paper: "Paper"
        case .sepia: "Sepia"
        case .dusk: "Dusk"
        case .night: "Night"
        }
    }

    public var summary: String {
        switch self {
        case .automatic: "Paper by day, lamplight after dark."
        case .paper: "Warm white, the colour of a new book."
        case .sepia: "Aged paper. Easiest on the eyes in a bright room."
        case .dusk: "Ivory on warm black, like a page under a lamp."
        case .night: "As dark as it goes, for a room with no other light."
        }
    }

    /// Resolves `automatic`. Every other case ignores the argument, which is
    /// the point of choosing one.
    public func palette(inDarkMode isDarkMode: Bool) -> ReaderPagePalette {
        switch self {
        case .automatic: isDarkMode ? Self.duskPalette : Self.paperPalette
        case .paper: Self.paperPalette
        case .sepia: Self.sepiaPalette
        case .dusk: Self.duskPalette
        case .night: Self.nightPalette
        }
    }

    // A sheet of new paper on a warm desk.
    private static let paperPalette = ReaderPagePalette(
        page: 0xFDFBF6,
        pageFoot: 0xF7F2E9,
        well: 0xE6DFD2,
        ink: 0x1D1913,
        inkMuted: 0x75695A,
        accent: 0x9A5A20,
        highlight: 0xF4E3AC,
        isDark: false
    )

    // The same sheet, older.
    private static let sepiaPalette = ReaderPagePalette(
        page: 0xF8EFDC,
        pageFoot: 0xF1E4CB,
        well: 0xDCCDAE,
        ink: 0x3B2D1B,
        inkMuted: 0x735F40,
        accent: 0x8C4A16,
        highlight: 0xEBD292,
        isDark: false
    )

    // Warm black and ivory. The default after dark, and the one that answers
    // the complaint this whole type exists for: a grey page is a screen, a
    // warm one is a book.
    private static let duskPalette = ReaderPagePalette(
        page: 0x1D1916,
        pageFoot: 0x161311,
        well: 0x0E0C0B,
        ink: 0xE7DAC4,
        inkMuted: 0x9B8D78,
        accent: 0xD9A15B,
        highlight: 0x4C3B1F,
        isDark: true
    )

    // For a dark room, where even Dusk is a light source. Still off neutral:
    // the ink keeps a trace of warmth so the page does not go blue.
    private static let nightPalette = ReaderPagePalette(
        page: 0x0B0A0A,
        pageFoot: 0x070606,
        well: 0x000000,
        ink: 0xBAB4AB,
        inkMuted: 0x807A73,
        accent: 0xB08C5A,
        highlight: 0x34301F,
        isDark: true
    )
}
