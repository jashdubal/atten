import Foundation
import XCTest
@testable import AttenCore

final class ExportServiceTests: XCTestCase {
    func testExportCopiesBytesAndDoesNotOverwrite() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.wav")
        let destination = directory.appendingPathComponent("exported/voice.wav")
        try Data("audio".utf8).write(to: source)
        let service = ExportService()

        let output = try service.copyAudio(from: source, to: destination)

        XCTAssertEqual(try Data(contentsOf: output), Data("audio".utf8))
        XCTAssertThrowsError(try service.copyAudio(from: source, to: destination))
    }

    func testFilenameSanitizationRemovesPathCharacters() {
        XCTAssertEqual(ExportService.safeFilename(" river/story:\n take 1 "), "river-story-- take 1")
    }
}
