import Foundation
import XCTest
@testable import AttenCore

/// Atten is meant to keep working for decades on a machine nobody maintains.
/// These cover the state it writes today still being readable — and never being
/// destroyed — by an Atten that runs much later, under files that users, disks,
/// and other versions have had every chance to damage.
final class DurabilityTests: XCTestCase {
    private var directory = URL(fileURLWithPath: "/tmp")

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttenDurability-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private var projectsFile: URL { directory.appendingPathComponent("projects.json") }

    private func quarantinedFiles() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.contains("unreadable") }
    }

    // MARK: - Project history

    func testUnreadableHistoryIsPreservedRatherThanOverwritten() async throws {
        try Data("this is not json at all".utf8).write(to: projectsFile)
        let repository = ProjectRepository(fileURL: projectsFile)

        let loaded = try await repository.load()
        try await repository.save([Self.record(title: "After the damage")])

        XCTAssertEqual(loaded, [])
        let quarantined = try quarantinedFiles()
        XCTAssertEqual(quarantined.count, 1)
        XCTAssertEqual(
            try String(contentsOf: XCTUnwrap(quarantined.first), encoding: .utf8),
            "this is not json at all"
        )
        let reloaded = try await repository.load()
        XCTAssertEqual(reloaded.map(\.title), ["After the damage"])
    }

    func testOneDamagedRecordDoesNotDiscardTheRestOfTheHistory() async throws {
        // The array still parses, but one entry is nonsense — a hand edit, or a
        // record a future version wrote in a shape this one cannot use.
        let json = """
        [
          {"audioPath": "/tmp/one.wav", "title": "One"},
          "not a record at all",
          {"audioPath": "/tmp/three.wav", "title": "Three"}
        ]
        """
        try Data(json.utf8).write(to: projectsFile)

        let salvaged = try await ProjectRepository(fileURL: projectsFile).load()

        XCTAssertEqual(salvaged.map(\.title), ["One", "Three"])
        XCTAssertEqual(try quarantinedFiles().count, 1)
    }

    func testHistoryTruncatedByACrashIsKeptForRecovery() async throws {
        let repository = ProjectRepository(fileURL: projectsFile)
        try await repository.save([Self.record(title: "First"), Self.record(title: "Second")])
        // A write cut short by a crash or a full disk leaves invalid JSON, which
        // nothing can salvage — but the bytes must survive for the user.
        let text = try String(contentsOf: projectsFile, encoding: .utf8)
        try Data(text.dropLast(60).utf8).write(to: projectsFile)

        let loaded = try await ProjectRepository(fileURL: projectsFile).load()

        XCTAssertEqual(loaded, [])
        let quarantined = try XCTUnwrap(quarantinedFiles().first)
        XCTAssertTrue(try String(contentsOf: quarantined, encoding: .utf8).contains("First"))
    }

    func testHistoryWrittenByAnotherVersionStillLoads() async throws {
        // Fields this version adds are missing, and fields a later version adds
        // are present and unknown. Neither may cost the user their history.
        let json = """
        [{
          "audioPath": "/tmp/from-the-future.wav",
          "title": "Chapter one",
          "narrationStyle": "whispered",
          "chapters": [{"start": 0.0}]
        }]
        """
        try Data(json.utf8).write(to: projectsFile)

        let loaded = try await ProjectRepository(fileURL: projectsFile).load()

        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.title, "Chapter one")
        XCTAssertEqual(loaded.first?.format, .wav)
        XCTAssertEqual(loaded.first?.voiceID, "af_heart")
        XCTAssertEqual(try quarantinedFiles(), [])
    }

    func testHistoryIsNeverReplacedBeforeItHasBeenRead() async throws {
        try Data("[]".utf8).write(to: projectsFile)
        // A repository that was never asked to load still must not clobber the
        // file that is already there.
        let repository = ProjectRepository(fileURL: projectsFile)

        try await repository.save([Self.record(title: "Fresh")])

        XCTAssertEqual(try quarantinedFiles().count, 1)
    }

    // MARK: - Settings

    func testSettingsWrittenByAnotherVersionKeepWhatStillApplies() throws {
        let json = """
        {
          "outputDirectory": "/tmp/exports",
          "appearance": "midnight",
          "defaultFormat": "opus",
          "defaultSpeed": 1.4,
          "selectedVoiceID": "bf_emma",
          "spatialAudio": true
        }
        """

        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))

        // Unknown enum cases fall back; everything understood is kept.
        XCTAssertEqual(settings.appearance, .system)
        XCTAssertEqual(settings.defaultFormat, .mp3)
        XCTAssertEqual(settings.defaultSpeed, 1.4)
        XCTAssertEqual(settings.selectedVoiceID, "bf_emma")
        XCTAssertEqual(settings.outputDirectory, "/tmp/exports")
        XCTAssertTrue(settings.checksForUpdates)
    }

    func testSettingsFromTheFirstReleaseStillLoad() throws {
        let json = """
        {"outputDirectory": "/tmp/exports"}
        """

        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))

        XCTAssertEqual(settings.selectedVoiceID, "af_heart")
        XCTAssertEqual(settings.defaultSpeed, 1.0)
        XCTAssertTrue(settings.useMPS)
    }

    // MARK: - Voices

    func testCatalogAlwaysOffersAVoice() {
        XCTAssertFalse(VoiceCatalog.all.isEmpty)
        XCTAssertFalse(VoiceCatalog.defaultVoice.id.isEmpty)
    }

    private static func record(title: String) -> ProjectRecord {
        ProjectRecord(
            title: title,
            text: "Body text.",
            voiceID: "af_heart",
            speed: 1,
            format: .wav,
            audioPath: "/tmp/\(title).wav"
        )
    }
}
