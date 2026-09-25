import AppKit
import AttenCore
import Foundation
import SwiftUI
import XCTest
@testable import Atten

/// Offscreen renders of a book's page (#102) in the four states it has to
/// read right in: a silent draft, a book generating, a voiced single-section
/// book and a voiced multi-chapter book. Gated behind `ATTEN_RENDER_DIR`,
/// like `LibraryRenderTests`.
@MainActor
final class BookDetailRenderTests: XCTestCase {
    func testBookDetailRendersInBothAppearances() async throws {
        guard let renderDirPath = ProcessInfo.processInfo.environment["ATTEN_RENDER_DIR"] else {
            throw XCTSkip("Set ATTEN_RENDER_DIR to render the book page")
        }
        let renderDir = URL(fileURLWithPath: renderDirPath, isDirectory: true)
        try FileManager.default.createDirectory(at: renderDir, withIntermediateDirectories: true)

        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttenBookDetailRender-\(UUID().uuidString)")
        let directories = AppDirectories(applicationSupport: workspace.appendingPathComponent("Application Support"))
        try directories.prepare()
        let suite = "AttenBookDetailRender.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let generator = GatedGenerator()
        let model = AppModel(
            directories: directories,
            settingsStore: SettingsStore(defaults: defaults),
            generator: generator
        )
        model.settings.defaultFormat = .wav
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: workspace)
        }

        // The two voiced books go straight onto the shelf, already narrated.
        let creekText = "The creek is bright this morning, and the meadow is ready for the first cut."
        let creek = try voiced(
            BookRecord(
                title: "The creek is bright", format: .document,
                sourcePath: workspace.appendingPathComponent("creek.txt").path,
                chapters: [BookChapter(title: "The creek is bright", text: creekText)],
                voiceID: "af_heart", speed: 1, audioFormat: .wav
            ),
            source: creekText, lengths: [5], in: workspace
        )
        let voyageText = (1...5).map { "Chapter \($0). " + String(repeating: "The sea kept its own counsel. ", count: 40) }
        let voyage = try voiced(
            BookRecord(
                title: "The Long Voyage", author: "Ada Marsh", format: .epub,
                sourcePath: workspace.appendingPathComponent("voyage.epub").path,
                chapters: voyageText.enumerated().map { BookChapter(title: ["Departure", "The Doldrums", "Landfall", "Winter Quarters", "Home"][$0.offset], text: $0.element) },
                voiceID: "bm_george", speed: 1, audioFormat: .wav
            ),
            source: voyageText.joined(separator: "\n"), lengths: [42, 186, 95, 271, 18], in: workspace
        )
        try await BookLibraryStore(fileURL: directories.booksFile).save([creek, voyage])
        await model.bookshelf.load()

        let shelf = model.bookshelf
        let silent = try shelf.saveDraft(
            title: "Notes on the harvest",
            text: "Bring the wagons round before dawn. The barley is dry enough to cut.",
            voiceID: "af_heart",
            defaults: model.settings
        )
        let parts = (1...4).map {
            DocumentChapter(title: "Letter \($0)", text: "Letter \($0). " + String(repeating: "Words to be read aloud. ", count: 120))
        }
        let generating = try shelf.saveDraft(
            title: "Letters Home", text: parts.map(\.text).joined(separator: "\n"),
            voiceID: "af_heart", defaults: model.settings, chapters: parts
        )
        shelf.narrate(generating.id, useMPS: false)
        generator.release()
        for _ in 0..<200 where shelf.narratedCount(of: generating) < 1 { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(shelf.narratingBookID, generating.id)

        let states: [(String, UUID)] = [
            ("silent", silent.id), ("generating", generating.id),
            ("single", creek.id), ("chapters", voyage.id),
        ]
        for (name, id) in states {
            let book = try XCTUnwrap(shelf.book(id: id))
            for dark in [false, true] {
                let image = try await renderImage(
                    BookDetailView(model: model, book: book) {},
                    dark: dark,
                    size: CGSize(width: 960, height: 900)
                )
                try write(image, to: renderDir.appendingPathComponent("book-detail-\(name)-\(dark ? "dark" : "light").png"))
            }
        }

        generator.open()
        try await shelf.stopAndSave()
    }

    /// `book` with its source on disk and one recording whose chapters run
    /// back to back for `lengths` seconds each.
    private func voiced(_ book: BookRecord, source: String, lengths: [Double], in directory: URL) throws -> BookRecord {
        var book = book
        try Data(source.utf8).write(to: book.sourceURL)
        let audio = try ListeningTests.silentAudio(seconds: lengths.reduce(0, +), in: directory)
        book.audioPath = audio.path
        var start = 0.0
        for (index, length) in lengths.enumerated() {
            book.chapters[index].audioPath = audio.path
            book.chapters[index].startTime = start
            book.chapters[index].endTime = start + length
            start += length
        }
        return book
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
        // `.task` work (cover loading, measuring a chapter) only runs across
        // repeated draws.
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
