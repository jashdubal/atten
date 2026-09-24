import AppKit
import AttenCore
import Foundation
import Observation
import UniformTypeIdentifiers

/// The four states Create moves through.
enum CreateState: Equatable {
    /// Nothing yet: a place to drop, paste or start writing.
    case empty
    /// Text is here, with a narrator and a Generate button beside it.
    case editing
    /// The draft is being narrated; the text is read-only in place.
    case generating
    /// Narration finished; the cover is on its way to the Library.
    case done
}

/// Create as a flow over the window.
///
/// The draft is a silent book on the shelf from its first saved word
/// (`BookshelfModel.saveDraft`), and generating it is `narrate` like any other
/// book — so narration keeps going if Create is left, and a finished draft is
/// simply a voiced book in the Library. The text and title live on `AppModel`
/// so every older way into Create (duplicating a project, the menu) still
/// lands its text here.
@MainActor
@Observable
final class CreateFlowModel {
    /// Set by `AppModel` once it exists.
    @ObservationIgnored weak var app: AppModel?

    /// The shelf's record for this draft, once it has been saved.
    private(set) var draftID: UUID?
    /// Set when someone chose to write, so an empty editor is still editing.
    private(set) var isWriting = false
    private(set) var isSaved = false
    private(set) var importingName: String?
    var chapterDetection = ChapterDetection.auto
    var errorMessage: String?
    var isCasting = false
    var isDropTargeted = false
    /// The draft being narrated, which may no longer be the one being written.
    @ObservationIgnored private var narratingID: UUID?
    /// The draft that just finished, while its cover is shown.
    private(set) var finishedBookID: UUID?
    /// The narration "Added to Library" is offering to undo.
    private(set) var toastBookID: UUID?

    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var toastTask: Task<Void, Never>?

    /// The text the "Try a sample" link starts from.
    static let sampleText = "The creek is bright this morning, and the meadow is ready for a new story."
    static let formats = "PDF · EPUB · MOBI · TXT · MD · RTF · DOCX · HTML"

    var title: String {
        get { app?.draftTitle ?? "" }
        set {
            app?.draftTitle = newValue
            scheduleSave()
        }
    }

    var text: String {
        get { app?.draftText ?? "" }
        set {
            app?.draftText = newValue
            if !newValue.isEmpty { isWriting = true }
            scheduleSave()
        }
    }

    var state: CreateState {
        if finishedBookID != nil { return .done }
        if isGenerating { return .generating }
        return isWriting || !text.isEmpty ? .editing : .empty
    }

    private var isGenerating: Bool {
        guard let draftID else { return false }
        return app?.bookshelf.progress?.bookID == draftID
    }

    private var trimmedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    // MARK: - Narrator

    var voice: Voice { app?.selectedVoice ?? VoiceCatalog.defaultVoice }

    func cast(_ voice: Voice) {
        app?.selectVoice(voice)
        scheduleSave()
    }

    /// What previews say: the draft's own first sentence, once there is one.
    var firstSentence: String? {
        let text = trimmedText
        guard !text.isEmpty else { return nil }
        var first: String?
        text.enumerateSubstrings(in: text.startIndex..., options: .bySentences) { sentence, _, _, stop in
            let clean = sentence?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !clean.isEmpty else { return }
            first = clean
            stop = true
        }
        return first.map { String($0.prefix(240)) }
    }

    func preview(_ voice: Voice) {
        app?.previewVoice(voice, speaking: firstSentence)
    }

    func previewURL(for voice: Voice) -> URL? {
        app?.voicePreviewURL(voice, speaking: firstSentence)
    }

    // MARK: - Estimates

    var wordCount: Int { ListenEstimator.wordCount(text) }

    private var estimator: ListenEstimator { app?.settings.listenEstimator ?? ListenEstimator() }

    var listenDuration: TimeInterval {
        estimator.listenDuration(words: wordCount, voiceID: voice.id)
    }

    var generationDuration: TimeInterval {
        estimator.generationTime(audioSeconds: listenDuration)
    }

    // MARK: - Getting text in

    func startWriting() {
        isWriting = true
    }

    func loadSample() {
        text = Self.sampleText
    }

    func paste() {
        guard let pasted = NSPasteboard.general.string(forType: .string),
              !pasted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            NSSound.beep()
            return
        }
        if title.isEmpty, let heading = ChapterDetection.openingHeading(in: pasted) { title = heading }
        text = pasted
    }

    func openImportPanel() {
        let panel = NSOpenPanel()
        panel.title = "Import into Atten"
        panel.allowedContentTypes = DocumentImporter.supportedExtensions
            .compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url { importDocument(from: url) }
    }

    /// Reads any document the Library can open into the editor. Its chapters
    /// come in under Markdown headings so chapter detection finds them again.
    /// Text already being written is left on the shelf as its own draft.
    func importDocument(from url: URL) {
        guard importingName == nil, state != .generating else { return }
        errorMessage = nil
        importingName = url.lastPathComponent
        Task {
            defer { importingName = nil }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            do {
                let document = try await Task.detached(priority: .userInitiated) {
                    try DocumentImporter.extract(from: url)
                }.value
                let body = document.chapters.count > 1
                    ? document.chapters.map { "# \($0.title)\n\n\($0.text)" }.joined(separator: "\n\n")
                    : document.chapters.map(\.text).joined(separator: "\n\n")
                if !trimmedText.isEmpty { saveNow(); detach() }
                title = document.title
                text = body
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// The Studio's scene-stored draft from before drafts were books, put on
    /// the shelf once. True when there is nothing left to import.
    func importLegacyDraft(_ legacy: String) -> Bool {
        guard let app, !legacy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return true }
        let hash = ContentHash.of(legacy)
        guard !app.bookshelf.books.contains(where: { $0.contentHash == hash }) else { return true }
        do {
            try app.bookshelf.saveDraft(
                title: ChapterDetection.openingHeading(in: legacy) ?? "",
                text: legacy,
                voiceID: app.selectedVoiceID,
                defaults: app.settings
            )
            return true
        } catch {
            return false
        }
    }

    // MARK: - Saving

    func scheduleSave() {
        isSaved = false
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    /// Writes the draft to the shelf now. Nothing is saved until there are
    /// words, so opening Create and leaving does not leave an empty book.
    func saveNow() {
        saveTask?.cancel()
        guard let app, !trimmedText.isEmpty, state == .editing else { return }
        do {
            let draft = try app.bookshelf.saveDraft(
                id: draftID,
                title: title,
                text: text,
                voiceID: voice.id,
                defaults: app.settings
            )
            draftID = draft.id
            isSaved = true
        } catch {
            errorMessage = "Your draft could not be saved: \(error.localizedDescription)"
        }
    }

    // MARK: - Generating

    var generateDisabledReason: String? {
        guard let app else { return nil }
        if trimmedText.isEmpty { return "Add text to generate" }
        if importingName != nil { return "Importing…" }
        if app.synthesis.isBusy { return "Another narration is running" }
        return nil
    }

    var canGenerate: Bool { state == .editing && generateDisabledReason == nil }

    func generate() {
        guard let app, canGenerate else { return }
        saveTask?.cancel()
        errorMessage = nil
        let displayTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let draft = try app.bookshelf.saveDraft(
                id: draftID,
                title: title,
                text: text,
                voiceID: voice.id,
                defaults: app.settings,
                chapters: chapterDetection.chapters(in: text, title: displayTitle.isEmpty ? "Untitled" : displayTitle)
            )
            draftID = draft.id
            isSaved = true
        } catch {
            errorMessage = "Your draft could not be saved: \(error.localizedDescription)"
            return
        }
        guard let draftID else { return }
        app.bookshelf.narrate(draftID, useMPS: app.settings.useMPS)
        if isGenerating { narratingID = draftID } else { errorMessage = app.bookshelf.errorMessage }
    }

    func cancel() {
        guard isGenerating else { return }
        app?.progressivePlayer.stop()
        app?.bookshelf.cancelNarration()
        // The shelf's own notice speaks for the Library; here the text simply
        // becomes editable again.
        app?.bookshelf.cancelledMessage = nil
    }

    /// How far narration has reached through the text, while it runs.
    var spokenExtent: SpokenExtent? {
        guard let app, let draftID, let progress = app.bookshelf.progress, progress.bookID == draftID,
              let book = app.bookshelf.book(id: draftID) else { return nil }
        let index = book.chapters.firstIndex { $0.id == progress.chapterID } ?? 0
        if progress.isCombining {
            return SpokenExtent(text: text, chapters: [text], chapterIndex: 0, spokenWords: .max)
        }
        return SpokenExtent(
            text: text,
            chapters: book.chapters.map(\.text),
            chapterIndex: index,
            spokenWords: progress.spokenWords
        )
    }

    /// Why the last attempt did not produce a narration, if it did not.
    var failure: String? {
        if let errorMessage { return errorMessage }
        guard let draftID, let book = app?.bookshelf.book(id: draftID), book.narrationState == .failed else { return nil }
        return book.narrationFailure
    }

    var narrationProgress: BookshelfModel.NarrationProgress? {
        guard let draftID, let progress = app?.bookshelf.progress, progress.bookID == draftID else { return nil }
        return progress
    }

    /// Progressive playback, once it exists and is following this draft
    /// rather than some other book's narration.
    var progressivePlayer: ProgressivePlayer? {
        guard let app, let draftID, app.progressivePlayer.bookID == draftID else { return nil }
        return app.progressivePlayer
    }

    /// The sentence sounding right now, as an exact range in the draft's own
    /// text — found through `NarrationTimings`, not the running word count
    /// `spokenExtent` estimates from.
    var playingSentenceRange: (location: Int, length: Int)? {
        guard let app, let draftID, let player = progressivePlayer, let active = player.activeSentence,
              let book = app.bookshelf.book(id: draftID), book.chapters.indices.contains(active.chapterIndex)
        else { return nil }
        let chapters = book.chapters.map(\.text)
        let before = SpokenExtent(text: text, chapters: chapters, chapterIndex: active.chapterIndex, spokenWords: active.wordsBefore)
        let after = SpokenExtent(
            text: text, chapters: chapters, chapterIndex: active.chapterIndex,
            spokenWords: active.wordsBefore + active.wordCount
        )
        // At the very start of a chapter past the first, `before` lands on
        // the heading gap rather than the chapter's own first word — the
        // same gap `AlignedTextEditor` trims before its own sweep.
        let whole = text as NSString
        var start = before.utf16Offset
        while start < after.utf16Offset, let scalar = UnicodeScalar(whole.character(at: start)),
              CharacterSet.whitespacesAndNewlines.contains(scalar) {
            start += 1
        }
        guard after.utf16Offset > start else { return nil }
        return (start, after.utf16Offset - start)
    }

    // MARK: - Done

    func narrationFinished(_ bookID: UUID) {
        guard let app, bookID == narratingID else { return }
        narratingID = nil
        // "Added to Library" says it; the shelf's banner would say it twice.
        app.bookshelf.successMessage = nil
        app.bookshelf.narrationSuccessMessage = nil
        toastBookID = bookID
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            self?.toastBookID = nil
        }
        guard bookID == draftID else { return }
        if app.section == .studio {
            finishedBookID = bookID
        } else {
            detach()
        }
    }

    /// Takes the finished draft to its place on the shelf, then clears Create
    /// for the next one.
    func leaveForLibrary() {
        guard let app, finishedBookID != nil else { return }
        app.returnToShelf()
        Task { [weak self] in
            // After the cover has flown, so the screen it left is not seen
            // emptying underneath it.
            try? await Task.sleep(for: .milliseconds(600))
            guard let self, self.finishedBookID != nil else { return }
            self.detach()
        }
    }

    /// Undo for "Added to Library": the narration goes, the draft stays.
    func undoNarration() {
        guard let app, let bookID = toastBookID else { return }
        if app.playingBook?.id == bookID { app.closePlayer() }
        app.bookshelf.removeNarration(bookID)
        dismissToast()
    }

    func dismissToast() {
        toastTask?.cancel()
        toastBookID = nil
    }

    /// Forgets the draft being written, leaving it on the shelf. The text and
    /// title are `AppModel`'s, and `newDraft()` clears those.
    func reset() {
        saveTask?.cancel()
        draftID = nil
        isWriting = false
        isSaved = false
        errorMessage = nil
        finishedBookID = nil
        isCasting = false
        chapterDetection = .auto
    }

    /// Starts a new draft while keeping the current one on the shelf.
    private func detach() {
        reset()
        app?.draftTitle = ""
        app?.draftText = ""
    }
}
