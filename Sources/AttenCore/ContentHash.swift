import CryptoKit
import Foundation

/// Identifies a book by what it says rather than where it came from, so the
/// same text imported twice — under a different file name, or re-exported
/// from a different app — is recognised as the book already on the shelf.
public enum ContentHash {
    /// SHA-256 of the text, normalized first so formatting differences that
    /// don't change what is read — Unicode form, a run of whitespace, a
    /// leading or trailing space — don't produce a different hash.
    public static func of(_ text: String) -> String {
        let digest = SHA256.hash(data: Data(normalize(text).utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func normalize(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
