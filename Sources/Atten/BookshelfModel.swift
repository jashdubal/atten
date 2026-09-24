import AVFoundation
import AttenCore
import Foundation
import Observation

/// The views available in the Library shelf. These are intentionally derived
/// from the records Atten already owns: an audiobook is a book with at least
/// one narration on disk, and Recently Added is the import date, not a made-up
/// folder or category.
enum LibraryFilter: String, CaseIterable, Identifiable, Sendable {
    case books
    case audiobooks
    case recentlyAdded

    var id: Self { self }

    var title: String {
        switch self {
        case .books: "Books"
        case .audiobooks: "Audiobooks"
        case .recentlyAdded: "Recently Added"
        }
    }

    var systemImage: String {
        switch self {
        case .books: "books.vertical"
        case .audiobooks: "headphones"
        case .recentlyAdded: "clock"
        }
    }
}

/// Presentation order only; records and their persisted import order are unchanged.
enum LibrarySort: String, CaseIterable, Identifiable {
    case recentlyAdded = "Recently added"
    case title = "Title"
    case author = "Author"

    var id: Self { self }

    func sorted(_ books: [BookRecord]) -> [BookRecord] {
        books.sorted { lhs, rhs in
            switch self {
            case .recentlyAdded:
                if lhs.addedAt != rhs.addedAt { return lhs.addedAt > rhs.addedAt }
            case .title:
                let comparison = lhs.title.localizedStandardCompare(rhs.title)
                if comparison != .orderedSame { return comparison == .orderedAscending }
            case .author:
                let comparison = (lhs.author ?? "Unknown author")
                    .localizedStandardCompare(rhs.author ?? "Unknown author")
                if comparison != .orderedSame { return comparison == .orderedAscending }
                let titleComparison = lhs.title.localizedStandardCompare(rhs.title)
                if titleComparison != .orderedSame { return titleComparison == .orderedAscending }
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}

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
        var eta: String = "Estimating time remaining…"
        var isCombining: Bool = false
        /// Words of the current chapter the engine has finished speaking, so
        /// Create can show narration reaching through the text.
        var spokenWords = 0

        var fraction: Double { total > 0 ? min(0.95, Double(completed) / Double(total) * 0.95) : 0 }
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
    var cancelledMessage: String?
    /// Per-operation messages keep an import completion from hiding a
    /// narration failure (and vice versa) when both run at once.
    var importErrorMessage: String?
    var importSuccessMessage: String?
    var narrationErrorMessage: String?
    var narrationSuccessMessage: String?

    @ObservationIgnored private let directories: AppDirectories
    @ObservationIgnored private let store: BookLibraryStore
    let synthesis: SynthesisCoordinator
    let covers: BookCoverStore
    typealias AudioAssembler = @Sendable ([URL], URL) throws -> BookAudioAssembler.Result
    @ObservationIgnored private let assembleAudio: AudioAssembler
    @ObservationIgnored private let generator: any TTSGenerating
    @ObservationIgnored private var narrationTask: Task<Void, Never>?
    @ObservationIgnored private var pendingSave: Task<Void, Error>?
    /// Answers with the model a voice still needs, or nil when it can speak
    /// now. Only the app model knows which models are installed.
    @ObservationIgnored var missingModelID: (String) -> String? = { _ in nil }
    @ObservationIgnored var isAudioInUse: (URL) -> Bool = { _ in false }
    /// Called with each segment as soon as its audio is on disk: book id,
    /// chapter index, segment. Progressive playback during generation (P5)
    /// attaches here.
    @ObservationIgnored var onSegmentReady: ((UUID, Int, SegmentReady) -> Void)?
    /// Called once a narration has been published as one recording.
    @ObservationIgnored var onNarrationFinished: ((NarrationRun) -> Void)?
    @ObservationIgnored private var retiredAudio: Set<URL> = []

    init(directories: AppDirectories, generator: any TTSGenerating,
         synthesis: SynthesisCoordinator = SynthesisCoordinator(),
         assembler: @escaping AudioAssembler = { try BookAudioAssembler.assemble($0, in: $1) }) {
        self.assembleAudio = assembler
        self.synthesis = synthesis
        self.directories = directories
        self.store = BookLibraryStore(fileURL: directories.booksFile)
        self.covers = BookCoverStore(
            directory: directories.bookSources.appendingPathComponent("Covers", isDirectory: true)
        )
        self.generator = generator
    }

    /// What one completed narration took, for calibrating estimates. Counts
    /// only the chapters generated in this run, so a resumed book does not
    /// credit the engine with audio it made on an earlier day.
    struct NarrationRun: Equatable {
        let bookID: UUID
        let voiceID: String
        let words: Int
        let audioSeconds: TimeInterval
        let wallSeconds: TimeInterval
    }

    var isNarrating: Bool { progress != nil }

    func book(id: UUID) -> BookRecord? { books.first { $0.id == id } }

    func narratedCount(of book: BookRecord) -> Int {
        narratedCounts[book.id] ?? 0
    }

    /// Applies the shelf filter and the Library search in one place so their
    /// combinations remain truthful. In particular, Audiobooks is based on
    /// narration files that still exist, rather than a book's file format.
    func filteredBooks(for filter: LibraryFilter, query: String = "") -> [BookRecord] {
        let candidates: [BookRecord]
        switch filter {
        case .books:
            candidates = books
        case .audiobooks:
            candidates = books.filter { narratedCount(of: $0) > 0 }
        case .recentlyAdded:
            candidates = books.sorted { lhs, rhs in
                if lhs.addedAt == rhs.addedAt { return lhs.id.uuidString < rhs.id.uuidString }
                return lhs.addedAt > rhs.addedAt
            }
        }

        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return candidates }
        return candidates.filter { book in
            let searchableText = ([
                book.title,
                book.author,
                book.format.displayName,
                book.format.rawValue,
            ] + book.chapters.map(\.title))
                .compactMap { $0 }
                .joined(separator: " ")
            return searchableText.localizedCaseInsensitiveContains(term)
        }
    }

    /// `filteredBooks(for:query:)` plus the shelf's sort order, in one place
    /// so the Library view and its tests agree on the combination — in
    /// particular that Recently Added, already newest-first, is never
    /// re-sorted underneath itself.
    func books(for filter: LibraryFilter, query: String = "", sort: LibrarySort) -> [BookRecord] {
        let candidates = filteredBooks(for: filter, query: query)
        guard filter != .recentlyAdded else { return candidates }
        return sort.sorted(candidates)
    }

    func isFullyNarrated(_ book: BookRecord) -> Bool {
        book.hasBookAudio && !book.needsPreparation
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
            let loaded = try await store.load().sorted { $0.addedAt > $1.addedAt }
            books = await Task.detached(priority: .utility) {
                loaded.map { original in
                    var book = original
                    let urls = Set(book.chapters.compactMap(\.audioURL) + [book.audioURL].compactMap { $0 })
                    var invalid: Set<URL> = []
                    for url in urls {
                        guard let audio = try? AVAudioFile(forReading: url), audio.length > 0 else {
                            invalid.insert(url); continue
                        }
                        if url == book.audioURL,
                           let end = book.playbackChapters.last?.endTime,
                           abs(end - Double(audio.length) / audio.processingFormat.sampleRate) > 0.1 {
                            invalid.insert(url)
                        }
                    }
                    if let url = book.audioURL, invalid.contains(url) {
                        book.audioPath = nil
                        book.previousChapters = nil
                    }
                    for index in book.chapters.indices {
                        if let url = book.chapters[index].audioURL, invalid.contains(url) {
                            book.chapters[index].audioPath = nil
                            book.chapters[index].startTime = nil
                            book.chapters[index].endTime = nil
                        }
                    }
                    if !invalid.isEmpty {
                        book.narrationState = .failed
                        book.narrationFailure = "Some audio is missing or unreadable. Prepare again to repair it."
                    }
                    return book
                }
            }.value
            refreshNarrationCounts()
            if let recovered = await store.recoveredFileURL {
                errorMessage = "Some library records could not be read. The original is preserved at \(recovered.path)."
            }
            // Interrupted preparation is resumed only by an explicit user action.
        } catch {
            errorMessage = "Atten could not read your library: \(error.localizedDescription)"
        }
    }

    // MARK: - Import

    /// What importing a book produced. `.alreadyInLibrary` means nothing was
    /// added — the shelf already has this text under some book, which may
    /// have a different title, author or file name.
    enum ImportResult: Equatable {
        case imported(BookRecord)
        case alreadyInLibrary(UUID)
    }

    /// Copies the book into Atten's own library folder and reads it into
    /// chapters. Extraction walks every page, so it runs off the main actor.
    @discardableResult
    func importBook(from url: URL, defaults: AppSettings) async -> ImportResult? {
        guard !isImporting else { return nil }
        errorMessage = nil
        successMessage = nil
        cancelledMessage = nil
        importErrorMessage = nil
        importSuccessMessage = nil
        isImporting = true
        defer { isImporting = false }

        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        guard let format = BookFormat.resolve(for: url) else {
            importErrorMessage = DocumentImportError
                .unsupportedFormat(url.pathExtension)
                .localizedDescription
            errorMessage = importErrorMessage
            return nil
        }

        do {
            let sourceDirectory = directories.bookSources
            let destination = try await Task.detached(priority: .userInitiated) {
                try Self.copyIntoLibrary(url, directory: sourceDirectory)
            }.value
            let bookID = UUID()
            do {
                let document = try await Task.detached(priority: .userInitiated) {
                    try DocumentImporter.extract(from: destination)
                }.value
                let hash = ContentHash.of(document.chapters.map(\.text).joined(separator: "\n"))
                if let existingID = existingBook(withContentHash: hash) {
                    // The text is already on the shelf, so the copy just made
                    // was only ever temporary — discard it rather than
                    // leaving a second file no book record points to.
                    try? FileManager.default.removeItem(at: destination)
                    let existingTitle = book(id: existingID)?.title ?? document.title
                    importSuccessMessage = "\(existingTitle) is already in your library."
                    successMessage = importSuccessMessage
                    return .alreadyInLibrary(existingID)
                }
                let book = BookRecord(
                    id: bookID,
                    title: document.title,
                    author: document.author,
                    format: format,
                    sourcePath: destination.path,
                    chapters: document.chapters.map {
                        BookChapter(title: $0.title, text: $0.text, pageIndex: $0.pageIndex)
                    },
                    voiceID: defaults.selectedVoiceID,
                    speed: defaults.defaultSpeed,
                    audioFormat: defaults.defaultFormat,
                    contentHash: hash
                )
                books.insert(book, at: 0)
                refreshNarrationCounts()
                try await saveNow()
                importSuccessMessage = "Added \(book.title) — \(book.chapters.count) \(book.chapters.count == 1 ? "chapter" : "chapters")."
                successMessage = importSuccessMessage
                return .imported(book)
            } catch {
                // Roll back the visible import if its metadata could not be committed.
                books.removeAll { $0.id == bookID }
                refreshNarrationCounts()
                persist()
                try? FileManager.default.removeItem(at: destination)
                throw error
            }
        } catch {
            importErrorMessage = error.localizedDescription
            errorMessage = importErrorMessage
            return nil
        }
    }

    /// The id of a book already on the shelf with this content hash, if any.
    /// A book saved before hashes existed has none stored, so it is computed
    /// here and kept on the in-memory record — not written back to
    /// `books.json` just for this, only when the book is next saved anyway.
    private func existingBook(withContentHash hash: String) -> UUID? {
        for index in books.indices {
            let existing: String
            if let stored = books[index].contentHash {
                existing = stored
            } else {
                existing = ContentHash.of(books[index].chapters.map(\.text).joined(separator: "\n"))
                books[index].contentHash = existing
            }
            if existing == hash { return books[index].id }
        }
        return nil
    }

    private nonisolated static func copyIntoLibrary(_ url: URL, directory: URL) throws -> URL {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let base = ExportService.safeFilename(url.deletingPathExtension().lastPathComponent)
        let name = base.isEmpty ? "Book" : base
        var destination = directory
            .appendingPathComponent(name)
            .appendingPathExtension(url.pathExtension)
        var counter = 2
        while FileManager.default.fileExists(atPath: destination.path) {
            destination = directory
                .appendingPathComponent("\(name) \(counter)")
                .appendingPathExtension(url.pathExtension)
            counter += 1
        }
        try FileManager.default.copyItem(at: url, to: destination)
        return destination
    }

    // MARK: - Drafts

    /// Saves Create-flow text as a silent (not yet narrated) book, so
    /// generation can reuse `narrate` — checkpointing, resuming, and
    /// continuing if the view is left — instead of a separate draft path.
    /// Passing the id of an existing draft updates it in place; removing a
    /// draft is `remove(_:)`, which already deletes only that one book's own
    /// source file.
    ///
    /// `chapters`, when given, is how the text is divided for narration;
    /// without it a draft is one chapter. Chapters whose text has not changed
    /// are kept as they are, so narration that was stopped resumes.
    @discardableResult
    func saveDraft(
        id: UUID? = nil,
        title: String,
        text: String,
        voiceID: String,
        defaults: AppSettings,
        chapters: [DocumentChapter]? = nil
    ) throws -> BookRecord {
        let resolvedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = resolvedTitle.isEmpty ? "Untitled" : resolvedTitle
        let bookID = id ?? UUID()
        let existingIndex = books.firstIndex { $0.id == bookID }

        try FileManager.default.createDirectory(at: directories.bookSources, withIntermediateDirectories: true)
        let destination = directories.bookSources.appendingPathComponent("\(bookID.uuidString).txt")
        try text.write(to: destination, atomically: true, encoding: .utf8)

        let hash = ContentHash.of(text)
        let draft: BookRecord
        if let existingIndex {
            // Update in place so narration, bookmarks and listening position
            // survive an autosave; only what the writer controls changes.
            var updated = books[existingIndex]
            updated.title = displayTitle
            updated.sourcePath = destination.path
            updated.voiceID = voiceID
            if let chapters {
                if updated.chapters.map(\.text) != chapters.map(\.text) {
                    updated.chapters = chapters.map { BookChapter(title: $0.title, text: $0.text) }
                }
            } else if updated.chapters.count == 1 {
                updated.chapters[0].title = displayTitle
                updated.chapters[0].text = text
            } else {
                updated.chapters = [BookChapter(title: displayTitle, text: text)]
            }
            updated.contentHash = hash
            books[existingIndex] = updated
            draft = updated
        } else {
            // New narration always generates at 1.0×; listening speed belongs
            // to the player.
            var created = BookRecord(
                id: bookID,
                title: displayTitle,
                format: .document,
                sourcePath: destination.path,
                chapters: chapters?.map { BookChapter(title: $0.title, text: $0.text) }
                    ?? [BookChapter(title: displayTitle, text: text)],
                voiceID: voiceID,
                speed: 1.0,
                audioFormat: defaults.defaultFormat
            )
            created.contentHash = hash
            books.insert(created, at: 0)
            draft = created
        }
        refreshNarrationCounts()
        persist()
        return draft
    }

    // MARK: - Narration

    /// Resumes chapter checkpoints, then publishes one recording for the book.
    /// A request from any chapter prepares the whole audiobook.
    func narrate(_ bookID: UUID, chapters requested: [Int]? = nil, useMPS: Bool) {
        guard narrationTask == nil, let book = book(id: bookID) else { return }
        let pending = Array(book.chapters.indices)
            .filter { book.chapters.indices.contains($0) && !book.chapters[$0].isNarrated }
        guard (!book.hasBookAudio || book.needsPreparation), !book.chapters.isEmpty else { return }

        if !pending.isEmpty, let missing = missingModelMessage(for: book.voiceID) {
            errorMessage = missing
            return
        }

        guard let lease = synthesis.acquire("Preparing “\(book.title)”") else {
            errorMessage = "Wait for \(synthesis.activity ?? "the current task") to finish, or stop it first."
            return
        }
        setNarrationState(.preparing, for: bookID)
        errorMessage = nil
        successMessage = nil
        cancelledMessage = nil
        narrationErrorMessage = nil
        narrationSuccessMessage = nil
        let directory = directories.narrations
            .appendingPathComponent(bookID.uuidString, isDirectory: true)
        progress = NarrationProgress(
            bookID: bookID,
            chapterID: book.chapters[pending.first ?? 0].id,
            chapterTitle: book.chapters[pending.first ?? 0].title,
            completed: book.narratedCount,
            total: book.chapters.count
        )

        narrationTask = Task { [weak self] in
            guard let self else { return }
            defer {
                synthesis.release(lease)
                narrationTask = nil
                progress = nil
            }
            do {
                try FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true
                )
                let started = Date()
                var generatedWords = 0
                var generatedSeconds = 0.0
                var completedWords = 0
                let totalWords = pending.reduce(0) { $0 + book.chapters[$1].text.count }
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
                    if completedWords > 0 {
                        let remaining = Date().timeIntervalSince(started) * Double(totalWords - completedWords) / Double(completedWords)
                        progress?.eta = "About \(max(1, Int(ceil(remaining / 60)))) min remaining"
                    }
                    let chapterDirectory = directory.appendingPathComponent(
                        "chapter-\(index)-\(UUID().uuidString)", isDirectory: true
                    )
                    var checkpointed = false
                    defer {
                        if !checkpointed { try? FileManager.default.removeItem(at: chapterDirectory) }
                    }
                    // Segment WAVs only matter while the chapter is being made; the
                    // chapter file holds the same audio once it is checkpointed.
                    let segmentsDirectory = chapterDirectory.appendingPathComponent("segments", isDirectory: true)
                    var segments: [TimedSegment] = []
                    var audioURL: URL?
                    let events = generator.generateStream(
                        GenerationRequest(
                            text: chapter.text,
                            voiceID: current.voiceID,
                            speed: current.speed,
                            format: current.audioFormat,
                            outputDirectory: chapterDirectory,
                            filename: Self.chapterFilename(index: index, title: chapter.title),
                            useMPS: useMPS,
                            modelID: VoiceCatalog.voice(id: current.voiceID)?.modelID,
                            segmentsDirectory: segmentsDirectory
                        )
                    )
                    for try await event in events {
                        try Task.checkCancellation()
                        switch event {
                        case let .segment(segment):
                            segments.append(segment.timing.estimatingMissingWords())
                            progress?.spokenWords += segment.timing.text.split(whereSeparator: \.isWhitespace).count
                            onSegmentReady?(bookID, index, segment)
                        case let .completed(url): audioURL = url
                        case .failed, .progress: break
                        }
                    }
                    try Task.checkCancellation()
                    guard let audioURL else { throw BackendError.malformedResponse }
                    if segments.isEmpty {
                        let audio = try AVAudioFile(forReading: audioURL)
                        segments = [TimedSegment(index: 0, text: chapter.text, start: 0,
                            duration: Double(audio.length) / audio.processingFormat.sampleRate, words: [])
                            .estimatingMissingWords()]
                    }
                    try NarrationTimings(segments: segments).save(beside: audioURL)
                    try Task.checkCancellation()
                    completedWords += chapter.text.count
                    generatedWords += chapter.text.split(whereSeparator: \.isWhitespace).count
                    generatedSeconds += segments.last.map { $0.start + $0.duration } ?? 0
                    // The shelf may have changed while the engine was running.
                    guard let updated = books.firstIndex(where: { $0.id == bookID }),
                          books[updated].chapters.indices.contains(index) else { return }
                    books[updated].chapters[index].audioPath = audioURL.path
                    refreshNarrationCounts()
                    // Saved after every chapter, so a crash or a quit costs at
                    // most the one that was in flight.
                    checkpointed = true
                    try await saveNow()
                    try? FileManager.default.removeItem(at: segmentsDirectory)
                }
                try Task.checkCancellation()
                let run = NarrationRun(
                    bookID: bookID,
                    voiceID: book.voiceID,
                    words: generatedWords,
                    audioSeconds: generatedSeconds,
                    wallSeconds: Date().timeIntervalSince(started)
                )
                guard let snapshot = self.book(id: bookID), snapshot.isFullyNarrated else { return }
                setNarrationState(.finalizing, for: bookID)
                progress = NarrationProgress(
                    bookID: bookID,
                    chapterID: snapshot.chapters[0].id,
                    chapterTitle: "Preparing audiobook",
                    completed: snapshot.chapters.count,
                    total: snapshot.chapters.count,
                    eta: "Finishing the book audio…",
                    isCombining: true
                )
                let assemble = assembleAudio
                let assembly = Task.detached(priority: .userInitiated) {
                    try assemble(snapshot.chapters.compactMap(\.audioURL), directory)
                }
                let result = try await withTaskCancellationHandler {
                    try await assembly.value
                } onCancel: {
                    assembly.cancel()
                }
                var committed = false
                defer { if !committed { Self.removeRecording(at: result.url) } }
                try Task.checkCancellation()
                guard result.ranges.count == snapshot.chapters.count else { throw CocoaError(.fileReadCorruptFile) }
                guard let position = books.firstIndex(where: { $0.id == bookID }) else { return }
                let previous = books[position]
                books[position].audioPath = result.url.path
                books[position].previousChapters = nil
                books[position].needsPreparation = false
                books[position].narrationState = .ready
                books[position].narrationFailure = nil
                books[position].listeningPosition = 0
                for index in books[position].chapters.indices {
                    books[position].chapters[index].audioPath = result.url.path
                    books[position].chapters[index].startTime = result.ranges[index].0
                    books[position].chapters[index].endTime = result.ranges[index].1
                }
                do { try await saveNow() }
                catch {
                    if let index = books.firstIndex(where: { $0.id == bookID }) {
                        books[index].audioPath = previous.audioPath
                        books[index].chapters = previous.chapters
                        books[index].previousChapters = previous.previousChapters
                        books[index].needsPreparation = previous.needsPreparation
                        books[index].listeningPosition = previous.listeningPosition
                    }
                    Self.removeRecording(at: result.url)
                    throw error
                }
                committed = true
                let obsolete = snapshot.chapters.compactMap(\.audioURL) + [previous.audioURL].compactMap { $0 }
                for url in Set(obsolete) where url != result.url {
                    retiredAudio.insert(url)
                }
                cleanRetiredAudio()
                refreshNarrationCounts()
                let finished = books.first { $0.id == bookID }
                narrationSuccessMessage = finished?.isFullyNarrated == true
                    ? "\(book.title) is fully narrated."
                    : "Narration finished."
                successMessage = narrationSuccessMessage
                onNarrationFinished?(run)
            } catch is CancellationError {
                setNarrationState(.interrupted, for: bookID)
            } catch BackendError.cancelled {
                setNarrationState(.interrupted, for: bookID)
            } catch {
                setNarrationState(.failed, for: bookID, failure: error.localizedDescription)
                narrationErrorMessage = error.localizedDescription
                errorMessage = narrationErrorMessage
            }
        }
    }

    func cancelNarration() {
        if let current = progress, let book = book(id: current.bookID) {
            cancelledMessage = "Narration cancelled for \(book.title). \(current.completed) of \(current.total) chapters saved. Resume to finish the audiobook."
        }
        narrationTask?.cancel()
        generator.cancel()
    }

    /// Most voices run on the bundled engine; the rest name one model that has
    /// to be downloaded once. Saying so beats starting a run of 135 chapters
    /// that can only fail on the first.
    private func missingModelMessage(for voiceID: String) -> String? {
        guard let required = missingModelID(voiceID) else { return nil }
        let name = VoiceCatalog.voice(id: voiceID)?.name ?? voiceID
        return """
        \(name) speaks through the \(required) model. Open Settings → Models and download it \
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
        guard progress?.bookID != bookID, let index = books.firstIndex(where: { $0.id == bookID }) else { return }
        let before = books[index]
        change(&books[index])
        guard books[index] != before else { return }
        if before.narratedCount > 0 || before.hasBookAudio {
            if before.hasBookAudio, books[index].previousChapters == nil {
                books[index].previousChapters = before.chapters
            }
            books[index].needsPreparation = true
            books[index].narrationState = .unprepared
            for chapter in books[index].chapters.indices {
                books[index].chapters[chapter].startTime = nil
                books[index].chapters[chapter].endTime = nil
                books[index].chapters[chapter].audioPath = nil
            }
            refreshNarrationCounts()
        }
        persist()
    }

    func cleanRetiredAudio() {
        for url in retiredAudio where !isAudioInUse(url) {
            do {
                if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
                Self.removeRecordingFolder(containing: url)
                retiredAudio.remove(url)
            } catch {
                // Retry cleanup after the next playback change.
            }
        }
    }

    /// Chapter and book recordings each live in a folder of their own, next to
    /// their `timings.json`; removing the audio should not strand the rest.
    static func removeRecording(at url: URL) {
        try? FileManager.default.removeItem(at: url)
        removeRecordingFolder(containing: url)
    }

    static func removeRecordingFolder(containing url: URL) {
        let folder = url.deletingLastPathComponent()
        let name = folder.lastPathComponent
        guard name.hasPrefix("chapter-") || name.hasPrefix("Audiobook-") else { return }
        try? FileManager.default.removeItem(at: folder)
    }

    private func setNarrationState(_ state: NarrationState, for id: UUID, failure: String? = nil) {
        guard let index = books.firstIndex(where: { $0.id == id }) else { return }
        books[index].narrationState = state
        books[index].narrationFailure = failure
        persist()
    }

    func saveListeningPosition(_ position: Double, for id: UUID) {
        guard position.isFinite, let index = books.firstIndex(where: { $0.id == id }) else { return }
        books[index].listeningPosition = max(0, position)
        books[index].lastListenedAt = Date()
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

    /// Notes that the book was just opened, which is the only recency signal
    /// Atten has. Written on open rather than on close, because a reader who
    /// quits mid-chapter never gets to close anything.
    func markOpened(_ bookID: UUID, at date: Date = Date()) {
        guard let index = books.firstIndex(where: { $0.id == bookID }) else { return }
        books[index].lastOpenedAt = date
        persist()
    }

    /// The books someone has actually opened, most recent first. A book that
    /// has never been opened is not "recent" at any age, so it is left out
    /// rather than sorted to the bottom.
    var recentlyOpened: [BookRecord] {
        books
            .compactMap { book in book.lastOpenedAt.map { (book, $0) } }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
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
        importErrorMessage = nil
        importSuccessMessage = nil
        narrationErrorMessage = nil
        narrationSuccessMessage = nil
        let book = books.remove(at: index)
        try? FileManager.default.removeItem(at: book.sourceURL)
        removeNarrations(for: bookID, chapters: book.chapters)
        covers.forget(bookID)
        narratedCounts.removeValue(forKey: bookID)
        persist()
        successMessage = "Removed \(book.title) from your library."
    }

    /// Takes a book back to silent: its narration is deleted and its text is
    /// kept. This is Undo for a narration someone did not want.
    func removeNarration(_ bookID: UUID) {
        guard progress?.bookID != bookID, let index = books.firstIndex(where: { $0.id == bookID }) else { return }
        removeNarrations(for: bookID, chapters: books[index].chapters + (books[index].previousChapters ?? []))
        if let audioURL = books[index].audioURL { AudioMetadataStore.shared.forget(audioURL) }
        books[index].audioPath = nil
        books[index].previousChapters = nil
        books[index].needsPreparation = false
        books[index].narrationState = .unprepared
        books[index].narrationFailure = nil
        books[index].listeningPosition = 0
        books[index].lastListenedAt = nil
        for chapter in books[index].chapters.indices {
            books[index].chapters[chapter].audioPath = nil
            books[index].chapters[chapter].startTime = nil
            books[index].chapters[chapter].endTime = nil
        }
        refreshNarrationCounts()
        persist()
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

    private func enqueueSave() -> Task<Void, Error> {
        let snapshot = books
        let previous = pendingSave
        let store = store
        let task = Task {
            // A later successful save may recover from an earlier failure.
            _ = try? await previous?.value
            try await store.save(snapshot)
        }
        pendingSave = task
        return task
    }

    private func saveNow() async throws {
        try await enqueueSave().value
    }

    func flushPersistence() async throws {
        try await pendingSave?.value
    }

    func stopAndSave() async throws {
        cancelNarration()
        await narrationTask?.value
        try await flushPersistence()
    }

    private func persist() {
        let task = enqueueSave()
        Task { [weak self] in
            do { try await task.value }
            catch { self?.errorMessage = "Your library could not be saved: \(error.localizedDescription)" }
        }
    }

    func dismissStatus() {
        errorMessage = nil
        successMessage = nil
        cancelledMessage = nil
        importErrorMessage = nil
        importSuccessMessage = nil
        narrationErrorMessage = nil
        narrationSuccessMessage = nil
    }
}
