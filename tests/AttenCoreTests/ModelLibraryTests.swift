import Foundation
import XCTest
@testable import AttenCore

final class ModelLibraryTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("atten-models-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testDownloadableSizeSkipsMediaDuplicatesAndExtraQuantizations() {
        let files: [(String, Int64)] = [
            ("config.json", 10),
            ("model.safetensors", 1_000),
            ("model.bin", 1_000),
            ("samples/demo.wav", 500),
            ("tts-Q4_K_M.gguf", 300),
            ("tts-Q8_0.gguf", 600),
        ]
        XCTAssertEqual(HuggingFaceCatalog.downloadableByteCount(of: files), 1_310)
    }

    func testCompatibilityFilterKeepsSupportedArchitecturesOnly() {
        XCTAssertTrue(HuggingFaceCatalog.isCompatible(id: "facebook/mms-tts-ara", tags: []))
        XCTAssertTrue(HuggingFaceCatalog.isCompatible(id: "someone/custom", tags: ["vits"]))
        XCTAssertFalse(HuggingFaceCatalog.isCompatible(id: "Qwen/Qwen-TTS", tags: ["vits"]))
        XCTAssertFalse(HuggingFaceCatalog.isCompatible(id: "someone/custom", tags: ["whisper"]))
    }

    func testLanguageSearchQueriesEveryISOCode() {
        let urls = HuggingFaceCatalog.queryURLs(query: "", language: "Arabic", sort: .mostStars)
        XCTAssertEqual(urls.count, 9)
        XCTAssertTrue(urls.allSatisfy { $0.absoluteString.contains("sort=likes") })
    }

    func testStoreIgnoresPartialDownloadsAndFindsCompleteOnes() throws {
        let store = ModelStore(root: root)
        let complete = store.directory(for: "facebook/mms-tts-ara")
        let partial = store.directory(for: "facebook/mms-tts-deu")
        try FileManager.default.createDirectory(at: complete, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: partial, withIntermediateDirectories: true)
        try Data("complete".utf8).write(to: complete.appendingPathComponent(".atten_complete"))
        try Data(count: 10).write(to: partial.appendingPathComponent(".model.safetensors.part"))

        XCTAssertEqual(store.installedModels().map(\.id), ["facebook/mms-tts-ara"])
        XCTAssertTrue(store.isInstalled("facebook/mms-tts-ara"))
        XCTAssertFalse(store.isInstalled("facebook/mms-tts-deu"))
        XCTAssertEqual(store.installedModels().first?.languages, "Arabic")

        try store.delete("facebook/mms-tts-ara")
        XCTAssertFalse(store.isInstalled("facebook/mms-tts-ara"))
        XCTAssertThrowsError(try store.delete(ModelStore.kokoroID))
    }

    func testDownloadedModelContributesVoiceThatCarriesItsModel() {
        let model = InstalledModel(
            id: "facebook/mms-tts-ara", name: "mms-tts-ara", languages: "Arabic", byteCount: 1
        )
        VoiceCatalog.setInstalledModels([model])
        defer { VoiceCatalog.setInstalledModels([]) }

        let voice = VoiceCatalog.voice(id: "dyn_facebook_mms_tts_ara")
        XCTAssertEqual(voice?.modelID, "facebook/mms-tts-ara")
        XCTAssertEqual(voice?.language, "Arabic")
        XCTAssertEqual(VoiceCatalog.all.count, VoiceCatalog.bundled.count + 1)
    }

    func testSettingsFromEarlierVersionsStillDecode() throws {
        let legacy = """
        {"appearance":"dark","outputDirectory":"/tmp","defaultFormat":"wav","defaultSpeed":1.2,
         "selectedVoiceID":"bf_emma","favoriteVoiceIDs":["af_heart"],"useMPS":false}
        """
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(legacy.utf8))
        XCTAssertEqual(settings.selectedVoiceID, "bf_emma")
        XCTAssertEqual(settings.pendingDownloadModelIDs, [])
    }

    func testSizeCachePersistsAcrossInstances() async {
        let url = root.appendingPathComponent("sizes.json")
        await ModelSizeCache(fileURL: url).store(42, for: "a/b")
        let reloaded = await ModelSizeCache(fileURL: url).byteCount(for: "a/b")
        XCTAssertEqual(reloaded, 42)
    }
}
