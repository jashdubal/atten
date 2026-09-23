import AVFoundation
import AttenCore
import XCTest
@testable import Atten

final class BookAudioTests: XCTestCase {
    func testAssemblyOffsetsTimingsWithoutChangingRelativeWords() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var urls: [URL] = []
        for index in 0..<2 {
            let url = try await ImmediateGenerator().generate(chapter: "chapter", in: directory.appendingPathComponent("chapter-\(index)"))
            let timing = TimedSegment(index: 0, text: "hello", start: 0, duration: 0.1,
                                      words: [TimedWord(text: "hello", start: 0.02, end: 0.08)])
            try NarrationTimings(segments: [timing]).save(beside: url)
            urls.append(url)
        }
        let result = try BookAudioAssembler.assemble(urls, in: directory)
        let timing = try XCTUnwrap(NarrationTimings.load(beside: result.url))
        XCTAssertEqual(timing.segments.map(\.index), [0, 1])
        XCTAssertEqual(timing.segments[1].start, result.ranges[1].0, accuracy: 0.00001)
        XCTAssertEqual(timing.segments[1].words[0].start, 0.02)
        XCTAssertEqual(timing.locate(time: 0.13).segment, 1)
        XCTAssertEqual(timing.locate(time: 0.13).word, 0)
        let second = try BookAudioAssembler.assemble(urls, in: directory)
        XCTAssertNotEqual(NarrationTimings.sidecarURL(for: result.url), NarrationTimings.sidecarURL(for: second.url))
        XCTAssertEqual(try NarrationTimings.load(beside: result.url), timing)
    }

    func testLongBookAssemblyStreamsThirtyMinutes() throws {
        guard ProcessInfo.processInfo.environment["ATTEN_RUN_PERFORMANCE"] == "1" else {
            throw XCTSkip("Run with ATTEN_RUN_PERFORMANCE=1 for the disk-backed long-audio check")
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("long.caf")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1))
        let frames: AVAudioFramePosition = 24_000 * 60 * 30
        do {
            let file = try AVAudioFile(forWriting: source, settings: format.settings)
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 65_536))
            buffer.frameLength = buffer.frameCapacity
            memset(buffer.floatChannelData![0], 0, Int(buffer.frameLength) * MemoryLayout<Float>.size)
            var written: AVAudioFramePosition = 0
            while written < frames {
                buffer.frameLength = AVAudioFrameCount(min(AVAudioFramePosition(buffer.frameCapacity), frames - written))
                try file.write(from: buffer)
                written += AVAudioFramePosition(buffer.frameLength)
            }
        }
        let result = try BookAudioAssembler.assemble([source], in: directory)
        XCTAssertEqual(try AVAudioFile(forReading: result.url).length, frames)
        XCTAssertEqual(result.ranges[0].1, 1800, accuracy: 0.001)
    }

    func testAssemblyPreservesChapterOffsetsAndOneTrack() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let generator = ImmediateGenerator()
        let first = try await generator.generate(chapter: "First", in: directory)
        let second = try await generator.generate(chapter: "Second", in: directory)
        let result = try BookAudioAssembler.assemble([first, second], in: directory)
        XCTAssertEqual(result.ranges.count, 2)
        XCTAssertEqual(result.ranges[0].0, 0)
        XCTAssertEqual(result.ranges[1].0, 0.1, accuracy: 0.0001)
        XCTAssertEqual(result.ranges[1].1, 0.2, accuracy: 0.0001)
        let audio = try AVAudioFile(forReading: result.url)
        XCTAssertEqual(audio.length, 4800)
        var book = BookRecord(title: "Book", format: .epub, sourcePath: "/book", chapters: [BookChapter(title: "First", text: "one"), BookChapter(title: "Second", text: "two")], voiceID: "af_heart", speed: 1, audioFormat: .wav)
        book.audioPath = result.url.path
        for index in book.chapters.indices {
            book.chapters[index].audioPath = result.url.path
            book.chapters[index].startTime = result.ranges[index].0
            book.chapters[index].endTime = result.ranges[index].1
        }
        let restored = try JSONDecoder().decode(BookRecord.self, from: JSONEncoder().encode(book))
        XCTAssertEqual(restored, book)
        XCTAssertEqual(restored.narrationTracks.count, 1)
        XCTAssertEqual(restored.narrationQueue, [result.url])
        XCTAssertEqual(restored.chapters[1].startTime, 0.1)
    }
}
