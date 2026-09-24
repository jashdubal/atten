import Foundation

public struct SegmentReady: Equatable, Sendable {
    public let url: URL
    public let timing: TimedSegment

    public init(url: URL, timing: TimedSegment) {
        self.url = url
        self.timing = timing
    }
}

public enum GenerationEvent: Equatable, Sendable {
    case progress(String)
    case segment(SegmentReady)
    case completed(URL)
    case failed(String)
}

public extension TTSGenerating {
    /// Compatibility for generators that only implement whole-file generation.
    func generateStream(_ request: GenerationRequest) -> AsyncThrowingStream<GenerationEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let output = try await generate(request)
                    continuation.yield(.completed(output.url))
                    continuation.finish()
                } catch {
                    continuation.yield(.failed(error.localizedDescription))
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { termination in
                if case .cancelled = termination {
                    task.cancel()
                    self.cancel()
                }
            }
        }
    }
}
