import Foundation
import XCTest

/// The mini player floats over content, so a vertical scroll view that forgets
/// `attenScrollPadding()` puts its last row under the player where it cannot
/// be reached.
final class ScrollPaddingTests: XCTestCase {
    func testEveryVerticalScrollViewLeavesRoomForThePlayer() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Atten")
        let files = try FileManager.default.contentsOfDirectory(atPath: sources.path)
            .filter { $0.hasSuffix(".swift") }
        XCTAssertFalse(files.isEmpty, "found no sources at \(sources.path)")

        // `ScrollView {` on its own; `NSScrollView` is the text editor's, and
        // a horizontal strip has no last row for the player to cover.
        let scrollView = try NSRegularExpression(pattern: #"(?<![A-Za-z])ScrollView \{"#)
        var violations: [String] = []
        for file in files.sorted() {
            let text = try String(contentsOf: sources.appendingPathComponent(file), encoding: .utf8)
            let scrollViews = scrollView.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
            let padded = text.components(separatedBy: ".attenScrollPadding()").count - 1
            if padded < scrollViews {
                violations.append("\(file): \(scrollViews) scroll views, \(padded) padded")
            }
        }
        XCTAssertTrue(violations.isEmpty, violations.joined(separator: "\n"))
    }
}
