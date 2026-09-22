import AttenCore
import Foundation
import Observation

/// The Library: books Atten has imported, and the narration it generates from
/// them one chapter at a time.
///
/// A whole book is far too much text for one call to the speech engine — the
/// user would watch a spinner for half an hour with no way to tell progress
/// from a hang. Narrating chapter by chapter gives real progress, lets a run be
/// cancelled without losing what is done, and makes a second run resume where
/// the first stopped.
@MainActor
@Observable
final class BookshelfModel {
    struct NarrationProgress: Equatable {
        let bookID: UUID
        let chapterID: UUID
        let chapterTitle: String
        let completed: Int
        let total: Int

        var fraction: Double { total > 0 ? Double(completed) / Double(total) : 0 }
    }

    private(set) var books: [BookRecord] = []
    private(set) var progress: NarrationProgress?
    private(set) var isImporting = false
    /// How many chapters of each book have narration on disk.
    ///
    /// Answering means asking the file system once per chapter, and the shelf
    /// asked from inside its card bodies — a book of two hundred chapters was
    /// two hundred questions per card, on every hover and every redraw.
    /// Counted when the shelf changes instead.
    private(set) var narratedCounts: [UUID: Int] = [:]
    var errorMessage: String?
    var successMessage: String?

    @ObservationIgnored private let directories: AppDirectories
    @ObservationIgnored private let store: BookLibraryStore
    let covers: BookCoverStore
    @ObservationIgnored private let generator: any TTSGenerating
    @ObservationIgnored private var narrationTask: Task<Void, Never>?
    /// Answers with the model a voice still needs, or nil when it can speak
    /// now. Only the app model knows which models are installed.
    @ObservationIgnored var missingModelID: (String) -> String? = { _ in nil }

    init(directories: AppDirectories, generator: any TTSGenerating) {
        self.directories = directories
        self.store = BookLibraryStore(fileURL: directories.booksFile)
        self.covers = BookCoverStore(
            directory: directories.bookSources.appendingPathComponent("Covers", isDirectory: true)
        )
        self.generator = generator
    }

    var isNarrating: Bool { progress != nil }

    func book(id: UUID) -> BookRecord? { books.first { $0.id == id } }

    func narratedCount(of book: BookRecord) -> Int {
        narratedCounts[book.id] ?? 0
    }

    func isFullyNarrated(_ book: BookRecord) -> Bool {
        !book.chapters.isEmpty && narratedCount(of: book) == book.chapters.count
    }

    /// Recounts from the file system. Called when the shelf changes, and again
    /// when the Library is opened, so narration deleted in Finder while Atten
    /// was on another screen does not leave a play button that does nothing.
    func refreshNarrationCounts() {
        narratedCounts = Dictionary(
            books.map { ($0.id, $0.narratedCount) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    func load() async {
        do {
            books = try await store.load().sorted { $0.addedAt > $1.addedAt }
            refreshNarrationCounts()
        } catch {
            errorMessage = "Atten could not read your library: \(error.localizedDescription)"
        }
    }

    // MARK: - Import

    /// Copies the book into Atten's own library folder and reads it into
    /// chapters. Extraction walks every page, so it runs off the main actor.
    func importBook(from url: URL, defaults: AppSettings) async {
        guard !isImporting else { return }
        isImporting = true
        defer { isImporting = false }

        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        guard let format = BookFormat.resolve(for: url) else {
            errorMessage = DocumentImportError
                .unsupportedFormat(url.pathExtension)
                .localizedDescription
            return
        }

        do {
            let destination = try copyIntoLibrary(url)
            do {
                let document = try await Task.detached(priority: .userInitiated) {
                    try DocumentImporter.extract(from: destination)
                }.value
                let book = BookRecord(
                    title: document.title,
                    author: document.author,
                    format: format,
                    sourcePath: destination.path,
                    chapters: document.chapters.map {
                        BookChapter(title: $0.title, text: $0.text, pageIndex: $0.pageIndex)
                    },
                    voiceID: defaults.selectedVoiceID,
                    speed: defaults.defaultSpeed,
                    audioFormat: defaults.defaultFormat
                )
                books.insert(book, at: 0)
                refreshNarrationCounts()
                try await store.save(books)
                successMessage = "Added \(book.title) — \(book.chapters.count) chapters."
            } catch {
                // A book Atten cannot read must not leave a copy behind.
                try? FileManager.default.removeItem(at: destination)
                throw error
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func copyIntoLibrary(_ url: URL) throws -> URL {
        try FileManager.default.createDirectory(
            at: directories.bookSources,
            withIntermediateDirectories: true
        )
        let base = ExportService.safeFilename(url.deletingPathExtension().lastPathComponent)
        let name = base.isEmpty ? "Book" : base
        var destination = directories.bookSources
            .appendingPathComponent(name)
            .appendingPathExtension(url.pathExtension)
        var counter = 2
        while FileManager.default.fileExists(atPath: destination.path) {
            destination = directories.bookSources
                .appendingPathComponent("\(name) \(counter)")
                .appendingPathExtension(url.pathExtension)
            counter += 1
        }
        try FileManager.default.copyItem(at: url, to: destination)
        return destination
    }

    // MARK: - Narration

    /// Narrates the chapters that have no audio yet, in reading order. Passing
    /// `chapters` narrates just those, which is how the reader narrates the one
    /// chapter on screen.
    func narrate(_ bookID: UUID, chapters requested: [Int]? = nil, useMPS: Bool) {
        guard narrationTask == nil, let book = book(id: bookID) else { return }
        let pending = (requested ?? Array(book.chapters.indices))
            .filter { book.chapters.indices.contains($0) && !book.chapters[$0].isNarrated }
        guard !pending.isEmpty else { return }

        if let missing = missingModelMessage(for: book.voiceID) {
            errorMessage = missing
            return
        }

        errorMessage = nil
        let directory = directories.narrations
            .appendingPathComponent(bookID.uuidString, isDirectory: true)
        progress = NarrationProgress(
            bookID: bookID,
            chapterID: book.chapters[pending[0]].id,
            chapterTitle: book.chapters[pending[0]].title,
            completed: book.narratedCount,
            total: book.chapters.count
        )

        narrationTask = Task { [weak self] in
            guard let self else { return }
            defer {
                narrationTask = nil
                progress = nil
            }
            do {
                try FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true
                )
                for index in pending {
                    try Task.checkCancellation()
                    guard let position = books.firstIndex(where: { $0.id == bookID }) else { return }
                    let current = books[position]
                    let chapter = current.chapters[index]
                    progress = NarrationProgress(
                        bookID: bookID,
                        chapterID: chapter.id,
                        chapterTitle: chapter.title,
                        completed: current.narratedCount,
                        total: current.chapters.count
                    )
                    let output = try await generator.generate(
                        GenerationRequest(
                            text: chapter.text,
                            voiceID: current.voiceID,
                            speed: current.speed,
                            format: current.audioFormat,
                            outputDirectory: directory,
                            filename: Self.chapterFilename(index: index, title: chapter.title),
                            useMPS: useMPS,
                            modelID: VoiceCatalog.voice(id: current.voiceID)?.modelID
                        )
                    )
                    // The shelf may have changed while the engine was running.
                    guard let updated = books.firstIndex(where: { $0.id == bookID }),
                          books[updated].chapters.indices.contains(index) else { return }
                    books[updated].chapters[index].audioPath = output.url.path
                    refreshNarrationCounts()
                    // Saved after every chapter, so a crash or a quit costs at
                    // most the one that was in flight.
                    try await store.save(books)
                }
                let finished = books.first { $0.id == bookID }
                successMessage = finished?.isFullyNarrated == true
                    ? "\(book.title) is fully narrated."
                    : "Narration finished."
            } catch is CancellationError {
                return
            } catch BackendError.cancelled {
                return
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func cancelNarration() {
        narrationTask?.cancel()
        narrationTask = nil
        generator.cancel()
        progress = nil
    }

    /// Most voices run on the bundled engine; the rest name one model that has
    /// to be downloaded once. Saying so beats starting a run of 135 chapters
    /// that can only fail on the first.
    private func missingModelMessage(for voiceID: String) -> String? {
        guard let required = missingModelID(voiceID) else { return nil }
        let name = VoiceCatalog.voice(id: voiceID)?.name ?? voiceID
        return """
        \(name) speaks through the \(required) model. Open Models and download it \
        once, or pick another voice for this book.
        """
    }

    /// Numbered so the narrations folder sorts in reading order in Finder.
    private static func chapterFilename(index: Int, title: String) -> String {
        let clean = ExportService.safeFilename(title, maximumByteCount: 120)
        let number = String(format: "%03d", index + 1)
        return clean.isEmpty ? number : "\(number) \(clean)"
    }

    // MARK: - Editing

    func updateVoice(_ voiceID: String, for bookID: UUID) {
        update(bookID) { $0.voiceID = voiceID }
    }

    func updateSpeed(_ speed: Double, for bookID: UUID) {
        update(bookID) { $0.speed = speed }
    }

    func updateFormat(_ format: AudioFormat, for bookID: UUID) {
        update(bookID) { $0.audioFormat = format }
    }

    /// Narration already on disk was spoken with the old settings, so changing
    /// them clears it rather than leaving a book narrated in two voices.
    private func update(_ bookID: UUID, _ change: (inout BookRecord) -> Void) {
        guard let index = books.firstIndex(where: { $0.id == bookID }) else { return }
        let before = books[index]
        change(&books[index])
        guard books[index] != before else { return }
        if before.narratedCount > 0 {
            removeNarrations(for: bookID, chapters: before.chapters)
            for chapter in books[index].chapters.indices {
                books[index].chapters[chapter].audioPath = nil
            }
            refreshNarrationCounts()
        }
        persist()
    }

    // MARK: - Reading

    /// Marks the spot, or clears the mark that is already on it. Bookmarks and
    /// reading position are kept apart from the settings above: they say
    /// nothing about how the book sounds, so they never cost narration.
    func toggleBookmark(at location: ReadingLocation, excerpt: String, in bookID: UUID) {
        guard let index = books.firstIndex(where: { $0.id == bookID }) else { return }
        if let existing = books[index].bookmarks.firstIndex(where: { $0.location.isAt(location) }) {
            books[index].bookmarks.remove(at: existing)
        } else {
            books[index].bookmarks.append(Bookmark(location: location, excerpt: excerpt))
            books[index].bookmarks.sort { $0.location.precedes($1.location) }
        }
        persist()
    }

    func removeBookmark(_ bookmarkID: UUID, from bookID: UUID) {
        guard let index = books.firstIndex(where: { $0.id == bookID }) else { return }
        books[index].bookmarks.removeAll { $0.id == bookmarkID }
        persist()
    }

    /// Remembers where the reader stopped. Written when they change chapter or
    /// close the book rather than on every line they scroll past, so following
    /// a long chapter does not mean rewriting the shelf hundreds of times.
    func updateReadingLocation(_ location: ReadingLocation, for bookID: UUID) {
        guard let index = books.firstIndex(where: { $0.id == bookID }),
              books[index].lastLocation != location else { return }
        books[index].lastLocation = location
        persist()
    }

    // MARK: - Removing

    func remove(_ bookID: UUID) {
        guard let index = books.firstIndex(where: { $0.id == bookID }) else { return }
        if progress?.bookID == bookID { cancelNarration() }
        let book = books.remove(at: index)
        try? FileManager.default.removeItem(at: book.sourceURL)
        removeNarrations(for: bookID, chapters: book.chapters)
        covers.forget(bookID)
        narratedCounts.removeValue(forKey: bookID)
        persist()
        successMessage = "Removed \(book.title) from your library."
    }

    /// Chapter audio is written to the same path every time it is generated,
    /// so anything Atten measured about the old file would otherwise be handed
    /// back for the new one.
    private func removeNarrations(for bookID: UUID, chapters: [BookChapter]) {
        for url in chapters.compactMap(\.audioURL) {
            AudioMetadataStore.shared.forget(url)
        }
        try? FileManager.default.removeItem(
            at: directories.narrations.appendingPathComponent(bookID.uuidString, isDirectory: true)
        )
    }

    private func persist() {
        let snapshot = books
        Task { [weak self] in
            do {
                try await self?.store.save(snapshot)
            } catch {
                self?.errorMessage = "Your library could not be saved: \(error.localizedDescription)"
            }
        }
    }

    func dismissStatus() {
        errorMessage = nil
        successMessage = nil
    }
}
