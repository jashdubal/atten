import AppKit
import AttenCore
import Foundation
import PDFKit
import SwiftUI

/// The picture on the front of a book.
///
/// A shelf of books that shows no covers is a list with rounded corners. An
/// EPUB names an image in its manifest; a PDF's cover is its first page, but
/// only when that page is a picture — a scanned jacket — and not a page of
/// text. Finding either means opening the file — unpacking a whole zip,
/// in the EPUB's case — so it is done once, off the main thread, and the result
/// is kept beside the book.
@MainActor
@Observable
final class BookCoverStore {
    private let directory: URL
    private var images: [UUID: NSImage] = [:]
    /// The colour a jacket's own art is dominated by, so a real cover can cast
    /// a shadow tinted like the book rather than a plain black one. Computed
    /// alongside the cover itself, off the main thread — a k-means pass on
    /// every redraw would be the kind of cost a shelf of covers cannot hide.
    private var dominantColors: [UUID: OKLCHColor] = [:]
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

    /// The dominant colour of that cover, once it has loaded. Nil for a book
    /// with no art of its own — a generated cover has no "dominant colour" of
    /// its own to speak of; it draws from its `CoverSeed` directly.
    func dominantColor(for bookID: UUID) -> OKLCHColor? { dominantColors[bookID] }

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
            cachedAt: cacheURL(book.id),
            replacing: legacyCacheURL(book.id)
        )
        guard let found, let image = NSImage(data: found) else {
            missing.insert(book.id)
            return
        }
        images[book.id] = image
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        dominantColors[book.id] = await Task.detached(priority: .utility) {
            CoverPalette.dominantColor(of: cgImage)
        }.value
    }

    func forget(_ bookID: UUID) {
        images.removeValue(forKey: bookID)
        dominantColors.removeValue(forKey: bookID)
        missing.remove(bookID)
        try? FileManager.default.removeItem(at: cacheURL(bookID))
        try? FileManager.default.removeItem(at: legacyCacheURL(bookID))
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
        func data(from source: URL, format: BookFormat, cachedAt cached: URL, replacing legacy: URL) -> Data? {
            // Decoded, not merely present: a cache file that cannot be read as
            // an image has to be extracted again rather than counted as a book
            // with no cover.
            if let cached = try? Data(contentsOf: cached), NSImage(data: cached) != nil {
                return cached
            }
            try? FileManager.default.removeItem(at: legacy)
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
        directory.appendingPathComponent("\(bookID.uuidString).v2.png")
    }

    /// Where covers were kept when any PDF's first page counted as one. Those
    /// renders of a page of text are thrown away, not shown.
    private func legacyCacheURL(_ bookID: UUID) -> URL {
        directory.appendingPathComponent("\(bookID.uuidString).png")
    }

    /// Runs off the main actor, so it touches nothing but the file it is given.
    nonisolated static func extract(from url: URL, format: BookFormat) -> Data? {
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
                  let page = document.page(at: 0),
                  isJacket(page) else { return nil }
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

    /// Whether a PDF's first page is a picture of the book's cover rather than
    /// its first page of reading. A scanned jacket is one image over most of
    /// the page and carries a few words at most, even with a text layer from
    /// OCR; a page of text is the opposite, and drawn on a shelf it is a grey
    /// block of tiny print that could be any book.
    private nonisolated static func isJacket(_ page: PDFPage) -> Bool {
        let words = (page.string ?? "").split { $0.isWhitespace || $0.isNewline }.count
        guard words < 100, let pageRef = page.pageRef else { return false }
        let box = pageRef.getBoxRect(.cropBox)
        guard box.width > 1, box.height > 1 else { return false }
        return imageArea(on: pageRef) / (box.width * box.height) >= 0.5
    }

    /// The area of the page its images are painted over, in the page's own
    /// units. An image XObject fills the unit square of whatever transform is
    /// current when it is drawn, so following `q`, `Q` and `cm` through the
    /// content stream is enough to measure each one.
    private nonisolated static func imageArea(on page: CGPDFPage) -> CGFloat {
        final class Painter {
            var transform = CGAffineTransform.identity
            var saved: [CGAffineTransform] = []
            var area: CGFloat = 0
        }
        guard let operators = CGPDFOperatorTableCreate() else { return 0 }
        CGPDFOperatorTableSetCallback(operators, "q") { _, info in
            let painter = Unmanaged<Painter>.fromOpaque(info!).takeUnretainedValue()
            painter.saved.append(painter.transform)
        }
        CGPDFOperatorTableSetCallback(operators, "Q") { _, info in
            let painter = Unmanaged<Painter>.fromOpaque(info!).takeUnretainedValue()
            painter.transform = painter.saved.popLast() ?? painter.transform
        }
        CGPDFOperatorTableSetCallback(operators, "cm") { scanner, info in
            let painter = Unmanaged<Painter>.fromOpaque(info!).takeUnretainedValue()
            var values = [CGPDFReal](repeating: 0, count: 6)
            for index in (0..<6).reversed() {
                guard CGPDFScannerPopNumber(scanner, &values[index]) else { return }
            }
            let matrix = CGAffineTransform(
                a: values[0], b: values[1], c: values[2], d: values[3], tx: values[4], ty: values[5]
            )
            painter.transform = matrix.concatenating(painter.transform)
        }
        CGPDFOperatorTableSetCallback(operators, "Do") { scanner, info in
            let painter = Unmanaged<Painter>.fromOpaque(info!).takeUnretainedValue()
            var name: UnsafePointer<CChar>?
            var object: CGPDFObjectRef?
            var stream: CGPDFStreamRef?
            var subtype: UnsafePointer<CChar>?
            guard CGPDFScannerPopName(scanner, &name), let name,
                  let object = CGPDFContentStreamGetResource(CGPDFScannerGetContentStream(scanner), "XObject", name),
                  CGPDFObjectGetValue(object, .stream, &stream), let stream,
                  let dictionary = CGPDFStreamGetDictionary(stream),
                  CGPDFDictionaryGetName(dictionary, "Subtype", &subtype), let subtype,
                  String(cString: subtype) == "Image" else { return }
            let t = painter.transform
            painter.area += abs(t.a * t.d - t.b * t.c)
        }
        let painter = Painter()
        let content = CGPDFContentStreamCreateWithPage(page)
        let scanner = CGPDFScannerCreate(content, operators, Unmanaged.passUnretained(painter).toOpaque())
        CGPDFScannerScan(scanner)
        CGPDFScannerRelease(scanner)
        CGPDFContentStreamRelease(content)
        CGPDFOperatorTableRelease(operators)
        return painter.area
    }
}
