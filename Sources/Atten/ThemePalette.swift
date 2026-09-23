import AppKit
import AttenCore
import Observation
import SwiftUI

/// One semantic colour, given as the light-mode and dark-mode sRGB pair it
/// resolves to. Holding the raw values keeps the palette readable as a table
/// and lets the accessibility tests measure contrast without a running app.
struct AttenThemeColor: Sendable, Equatable {
    let light: UInt
    let dark: UInt
    /// Opacity on each side. Only the translucent roles — glass, hairline and
    /// the glass highlight and shadow — are below 1.
    let lightAlpha: Double
    let darkAlpha: Double
    /// Built once, when the palette is first touched, so reading a colour
    /// during a view update is a field access rather than an allocation.
    let color: Color

    init(_ light: UInt, _ dark: UInt) {
        self.init(light: light, dark: dark, lightAlpha: 1, darkAlpha: 1)
    }

    /// A role written as the OKLCH pair it is designed in.
    init(light: OKLCH, dark: OKLCH) {
        self.init(light: light.hex, dark: dark.hex, lightAlpha: light.alpha, darkAlpha: dark.alpha)
    }

    private init(light: UInt, dark: UInt, lightAlpha: Double, darkAlpha: Double) {
        self.light = light
        self.dark = dark
        self.lightAlpha = lightAlpha
        self.darkAlpha = darkAlpha
        self.color = Color(nsColor: Self.dynamic(light, lightAlpha, dark, darkAlpha))
    }

    /// For the few places that hand a colour to AppKit directly.
    var nsColor: NSColor { Self.dynamic(light, lightAlpha, dark, darkAlpha) }

    private static func dynamic(_ light: UInt, _ lightAlpha: Double, _ dark: UInt, _ darkAlpha: Double) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
                .withAlphaComponent(isDark ? darkAlpha : lightAlpha)
        }
    }
}

/// Every colour the interface draws with. Views never name a hue; they name one
/// of these roles through `AttenColor`, which is what lets a new screen pick up
/// the right colours for free.
///
/// The chrome is nearly colourless. Colour and light come from content —
/// covers, the ambient tint — and from voice that is live. `signal` is the
/// one hue in the chrome and it is reserved for that: playing, generating, the
/// current word, the primary button, and the focus ring. Nowhere else.
///
/// The dark appearance is the designed one. The light side of each role keeps
/// its hue and mirrors its lightness, far enough that every role holds at
/// least the contrast its dark side has.
struct AttenPalette: Sendable, Equatable {
    // MARK: Chrome

    /// The window's ground.
    let bg: AttenThemeColor
    /// One step off the ground: a card, a field, a panel.
    let surface1: AttenThemeColor
    /// The tint laid over a material. Translucent by design.
    let glass: AttenThemeColor
    /// Every 1pt edge and divider.
    let hairline: AttenThemeColor
    let text1: AttenThemeColor
    let text2: AttenThemeColor
    let text3: AttenThemeColor
    /// Voice that is live. See the type's note before reaching for it.
    let signal: AttenThemeColor
    /// Text and glyphs drawn on `signal`.
    let signalInk: AttenThemeColor
    /// A hover fill or a progress groove: a step off `surface1`.
    let surfaceMuted: AttenThemeColor
    /// The 1pt inner top edge that catches light on glass.
    let glassHighlight: AttenThemeColor
    /// The shadow under glass.
    let glassShadow: AttenThemeColor
    /// What every other shadow is cast in, at the opacity its elevation asks.
    let shadow: AttenThemeColor

    // MARK: Status

    let success: AttenThemeColor
    let warning: AttenThemeColor
    let destructive: AttenThemeColor

    // MARK: The page

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

/// The names screens were written against, mapped onto the roles above until
/// each screen is moved over. `accent` is no longer the button colour: it is a
/// neutral, and the one hue belongs to `signal`.
extension AttenPalette {
    var appBackground: AttenThemeColor { bg }
    var sidebar: AttenThemeColor { bg }
    var surface: AttenThemeColor { surface1 }
    var surfaceElevated: AttenThemeColor { surface1 }
    var separator: AttenThemeColor { hairline }
    var textPrimary: AttenThemeColor { text1 }
    var textSecondary: AttenThemeColor { text2 }
    var textMuted: AttenThemeColor { text3 }
    var accent: AttenThemeColor { text1 }
    var accentHover: AttenThemeColor { text1 }
    var accentSecondary: AttenThemeColor { text2 }
    var onAccent: AttenThemeColor { bg }
    /// Long-form text in the chrome around the page — the snippets under a
    /// search result.
    var readerText: AttenThemeColor { text1 }
    /// The reading surface, edge to edge. It is the window's ground, so the
    /// page has no edge to see.
    var readerBackground: AttenThemeColor { bg }
}

extension AttenPalette {
    static let atten = AttenPalette(
        bg: AttenThemeColor(light: OKLCH(0.975, 0.004, 265), dark: OKLCH(0.14, 0.008, 265)),
        surface1: AttenThemeColor(light: OKLCH(0.995, 0.003, 265), dark: OKLCH(0.18, 0.01, 265)),
        glass: AttenThemeColor(
            light: OKLCH(0.98, 0.005, 265, alpha: 0.6),
            dark: OKLCH(0.20, 0.01, 265, alpha: 0.55)
        ),
        hairline: AttenThemeColor(light: OKLCH(0, 0, 0, alpha: 0.08), dark: OKLCH(1, 0, 0, alpha: 0.07)),
        text1: AttenThemeColor(light: OKLCH(0.14, 0.01, 265), dark: OKLCH(0.97, 0, 0)),
        text2: AttenThemeColor(light: OKLCH(0.41, 0.01, 265), dark: OKLCH(0.72, 0.01, 265)),
        text3: AttenThemeColor(light: OKLCH(0.58, 0.01, 265), dark: OKLCH(0.52, 0.01, 265)),
        // Light signal sits below the brief's 0.62 so signalInk on it clears
        // 4.5:1; at 0.62 a primary button's label was 3.4:1.
        signal: AttenThemeColor(light: OKLCH(0.55, 0.12, 210), dark: OKLCH(0.84, 0.13, 200)),
        signalInk: AttenThemeColor(light: OKLCH(0.99, 0.01, 220), dark: OKLCH(0.18, 0.03, 220)),
        surfaceMuted: AttenThemeColor(light: OKLCH(0.93, 0.005, 265), dark: OKLCH(0.23, 0.01, 265)),
        glassHighlight: AttenThemeColor(light: OKLCH(1, 0, 0, alpha: 0.08), dark: OKLCH(1, 0, 0, alpha: 0.08)),
        glassShadow: AttenThemeColor(light: OKLCH(0, 0, 0, alpha: 0.12), dark: OKLCH(0, 0, 0, alpha: 0.45)),
        shadow: AttenThemeColor(light: OKLCH(0, 0, 0), dark: OKLCH(0, 0, 0)),
        success: AttenThemeColor(0x177A50, 0x73AC88),
        warning: AttenThemeColor(0x8A5A12, 0xC7AA72),
        destructive: AttenThemeColor(0xB42346, 0xE28585),
        readerInk: AttenThemeColor(0x2A2721, 0xDCDCDC),
        readerInkMuted: AttenThemeColor(0x6A6459, 0xA6A6A6),
        readerAccent: AttenThemeColor(0x6E6459, 0xB7B7B7),
        readerHighlight: AttenThemeColor(0xE8E2D4, 0x363636),
        scrim: AttenThemeColor(0x0B121C, 0x000000)
    )
}

/// The one colour that is set while the app runs: a tint taken from whatever
/// is playing, behind the player. Whatever is proposed is held to a mid
/// lightness and a quiet chroma, then darkened until `text1` reads on it.
@MainActor
@Observable
final class AttenAmbient {
    static let shared = AttenAmbient()

    /// Before anything has proposed a colour: a neutral from the chrome's hue.
    static let neutral = OKLCH(0.5, 0.01, 265)

    private(set) var tint: OKLCH

    init() {
        tint = Self.clamped(Self.neutral)
    }

    var color: Color { Color(hex: tint.hex) }

    func set(_ proposed: OKLCH) {
        tint = Self.clamped(proposed)
    }

    func reset() {
        tint = Self.clamped(Self.neutral)
    }

    /// Ambient sits behind light text in both appearances, so it is held
    /// against the dark side of `text1`.
    static func clamped(_ proposed: OKLCH) -> OKLCH {
        proposed.clampedForAmbient(text: AttenPalette.atten.text1.dark)
    }
}
