import AttenCore
import Foundation
import XCTest
@testable import Atten

final class ChapterDetectionTests: XCTestCase {
    private let headed = "# One\n\nThe first part.\n\n# Two\n\nThe second part."

    func testAutoDividesAtHeadings() {
        let chapters = ChapterDetection.auto.chapters(in: headed, title: "Draft")
        XCTAssertEqual(chapters.map(\.title), ["One", "Two"])
        XCTAssertEqual(chapters.map(\.text), ["The first part.", "The second part."])
    }

    func testAutoCutsLongTextWithoutHeadingsIntoParts() {
        let paragraph = Array(repeating: "word", count: 500).joined(separator: " ")
        let chapters = ChapterDetection.auto.chapters(in: [paragraph, paragraph, paragraph].joined(separator: "\n\n"), title: "Draft")
        XCTAssertGreaterThan(chapters.count, 1)
    }

    func testShortTextIsOneChapterNamedForTheDraft() {
        for detection in ChapterDetection.allCases {
            let chapters = detection.chapters(in: "Just a line.", title: "Draft")
            XCTAssertEqual(chapters.map(\.title), ["Draft"], "\(detection)")
            XCTAssertEqual(chapters.map(\.text), ["Just a line."], "\(detection)")
        }
    }

    func testNoneKeepsOneChapterAndReadsHeadingsWithoutTheirMarks() {
        let chapters = ChapterDetection.none.chapters(in: headed, title: "Draft")
        XCTAssertEqual(chapters.count, 1)
        XCTAssertEqual(chapters[0].text, "One\n\nThe first part.\n\nTwo\n\nThe second part.")
    }

    func testHeadingsDividesOnlyAtHeadings() {
        XCTAssertEqual(ChapterDetection.headings.chapters(in: headed, title: "Draft").count, 2)
        let paragraph = Array(repeating: "word", count: 2_000).joined(separator: " ")
        XCTAssertEqual(ChapterDetection.headings.chapters(in: paragraph, title: "Draft").count, 1)
    }

    func testOpeningHeadingIsWhatAPastedDocumentCallsItself() {
        XCTAssertEqual(ChapterDetection.openingHeading(in: "\n# The Title\nBody."), "The Title")
        XCTAssertNil(ChapterDetection.openingHeading(in: "Body first.\n# Later"))
    }

    func testSpokenExtentFollowsWordsThroughOneChapter() {
        let text = "One two three. Four five."
        let extent = SpokenExtent(text: text, chapters: [text], chapterIndex: 0, spokenWords: 3)
        XCTAssertEqual(extent.words, 3)
        XCTAssertEqual(extent.totalWords, 5)
        XCTAssertEqual((text as NSString).substring(to: extent.utf16Offset), "One two three.")
    }

    func testSpokenExtentFindsLaterChaptersPastTheirHeadings() {
        let chapters = ChapterDetection.auto.chapters(in: headed, title: "Draft").map(\.text)
        let extent = SpokenExtent(text: headed, chapters: chapters, chapterIndex: 1, spokenWords: 2)
        XCTAssertEqual((headed as NSString).substring(to: extent.utf16Offset), "# One\n\nThe first part.\n\n# Two\n\nThe second")
        XCTAssertEqual(extent.totalWords, 8)
    }

    func testSpokenExtentNeverRunsPastTheText() {
        let extent = SpokenExtent(text: "Short.", chapters: ["Short."], chapterIndex: 0, spokenWords: .max)
        XCTAssertEqual(extent.fraction, 1)
        XCTAssertEqual(extent.utf16Offset, 6)
    }

    func testADraftIsCalledByItsOpeningWords() {
        XCTAssertEqual(ChapterDetection.derivedTitle(from: "\n  Hello there. How are you?\nMore."), "Hello there")
        XCTAssertEqual(ChapterDetection.derivedTitle(from: "# The Title\n\nBody."), "The Title")
        XCTAssertEqual(ChapterDetection.derivedTitle(from: "Is it raining? Yes."), "Is it raining")
        // The clause cut and the six-word cap agree here (the comma lands on
        // word six), so the derived title is much shorter than the sentence.
        XCTAssertEqual(
            ChapterDetection.derivedTitle(from: "The creek is bright this morning, and the meadow is ready for a new story."),
            "The creek is bright this morning"
        )
        XCTAssertEqual(ChapterDetection.derivedTitle(from: "One two three four five six seven eight."), "One two three four five six")
        XCTAssertNil(ChapterDetection.derivedTitle(from: " \n\n "))
        let long = String(repeating: "x", count: 80)
        XCTAssertEqual(ChapterDetection.derivedTitle(from: long), String(repeating: "x", count: 60) + "…")
    }

    func testEstimateLabels() {
        XCTAssertEqual(ListenEstimator.audioLabel(16 * 60), "≈ 16 min of audio")
        XCTAssertEqual(ListenEstimator.remainingLabel(90), "~2 min remaining")
    }
}

@MainActor
final class CreateFlowTests: XCTestCase {
    private var root: URL!
    private var model: AppModel!
    private var suite: String!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("AttenCreate-\(UUID().uuidString)")
        suite = "AttenCreateTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        model = AppModel(
            directories: AppDirectories(applicationSupport: root),
            settingsStore: SettingsStore(defaults: defaults),
            generator: ImmediateGenerator()
        )
        // The stand-in engine writes WAV, so drafts are made as WAV.
        model.settings.defaultFormat = .wav
        await model.bookshelf.load()
    }

    override func tearDown() async throws {
        try? await model.bookshelf.flushPersistence()
        UserDefaults().removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }

    private var flow: CreateFlowModel { model.createFlow }

    private func waitForNarration() async throws {
        for _ in 0..<300 {
            if !model.bookshelf.isNarrating { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("narration did not finish")
    }

    func testStatesRunFromEmptyThroughEditing() {
        XCTAssertEqual(flow.state, .empty)
        flow.startWriting()
        XCTAssertEqual(flow.state, .editing)
        XCTAssertEqual(flow.generateDisabledReason, "Add text to generate")
        XCTAssertFalse(flow.canGenerate)
        flow.text = "Hello there."
        XCTAssertTrue(flow.canGenerate)
        model.newDraft()
        XCTAssertEqual(flow.state, .empty)
    }

    func testGenerateSaysWhyWhenTheEngineIsMissing() {
        flow.startWriting()
        flow.text = "Hello there."
        model.locateBackend = { false }
        XCTAssertEqual(flow.generateDisabledReason, "Speech engine not found")
        XCTAssertFalse(flow.canGenerate)
    }

    func testGenerateSaysWhichModelAVoiceStillNeeds() {
        flow.startWriting()
        flow.text = "Hello there."
        model.selectedVoiceID = "jf_alpha"
        XCTAssertEqual(flow.generateDisabledReason, "Voice needs download")
        XCTAssertFalse(flow.canGenerate)
    }

    func testTheSampleOpensTheEditor() {
        flow.loadSample()
        XCTAssertEqual(flow.state, .editing)
        XCTAssertEqual(flow.text, CreateFlowModel.sampleText)
    }

    func testTheDraftIsASilentLibraryItemFromItsFirstSave() throws {
        flow.text = "A draft worth keeping."
        flow.saveNow()
        let draft = try XCTUnwrap(model.bookshelf.book(id: XCTUnwrap(flow.draftID)))
        XCTAssertEqual(LibraryItem.book(draft).state, .silent)
        XCTAssertTrue(flow.isSaved)

        flow.text = "A draft worth keeping, revised."
        flow.saveNow()
        XCTAssertEqual(model.bookshelf.books.count, 1)
    }

    /// A draft nobody named is saved under its opening words, not
    /// "Untitled"; a typed title still wins (#98).
    func testAnUntitledDraftTakesItsTitleFromItsText() throws {
        flow.text = "A walk to the creek. It was cold."
        flow.saveNow()
        let id = try XCTUnwrap(flow.draftID)
        XCTAssertEqual(model.bookshelf.book(id: id)?.title, "A walk to the creek")

        flow.title = "Morning"
        flow.saveNow()
        XCTAssertEqual(model.bookshelf.book(id: id)?.title, "Morning")
    }

    func testNothingIsSavedUntilThereAreWords() {
        flow.startWriting()
        flow.saveNow()
        XCTAssertNil(flow.draftID)
        XCTAssertTrue(model.bookshelf.books.isEmpty)
    }

    func testGeneratingAtNormalSpeedFinishesAndCalibrates() async throws {
        model.settings.defaultSpeed = 1.6
        model.section = .studio
        flow.text = "# One\n\nThe first part.\n\n# Two\n\nThe second part."
        flow.generate()
        XCTAssertEqual(flow.state, .generating)
        try await waitForNarration()
        XCTAssertNil(model.bookshelf.errorMessage)

        XCTAssertEqual(flow.state, .done)
        let book = try XCTUnwrap(model.bookshelf.book(id: XCTUnwrap(flow.draftID)))
        XCTAssertEqual(book.speed, 1.0)
        XCTAssertEqual(book.chapters.map(\.title), ["One", "Two"])
        XCTAssertEqual(LibraryItem.book(book).state, .voiced)
        XCTAssertEqual(flow.toastBookID, book.id)
        XCTAssertNotNil(model.settings.listenWordsPerMinuteByVoice[book.voiceID])
        XCTAssertNotEqual(model.settings.listenRealTimeFactor, ListenEstimator.defaultRealTimeFactor)
        XCTAssertNil(model.bookshelf.successMessage)
    }

    /// P3: a finished generation lands in the Library with its Undo toast
    /// and nothing plays until someone presses Play. P5: segments arriving
    /// leave progressive playback idle, and a system play command (a media
    /// key, headphones reconnecting) does not count as that Play (#98).
    func testGeneratingPlaysNothingAndOpensNoPlayer() async throws {
        model.section = .studio
        var statesWhileNarrating: [ProgressivePlayer.State] = []
        let receive = model.bookshelf.onSegmentReady
        model.bookshelf.onSegmentReady = { [weak model] bookID, chapter, segment in
            receive?(bookID, chapter, segment)
            model?.remotePlayOrPause(playing: true)
            if let state = model?.progressivePlayer.state { statesWhileNarrating.append(state) }
        }
        flow.loadSample()
        flow.generate()
        try await waitForNarration()

        XCTAssertEqual(statesWhileNarrating, [.idle])
        XCTAssertEqual(flow.state, .done)
        XCTAssertEqual(model.section, .studio)
        XCTAssertNil(model.queue.current)
        XCTAssertFalse(model.isPlaying)

        flow.leaveForLibrary()
        XCTAssertEqual(model.section, .library)
        XCTAssertNotNil(flow.toastBookID)
        XCTAssertNil(model.playerTitle)
        XCTAssertFalse(model.isPlaying)
        XCTAssertFalse(model.progressivePlayer.isPlaying)
    }

    func testFinishingAfterLeavingCreateClearsItForTheNextDraft() async throws {
        model.section = .studio
        flow.text = "Narrate me."
        flow.generate()
        model.section = .library
        try await waitForNarration()

        XCTAssertEqual(flow.state, .empty)
        XCTAssertNotNil(flow.toastBookID)
        XCTAssertEqual(model.bookshelf.books.count, 1)
    }

    func testADraftStartedWhileAnotherIsNarratedStillHearsItFinish() async throws {
        flow.text = "The first draft."
        flow.generate()
        model.newDraft()
        flow.text = "The second draft."
        XCTAssertTrue(flow.canGenerate, "It can queue behind the first")
        try await waitForNarration()

        XCTAssertNotNil(flow.toastBookID)
        XCTAssertEqual(flow.state, .editing)
        XCTAssertEqual(flow.text, "The second draft.")
    }

    func testUndoRemovesTheNarrationAndKeepsTheDraft() async throws {
        flow.text = "Narrate me, then change my mind."
        flow.generate()
        try await waitForNarration()
        let id = try XCTUnwrap(flow.toastBookID)
        let audio = try XCTUnwrap(model.bookshelf.book(id: id)?.audioURL)

        flow.undoNarration()

        let book = try XCTUnwrap(model.bookshelf.book(id: id))
        XCTAssertEqual(LibraryItem.book(book).state, .silent)
        XCTAssertFalse(FileManager.default.fileExists(atPath: audio.path))
        XCTAssertEqual(book.chapters.first?.text, "Narrate me, then change my mind.")
        XCTAssertNil(flow.toastBookID)
    }

    func testSegmentsReportProgressAndReachTheHook() async throws {
        var reached: [Int] = []
        model.bookshelf.onSegmentReady = { _, chapter, _ in reached.append(chapter) }
        flow.text = "# One\n\nThe first part.\n\n# Two\n\nThe second part."
        flow.generate()
        try await waitForNarration()
        XCTAssertEqual(reached, [0, 1])
    }

    /// P5: as each segment lands, `AppModel` feeds it to `progressivePlayer`,
    /// and `CreateFlowModel` can turn where that player has reached back into
    /// an exact range of the draft's own text.
    func testPlayingSentenceRangeTracksProgressivePlaybackWhileGenerating() async throws {
        var capturedRanges: [(location: Int, length: Int)?] = []
        model.bookshelf.onSegmentReady = { [weak model] bookID, chapterIndex, segment in
            guard let model else { return }
            model.progressivePlayer.receive(bookID: bookID, chapterIndex: chapterIndex, segment: segment)
            // Nothing is actually playing in this test, so position never
            // moves on its own — seek to what just landed to look at it.
            model.progressivePlayer.seek(to: model.progressivePlayer.duration)
            capturedRanges.append(model.createFlow.playingSentenceRange)
        }
        let text = "# One\n\nFirst chapter text.\n\n# Two\n\nSecond chapter text."
        flow.text = text
        flow.generate()
        try await waitForNarration()

        XCTAssertEqual(capturedRanges.count, 2, "one segment per chapter")
        let first = try XCTUnwrap(capturedRanges[0])
        XCTAssertEqual((text as NSString).substring(with: NSRange(location: first.location, length: first.length)), "First chapter text.")
        let second = try XCTUnwrap(capturedRanges[1])
        XCTAssertEqual((text as NSString).substring(with: NSRange(location: second.location, length: second.length)), "Second chapter text.")

        // Once narration finishes, nothing should still claim to be playing
        // along with a draft that is no longer being generated.
        XCTAssertNil(flow.playingSentenceRange)
    }

    func testTheOldStudioDraftIsImportedOnce() {
        XCTAssertTrue(flow.importLegacyDraft("# Kept\nWords from before drafts were books."))
        XCTAssertTrue(flow.importLegacyDraft("# Kept\nWords from before drafts were books."))
        XCTAssertEqual(model.bookshelf.books.map(\.title), ["Kept"])
        XCTAssertEqual(flow.state, .empty)
    }

    func testPreviewsAreCachedPerVoicePerSentence() {
        let voice = VoiceCatalog.defaultVoice
        XCTAssertEqual(model.voicePreviewURL(voice).lastPathComponent, "preview-\(voice.id).wav")
        flow.text = "First sentence here. Second one."
        XCTAssertEqual(flow.firstSentence, "First sentence here.")
        let own = try? XCTUnwrap(flow.previewURL(for: voice))
        XCTAssertNotEqual(own, model.voicePreviewURL(voice))
        XCTAssertEqual(own, model.voicePreviewURL(voice, speaking: "First sentence here."))
    }

    func testPreviewAppliesPronunciationsAndTheirOwnCacheKey() throws {
        let voice = VoiceCatalog.defaultVoice
        flow.text = "Say Kubernetes correctly."
        let before = try XCTUnwrap(flow.previewURL(for: voice))
        XCTAssertEqual(before, model.voicePreviewURL(voice, speaking: "Say Kubernetes correctly."))

        flow.pronunciations = [Pronunciation(match: "Kubernetes", say: "koo-ber-NET-eez")]

        let after = try XCTUnwrap(flow.previewURL(for: voice))
        XCTAssertNotEqual(after, before, "a changed pronunciation should miss the old cache entry")
        XCTAssertEqual(after, model.voicePreviewURL(voice, speaking: "Say koo-ber-NET-eez correctly."))
    }
}
