import Foundation

/// Where someone stopped listening to a book, and when.
public struct ListeningPosition: Codable, Equatable, Sendable {
    public var position: Double
    public var updatedAt: Date

    public init(position: Double, updatedAt: Date) {
        self.position = position
        self.updatedAt = updatedAt
    }
}

extension BookRecord {
    /// Takes a position kept outside `books.json` when it is newer than the
    /// one saved with the book. `lastListenedAt` is the book's own
    /// `updatedAt`; on a tie the book's record stands.
    public mutating func adopt(_ saved: ListeningPosition?) {
        guard let saved, saved.position.isFinite, saved.updatedAt > (lastListenedAt ?? .distantPast) else { return }
        listeningPosition = max(0, saved.position)
        lastListenedAt = saved.updatedAt
    }
}

/// Playback positions, in a `positions.json` of their own beside `books.json`.
///
/// A playing book's position changes every few seconds. Keeping it only in
/// `books.json` meant rewriting the whole library each time — megabytes at a
/// thousand books, and every rewrite another moment a crash could catch.
/// This file holds only positions, is written atomically, and is written at
/// most once per `minimumInterval`: a change inside the interval waits for
/// its end, and the changes that pile up meanwhile go out as one write.
///
/// `books.json` still carries whatever position it had when it was last
/// saved, which is what a build that predates this file reads. On load the
/// newer of the two wins (`BookRecord.adopt`).
public actor ListeningPositionStore {
    /// The store's sense of time, replaceable so tests can step through the
    /// interval rather than wait it out.
    public struct Clock: Sendable {
        public var now: @Sendable () -> Date
        public var sleep: @Sendable (TimeInterval) async -> Void

        public init(now: @escaping @Sendable () -> Date, sleep: @escaping @Sendable (TimeInterval) async -> Void) {
            self.now = now
            self.sleep = sleep
        }

        public static let system = Clock(now: { Date() }, sleep: { try? await Task.sleep(for: .seconds($0)) })
    }

    public static let minimumInterval: TimeInterval = 5

    private let fileURL: URL
    private let clock: Clock
    private let encoder = JSONEncoder()
    private var positions: [UUID: ListeningPosition] = [:]
    private var lastWrite: Date?
    private var isDirty = false
    private var scheduledWrite: Task<Void, Never>?
    /// What this store has put on disk, for measuring what playback costs.
    public private(set) var writeCount = 0
    public private(set) var bytesWritten = 0

    public init(fileURL: URL, clock: Clock = .system) {
        self.fileURL = fileURL
        self.clock = clock
        encoder.outputFormatting = [.sortedKeys]
    }

    /// A missing file is no positions. A damaged one is copied aside as
    /// `positions.json.corrupt` before the next write replaces it, and the
    /// positions saved in `books.json` stand in the meantime.
    public func load() -> [UUID: ListeningPosition] {
        guard let data = try? Data(contentsOf: fileURL) else { return [:] }
        guard let decoded = try? JSONDecoder().decode([String: ListeningPosition].self, from: data) else {
            _ = try? CorruptFileBackup.preserve(fileURL)
            return [:]
        }
        positions = Dictionary(
            decoded.compactMap { key, value in UUID(uuidString: key).map { ($0, value) } },
            uniquingKeysWith: { first, second in first.updatedAt >= second.updatedAt ? first : second }
        )
        return positions
    }

    /// Keeps the newest position for a book; one older than what is already
    /// held changes nothing.
    public func record(_ position: Double, for bookID: UUID, at date: Date) {
        guard position.isFinite, positions[bookID].map({ $0.updatedAt <= date }) ?? true else { return }
        positions[bookID] = ListeningPosition(position: max(0, position), updatedAt: date)
        scheduleWrite()
    }

    /// For a book that is gone, or whose narration was replaced.
    public func forget(_ bookID: UUID) {
        guard positions.removeValue(forKey: bookID) != nil else { return }
        scheduleWrite()
    }

    /// Writes anything not yet on disk now, however recently the last write
    /// was: the app is quitting.
    public func flush() throws {
        scheduledWrite?.cancel()
        scheduledWrite = nil
        guard isDirty else { return }
        try write()
    }

    private func scheduleWrite() {
        isDirty = true
        guard scheduledWrite == nil else { return }
        let wait = lastWrite.map { Self.minimumInterval - clock.now().timeIntervalSince($0) } ?? 0
        guard wait > 0 else {
            // A failed write stays dirty and is tried again with the next
            // change; `books.json` still has the position meanwhile.
            try? write()
            return
        }
        let sleep = clock.sleep
        scheduledWrite = Task {
            await sleep(wait)
            guard !Task.isCancelled else { return }
            writeScheduled()
        }
    }

    private func writeScheduled() {
        scheduledWrite = nil
        guard isDirty else { return }
        try? write()
    }

    private func write() throws {
        let data = try encoder.encode(Dictionary(uniqueKeysWithValues: positions.map { ($0.key.uuidString, $0.value) }))
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
        lastWrite = clock.now()
        isDirty = false
        writeCount += 1
        bytesWritten += data.count
    }
}
