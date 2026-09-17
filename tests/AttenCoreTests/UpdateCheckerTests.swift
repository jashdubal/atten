import Foundation
import XCTest
@testable import AttenCore

final class UpdateCheckerTests: XCTestCase {
    func testVersionComparison() {
        XCTAssertTrue(UpdateChecker.isVersion("0.2.5", newerThan: "0.2.4"))
        XCTAssertTrue(UpdateChecker.isVersion("0.10.0", newerThan: "0.9.9"))
        XCTAssertTrue(UpdateChecker.isVersion("1.0", newerThan: "0.9.9"))
        XCTAssertFalse(UpdateChecker.isVersion("0.2.4", newerThan: "0.2.4"))
        XCTAssertFalse(UpdateChecker.isVersion("0.2.4", newerThan: "0.3.0"))
        XCTAssertFalse(UpdateChecker.isVersion("0.2", newerThan: "0.2.0"))
    }

    func testParsesReleaseWithDMGAsset() throws {
        let json = """
        {"tag_name":"v0.3.0","body":"Notes","html_url":"https://github.com/jashdubal/atten/releases/tag/v0.3.0",
         "draft":false,"prerelease":false,"assets":[
          {"name":"Atten-macOS-arm64.dmg","browser_download_url":"https://example.com/a.dmg"},
          {"name":"SHA256SUMS.txt","browser_download_url":"https://example.com/sums"}]}
        """
        let release = try XCTUnwrap(UpdateChecker.parseRelease(Data(json.utf8)))
        XCTAssertEqual(release.version, "0.3.0")
        XCTAssertEqual(release.dmgURL.absoluteString, "https://example.com/a.dmg")
        XCTAssertEqual(release.checksumsURL?.absoluteString, "https://example.com/sums")
    }

    func testIgnoresReleaseWithoutDMG() {
        let json = """
        {"tag_name":"v0.3.0","html_url":"https://github.com","draft":false,"prerelease":false,"assets":[]}
        """
        XCTAssertNil(UpdateChecker.parseRelease(Data(json.utf8)))
    }

    func testFindsChecksumForFile() {
        let listing = "abc123  Atten-macOS-arm64.dmg\ndef456  Atten-sbom.spdx.json\n"
        XCTAssertEqual(UpdateChecker.expectedChecksum(for: "Atten-macOS-arm64.dmg", in: listing), "abc123")
        XCTAssertNil(UpdateChecker.expectedChecksum(for: "missing.dmg", in: listing))
    }

    /// An update that cannot speak offline must never replace one that can.
    func testStagedAppIsRejectedUnlessItCarriesItsEngineAndModel() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttenUpdate-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("Atten.app")

        func add(_ relativePath: String) throws {
            let url = app.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("x".utf8).write(to: url)
        }

        try add("Contents/MacOS/Atten")
        XCTAssertFalse(UpdateChecker.isCompleteApp(app))

        try add("Contents/Resources/Backend/atten-backend/atten-backend")
        XCTAssertFalse(UpdateChecker.isCompleteApp(app))

        try add("Contents/Resources/Models/Kokoro-82M/kokoro-v1_0.pth")
        XCTAssertTrue(UpdateChecker.isCompleteApp(app))
    }
}
