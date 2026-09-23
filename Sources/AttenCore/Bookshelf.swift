import Foundation

public enum BookFormat: String, Codable, Sendable {
    case pdf
    case epub
    /// A Kindle book: Mobipocket, and the KF8 files that succeeded it.
    case mobi
    /// Anything that is one flat run of text rather than a book: a note, a
    /// paper, a report someone wants read out to them. Atten sets the type for
    /// these itself, exactly as it does for an EPUB.
    case document

    /// The extensions each format is recognised by. A document has several
    /// because the format is about what Atten does with the file, not about
    /// which of the interchangeable text formats it arrived in.
    public var extensions: [String] {
        switch self {
        case .pdf: ["pdf"]
        case .epub: ["epub"]
        case .mobi: ["mobi", "azw", "azw3", "prc"]
        case .document: ["txt", "text", "md", "markdown", "rtf", "rtfd", "doc", "docx", "html", "htm"]
        }
    }

    public static func forExtension(_ pathExtension: String) -> BookFormat? {
        let wanted = pathExtension.lowercased()
        return [.pdf, .epub, .mobi, .document].first { $0.extensions.contains(wanted) }
    }

    /// The format a file's first bytes say it is. Only the two book containers
    /// are recognised, because they are the two that get confused: a `.docx` is
    /// a zip as well, and it is a document however its bytes begin.
    static func forContents(of url: URL) -> BookFormat? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: 68), header.count >= 68 else { return nil }
        if header.prefix(4).elementsEqual([0x50, 0x4B, 0x03, 0x04]) { return .epub }
        // A Palm database names its type and creator at byte 60.
        if header[60..<68].elementsEqual(Array("BOOKMOBI".utf8)) { return .mobi }
        return nil
    }

    /// The format Atten will actually read the file as. Kindle books are handed
    /// around named `.epub` often enough that the extension alone is not worth
    /// trusting for a book — so for a book, the bytes decide. Every other
    /// format is taken at its extension.
    public static func resolve(for url: URL) -> BookFormat? {
        let declared = forExtension(url.pathExtension)
        guard declared == .epub || declared == .mobi else { return declared }
        return forContents(of: url) ?? declared
    }

    public static let supportedExtensions = [BookFormat.pdf, .epub, .mobi, .document]
        .flatMap(\.extensions)

    public var displayName: String {
        switch self {
        case .pdf, .epub, .mobi: rawValue.uppercased()
        case .document: "DOC"
        }
    }

    /// Whether Atten sets this format's type itself. A PDF is already typeset
    /// — it is pages of artwork, and reflowing it would be inventing a book
    /// its publisher did not print.
    public var isTypeset: Bool { self != .pdf }

    /// What one division of the whole is called, which is the word the reader
    /// prints above a title. A report has sections, not chapters.
    public var sectionNoun: String {
        switch self {
        case .epub, .mobi: "Chapter"
        case .pdf, .document: "Section"
        }
    }

    public var icon: String {
        switch self {
        case .pdf: "doc.richtext"
        case .epub, .mobi: "book.closed"
        case .document: "doc.text"
        }
    }
}

public struct BookChapter: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var text: String
    public var pageIndex: Int?
    /// Where this chapter's narration was written, once it has been generated.
    public var audioPath: String?
    public var startTime: Double?
    public var endTime: Double?

    public init(
        id: UUID = UUID(),
        title: String,
        text: String,
        pageIndex: Int? = nil,
        audioPath: String? = nil
    ) {
        self.id = id
        self.title = title
        self.text = text
        self.pageIndex = pageIndex
        self.audioPath = audioPath
    }

    public var audioURL: URL? { audioPath.map { URL(fileURLWithPath: $0) } }

    /// Narration counts only while the file is still there. A user who empties
    /// the narrations folder should see the chapter offer to generate again
    /// rather than a play button that does nothing.
    public var isNarrated: Bool {
        guard let audioPath else { return false }
        return FileManager.default.fileExists(atPath: audioPath)
    }

    // Only the title and text are structural. Everything else falls back so a
    // shelf written by an older or newer Atten still loads.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decode(String.self, forKey: .text)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Chapter"
        pageIndex = try container.decodeIfPresent(Int.self, forKey: .pageIndex)
        audioPath = try container.decodeIfPresent(String.self, forKey: .audioPath)
        startTime = try container.decodeIfPresent(Double.self, forKey: .startTime)
        endTime = try container.decodeIfPresent(Double.self, forKey: .endTime)
    }
}

public enum NarrationState: String, Codable, Sendable {
    case unprepared, preparing, interrupted, failed, finalizing, ready
}

public struct BookRecord: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var author: String?
    public var format: BookFormat
    /// Atten's own copy of the book, so the shelf keeps working after the
    /// original is moved, renamed, or deleted.
    public var sourcePath: String
    public var chapters: [BookChapter]
    public var voiceID: String
    public var speed: Double
    public var audioFormat: AudioFormat
    public var addedAt: Date
    /// Places the reader marked, in reading order.
    public var bookmarks: [Bookmark]
    /// Where the reader left off, so opening the book comes back to the page
    /// they stopped on rather than to the beginning.
    public var lastLocation: ReadingLocation?
    /// When the book was last opened.
    ///
    /// `lastLocation` says *where* someone stopped but not *when*, so ordering
    /// by it was impossible and Home had to fall back on import order — which
    /// puts a book imported this morning and never opened above the one being
    /// read all week. Nil for every book on a shelf written before this
    /// existed, and for a book that has been imported and not yet opened;
    /// both are honestly "never opened".
    public var lastOpenedAt: Date?
    public var audioPath: String?
    public var audioURL: URL? { audioPath.map { URL(fileURLWithPath: $0) } }
    public var narrationState: NarrationState = .unprepared
    public var narrationFailure: String?
    public var needsPreparation: Bool = false
    public var listeningPosition: Double = 0
    public var lastListenedAt: Date?
    /// Previous complete recording remains playable while replacement checkpoints are built.
    public var previousChapters: [BookChapter]?
    /// SHA-256 of the book's normalized text (`ContentHash`), used to notice
    /// the same book arriving under a different file name. Nil for a book
    /// imported before this existed; the hash is filled in lazily in memory
    /// when it is needed rather than by rewriting every shelf on launch.
    public var contentHash: String?
    public var hasBookAudio: Bool {
        guard let audioPath, FileManager.default.fileExists(atPath: audioPath) else { return false }
        let timeline = previousChapters ?? chapters
        guard !timeline.isEmpty else { return false }
        var end = 0.0
        for chapter in timeline {
            guard let start = chapter.startTime, let stop = chapter.endTime,
                  start.isFinite, stop.isFinite, abs(start - end) < 0.01, stop > start else { return false }
            end = stop
        }
        return true
    }
    public var playbackChapters: [BookChapter] { previousChapters ?? chapters }


    public init(
        id: UUID = UUID(),
        title: String,
        author: String? = nil,
        format: BookFormat,
        sourcePath: String,
        chapters: [BookChapter],
        voiceID: String,
        speed: Double,
        audioFormat: AudioFormat,
        addedAt: Date = Date(),
        bookmarks: [Bookmark] = [],
        lastLocation: ReadingLocation? = nil,
        lastOpenedAt: Date? = nil,
        contentHash: String? = nil
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.format = format
        self.sourcePath = sourcePath
        self.chapters = chapters
        self.voiceID = voiceID
        self.speed = speed
        self.audioFormat = audioFormat
        self.addedAt = addedAt
        self.bookmarks = bookmarks
        self.lastLocation = lastLocation
        self.lastOpenedAt = lastOpenedAt
        self.contentHash = contentHash
    }

    public var sourceURL: URL { URL(fileURLWithPath: sourcePath) }

    public var sourceExists: Bool { FileManager.default.fileExists(atPath: sourcePath) }

    public var narratedCount: Int { chapters.count { $0.isNarrated } }

    public var isFullyNarrated: Bool {
        !chapters.isEmpty && narratedCount == chapters.count
    }

    /// Every narrated chapter in reading order, which is what "play all" plays.
    public var narrationQueue: [URL] { if hasBookAudio, let audioURL { return [audioURL] }; return chapters.compactMap { $0.isNarrated ? $0.audioURL : nil } }

    public var wordCount: Int {
        chapters.reduce(0) { $0 + $1.text.split(whereSeparator: \.isWhitespace).count }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sourcePath = try container.decode(String.self, forKey: .sourcePath)
        chapters = try container.decodeIfPresent([BookChapter].self, forKey: .chapters) ?? []
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decodeIfPresent(String.self, forKey: .title)
            ?? URL(fileURLWithPath: sourcePath).deletingPathExtension().lastPathComponent
        author = try container.decodeIfPresent(String.self, forKey: .author)
        format = (try? container.decodeIfPresent(BookFormat.self, forKey: .format))
            .flatMap { $0 }
            ?? BookFormat(rawValue: URL(fileURLWithPath: sourcePath).pathExtension.lowercased())
            ?? .pdf
        voiceID = try container.decodeIfPresent(String.self, forKey: .voiceID) ?? "af_heart"
        speed = try container.decodeIfPresent(Double.self, forKey: .speed) ?? 1.0
        audioFormat = (try? container.decodeIfPresent(AudioFormat.self, forKey: .audioFormat))
            .flatMap { $0 } ?? .mp3
        addedAt = try container.decodeIfPresent(Date.self, forKey: .addedAt) ?? Date()
        // A shelf whose bookmarks no longer decode still opens the book; losing
        // a mark is a nuisance, losing the book is not.
        bookmarks = (try? container.decodeIfPresent([Bookmark].self, forKey: .bookmarks))
            .flatMap { $0 } ?? []
        lastLocation = (try? container.decodeIfPresent(ReadingLocation.self, forKey: .lastLocation))
            .flatMap { $0 }
        lastOpenedAt = try container.decodeIfPresent(Date.self, forKey: .lastOpenedAt)
        audioPath = try container.decodeIfPresent(String.self, forKey: .audioPath)
        narrationState = (try? container.decode(NarrationState.self, forKey: .narrationState)) ?? .unprepared
        if narrationState == .preparing || narrationState == .finalizing { narrationState = .interrupted }
        narrationFailure = try? container.decode(String.self, forKey: .narrationFailure)
        needsPreparation = (try? container.decode(Bool.self, forKey: .needsPreparation)) ?? false
        listeningPosition = max(0, (try? container.decode(Double.self, forKey: .listeningPosition)) ?? 0)
        lastListenedAt = try? container.decode(Date.self, forKey: .lastListenedAt)
        previousChapters = try? container.decode([BookChapter].self, forKey: .previousChapters)
        contentHash = try container.decodeIfPresent(String.self, forKey: .contentHash)
    }
}

/// Stores the shelf beside the project history. A damaged shelf loses at most
/// the books whose entries no longer decode; the rest are kept, and a book can
/// always be added again from its source file.
public actor BookLibraryStore {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    public private(set) var recoveredFileURL: URL?
    private var loadFailed = false

    public init(fileURL: URL) {
        self.fileURL = fileURL
        encoder.outputFormatting = [.sortedKeys]
    }

    public func load() throws -> [BookRecord] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        loadFailed = true
        let data = try Data(contentsOf: fileURL)
        if let books = try? decoder.decode([BookRecord].self, from: data) {
            loadFailed = false
            return books
        }
        let recovery = fileURL.deletingPathExtension().appendingPathExtension("recovered-\(UUID().uuidString).json")
        try FileManager.default.copyItem(at: fileURL, to: recovery)
        recoveredFileURL = recovery
        loadFailed = false
        return (try? decoder.decode([Salvaged].self, from: data))?.compactMap(\.record) ?? []
    }

    public func save(_ books: [BookRecord]) throws {
        guard !loadFailed else { throw CocoaError(.fileWriteNoPermission) }
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoder.encode(books).write(to: fileURL, options: .atomic)
    }

    private struct Salvaged: Decodable {
        let record: BookRecord?

        init(from decoder: Decoder) throws {
            record = try? BookRecord(from: decoder)
        }
    }
}
