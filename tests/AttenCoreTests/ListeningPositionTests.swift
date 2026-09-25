import AttenCore
import Foundation
import XCTest
@testable import Atten

/// Playback positions in `positions.json`: what is written, how often, and
/// how it is reconciled with the positions older builds left in `books.json`.
@MainActor
final class ListeningPositionTests: XCTestCase {
    private var root: URL!
    private var directories: AppDirectories!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("AttenPositions-\(UUID().uuidString)")
        directories = AppDirectories(applicationSupport: root)
        try directories.prepare()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - The file

    func testPositionsRoundTrip() async throws {
        let clock = ManualClock()
        let store = ListeningPositionStore(fileURL: directories.positionsFile, clock: clock.clock)
        let (first, second) = (UUID(), UUID())
        await store.record(12.5, for: first, at: clock.now)
        clock.advance(by: 10)
        await store.record(300, for: second, at: clock.now)
        try await store.flush()

        let loaded = await ListeningPositionStore(fileURL: directories.positionsFile).load()
        XCTAssertEqual(loaded[first], ListeningPosition(position: 12.5, updatedAt: clock.now.addingTimeInterval(-10)))
        XCTAssertEqual(loaded[second], ListeningPosition(position: 300, updatedAt: clock.now))

        // Book ids are the keys, so the file reads the same by hand.
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: directories.positionsFile)) as? [String: Any])
        XCTAssertEqual(Set(json.keys), [first.uuidString, second.uuidString])
    }

    func testAnOlderPositionDoesNotReplaceANewerOne() async throws {
        let clock = ManualClock()
        let store = ListeningPositionStore(fileURL: directories.positionsFile, clock: clock.clock)
        let id = UUID()
        await store.record(50, for: id, at: clock.now)
        await store.record(10, for: id, at: clock.now.addingTimeInterval(-1))
        try await store.flush()
        let loaded = await ListeningPositionStore(fileURL: directories.positionsFile).load()
        XCTAssertEqual(loaded[id]?.position, 50)
    }

    func testADamagedFileIsKeptAsideAndTheShelfsPositionsStand() async throws {
        try Data("{\"not\": ".utf8).write(to: directories.positionsFile)
        let book = try seededBook(position: 7, listenedAt: Date(timeIntervalSince1970: 1_000))
        try await BookLibraryStore(fileURL: directories.booksFile).save([book])

        let shelf = BookshelfModel(directories: directories, generator: ImmediateGenerator())
        await shelf.load()
        XCTAssertEqual(shelf.book(id: book.id)?.listeningPosition, 7)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directories.positionsFile.path + ".corrupt"))
    }

    // MARK: - Precedence

    func testTheNewerUpdatedAtWins() throws {
        let earlier = Date(timeIntervalSince1970: 1_000)
        let later = Date(timeIntervalSince1970: 2_000)
        var book = try seededBook(position: 10, listenedAt: earlier)

        book.adopt(ListeningPosition(position: 99, updatedAt: later))
        XCTAssertEqual(book.listeningPosition, 99)
        XCTAssertEqual(book.lastListenedAt, later)

        book.adopt(ListeningPosition(position: 5, updatedAt: earlier))
        XCTAssertEqual(book.listeningPosition, 99, "An older position does not win")

        book.adopt(ListeningPosition(position: 42, updatedAt: later))
        XCTAssertEqual(book.listeningPosition, 99, "On a tie the book's own record stands")

        var neverListened = try seededBook(position: 0, listenedAt: nil)
        neverListened.adopt(ListeningPosition(position: 3, updatedAt: earlier))
        XCTAssertEqual(neverListened.listeningPosition, 3)
        neverListened.adopt(nil)
        XCTAssertEqual(neverListened.listeningPosition, 3)
    }

    func testAShelfSavedByAnOlderBuildAfterwardsStillWins() async throws {
        // positions.json from this build, then books.json written later by an
        // older build that knows nothing of it.
        let book = try seededBook(position: 80, listenedAt: Date(timeIntervalSince1970: 2_000))
        try await BookLibraryStore(fileURL: directories.booksFile).save([book])
        let store = ListeningPositionStore(fileURL: directories.positionsFile)
        await store.record(20, for: book.id, at: Date(timeIntervalSince1970: 1_000))
        try await store.flush()

        let shelf = BookshelfModel(directories: directories, generator: ImmediateGenerator())
        await shelf.load()
        XCTAssertEqual(shelf.book(id: book.id)?.listeningPosition, 80)
    }

    // MARK: - Migration

    func testPositionsInBooksJSONStillLoadAndNewOnesSkipIt() async throws {
        // A shelf from before positions.json: the position lives only in books.json.
        let book = try seededBook(position: 33, listenedAt: Date(timeIntervalSince1970: 1_000))
        try await BookLibraryStore(fileURL: directories.booksFile).save([book])
        let booksBefore = try Data(contentsOf: directories.booksFile)

        let shelf = BookshelfModel(directories: directories, generator: ImmediateGenerator())
        await shelf.load()
        XCTAssertEqual(shelf.book(id: book.id)?.listeningPosition, 33)

        shelf.saveListeningPosition(61, for: book.id)
        try await shelf.flushPersistence()
        XCTAssertEqual(try Data(contentsOf: directories.booksFile), booksBefore, "Saving a position does not rewrite the library")
        let saved = await ListeningPositionStore(fileURL: directories.positionsFile).load()
        XCTAssertEqual(saved[book.id]?.position, 61)

        let relaunched = BookshelfModel(directories: directories, generator: ImmediateGenerator())
        await relaunched.load()
        XCTAssertEqual(relaunched.book(id: book.id)?.listeningPosition, 61)
        XCTAssertEqual(relaunched.book(id: book.id)?.lastListenedAt, saved[book.id]?.updatedAt)
    }

    func testTheNextFullSaveCarriesThePositionForOlderBuilds() async throws {
        let book = try seededBook(position: 0, listenedAt: nil)
        try await BookLibraryStore(fileURL: directories.booksFile).save([book])
        let shelf = BookshelfModel(directories: directories, generator: ImmediateGenerator())
        await shelf.load()

        shelf.saveListeningPosition(44, for: book.id)
        shelf.markOpened(book.id)
        try await shelf.flushPersistence()

        let onShelf = try await BookLibraryStore(fileURL: directories.booksFile).load()
        XCTAssertEqual(onShelf.first?.listeningPosition, 44)
    }

    func testRemovingNarrationForgetsThePosition() async throws {
        let book = try seededBook(position: 0, listenedAt: nil)
        try await BookLibraryStore(fileURL: directories.booksFile).save([book])
        let shelf = BookshelfModel(directories: directories, generator: ImmediateGenerator())
        await shelf.load()
        shelf.saveListeningPosition(44, for: book.id)
        shelf.removeNarration(book.id)
        try await shelf.flushPersistence()

        let relaunched = BookshelfModel(directories: directories, generator: ImmediateGenerator())
        await relaunched.load()
        XCTAssertEqual(relaunched.book(id: book.id)?.listeningPosition, 0)
        XCTAssertNil(relaunched.book(id: book.id)?.lastListenedAt)
    }

    // MARK: - Coalescing

    func testWritesAreCoalescedToOneEveryFiveSeconds() async throws {
        let clock = ManualClock()
        let store = ListeningPositionStore(fileURL: directories.positionsFile, clock: clock.clock)
        let id = UUID()

        // The first change goes out at once.
        await store.record(1, for: id, at: clock.now)
        var writes = await store.writeCount
        XCTAssertEqual(writes, 1)
        XCTAssertEqual(try onDisk(id), 1)

        // Changes inside the interval wait for its end, and go out as one.
        for second in 1...4 {
            clock.advance(by: 1)
            await store.record(Double(second + 1), for: id, at: clock.now)
            // The scheduled write registers its sleep asynchronously; advancing
            // before it does would push its deadline past the interval.
            if second == 1 { try await waitUntil { clock.sleeperCount == 1 } }
        }
        writes = await store.writeCount
        XCTAssertEqual(writes, 1)
        XCTAssertEqual(try onDisk(id), 1)
        XCTAssertEqual(clock.requestedSleeps, [4], "The wait runs to five seconds after the last write")

        clock.advance(by: 1)
        try await waitUntilAsync { await store.writeCount == 2 }
        XCTAssertEqual(try onDisk(id), 5)

        // A change right after that write waits again; quitting writes it now.
        clock.advance(by: 0.5)
        await store.record(6, for: id, at: clock.now)
        writes = await store.writeCount
        XCTAssertEqual(writes, 2)
        try await store.flush()
        writes = await store.writeCount
        XCTAssertEqual(writes, 3)
        XCTAssertEqual(try onDisk(id), 6)

        // Nothing new, nothing written.
        try await store.flush()
        writes = await store.writeCount
        XCTAssertEqual(writes, 3)

        // After a quiet spell longer than the interval, a change goes out at once.
        clock.advance(by: 30)
        await store.record(7, for: id, at: clock.now)
        writes = await store.writeCount
        XCTAssertEqual(writes, 4)
    }

    // MARK: - Helpers

    private func onDisk(_ id: UUID) throws -> Double? {
        let data = try Data(contentsOf: directories.positionsFile)
        return try JSONDecoder().decode([String: ListeningPosition].self, from: data)[id.uuidString]?.position
    }

    private func seededBook(position: Double, listenedAt: Date?) throws -> BookRecord {
        let id = UUID()
        let source = directories.bookSources.appendingPathComponent("\(id.uuidString).txt")
        try "Words.".write(to: source, atomically: true, encoding: .utf8)
        var book = BookRecord(
            id: id, title: "Positions", format: .document, sourcePath: source.path,
            chapters: [BookChapter(title: "One", text: "Words.")],
            voiceID: "af_heart", speed: 1, audioFormat: .wav
        )
        book.listeningPosition = position
        book.lastListenedAt = listenedAt
        return book
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<500 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("condition was never met")
    }

    private func waitUntilAsync(_ condition: () async -> Bool) async throws {
        for _ in 0..<500 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("condition was never met")
    }
}

/// Time that moves only when a test says so.
final class ManualClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_800_000_000)
    private var sleepers: [(deadline: Date, continuation: CheckedContinuation<Void, Never>)] = []
    private var sleeps: [TimeInterval] = []

    var clock: ListeningPositionStore.Clock {
        ListeningPositionStore.Clock(now: { self.now }, sleep: { await self.sleep($0) })
    }

    var now: Date { lock.withLock { current } }
    var sleeperCount: Int { lock.withLock { sleepers.count } }
    /// Every wait asked for, in seconds.
    var requestedSleeps: [TimeInterval] { lock.withLock { sleeps } }

    func advance(by seconds: TimeInterval) {
        let due = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            current = current.addingTimeInterval(seconds)
            let due = sleepers.filter { $0.deadline <= current }.map(\.continuation)
            sleepers.removeAll { $0.deadline <= current }
            return due
        }
        due.forEach { $0.resume() }
    }

    private func sleep(_ seconds: TimeInterval) async {
        await withCheckedContinuation { continuation in
            lock.withLock {
                sleeps.append(seconds)
                sleepers.append((current.addingTimeInterval(seconds), continuation))
            }
        }
    }
}
