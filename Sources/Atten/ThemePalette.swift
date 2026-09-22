import AppKit
import AttenCore
import Observation
import SwiftUI

/// One semantic colour, given as the light-mode and dark-mode hex pair it
/// resolves to. Holding the raw values keeps the palette readable as a table
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
/// of these roles through `AttenColor`, which is what lets a new screen pick up
/// the right colours for free.
///
/// There is one palette. Appearance — light or dark — is the only axis, and
/// each role carries both sides of it, so switching appearance is a repaint
/// rather than a different design. What used to be seven themes is gone: seven
/// palettes meant seven sets of contrast to defend and no single surface the
/// rest of the app could be designed against.
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

    /// Long-form text in the chrome around the page — the snippets under a
    /// search result.
    let readerText: AttenThemeColor

    /// The reading surface, edge to edge.
    let readerBackground: AttenThemeColor
    /// The text on the page. Warmth lives here rather than in the background —
    /// warm ink on a neutral ground is what a lamp actually does to a page,
    /// and tinting the ground as well is what made every theme look alike.
    let readerInk: AttenThemeColor
    /// Folios, running heads, and the line above a chapter title.
    let readerInkMuted: AttenThemeColor
    /// The few marks on the page that are not words.
    let readerAccent: AttenThemeColor
    /// Fill behind a search match or the sentence being spoken.
    let readerHighlight: AttenThemeColor
    /// Drawn at partial opacity over whatever a focused view is dimming.
    let scrim: AttenThemeColor
}

extension AttenPalette {
    /// Atten's palette.
    ///
    /// Dark is a cool near-black rather than the grey the old Quiet theme used
    /// and rather than the void Terminal used: lifted just off black so the
    /// chrome has somewhere to sit, tipped towards navy so the blue accent
    /// belongs to it. The page keeps Quiet's reading comfort — warm ink on a
    /// near-black ground — because that part was right, and the brightness
    /// control still takes the ink further down for a dark room.
    ///
    /// Light is a deliberate companion, not an inversion: paper-white surfaces
    /// over a cool off-white ground, with the same blue carrying the same
    /// meaning at a weight that survives daylight.
    static let atten = AttenPalette(
        appBackground: AttenThemeColor(0xF4F6FA, 0x0A0D12),
        sidebar: AttenThemeColor(0xEAEEF5, 0x070A0E),
        surface: AttenThemeColor(0xFFFFFF, 0x11151C),
        surfaceElevated: AttenThemeColor(0xFAFCFF, 0x161B24),
        surfaceMuted: AttenThemeColor(0xE4E9F2, 0x1C222C),
        separator: AttenThemeColor(0xC3CCDA, 0x272E3A),
        textPrimary: AttenThemeColor(0x0E141C, 0xE6ECF5),
        textSecondary: AttenThemeColor(0x55637A, 0x93A1B5),
        accent: AttenThemeColor(0x0A66C2, 0x6FB4FF),
        accentHover: AttenThemeColor(0x074D96, 0x9ECBFF),
        accentSecondary: AttenThemeColor(0x1F6F86, 0x7FD1E8),
        success: AttenThemeColor(0x177A50, 0x4ADE80),
        warning: AttenThemeColor(0x8A5A12, 0xF0B849),
        destructive: AttenThemeColor(0xB42346, 0xFB7185),
        onAccent: AttenThemeColor(0xFFFFFF, 0x06111F),
        readerText: AttenThemeColor(0x141B26, 0xDCE4F0),
        readerBackground: AttenThemeColor(0xFBFAF7, 0x06080C),
        readerInk: AttenThemeColor(0x2A2721, 0xD6CFC2),
        readerInkMuted: AttenThemeColor(0x6A6459, 0x8B8578),
        readerAccent: AttenThemeColor(0x1F5A8C, 0x9FB6D8),
        readerHighlight: AttenThemeColor(0xD9E6F5, 0x1E3350),
        scrim: AttenThemeColor(0x0E141C, 0x000000)
    )
}
