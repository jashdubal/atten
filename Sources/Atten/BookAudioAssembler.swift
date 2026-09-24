import AVFoundation
import AttenCore
import Foundation

/// Streams decoded samples to one file without holding a book in memory.
enum BookAudioAssembler {
    struct Result: Sendable {
        let url: URL
        let ranges: [(Double, Double)]
    }

    static func assemble(_ urls: [URL], in directory: URL) throws -> Result {
        let recordingDirectory = directory.appendingPathComponent("Audiobook-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: recordingDirectory, withIntermediateDirectories: true)
        var published = false
        defer { if !published { try? FileManager.default.removeItem(at: recordingDirectory) } }
        let destination = recordingDirectory.appendingPathComponent("Audiobook.caf")
        let temporary = recordingDirectory.appendingPathComponent("\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard let first = urls.first else { throw CocoaError(.fileReadUnknown) }
        let format = try AVAudioFile(forReading: first).processingFormat
        var ranges: [(Double, Double)] = []
        var segments: [TimedSegment] = []
        var frames: AVAudioFramePosition = 0
        do {
            let output = try AVAudioFile(forWriting: temporary, settings: format.settings)
            for url in urls {
                try Task.checkCancellation()
                let input = try AVAudioFile(forReading: url)
                guard input.processingFormat == format,
                      let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 65536) else {
                    throw NSError(domain: "BookAudio", code: 1, userInfo: [NSLocalizedDescriptionKey: "Chapter audio formats differ. Regenerate the book using one voice and format."])
                }
                guard input.length > 0 else { throw CocoaError(.fileReadCorruptFile) }
                let start = Double(frames) / format.sampleRate
                while input.framePosition < input.length {
                    try Task.checkCancellation()
                    try input.read(into: buffer)
                    try output.write(from: buffer)
                    frames += AVAudioFramePosition(buffer.frameLength)
                }
                ranges.append((start, Double(frames) / format.sampleRate))
                if let timings = try NarrationTimings.load(beside: url) {
                    segments += timings.offset(by: start, startingAt: segments.count).segments
                }
            }
        }
        try Task.checkCancellation()
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: destination)
        }
        if !segments.isEmpty { try NarrationTimings(segments: segments).save(beside: destination) }
        published = true
        return Result(url: destination, ranges: ranges)
    }
}
