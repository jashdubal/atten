import AppKit
import AttenCore
import Foundation
import SwiftUI
import XCTest
@testable import Atten

/// Offscreen renders of the Library, for reviewing it by eye without opening a
/// window — the portrait display these are normally checked on is sometimes
/// disconnected, and CI has no display at all. Gated behind `ATTEN_RENDER_DIR`
/// so it never runs there.
@MainActor
final class LibraryRenderTests: XCTestCase {
    private var workspace: URL!

    override func setUp() async throws {
        workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttenLibraryRenderTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: workspace)
    }

    func testLibraryRendersInBothAppearances() async throws {
        guard let renderDirPath = ProcessInfo.processInfo.environment["ATTEN_RENDER_DIR"] else {
            throw XCTSkip("Set ATTEN_RENDER_DIR to render Library screenshots")
        }
        let renderDir = URL(fileURLWithPath: renderDirPath, isDirectory: true)
        try FileManager.default.createDirectory(at: renderDir, withIntermediateDirectories: true)

        let fixture = try await makeFixture()
        defer { fixture.cleanUp() }

        // Settle the shelf's final state — including the "Old Friends" import
        // that the toast points at — before any snapshot is taken, so light
        // and dark render from the identical state rather than one from
        // before this import and one from after it.
        await fixture.triggerDuplicateToast()

        for dark in [false, true] {
            let suffix = dark ? "dark" : "light"

            let shelf = try await renderImage(
                LibraryView(model: fixture.model),
                dark: dark,
                size: CGSize(width: 1100, height: 1300)
            )
            try write(shelf, to: renderDir.appendingPathComponent("library-shelf-\(suffix).png"))

            // The toast only appears while `duplicateBookID` changes on a
            // *mounted* view, so each pass re-triggers the same (now
            // already-imported) duplicate on its own fresh `LibraryView` —
            // the book list this produces is identical to what's already
            // there, only the toast's own appearance is new each time.
            let toast = try await renderImage(
                LibraryView(model: fixture.model),
                dark: dark,
                size: CGSize(width: 1100, height: 1300),
                midway: { await fixture.triggerDuplicateToast() }
            )
            try write(toast, to: renderDir.appendingPathComponent("library-toast-\(suffix).png"))

            // A real sheet gets its background from the system's sheet
            // chrome, which this offscreen render has no window to supply.
            let export = try await renderImage(
                ExportSheet(model: fixture.model, target: fixture.exportTarget)
                    .frame(width: 420, height: 260)
                    .background(AttenColor.bg),
                dark: dark,
                size: CGSize(width: 420, height: 260)
            )
            try write(export, to: renderDir.appendingPathComponent("export-sheet-\(suffix).png"))
        }
    }

    // MARK: - Rendering

    private enum RenderError: Error { case empty }

    /// `ImageRenderer` only runs `.task`/`.onChange` work if it is asked to
    /// draw more than once with time passing in between, so this polls it
    /// for a few seconds rather than reading `nsImage` a single time. `midway`
    /// runs partway through that window, once the view has actually mounted —
    /// state changed before the first draw is not something `.onChange` ever
    /// sees as a change.
    private func renderImage(
        _ view: some View,
        dark: Bool,
        size: CGSize,
        midway: (() async -> Void)? = nil
    ) async throws -> NSImage {
        NSApplication.shared.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let renderer = ImageRenderer(content:
            view
                .environment(\.colorScheme, dark ? .dark : .light)
                .environment(\.attenIsOffscreenRender, true)
                .frame(width: size.width, height: size.height)
        )
        renderer.scale = 2
        var image: NSImage?
        let cycles = 10
        for cycle in 0..<cycles {
            image = renderer.nsImage
            if cycle == cycles / 2, let midway {
                await midway()
            }
            try? await Task.sleep(for: .milliseconds(300))
        }
        image = renderer.nsImage
        guard let image else { throw RenderError.empty }
        return image
    }

    private func write(_ image: NSImage, to url: URL) throws {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else { throw RenderError.empty }
        try png.write(to: url)
    }

    // MARK: - Fixture

    /// One of each state the shelf can show at once: a silent draft, a book
    /// partway through narration, a fully voiced book (also the Continue
    /// Listening hero), and a legacy `projects.json` entry.
    private func makeFixture() async throws -> Fixture {
        let directories = AppDirectories(
            applicationSupport: workspace.appendingPathComponent("Application Support")
        )
        try directories.prepare()
        let suite = "AttenLibraryRenderTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let model = AppModel(
            directories: directories,
            settingsStore: SettingsStore(defaults: defaults),
            generator: ImmediateGenerator()
        )

        // Distinct text per book, not just distinct titles — `BookshelfModel`
        // computes a book's content hash from its chapter text the first
        // time anything checks for a duplicate, so identical placeholder
        // text across fixture books would make two different books collide
        // onto the same hash, and so the same generated-cover seed.
        let silent = plainBook(title: "The Unread Manuscript", text: "A manuscript no one has opened yet.")

        var generating = plainBook(title: "Halfway There", text: "A book partway through being narrated.")
        generating.narrationState = .preparing
        generating.chapters = [
            try await chapter(narrated: true),
            try await chapter(narrated: false),
            try await chapter(narrated: false),
        ]

        // `BookshelfModel.load()` opens every chapter's audio with
        // `AVAudioFile` and drops anything that doesn't decode, and for the
        // book-level file it also drops audio whose real duration doesn't
        // match the chapter timeline — so the fixture needs the generator's
        // real (if silent) WAV, and `endTime` needs to match its length.
        var voiced = plainBook(title: "Finished Listen", text: "A book someone has already finished listening to.")
        let audioURL = try await generator.generate(chapter: "book-\(UUID().uuidString)", in: workspace)
        voiced.audioPath = audioURL.path
        voiced.chapters[0].audioPath = audioURL.path
        voiced.chapters[0].startTime = 0
        voiced.chapters[0].endTime = 0.1
        voiced.lastListenedAt = Date()
        voiced.listeningPosition = 0.05

        try await BookLibraryStore(fileURL: directories.booksFile).save([silent, generating, voiced])
        await model.bookshelf.load()

        model.projects = [
            ProjectRecord(
                title: "An Old Project",
                text: "Some legacy narration text, from before books existed.",
                voiceID: "af_heart",
                speed: 1,
                format: .mp3,
                audioPath: workspace.appendingPathComponent("legacy.mp3").path
            ),
        ]

        let exportTarget = try XCTUnwrap(ExportTarget(book: voiced))
        return Fixture(model: model, workspace: workspace, defaults: defaults, suite: suite, exportTarget: exportTarget)
    }

    /// Also used to give each book a real, valid narration file: `load()`
    /// discards audio `AVAudioFile` can't open, so an empty stand-in file
    /// would silently undo the fixture's own narration state.
    private let generator = ImmediateGenerator()

    private func plainBook(title: String, text: String) -> BookRecord {
        let sourcePath = workspace.appendingPathComponent("\(title).txt").path
        try? Data(text.utf8).write(to: URL(fileURLWithPath: sourcePath))
        return BookRecord(
            title: title,
            author: "A. Writer",
            format: .document,
            sourcePath: sourcePath,
            chapters: [BookChapter(title: "One", text: text)],
            voiceID: "af_heart",
            speed: 1,
            audioFormat: .wav
        )
    }

    private func chapter(narrated: Bool) async throws -> BookChapter {
        BookChapter(
            title: "Chapter",
            text: "Once upon a time.",
            audioPath: narrated
                ? try await generator.generate(chapter: "chapter-\(UUID().uuidString)", in: workspace).path
                : nil
        )
    }
}

@MainActor
private struct Fixture {
    let model: AppModel
    let workspace: URL
    let defaults: UserDefaults
    let suite: String
    let exportTarget: ExportTarget

    /// Imports the same text twice, exactly as a user dropping a duplicate
    /// would, so the dedupe toast shown is the real one rather than a
    /// stand-in built just for this render.
    func triggerDuplicateToast() async {
        let text = "The same story, imported twice so the toast has something to point at."
        let first = workspace.appendingPathComponent("Old Friends.txt")
        let second = workspace.appendingPathComponent("Old Friends Copy.txt")
        try? Data(text.utf8).write(to: first)
        try? Data(text.utf8).write(to: second)
        _ = await model.bookshelf.importBook(from: first, defaults: model.settings)
        _ = await model.bookshelf.importBook(from: second, defaults: model.settings)
    }

    func cleanUp() {
        defaults.removePersistentDomain(forName: suite)
    }
}
