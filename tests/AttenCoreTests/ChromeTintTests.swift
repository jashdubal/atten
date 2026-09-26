import Foundation
import XCTest

/// The app is tinted `signal` so that selected controls and the primary
/// button pick it up — but a borderless menu or button draws its label in the
/// tint too, and would light every ⋯ and "Sort by" cyan (#111). Each one names
/// a quiet tint of its own.
///
/// `ImageRenderer` draws a `Menu` as a placeholder, so this is checked in the
/// source rather than in a render.
final class ChromeTintTests: XCTestCase {
    /// Screens tinted quietly as a whole.
    private static let allowlist: Set<String> = ["BookReaderView.swift"]

    func testBorderlessControlsDoNotTakeTheSignalTint() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Atten")
        let files = try FileManager.default.contentsOfDirectory(atPath: sources.path)
            .filter { $0.hasSuffix(".swift") && !Self.allowlist.contains($0) }
        XCTAssertFalse(files.isEmpty, "found no sources at \(sources.path)")

        var violations: [String] = []
        for file in files.sorted() {
            let lines = try String(contentsOf: sources.appendingPathComponent(file), encoding: .utf8)
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            for (index, line) in lines.enumerated()
            where line.hasPrefix(".menuStyle(.borderlessButton)") || line.hasPrefix(".buttonStyle(.borderless)") {
                // The rest of the modifier chain, either side of this line.
                var chain = [line]
                var above = index - 1
                while above >= 0, lines[above].hasPrefix(".") || lines[above].hasPrefix("//") {
                    chain.append(lines[above]); above -= 1
                }
                var below = index + 1
                while below < lines.count, lines[below].hasPrefix(".") || lines[below].hasPrefix("//") {
                    chain.append(lines[below]); below += 1
                }
                if !chain.contains(where: { $0.hasPrefix(".tint(") }) {
                    violations.append("Sources/Atten/\(file):\(index + 1): \(line)")
                }
            }
        }
        XCTAssertTrue(violations.isEmpty, "borderless controls with no tint of their own:\n" + violations.joined(separator: "\n"))
    }
}
