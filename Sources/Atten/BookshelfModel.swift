import AVFoundation
import AttenCore
import Foundation
import Observation

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

    /// An import that turned out to already be on the shelf, under whatever
    /// title it was first added as. A struct rather than a bare `UUID` so
    /// importing the same duplicate twice in a row is still a change the
    /// Library's dedupe toast can observe.
    struct DuplicateImportEvent: Equatable {
        private let token = UUID()
        let bookID: UUID
    }

    private(set) var books: [BookRecord] = [] {
        didSet { shelfQueryCache = nil }
    }
    private(set) var progress: NarrationProgress?
    /// Narrations in the order they take the engine, the running one
    /// included until it ends.
    private(set) var queue: [QueuedNarration] = []
    private(set) var isImporting = false
    private(set) var duplicateImport: DuplicateImportEvent?
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
    @ObservationIgnored let positions: ListeningPositionStore
    /// Position changes reach the store in the order they were made.
    @ObservationIgnored private var positionUpdate: Task<Void, Never>?
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
    /// Called when a narration task ends, however it ends — finished,
    /// cancelled, or failed — so anything following it (progressive
    /// playback) can let go.
    @ObservationIgnored var onNarrationEnded: ((UUID) -> Void)?
    /// The app's calibrated estimates, for time remaining.
    @ObservationIgnored var listenEstimator: () -> ListenEstimator = { ListenEstimator() }
    @ObservationIgnored private var retiredAudio: Set<URL> = []
    /// Set on quit, so the narration being stopped keeps its place in the
    /// queue and nothing after it starts.
    @ObservationIgnored private var isShuttingDown = false
    /// The last answer `books(for:query:sort:)` gave. The Library asks the
    /// same question more than once per draw, and again on every progress
    /// tick while a book narrates; at a thousand books the search and the
    /// localized sort cost tens of milliseconds on the main actor each time.
    @ObservationIgnored private var shelfQueryCache: (key: String, books: [BookRecord])?

    init(directories: AppDirectories, generator: any TTSGenerating,
         synthesis: SynthesisCoordinator = SynthesisCoordinator(),
         assembler: @escaping AudioAssembler = { try BookAudioAssembler.assemble($0, in: $1) },
         positionClock: ListeningPositionStore.Clock = .system) {
        self.assembleAudio = assembler
        self.synthesis = synthesis
        self.directories = directories
        self.store = BookLibraryStore(fileURL: directories.booksFile)
        self.positions = ListeningPositionStore(fileURL: directories.positionsFile, clock: positionClock)
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
    /// combinations remain truthful. The filter itself is `LibraryItem`'s —
    /// the same one the Library's chips and its dedupe toast use — applied to
    /// each book wrapped as a `LibraryItem` so a book's drafts/audiobooks
    /// state is decided in exactly one place.
    func filteredBooks(for filter: AttenCore.LibraryItemFilter, query: String = "") -> [BookRecord] {
        let candidates = books.filter { AttenCore.LibraryItem.filter([.book($0)], by: filter).count == 1 }

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
    /// so the Library view and its tests agree on the combination.
    func books(for filter: AttenCore.LibraryItemFilter, query: String = "", sort: LibrarySort) -> [BookRecord] {
        // Reading `books` before the cache keeps a view that asks observing
        // the shelf, even when the answer comes from the cache.
        guard !books.isEmpty else { return [] }
        let key = "\(filter.rawValue)\u{0}\(sort.rawValue)\u{0}\(query)"
        if let cached = shelfQueryCache, cached.key == key { return cached.books }
        let result = sort.sorted(filteredBooks(for: filter, query: query))
        shelfQueryCache = (key, result)
        return result
    }

    func isFullyNarrated(_ book: BookRecord) -> Bool {
        book.hasBookAudio && !book.needsPreparation
    }

    /// Recounts from the file system. Called when the shelf changes, and again
    /// when the Library is opened, so narration deleted in Finder while Atten
    /// was on another screen does not leave a play button that does nothing.
    func refreshNarrationCounts() {
        // Once a book is one recording, every chapter points at that one
        // file, so each file is asked about once rather than once a chapter.
        var onDisk: [String: Bool] = [:]
        func exists(_ path: String) -> Bool {
            if let known = onDisk[path] { return known }
            let found = FileManager.default.fileExists(atPath: path)
            onDisk[path] = found
            return found
        }
        narratedCounts = Dictionary(
            books.map { book in (book.id, book.chapters.count { $0.audioPath.map(exists) ?? false }) },
            uniquingKeysWith: { first, _ in first }
        )
        // Which books count as audiobooks rests on the same files.
        shelfQueryCache = nil
    }

    func load() async {
        do {
            let saved = await positions.load()
            let loaded = try await store.load().sorted { $0.addedAt > $1.addedAt }
                .map { var book = $0; book.adopt(saved[book.id]); return book }
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
            restoreQueue()
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
                    duplicateImport = DuplicateImportEvent(bookID: existingID)
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
        chapters: [DocumentChapter]? = nil,
        pronunciations: [Pronunciation] = [],
        pauseLength: PauseLength = .normal
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
            let spoken = (pronunciations.isEmpty ? nil : pronunciations, pauseLength == .normal ? nil : pauseLength)
            if spoken != (updated.pronunciations, updated.pauseLength) {
                // Chapters already narrated were spoken the old way.
                updated.chapters = updated.chapters.map { BookChapter(title: $0.title, text: $0.text) }
                (updated.pronunciations, updated.pauseLength) = spoken
            }
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
            created.pronunciations = pronunciations.isEmpty ? nil : pronunciations
            created.pauseLength = pauseLength == .normal ? nil : pauseLength
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
    /// While another book is narrating, this one joins the queue instead.
    func narrate(_ bookID: UUID, chapters requested: [Int]? = nil, useMPS: Bool) {
        if narrationTask != nil {
            enqueue(bookID, useMPS: useMPS)
            return
        }
        guard let book = book(id: bookID) else { return }
        let pending = Array(book.chapters.indices)
            .filter { book.chapters.indices.contains($0) && !book.chapters[$0].isNarrated }
        guard (!book.hasBookAudio || book.needsPreparation), !book.chapters.isEmpty else { return }

        // Saying so beats starting a run of 135 chapters that can only fail
        // on the first. The narrator card offers the download.
        if !pending.isEmpty, missingModelID(book.voiceID) != nil {
            errorMessage = "Voice needs download"
            return
        }

        guard let lease = synthesis.acquire("Preparing “\(book.title)”") else {
            errorMessage = "Wait for \(synthesis.activity ?? "the current task") to finish, or stop it first."
            return
        }
        admit(bookID, useMPS: useMPS)
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
                onNarrationEnded?(bookID)
                narrationEnded(bookID)
            }
            do {
                try FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true
                )
                let started = Date()
                var generatedWords = 0
                var generatedSeconds = 0.0
                for index in pending {
                    try Task.checkCancellation()
                    // Pausing waits for a chapter boundary, so every chapter
                    // finished so far is kept.
                    if isPaused(bookID) {
                        setNarrationState(.interrupted, for: bookID)
                        return
                    }
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
                    var pronounced = PronouncedText(chapter.text, pronunciations: current.pronunciations ?? [])
                    let events = generator.generateStream(
                        GenerationRequest(
                            text: pronounced.spoken,
                            voiceID: current.voiceID,
                            speed: current.speed,
                            format: current.audioFormat,
                            outputDirectory: chapterDirectory,
                            filename: Self.chapterFilename(index: index, title: chapter.title),
                            useMPS: useMPS,
                            modelID: VoiceCatalog.voice(id: current.voiceID)?.modelID,
                            segmentsDirectory: segmentsDirectory,
                            pauseLength: current.pauseLength
                        )
                    )
                    for try await event in events {
                        try Task.checkCancellation()
                        switch event {
                        case let .segment(spoken):
                            let segment = SegmentReady(url: spoken.url, timing: pronounced.restore(spoken.timing))
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
                updatePositions { await $0.forget(bookID) }
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

    // MARK: - Queue

    /// The book narrating now, if any.
    var narratingBookID: UUID? { progress?.bookID }

    /// Waiting for the engine or paused, but not running.
    func isQueued(_ bookID: UUID) -> Bool {
        narratingBookID != bookID && queue.contains { $0.bookID == bookID }
    }

    func isPaused(_ bookID: UUID) -> Bool {
        queue.first { $0.bookID == bookID }?.isPaused == true
    }

    /// Narration can be asked for when the engine is free, or when what holds
    /// it is another narration the request can queue behind.
    var canStartNarration: Bool { !synthesis.isBusy || narrationTask != nil }

    /// A running narration finishes the chapter it is on, then stops.
    func pauseNarration(_ bookID: UUID) {
        guard let index = queue.firstIndex(where: { $0.bookID == bookID }) else { return }
        queue[index].isPaused = true
        saveQueue()
    }

    func resumeNarration(_ bookID: UUID) {
        guard canStartNarration, let index = queue.firstIndex(where: { $0.bookID == bookID }) else { return }
        queue[index].isPaused = false
        saveQueue()
        startNext()
    }

    /// Removing the running narration stops it, keeping every finished chapter.
    func removeFromQueue(_ bookID: UUID) {
        if narratingBookID == bookID {
            cancelNarration()
            return
        }
        queue.removeAll { $0.bookID == bookID }
        saveQueue()
    }

    /// Order decides what runs next; the running narration is not interrupted.
    func moveQueue(fromOffsets source: IndexSet, toOffset destination: Int) {
        queue.move(fromOffsets: source, toOffset: destination)
        saveQueue()
    }

    /// Words still to be spoken: every chapter not yet narrated, less what the
    /// engine has already said of the one in progress.
    func remainingWords(for bookID: UUID) -> Int {
        guard let book = book(id: bookID) else { return 0 }
        let words = book.chapters.filter { !$0.isNarrated }.reduce(0) { $0 + ListenEstimator.wordCount($1.text) }
        return max(0, words - (progress?.bookID == bookID ? progress?.spokenWords ?? 0 : 0))
    }

    /// How long the rest of a book should take to generate, from the text of
    /// its chapters still to narrate. Every readout of time remaining — the
    /// Library, the book, the queue — comes from here, so they agree.
    func remainingGenerationTime(for bookID: UUID) -> TimeInterval {
        guard let book = book(id: bookID) else { return 0 }
        let estimator = listenEstimator()
        return estimator.generationTime(
            audioSeconds: estimator.listenDuration(words: remainingWords(for: bookID), voiceID: book.voiceID)
        )
    }

    func remainingLabel(for bookID: UUID) -> String {
        if let progress, progress.bookID == bookID, progress.isCombining { return progress.eta }
        return ListenEstimator.remainingLabel(remainingGenerationTime(for: bookID))
    }

    private func enqueue(_ bookID: UUID, useMPS: Bool) {
        guard let book = book(id: bookID), !isFullyNarrated(book) else { return }
        if let index = queue.firstIndex(where: { $0.bookID == bookID }) {
            queue[index].isPaused = false
        } else {
            queue.append(QueuedNarration(bookID: bookID, useMPS: useMPS))
        }
        saveQueue()
    }

    /// A narration that starts at once goes to the front, running.
    private func admit(_ bookID: UUID, useMPS: Bool) {
        if let index = queue.firstIndex(where: { $0.bookID == bookID }) {
            queue[index].isPaused = false
        } else {
            queue.insert(QueuedNarration(bookID: bookID, useMPS: useMPS), at: 0)
        }
        saveQueue()
    }

    /// A paused narration keeps its place; anything else that ended — done,
    /// stopped or failed — leaves, and the next one waiting starts.
    private func narrationEnded(_ bookID: UUID) {
        guard !isShuttingDown else { return }
        if !isPaused(bookID) || book(id: bookID).map(isFullyNarrated) ?? true {
            queue.removeAll { $0.bookID == bookID }
        }
        saveQueue()
        startNext()
    }

    /// Starts the first narration that is not paused. One that cannot start —
    /// already narrated, its voice not downloaded — leaves the queue, and
    /// the shelf's message says why.
    private func startNext() {
        while narrationTask == nil, !synthesis.isBusy, let next = queue.first(where: { !$0.isPaused }) {
            narrate(next.bookID, useMPS: next.useMPS)
            if narrationTask == nil {
                queue.removeAll { $0.bookID == next.bookID }
                saveQueue()
            }
        }
    }

    /// A queue left by the last launch comes back paused: nothing starts
    /// generating until it is asked to again.
    private func restoreQueue() {
        queue = NarrationQueueFile.load(from: NarrationQueueFile.url(in: directories))
            .filter { entry in book(id: entry.bookID).map { !isFullyNarrated($0) } ?? false }
            .map { var entry = $0; entry.isPaused = true; return entry }
    }

    private func saveQueue() {
        try? NarrationQueueFile.save(queue, to: NarrationQueueFile.url(in: directories))
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

    /// Goes to `positions.json` rather than rewriting the whole shelf; the
    /// next full save carries it into `books.json` as well.
    func saveListeningPosition(_ position: Double, for id: UUID) {
        guard position.isFinite, let index = books.firstIndex(where: { $0.id == id }) else { return }
        let now = Date()
        books[index].listeningPosition = max(0, position)
        books[index].lastListenedAt = now
        updatePositions { await $0.record(position, for: id, at: now) }
    }

    private func updatePositions(_ change: @escaping @Sendable (ListeningPositionStore) async -> Void) {
        let previous = positionUpdate
        let positions = positions
        positionUpdate = Task {
            await previous?.value
            await change(positions)
        }
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

    /// Marks a spot heard in the player. Two sentences of one paragraph are
    /// the same place to the Reader but two marks to a listener, so only the
    /// same sentence twice is refused.
    func addBookmark(at location: ReadingLocation, excerpt: String, in bookID: UUID) {
        guard let index = books.firstIndex(where: { $0.id == bookID }),
              !books[index].bookmarks.contains(where: { $0.location.isAt(location) && $0.excerpt == excerpt })
        else { return }
        books[index].bookmarks.append(Bookmark(location: location, excerpt: excerpt))
        books[index].bookmarks.sort { $0.location.precedes($1.location) }
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
        else if queue.contains(where: { $0.bookID == bookID }) { removeFromQueue(bookID) }
        importErrorMessage = nil
        importSuccessMessage = nil
        narrationErrorMessage = nil
        narrationSuccessMessage = nil
        let book = books.remove(at: index)
        try? FileManager.default.removeItem(at: book.sourceURL)
        removeNarrations(for: bookID, chapters: book.chapters)
        covers.forget(bookID)
        narratedCounts.removeValue(forKey: bookID)
        updatePositions { await $0.forget(bookID) }
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
        updatePositions { await $0.forget(bookID) }
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
        await positionUpdate?.value
        try await positions.flush()
    }

    func stopAndSave() async throws {
        isShuttingDown = true
        cancelNarration()
        await narrationTask?.value
        // What a relaunch would restore, should the quit be called off.
        for index in queue.indices { queue[index].isPaused = true }
        isShuttingDown = false
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
