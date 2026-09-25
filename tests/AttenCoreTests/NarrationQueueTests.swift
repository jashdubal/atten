import AttenCore
import Foundation
import XCTest
@testable import Atten

@MainActor
final class NarrationQueueTests: XCTestCase {
    private var workspace: URL!
    private var directories: AppDirectories!
    private var generator: GatedGenerator!
    private var shelf: BookshelfModel!

    override func setUp() async throws {
        workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttenQueueTests-\(UUID().uuidString)")
        directories = AppDirectories(
            applicationSupport: workspace.appendingPathComponent("Application Support")
        )
        try directories.prepare()
        generator = GatedGenerator()
        shelf = BookshelfModel(directories: directories, generator: generator)
    }

    override func tearDown() async throws {
        generator.open()
        try? await shelf.stopAndSave()
        try? FileManager.default.removeItem(at: workspace)
    }

    func testNarratingWhileAnotherRunsQueuesIt() async throws {
        let first = try draft("First")
        let second = try draft("Second")

        shelf.narrate(first.id, useMPS: false)
        shelf.narrate(second.id, useMPS: false)

        XCTAssertEqual(shelf.narratingBookID, first.id)
        XCTAssertEqual(shelf.queue.map(\.bookID), [first.id, second.id])
        XCTAssertTrue(shelf.isQueued(second.id))
        XCTAssertFalse(shelf.isQueued(first.id))
        XCTAssertNil(shelf.errorMessage)

        generator.open()
        try await waitUntil { self.shelf.queue.isEmpty && !self.shelf.isNarrating }
        XCTAssertTrue(try XCTUnwrap(shelf.book(id: first.id)).isFullyNarrated)
        XCTAssertTrue(try XCTUnwrap(shelf.book(id: second.id)).isFullyNarrated)
    }

    func testQueueRunsInOrderAfterReorderingAndRemoving() async throws {
        let books = try ["A", "B", "C", "D"].map { try draft($0) }
        var finished: [UUID] = []
        shelf.onNarrationFinished = { finished.append($0.bookID) }
        for book in books { shelf.narrate(book.id, useMPS: false) }
        XCTAssertEqual(shelf.queue.map(\.bookID), books.map(\.id))

        shelf.moveQueue(fromOffsets: [3], toOffset: 1)
        XCTAssertEqual(shelf.queue.map(\.bookID), [books[0], books[3], books[1], books[2]].map(\.id))
        shelf.removeFromQueue(books[1].id)
        XCTAssertEqual(shelf.queue.map(\.bookID), [books[0], books[3], books[2]].map(\.id))

        generator.open()
        try await waitUntil { self.shelf.queue.isEmpty && !self.shelf.isNarrating }
        XCTAssertEqual(finished, [books[0], books[3], books[2]].map(\.id))
        XCTAssertEqual(shelf.narratedCount(of: try XCTUnwrap(shelf.book(id: books[1].id))), 0)
    }

    func testPauseStopsAtAChapterBoundaryAndResumeContinuesFromTheCheckpoint() async throws {
        let book = try draft("Paused", chapters: 3)
        let next = try draft("Next")
        shelf.narrate(book.id, useMPS: false)
        shelf.narrate(next.id, useMPS: false)
        try await waitUntil { self.generator.started.count == 1 }

        // Paused mid-chapter: the chapter in flight still finishes.
        shelf.pauseNarration(book.id)
        XCTAssertEqual(shelf.narratingBookID, book.id)
        generator.release()
        try await waitUntil { self.shelf.narratingBookID == next.id }

        let paused = try XCTUnwrap(shelf.book(id: book.id))
        XCTAssertEqual(paused.narratedCount, 1)
        XCTAssertEqual(paused.narrationState, .interrupted)
        XCTAssertTrue(paused.chapters[0].isNarrated)
        XCTAssertEqual(shelf.queue.map(\.bookID), [book.id, next.id])
        XCTAssertTrue(shelf.isPaused(book.id))
        XCTAssertEqual(generator.started, [paused.chapters[0].text, next.chapters[0].text])

        generator.open()
        try await waitUntil { !self.shelf.isNarrating }
        shelf.resumeNarration(book.id)
        XCTAssertEqual(shelf.narratingBookID, book.id)
        try await waitUntil { self.shelf.queue.isEmpty && !self.shelf.isNarrating }

        let resumed = try XCTUnwrap(shelf.book(id: book.id))
        XCTAssertTrue(resumed.isFullyNarrated)
        // The finished chapter was kept, not spoken again.
        XCTAssertEqual(
            generator.started.filter { text in resumed.chapters.contains { $0.text == text } },
            resumed.chapters.map(\.text)
        )
    }

    func testCancellingTheRunningNarrationStartsTheNext() async throws {
        let first = try draft("First", chapters: 2)
        let second = try draft("Second")
        shelf.narrate(first.id, useMPS: false)
        shelf.narrate(second.id, useMPS: false)
        try await waitUntil { self.generator.started.count == 1 }

        shelf.cancelNarration()
        try await waitUntil { self.shelf.narratingBookID == second.id }
        XCTAssertEqual(shelf.queue.map(\.bookID), [second.id])
        XCTAssertEqual(shelf.book(id: first.id)?.narrationState, .interrupted)
    }

    func testTheQueueSurvivesARelaunchPausedAndDoesNotStart() async throws {
        let first = try draft("First")
        let second = try draft("Second")
        shelf.narrate(first.id, useMPS: false)
        shelf.narrate(second.id, useMPS: false)
        try await shelf.flushPersistence()

        let reopened = BookshelfModel(directories: directories, generator: ImmediateGenerator())
        await reopened.load()
        XCTAssertEqual(reopened.queue.map(\.bookID), [first.id, second.id])
        XCTAssertTrue(reopened.queue.allSatisfy(\.isPaused))
        XCTAssertFalse(reopened.isNarrating)

        // Quitting keeps the running narration in the queue too.
        try await shelf.stopAndSave()
        let again = BookshelfModel(directories: directories, generator: ImmediateGenerator())
        await again.load()
        XCTAssertEqual(again.queue.map(\.bookID), [first.id, second.id])
    }

    func testLibraryDataWithoutAQueueLoadsWithAnEmptyOne() async throws {
        let book = try draft("Old")
        try await shelf.flushPersistence()
        let queueFile = NarrationQueueFile.url(in: directories)
        XCTAssertFalse(FileManager.default.fileExists(atPath: queueFile.path))

        let reopened = BookshelfModel(directories: directories, generator: ImmediateGenerator())
        await reopened.load()
        XCTAssertEqual(reopened.books.map(\.id), [book.id])
        XCTAssertTrue(reopened.queue.isEmpty)

        // An unreadable queue, or one naming a book no longer on the shelf,
        // costs the queue and nothing else.
        try Data("not json".utf8).write(to: queueFile)
        let garbled = BookshelfModel(directories: directories, generator: ImmediateGenerator())
        await garbled.load()
        XCTAssertEqual(garbled.books.map(\.id), [book.id])
        XCTAssertTrue(garbled.queue.isEmpty)

        try NarrationQueueFile.save([QueuedNarration(bookID: UUID(), useMPS: false)], to: queueFile)
        let stale = BookshelfModel(directories: directories, generator: ImmediateGenerator())
        await stale.load()
        XCTAssertTrue(stale.queue.isEmpty)
    }

    func testTimeRemainingComesFromEachBooksChaptersStillToNarrate() async throws {
        // 120 words a minute, generated at half speed: one second per word.
        shelf.listenEstimator = { ListenEstimator(calibratedWordsPerMinute: ["af_heart": 120], realTimeFactor: 2) }
        let long = try draft("Long", chapters: 4, extraWords: 300)
        let short = try draft("Short", chapters: 3, extraWords: 100)
        func words(_ chapters: ArraySlice<BookChapter>) -> Double {
            Double(chapters.reduce(0) { $0 + ListenEstimator.wordCount($1.text) })
        }

        XCTAssertEqual(shelf.remainingGenerationTime(for: long.id), words(long.chapters[...]), accuracy: 0.001)
        XCTAssertEqual(shelf.remainingGenerationTime(for: short.id), words(short.chapters[...]), accuracy: 0.001)

        shelf.narrate(long.id, useMPS: false)
        shelf.narrate(short.id, useMPS: false)
        generator.release()
        try await waitUntil { self.shelf.narratedCount(of: long) == 1 }

        // The running book counts only what is left; the queued one is untouched.
        let remaining = shelf.remainingGenerationTime(for: long.id)
        XCTAssertEqual(remaining, words(long.chapters[1...]), accuracy: 0.001)
        XCTAssertEqual(shelf.remainingLabel(for: long.id), ListenEstimator.remainingLabel(remaining))
        XCTAssertEqual(shelf.remainingGenerationTime(for: short.id), words(short.chapters[...]), accuracy: 0.001)
        XCTAssertNotEqual(shelf.remainingLabel(for: long.id), shelf.remainingLabel(for: short.id))
    }

    // MARK: - Completion notification

    func testACompletionNotifiesOnlyWhenAttenIsNotFrontmost() async {
        var isFrontmost = true
        var authorizations = 0
        var delivered: [(String, UUID)] = []
        let notifier = NarrationNotifier()
        notifier.isAppFrontmost = { isFrontmost }
        notifier.authorize = { authorizations += 1; return true }
        notifier.deliver = { delivered.append(($0, $1)) }
        let bookID = UUID()

        XCTAssertNil(notifier.narrationFinished(bookID: bookID, title: "Frontmost"))
        XCTAssertEqual(authorizations, 0, "Permission is not asked for while there is nothing to send")
        XCTAssertTrue(delivered.isEmpty)

        isFrontmost = false
        await notifier.narrationFinished(bookID: bookID, title: "Away")?.value
        XCTAssertEqual(authorizations, 1)
        XCTAssertEqual(delivered.map(\.0), ["Away"])
        XCTAssertEqual(delivered.map(\.1), [bookID])
    }

    func testACompletionIsNotDeliveredWithoutPermission() async {
        var delivered = 0
        let notifier = NarrationNotifier()
        notifier.isAppFrontmost = { false }
        notifier.authorize = { false }
        notifier.deliver = { _, _ in delivered += 1 }

        await notifier.narrationFinished(bookID: UUID(), title: "Denied")?.value
        XCTAssertEqual(delivered, 0)
    }

    // MARK: - Helpers

    private func draft(_ title: String, chapters: Int = 1, extraWords: Int = 0) throws -> BookRecord {
        let parts = (1...chapters).map {
            DocumentChapter(
                title: "\(title) \($0)",
                text: "\(title) chapter \($0) is read aloud." + String(repeating: " word", count: extraWords)
            )
        }
        return try shelf.saveDraft(
            title: title,
            text: parts.map(\.text).joined(separator: "\n"),
            voiceID: "af_heart",
            defaults: AppSettings(outputDirectory: directories.defaultExports.path, defaultFormat: .wav, selectedVoiceID: "af_heart"),
            chapters: parts
        )
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<500 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting")
    }
}

/// Holds every chapter until the test lets it through, so a test can act
/// while a narration is partway through a chapter.
final class GatedGenerator: TTSGenerating, @unchecked Sendable {
    private let inner = ImmediateGenerator()
    private let lock = NSLock()
    private var permits = 0
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var startedTexts: [String] = []

    /// The text of every chapter the engine was asked for, in order.
    var started: [String] { lock.withLock { startedTexts } }

    func generate(_ request: GenerationRequest) async throws -> GenerationOutput {
        try await inner.generate(request)
    }

    func generateStream(_ request: GenerationRequest) -> AsyncThrowingStream<GenerationEvent, Error> {
        lock.withLock { startedTexts.append(request.text) }
        return AsyncThrowingStream { continuation in
            let task = Task {
                await self.wait()
                do {
                    for try await event in self.inner.generateStream(request) { continuation.yield(event) }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { termination in
                if case .cancelled = termination { task.cancel() }
            }
        }
    }

    func cancel() {
        let released = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            defer { waiters = [] }
            return waiters
        }
        released.forEach { $0.resume() }
    }

    /// Lets one chapter through.
    func release() {
        let waiter = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            if waiters.isEmpty { permits += 1; return nil }
            return waiters.removeFirst()
        }
        waiter?.resume()
    }

    /// Lets every chapter through from now on.
    func open() {
        lock.withLock { isOpen = true }
        cancel()
    }

    private func wait() async {
        await withCheckedContinuation { continuation in
            let passes = lock.withLock { () -> Bool in
                if isOpen { return true }
                if permits > 0 { permits -= 1; return true }
                waiters.append(continuation)
                return false
            }
            if passes { continuation.resume() }
        }
    }
}
