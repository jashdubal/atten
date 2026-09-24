import Foundation
import XCTest
@testable import Atten
@testable import AttenCore

final class PronunciationTests: XCTestCase {
    private let hermione = Pronunciation(match: "Hermione", say: "Her my oh nee")

    // MARK: - Substitution

    func testWholeWordsAreReplacedInAnyCase() {
        let text = PronouncedText(
            "Hermione waved. HERMIONE's owl, hermione! Hermiones and Hermionely stay.",
            pronunciations: [hermione]
        )
        XCTAssertEqual(
            text.spoken,
            "Her my oh nee waved. Her my oh nee's owl, Her my oh nee! Hermiones and Hermionely stay."
        )
    }

    func testSubstitutionsDoNotChainAndTheLongestMatchWins() {
        let text = PronouncedText("York, New York, and GIF.", pronunciations: [
            Pronunciation(match: "York", say: "Yawk"),
            Pronunciation(match: "New York", say: "Noo Yawk"),
            Pronunciation(match: "GIF", say: "York"),
        ])
        XCTAssertEqual(text.spoken, "Yawk, Noo Yawk, and York.")
    }

    func testBlankAndRepeatedEntriesAreIgnored() {
        let text = PronouncedText("Leave me be. Dr. Who", pronunciations: [
            Pronunciation(match: " ", say: "nothing"),
            Pronunciation(match: "be", say: ""),
            Pronunciation(match: "Dr.", say: "Doctor"),
            Pronunciation(match: "dr.", say: "Drive"),
        ])
        XCTAssertEqual(text.spoken, "Leave me be. Doctor Who")
        XCTAssertEqual(PronouncedText("Unchanged.", pronunciations: []).spoken, "Unchanged.")
    }

    // MARK: - Timing remap

    func testTimedWordsMapBackToTheOriginalWord() {
        var text = PronouncedText("Hermione waved.", pronunciations: [hermione])
        let spoken = TimedSegment(index: 0, text: "Her my oh nee waved.", start: 2, duration: 1, words: [
            TimedWord(text: "Her", start: 0.0, end: 0.1),
            TimedWord(text: "my", start: 0.1, end: 0.2),
            TimedWord(text: "oh", start: 0.2, end: 0.3),
            TimedWord(text: "nee", start: 0.3, end: 0.4),
            TimedWord(text: "waved", start: 0.45, end: 0.7),
            TimedWord(text: ".", start: 0.7, end: 0.75),
        ])

        let restored = text.restore(spoken)

        XCTAssertEqual(restored.text, "Hermione waved.")
        XCTAssertEqual(restored.words, [
            TimedWord(text: "Hermione", start: 0.0, end: 0.4),
            TimedWord(text: "waved", start: 0.45, end: 0.7),
            TimedWord(text: ".", start: 0.7, end: 0.75),
        ])
        XCTAssertEqual(restored.start, 2)
        XCTAssertEqual(restored.duration, 1)

        // The read-along underlines the original word while the substitute is spoken.
        let script = ReadAlongScript(timings: NarrationTimings(segments: [restored]))
        XCTAssertEqual(script.sentences.map(\.text), ["Hermione waved."])
        XCTAssertEqual(script.locate(time: 2.25), ReadAlongPlace(sentence: 0, word: 0..<8))
        XCTAssertEqual(script.locate(time: 2.5), ReadAlongPlace(sentence: 0, word: 9..<14))
    }

    func testEachSegmentGetsBackItsOwnOriginalsInOrder() {
        let original = "Hermione.\nThen HERMIONE, and Ron."
        var text = PronouncedText(original, pronunciations: [hermione, Pronunciation(match: "Ron", say: "Ronn")])
        XCTAssertEqual(text.spoken, "Her my oh nee.\nThen Her my oh nee, and Ronn.")

        let first = text.restore(TimedSegment(index: 0, text: "Her my oh nee.", start: 0, duration: 1, words: []))
        let plain = text.restore(TimedSegment(index: 1, text: "Nothing here.", start: 1, duration: 1, words: []))
        let second = text.restore(TimedSegment(
            index: 2, text: "Then Her my oh nee, and Ronn.", start: 2, duration: 1,
            words: ["Then", "Her", "my", "oh", "nee", ",", "and", "Ronn", "."].enumerated().map {
                TimedWord(text: $1, start: Double($0) / 10, end: Double($0 + 1) / 10)
            }
        ))

        XCTAssertEqual(first.text, "Hermione.")
        XCTAssertEqual(plain.text, "Nothing here.")
        XCTAssertEqual(second.text, "Then HERMIONE, and Ron.")
        XCTAssertEqual(second.words.map(\.text), ["Then", "HERMIONE", ",", "and", "Ron", "."])
        XCTAssertEqual(second.words[1], TimedWord(text: "HERMIONE", start: 0.1, end: 0.5))
    }

    func testASubstitutionTheEngineLostDoesNotHoldUpTheRest() {
        var text = PronouncedText("Hermione met Ron.", pronunciations: [hermione, Pronunciation(match: "Ron", say: "Ronn")])
        // The engine split the substitute across two segments.
        _ = text.restore(TimedSegment(index: 0, text: "Her my", start: 0, duration: 1, words: []))
        let rest = text.restore(TimedSegment(index: 1, text: "oh nee met Ronn.", start: 1, duration: 1, words: []))
        XCTAssertEqual(rest.text, "oh nee met Ron.")
    }

    // MARK: - Persistence

    func testABookWrittenBeforePronunciationsStillDecodes() throws {
        let json = Data("""
        [{"sourcePath": "/tmp/old.txt", "chapters": [{"text": "Once."}], "voiceID": "bf_emma"}]
        """.utf8)
        let book = try XCTUnwrap(try JSONDecoder().decode([BookRecord].self, from: json).first)
        XCTAssertNil(book.pronunciations)
        XCTAssertNil(book.pauseLength)
        XCTAssertEqual(book.voiceID, "bf_emma")

        // And a book without them writes nothing new for an older Atten to meet.
        let written = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(book)) as? [String: Any])
        XCTAssertNil(written["pronunciations"])
        XCTAssertNil(written["pauseLength"])
    }

    func testPronunciationsAndPauseRoundTrip() throws {
        var book = BookRecord(
            title: "Owls", format: .document, sourcePath: "/tmp/owls.txt",
            chapters: [BookChapter(title: "Owls", text: "Hermione.")],
            voiceID: "af_heart", speed: 1, audioFormat: .wav
        )
        book.pronunciations = [hermione]
        book.pauseLength = .long
        let json = try JSONEncoder().encode(book)
        let written = try XCTUnwrap(JSONSerialization.jsonObject(with: json) as? [String: Any])
        XCTAssertEqual(written["pronunciations"] as? [[String: String]], [["match": "Hermione", "say": "Her my oh nee"]])
        XCTAssertEqual(written["pauseLength"] as? String, "long")
        XCTAssertEqual(try JSONDecoder().decode(BookRecord.self, from: json), book)
    }

    func testAPauseFromANewerAttenIsReadAsNormal() throws {
        let json = Data(#"{"sourcePath": "/tmp/a.txt", "pauseLength": "dramatic"}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(BookRecord.self, from: json).pauseLength)
    }

    // MARK: - Requests

    func testThePauseReachesTheBackendOnlyWhenSet() throws {
        var request = GenerationRequest(
            text: "Hi", voiceID: "af_heart", speed: 1, format: .wav,
            outputDirectory: URL(fileURLWithPath: "/tmp"), filename: "hi"
        )
        func body() throws -> [String: Any] {
            try XCTUnwrap(JSONSerialization.jsonObject(
                with: PersistentBackendClient.requestLine(for: request, id: "1")
            ) as? [String: Any])
        }
        XCTAssertNil(try body()["pause"])
        request.pauseLength = .short
        XCTAssertEqual(try body()["pause"] as? String, "short")
    }
}

/// Narrating a book with pronunciations: the engine hears the substitutes,
/// the timings keep the book's own words.
@MainActor
final class PronunciationNarrationTests: XCTestCase {
    private final class RecordingGenerator: TTSGenerating, @unchecked Sendable {
        let engine = ImmediateGenerator()
        private(set) var requests: [GenerationRequest] = []

        func generate(_ request: GenerationRequest) async throws -> GenerationOutput {
            try await engine.generate(request)
        }

        func generateStream(_ request: GenerationRequest) -> AsyncThrowingStream<GenerationEvent, Error> {
            requests.append(request)
            return engine.generateStream(request)
        }

        func cancel() {}
    }

    func testTheEngineHearsTheSubstituteAndTheTimingsKeepTheOriginal() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AttenSay-\(UUID().uuidString)")
        let suite = "AttenSayTests.\(UUID().uuidString)"
        defer {
            UserDefaults().removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        let generator = RecordingGenerator()
        let model = AppModel(
            directories: AppDirectories(applicationSupport: root),
            settingsStore: SettingsStore(defaults: try XCTUnwrap(UserDefaults(suiteName: suite))),
            generator: generator
        )
        model.settings.defaultFormat = .wav
        await model.bookshelf.load()
        model.section = .studio
        let flow = model.createFlow
        flow.text = "Hermione waved."
        flow.pronunciations = [Pronunciation(match: "Hermione", say: "Her my oh nee")]
        flow.pauseLength = .long

        flow.generate()
        for _ in 0..<300 where model.bookshelf.isNarrating { try await Task.sleep(for: .milliseconds(10)) }
        try? await model.bookshelf.flushPersistence()

        XCTAssertEqual(generator.requests.map(\.text), ["Her my oh nee waved."])
        XCTAssertEqual(generator.requests.map(\.pauseLength), [.long])
        let book = try XCTUnwrap(model.bookshelf.book(id: XCTUnwrap(flow.draftID)))
        XCTAssertEqual(book.pronunciations, flow.pronunciations)
        XCTAssertEqual(book.chapters.map(\.text), ["Hermione waved."])
        let timings = try XCTUnwrap(NarrationTimings.load(beside: XCTUnwrap(book.audioURL)))
        XCTAssertEqual(timings.segments.map(\.text), ["Hermione waved."])
    }
}
