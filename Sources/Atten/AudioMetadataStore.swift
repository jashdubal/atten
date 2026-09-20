import Foundation
import SwiftUI

/// Remembers what Atten has measured about an audio file.
///
/// Reading a file's duration means opening and parsing it, which takes long
/// enough to be felt. Lists asked for it from inside their row bodies, so a
/// window of fifty exports reopened fifty files every time anything on screen
/// changed — a hover, a playback tick, a theme change. Each file is measured
/// once here, off the main thread, and the answer is kept.
final class AudioMetadataStore: @unchecked Sendable {
    static let shared = AudioMetadataStore()

    private let lock = NSLock()
    private var entries: [URL: AudioFileMetadata] = [:]

    func measure(_ url: URL) async -> AudioFileMetadata {
        if let cached = lock.withLock({ entries[url] }) { return cached }
        let measured = await Task.detached(priority: .utility) {
            AudioFileMetadata(url: url)
        }.value
        lock.withLock { entries[url] = measured }
        return measured
    }

    /// Called when a file is renamed, replaced, or deleted, so the next look at
    /// it measures the file that is there now.
    func forget(_ url: URL) {
        lock.withLock { _ = entries.removeValue(forKey: url) }
    }
}

extension View {
    /// Measures `url` once the row is on screen and hands the result back, so
    /// the row draws immediately and never opens a file while it is drawing.
    /// Re-runs if the row is reused for a different file.
    func audioMetadata(
        of url: URL,
        into receive: @escaping (AudioFileMetadata) -> Void
    ) -> some View {
        task(id: url) { receive(await AudioMetadataStore.shared.measure(url)) }
    }
}
