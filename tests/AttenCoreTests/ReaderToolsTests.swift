import AttenCore
import XCTest
@testable import Atten

final class ReaderToolsTests: XCTestCase {
    func testToolsPanelUsesTheAvailableWidthOnNarrowWindows() {
        XCTAssertEqual(ReaderToolsLayout.panelWidth(for: 320), 288)
        XCTAssertEqual(ReaderToolsLayout.panelWidth(for: 200), 168)
    }

    func testToolsPanelDoesNotGrowWithAnExtraWideCanvas() {
        XCTAssertEqual(ReaderToolsLayout.panelWidth(for: 1_600), ReaderToolsLayout.maximumPanelWidth)
    }

    func testReaderPanelTabsRemainDiscoverable() {
        XCTAssertEqual(
            ReaderPanelTab.allCases.map(\.label),
            ["Contents", "Bookmarks"]
        )
        XCTAssertEqual(
            ReaderPanelTab.allCases.map(\.icon),
            ["list.bullet", "bookmark"]
        )
    }
}
