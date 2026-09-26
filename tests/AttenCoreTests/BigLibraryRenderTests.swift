import AppKit
import AttenCore
@testable import AttenFixtureKit
import Foundation
import SwiftUI
import XCTest
@testable import Atten

/// Offscreen renders of what the 1,000-book live run turned up (#111): text-only
/// PDFs wearing a render of their first page as a cover (grid, hero, mini
/// player), and status lines that wrapped — the card's chapter count and the
/// sidebar's queue indicator. Built from `LibraryFixture`, like
/// `make-fixture-library`. Gated behind `ATTEN_RENDER_DIR`.
@MainActor
final class BigLibraryRenderTests: XCTestCase {
    func testFixtureLibraryRendersInBothAppearances() async throws {
        guard let renderDirPath = ProcessInfo.processInfo.environment["ATTEN_RENDER_DIR"] else {
            throw XCTSkip("Set ATTEN_RENDER_DIR to render the fixture library")
        }
        let renderDir = URL(fileURLWithPath: renderDirPath, isDirectory: true)
        try FileManager.default.createDirectory(at: renderDir, withIntermediateDirectories: true)

        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttenBigLibraryRender-\(UUID().uuidString)")
        let directories = AppDirectories(applicationSupport: workspace.appendingPathComponent("Application Support"))
        let suite = "AttenBigLibraryRender.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: workspace)
        }

        // Every silent draft waiting, so the queue's count runs to three
        // digits; books narrated partway stay off it, to show their meters.
        let built = try LibraryFixture.build(count: 200, voicedFraction: 0.25, in: directories)
        try await BookLibraryStore(fileURL: directories.booksFile).save(built.books)
        let waiting = built.books.filter { $0.chapters.allSatisfy { $0.audioPath == nil } }.map { LibraryFixture.QueuedEntry(bookID: $0.id) }
        try LibraryFixture.saveQueue(waiting, to: directories)
        let model = AppModel(
            directories: directories,
            settingsStore: SettingsStore(defaults: defaults),
            generator: ImmediateGenerator()
        )
        model.settings.defaultFormat = .wav
        await model.bookshelf.load()

        // A voiced, text-only PDF playing: the hero and the mini player.
        let pdf = try XCTUnwrap(model.bookshelf.books.first { $0.format == .pdf && $0.hasBookAudio })
        model.listen(to: pdf)
        model.pause()
        defer { model.closePlayer() }

        for dark in [false, true] {
            let suffix = dark ? "dark" : "light"
            try write(
                try await renderImage(LibraryView(model: model), dark: dark, size: CGSize(width: 1000, height: 2600)),
                to: renderDir.appendingPathComponent("biglib-library-\(suffix).png")
            )
            try write(
                try await renderImage(MiniPlayerStage(model: model), dark: dark, size: CGSize(width: 680, height: 110)),
                to: renderDir.appendingPathComponent("biglib-mini-player-\(suffix).png")
            )
            // The sidebar at its narrowest, and narrower than it goes.
            for width in [180, 120] {
                try write(
                    try await renderImage(
                        NarrationQueueIndicator(model: model).padding(.horizontal, AttenSpacing.xs).background(AttenColor.bg),
                        dark: dark, size: CGSize(width: CGFloat(width), height: 48)
                    ),
                    to: renderDir.appendingPathComponent("biglib-queue-indicator-\(width)-\(suffix).png")
                )
            }
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
        // `.task` work (cover loading) only runs across repeated draws.
        for _ in 0..<8 {
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
