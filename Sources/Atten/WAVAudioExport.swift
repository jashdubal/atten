import AVFoundation
import CoreAudio
import Foundation

/// Export to a linear-PCM `.wav`, via `AVAssetReader`/`AVAssetWriter` rather
/// than `AVAssetExportSession` — its presets never included WAV, only
/// compressed formats like M4A with a codec of their own.
enum WAVAudioExport {
    enum ExportError: LocalizedError {
        case noAudioTrack

        var errorDescription: String? {
            switch self {
            case .noAudioTrack: "This file has no audio to export."
            }
        }
    }

    static func export(_ source: URL, to destination: URL) async throws {
        let asset = AVURLAsset(url: source)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw ExportError.noAudioTrack
        }
        let (sampleRate, channelCount) = try await Self.audioFormat(of: track)

        // The reader decodes to linear PCM in whatever shape it likes; the
        // writer, unlike the reader, refuses to start without an explicit
        // sample rate and channel count for the file it is asked to produce.
        let readerSettings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM]
        let writerSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: readerSettings)
        reader.add(output)

        let temporary = destination.deletingLastPathComponent()
            .appendingPathComponent(".Atten-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: temporary) }

        let writer = try AVAssetWriter(outputURL: temporary, fileType: .wav)
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: writerSettings)
        input.expectsMediaDataInRealTime = false
        writer.add(input)

        guard reader.startReading() else { throw reader.error ?? CocoaError(.fileReadCorruptFile) }
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        try await SampleBufferPump(reader: reader, output: output, writer: writer, input: input).run()

        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: destination)
        }
    }

    private static func audioFormat(of track: AVAssetTrack) async throws -> (sampleRate: Double, channelCount: Int) {
        guard let description = try await track.load(.formatDescriptions).first else {
            throw ExportError.noAudioTrack
        }
        guard let basic = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee else {
            throw ExportError.noAudioTrack
        }
        return (basic.mSampleRate, Int(basic.mChannelsPerFrame))
    }
}

/// Copies sample buffers from an `AVAssetReaderTrackOutput` to an
/// `AVAssetWriterInput` until the track is exhausted. None of AVFoundation's
/// reader/writer types are `Sendable` — same reason `ProcessExecution` in
/// `BackendClient` exists for `Process` — so the pump owns them on one queue
/// instead of moving them through a `@Sendable` closure itself.
private final class SampleBufferPump: @unchecked Sendable {
    private let reader: AVAssetReader
    private let output: AVAssetReaderTrackOutput
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput

    init(reader: AVAssetReader, output: AVAssetReaderTrackOutput, writer: AVAssetWriter, input: AVAssetWriterInput) {
        self.reader = reader
        self.output = output
        self.writer = writer
        self.input = input
    }

    func run() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let queue = DispatchQueue(label: "com.jashdubal.Atten.wav-export")
            input.requestMediaDataWhenReady(on: queue) { [self] in
                while input.isReadyForMoreMediaData {
                    if let buffer = output.copyNextSampleBuffer() {
                        input.append(buffer)
                        continue
                    }
                    input.markAsFinished()
                    if reader.status == .failed {
                        writer.cancelWriting()
                        continuation.resume(throwing: reader.error ?? CocoaError(.fileReadCorruptFile))
                        return
                    }
                    writer.finishWriting {
                        if self.writer.status == .completed {
                            continuation.resume()
                        } else {
                            continuation.resume(throwing: self.writer.error ?? CocoaError(.fileWriteUnknown))
                        }
                    }
                    return
                }
            }
        }
    }
}
