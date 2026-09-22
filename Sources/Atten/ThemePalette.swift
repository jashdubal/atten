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
    /// Dark is the reading black — the same `0x06080C` the page is printed on
    /// — carried out into the whole app, so the chrome and the page share one
    /// ground and the page has no edges. Surfaces lift off it by a few points
    /// rather than by a step: a panel here is a change of depth, not a box
    /// drawn on top of the window.
    ///
    /// The accent is the brand's, from the landing page: cyan `0x5DDBFF`, with
    /// violet `0x9E70FF` beside it. It is spent sparingly. Apple Music is the
    /// reference for how little accent a dark app needs — its red lands on
    /// about four things per screen and everything else is grey.
    ///
    /// Light is a deliberate companion, not an inversion, and the page keeps
    /// its warm paper: warm ink is what a lamp does to a page, and the
    /// brightness control still takes the ink down for a dark room.
    static let atten = AttenPalette(
        appBackground: AttenThemeColor(0xF7F8FA, 0x06080C),
        sidebar: AttenThemeColor(0xF4F6F9, 0x07090E),
        surface: AttenThemeColor(0xFFFFFF, 0x0B0F16),
        surfaceElevated: AttenThemeColor(0xFCFDFF, 0x0E131B),
        surfaceMuted: AttenThemeColor(0xEDF0F5, 0x141A24),
        separator: AttenThemeColor(0xD0D8E3, 0x1F2734),
        textPrimary: AttenThemeColor(0x0B121C, 0xE7EEF8),
        textSecondary: AttenThemeColor(0x55637A, 0x8FA2BA),
        accent: AttenThemeColor(0x0B6E8F, 0x5DDBFF),
        accentHover: AttenThemeColor(0x095A73, 0x91E8FF),
        accentSecondary: AttenThemeColor(0x6D28D9, 0x9E70FF),
        success: AttenThemeColor(0x177A50, 0x4ADE80),
        warning: AttenThemeColor(0x8A5A12, 0xF0B849),
        destructive: AttenThemeColor(0xB42346, 0xFB7185),
        onAccent: AttenThemeColor(0xFFFFFF, 0x061018),
        readerText: AttenThemeColor(0x141B26, 0xDCE6F2),
        readerBackground: AttenThemeColor(0xFBFAF7, 0x06080C),
        readerInk: AttenThemeColor(0x2A2721, 0xD6CFC2),
        readerInkMuted: AttenThemeColor(0x6A6459, 0x8B8578),
        readerAccent: AttenThemeColor(0x1F5A8C, 0x8FB8C9),
        readerHighlight: AttenThemeColor(0xD9E6F5, 0x1E3350),
        scrim: AttenThemeColor(0x0B121C, 0x000000)
    )

    /// Atten's mark, for the few places that carry the brand rather than
    /// information: the wordmark, an empty state's glyph, the one hero line.
    ///
    /// Taken from the landing page verbatim — cyan through pale cyan to
    /// violet. It is used sparingly on purpose. An accent that appears
    /// everywhere is not an accent, and the reference for this app's chrome is
    /// Apple Music, where the accent lands on perhaps four things per screen
    /// and the rest is grey on near-black.
    static let brandGradient = [Color(hex: 0x5DDBFF), Color(hex: 0xB7F2FF), Color(hex: 0x9E70FF)]
}
