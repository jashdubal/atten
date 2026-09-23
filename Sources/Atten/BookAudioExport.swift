import AVFoundation
import Foundation

/// Export away from the destination, replacing it only after encoding succeeds.
enum BookAudioExport {
    static func export(_ source: URL, to destination: URL) async throws {
        let asset = AVURLAsset(url: source)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let temporary = destination.deletingLastPathComponent()
            .appendingPathComponent(".Atten-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: temporary) }
        session.outputURL = temporary
        session.outputFileType = .m4a
        await session.export()
        guard session.status == .completed else {
            throw session.error ?? CocoaError(.fileWriteUnknown)
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: destination)
        }
    }
}
