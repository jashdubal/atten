import AppKit
import AttenCore
import Foundation
import SwiftUI
import XCTest
@testable import Atten

/// Offscreen renders of the Export sheet and Settings (#107), where
/// segmented pickers, toggles and sliders now pick up `AttenColor.signal`
/// instead of the macOS system accent. Gated behind `ATTEN_RENDER_DIR`, like
/// `BookDetailRenderTests`.
///
/// `ImageRenderer` cannot rasterize the native AppKit chrome behind
/// `Picker(.segmented)` or `TabView` off a real window — both draw as a
/// placeholder "prohibited" glyph here regardless of tint. The button and
/// text colours in these renders confirm `.tint(AttenColor.signal)` resolves
/// correctly per appearance; the segmented control and Settings' tab chrome
/// still need the coordinator's live on-screen check.
@MainActor
final class AccentTintRenderTests: XCTestCase {
    func testExportSheetAndSettingsRenderInBothAppearances() async throws {
        guard let renderDirPath = ProcessInfo.processInfo.environment["ATTEN_RENDER_DIR"] else {
            throw XCTSkip("Set ATTEN_RENDER_DIR to render the accent-tint screens")
        }
        let renderDir = URL(fileURLWithPath: renderDirPath, isDirectory: true)
        try FileManager.default.createDirectory(at: renderDir, withIntermediateDirectories: true)

        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttenAccentTintRender-\(UUID().uuidString)")
        let directories = AppDirectories(applicationSupport: workspace.appendingPathComponent("Application Support"))
        try directories.prepare()
        let suite = "AttenAccentTintRender.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let model = AppModel(
            directories: directories,
            settingsStore: SettingsStore(defaults: defaults),
            generator: ImmediateGenerator()
        )
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: workspace)
        }

        let audio = try ListeningTests.silentAudio(seconds: 12, in: workspace)
        var book = BookRecord(
            title: "The Long Voyage", author: "Ada Marsh", format: .epub,
            sourcePath: workspace.appendingPathComponent("voyage.epub").path,
            chapters: [BookChapter(title: "Departure", text: "The tide was out and the harbour was quiet.")],
            voiceID: "bm_george", speed: 1, audioFormat: .wav
        )
        book.audioPath = audio.path
        book.chapters[0].audioPath = audio.path
        book.chapters[0].startTime = 0
        book.chapters[0].endTime = 12
        let target = try XCTUnwrap(ExportTarget(book: book))

        for dark in [false, true] {
            let export = try await renderImage(ExportSheet(model: model, target: target), dark: dark, size: CGSize(width: 420, height: 260))
            try write(export, to: renderDir.appendingPathComponent("accent-tint-export-\(dark ? "dark" : "light").png"))

            let settings = try await renderImage(SettingsView(model: model), dark: dark, size: CGSize(width: 720, height: 560))
            try write(settings, to: renderDir.appendingPathComponent("accent-tint-settings-\(dark ? "dark" : "light").png"))
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
            try? await Task.sleep(for: .milliseconds(150))
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
