@testable import AttenCore
import Foundation
import XCTest
@testable import Atten

/// Truncated and garbage state files: whatever is still valid is salvaged,
/// the damaged original is copied aside as `.corrupt`, and nothing is written
/// over it before that copy exists.
@MainActor
final class CorruptDataTests: XCTestCase {
    private var root: URL!
    private var directories: AppDirectories!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("AttenCorrupt-\(UUID().uuidString)")
        directories = AppDirectories(applicationSupport: root)
        try directories.prepare()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func books(_ count: Int) -> [BookRecord] {
        (0..<count).map { index in
            BookRecord(title: "Book \(index)", format: .document, sourcePath: "/tmp/book-\(index).txt",
                       chapters: [BookChapter(title: "One", text: "Text with \"quotes\", [brackets] and {braces} \(index).")],
                       voiceID: "af_heart", speed: 1, audioFormat: .wav)
        }
    }

    private func backups(of file: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: file.deletingLastPathComponent(), includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix(file.lastPathComponent) && $0.pathExtension == "corrupt" }
    }

    // MARK: - books.json

    func testATruncatedShelfKeepsEveryBookItFinishedWriting() async throws {
        let written = books(40)
        try await BookLibraryStore(fileURL: directories.booksFile).save(written)
        let whole = try Data(contentsOf: directories.booksFile)
        let truncated = whole.prefix(whole.count * 7 / 10)
        try truncated.write(to: directories.booksFile)

        let store = BookLibraryStore(fileURL: directories.booksFile)
        let loaded = try await store.load()

        // Before this, a cut-short save lost the whole shelf.
        XCTAssertGreaterThan(loaded.count, 20)
        XCTAssertLessThan(loaded.count, 40)
        XCTAssertEqual(loaded.map(\.id), written.prefix(loaded.count).map(\.id))
        let recovered = await store.recoveredFileURL
        let backup = try XCTUnwrap(recovered)
        XCTAssertEqual(backup.lastPathComponent, "books.json.corrupt")
        XCTAssertEqual(try Data(contentsOf: backup), truncated)
        // Loading wrote nothing over the original.
        XCTAssertEqual(try Data(contentsOf: directories.booksFile), truncated)

        try await store.save(loaded)
        XCTAssertEqual(try Data(contentsOf: backup), truncated)
        let reloaded = try await BookLibraryStore(fileURL: directories.booksFile).load()
        XCTAssertEqual(reloaded.count, loaded.count)
    }

    func testAGarbageShelfOpensEmptyAndSaysWhereTheOriginalIs() async throws {
        let garbage = Data((0..<4_096).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ 7) })
        try garbage.write(to: directories.booksFile)
        let shelf = BookshelfModel(directories: directories, generator: ImmediateGenerator())

        await shelf.load()

        XCTAssertEqual(shelf.books, [])
        let message = try XCTUnwrap(shelf.errorMessage)
        XCTAssertTrue(message.contains("books.json.corrupt"), message)
        XCTAssertEqual(try Data(contentsOf: directories.booksFile.appendingPathExtension("corrupt")), garbage)
    }

    func testLaunchingOverTheSameDamageKeepsOneCopy() async throws {
        try Data("[{\"sourcePath\": \"/tmp/a\"".utf8).write(to: directories.booksFile)
        for _ in 0..<3 { _ = try await BookLibraryStore(fileURL: directories.booksFile).load() }
        XCTAssertEqual(try backups(of: directories.booksFile).count, 1)

        // Different damage is a different file, and the first copy survives it.
        try Data("not json".utf8).write(to: directories.booksFile)
        let store = BookLibraryStore(fileURL: directories.booksFile)
        _ = try await store.load()
        let second = await store.recoveredFileURL
        XCTAssertEqual(second?.lastPathComponent, "books.json.2.corrupt")
        XCTAssertEqual(try backups(of: directories.booksFile).count, 2)
    }

    // MARK: - projects.json

    func testATruncatedHistoryKeepsTheProjectsItFinishedWriting() async throws {
        let projects = (0..<10).map {
            ProjectRecord(title: "Project \($0)", text: "Said [aloud], \"twice\".", voiceID: "af_heart", speed: 1,
                          format: .wav, audioPath: "/tmp/project-\($0).wav")
        }
        let repository = ProjectRepository(fileURL: directories.projectsFile)
        _ = try await repository.load()
        try await repository.save(projects)
        let whole = try Data(contentsOf: directories.projectsFile)
        try whole.prefix(whole.count / 2).write(to: directories.projectsFile)

        let reopened = ProjectRepository(fileURL: directories.projectsFile)
        let loaded = try await reopened.load()

        XCTAssertGreaterThanOrEqual(loaded.count, 4)
        XCTAssertEqual(loaded.map(\.title), projects.prefix(loaded.count).map(\.title))
        let quarantined = await reopened.quarantinedFileURL
        XCTAssertEqual(quarantined?.lastPathComponent, "projects.json.corrupt")
        // The original stays where it was until a save replaces it.
        XCTAssertEqual(try Data(contentsOf: directories.projectsFile), whole.prefix(whole.count / 2))
    }

    // MARK: - queue.json

    func testATruncatedQueueKeepsTheEntriesItFinishedWriting() throws {
        let queue = (0..<5).map { QueuedNarration(bookID: UUID(), useMPS: $0.isMultiple(of: 2)) }
        let file = NarrationQueueFile.url(in: directories)
        try NarrationQueueFile.save(queue, to: file)
        let whole = try Data(contentsOf: file)
        let truncated = whole.prefix(whole.count * 3 / 4)
        try truncated.write(to: file)

        let loaded = NarrationQueueFile.load(from: file)

        XCTAssertGreaterThanOrEqual(loaded.count, 3)
        XCTAssertEqual(loaded, Array(queue.prefix(loaded.count)))
        XCTAssertEqual(try Data(contentsOf: file.appendingPathExtension("corrupt")), truncated)
    }

    // MARK: - timings.json

    func testAGarbageTimingsSidecarIsSetAsideAndTheBookStillAssembles() async throws {
        let generator = ImmediateGenerator()
        let chapters = try await [
            generator.generate(chapter: "one", in: root.appendingPathComponent("chapter-1")),
            generator.generate(chapter: "two", in: root.appendingPathComponent("chapter-2")),
        ]
        try NarrationTimings(segments: [TimedSegment(index: 0, text: "one", start: 0, duration: 0.1, words: [])])
            .save(beside: chapters[0])
        let sidecar = NarrationTimings.sidecarURL(for: chapters[1])
        try Data("{\"segments\": [{\"index\": 0, \"te".utf8).write(to: sidecar)

        XCTAssertNil(try NarrationTimings.load(beside: chapters[1]))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sidecar.appendingPathExtension("corrupt").path))

        // Before, the damaged sidecar failed assembly on every attempt.
        let result = try BookAudioAssembler.assemble(chapters, in: root)
        XCTAssertEqual(result.ranges.count, 2)
        XCTAssertEqual(try NarrationTimings.load(beside: result.url)?.segments.map(\.text), ["one"])
    }

    // MARK: - Salvage

    func testSalvageFindsWholeElementsAndStopsAtTheCut() {
        func salvaged(_ json: String) -> [String] {
            JSONArraySalvage.elements(in: Data(json.utf8)).map { String(decoding: $0, as: UTF8.self) }
        }
        XCTAssertEqual(salvaged(#"[{"a":"]},\"{"}, [1,[2]] ,"x,y", 3]"#), [#"{"a":"]},\"{"}"#, "[1,[2]]", #""x,y""#, "3"])
        XCTAssertEqual(salvaged(#"  [{"a":1},{"b":"#), [#"{"a":1}"#])
        XCTAssertEqual(salvaged(#"[{"a":1}"#), [#"{"a":1}"#])
        XCTAssertEqual(salvaged(#"{"a":1}"#), [])
        XCTAssertEqual(salvaged(""), [])
        XCTAssertEqual(salvaged("[]"), [])
    }
}
