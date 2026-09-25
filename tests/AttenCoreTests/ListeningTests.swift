import AttenCore
import AVFoundation
import Foundation
import XCTest
@testable import Atten

/// The player's chapters, its bookmarks — the Reader's, heard — and the sleep
/// timer.
@MainActor
final class ListeningTests: XCTestCase {

    // MARK: - Chapters

    private func threeChapters() -> ListeningMap {
        var book = BookRecord(
            title: "Book", format: .epub, sourcePath: "/book",
            chapters: [
                BookChapter(title: "One", text: "First."),
                BookChapter(title: "Two", text: "Second."),
                BookChapter(title: "Three", text: "Third."),
            ],
            voiceID: "af_heart", speed: 1, audioFormat: .wav
        )
        for (index, (start, end)) in [(0.0, 10.0), (10.0, 25.0), (25.0, 40.0)].enumerated() {
            book.chapters[index].startTime = start
            book.chapters[index].endTime = end
        }
        return ListeningMap(book: book, duration: 40)
    }

    func testAChapterOwnsItsFirstMomentAndNotItsLast() {
        let map = threeChapters()
        XCTAssertEqual(map.chapters.map(\.duration), [10, 15, 15])
        XCTAssertEqual(map.chapterIndex(at: 0), 0)
        XCTAssertEqual(map.chapterIndex(at: 9.999), 0)
        XCTAssertEqual(map.chapterIndex(at: 10), 1, "a boundary belongs to the chapter starting there")
        XCTAssertEqual(map.chapterIndex(at: 24.999), 1)
        XCTAssertEqual(map.chapterIndex(at: 25), 2)
        XCTAssertEqual(map.chapterIndex(at: 40), 2, "the very end is still the last chapter")
    }

    func testTimesOutsideTheRecordingBelongToTheNearestEnd() {
        let map = threeChapters()
        XCTAssertEqual(map.chapterIndex(at: -3), 0)
        XCTAssertEqual(map.chapterIndex(at: 400), 2)
        XCTAssertNil(ListeningMap(chapters: []).chapterIndex(at: 0))
    }

    func testAChapterWithNoRecordedEndRunsToTheNextOne() {
        var book = BookRecord(
            title: "Book", format: .epub, sourcePath: "/book",
            chapters: [BookChapter(title: "One", text: "A."), BookChapter(title: "Two", text: "B.")],
            voiceID: "af_heart", speed: 1, audioFormat: .wav
        )
        book.chapters[0].startTime = 0
        book.chapters[1].startTime = 6
        let map = ListeningMap(book: book, duration: 20)
        XCTAssertEqual(map.chapters.map(\.end), [6, 20])
    }

    // MARK: - Bookmarks

    private let chapterText = """
    Rain fell on the harbour. The boats knocked together.

    Nobody came down to the water that night.

    By morning the tide had turned. Gulls were back on the wall.
    """

    /// Chapter 1 of two, from 30 s to 90 s.
    private func harbourBook() -> BookRecord {
        var book = BookRecord(
            title: "Harbour", format: .epub, sourcePath: "/harbour",
            chapters: [BookChapter(title: "Before", text: "An opening line."), BookChapter(title: "Harbour", text: chapterText)],
            voiceID: "af_heart", speed: 1, audioFormat: .wav
        )
        book.chapters[0].startTime = 0
        book.chapters[0].endTime = 30
        book.chapters[1].startTime = 30
        book.chapters[1].endTime = 90
        return book
    }

    private func script(for book: BookRecord) -> ReadAlongScript {
        ReadAlongScript(estimating: book.playbackChapters.map { ($0.text, $0.startTime ?? 0, $0.endTime ?? 0) })
    }

    func testASentenceHeardIsMarkedOnTheParagraphItIsIn() throws {
        let book = harbourBook()
        let map = ListeningMap(book: book, duration: 90)
        let script = script(for: book)
        let sentence = try XCTUnwrap(script.sentences.first { $0.text == "Gulls were back on the wall." })

        let location = map.location(at: sentence.start, sentence: sentence.text)

        XCTAssertEqual(location, ReadingLocation(chapterIndex: 1, paragraphIndex: 2))
    }

    func testAMarkMadeWhileListeningPlaysFromItsOwnSentence() throws {
        let book = harbourBook()
        let map = ListeningMap(book: book, duration: 90)
        let script = script(for: book)
        let sentence = try XCTUnwrap(script.sentences.first { $0.text == "Gulls were back on the wall." })
        let location = try XCTUnwrap(map.location(at: sentence.start, sentence: sentence.text))

        let time = try XCTUnwrap(map.time(of: location, excerpt: sentence.text, script: script))

        XCTAssertEqual(time, sentence.start, accuracy: 0.0001,
                       "the second sentence of a paragraph, not the paragraph's first")
    }

    func testAReaderBookmarkPlaysFromTheStartOfItsParagraph() throws {
        let book = harbourBook()
        let map = ListeningMap(book: book, duration: 90)
        let script = script(for: book)
        let paragraph = book.chapters[1].paragraphs[2]
        let reader = Bookmark(location: ReadingLocation(chapterIndex: 1, paragraphIndex: 2), excerpt: String(paragraph.prefix(160)))
        let opening = try XCTUnwrap(script.sentences.first { $0.text == "By morning the tide had turned." })

        let time = try XCTUnwrap(map.time(of: reader.location, excerpt: reader.excerpt, script: script))

        XCTAssertEqual(time, opening.start, accuracy: 0.0001)
        XCTAssertEqual(map.location(at: time, sentence: opening.text), reader.location, "and it round-trips")
    }

    /// Without a script there is only the text's length to go on, but the
    /// two directions still agree.
    func testWithoutAScriptTimeAndPlaceStillRoundTrip() throws {
        let map = ListeningMap(book: harbourBook(), duration: 90)
        for paragraph in 0..<3 {
            let location = ReadingLocation(chapterIndex: 1, paragraphIndex: paragraph)
            let time = try XCTUnwrap(map.time(of: location))
            XCTAssertGreaterThanOrEqual(time, 30)
            XCTAssertLessThan(time, 90)
            XCTAssertEqual(map.location(at: time + 0.01), location)
        }
        XCTAssertEqual(try XCTUnwrap(map.time(of: ReadingLocation(chapterIndex: 1))), 30, accuracy: 0.0001)
        XCTAssertNil(map.time(of: ReadingLocation(chapterIndex: 7)))
    }

    func testAPDFPageIsPlacedByHowFarThroughItsChapterItIs() throws {
        var book = harbourBook()
        book.chapters[0].pageIndex = 0
        book.chapters[1].pageIndex = 10
        let map = ListeningMap(book: book, duration: 90)

        let time = try XCTUnwrap(map.time(of: ReadingLocation(chapterIndex: 0, pageIndex: 5)))

        XCTAssertEqual(time, 15, accuracy: 0.0001)
    }

    func testAChapterPlayedFromItsOwnFileKeepsTheBooksChapterNumber() throws {
        let book = harbourBook()
        let map = ListeningMap(chapter: 1, of: book, duration: 60)
        XCTAssertEqual(map.location(at: 59), ReadingLocation(chapterIndex: 1, paragraphIndex: 2))
        XCTAssertEqual(try XCTUnwrap(map.time(of: ReadingLocation(chapterIndex: 1))), 0)
    }

    /// The player writes into the same list the Reader reads, and reads the
    /// Reader's marks back out of it.
    func testBookmarksAreSharedWithTheReader() async throws {
        let (model, directory) = try makeModel()
        var book = harbourBook()
        let audio = try Self.silentAudio(seconds: 4, in: directory)
        book.sourcePath = directory.appendingPathComponent("harbour.txt").path
        try Data(chapterText.utf8).write(to: URL(fileURLWithPath: book.sourcePath))
        book.audioPath = audio.path
        book.chapters[0].endTime = 1
        book.chapters[1].startTime = 1
        book.chapters[1].endTime = 4
        try await BookLibraryStore(fileURL: AppDirectories(applicationSupport: directory).booksFile).save([book])
        await model.bookshelf.load()
        let loaded = try XCTUnwrap(model.bookshelf.book(id: book.id))
        XCTAssertTrue(loaded.hasBookAudio)
        model.listen(to: loaded, chapter: loaded.chapters[1])
        model.pause()
        let script = script(for: loaded)
        let heard = try XCTUnwrap(script.sentences.firstIndex { $0.text == "The boats knocked together." })

        model.addBookmark(sentence: heard, of: script)
        model.addBookmark(sentence: heard, of: script)

        let marks = try XCTUnwrap(model.bookshelf.book(id: book.id)?.bookmarks)
        XCTAssertEqual(marks.count, 1, "the same sentence twice is one mark")
        XCTAssertEqual(marks.first?.location, ReadingLocation(chapterIndex: 1, paragraphIndex: 0))
        XCTAssertEqual(marks.first?.excerpt, "The boats knocked together.")

        model.bookshelf.toggleBookmark(
            at: ReadingLocation(chapterIndex: 1, paragraphIndex: 1),
            excerpt: "Nobody came down to the water that night.",
            in: book.id
        )
        let reader = try XCTUnwrap(model.bookshelf.book(id: book.id)?.bookmarks.first { $0.location.paragraphIndex == 1 })
        let expected = try XCTUnwrap(script.sentences.first { $0.text == reader.excerpt }).start
        XCTAssertEqual(try XCTUnwrap(model.time(of: reader, script: script)), expected, accuracy: 0.0001)
    }

    /// A shelf from before the player could bookmark still decodes, marks
    /// and all, and the player can play those marks.
    func testAnOldShelfStillDecodesAndItsBookmarksPlay() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AttenOldShelf-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("books.json")
        let old = """
        [{"sourcePath":"/old.epub","title":"Old","format":"epub","voiceID":"af_heart","speed":1,
          "audioFormat":"wav","addedAt":700000000,
          "chapters":[{"title":"One","text":"A.\\n\\nB.","startTime":0,"endTime":10},
                      {"title":"Two","text":"C.\\n\\nD.","startTime":10,"endTime":20}],
          "bookmarks":[{"id":"6F1C1A4E-7E5B-4E0B-9D7F-0C6E0B1C2D3E","excerpt":"D.",
                        "createdAt":700000100,"location":{"chapterIndex":1,"paragraphIndex":1}}]}]
        """
        try Data(old.utf8).write(to: file)

        let books = try await BookLibraryStore(fileURL: file).load()

        let book = try XCTUnwrap(books.first)
        XCTAssertEqual(book.bookmarks.count, 1)
        XCTAssertEqual(book.bookmarks.first?.location, ReadingLocation(chapterIndex: 1, paragraphIndex: 1))
        let time = try XCTUnwrap(ListeningMap(book: book, duration: 20).time(of: book.bookmarks[0].location))
        XCTAssertEqual(time, 15, accuracy: 0.0001)
    }

    // MARK: - Sleep timer

    private final class Clock {
        var now = Date(timeIntervalSince1970: 1_000_000)
        func advance(_ seconds: TimeInterval) { now += seconds }
    }

    private final class Box<Value> {
        var value: Value
        init(_ value: Value) { self.value = value }
    }

    private func makeTimer(_ playback: SleepTimer.Playback) -> (SleepTimer, Clock, Box<SleepTimer.Playback>, Box<Float>, Box<Int>) {
        let clock = Clock()
        let timer = SleepTimer(clock: { clock.now })
        let state = Box(playback), volume = Box<Float>(1), pauses = Box(0)
        timer.observe = { state.value }
        timer.setVolume = { volume.value = $0 }
        timer.pause = { pauses.value += 1 }
        return (timer, clock, state, volume, pauses)
    }

    func testAMinutesTimerFadesOverItsLastTenSecondsThenPauses() {
        let (timer, clock, _, volume, pauses) = makeTimer(.init(isPlaying: true))
        timer.set(.minutes(15), ticking: false)
        XCTAssertEqual(timer.remaining, 900)

        clock.advance(880); timer.tick()
        XCTAssertEqual(volume.value, 1)
        XCTAssertEqual(timer.remaining, 20)
        clock.advance(10); timer.tick()
        XCTAssertEqual(volume.value, 1, "the fade starts at ten seconds left")
        clock.advance(5); timer.tick()
        XCTAssertEqual(volume.value, 0.5, accuracy: 0.001)
        XCTAssertEqual(pauses.value, 0)
        clock.advance(5); timer.tick()

        XCTAssertEqual(pauses.value, 1)
        XCTAssertEqual(volume.value, 1, "the next listen starts at full volume")
        XCTAssertNil(timer.choice)
        XCTAssertNil(timer.remaining)
    }

    func testAPauseHoldsTheCountdown() {
        let (timer, clock, state, _, pauses) = makeTimer(.init(isPlaying: true))
        timer.set(.minutes(15), ticking: false)
        clock.advance(600); timer.tick()
        state.value.isPlaying = false
        timer.tick()
        clock.advance(3_600); timer.tick()
        XCTAssertEqual(timer.remaining, 300)
        state.value.isPlaying = true
        timer.tick()
        clock.advance(100); timer.tick()
        XCTAssertEqual(timer.remaining, 200)
        XCTAssertEqual(pauses.value, 0)
    }

    func testEndOfChapterFadesIntoTheChaptersEnd() {
        let (timer, _, state, volume, pauses) = makeTimer(.init(isPlaying: true, secondsToChapterEnd: 125, chapter: "a"))
        timer.set(.endOfChapter, ticking: false)
        XCTAssertEqual(timer.remaining, 125)
        XCTAssertEqual(volume.value, 1)
        state.value.secondsToChapterEnd = 2.5; timer.tick()
        XCTAssertEqual(volume.value, 0.25, accuracy: 0.001)
        state.value.secondsToChapterEnd = 0; timer.tick()
        XCTAssertEqual(pauses.value, 1)
        XCTAssertNil(timer.choice)
    }

    /// The chapter can end between two ticks; the next one already reads the
    /// next chapter's full length.
    func testEndOfChapterStopsWhenTheChapterRunsOutBetweenTicks() {
        let (timer, _, state, _, pauses) = makeTimer(.init(isPlaying: true, secondsToChapterEnd: 0.2, chapter: "a"))
        timer.set(.endOfChapter, ticking: false)
        state.value = .init(isPlaying: true, secondsToChapterEnd: 600, chapter: "b")
        timer.tick()
        XCTAssertEqual(pauses.value, 1)
    }

    func testSkippingToAnotherChapterRetargetsEndOfChapter() {
        let (timer, _, state, volume, pauses) = makeTimer(.init(isPlaying: true, secondsToChapterEnd: 300, chapter: "a"))
        timer.set(.endOfChapter, ticking: false)
        state.value = .init(isPlaying: true, secondsToChapterEnd: 600, chapter: "b")
        timer.tick()
        XCTAssertEqual(pauses.value, 0)
        XCTAssertEqual(timer.remaining, 600)
        XCTAssertEqual(volume.value, 1)
    }

    /// Listening while it narrates, the chapter's end is not known until the
    /// next chapter has begun — so the timer waits for that.
    func testEndOfChapterWhileNarratingStopsWhenTheNextChapterBegins() {
        let (timer, _, state, volume, pauses) = makeTimer(.init(isPlaying: true, secondsToChapterEnd: nil, chapter: "0"))
        timer.set(.endOfChapter, ticking: false)
        XCTAssertNil(timer.remaining)
        XCTAssertEqual(volume.value, 1)
        state.value.chapter = "1"
        timer.tick()
        XCTAssertEqual(pauses.value, 1)
    }

    func testTurningTheTimerOffRestoresTheVolume() {
        let (timer, _, state, volume, pauses) = makeTimer(.init(isPlaying: true, secondsToChapterEnd: 5, chapter: "a"))
        timer.set(.endOfChapter, ticking: false)
        XCTAssertEqual(volume.value, 0.5, accuracy: 0.001)
        timer.set(nil)
        XCTAssertEqual(volume.value, 1)
        state.value.secondsToChapterEnd = 0
        timer.tick()
        XCTAssertEqual(pauses.value, 0)
    }

    func testProgressiveChapterEndIsTheNextChaptersFirstSegment() {
        var timeline = ProgressiveTimeline()
        let url = URL(fileURLWithPath: "/seg.wav")
        timeline.append(chapterIndex: 0, url: url, timing: TimedSegment(index: 0, text: "a", start: 0, duration: 4, words: []))
        timeline.append(chapterIndex: 0, url: url, timing: TimedSegment(index: 1, text: "b", start: 4, duration: 3, words: []))
        XCTAssertNil(timeline.chapterEnd(at: 5), "the next chapter has not been narrated yet")
        timeline.append(chapterIndex: 1, url: url, timing: TimedSegment(index: 0, text: "c", start: 0, duration: 2, words: []))
        XCTAssertEqual(timeline.chapterEnd(at: 5), 7)
        XCTAssertNil(timeline.chapterEnd(at: 8))
    }

    // MARK: - Fixtures

    private func makeModel() throws -> (AppModel, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttenListeningTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "AttenListeningTests.\(UUID().uuidString)"))
        let model = AppModel(
            directories: AppDirectories(applicationSupport: directory),
            settingsStore: SettingsStore(defaults: defaults),
            generator: ImmediateGenerator()
        )
        return (model, directory)
    }

    /// A silent recording of any length, at the lowest sample rate a WAV
    /// is written at.
    static func silentAudio(seconds: Double, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent("silence-\(UUID().uuidString).wav")
        let rate = 8_000.0
        let file = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate,
            AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
        ])
        let frames = AVAudioFrameCount(seconds * rate)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames))
        buffer.frameLength = frames
        // Truly silent: the buffer's memory is not promised to start zeroed,
        // and a test that plays this should not be heard.
        if let samples = buffer.floatChannelData?[0] { samples.update(repeating: 0, count: Int(frames)) }
        try file.write(from: buffer)
        return url
    }
}
