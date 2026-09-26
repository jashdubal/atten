import AttenCore
import Foundation
import XCTest
@testable import Atten

final class ModelDownloadFailureTests: XCTestCase {
    /// What `cli.py --download-model` actually prints when a download stops.
    func testTheBackendsWordingBecomesOneShortLine() {
        let cases: [(String, ModelDownloadFailure)] = [
            ("Download failed: [Errno 28] No space left on device", .diskFull),
            ("Download failed: HTTP Error 404: Not Found", .notFound),
            ("Download failed: No files found for Hugging Face repository facebook/mms-tts-xyz", .notFound),
            ("Download failed: HTTP Error 401: Unauthorized", .needsAccess),
            ("Download failed: HTTP Error 403: Forbidden", .needsAccess),
            ("Download failed: <urlopen error [Errno 8] nodename nor servname provided, or not known>", .offline),
            ("Download failed: <urlopen error timed out>", .offline),
            ("Download failed: [Errno 54] Connection reset by peer", .offline),
            (
                "Download failed: facebook/mms-tts-jpn did not download completely; 1 file(s) could not be "
                    + "fetched, starting with model.safetensors. Try the download again — the parts already "
                    + "on disk are kept and resumed.",
                .other
            ),
        ]
        for (message, expected) in cases {
            XCTAssertEqual(ModelDownloadFailure(BackendError.processFailed(message)), expected, message)
        }
        XCTAssertEqual(ModelDownloadFailure(BackendError.backendNotFound), .engineMissing)
    }

    func testNoFailureShowsARawErrorOrAParagraph() {
        let all: [ModelDownloadFailure] = [.offline, .diskFull, .notFound, .needsAccess, .engineMissing, .other]
        for failure in all {
            XCTAssertLessThanOrEqual(failure.message.count, 32, failure.message)
            XCTAssertFalse(failure.message.contains("Errno"), failure.message)
            XCTAssertFalse(failure.message.contains("HTTP"), failure.message)
            XCTAssertFalse(failure.message.contains("."), failure.message)
        }
    }
}

@MainActor
final class ModelDownloadStateTests: XCTestCase {
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent("AttenModelStates-\(UUID().uuidString)")
    private var suite: String!
    private var model: AppModel!
    private var library: ModelLibrary!
    private let modelID = "facebook/mms-tts-jpn"

    /// Stands in for `ProcessModelDownloader`: no process, no network.
    private struct StubDownloader: ModelDownloading {
        let run: @Sendable (String) async throws -> Void
        func download(_ modelID: String, progress: @escaping @Sendable (ModelDownloadProgress) -> Void) async throws {
            try await run(modelID)
        }
        func stop(_ modelID: String) {}
    }

    private var store: ModelStore { ModelStore(root: root.appendingPathComponent("models", isDirectory: true)) }

    private func makeModel(_ run: @escaping @Sendable (String) async throws -> Void) throws {
        suite = "AttenModelStatesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        library = ModelLibrary(
            store: store,
            downloader: StubDownloader(run: run),
            sizeCacheURL: root.appendingPathComponent("sizes.json")
        )
        model = AppModel(
            directories: AppDirectories(applicationSupport: root),
            settingsStore: SettingsStore(defaults: defaults),
            generator: ImmediateGenerator(),
            library: library
        )
        model.locateBackend = { true }
        model.selectVoice(try XCTUnwrap(VoiceCatalog.voice(id: "jf_alpha")))
        model.createFlow.startWriting()
        model.createFlow.text = "Hello there."
    }

    override func tearDown() async throws {
        VoiceCatalog.setInstalledModels([])
        if let suite { UserDefaults().removePersistentDomain(forName: suite) }
        try? FileManager.default.removeItem(at: root)
    }

    private func waitForDownloadToSettle() async throws {
        for _ in 0..<300 where library.downloads[modelID]?.phase == .downloading {
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func testAFinishedDownloadMakesItsVoicesUsableWithoutARelaunch() async throws {
        let directory = store.directory(for: modelID)
        try makeModel { _ in
            // What the backend leaves behind: the files and its marker.
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("{}".utf8).write(to: directory.appendingPathComponent("config.json"))
            try Data("complete\n".utf8).write(to: directory.appendingPathComponent(".atten_complete"))
        }
        XCTAssertEqual(model.createFlow.generateDisabledReason, "Voice needs download")
        XCTAssertEqual(library.needsDownloadLabel(for: modelID), "Needs download")

        library.download(modelID)
        XCTAssertEqual(library.needsDownloadLabel(for: modelID), "Downloading")
        try await waitForDownloadToSettle()

        XCTAssertNil(library.downloads[modelID])
        XCTAssertNil(model.requiredModelID(for: "jf_alpha"))
        XCTAssertNil(model.requiredModelID(for: "jm_kaito"), "every voice on the model is ready")
        XCTAssertNil(model.createFlow.generateDisabledReason)
        XCTAssertTrue(model.createFlow.canGenerate)
    }

    func testAnOfflineDownloadSaysSoAndCanBeRetried() async throws {
        try makeModel { _ in
            throw BackendError.processFailed(
                "Download failed: <urlopen error [Errno 8] nodename nor servname provided, or not known>"
            )
        }
        library.download(modelID)
        try await waitForDownloadToSettle()

        XCTAssertEqual(library.downloads[modelID]?.phase, .failed(.offline))
        XCTAssertEqual(library.needsDownloadLabel(for: modelID), "No internet connection")
        XCTAssertEqual(model.createFlow.generateDisabledReason, "Voice needs download")

        library.download(modelID)
        XCTAssertEqual(library.downloads[modelID]?.phase, .downloading, "Retry starts the download again")
        try await waitForDownloadToSettle()
    }

    func testProgressReadsAsOneLine() {
        var state = ModelLibrary.DownloadState(
            phase: .downloading,
            progress: ModelDownloadProgress(status: "Connecting to Hugging Face…")
        )
        XCTAssertEqual(ModelDownloadStatus.summary(of: state), "Connecting…")

        state.progress = ModelDownloadProgress(
            percent: 42, status: "Downloading model.safetensors (2/5)", speed: "3.1 MB/s",
            eta: "52s", sizeText: "122.0 MB / 290.0 MB"
        )
        XCTAssertEqual(ModelDownloadStatus.summary(of: state), "42% · 122.0 MB / 290.0 MB · 3.1 MB/s · 52s left")

        state.phase = .paused
        state.progress.speed = ""
        state.progress.eta = ""
        XCTAssertEqual(ModelDownloadStatus.summary(of: state), "Paused · 42% · 122.0 MB / 290.0 MB")
    }
}
