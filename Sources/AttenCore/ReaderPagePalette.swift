import Foundation

/// The colours one page of reading is printed in.
///
/// There is no sheet here, and no well behind one. A page in Apple Books is
/// not an object lying on a desk — it is the window, with margins. Drawing a
/// card with a shadow and a corner radius put a visible rectangle around the
/// text, and a reader who can see the edges of the page is looking at the app
/// rather than at the book.
///
/// Held as plain hex so a page can be set on a background thread and so the
/// values can be checked for contrast without a running app.
public struct ReaderPagePalette: Equatable, Sendable {
    /// The reading surface, edge to edge. The chrome around it is drawn in the
    /// same colour, which is what makes the page have no edges.
    public let background: UInt
    public let ink: UInt
    /// Running heads, folios, and the line above a chapter title.
    public let inkMuted: UInt
    /// The few marks on the page that are not words.
    public let accent: UInt
    public let highlight: UInt
    /// Whether this is a dark page, for deciding how heavy a shadow under a
    /// turning leaf has to be to be seen at all.
    public let isDark: Bool

    public init(
        background: UInt,
        ink: UInt,
        inkMuted: UInt,
        accent: UInt,
        highlight: UInt,
        isDark: Bool
    ) {
        self.background = background
        self.ink = ink
        self.inkMuted = inkMuted
        self.accent = accent
        self.highlight = highlight
        self.isDark = isDark
    }
}

extension ReaderPagePalette {
    /// How far the ink may be taken down.
    ///
    /// This range deliberately goes below WCAG AA, which the themes otherwise
    /// clear by design: AA is a floor for text a reader is made to read, and
    /// this is a reader choosing, on their own page, at night, with the level
    /// in front of them and the way back a drag away. What it will not do is
    /// let the words disappear into the page — at the dimmest setting the
    /// tightest theme still holds about 2.5:1, which is soft, not gone.
    ///
    /// One floor for every theme, set by the tightest of them. A dark page
    /// could go further, but a control whose range moves when the lights
    /// change is a control the reader cannot learn.
    public static let inkBrightnessRange = 0.45...1.0

    /// The same page with quieter ink.
    ///
    /// Night reading at full contrast glares. The way not to do this is to
    /// fade the whole page towards grey, which lifts the ground as much as it
    /// drops the ink and leaves the reader looking at a washed-out screen.
    /// Instead the ink is carried towards the ground the theme already chose,
    /// so a warm page stays warm and only the text softens. The ground, the
    /// accent, and a search highlight are left alone: they are marks, not
    /// prose, and a reader who has dimmed the text still has to find them.
    public func dimmingInk(to brightness: Double) -> ReaderPagePalette {
        let level = min(max(Self.inkBrightnessRange.lowerBound, brightness), Self.inkBrightnessRange.upperBound)
        guard level < 1 else { return self }
        return ReaderPagePalette(
            background: background,
            ink: Self.blend(ink, towards: background, by: 1 - level),
            inkMuted: Self.blend(inkMuted, towards: background, by: 1 - level),
            accent: accent,
            highlight: highlight,
            isDark: isDark
        )
    }

    private static func blend(_ color: UInt, towards target: UInt, by amount: Double) -> UInt {
        func channel(_ shift: UInt) -> UInt {
            let from = Double((color >> shift) & 0xff)
            let to = Double((target >> shift) & 0xff)
            return UInt((from + (to - from) * amount).rounded())
        }
        return (channel(16) << 16) | (channel(8) << 8) | channel(0)
    }
}
