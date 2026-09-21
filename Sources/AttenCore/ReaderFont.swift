import Foundation

/// The face a page is set in.
///
/// The list is the one Apple Books offers, and for the same reason: these are
/// the faces macOS ships that were drawn for continuous reading, so any of
/// them can be read for an hour without the page turning into work. The system
/// serif is not on it — it is a UI face with serifs added, and it reads like
/// one at paragraph length.
///
/// Both ends of the list matter here. A novel wants ``iowan`` or ``charter``;
/// a report or a paper someone is having read aloud to them often wants
/// ``seravek`` or ``system``, because that is what the document itself was
/// written in.
public enum ReaderFont: String, Codable, CaseIterable, Identifiable, Sendable {
    case iowan
    case charter
    case athelas
    case georgia
    case palatino
    case seravek
    case system

    /// Iowan Old Style: a warm humanist face with a large x-height, which is
    /// what keeps it readable at the sizes a screen is read at.
    public static let `default` = ReaderFont.iowan

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .iowan: "Iowan Old Style"
        case .charter: "Charter"
        case .athelas: "Athelas"
        case .georgia: "Georgia"
        case .palatino: "Palatino"
        case .seravek: "Seravek"
        case .system: "System"
        }
    }

    /// Whether the face has serifs, which decides how a page set in it is
    /// spaced: a sans face needs a little more air between lines to hold a
    /// long measure together.
    public var isSerif: Bool {
        switch self {
        case .seravek, .system: false
        default: true
        }
    }

    /// The family to ask the font system for. `system` has none — it is
    /// whatever the system face currently is.
    public var familyName: String? {
        switch self {
        case .iowan: "Iowan Old Style"
        case .charter: "Charter"
        case .athelas: "Athelas"
        case .georgia: "Georgia"
        case .palatino: "Palatino"
        case .seravek: "Seravek"
        case .system: nil
        }
    }
}
