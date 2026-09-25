import AppKit
import AttenCore
import Foundation
import SwiftUI
import XCTest
@testable import Atten

/// An offscreen render of Create's footer: the word count and listen
/// estimate, now in the same unit the inspector uses (#101). The title field
/// isn't rendered here — like `AlignedTextEditor`, a `TextField` doesn't draw
/// through `ImageRenderer` (it renders as a "prohibited" cursor glyph
/// regardless of content), so its truncation fix is covered by
/// `ChapterDetectionTests.testADraftIsCalledByItsOpeningWords` and manual
/// on-screen QA instead. Gated behind `ATTEN_RENDER_DIR`, like
/// `CreateQueueRenderTests`.
@MainActor
final class CreateTitleRenderTests: XCTestCase {
    func testCreateFooterRendersInBothAppearances() async throws {
        guard let renderDirPath = ProcessInfo.processInfo.environment["ATTEN_RENDER_DIR"] else {
            throw XCTSkip("Set ATTEN_RENDER_DIR to render the Create footer")
        }
        let renderDir = URL(fileURLWithPath: renderDirPath, isDirectory: true)
        try FileManager.default.createDirectory(at: renderDir, withIntermediateDirectories: true)

        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttenCreateTitleRender-\(UUID().uuidString)")
        let suite = "AttenCreateTitleRender.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let model = AppModel(
            directories: AppDirectories(applicationSupport: workspace),
            settingsStore: SettingsStore(defaults: defaults),
            generator: GatedGenerator()
        )
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: workspace)
        }
        model.createFlow.text = CreateFlowModel.sampleText
        XCTAssertEqual(model.createFlow.state, .editing)

        for dark in [false, true] {
            let suffix = dark ? "dark" : "light"
            let footer = try await renderImage(
                CreateStatusFooter(flow: model.createFlow).background(AttenColor.bg),
                dark: dark,
                size: CGSize(width: 640, height: 60)
            )
            try write(footer, to: renderDir.appendingPathComponent("create-footer-\(suffix).png"))
        }
    }

    private enum RenderError: Error { case empty }

    private func renderImage(_ view: some View, dark: Bool, size: CGSize) async throws -> NSImage {
        NSApplication.shared.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let renderer = ImageRenderer(content:
            view
                .environment(\.colorScheme, dark ? .dark : .light)
                .environment(\.attenIsOffscreenRender, true)
                .frame(width: size.width, height: size.height)
        )
        renderer.scale = 2
        for _ in 0..<4 {
            _ = renderer.nsImage
            try? await Task.sleep(for: .milliseconds(200))
        }
        guard let image = renderer.nsImage else { throw RenderError.empty }
        return image
    }

    private func write(_ image: NSImage, to url: URL) throws {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else { throw RenderError.empty }
        try png.write(to: url)
    }
}
