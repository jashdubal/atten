import AVFoundation
import AttenCore
import Foundation
import XCTest
@testable import Atten

/// A library on a disk that fills up: a 20 MB disk image mounted in a
/// temporary folder, which is always detached again. Narration and export
/// must fail with a clear message, keep their checkpoints, and leave no
/// partial files.
@MainActor
final class LowDiskStressTests: XCTestCase {
    private var scratch: URL!
    private var volume: URL!

    override func setUp() async throws {
        try StressFixtures.skipUnlessEnabled()
        scratch = try StressFixtures.dataDirectory("lowdisk")
        volume = scratch.appendingPathComponent("volume", isDirectory: true)
        try FileManager.default.createDirectory(at: volume, withIntermediateDirectories: true)
        let image = scratch.appendingPathComponent("full.dmg")
        try hdiutil(["create", "-size", "20m", "-fs", "HFS+", "-volname", "AttenLowDisk", image.path])
        try hdiutil(["attach", image.path, "-mountpoint", volume.path, "-nobrowse", "-noverify", "-noautoopen"])
    }

    override func tearDown() async throws {
        guard let scratch else { return }
        try? hdiutil(["detach", volume.path, "-force"])
        try? FileManager.default.removeItem(at: scratch)
    }

    private func hdiutil(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown) }
    }

    /// Takes up all but about `leaving` bytes of the volume.
    @discardableResult
    private func fill(leaving: Int) throws -> URL {
        let filler = volume.appendingPathComponent("filler")
        FileManager.default.createFile(atPath: filler.path, contents: nil)
        let handle = try FileHandle(forWritingTo: filler)
        let chunk = Data(count: 256 * 1_024)
        while (try? handle.write(contentsOf: chunk)) != nil {}
        let size = try handle.offset()
        try handle.truncate(atOffset: max(0, size - UInt64(leaving)))
        try handle.close()
        return filler
    }

    /// Files under `url`, hidden ones included, as paths relative to it.
    private func files(under url: URL) -> [String] {
        let base = url.resolvingSymlinksInPath().path
        let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey])
        return (enumerator?.allObjects as? [URL] ?? [])
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            .map { String($0.resolvingSymlinksInPath().path.dropFirst(base.count + 1)) }
            .sorted()
    }

    func testANarrationThatRunsOutOfDiskKeepsItsChaptersAndFinishesOnceThereIsRoom() async throws {
        let directories = AppDirectories(applicationSupport: volume.appendingPathComponent("Atten"))
        try directories.prepare()
        let book = BookRecord(title: "Four chapters", format: .document,
                              sourcePath: directories.bookSources.appendingPathComponent("book.txt").path,
                              chapters: (1...4).map { BookChapter(title: "Part \($0)", text: "Chapter \($0).") },
                              voiceID: "af_heart", speed: 1, audioFormat: .wav)
        try await BookLibraryStore(fileURL: directories.booksFile).save([book])
        // Four chapters of a megabyte and a half fit; combining them into one
        // more file of the same size does not while the filler is there.
        let filler = volume.appendingPathComponent("filler")
        try Data(count: 8 * 1_048_576).write(to: filler)
        let generator = SizedGenerator(seconds: 32)
        let shelf = BookshelfModel(directories: directories, generator: generator)
        await shelf.load()

        shelf.narrate(book.id, useMPS: false)
        try await waitUntil { !shelf.isNarrating }

        let failed = try XCTUnwrap(shelf.book(id: book.id))
        XCTAssertEqual(failed.narrationState, .failed)
        let message = try XCTUnwrap(failed.narrationFailure)
        XCTAssertTrue(message.localizedCaseInsensitiveContains("space"), message)
        XCTAssertEqual(failed.narratedCount, 4, "every chapter checkpoint is kept")
        XCTAssertFalse(failed.hasBookAudio)
        let folder = directories.narrations.appendingPathComponent(book.id.uuidString)
        let leftovers = files(under: folder)
        XCTAssertEqual(leftovers.filter { !$0.hasPrefix("chapter-") }, [], "no partial audiobook")
        XCTAssertEqual(leftovers.count, 8, "four chapters and their timings")
        let saved = try await BookLibraryStore(fileURL: directories.booksFile).load()
        XCTAssertEqual(saved.first?.narratedCount, 4)

        try FileManager.default.removeItem(at: filler)
        shelf.narrate(book.id, useMPS: false)
        try await waitUntil { !shelf.isNarrating }

        let finished = try XCTUnwrap(shelf.book(id: book.id))
        XCTAssertEqual(finished.narrationState, .ready)
        XCTAssertTrue(finished.hasBookAudio)
        XCTAssertEqual(generator.calls, 4, "the checkpoints were not generated again")
    }

    func testExportsToAFullDiskFailAndLeaveNothingBehind() async throws {
        let source = scratch.appendingPathComponent("Audiobook.caf")
        try StressFixtures.noiseWAV(seconds: 300).write(to: source)
        try fill(leaving: 64 * 1_024)
        let before = files(under: volume)

        let volume = volume!
        let exports: [(String, @MainActor @Sendable () async throws -> Void)] = [
            ("wav", { try await WAVAudioExport.export(source, to: volume.appendingPathComponent("Book.wav")) }),
            ("m4a", { try await BookAudioExport.export(source, to: volume.appendingPathComponent("Book.m4a")) }),
            ("copy", { _ = try ExportService().copyAudio(from: source, to: volume.appendingPathComponent("Book.caf")) }),
        ]
        for (name, export) in exports {
            let outcome = await within(.seconds(60), export)
            switch outcome {
            case .none: XCTFail("\(name) export to a full disk never finished")
            case .some(.success):
                let written = volume.appendingPathComponent("Book.\(name == "copy" ? "caf" : name)")
                let size = (try? FileManager.default.attributesOfItem(atPath: written.path)[.size] as? Int) ?? -1
                let seconds = (try? AVAudioFile(forReading: written)).map { Double($0.length) / $0.processingFormat.sampleRate } ?? -1
                XCTFail("\(name) export to a full disk succeeded: \(size) bytes, \(seconds) s")
            case .some(.failure(let error)): StressFixtures.report("\(name) export to a full disk", 0, error.localizedDescription)
            }
            XCTAssertEqual(files(under: volume), before, "\(name) export left a file behind")
        }
    }

    /// Runs `body`, answering nil if it has not finished in `limit` — a hung
    /// export is the failure being looked for, so it must not hang the test.
    private func within(
        _ limit: Duration,
        _ body: @escaping @MainActor @Sendable () async throws -> Void
    ) async -> Result<Void, Error>? {
        var outcome: Result<Void, Error>?
        let task = Task { @MainActor in
            do { try await body(); outcome = .success(()) } catch { outcome = .failure(error) }
        }
        let deadline = ContinuousClock.now + limit
        while outcome == nil, ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(50)) }
        if outcome == nil { task.cancel() }
        return outcome
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(60)
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(condition(), "Timed out")
    }
}

/// Writes a chapter of `seconds` of silence wherever the engine would have.
private final class SizedGenerator: TTSGenerating, @unchecked Sendable {
    private let seconds: Double
    private let lock = NSLock()
    private var count = 0
    var calls: Int { lock.withLock { count } }

    init(seconds: Double) { self.seconds = seconds }

    func generate(_ request: GenerationRequest) async throws -> GenerationOutput {
        lock.withLock { count += 1 }
        try FileManager.default.createDirectory(at: request.outputDirectory, withIntermediateDirectories: true)
        let url = request.outputDirectory.appendingPathComponent(request.filename).appendingPathExtension("wav")
        try StressFixtures.silentWAV(seconds: seconds).write(to: url)
        return GenerationOutput(url: url, segmentCount: 1, sampleRate: 24_000)
    }

    func generateStream(_ request: GenerationRequest) -> AsyncThrowingStream<GenerationEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    continuation.yield(.completed(try await self.generate(request).url))
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
        }
    }

    func cancel() {}
}

/// The quick half of the above: a failed write is blamed on the disk only
/// when the disk really is (all but) full.
final class DiskSpaceTests: XCTestCase {
    func testAFailedWriteIsBlamedOnTheDiskOnlyWhenItIsFull() {
        let failure = NSError(domain: "com.apple.coreaudio.avfaudio", code: -40)
        let directory = FileManager.default.temporaryDirectory

        let full = DiskSpace.explain(failure, writingTo: directory, margin: .max)
        XCTAssertEqual((full as? CocoaError)?.code, .fileWriteOutOfSpace)
        XCTAssertTrue(full.localizedDescription.contains("space"), full.localizedDescription)

        let roomy = DiskSpace.explain(failure, writingTo: directory, margin: 0) as NSError
        XCTAssertEqual(roomy.code, -40)
    }
}
