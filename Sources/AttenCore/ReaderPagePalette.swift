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
