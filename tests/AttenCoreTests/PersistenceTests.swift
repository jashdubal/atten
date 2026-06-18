import Foundation
import XCTest
@testable import AttenCore

final class PersistenceTests: XCTestCase {
    func testProjectsRoundTripThroughAtomicJSONStore() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = ProjectRepository(fileURL: directory.appendingPathComponent("projects.json"))
        let project = ProjectRecord(
            title: "Forest note",
            text: "Meet me by the river.",
            voiceID: "af_heart",
            speed: 1.1,
            format: .wav,
            audioPath: "/tmp/forest.wav"
        )

        try await repository.save([project])
        let loaded = try await repository.load()

        XCTAssertEqual(loaded, [project])
    }

    func testLegacySettingsMigrateWithoutRemovingOldValues() throws {
        let suite = "AttenTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("bf_emma", forKey: "tts.selectedVoice")
        defaults.set(1.25, forKey: "tts.speed")
        defaults.set("wav", forKey: "tts.outputFormat")
        defaults.set("/tmp/legacy", forKey: "tts.outputDirectory")
        let store = SettingsStore(defaults: defaults)

        let settings = store.load(defaultOutputDirectory: URL(fileURLWithPath: "/tmp/new"))
        try store.save(settings)

        XCTAssertEqual(settings.selectedVoiceID, "bf_emma")
        XCTAssertEqual(settings.defaultSpeed, 1.25)
        XCTAssertEqual(settings.defaultFormat, .wav)
        XCTAssertEqual(settings.outputDirectory, "/tmp/legacy")
        XCTAssertEqual(defaults.string(forKey: "tts.selectedVoice"), "bf_emma")
        XCTAssertNotNil(defaults.data(forKey: SettingsStore.currentKey))
    }

    func testLegacyAudioDiscoveryIgnoresKnownAndUnsupportedFiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let known = directory.appendingPathComponent("known.mp3")
        let fresh = directory.appendingPathComponent("fresh.wav")
        try Data("known".utf8).write(to: known)
        try Data("fresh".utf8).write(to: fresh)
        try Data("skip".utf8).write(to: directory.appendingPathComponent("notes.txt"))
        let existing = ProjectRecord(
            title: "Known", text: "", voiceID: "af_heart", speed: 1,
            format: .mp3, audioPath: known.path
        )

        let imported = LegacyOutputImporter.discover(in: directory, excluding: [existing])

        XCTAssertEqual(imported.count, 1)
        XCTAssertEqual(imported.first?.audioPath, fresh.resolvingSymlinksInPath().path)
        XCTAssertEqual(imported.first?.isLegacyImport, true)
    }
}
