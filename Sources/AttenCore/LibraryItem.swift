import Foundation

/// Where an item stands between being just text and being a finished
/// audiobook. `drafts` and `audiobooks` in the Library are exactly `.silent`
/// and `.voiced`; `.generating` is what shows progress while narration runs.
public enum LibraryItemState: Equatable, Sendable {
    case silent
    case generating(progress: Double)
    case voiced
}

/// The Library's single presentation of everything on it. A book and a
/// legacy project (`projects.json`, from before books existed) are different
/// records with different histories, but someone browsing their library
/// doesn't need to know that — they need a title, a state, and something to
/// press play on. Legacy projects are always shown as already voiced, since
/// a project is never written until its generation has succeeded; they are
/// only ever read here, never migrated into `books.json`.
public enum LibraryItem: Identifiable, Equatable, Sendable {
    case book(BookRecord)
    case project(ProjectRecord)

    public var id: UUID {
        switch self {
        case .book(let book): book.id
        case .project(let project): project.id
        }
    }

    public var title: String {
        switch self {
        case .book(let book): book.title
        case .project(let project): project.title
        }
    }

    /// The author for a book; nil for a project, which has no author field.
    public var sourceLabel: String? {
        switch self {
        case .book(let book): book.author
        case .project: nil
        }
    }

    public var state: LibraryItemState {
        switch self {
        case .book(let book):
            // Audio already committed to disk outranks the record's own
            // narration state, because a previous complete recording stays
            // playable while a replacement is (re)generated or fails.
            if book.hasBookAudio { return .voiced }
            if book.narrationState == .preparing || book.narrationState == .finalizing {
                let total = max(book.chapters.count, 1)
                return .generating(progress: Double(book.narratedCount) / Double(total))
            }
            return .silent
        case .project:
            return .voiced
        }
    }

    public var audioURL: URL? {
        switch self {
        case .book(let book): book.audioURL
        case .project(let project): project.audioURL
        }
    }

    public var addedAt: Date {
        switch self {
        case .book(let book): book.addedAt
        case .project(let project): project.createdAt
        }
    }

    /// Nil for a project: `ProjectRecord` never tracked a listening position.
    public var lastListenedAt: Date? {
        switch self {
        case .book(let book): book.lastListenedAt
        case .project: nil
        }
    }

    /// A project has no stored hash, but its text is right there, so one is
    /// computed on the fly rather than left out — this is a read, not a
    /// rewrite of `projects.json`.
    public var contentHash: String? {
        switch self {
        case .book(let book): book.contentHash
        case .project(let project): ContentHash.of(project.text)
        }
    }

    /// Has a listening position and isn't finished. A project never
    /// qualifies: it has no listening position to have started.
    public var isListening: Bool {
        guard case .book(let book) = self, book.listeningPosition > 0 else { return false }
        return !Self.isFinished(book)
    }

    private static func isFinished(_ book: BookRecord) -> Bool {
        guard let total = book.playbackChapters.last?.endTime, total > 0 else { return false }
        return book.listeningPosition >= total - 1
    }
}

public enum LibraryItemFilter: String, CaseIterable, Sendable {
    case all
    case listening
    case drafts
    case audiobooks
}

public extension LibraryItem {
    static func filter(_ items: [LibraryItem], by filter: LibraryItemFilter) -> [LibraryItem] {
        switch filter {
        case .all: items
        case .listening: items.filter(\.isListening)
        case .drafts: items.filter { $0.state == .silent }
        case .audiobooks: items.filter { $0.state == .voiced }
        }
    }
}
