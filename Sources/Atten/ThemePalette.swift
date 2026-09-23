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
    /// Comfortable reading text, with neutral ink in the charcoal appearance.
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
    /// Neutral charcoal surfaces and muted gray controls, following the supplied Cursor reference.
    /// The light appearance and the Reader's adjustable ink remain available.
    static let atten = AttenPalette(
        appBackground: AttenThemeColor(0xF7F8FA, 0x1E1E1E),
        sidebar: AttenThemeColor(0xF4F6F9, 0x141414),
        surface: AttenThemeColor(0xFFFFFF, 0x222222),
        surfaceElevated: AttenThemeColor(0xFCFDFF, 0x282828),
        surfaceMuted: AttenThemeColor(0xEDF0F5, 0x2A2A2A),
        separator: AttenThemeColor(0xD0D8E3, 0x383838),
        textPrimary: AttenThemeColor(0x0B121C, 0xE6E6E6),
        textSecondary: AttenThemeColor(0x55637A, 0xABABAB),
        accent: AttenThemeColor(0x111922, 0xD4D4D4),
        accentHover: AttenThemeColor(0x000000, 0xF0F0F0),
        accentSecondary: AttenThemeColor(0x4C5561, 0xB8B8B8),
        success: AttenThemeColor(0x177A50, 0x73AC88),
        warning: AttenThemeColor(0x8A5A12, 0xC7AA72),
        destructive: AttenThemeColor(0xB42346, 0xE28585),
        onAccent: AttenThemeColor(0xFFFFFF, 0x1E1E1E),
        readerText: AttenThemeColor(0x141B26, 0xDCDCDC),
        readerBackground: AttenThemeColor(0xF7F8FA, 0x1E1E1E),
        readerInk: AttenThemeColor(0x2A2721, 0xDCDCDC),
        readerInkMuted: AttenThemeColor(0x6A6459, 0xA6A6A6),
        readerAccent: AttenThemeColor(0x6E6459, 0xB7B7B7),
        readerHighlight: AttenThemeColor(0xE8E2D4, 0x363636),
        scrim: AttenThemeColor(0x0B121C, 0x000000)
    )
}
