import AttenCore
import Foundation
import XCTest
@testable import Atten

private final class ImmediateGenerator: TTSGenerating, @unchecked Sendable {
    func generate(_ request: GenerationRequest) async throws -> GenerationOutput {
        try FileManager.default.createDirectory(
            at: request.outputDirectory,
            withIntermediateDirectories: true
        )
        let url = request.outputDirectory
            .appendingPathComponent(request.filename)
            .appendingPathExtension(request.format.rawValue)
        try silentWAV().write(to: url)
        return GenerationOutput(url: url, segmentCount: 1, sampleRate: 24_000)
    }

    func cancel() {}

    private func silentWAV() -> Data {
        let sampleCount: UInt32 = 2_400
        let dataSize = sampleCount * 2
        var data = Data()
        data.append(contentsOf: "RIFF".utf8)
        append(36 + dataSize, to: &data)
        data.append(contentsOf: "WAVEfmt ".utf8)
        append(UInt32(16), to: &data)
        append(UInt16(1), to: &data)
        append(UInt16(1), to: &data)
        append(UInt32(24_000), to: &data)
        append(UInt32(48_000), to: &data)
        append(UInt16(2), to: &data)
        append(UInt16(16), to: &data)
        data.append(contentsOf: "data".utf8)
        append(dataSize, to: &data)
        data.append(Data(count: Int(dataSize)))
        return data
    }

    private func append<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }
}

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
