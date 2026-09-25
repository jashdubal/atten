import AttenCore
import AttenFixtureKit
import Darwin
import Foundation
import XCTest

/// Builds the large inputs the stress tests run against — a thousand-book
/// shelf, thousand-page books — in a scratch `ATTEN_DATA_DIRECTORY`, so none
/// of it is committed and none of it goes near a real library.
enum StressFixtures {
    /// Whether the slow, large-input tests should run. They build hundreds of
    /// megabytes of fixtures, so they are opt-in.
    static var isEnabled: Bool { ProcessInfo.processInfo.environment["ATTEN_STRESS_TESTS"] == "1" }

    static func skipUnlessEnabled() throws {
        guard isEnabled else { throw XCTSkip("Set ATTEN_STRESS_TESTS=1 to run the large-input stress tests") }
    }

    static func dataDirectory(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttenStress-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - Text

    /// Deterministic prose: `count` words in sentences of about a dozen.
    static func words(_ count: Int, seed: Int) -> String { FixtureBuilders.words(count, seed: seed) }

    // MARK: - A large shelf

    /// A shelf of `count` books, one in `narratedEvery` of them with a short
    /// recording on disk whose chapter timeline matches it, so loading the
    /// shelf has real audio to check.
    static func library(
        count: Int,
        chapters: Int,
        wordsPerChapter: Int,
        narratedEvery: Int,
        in directories: AppDirectories
    ) throws -> [BookRecord] {
        let chapterSeconds = 0.1
        let wav = silentWAV(seconds: chapterSeconds * Double(chapters))
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        return try (0..<count).map { index in
            let id = UUID()
            var book = BookRecord(
                id: id,
                title: "Volume \(index) of the \(FixtureBuilders.vocabulary[index % FixtureBuilders.vocabulary.count]) cycle",
                author: index % 7 == 0 ? nil : "Author \(index % 97)",
                format: [.epub, .pdf, .document, .mobi][index % 4],
                sourcePath: directories.bookSources.appendingPathComponent("\(id.uuidString).txt").path,
                chapters: (0..<chapters).map { chapter in
                    BookChapter(title: "Chapter \(chapter + 1)", text: words(wordsPerChapter, seed: index * 1_000 + chapter))
                },
                voiceID: "af_heart",
                speed: 1,
                audioFormat: .wav,
                addedAt: base.addingTimeInterval(Double(index) * 60),
                contentHash: index % 3 == 0 ? nil : String(format: "%064x", index)
            )
            if index % narratedEvery == 0 {
                let folder = directories.narrations
                    .appendingPathComponent(id.uuidString, isDirectory: true)
                    .appendingPathComponent("Audiobook-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let audio = folder.appendingPathComponent("Audiobook.caf")
                try wav.write(to: audio)
                book.audioPath = audio.path
                book.narrationState = .ready
                for chapter in book.chapters.indices {
                    book.chapters[chapter].audioPath = audio.path
                    book.chapters[chapter].startTime = Double(chapter) * chapterSeconds
                    book.chapters[chapter].endTime = Double(chapter + 1) * chapterSeconds
                }
                if index % (narratedEvery * 2) == 0 {
                    book.listeningPosition = 0.5
                    book.lastListenedAt = base.addingTimeInterval(Double(index))
                }
            }
            return book
        }
    }

    /// Sixteen-bit mono silence at 24 kHz.
    static func silentWAV(seconds: Double) -> Data { FixtureBuilders.silentWAV(seconds: seconds) }

    /// Quiet noise, which an encoder cannot squeeze to nearly nothing the way
    /// it can silence.
    static func noiseWAV(seconds: Double) -> Data { FixtureBuilders.noiseWAV(seconds: seconds) }

    // MARK: - Long books

    /// An EPUB of `pages` pages of about 300 words, split across `files` spine
    /// documents full of the entities real books use. One file makes the
    /// whole book a single document; `wellFormed: false` sends every file
    /// down the tag-stripping fallback.
    static func epub(pages: Int, files: Int, wellFormed: Bool = true, in directory: URL) throws -> URL {
        try FixtureBuilders.epub(pages: pages, files: files, wellFormed: wellFormed, in: directory)
    }

    /// A PDF of `pages` pages of about 300 words, with a top-level outline
    /// entry every `pagesPerChapter` pages when that is given.
    static func pdf(pages: Int, pagesPerChapter: Int?, in directory: URL) throws -> URL {
        try FixtureBuilders.pdf(pages: pages, pagesPerChapter: pagesPerChapter, in: directory)
    }

    // MARK: - Measuring

    /// Wall-clock seconds `body` took, and what it returned.
    static func time<T>(_ body: () throws -> T) rethrows -> (T, Double) {
        let start = ContinuousClock.now
        let value = try body()
        let elapsed = ContinuousClock.now - start
        return (value, Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18)
    }

    /// The stress tests run on the main actor, and so does what they time.
    @MainActor
    static func time<T>(_ body: @MainActor () async throws -> T) async rethrows -> (T, Double) {
        let start = ContinuousClock.now
        let value = try await body()
        let elapsed = ContinuousClock.now - start
        return (value, Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18)
    }

    /// The process's physical footprint in megabytes — what Activity Monitor
    /// calls its memory.
    static func footprintMB() -> Double {
        var usage = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &usage) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(getpid(), RUSAGE_INFO_V4, $0)
            }
        }
        return result == 0 ? Double(usage.ri_phys_footprint) / 1_048_576 : 0
    }


    /// One line of the table the stress tests print, prefixed so it can be
    /// grepped out of `swift test` output.
    static func report(_ label: String, _ seconds: Double, _ detail: String = "") {
        let padded = label.padding(toLength: 52, withPad: " ", startingAt: 0)
        print("STRESS | \(padded) | " + String(format: "%9.1f ms", seconds * 1_000) + " | \(detail)")
    }
}

/// Samples the footprint every few milliseconds on its own thread, so the
/// high-water mark of one operation can be read without the process-lifetime
/// peak that `getrusage` reports.
final class FootprintSampler: @unchecked Sendable {
    private let lock = NSLock()
    private var peak = StressFixtures.footprintMB()
    private var running = true

    init() {
        Thread.detachNewThread { [self] in
            while lock.withLock({ running }) {
                let now = StressFixtures.footprintMB()
                lock.withLock { peak = max(peak, now) }
                usleep(5_000)
            }
        }
    }

    /// Stops sampling and answers the highest footprint seen, in megabytes.
    func stop() -> Double {
        lock.withLock {
            running = false
            return max(peak, StressFixtures.footprintMB())
        }
    }
}
