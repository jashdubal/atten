import AttenCore
import Foundation
import XCTest
@testable import Atten

@MainActor
final class AppModelTests: XCTestCase {
    func testPlaygroundSampleIsTemporaryAndNeverCreatesProject() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }

        fixture.model.generatePlaygroundSample(
            text: "A temporary meadow sample.",
            voiceID: "af_heart",
            speed: 1.15,
            format: .wav,
            useMPS: false
        )
        try await waitForPlayground(fixture.model)

        let audioURL = try XCTUnwrap(fixture.model.playgroundAudioURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: audioURL.path))
        XCTAssertTrue(audioURL.path.contains("/Atten/Playground/"))
        XCTAssertTrue(fixture.model.projects.isEmpty)
        XCTAssertEqual(fixture.model.activeAudioURL, audioURL)

        let metadata = AudioFileMetadata(url: audioURL)
        XCTAssertGreaterThan(metadata.byteCount ?? 0, 0)
        XCTAssertEqual(metadata.duration ?? 0, 0.1, accuracy: 0.01)

        fixture.model.clearPlaygroundSample()

        XCTAssertFalse(FileManager.default.fileExists(atPath: audioURL.path))
        XCTAssertNil(fixture.model.playgroundAudioURL)
        XCTAssertNil(fixture.model.activeAudioURL)
    }

    func testProjectDeletionCanKeepOrRemoveAudio() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let keptAudio = fixture.directory.appendingPathComponent("kept.wav")
        let removedAudio = fixture.directory.appendingPathComponent("removed.wav")
        try Data("audio".utf8).write(to: keptAudio)
        try Data("audio".utf8).write(to: removedAudio)
        let keptProject = project(url: keptAudio)
        let removedProject = project(url: removedAudio)
        fixture.model.projects = [keptProject, removedProject]

        fixture.model.delete(keptProject)
        fixture.model.delete(removedProject, includingAudio: true)

        XCTAssertTrue(FileManager.default.fileExists(atPath: keptAudio.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: removedAudio.path))
        XCTAssertTrue(fixture.model.projects.isEmpty)
    }

    private func project(url: URL) -> ProjectRecord {
        ProjectRecord(
            title: url.deletingPathExtension().lastPathComponent,
            text: "Test",
            voiceID: "af_heart",
            speed: 1,
            format: .wav,
            audioPath: url.path
        )
    }

    /// A book is narrated as one file per chapter, so listening straight
    /// through depends on the player moving to the next file by itself.
    func testPlayingASequenceAdvancesToTheNextChapterOnItsOwn() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let generator = ImmediateGenerator()
        let first = try await generator.generate(chapter: "one", in: fixture.directory)
        let second = try await generator.generate(chapter: "two", in: fixture.directory)

        fixture.model.playSequence([first, second])
        XCTAssertEqual(fixture.model.activeAudioURL, first)

        for _ in 0..<100 {
            if fixture.model.activeAudioURL == second { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(fixture.model.activeAudioURL, second)
    }

    private func waitForPlayground(_ model: AppModel) async throws {
        for _ in 0..<50 {
            if model.playgroundAudioURL != nil { return }
            if case let .failed(message) = model.playgroundState {
                XCTFail(message)
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Timed out waiting for the Playground sample")
    }

    private func makeFixture() throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttenTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "AttenTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let directories = AppDirectories(applicationSupport: directory.appendingPathComponent("Application Support"))
        let model = AppModel(
            directories: directories,
            settingsStore: SettingsStore(defaults: defaults),
            generator: ImmediateGenerator()
        )
        return Fixture(model: model, directory: directory, defaults: defaults, suite: suite)
    }
}

@MainActor
private struct Fixture {
    let model: AppModel
    let directory: URL
    let defaults: UserDefaults
    let suite: String

    func cleanUp() {
        model.clearPlaygroundSample()
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }
}
