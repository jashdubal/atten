import AttenCore
import AttenFixtureKit
import Foundation
import XCTest
@testable import Atten

/// The `make-fixture-library` QA tool (#107) has to produce something the
/// app actually opens. This builds the same fixtures the CLI does and loads
/// them the way `AttenApp` does when `ATTEN_DATA_DIRECTORY` is set.
@MainActor
final class FixtureLibraryTests: XCTestCase {
    private var workspace: URL!

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: workspace)
    }

    func testFiftyBookLibraryLoadsThroughBookshelfModel() async throws {
        workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttenFixtureLibrary-\(UUID().uuidString)")
        let directories = AppDirectories(applicationSupport: workspace.appendingPathComponent("Application Support"))

        let built = try LibraryFixture.build(count: 50, voicedFraction: 0.3, in: directories)
        try await BookLibraryStore(fileURL: directories.booksFile).save(built.books)
        try LibraryFixture.saveQueue(built.queue, to: directories)

        let shelf = BookshelfModel(directories: directories, generator: ImmediateGenerator())
        await shelf.load()

        XCTAssertNil(shelf.errorMessage)
        XCTAssertEqual(shelf.books.count, 50)

        // Every format, every state, and mixed languages actually made it
        // onto the shelf, not just onto disk.
        XCTAssertEqual(Set(shelf.books.map(\.format)), Set([.epub, .document, .pdf, .mobi]))
        XCTAssertTrue(shelf.books.contains { $0.hasBookAudio }, "expected at least one voiced book")
        XCTAssertTrue(shelf.books.contains { !$0.hasBookAudio && $0.narratedCount == 0 }, "expected at least one draft")
        XCTAssertTrue(shelf.books.contains { $0.narrationState == .interrupted }, "expected at least one interrupted, mid-narration book")
        XCTAssertTrue(Set(shelf.books.map(\.voiceID)).count > 1, "expected more than one language/voice")

        // A voiced book's audio and word timings really do load.
        let voiced = try XCTUnwrap(shelf.books.first { $0.hasBookAudio })
        let audioURL = try XCTUnwrap(voiced.audioURL)
        XCTAssertNotNil(try NarrationTimings.load(beside: audioURL))

        // The queue restored from queue.json only drops books that are
        // already fully narrated, exactly as a real relaunch would; none of
        // the fixture's queued books are, so all of them survive.
        XCTAssertFalse(built.queue.isEmpty, "fixture should have queued at least one book")
        XCTAssertEqual(shelf.queue.count, built.queue.count)
    }
}
