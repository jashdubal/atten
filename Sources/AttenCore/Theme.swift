import Foundation

/// The colour schemes a reader can pick between. Atten is used by people who
/// want a plain white page and by people who want the loudest thing on their
/// screen, so the set spans both ends rather than offering one house style.
///
/// Each theme carries a full light and dark palette, so this stays independent
/// of ``AppearancePreference``: picking Sepia and picking Dark are two separate
/// decisions that combine.
public enum AttenTheme: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Atten's original cyan console palette.
    case terminal
    /// Muted white with quiet ink accents.
    case paper
    /// Near-greyscale and the lowest contrast of the set.
    case quiet
    /// Warm parchment for long reading sessions.
    case sepia
    /// Restrained steel blue for a work machine.
    case slate
    /// Magenta and cyan over deep purple.
    case vaporwave
    /// Green phosphor on black.
    case matrix

    public static let `default` = AttenTheme.terminal

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .terminal: "Terminal"
        case .paper: "Paper"
        case .quiet: "Quiet"
        case .sepia: "Sepia"
        case .slate: "Slate"
        case .vaporwave: "Vaporwave"
        case .matrix: "Matrix"
        }
    }

    /// One line describing who the theme is for, shown beside the picker.
    public var summary: String {
        switch self {
        case .terminal: "Atten's cyan console. Bright accents, technical feel."
        case .paper: "Muted white with quiet ink accents. Almost no colour."
        case .quiet: "Dimmed greyscale. The gentlest option in a dark room."
        case .sepia: "Warm parchment tuned for hours of reading."
        case .slate: "Restrained steel blue. At home on a work machine."
        case .vaporwave: "Magenta and cyan over deep purple. Loud on purpose."
        case .matrix: "Green phosphor on black. Loud on purpose."
        }
    }

    /// The SF Symbol shown for the theme in menus and pickers.
    public var icon: String {
        switch self {
        case .terminal: "terminal"
        case .paper: "doc.plaintext"
        case .quiet: "circle.lefthalf.filled"
        case .sepia: "book.closed"
        case .slate: "briefcase"
        case .vaporwave: "sparkles"
        case .matrix: "chevron.left.forwardslash.chevron.right"
        }
    }
}
