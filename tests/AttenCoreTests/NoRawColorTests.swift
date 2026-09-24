import Foundation
import XCTest

/// Colours come from `AttenColor` and nowhere else. A raw hex, `.black` or
/// `.white` in a screen is a colour the palette does not know about, so it
/// cannot follow the appearance and cannot be checked for contrast.
///
/// The token files are where the raw values live, and the Reader's page is
/// content with its own palette, so those are allowed.
final class NoRawColorTests: XCTestCase {
    private static let allowlist: Set<String> = [
        "DesignSystem.swift",
        "ThemePalette.swift",
        "BookReaderView.swift",
    ]

    private static let patterns = [
        #"Color\(hex:"#,
        #"NSColor\(hex:"#,
        #"Color\(red:"#,
        #"Color\(light:"#,
        #"Color\.black\b"#,
        #"Color\.white\b"#,
        #"\.black\b"#,
        #"\.white\b"#,
    ]

    func testScreensDrawOnlyWithTokens() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Atten")
        let files = try FileManager.default.contentsOfDirectory(atPath: sources.path)
            .filter { $0.hasSuffix(".swift") }
            .filter { !Self.allowlist.contains($0) && !$0.hasPrefix("Reader") }
        XCTAssertFalse(files.isEmpty, "found no sources at \(sources.path)")

        let expressions = try Self.patterns.map { try NSRegularExpression(pattern: $0) }
        var violations: [String] = []
        for file in files.sorted() {
            let text = try String(contentsOf: sources.appendingPathComponent(file), encoding: .utf8)
            for (index, line) in text.components(separatedBy: .newlines).enumerated() {
                let range = NSRange(line.startIndex..., in: line)
                if expressions.contains(where: { $0.firstMatch(in: line, range: range) != nil }) {
                    violations.append("Sources/Atten/\(file):\(index + 1): \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        }
        XCTAssertTrue(violations.isEmpty, "raw colours outside the tokens:\n" + violations.joined(separator: "\n"))
    }
}
