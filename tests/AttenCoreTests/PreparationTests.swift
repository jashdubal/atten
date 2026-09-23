import AttenCore
import AVFoundation
import XCTest
@testable import Atten

@MainActor
final class PreparationTests: XCTestCase {
    private var root: URL!
    private var directories: AppDirectories!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        directories = AppDirectories(applicationSupport: root)
        try directories.prepare()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func seed() async throws -> BookRecord {
        let book = BookRecord(title: "A book", format: .document, sourcePath: "/missing.txt",
            chapters: [BookChapter(title: "One", text: "one"), BookChapter(title: "Two", text: "two")],
            voiceID: "af_heart", speed: 1, audioFormat: .wav)
        try await BookLibraryStore(fileURL: directories.booksFile).save([book])
        return book
    }

    private func finish(_ shelf: BookshelfModel) async throws {
        for _ in 0..<300 {
            if !shelf.isNarrating { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Preparation did not finish")
    }

    func testFailedSecondChapterResumesFromCheckpointAfterRelaunch() async throws {
        let book = try await seed()
        let generator = CheckpointGenerator()
        let shelf = BookshelfModel(directories: directories, generator: generator)
        await shelf.load()
        shelf.narrate(book.id, useMPS: false)
        try await finish(shelf)
        XCTAssertEqual(shelf.book(id: book.id)?.narratedCount, 1)
        XCTAssertEqual(shelf.book(id: book.id)?.narrationState, .failed)
        let reopened = BookshelfModel(directories: directories, generator: ImmediateGenerator())
        await reopened.load()
        XCTAssertFalse(reopened.isNarrating)
        let checkpoint = try XCTUnwrap(reopened.book(id: book.id)?.chapters.first?.audioURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: checkpoint.path))
        reopened.narrate(book.id, useMPS: false)
        try await finish(reopened)
        XCTAssertTrue(try XCTUnwrap(reopened.book(id: book.id)).hasBookAudio)
        XCTAssertEqual(reopened.book(id: book.id)?.narrationState, .ready)
    }

    func testCancellationKeepsLeaseUntilTaskUnwindsAndPreservesCheckpoint() async throws {
        let book = try await seed()
        let coordinator = SynthesisCoordinator()
        let generator = CheckpointGenerator(waitOnSecond: true)
        let shelf = BookshelfModel(directories: directories, generator: generator, synthesis: coordinator)
        await shelf.load()
        shelf.narrate(book.id, useMPS: false)
        for _ in 0..<200 {
            if await generator.calls >= 2 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        shelf.cancelNarration()
        XCTAssertNil(coordinator.acquire("Competing preview"))
        try await finish(shelf)
        XCTAssertFalse(coordinator.isBusy)
        XCTAssertEqual(shelf.book(id: book.id)?.narratedCount, 1)
        XCTAssertEqual(shelf.book(id: book.id)?.narrationState, .interrupted)
    }

    func testCreateCannotStartWhileBookPreparationOwnsEngine() async throws {
        let book = try await seed()
        let generator = CheckpointGenerator(waitOnSecond: true)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "AttenTest.\(UUID().uuidString)"))
        let model = AppModel(directories: directories, settingsStore: SettingsStore(defaults: defaults), generator: generator)
        await model.bookshelf.load()
        model.bookshelf.narrate(book.id, useMPS: false)
        model.draftText = "A competing narration"
        model.generate()
        model.previewVoice(VoiceCatalog.defaultVoice)
        model.generatePlaygroundSample(text: "sample", voiceID: "af_heart", speed: 1, format: .wav, useMPS: false)
        XCTAssertFalse(model.isGenerating)
        XCTAssertFalse(model.isPlaygroundGenerating)
        XCTAssertNil(model.voicePreviewID)
        model.bookshelf.cancelNarration()
        try await finish(model.bookshelf)
    }

    func testListeningPositionRestoresPausedIndependentlyOfReadingPosition() async throws {
        let book = try await seed()
        let shelf = BookshelfModel(directories: directories, generator: ImmediateGenerator())
        await shelf.load()
        shelf.narrate(book.id, useMPS: false)
        try await finish(shelf)
        shelf.saveListeningPosition(0.05, for: book.id)
        try await shelf.flushPersistence()
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "AttenTest.\(UUID().uuidString)"))
        let store = SettingsStore(defaults: defaults)
        var settings = store.load(defaultOutputDirectory: directories.defaultExports)
        settings.checksForUpdates = false
        try store.save(settings)
        let model = AppModel(directories: directories, settingsStore: store, generator: ImmediateGenerator())
        await model.start()
        XCTAssertFalse(model.isPlaying)
        XCTAssertEqual(model.playingBook?.id, book.id)
        XCTAssertEqual(model.playbackPosition, 0.05, accuracy: 0.001)
        XCTAssertNil(model.bookshelf.book(id: book.id)?.lastLocation)
    }

    func testCreatingDraftAndAudioKeepsExistingBookInPlayer() async throws {
        let book = try await seed()
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "AttenTest.\(UUID().uuidString)"))
        let model = AppModel(directories: directories, settingsStore: SettingsStore(defaults: defaults), generator: ImmediateGenerator())
        await model.bookshelf.load()
        model.bookshelf.narrate(book.id, useMPS: false)
        try await finish(model.bookshelf)
        let ready = try XCTUnwrap(model.bookshelf.book(id: book.id))
        model.listen(to: ready)
        model.newDraft()
        XCTAssertEqual(model.activeAudioURL, ready.audioURL)
        model.draftText = "A new narration"
        model.generate()
        for _ in 0..<200 {
            if !model.isGenerating { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNotNil(model.currentAudioURL)
        XCTAssertEqual(model.activeAudioURL, ready.audioURL)
        model.pause()
        try await model.bookshelf.flushPersistence()
    }

    func testReplacementKeepsLoadedRecordingUntilPlayerSwitches() async throws {
        let book = try await seed()
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "AttenTest.\(UUID().uuidString)"))
        let model = AppModel(directories: directories, settingsStore: SettingsStore(defaults: defaults), generator: ImmediateGenerator())
        await model.bookshelf.load()
        model.bookshelf.narrate(book.id, useMPS: false)
        try await finish(model.bookshelf)
        let first = try XCTUnwrap(model.bookshelf.book(id: book.id))
        model.listen(to: first)
        model.pause()
        model.bookshelf.updateVoice("bf_emma", for: book.id)
        model.bookshelf.narrate(book.id, useMPS: false)
        try await finish(model.bookshelf)
        let replacement = try XCTUnwrap(model.bookshelf.book(id: book.id))
        XCTAssertEqual(model.playingBook?.audioURL, first.audioURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(first.audioURL).path))
        XCTAssertNotEqual(replacement.audioURL, first.audioURL)
        model.listen(to: replacement)
        model.pause()
        XCTAssertEqual(model.activeAudioURL, replacement.audioURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(first.audioURL).path))
        try await model.bookshelf.flushPersistence()
    }

    func testCorruptedAudioBecomesRepairableAfterReload() async throws {
        let book = try await seed()
        let shelf = BookshelfModel(directories: directories, generator: ImmediateGenerator())
        await shelf.load()
        shelf.narrate(book.id, useMPS: false)
        try await finish(shelf)
        let url = try XCTUnwrap(shelf.book(id: book.id)?.audioURL)
        try Data("broken audio".utf8).write(to: url)
        let reopened = BookshelfModel(directories: directories, generator: ImmediateGenerator())
        await reopened.load()
        let repaired = try XCTUnwrap(reopened.book(id: book.id))
        XCTAssertFalse(repaired.hasBookAudio)
        XCTAssertEqual(repaired.narratedCount, 0)
        XCTAssertEqual(repaired.narrationState, .failed)
    }

    func testAssemblyFailureKeepsAllCheckpointsForRetry() async throws {
        let book = try await seed()
        let shelf = BookshelfModel(directories: directories, generator: ImmediateGenerator(), assembler: { _, _ in
            throw CocoaError(.fileWriteOutOfSpace)
        })
        await shelf.load()
        shelf.narrate(book.id, useMPS: false)
        try await finish(shelf)
        let failed = try XCTUnwrap(shelf.book(id: book.id))
        XCTAssertEqual(failed.narrationState, .failed)
        XCTAssertEqual(failed.narratedCount, 2)
        XCTAssertNil(failed.audioPath)
        XCTAssertFalse(shelf.synthesis.isBusy)
        try await shelf.flushPersistence()
        let reopened = BookshelfModel(directories: directories, generator: ImmediateGenerator())
        await reopened.load()
        reopened.narrate(book.id, useMPS: false)
        try await finish(reopened)
        XCTAssertTrue(try XCTUnwrap(reopened.book(id: book.id)).hasBookAudio)
    }

    func testCancellationDuringFinalizationPreservesAllChapters() async throws {
        let book = try await seed()
        let shelf = BookshelfModel(directories: directories, generator: ImmediateGenerator(), assembler: { _, _ in
            while !Task.isCancelled { Thread.sleep(forTimeInterval: 0.005) }
            throw CancellationError()
        })
        await shelf.load()
        shelf.narrate(book.id, useMPS: false)
        for _ in 0..<200 {
            if shelf.progress?.isCombining == true { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(shelf.progress?.isCombining, true)
        shelf.cancelNarration()
        try await finish(shelf)
        XCTAssertEqual(shelf.book(id: book.id)?.narrationState, .interrupted)
        XCTAssertEqual(shelf.book(id: book.id)?.narratedCount, 2)
        XCTAssertFalse(shelf.synthesis.isBusy)
    }

    func testFailedMetadataCommitPreservesPreviousRecordingAndCheckpoints() async throws {
        let book = try await seed()
        let initial = BookshelfModel(directories: directories, generator: ImmediateGenerator())
        await initial.load()
        initial.narrate(book.id, useMPS: false)
        try await finish(initial)
        let previousURL = try XCTUnwrap(initial.book(id: book.id)?.audioURL)
        let file = directories.booksFile
        let backup = root.appendingPathComponent("saved-books.json")
        let replacement = BookshelfModel(directories: directories, generator: ImmediateGenerator(), assembler: { urls, directory in
            let result = try BookAudioAssembler.assemble(urls, in: directory)
            // Refuse the metadata commit after successful encoding.
            try FileManager.default.moveItem(at: file, to: backup)
            try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
            return result
        })
        await replacement.load()
        replacement.updateVoice("bf_emma", for: book.id)
        replacement.narrate(book.id, useMPS: false)
        try await finish(replacement)
        let failed = try XCTUnwrap(replacement.book(id: book.id))
        XCTAssertEqual(failed.narrationState, .failed)
        XCTAssertEqual(failed.audioURL, previousURL)
        XCTAssertTrue(failed.hasBookAudio)
        XCTAssertTrue(failed.needsPreparation)
        XCTAssertEqual(failed.narratedCount, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: previousURL.path))
        let recordings = try FileManager.default.contentsOfDirectory(at: previousURL.deletingLastPathComponent(), includingPropertiesForKeys: nil)
        XCTAssertEqual(recordings.filter { $0.pathExtension == "caf" }.map { $0.resolvingSymlinksInPath() }, [previousURL.resolvingSymlinksInPath()])
    }

    func testExportProducesPlayableM4AAndFailedExportPreservesDestination() async throws {
        let source = try await ImmediateGenerator().generate(chapter: "audio", in: root)
        let destination = root.appendingPathComponent("export.m4a")
        try await BookAudioExport.export(source, to: destination)
        let audio = try AVAudioFile(forReading: destination)
        XCTAssertGreaterThan(audio.length, 0)
        let before = try Data(contentsOf: destination)
        do {
            try await BookAudioExport.export(root.appendingPathComponent("missing.caf"), to: destination)
            XCTFail("Missing source exported successfully")
        } catch {}
        XCTAssertEqual(try Data(contentsOf: destination), before)
    }

    func testDamagedLibraryIsPreservedBeforeSavingSalvage() async throws {
        let original = Data("[{broken".utf8)
        try original.write(to: directories.booksFile)
        let store = BookLibraryStore(fileURL: directories.booksFile)
        let loaded = try await store.load()
        XCTAssertTrue(loaded.isEmpty)
        let backup = await store.recoveredFileURL
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(backup)), original)
        try await store.save([])
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(backup)), original)
    }

    func testInterruptedStateDecodesWithoutRestartAndLegacyRoutesMapToWorkspaces() throws {
        var book = BookRecord(title: "Book", format: .document, sourcePath: "/source", chapters: [], voiceID: "af_heart", speed: 1, audioFormat: .wav)
        book.narrationState = .finalizing
        let decoded = try JSONDecoder().decode(BookRecord.self, from: JSONEncoder().encode(book))
        XCTAssertEqual(decoded.narrationState, .interrupted)
        XCTAssertEqual(SidebarItem.restored("home"), .library)
        XCTAssertEqual(SidebarItem.restored("unknown"), .library)
        XCTAssertEqual(SidebarItem.restored("projects").workspace, .studio)
    }
}

private actor CheckpointGenerator: TTSGenerating {
    private(set) var calls = 0
    let waitOnSecond: Bool
    init(waitOnSecond: Bool = false) { self.waitOnSecond = waitOnSecond }
    nonisolated func cancel() {}
    func generate(_ request: GenerationRequest) async throws -> GenerationOutput {
        calls += 1
        if calls == 2 {
            if waitOnSecond { try await Task.sleep(for: .seconds(30)) }
            throw BackendError.processFailed("Test interruption")
        }
        return try await ImmediateGenerator().generate(request)
    }
}
