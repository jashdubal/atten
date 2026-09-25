import AttenCore
import Foundation

/// One book waiting its turn on the speech engine, or the one taking it now.
struct QueuedNarration: Codable, Equatable, Identifiable {
    let bookID: UUID
    var useMPS: Bool
    /// Held back until resumed. A paused narration that is running stops at
    /// its next chapter boundary, with every finished chapter kept.
    var isPaused = false

    var id: UUID { bookID }
}

/// The queue lives in a `queue.json` of its own beside `books.json`, so a
/// build that predates it simply never reads it.
enum NarrationQueueFile {
    static func url(in directories: AppDirectories) -> URL {
        directories.applicationSupport.appendingPathComponent("queue.json")
    }

    /// Nothing to resume is the answer for a missing or unreadable file:
    /// the books themselves keep every chapter already narrated. A damaged
    /// file keeps the entries it finished writing, and a copy of it is kept
    /// as `queue.json.corrupt` before the next save replaces it.
    static func load(from url: URL) -> [QueuedNarration] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        if let queue = try? JSONDecoder().decode([QueuedNarration].self, from: data) { return queue }
        try? CorruptFileBackup.preserve(url)
        return JSONArraySalvage.decode(QueuedNarration.self, from: data, using: JSONDecoder())
    }

    static func save(_ queue: [QueuedNarration], to url: URL) throws {
        try JSONEncoder().encode(queue).write(to: url, options: .atomic)
    }
}
