import AttenCore
import Foundation
import XCTest
@testable import Atten

/// A thousand books on one shelf: loading it, filtering, searching and sorting
/// it, and what drawing it costs per card. Prints a `STRESS |` table.
@MainActor
final class LargeLibraryStressTests: XCTestCase {
    /// The shelf remembers its last filtered, sorted answer; any change to a
    /// book, and any recount of the files behind them, must be seen.
    func testTheRememberedShelfFollowsEveryChange() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AttenShelfCache-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let directories = AppDirectories(applicationSupport: root)
        try directories.prepare()
        let books = try StressFixtures.library(count: 6, chapters: 2, wordsPerChapter: 5, narratedEvery: 2, in: directories)
        try await BookLibraryStore(fileURL: directories.booksFile).save(books)
        let shelf = BookshelfModel(directories: directories, generator: ImmediateGenerator())
        await shelf.load()

        XCTAssertEqual(shelf.books(for: .audiobooks, sort: .title).count, 3)
        XCTAssertEqual(shelf.books(for: .all, query: "renamed", sort: .title), [])

        // An in-place edit of one book.
        let draft = try XCTUnwrap(shelf.books.first { $0.audioPath == nil })
        try shelf.saveDraft(id: draft.id, title: "Renamed", text: "Words.", voiceID: "af_heart",
                            defaults: AppSettings(outputDirectory: root.path))
        XCTAssertEqual(shelf.books(for: .all, query: "renamed", sort: .title).map(\.id), [draft.id])

        // A recording deleted behind Atten's back, noticed on the next recount.
        let narrated = try XCTUnwrap(shelf.books.first { $0.audioPath != nil })
        try FileManager.default.removeItem(at: XCTUnwrap(narrated.audioURL))
        shelf.refreshNarrationCounts()
        XCTAssertEqual(shelf.books(for: .audiobooks, sort: .title).count, 2)
        XCTAssertEqual(shelf.narratedCount(of: narrated), 0)

        shelf.remove(draft.id)
        XCTAssertEqual(shelf.books(for: .all, query: "renamed", sort: .title), [])
    }

    func testACachedCoverSeedIsTheSeed() {
        for key in ["", "abc", UUID().uuidString, String(repeating: "f", count: 64)] {
            XCTAssertEqual(CoverSeed.cached(contentHash: key), CoverSeed(contentHash: key))
            XCTAssertEqual(CoverSeed.cached(contentHash: key), CoverSeed(contentHash: key))
        }
    }

    func testAThousandBookShelfLoadsFiltersAndDrawsWithinBudget() async throws {
        try StressFixtures.skipUnlessEnabled()
        let root = try StressFixtures.dataDirectory("library")
        defer { try? FileManager.default.removeItem(at: root) }
        let directories = AppDirectories(applicationSupport: root)
        try directories.prepare()

        let books = try StressFixtures.library(count: 1_000, chapters: 30, wordsPerChapter: 300, narratedEvery: 5, in: directories)
        try await BookLibraryStore(fileURL: directories.booksFile).save(books)
        let size = (try FileManager.default.attributesOfItem(atPath: directories.booksFile.path)[.size] as? Int) ?? 0
        StressFixtures.report("fixture: books.json", 0, "\(size / 1_048_576) MB, \(books.count) books")

        let (decoded, decodeTime) = try await StressFixtures.time {
            try await BookLibraryStore(fileURL: directories.booksFile).load()
        }
        XCTAssertEqual(decoded.count, 1_000)
        StressFixtures.report("BookLibraryStore.load", decodeTime)

        let shelf = BookshelfModel(directories: directories, generator: ImmediateGenerator())
        let (_, loadTime) = await StressFixtures.time { await shelf.load() }
        XCTAssertEqual(shelf.books.count, 1_000)
        XCTAssertNil(shelf.errorMessage)
        StressFixtures.report("BookshelfModel.load (with audio checks)", loadTime)

        let (_, saveTime) = try await StressFixtures.time { try await BookLibraryStore(fileURL: directories.booksFile).save(shelf.books) }
        StressFixtures.report("BookLibraryStore.save", saveTime)

        let (items, adaptTime) = StressFixtures.time {
            shelf.books.map(AttenCore.LibraryItem.book).map { ($0, $0.state, $0.isListening) }
        }
        XCTAssertEqual(items.count, 1_000)
        StressFixtures.report("LibraryItem adapter + state (1,000)", adaptTime)

        var filterTimes: [String: Double] = [:]
        for filter in AttenCore.LibraryItemFilter.allCases {
            let (result, seconds) = StressFixtures.time { shelf.filteredBooks(for: filter) }
            filterTimes[filter.rawValue] = seconds
            StressFixtures.report("filter .\(filter.rawValue)", seconds, "\(result.count) books")
        }
        let (hits, searchTime) = StressFixtures.time { shelf.filteredBooks(for: .all, query: "chapter 30") }
        XCTAssertEqual(hits.count, 1_000)
        StressFixtures.report("search \"chapter 30\" (matches every book)", searchTime)
        let (misses, missTime) = StressFixtures.time { shelf.filteredBooks(for: .all, query: "zzzz") }
        XCTAssertTrue(misses.isEmpty)
        StressFixtures.report("search \"zzzz\" (matches nothing)", missTime)
        for sort in LibrarySort.allCases {
            let (_, seconds) = StressFixtures.time { shelf.books(for: .all, sort: sort) }
            StressFixtures.report("sort \(sort.rawValue)", seconds)
        }

        let (_, countTime) = StressFixtures.time { shelf.refreshNarrationCounts() }
        StressFixtures.report("refreshNarrationCounts (main actor)", countTime)

        // One evaluation of the Library body: it asks for the visible books
        // twice (is it empty, then the grid) and looks for the hero's book.
        let (_, bodyTime) = StressFixtures.time {
            for _ in 0..<2 { _ = shelf.books(for: .all, query: "cycle", sort: .author) }
            _ = shelf.books.filter { $0.lastListenedAt != nil }.max { ($0.lastListenedAt ?? .distantPast) < ($1.lastListenedAt ?? .distantPast) }
        }
        StressFixtures.report("Library body: search + author sort, as drawn", bodyTime)
        let (_, repeatTime) = StressFixtures.time {
            for _ in 0..<2 { _ = shelf.books(for: .all, query: "cycle", sort: .author) }
        }
        StressFixtures.report("Library body again, shelf unchanged", repeatTime)

        let seeds = shelf.books.map { AttenCore.LibraryItem.book($0).coverSeedKey }
        let (_, seedTime) = StressFixtures.time { for key in seeds { _ = CoverSeed(contentHash: key) } }
        StressFixtures.report("CoverSeed, 1,000 covers, computed", seedTime)
        for key in seeds { _ = CoverSeed.cached(contentHash: key) }
        let (_, cachedSeedTime) = StressFixtures.time { for key in seeds { _ = CoverSeed.cached(contentHash: key) } }
        StressFixtures.report("CoverSeed, 1,000 covers, cached", cachedSeedTime)

        // What the shelf's body evaluates for each card it draws: the seed a
        // generated cover is drawn from (twice: the art and its shadow tint),
        // and the state that decides its colour and its badge.
        let (_, cardTime) = StressFixtures.time {
            for book in shelf.books {
                let item = AttenCore.LibraryItem.book(book)
                _ = CoverSeed.cached(contentHash: item.coverSeedKey)
                _ = CoverSeed.cached(contentHash: item.coverSeedKey).hue
                _ = item.state
                _ = book.hasBookAudio && !book.needsPreparation
                _ = book.sourceExists
                _ = shelf.narratedCount(of: book)
            }
        }
        StressFixtures.report("per-card work, all 1,000 cards", cardTime)

        // Budgets for an interactive shelf, with room for a slow CI runner.
        XCTAssertLessThan(loadTime, 10)
        XCTAssertLessThan(searchTime, 0.25)
        XCTAssertLessThan(countTime, 0.25)
        XCTAssertLessThan(filterTimes.values.max() ?? 0, 0.25)
        XCTAssertLessThan(cardTime, 0.25)
        XCTAssertLessThan(repeatTime, 0.01)
    }

    /// Bytes written per minute of playback. A position was saved every 5 s
    /// by rewriting all of `books.json`; now it goes to `positions.json`,
    /// written at most once per 5 s, and `books.json` is left alone.
    func testAMinuteOfPlaybackWritesPositionsNotTheLibrary() async throws {
        try StressFixtures.skipUnlessEnabled()
        let root = try StressFixtures.dataDirectory("positions")
        defer { try? FileManager.default.removeItem(at: root) }
        let directories = AppDirectories(applicationSupport: root)
        try directories.prepare()
        let books = try StressFixtures.library(count: 1_000, chapters: 30, wordsPerChapter: 300, narratedEvery: 5, in: directories)
        let library = BookLibraryStore(fileURL: directories.booksFile)
        try await library.save(books)
        let saves = Int(60 / ListeningPositionStore.minimumInterval)

        // Before: each save rewrote the whole shelf.
        var before = 0
        let (_, beforeTime) = try await StressFixtures.time {
            for _ in 0..<saves {
                try await library.save(books)
                before += (try FileManager.default.attributesOfItem(atPath: directories.booksFile.path)[.size] as? Int) ?? 0
            }
        }
        StressFixtures.report("before: books.json × \(saves) per minute", beforeTime, "\(before / 1_024) KB/min")

        // After, with one book ever listened to and then with all thousand.
        let clock = ManualClock()
        let shelf = BookshelfModel(directories: directories, generator: ImmediateGenerator(), positionClock: clock.clock)
        await shelf.load()
        let booksJSON = try Data(contentsOf: directories.booksFile)
        let playing = try XCTUnwrap(shelf.books.first { $0.hasBookAudio })
        var results: [Int] = []
        for listened in [1, 1_000] {
            for book in shelf.books.prefix(listened) { shelf.saveListeningPosition(1, for: book.id) }
            try await shelf.flushPersistence()
            let (startBytes, startWrites) = (await shelf.positions.bytesWritten, await shelf.positions.writeCount)
            let (_, afterTime) = try await StressFixtures.time {
                for tick in 1...saves {
                    clock.advance(by: ListeningPositionStore.minimumInterval)
                    shelf.saveListeningPosition(Double(tick * 5), for: playing.id)
                    try await shelf.flushPersistence()
                }
            }
            let bytes = await shelf.positions.bytesWritten - startBytes
            let writes = await shelf.positions.writeCount - startWrites
            XCTAssertEqual(writes, saves)
            results.append(bytes)
            StressFixtures.report("after: positions.json, \(listened) book(s) listened", afterTime, "\(bytes) B/min in \(writes) writes")
        }
        XCTAssertEqual(try Data(contentsOf: directories.booksFile), booksJSON, "Playback never rewrote books.json")
        StressFixtures.report("reduction, worst case", 0, String(format: "%.0f×", Double(before) / Double(max(1, results.max() ?? 1))))
        XCTAssertLessThan(results.max() ?? .max, before / 50)
    }
}
