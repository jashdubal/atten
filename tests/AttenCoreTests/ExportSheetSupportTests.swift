import AttenCore
import AVFoundation
import Foundation
import XCTest
@testable import Atten

/// The two encoders `ExportSheet` reaches for besides `BookAudioExport`
/// (already covered by `BookAudioTests`): a linear-PCM `.wav` via
/// AVFoundation, and an `.mp3` via the backend's own `transcode` command.
final class ExportSheetSupportTests: XCTestCase {
    private var workspace: URL!

    override func setUpWithError() throws {
        workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttenExportTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: workspace)
    }

    func testWAVExportProducesAReadableLinearPCMFile() async throws {
        let source = try await ImmediateGenerator().generate(chapter: "One", in: workspace)
        let destination = workspace.appendingPathComponent("exported.wav")

        try await WAVAudioExport.export(source, to: destination)

        let file = try AVAudioFile(forReading: destination)
        XCTAssertGreaterThan(file.length, 0)
        XCTAssertEqual(file.fileFormat.settings[AVFormatIDKey] as? UInt32, kAudioFormatLinearPCM)
    }

    func testWAVExportReplacesAnExistingDestination() async throws {
        let source = try await ImmediateGenerator().generate(chapter: "One", in: workspace)
        let destination = workspace.appendingPathComponent("exported.wav")
        try Data("placeholder".utf8).write(to: destination)

        try await WAVAudioExport.export(source, to: destination)

        XCTAssertGreaterThan(try AVAudioFile(forReading: destination).length, 0)
    }

    func testMP3TranscodeUsesTheDevelopmentBackend() async throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: repoRoot.appendingPathComponent("cli.py").path) else {
            throw XCTSkip("cli.py not found relative to the test bundle")
        }

        let source = try await ImmediateGenerator().generate(chapter: "One", in: workspace)
        let destination = workspace.appendingPathComponent("exported.mp3")

        try await TranscodeService.mp3(from: source, to: destination, installation: .development(root: repoRoot))

        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertGreaterThan(try Data(contentsOf: destination).count, 0)
    }

    func testExportTargetFromABookNeedsFinishedAudio() {
        let silent = BookRecord(
            title: "Silent", format: .document, sourcePath: workspace.appendingPathComponent("s.txt").path,
            chapters: [BookChapter(title: "One", text: "Text")], voiceID: "af_heart", speed: 1, audioFormat: .wav
        )
        XCTAssertNil(ExportTarget(book: silent))
    }

    func testExportTargetFromAProjectAllowsOnlyMP3AndWAV() {
        let project = ProjectRecord(
            title: "A Project", text: "Some text.", voiceID: "af_heart", speed: 1,
            format: .mp3, audioPath: workspace.appendingPathComponent("project.mp3").path
        )
        let target = ExportTarget(project: project)
        XCTAssertFalse(target.allowsM4A)
        XCTAssertEqual(target.sourceURL, project.audioURL)
    }
}
