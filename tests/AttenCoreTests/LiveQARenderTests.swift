import AppKit
import AttenCore
import Foundation
import SwiftUI
import XCTest
@testable import Atten

/// Offscreen renders of what #98 changed: the empty Library, text-free
/// thumbnail covers in the mini player and the list view, and Create with an
/// unnamed draft's derived title, estimates in seconds and a one-line
/// narrator. Gated behind `ATTEN_RENDER_DIR` so it never runs on CI.
@MainActor
final class LiveQARenderTests: XCTestCase {
    func testChangedSurfacesRenderInBothAppearances() async throws {
        guard let renderDirPath = ProcessInfo.processInfo.environment["ATTEN_RENDER_DIR"] else {
            throw XCTSkip("Set ATTEN_RENDER_DIR to render the #98 surfaces")
        }
        let renderDir = URL(fileURLWithPath: renderDirPath, isDirectory: true)
        try FileManager.default.createDirectory(at: renderDir, withIntermediateDirectories: true)

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttenLiveQARender-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "AttenLiveQARender.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(
            directories: AppDirectories(applicationSupport: directory),
            settingsStore: SettingsStore(defaults: defaults),
            generator: ImmediateGenerator()
        )
        model.settings.defaultFormat = .wav
        await model.bookshelf.load()

        for dark in [false, true] {
            let suffix = dark ? "dark" : "light"
            try write(
                try await renderImage(LibraryView(model: model), dark: dark, size: CGSize(width: 900, height: 560)),
                to: renderDir.appendingPathComponent("library-empty-\(suffix).png")
            )
        }

        // An untitled draft, voiced and playing: the case that printed
        // "Unt / itl…" in the mini player.
        var book = BookRecord(
            title: "Untitled", format: .document,
            sourcePath: directory.appendingPathComponent("draft.txt").path,
            chapters: [BookChapter(title: "Untitled", text: "The creek is bright this morning.")],
            voiceID: "af_heart", speed: 1, audioFormat: .wav
        )
        try Data("The creek is bright this morning.".utf8).write(to: book.sourceURL)
        book.audioPath = try ListeningTests.silentAudio(seconds: 4, in: directory).path
        book.chapters[0].startTime = 0
        book.chapters[0].endTime = 4
        try await BookLibraryStore(fileURL: AppDirectories(applicationSupport: directory).booksFile).save([book])
        await model.bookshelf.load()
        let loaded = try XCTUnwrap(model.bookshelf.book(id: book.id))
        model.listen(to: loaded)
        model.pause()
        defer { model.closePlayer() }

        UserDefaults.standard.set(true, forKey: "Atten.libraryListView")
        defer { UserDefaults.standard.removeObject(forKey: "Atten.libraryListView") }
        for dark in [false, true] {
            let suffix = dark ? "dark" : "light"
            try write(
                try await renderImage(MiniPlayerStage(model: model), dark: dark, size: CGSize(width: 680, height: 110)),
                to: renderDir.appendingPathComponent("mini-player-\(suffix).png")
            )
            try write(
                try await renderImage(LibraryView(model: model), dark: dark, size: CGSize(width: 900, height: 760)),
                to: renderDir.appendingPathComponent("library-list-\(suffix).png")
            )
        }
        model.closePlayer()

        model.section = .studio
        model.createFlow.loadSample()
        for dark in [false, true] {
            let suffix = dark ? "dark" : "light"
            try write(
                // The editor beside it is an `NSViewRepresentable`, which
                // `ImageRenderer` cannot draw.
                try await renderImage(
                    CreateInspector(model: model, flow: model.createFlow).background(AttenColor.bg),
                    dark: dark, size: CGSize(width: 320, height: 640)
                ),
                to: renderDir.appendingPathComponent("create-inspector-\(suffix).png")
            )
        }
    }

    private struct MiniPlayerStage: View {
        let model: AppModel
        @Namespace private var namespace

        var body: some View {
            ZStack {
                AttenColor.bg
                GlobalPlayer(model: model, isCompact: false, namespace: namespace)
                    .padding(AttenSpacing.lg)
            }
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
