import AppKit
import AttenCore
import Foundation
import PDFKit
import SwiftUI

/// The picture on the front of a book.
///
/// A shelf of books that shows no covers is a list with rounded corners. Both
/// formats carry one: a PDF's is its first page, and an EPUB names an image in
/// its manifest. Finding either means opening the file — unpacking a whole zip,
/// in the EPUB's case — so it is done once, off the main thread, and the result
/// is kept beside the book.
@MainActor
@Observable
final class BookCoverStore {
    private let directory: URL
    private var images: [UUID: NSImage] = [:]
    private var inFlight: Set<UUID> = []
    /// Books that turned out not to have one. Without this, every book with no
    /// cover unpacked its whole archive again each time its card came back on
    /// screen, because "already looked" was only ever recorded as a success.
    private var missing: Set<UUID> = []
    /// Finding a cover means unpacking an archive, and a shelf coming into view
    /// asks for every visible book at once. One at a time.
    private let extractor = Extractor()

    init(directory: URL) {
        self.directory = directory
    }

    /// What is already known, for a card that is drawing right now.
    func cover(for bookID: UUID) -> NSImage? { images[bookID] }

    /// Loads the cover if it has not been looked for yet. Safe to call from
    /// every redraw: the second call for a book does nothing.
    func load(_ book: BookRecord) async {
        guard images[book.id] == nil,
              !missing.contains(book.id),
              !inFlight.contains(book.id) else { return }
        inFlight.insert(book.id)
        defer { inFlight.remove(book.id) }

        let found = await extractor.data(
            from: book.sourceURL,
            format: book.format,
            cachedAt: cacheURL(book.id)
        )
        guard let found, let image = NSImage(data: found) else {
            missing.insert(book.id)
            return
        }
        images[book.id] = image
    }

    func forget(_ bookID: UUID) {
        images.removeValue(forKey: bookID)
        missing.remove(bookID)
        try? FileManager.default.removeItem(at: cacheURL(bookID))
    }

    /// An actor, so however many cards ask at once the archives are opened one
    /// after another rather than all together.
    private actor Extractor {
        /// Hands back the cover's bytes rather than the cover.
        ///
        /// `NSImage` is not Sendable, so returning one from an actor is a
        /// compile error under Swift 6's concurrency checking — and one that a
        /// new enough toolchain lets through, which is why this reached CI
        /// rather than the machine it was written on. Data crosses safely, and
        /// the image is made on the main actor, where it is going to be drawn.
        func data(from source: URL, format: BookFormat, cachedAt cached: URL) -> Data? {
            // Decoded, not merely present: a cache file that cannot be read as
            // an image has to be extracted again rather than counted as a book
            // with no cover.
            if let cached = try? Data(contentsOf: cached), NSImage(data: cached) != nil {
                return cached
            }
            guard let data = BookCoverStore.extract(from: source, format: format),
                  NSImage(data: data) != nil else { return nil }
            try? FileManager.default.createDirectory(
                at: cached.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? data.write(to: cached, options: .atomic)
            return data
        }
    }

    private func cacheURL(_ bookID: UUID) -> URL {
        directory.appendingPathComponent("\(bookID.uuidString).png")
    }

    /// Runs off the main actor, so it touches nothing but the file it is given.
    private nonisolated static func extract(from url: URL, format: BookFormat) -> Data? {
        switch format {
        // A report has no cover, and inventing one would be a picture of
        // something that does not exist. The shelf draws its own card.
        case .document:
            return nil
        case .epub:
            return EPUBTextExtractor.coverImageData(from: url)
        case .mobi:
            return MOBITextExtractor.coverImageData(from: url)
        case .pdf:
            guard let document = PDFDocument(url: url),
                  !document.isLocked,
                  let page = document.page(at: 0) else { return nil }
            let bounds = page.bounds(for: .cropBox)
            guard bounds.width > 1, bounds.height > 1 else { return nil }
            // Twice the size a card draws it at, so it stays sharp on a retina
            // display without keeping a whole page of artwork in memory.
            let scale = min(600 / bounds.width, 900 / bounds.height, 3)
            let size = NSSize(
                width: (bounds.width * scale).rounded(),
                height: (bounds.height * scale).rounded()
            )
            let thumbnail = page.thumbnail(of: size, for: .cropBox)
            guard let tiff = thumbnail.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
            return bitmap.representation(using: .png, properties: [:])
        }
    }
}
