import AttenCore
import Foundation

/// A realistic-looking library for the coordinator's live QA (#107): mixed
/// formats, lengths and languages, in every state a book can be in — silent
/// drafts, one queued for narration, a few interrupted partway through, and
/// some already voiced. Built from the same word and audio builders as the
/// #90 stress fixtures (`FixtureBuilders`), just arranged to look like a
/// library someone actually has rather than a stress-test shelf.
public enum LibraryFixture {
    public struct Built {
        public let books: [BookRecord]
        /// Mirrors Atten's own `QueuedNarration`, written straight to
        /// `queue.json` — the fixture tool has no reason to depend on the app
        /// executable target for one small `Codable` struct.
        public let queue: [QueuedEntry]
    }

    public struct QueuedEntry: Codable {
        public let bookID: UUID
        public var useMPS = false
        public var isPaused = false
    }

    private struct Title { let title: String; let author: String; let voiceID: String }

    private static let titles: [Title] = [
        Title(title: "The Salt House", author: "Marguerite Ashdown", voiceID: "af_heart"),
        Title(title: "A Quiet Ledger", author: "Owen Faircastle", voiceID: "am_michael"),
        Title(title: "Nine Winters in Esk", author: "Bettina Colquhoun", voiceID: "bf_emma"),
        Title(title: "The Cartographer's Daughter", author: "Rhys Penhallow", voiceID: "bm_george"),
        Title(title: "Low Tide at Merrow", author: "Frances Oduya", voiceID: "af_nicole"),
        Title(title: "What the Orchard Kept", author: "Tobias Wrenfield", voiceID: "am_fenrir"),
        Title(title: "The Long Correspondence", author: "Iris Halloway", voiceID: "bf_isabella"),
        Title(title: "Signal and Ash", author: "Desmond Carraway", voiceID: "bm_fable"),
        Title(title: "The Understudy's Notebook", author: "Priya Ashworth", voiceID: "af_sarah"),
        Title(title: "A Minor Cartography", author: "Elliot Marsh", voiceID: "am_puck"),
        Title(title: "The Weight of Ordinary Days", author: "Susanna Colefax", voiceID: "bf_alice"),
        Title(title: "Everything Left Unsent", author: "Julian Thorne", voiceID: "bm_lewis"),
        Title(title: "The Glasshouse Almanac", author: "Nora Kettering", voiceID: "af_aoede"),
        Title(title: "A Field Guide to Leaving", author: "Marcus Abelard", voiceID: "am_michael"),
        Title(title: "The Quiet Machinery", author: "Helena Byrd", voiceID: "af_kore"),
        Title(title: "Letters from the North Room", author: "Callum Ferris", voiceID: "am_eric"),
        Title(title: "The Last Good Harvest", author: "Dorothea Lindqvist", voiceID: "bf_lily"),
        Title(title: "A Brief History of Waiting", author: "Simeon Achebe", voiceID: "bm_daniel"),
        Title(title: "The Cormorant's Ledger", author: "Wren Aldous", voiceID: "af_nova"),
        Title(title: "Small Hours, Wide River", author: "Peregrine Voss", voiceID: "am_onyx"),
        Title(title: "La Maison du Vent", author: "Élodie Vasseur", voiceID: "ff_siwis"),
        Title(title: "Les Heures Silencieuses", author: "Baptiste Mercier", voiceID: "ff_siwis"),
        Title(title: "El Peso del Silencio", author: "Mateo Duarte", voiceID: "em_alex"),
        Title(title: "Un Verano sin Nombre", author: "Camila Restrepo", voiceID: "ef_dora"),
        Title(title: "Le Ombre di Settembre", author: "Nicola Ferretti", voiceID: "im_nicola"),
        Title(title: "Il Giardino Sommerso", author: "Valentina Rossato", voiceID: "if_sara"),
        Title(title: "O Rio Que Não Dorme", author: "Beatriz Nogueira", voiceID: "pf_dora"),
        Title(title: "Cartas Para Ninguém", author: "Renato Salgado", voiceID: "pm_alex"),
    ]

    private static let lengthClasses: [(chapters: ClosedRange<Int>, words: ClosedRange<Int>)] = [
        (3...6, 350...550),
        (8...14, 500...800),
        (16...26, 600...950),
    ]

    /// One narrated chapter's synthetic audio, kept fixed and tiny regardless
    /// of chapter length — these fixtures only need to load and play, not to
    /// sound like anything.
    private static let chapterSeconds = 0.15

    private enum State { case draft, queued, midNarration, voiced }

    /// `count` books split across `AppDirectories`. `voicedFraction` of them
    /// come out fully narrated; the rest split between plain drafts, one
    /// interrupted partway through, and a few queued for narration.
    public static func build(count: Int, voicedFraction: Double, in directories: AppDirectories) throws -> Built {
        try directories.prepare()

        let voicedCount = Int((Double(count) * voicedFraction).rounded())
        let remaining = max(0, count - voicedCount)
        let midCount = remaining > 0 ? max(1, remaining / 5) : 0
        let queuedCount = remaining > 0 ? max(1, remaining / 3) : 0
        let draftCount = max(0, remaining - midCount - queuedCount)

        var states = Array(repeating: State.voiced, count: voicedCount)
            + Array(repeating: .midNarration, count: midCount)
            + Array(repeating: .queued, count: queuedCount)
            + Array(repeating: .draft, count: draftCount)
        while states.count < count { states.append(.draft) }
        states = Array(states.prefix(count))
        // A deterministic Fisher-Yates shuffle, so states aren't laid out in
        // blocks but a rerun with the same count still produces the same shelf.
        for i in stride(from: states.count - 1, to: 0, by: -1) {
            states.swapAt(i, Int(hashed(i, 11) % UInt64(i + 1)))
        }

        let base = Date(timeIntervalSince1970: 1_735_000_000)
        var books: [BookRecord] = []
        var queue: [QueuedEntry] = []

        for index in 0..<count {
            let state = states[index]
            var book = try makeBook(index: index, base: base, in: directories)

            switch state {
            case .draft:
                break
            case .queued:
                queue.append(QueuedEntry(bookID: book.id))
            case .midNarration:
                try narratePartially(&book, in: directories)
            case .voiced:
                try narrateFully(&book, in: directories)
                if index % 3 == 0 {
                    book.listeningPosition = chapterSeconds * 0.5
                    book.lastListenedAt = base.addingTimeInterval(Double(index) * 3_600)
                    book.lastOpenedAt = book.lastListenedAt
                }
            }
            books.append(book)
        }

        return Built(books: books, queue: queue)
    }

    public static func saveQueue(_ queue: [QueuedEntry], to directories: AppDirectories) throws {
        guard !queue.isEmpty else { return }
        let url = directories.applicationSupport.appendingPathComponent("queue.json")
        try JSONEncoder().encode(queue).write(to: url, options: .atomic)
    }

    // MARK: - Building one book

    private static func makeBook(index: Int, base: Date, in directories: AppDirectories) throws -> BookRecord {
        let title = titles[index % titles.count]
        let lengthClass = lengthClasses[Int(hashed(index, 1) % UInt64(lengthClasses.count))]
        let chapterCount = lengthClass.chapters.lowerBound
            + Int(hashed(index, 2) % UInt64(lengthClass.chapters.count))
        let wordsPerChapter = lengthClass.words.lowerBound
            + Int(hashed(index, 3) % UInt64(lengthClass.words.count))
        let format = [BookFormat.epub, .document, .pdf, .mobi][index % 4]

        let chapters = (0..<chapterCount).map { chapter in
            BookChapter(
                title: "Chapter \(chapter + 1)",
                text: FixtureBuilders.words(wordsPerChapter, seed: index * 1_000 + chapter)
            )
        }

        // The pool repeats past its own length; disambiguate the repeats.
        let displayTitle = index < titles.count ? title.title : "\(title.title) (\(index / titles.count + 1))"
        let sourcePath = try writeSource(
            title: displayTitle, format: format, chapters: chapters, index: index, in: directories
        )

        return BookRecord(
            id: UUID(),
            title: displayTitle,
            author: title.author,
            format: format,
            sourcePath: sourcePath.path,
            chapters: chapters,
            voiceID: title.voiceID,
            speed: 1,
            audioFormat: .wav,
            addedAt: base.addingTimeInterval(-Double(index) * 3_600)
        )
    }

    /// A source file that actually exists on disk, so the Library never shows
    /// a "source file unavailable" notice for a fixture book. Its content
    /// only has to be recognisable as the format — the chapters that get read
    /// aloud are already embedded in the book record, exactly as they are for
    /// a real book reopened after import.
    private static func writeSource(
        title: String, format: BookFormat, chapters: [BookChapter], index: Int, in directories: AppDirectories
    ) throws -> URL {
        let slug = ExportService.safeFilename(title, maximumByteCount: 80)
        switch format {
        case .document:
            let url = directories.bookSources.appendingPathComponent("\(slug).txt")
            try chapters.map(\.text).joined(separator: "\n\n").write(to: url, atomically: true, encoding: .utf8)
            return url
        case .epub:
            return try FixtureBuilders.epub(
                pages: max(chapters.count, 1), files: max(chapters.count, 1), in: directories.bookSources
            )
        case .pdf:
            return try FixtureBuilders.pdf(
                pages: max(chapters.count * 2, 2),
                pagesPerChapter: chapters.count > 1 ? 2 : nil,
                in: directories.bookSources
            )
        case .mobi:
            let url = directories.bookSources.appendingPathComponent("\(slug).mobi")
            try chapters.map(\.text).joined(separator: "\n\n").write(to: url, atomically: true, encoding: .utf8)
            return url
        }
    }

    // MARK: - Narration

    /// One combined recording across every chapter, exactly the shape
    /// `BookAudioAssembler` publishes: `Audiobook.caf` plus a `timings.json`
    /// beside it, with the chapters' timeline contiguous end to end.
    private static func narrateFully(_ book: inout BookRecord, in directories: AppDirectories) throws {
        let folder = directories.narrations
            .appendingPathComponent(book.id.uuidString, isDirectory: true)
            .appendingPathComponent("Audiobook-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let audioURL = folder.appendingPathComponent("Audiobook.caf")

        var segments: [TimedSegment] = []
        var cursor = 0.0
        for chapter in book.chapters {
            let segment = TimedSegment(index: 0, text: chapter.text, start: 0, duration: chapterSeconds, words: [])
                .estimatingMissingWords()
            segments += NarrationTimings(segments: [segment]).offset(by: cursor, startingAt: segments.count).segments
            cursor += chapterSeconds
        }
        try FixtureBuilders.silentWAV(seconds: cursor).write(to: audioURL)
        try NarrationTimings(segments: segments).save(beside: audioURL)

        book.audioPath = audioURL.path
        book.narrationState = .ready
        for index in book.chapters.indices {
            book.chapters[index].audioPath = audioURL.path
            book.chapters[index].startTime = Double(index) * chapterSeconds
            book.chapters[index].endTime = Double(index + 1) * chapterSeconds
        }
    }

    /// The first third of the chapters get their own interim recording, the
    /// shape a chapter takes mid-run before the book is combined — same
    /// layout `BookshelfModel.narrate` writes to, so quitting Atten mid-run
    /// and reopening this fixture look the same.
    private static func narratePartially(_ book: inout BookRecord, in directories: AppDirectories) throws {
        let narratedCount = max(1, min(book.chapters.count - 1, book.chapters.count / 3))
        for index in 0..<narratedCount {
            let chapter = book.chapters[index]
            let folder = directories.narrations
                .appendingPathComponent(book.id.uuidString, isDirectory: true)
                .appendingPathComponent("chapter-\(index)-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let numbered = String(format: "%03d", index + 1)
            let audioURL = folder.appendingPathComponent("\(numbered) \(ExportService.safeFilename(chapter.title)).caf")
            try FixtureBuilders.silentWAV(seconds: chapterSeconds).write(to: audioURL)
            let segment = TimedSegment(index: 0, text: chapter.text, start: 0, duration: chapterSeconds, words: [])
                .estimatingMissingWords()
            try NarrationTimings(segments: [segment]).save(beside: audioURL)
            book.chapters[index].audioPath = audioURL.path
        }
        book.narrationState = .interrupted
    }

    // MARK: - Deterministic choice

    private static func hashed(_ index: Int, _ salt: Int) -> UInt64 {
        var x = UInt64(bitPattern: Int64(index &* 1_000_003 &+ salt))
        x = x &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        x ^= x >> 33
        x = x &* 0xff51afd7ed558ccd
        x ^= x >> 33
        return x
    }
}
