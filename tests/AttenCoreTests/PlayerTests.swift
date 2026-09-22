import AttenCore
import Foundation
import XCTest
@testable import Atten

/// Playback moved out of a bar pinned under every screen and into one compact
/// control in the top chrome, with the rest behind an expand affordance. The
/// queue, the rate and the system media commands underneath are unchanged —
/// these cover the promise that there is still exactly one of them.
@MainActor
final class PlayerTests: XCTestCase {

    /// The expanded panel's queue list jumps by replaying the queue it is
    /// already showing. That must move the same queue rather than starting a
    /// second one beside it.
    func testJumpingToAQueueRowKeepsOneQueue() async throws {
        let model = try makeModel()
        let tracks = try await makeTracks(count: 3)

        model.play(tracks: tracks, startingAt: 0)
        XCTAssertEqual(model.queue.tracks.count, 3)

        model.play(tracks: model.queue.tracks, startingAt: 2)

        XCTAssertEqual(model.queue.tracks.count, 3, "jumping built a second queue")
        XCTAssertEqual(model.queue.index, 2)
        XCTAssertEqual(model.playerTitle, tracks[2].title)
        XCTAssertFalse(model.queue.hasNext)
        XCTAssertTrue(model.queue.hasPrevious)
    }

    /// Closing from the expanded panel has to leave nothing playing and
    /// nothing drawn — the compact player keys off `playerTitle`.
    func testClosingThePlayerLeavesNothingToDraw() async throws {
        let model = try makeModel()
        model.play(tracks: try await makeTracks(count: 2), startingAt: 0)
        XCTAssertNotNil(model.playerTitle)

        model.closePlayer()

        XCTAssertNil(model.playerTitle)
        XCTAssertFalse(model.isPlaying)
        XCTAssertTrue(model.queue.isEmpty)
    }

    /// With nothing playing there is no player at all, which is what keeps a
    /// reader with no narration from losing a strip of page to empty chrome.
    func testNothingPlayingMeansNoPlayer() throws {
        let model = try makeModel()

        XCTAssertNil(model.playerTitle)
        XCTAssertTrue(model.queue.isEmpty)
    }

    /// A one-off render — a Studio result, a voice preview — has a queue of
    /// one, and the panel hides its chapter list rather than showing a list
    /// of one thing.
    func testAOneOffRenderHasNoQueuePositionToShow() async throws {
        let model = try makeModel()

        model.play(tracks: try await makeTracks(count: 1), startingAt: 0)

        XCTAssertNil(model.queue.position, "a queue of one should not claim to be 1 of 1")
        XCTAssertEqual(model.queue.tracks.count, 1)
        XCTAssertFalse(model.queue.hasNext)
        XCTAssertFalse(model.queue.hasPrevious)
    }

    /// A Studio file carries its project record into the shared player, so
    /// Now Playing does not fall back to a generated filename or pretend it is
    /// a book chapter.
    func testStudioAudioKeepsProjectMetadata() async throws {
        let model = try makeModel()
        let tracks = try await makeTracks(count: 1)
        let url = tracks[0].url
        let project = ProjectRecord(
            title: "A studio take",
            text: "A short script",
            voiceID: "af_heart",
            speed: 1,
            format: .wav,
            audioPath: url.path
        )
        model.projects = [project]

        model.togglePlayback(url: url)

        XCTAssertEqual(model.playerTitle, "A studio take")
        XCTAssertEqual(model.playingProject?.id, project.id)
        XCTAssertNil(model.playingBook)
    }

    /// A book being listened to straight through does say where it is.
    func testABookSaysWhichChapterOfHowMany() async throws {
        let model = try makeModel()

        model.play(tracks: try await makeTracks(count: 16), startingAt: 2)

        XCTAssertEqual(model.queue.position, "3 of 16")
    }

    /// Rate is one setting for the whole player, set from the expanded panel
    /// and kept across tracks, and it is clamped on the way back in so a
    /// stored zero cannot look like a player that has silently stopped.
    func testRateIsOneSettingAndIsHeldInsideItsRange() async throws {
        let model = try makeModel()
        model.play(tracks: try await makeTracks(count: 2), startingAt: 0)

        model.setPlaybackRate(1.75)
        XCTAssertEqual(model.playbackRate, 1.75)

        model.playNext()
        XCTAssertEqual(model.playbackRate, 1.75, "rate did not survive a chapter change")

        XCTAssertTrue(
            PlaybackFormat.rates.allSatisfy { (0.5...3.0).contains($0) },
            "a rate is offered that the settings clamp would reject"
        )
    }

    /// Every rate the panel offers has to read as a different number, or the
    /// picker shows the same label twice.
    func testEveryOfferedRateReadsDifferently() {
        XCTAssertEqual(
            Set(PlaybackFormat.rates.map(PlaybackFormat.rateText)).count,
            PlaybackFormat.rates.count
        )
    }

    func testTimesAreWrittenForTheLengthTheyAre() {
        XCTAssertEqual(PlaybackFormat.timeText(0), "0:00")
        XCTAssertEqual(PlaybackFormat.timeText(61), "1:01")
        XCTAssertEqual(PlaybackFormat.timeText(3_661), "1:01:01")
        // A duration that has not been read off the file yet must not render
        // as a crash or as a wild number.
        XCTAssertEqual(PlaybackFormat.timeText(.infinity), "0:00")
        XCTAssertEqual(PlaybackFormat.timeText(-5), "0:00")
    }

    // MARK: -

    /// Real (if silent) WAVs: an unplayable file is dropped by the player and
    /// the queue empties, which is correct behaviour and useless for testing
    /// the queue.
    private func makeTracks(count: Int) async throws -> [PlaybackTrack] {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttenPlayerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let generator = ImmediateGenerator()
        var tracks: [PlaybackTrack] = []
        for index in 0..<count {
            let url = try await generator.generate(chapter: "chapter-\(index)", in: directory)
            tracks.append(
                PlaybackTrack(url: url, title: "Chapter \(index + 1)", subtitle: "A Book")
            )
        }
        return tracks
    }

    private func makeModel() throws -> AppModel {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttenPlayerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "AttenPlayerTests.\(UUID().uuidString)"))
        return AppModel(
            directories: AppDirectories(
                applicationSupport: directory.appendingPathComponent("Application Support")
            ),
            settingsStore: SettingsStore(defaults: defaults),
            generator: ImmediateGenerator()
        )
    }
}
