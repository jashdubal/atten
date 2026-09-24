import Foundation

/// One owner's way of reaching a `PersistentBackendClient` that another
/// owner reaches too: every owner's requests interleave through the same
/// resident process, but `cancel()` only reaches the requests THIS owner
/// submitted, so cancelling one owner's work never touches another's.
public final class SharedBackendClient: TTSGenerating, @unchecked Sendable {
    private let engine: PersistentBackendClient
    private let lock = NSLock()
    private var activeIDs: Set<String> = []

    public init(sharing engine: PersistentBackendClient) {
        self.engine = engine
    }

    public func generate(_ request: GenerationRequest) async throws -> GenerationOutput {
        let id = UUID().uuidString
        track(id)
        defer { untrack(id) }
        return try await engine.generate(request, id: id)
    }

    public func generateStream(_ request: GenerationRequest) -> AsyncThrowingStream<GenerationEvent, Error> {
        let id = UUID().uuidString
        track(id)
        let events = engine.generateStream(request, id: id)
        return AsyncThrowingStream { continuation in
            let task = Task {
                defer { self.untrack(id) }
                do {
                    for try await event in events { continuation.yield(event) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { termination in
                if case .cancelled = termination { task.cancel() }
            }
        }
    }

    /// Cancels every request this owner has submitted; a request another
    /// owner submitted through the same engine keeps running.
    public func cancel() {
        for id in lock.withLock({ activeIDs }) { engine.cancel(id: id) }
    }

    private func track(_ id: String) {
        lock.withLock { _ = activeIDs.insert(id) }
    }

    private func untrack(_ id: String) {
        lock.withLock { _ = activeIDs.remove(id) }
    }
}
