import Foundation

/// A voice as it is shown to someone choosing a narrator, built from the raw
/// engine entry in `resources/voices.json` (`VoiceCatalog`). Casting a book
/// is the one choice in Atten that is expensive to change — regenerating a
/// whole audiobook — so this is what carries what that choice needs: a name
/// a person recognises, and a description instead of a spec sheet.
public struct VoiceProfile: Equatable, Sendable {
    public let voiceID: String
    /// A human-friendly name, e.g. `af_heart` → "Heart". The catalog's own
    /// `name` often carries the language in parentheses for disambiguation
    /// elsewhere; that part is dropped here since language is shown on its own.
    public let displayName: String
    /// Traits plus accent, e.g. "Warm · Expressive · US English".
    public let descriptor: String
    /// The traits alone, e.g. "Warm · Expressive"; empty when the voice has
    /// none beyond its accent.
    public let traits: String
    public let accent: String
    public let gender: String
    public let language: String
    /// A hue (0–360) for tinting this voice in casting UI, spread
    /// deterministically so voices next to each other in a list don't share a
    /// colour. Two runs of Atten must agree, so this never uses Swift's
    /// built-in string hashing, which is randomised per process.
    public let hue: Double
    /// Trait words, lowercased, for filtering a casting sheet.
    public let tones: Set<String>

    public init(voice: Voice) {
        voiceID = voice.id
        gender = voice.gender
        language = voice.language
        let resolvedAccent = Self.accent(fromLanguage: voice.language)
        accent = resolvedAccent
        displayName = Self.displayName(fromCatalogName: voice.name)
        // A trait equal to the accent (many non-English voices are given a
        // single trait naming their language, e.g. "Spanish") would otherwise
        // repeat it right next to the accent it already restates.
        let distinctTraits = voice.traits.filter { $0.caseInsensitiveCompare(resolvedAccent) != .orderedSame }
        traits = distinctTraits.map { $0.capitalized }.joined(separator: " · ")
        descriptor = (distinctTraits.map { $0.capitalized } + [resolvedAccent]).joined(separator: " · ")
        tones = Set(voice.traits.map { $0.lowercased() })
        hue = Self.hue(forVoiceID: voice.id)
    }

    private static func displayName(fromCatalogName name: String) -> String {
        guard let parenIndex = name.firstIndex(of: "(") else { return name }
        return name[..<parenIndex].trimmingCharacters(in: .whitespaces)
    }

    /// "English (US)" → "US English". A language with no parenthetical
    /// region, such as "Spanish", is already the accent.
    private static func accent(fromLanguage language: String) -> String {
        guard let open = language.firstIndex(of: "("),
              let close = language.firstIndex(of: ")"), open < close else {
            return language
        }
        let base = language[..<open].trimmingCharacters(in: .whitespaces)
        let region = language[language.index(after: open)..<close].trimmingCharacters(in: .whitespaces)
        return "\(region) \(base)"
    }

    /// FNV-1a over the id's UTF-8 bytes.
    private static func hue(forVoiceID id: String) -> Double {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in id.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return Double(hash % 360)
    }
}
