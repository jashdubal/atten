import AttenCore
import Foundation

/// Stands in for the speech engine: writes a short silent WAV wherever a real
/// generation would have written audio, so tests exercise the surrounding
/// bookkeeping without a Python process.
final class ImmediateGenerator: TTSGenerating, @unchecked Sendable {
    func generate(_ request: GenerationRequest) async throws -> GenerationOutput {
        try FileManager.default.createDirectory(
            at: request.outputDirectory,
            withIntermediateDirectories: true
        )
        let url = request.outputDirectory
            .appendingPathComponent(request.filename)
            .appendingPathExtension(request.format.rawValue)
        try silentWAV().write(to: url)
        return GenerationOutput(url: url, segmentCount: 1, sampleRate: 24_000)
    }

    func cancel() {}

    /// Writes a stand-in narration for one chapter and hands back its URL.
    func generate(chapter: String, in directory: URL) async throws -> URL {
        try await generate(
            GenerationRequest(
                text: chapter,
                voiceID: "af_heart",
                speed: 1,
                format: .wav,
                outputDirectory: directory,
                filename: chapter
            )
        ).url
    }

    private func silentWAV() -> Data {
        let sampleCount: UInt32 = 2_400
        let dataSize = sampleCount * 2
        var data = Data()
        data.append(contentsOf: "RIFF".utf8)
        append(36 + dataSize, to: &data)
        data.append(contentsOf: "WAVEfmt ".utf8)
        append(UInt32(16), to: &data)
        append(UInt16(1), to: &data)
        append(UInt16(1), to: &data)
        append(UInt32(24_000), to: &data)
        append(UInt32(48_000), to: &data)
        append(UInt16(2), to: &data)
        append(UInt16(16), to: &data)
        data.append(contentsOf: "data".utf8)
        append(dataSize, to: &data)
        data.append(Data(count: Int(dataSize)))
        return data
    }

    private func append<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }
}
