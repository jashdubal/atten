import AppKit
import AttenCore
import Foundation
import SwiftUI
import XCTest
@testable import Atten

/// Offscreen renders of the player's transport with its chapter list and
/// bookmarks open and the sleep timer running, for reviewing by eye without a
/// window. A popover is a window of its own, which `ImageRenderer` cannot
/// draw, so each list is laid out where its popover opens. Gated behind
/// `ATTEN_RENDER_DIR` so it never runs on CI.
@MainActor
final class PlayerRenderTests: XCTestCase {
    func testPlayerRendersInBothAppearances() async throws {
        guard let renderDirPath = ProcessInfo.processInfo.environment["ATTEN_RENDER_DIR"] else {
            throw XCTSkip("Set ATTEN_RENDER_DIR to render player screenshots")
        }
        let renderDir = URL(fileURLWithPath: renderDirPath, isDirectory: true)
        try FileManager.default.createDirectory(at: renderDir, withIntermediateDirectories: true)

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttenPlayerRenderTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "AttenPlayerRenderTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(
            directories: AppDirectories(applicationSupport: directory),
            settingsStore: SettingsStore(defaults: defaults),
            generator: ImmediateGenerator()
        )

        let bounds: [Double] = [0, 312, 845, 1210, 1580, 1905]
        let titles = ["The Harbour", "Low Water", "What the Gulls Knew", "A Letter from Inland", "Morning"]
        var book = BookRecord(
            title: "The Harbour Year", author: "M. Aldous", format: .epub,
            sourcePath: directory.appendingPathComponent("harbour.epub").path,
            chapters: titles.map { BookChapter(title: $0, text: "Rain fell on the harbour.\n\nThe boats knocked together.") },
            voiceID: "af_heart", speed: 1, audioFormat: .wav
        )
        try Data("book".utf8).write(to: book.sourceURL)
        book.audioPath = try ListeningTests.silentAudio(seconds: bounds.last!, in: directory).path
        for index in book.chapters.indices {
            book.chapters[index].startTime = bounds[index]
            book.chapters[index].endTime = bounds[index + 1]
        }
        book.bookmarks = [
            Bookmark(location: ReadingLocation(chapterIndex: 0, paragraphIndex: 1), excerpt: "The boats knocked together."),
            Bookmark(
                location: ReadingLocation(chapterIndex: 2, paragraphIndex: 0),
                excerpt: "Nobody came down to the water that night, and by morning the tide had turned."
            ),
        ]
        try await BookLibraryStore(fileURL: AppDirectories(applicationSupport: directory).booksFile).save([book])
        await model.bookshelf.load()
        let loaded = try XCTUnwrap(model.bookshelf.book(id: book.id))
        XCTAssertTrue(loaded.hasBookAudio)
        model.listen(to: loaded, chapter: loaded.chapters[2])
        model.pause()
        model.seek(to: bounds[2] + 190)
        model.sleepTimer.set(.endOfChapter, ticking: false)
        defer { model.closePlayer() }
        let map = try XCTUnwrap(model.listeningMap)

        for dark in [false, true] {
            let suffix = dark ? "dark" : "light"
            let chapters = PlayerChapterList(chapters: map.chapters, current: map.chapterIndex(at: model.playbackPosition)) { _ in }
            try write(
                try await renderImage(Stage(model: model, panel: AnyView(chapters)), dark: dark),
                to: renderDir.appendingPathComponent("player-chapters-\(suffix).png")
            )
            let bookmarks = PlayerBookmarkList(
                entries: loaded.bookmarks.map {
                    .init(bookmark: $0, chapterTitle: titles[$0.location.chapterIndex],
                          time: model.time(of: $0, script: .empty))
                },
                add: {}, jump: { _ in }, remove: { _ in }
            )
            try write(
                try await renderImage(Stage(model: model, panel: AnyView(bookmarks)), dark: dark),
                to: renderDir.appendingPathComponent("player-bookmarks-\(suffix).png")
            )
        }
    }

    /// The foot of the player: a list open over the transport.
    private struct Stage: View {
        let model: AppModel
        let panel: AnyView
        @Namespace private var namespace
        @State private var playhead = ReadAlongPlayhead()

        var body: some View {
            ZStack {
                AttenColor.bg
                VStack(alignment: .leading, spacing: AttenSpacing.xs) {
                    Spacer()
                    panel
                        .attenElevated(.floating, radius: AttenRadius.card)
                        .padding(.leading, AttenSpacing.xl)
                    ReadAlongTransport(model: model, namespace: namespace, script: .empty, playhead: playhead)
                }
                .padding(AttenSpacing.lg)
            }
        }
    }

    private enum RenderError: Error { case empty }

    private func renderImage(_ view: some View, dark: Bool) async throws -> NSImage {
        NSApplication.shared.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let renderer = ImageRenderer(content:
            view
                .environment(\.colorScheme, dark ? .dark : .light)
                .environment(\.attenIsOffscreenRender, true)
                .frame(width: 728, height: 560)
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
