import AttenCore
import Foundation

/// One thing to play, and enough about it to say what it is.
///
/// The player used to be handed bare file URLs, which left it two problems it
/// could not solve: it could only ever go forwards, and the only name it had
/// for what was playing was the filename — a narrated chapter announced itself
/// as "003 THE ALCHEMIST". A track carries where it came from.
struct PlaybackTrack: Identifiable, Equatable, Sendable {
    let id: UUID
    let url: URL
    let title: String
    /// The book, project, or voice this came from. Shown under the title.
    let subtitle: String?

    init(id: UUID = UUID(), url: URL, title: String, subtitle: String? = nil) {
        self.id = id
        self.url = url
        self.title = title
        self.subtitle = subtitle
    }

    /// For audio that has no record behind it — a voice preview, a playground
    /// sample — the file is all there is to go on.
    init(url: URL, subtitle: String? = nil) {
        self.init(
            url: url,
            title: url.deletingPathExtension().lastPathComponent,
            subtitle: subtitle
        )
    }
}

/// What is playing, what played before it, and what comes next.
struct PlaybackQueue: Equatable {
    private(set) var tracks: [PlaybackTrack] = []
    private(set) var index = 0

    init(tracks: [PlaybackTrack] = [], startingAt index: Int = 0) {
        self.tracks = tracks
        self.index = tracks.indices.contains(index) ? index : 0
    }

    var current: PlaybackTrack? { tracks.indices.contains(index) ? tracks[index] : nil }
    var next: PlaybackTrack? { tracks.indices.contains(index + 1) ? tracks[index + 1] : nil }
    var hasNext: Bool { next != nil }
    var hasPrevious: Bool { index > 0 }
    var isEmpty: Bool { tracks.isEmpty }
    /// "3 of 16", for a book being listened to straight through.
    var position: String? { tracks.count > 1 ? "\(index + 1) of \(tracks.count)" : nil }

    mutating func advance() -> PlaybackTrack? {
        guard hasNext else { return nil }
        index += 1
        return current
    }

    mutating func retreat() -> PlaybackTrack? {
        guard hasPrevious else { return nil }
        index -= 1
        return current
    }

    /// Moves to a track already in the queue, for the play button on a row of
    /// a list the queue was built from.
    mutating func move(to url: URL) -> Bool {
        guard let found = tracks.firstIndex(where: { $0.url == url }) else { return false }
        index = found
        return true
    }
}

extension BookRecord {
    /// Every narrated chapter, in reading order, named the way the book names
    /// it rather than the way the file is named.
    var narrationTracks: [PlaybackTrack] {
        chapters.compactMap { chapter in
            guard chapter.isNarrated, let url = chapter.audioURL else { return nil }
            return PlaybackTrack(id: chapter.id, url: url, title: chapter.title, subtitle: title)
        }
    }
}
