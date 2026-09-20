import Foundation

public enum BookFormat: String, Codable, Sendable {
    case pdf
    case epub

    public var displayName: String { rawValue.uppercased() }

    public var icon: String {
        switch self {
        case .pdf: "doc.richtext"
        case .epub: "book.closed"
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
    }
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
        addedAt: Date = Date()
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
    }

    public var sourceURL: URL { URL(fileURLWithPath: sourcePath) }

    public var sourceExists: Bool { FileManager.default.fileExists(atPath: sourcePath) }

    public var narratedCount: Int { chapters.count { $0.isNarrated } }

    public var isFullyNarrated: Bool {
        !chapters.isEmpty && narratedCount == chapters.count
    }

    /// Every narrated chapter in reading order, which is what "play all" plays.
    public var narrationQueue: [URL] { chapters.compactMap { $0.isNarrated ? $0.audioURL : nil } }

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
    }
}

/// Stores the shelf beside the project history. A damaged shelf loses at most
/// the books whose entries no longer decode; the rest are kept, and a book can
/// always be added again from its source file.
public actor BookLibraryStore {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(fileURL: URL) {
        self.fileURL = fileURL
        encoder.outputFormatting = [.sortedKeys]
    }

    public func load() throws -> [BookRecord] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        if let books = try? decoder.decode([BookRecord].self, from: data) { return books }
        return (try? decoder.decode([Salvaged].self, from: data))?.compactMap(\.record) ?? []
    }

    public func save(_ books: [BookRecord]) throws {
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
