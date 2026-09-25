import AppKit
import AttenCore
import Foundation
import SwiftUI
import XCTest
@testable import Atten

/// An offscreen render of Create's inspector with the draft queued behind
/// another narration. Gated behind `ATTEN_RENDER_DIR`, like
/// `NarrationQueueRenderTests`.
@MainActor
final class CreateQueueRenderTests: XCTestCase {
    func testQueuedInspectorRendersInBothAppearances() async throws {
        guard let renderDirPath = ProcessInfo.processInfo.environment["ATTEN_RENDER_DIR"] else {
            throw XCTSkip("Set ATTEN_RENDER_DIR to render the queued inspector")
        }
        let renderDir = URL(fileURLWithPath: renderDirPath, isDirectory: true)
        try FileManager.default.createDirectory(at: renderDir, withIntermediateDirectories: true)

        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttenCreateQueueRender-\(UUID().uuidString)")
        let suite = "AttenCreateQueueRender.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let generator = GatedGenerator()
        let model = AppModel(
            directories: AppDirectories(applicationSupport: workspace),
            settingsStore: SettingsStore(defaults: defaults),
            generator: generator
        )
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: workspace)
        }
        model.settings.defaultFormat = .wav

        let running = try model.bookshelf.saveDraft(
            title: "The Long Voyage", text: "Already narrating.", voiceID: "af_heart", defaults: model.settings
        )
        let waiting = try model.bookshelf.saveDraft(
            title: "Letters Home", text: "Waiting its turn.", voiceID: "af_heart", defaults: model.settings
        )
        model.bookshelf.narrate(running.id, useMPS: false)
        model.bookshelf.narrate(waiting.id, useMPS: false)
        model.section = .studio
        model.createFlow.title = "A Field Guide to Clouds"
        model.createFlow.text = String(repeating: "Cumulus clouds drift over the meadow in the afternoon. ", count: 120)
        model.createFlow.generate()
        XCTAssertEqual(model.createFlow.state, .queued)
        XCTAssertEqual(model.createFlow.queuePosition, 2)

        for dark in [false, true] {
            let image = try await renderImage(
                CreateInspector(model: model, flow: model.createFlow).background(AttenColor.bg),
                dark: dark,
                size: CGSize(width: 320, height: 640)
            )
            try write(image, to: renderDir.appendingPathComponent("create-queued-inspector-\(dark ? "dark" : "light").png"))
        }

        generator.open()
        try await model.bookshelf.stopAndSave()
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
