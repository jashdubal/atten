import AttenCore
import XCTest

final class ContentHashTests: XCTestCase {
    func testIdenticalTextHashesTheSame() {
        XCTAssertEqual(ContentHash.of("Hello, world."), ContentHash.of("Hello, world."))
    }

    func testWhitespaceOnlyDifferencesHashTheSame() {
        let tidy = "Hello, world.\nThis is a book."
        let messy = "  Hello,   world.\n\n\nThis   is\ta book.   "
        XCTAssertEqual(ContentHash.of(tidy), ContentHash.of(messy))
    }

    func testUnicodeNormalizationHashesTheSame() {
        // "é" as one precomposed scalar vs. "e" + a combining acute accent.
        let precomposed = "Caf\u{00E9}"
        let decomposed = "Cafe\u{0301}"
        XCTAssertEqual(ContentHash.of(precomposed), ContentHash.of(decomposed))
    }

    func testDifferentTextHashesDifferently() {
        XCTAssertNotEqual(ContentHash.of("Hello, world."), ContentHash.of("Goodbye, world."))
    }
}
