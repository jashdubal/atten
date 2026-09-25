import AppKit
import AttenCore
import Foundation
import SwiftUI
import XCTest
@testable import Atten

/// Offscreen renders of the narration queue: its popover, the sidebar
/// indicator that opens it, and a queued book on the shelf. Gated behind
/// `ATTEN_RENDER_DIR`, like `LibraryRenderTests`.
@MainActor
final class NarrationQueueRenderTests: XCTestCase {
    func testQueueRendersInBothAppearances() async throws {
        guard let renderDirPath = ProcessInfo.processInfo.environment["ATTEN_RENDER_DIR"] else {
            throw XCTSkip("Set ATTEN_RENDER_DIR to render queue screenshots")
        }
        let renderDir = URL(fileURLWithPath: renderDirPath, isDirectory: true)
        try FileManager.default.createDirectory(at: renderDir, withIntermediateDirectories: true)

        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttenQueueRenderTests-\(UUID().uuidString)")
        let directories = AppDirectories(applicationSupport: workspace.appendingPathComponent("Application Support"))
        try directories.prepare()
        let suite = "AttenQueueRenderTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let generator = GatedGenerator()
        let model = AppModel(
            directories: directories,
            settingsStore: SettingsStore(defaults: defaults),
            generator: generator
        )
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: workspace)
        }

        // One book generating, one waiting its turn, one paused.
        let shelf = model.bookshelf
        let running = try draft("The Long Voyage", chapters: 4, in: model)
        let waiting = try draft("Letters Home", chapters: 3, in: model)
        let paused = try draft("A Field Guide to Clouds", chapters: 6, in: model)
        for book in [running, waiting, paused] { shelf.narrate(book.id, useMPS: false) }
        shelf.pauseNarration(paused.id)
        generator.release()
        for _ in 0..<200 where shelf.narratedCount(of: running) < 1 { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(shelf.narratingBookID, running.id)

        for dark in [false, true] {
            let suffix = dark ? "dark" : "light"
            let panel = try await renderImage(
                NarrationQueuePanel(model: model).background(AttenColor.surfaceElevated),
                dark: dark,
                size: CGSize(width: 380, height: 250)
            )
            try write(panel, to: renderDir.appendingPathComponent("queue-popover-\(suffix).png"))

            let indicator = try await renderImage(
                NarrationQueueIndicator(model: model).padding(AttenSpacing.xs).background(AttenColor.bg),
                dark: dark,
                size: CGSize(width: 200, height: 48)
            )
            try write(indicator, to: renderDir.appendingPathComponent("queue-indicator-\(suffix).png"))

            let library = try await renderImage(
                LibraryView(model: model),
                dark: dark,
                size: CGSize(width: 1000, height: 760)
            )
            try write(library, to: renderDir.appendingPathComponent("queue-library-\(suffix).png"))
        }

        generator.open()
        try await shelf.stopAndSave()
    }

    private func draft(_ title: String, chapters: Int, in model: AppModel) throws -> BookRecord {
        let parts = (1...chapters).map {
            DocumentChapter(title: "Chapter \($0)", text: "\(title), chapter \($0). " + String(repeating: "Words to be read aloud. ", count: 60 * title.count))
        }
        return try model.bookshelf.saveDraft(
            title: title,
            text: parts.map(\.text).joined(separator: "\n"),
            voiceID: "af_heart",
            defaults: model.settings,
            chapters: parts
        )
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
        // `.task` work (cover loading) only runs across repeated draws.
        for _ in 0..<6 {
            _ = renderer.nsImage
            try? await Task.sleep(for: .milliseconds(300))
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
