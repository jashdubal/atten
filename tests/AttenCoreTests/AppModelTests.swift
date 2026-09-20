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

        fixture.model.play(tracks: [
            PlaybackTrack(url: first, title: "One", subtitle: "A book"),
            PlaybackTrack(url: second, title: "Two", subtitle: "A book"),
        ])
        XCTAssertEqual(fixture.model.activeAudioURL, first)
        XCTAssertEqual(fixture.model.playerTitle, "One")
        XCTAssertFalse(fixture.model.queue.hasPrevious)

        for _ in 0..<100 {
            if fixture.model.activeAudioURL == second { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(fixture.model.activeAudioURL, second)
        // The chapter just left is still behind it, so the player can go back.
        XCTAssertTrue(fixture.model.queue.hasPrevious)
        XCTAssertFalse(fixture.model.queue.hasNext)
    }

    /// Playing one chapter out of a book keeps the rest of the book, so the
    /// player can move either way through it.
    func testPlayingOneTrackOfAQueueKeepsTheQueue() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let generator = ImmediateGenerator()
        let first = try await generator.generate(chapter: "one", in: fixture.directory)
        let second = try await generator.generate(chapter: "two", in: fixture.directory)
        let tracks = [
            PlaybackTrack(url: first, title: "One"),
            PlaybackTrack(url: second, title: "Two"),
        ]

        fixture.model.play(tracks: tracks)
        fixture.model.togglePlayback(track: tracks[1])

        XCTAssertEqual(fixture.model.activeAudioURL, second)
        XCTAssertTrue(fixture.model.queue.hasPrevious)

        fixture.model.playPrevious()

        XCTAssertEqual(fixture.model.activeAudioURL, first)
    }

    /// Ten seconds back from the first second of a chapter is the chapter
    /// before it, not a player that refuses to move.
    func testSkippingPastEitherEndMovesToTheNeighbouringTrack() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let generator = ImmediateGenerator()
        let first = try await generator.generate(chapter: "one", in: fixture.directory)
        let second = try await generator.generate(chapter: "two", in: fixture.directory)
        let tracks = [
            PlaybackTrack(url: first, title: "One"),
            PlaybackTrack(url: second, title: "Two"),
        ]

        fixture.model.play(tracks: tracks)
        fixture.model.skip(by: 30)

        XCTAssertEqual(fixture.model.activeAudioURL, second)

        fixture.model.skip(by: -30)

        XCTAssertEqual(fixture.model.activeAudioURL, first)
    }

    /// Listening speed is a preference, so it survives the next thing played.
    func testListeningSpeedIsRememberedAcrossTracks() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let url = try await ImmediateGenerator().generate(chapter: "one", in: fixture.directory)

        fixture.model.play(tracks: [PlaybackTrack(url: url, title: "One")])
        fixture.model.setPlaybackRate(1.5)
        fixture.model.play(tracks: [PlaybackTrack(url: url, title: "Again")])

        XCTAssertEqual(fixture.model.playbackRate, 1.5)
        XCTAssertEqual(fixture.model.settings.playbackRate, 1.5)
    }

    /// Two significant digits turned 1.25 into "1.2" and 1.75 into "1.8", so
    /// the speed menu offered two settings that looked like neighbours of the
    /// ones it actually had.
    func testListeningSpeedsAreWrittenOutInFull() {
        XCTAssertEqual(PlayerBar.rateText(0.75), "0.75×")
        XCTAssertEqual(PlayerBar.rateText(1.0), "1×")
        XCTAssertEqual(PlayerBar.rateText(1.25), "1.25×")
        XCTAssertEqual(PlayerBar.rateText(1.75), "1.75×")
        XCTAssertEqual(PlayerBar.rateText(2.0), "2×")
        XCTAssertEqual(
            Set(PlayerBar.rates.map(PlayerBar.rateText)).count,
            PlayerBar.rates.count,
            "Every speed in the menu should be distinguishable from the others"
        )
    }

    /// Elapsed and remaining sit either side of the same scrubber, so they have
    /// to be measuring the same thing.
    func testElapsedAndRemainingAddUpToTheWholeChapter() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let url = try await ImmediateGenerator().generate(chapter: "one", in: fixture.directory)

        fixture.model.play(tracks: [PlaybackTrack(url: url, title: "One")])
        fixture.model.setPlaybackRate(2.0)
        fixture.model.seek(to: fixture.model.playbackDuration / 2)

        XCTAssertEqual(
            fixture.model.playbackPosition + fixture.model.playbackRemaining,
            fixture.model.playbackDuration,
            accuracy: 0.01
        )
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
