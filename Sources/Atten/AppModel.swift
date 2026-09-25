import AppKit
import AttenCore
import AVFoundation
import Foundation
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
final class AppModel {
    enum GenerationState: Equatable {
        case idle
        case generating
        case ready(URL)
        case failed(String)
    }

    var draftTitle = ""
    var draftText = ""
    var selectedVoiceID: String
    var speed: Double
    var format: AudioFormat
    var projects: [ProjectRecord] = []
    var settings: AppSettings
    var generationState: GenerationState = .idle
    var successMessage: String?
    var isPlaying = false
    /// What is playing, what played before it, and what comes next.
    private(set) var queue = PlaybackQueue()
    @ObservationIgnored private var playbackBookSnapshot: BookRecord?
    var startupError: String?
    var voicePreviewID: String?
    var playbackPosition: TimeInterval = 0
    var playbackDuration: TimeInterval = 0
    /// Bumped when downloaded models add or remove voices, since the voice
    /// catalog itself is not observable.
    private(set) var voiceCatalogRevision = 0
    var availableUpdate: AppRelease?
    private(set) var isInstallingUpdate = false
    var updateError: String?
    var updateMessage: String?
    private(set) var isCheckingForUpdate = false
    let library: ModelLibrary
    let bookshelf: BookshelfModel
    let synthesis = SynthesisCoordinator()
    let createFlow = CreateFlowModel()
    /// Plays whichever narration is being generated, as its segments land.
    let progressivePlayer = ProgressivePlayer()
    let sleepTimer = SleepTimer()
    let narrationNotifier = NarrationNotifier()

    @ObservationIgnored private let directories: AppDirectories
    @ObservationIgnored private let repository: ProjectRepository
    @ObservationIgnored private let settingsStore: SettingsStore
    @ObservationIgnored private let generator: any TTSGenerating
    @ObservationIgnored private let exportService = ExportService()
    @ObservationIgnored private var generationTask: Task<Void, Never>?
    @ObservationIgnored private var audioPlayer: AVAudioPlayer?
    @ObservationIgnored private var audioDelegate: AudioPlaybackDelegate?
    @ObservationIgnored private var activeGenerationID: UUID?
    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private var hasAnnouncedQuarantinedHistory = false
    @ObservationIgnored private var playbackTimer: Timer?
    @ObservationIgnored private let nowPlaying = NowPlayingCenter()
    /// The playing voice's level, for the views that breathe with it.
    @ObservationIgnored let levelMeter = LevelMeter()

    init(
        directories: AppDirectories = AppDirectories(),
        settingsStore: SettingsStore = SettingsStore(),
        generator: (any TTSGenerating)? = nil,
        library: ModelLibrary? = nil
    ) {
        self.directories = directories
        self.repository = ProjectRepository(fileURL: directories.projectsFile)
        self.settingsStore = settingsStore
        let loadedSettings = settingsStore.load(defaultOutputDirectory: directories.defaultExports)
        self.settings = loadedSettings
        self.selectedVoiceID = loadedSettings.selectedVoiceID
        self.speed = loadedSettings.defaultSpeed
        self.format = loadedSettings.defaultFormat
        // Studio and the bookshelf share one resident engine, so only one
        // model is ever loaded; each reaches it through its own
        // `SharedBackendClient`, so cancelling a Studio draft still does not
        // stop a book that is halfway through being narrated, and the reverse.
        func sharedBackendClients() -> (any TTSGenerating, any TTSGenerating) {
            let engine = PersistentBackendClient()
            NotificationCenter.default.addObserver(
                forName: NSApplication.willTerminateNotification, object: nil, queue: nil
            ) { _ in engine.shutdown() }
            let studio = RetryingBackendClient(wrapping: SharedBackendClient(sharing: engine), maximumAttempts: 2)
            let bookshelf = RetryingBackendClient(wrapping: SharedBackendClient(sharing: engine), maximumAttempts: 2)
            return (studio, bookshelf)
        }
        let (studioGenerator, bookshelfGenerator): (any TTSGenerating, any TTSGenerating) =
            generator.map { ($0, $0) } ?? sharedBackendClients()
        self.generator = studioGenerator
        self.bookshelf = BookshelfModel(
            directories: directories,
            generator: bookshelfGenerator,
            synthesis: synthesis
        )
        self.library = library ?? ModelLibrary(
            sizeCacheURL: directories.applicationSupport.appendingPathComponent("model_sizes_cache.json")
        )
        self.library.loadPendingDownloads = { [weak self] in
            self?.settings.pendingDownloadModelIDs ?? []
        }
        self.library.savePendingDownloads = { [weak self] pending in
            guard let self, settings.pendingDownloadModelIDs != pending else { return }
            settings.pendingDownloadModelIDs = pending
            saveSettings()
        }
        self.library.onInstalledModelsChanged = { [weak self] in
            self?.installedModelsChanged()
        }
        self.bookshelf.isAudioInUse = { [weak self] url in self?.activeAudioURL == url }
        self.bookshelf.missingModelID = { [weak self] voiceID in
            self?.requiredModelID(for: voiceID)
        }
        // Every finished narration sharpens the estimates Create shows.
        self.bookshelf.onNarrationFinished = { [weak self] run in
            guard let self else { return }
            settings.listenEstimator.record(voiceID: run.voiceID, words: run.words, audioSeconds: run.audioSeconds)
            settings.listenEstimator.recordGeneration(audioSeconds: run.audioSeconds, wallSeconds: run.wallSeconds)
            saveSettings()
            // Listening progressively hands off to the finished recording at
            // the same position, with no gap a listener would notice.
            if progressivePlayer.bookID == run.bookID {
                let handoff = progressivePlayer.handoff()
                // Only a listener actually mid-narration needs handing off —
                // otherwise nothing was following along, and switching the
                // player over would silently steal whatever it already had
                // loaded. A full player open on the narration, paused, has
                // nothing loaded to steal and keeps its place.
                let isShowingNarration = queue.current == nil && section == .nowPlaying
                if handoff.wasPlaying || isShowingNarration, let book = bookshelf.book(id: run.bookID) {
                    play(tracks: book.narrationTracks, atPosition: handoff.position, autoplay: handoff.wasPlaying)
                }
            }
            createFlow.narrationFinished(run.bookID)
            if let book = bookshelf.book(id: run.bookID) {
                narrationNotifier.narrationFinished(bookID: book.id, title: book.title)
            }
        }
        SystemNotifications.shared.open = { [weak self] bookID in
            self?.section = .library
            self?.openInLibrary(.book(bookID))
        }
        self.bookshelf.onSegmentReady = { [weak self] bookID, chapterIndex, segment in
            self?.progressivePlayer.receive(bookID: bookID, chapterIndex: chapterIndex, segment: segment)
        }
        self.bookshelf.onNarrationEnded = { [weak self] _ in
            self?.progressivePlayer.stop()
        }
        self.progressivePlayer.onChange = { [weak self] in
            self?.publishProgressiveNowPlaying()
        }
        createFlow.app = self
        connectSleepTimer()
    }

    var selectedVoice: Voice {
        VoiceCatalog.voice(id: selectedVoiceID) ?? VoiceCatalog.defaultVoice
    }

    var currentAudioURL: URL? {
        if case let .ready(url) = generationState { return url }
        return nil
    }

    var isGenerating: Bool { generationState == .generating }

    var currentProject: ProjectRecord? {
        guard let currentAudioURL else { return nil }
        return projects.first { $0.audioPath == currentAudioURL.path }
    }

    var backendIsAvailable: Bool { BackendLocator.locateInstallation() != nil }

    /// Most voices run on the bundled engine. The rest name one model that has
    /// to be downloaded once; until it is, Atten says so rather than starting a
    /// generation that can only fail.
    func requiredModelID(for voiceID: String) -> String? {
        guard let required = VoiceCatalog.voice(id: voiceID)?.requiresModelID,
              !library.isInstalled(required) else { return nil }
        return required
    }

    private func missingModelMessage(for voiceID: String) -> String? {
        guard let required = requiredModelID(for: voiceID) else { return nil }
        let name = VoiceCatalog.voice(id: voiceID)?.name ?? voiceID
        return """
        \(name) speaks through the \(required) model, which is not downloaded yet. \
        Open Settings → Models and download it once — after that this voice works offline like the rest.
        """
    }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        startRemoteCommands()
        await repairQuarantineIfNeeded()
        do {
            try directories.prepare()
            var loaded = try await repository.load()
            if case let .development(backendRoot)? = BackendLocator.locateInstallation() {
                let legacyDirectory = backendRoot.appendingPathComponent("outputs", isDirectory: true)
                let imported = LegacyOutputImporter.discover(in: legacyDirectory, excluding: loaded)
                if !imported.isEmpty {
                    loaded.append(contentsOf: imported)
                    try await repository.save(loaded)
                }
            }
            projects = loaded.sorted { $0.updatedAt > $1.updatedAt }
            await announceQuarantinedHistory()
        } catch {
            reportStartupProblem(error.localizedDescription)
        }
        library.start()
        await bookshelf.load()
        if let book = bookshelf.books.filter({ $0.hasBookAudio && $0.lastListenedAt != nil })
            .max(by: { ($0.lastListenedAt ?? .distantPast) < ($1.lastListenedAt ?? .distantPast) }),
           let track = book.narrationTracks.first {
            queue = PlaybackQueue(tracks: book.narrationTracks)
            playbackBookSnapshot = book
            start(track, autoplay: false, position: book.listeningPosition)
        }
        if settings.checksForUpdates { await checkForUpdate() }
    }

    /// macOS kills the bundled engine while it is still marked as downloaded,
    /// which looks to the user like a generation that stops for no reason. The
    /// user has already opened this app, so Atten clears the flag from its own
    /// bundle; if macOS will not let it, the user is told what to do instead.
    ///
    /// Clearing the flag walks every file in the bundle, model included, so it
    /// runs off the main actor and the window is never held up by it.
    private func repairQuarantineIfNeeded() async {
        guard case let .bundled(helper, _)? = BackendLocator.locateInstallation() else { return }
        guard Bundle.main.object(forInfoDictionaryKey: "AttenDistributionSigned") as? Bool != true else { return }
        let bundle = Bundle.main.bundleURL
        let repaired = await Task.detached(priority: .userInitiated) {
            BundleQuarantine.clear(from: bundle, verifying: helper)
        }.value
        if !repaired {
            reportStartupProblem(BackendError.blockedByGatekeeper.localizedDescription)
        }
    }

    /// Startup problems accumulate rather than replace one another, so the one
    /// the user can act on is never hidden by one that arrived later.
    private func reportStartupProblem(_ message: String) {
        startupError = [startupError, message].compactMap { $0 }.joined(separator: "\n\n")
    }

    /// History that could not be read is set aside instead of overwritten, and
    /// that can happen on the first save as well as at launch. Either way the
    /// user is told where their old file went, once.
    private func announceQuarantinedHistory() async {
        guard let quarantined = await repository.quarantinedFileURL,
              !hasAnnouncedQuarantinedHistory else { return }
        hasAnnouncedQuarantinedHistory = true
        reportStartupProblem("""
        Atten could not read its project history, so the old file was kept at \
        \(quarantined.path) and a fresh history was started. \
        Your audio files were not touched.
        """)
    }

    var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.3.2"
    }

    /// Launch checks stay silent when offline; manual checks report the outcome.
    func checkForUpdate(manual: Bool = false) async {
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            if manual { updateMessage = "Update checks only run in the installed app." }
            return
        }
        guard !isCheckingForUpdate else { return }
        isCheckingForUpdate = true
        defer { isCheckingForUpdate = false }
        do {
            availableUpdate = try await UpdateChecker.newerRelease(than: appVersion)
            if manual, availableUpdate == nil { updateMessage = "You're on the latest version (\(appVersion))." }
        } catch {
            if manual { updateMessage = "Couldn't reach GitHub. Check your internet connection." }
        }
    }

    @ObservationIgnored private var stagedUpdate: URL?

    func finishPendingUpdate() throws {
        guard let stagedUpdate else { return }
        try UpdateChecker.scheduleReplacement(of: Bundle.main.bundleURL, with: stagedUpdate)
        self.stagedUpdate = nil
    }

    func cancelPendingUpdate() {
        stagedUpdate = nil
        isInstallingUpdate = false
    }

    func installUpdate() {
        guard let release = availableUpdate, !isInstallingUpdate else { return }
        isInstallingUpdate = true
        Task {
            do {
                let stagedApp = try await UpdateChecker.downloadAndStage(release)
                stagedUpdate = stagedApp
                NSApp.terminate(nil)
            } catch {
                isInstallingUpdate = false
                updateError = error.localizedDescription
            }
        }
    }

    // MARK: - Navigation

    /// Where the Library is, kept on the model rather than inside the view.
    ///
    /// The detail pane is rebuilt from nothing whenever the sidebar changes
    /// section, so a path owned by `LibraryView` was thrown away every time the
    /// user glanced at Studio: the book they were reading became the shelf
    /// again, and the reader was torn down mid-transition while it still had
    /// the window in focus mode.
    /// Which screen the sidebar is showing.
    ///
    /// Held here so that "back" can tell whether there is anything behind the
    /// current screen. The window remembers it across launches by way of scene
    /// storage, which is a place to write it down rather than a second owner.
    var section = SidebarItem.library {
        didSet {
            // Focus belongs to the reader, not to the window. A sidebar
            // selection can replace the reader without giving its view an
            // opportunity to run `onDisappear`, so unwind the window here as
            // the single navigation owner.
            if section != .library, isReaderFocused {
                setReaderFocus(false)
            }
            if section == .studio, oldValue != .studio { sectionBeforeCreate = oldValue }
        }
    }

    /// Where Create was opened from. Create is a flow over the window rather
    /// than a place, so leaving it goes back there.
    private(set) var sectionBeforeCreate = SidebarItem.library

    /// Which Settings tab is showing, so a screen can send someone straight
    /// to Models.
    var settingsTab = "general"

    func leaveCreate() {
        guard section == .studio else { return }
        section = sectionBeforeCreate
    }

    private(set) var libraryPath: [LibraryRoute] = []

    /// Which way the last move through the Library went, so its screens slide
    /// the way the reader just travelled instead of always the same way.
    private(set) var libraryMovedForward = true

    /// Whether the reader has taken the whole window.
    ///
    /// Also kept here, and for the same reason. Focus mode reaches outside the
    /// reader — it hides Atten's own sidebar and puts the window into full
    /// screen — so anything that tore the reader down without its cooperation
    /// left a hidden sidebar and a full-screen window with nothing in it.
    private(set) var isReaderFocused = false

    /// What the Library's search field holds.
    ///
    /// Here rather than in `LibraryView` so Home's search can put something in
    /// it and send the user to the shelf, and so the term survives a trip into
    /// a book and back.
    var libraryQuery = ""

    func openInLibrary(_ route: LibraryRoute) {
        // Opening another Library route is also a safe boundary for focus.
        // This matters when a command or an automation opens a book while the
        // old reader is still disappearing.
        if isReaderFocused { setReaderFocus(false) }
        // Opening a book counts however deep it is opened, and the mark is set
        // before the early return: reopening the reader on the book already
        // open is still the user telling us this is the book they are reading.
        switch route {
        case let .book(id), let .reader(id):
            bookshelf.markOpened(id)
        }
        guard libraryPath.last != route else { return }
        libraryMovedForward = true
        libraryPath.append(route)
    }

    /// Show the shelf, filtered. Home's search has nowhere of its own to put
    /// results, and a second set of them would be a second place to keep the
    /// filtering rules in step.
    func searchLibrary(for query: String) {
        setReaderFocus(false)
        libraryQuery = query
        returnToShelf()
        section = .library
    }

    /// Back to the shelf in one step, for a book that has just been removed
    /// from under whoever was reading it.
    func returnToShelf() {
        section = .library
        setReaderFocus(false)
        guard !libraryPath.isEmpty else { return }
        libraryMovedForward = false
        libraryPath.removeAll()
    }

    func selectReaderViewMode(_ mode: ReaderViewMode) {
        guard settings.readerViewMode != mode else { return }
        settings.readerViewMode = mode
        saveSettings()
    }

    func setReaderJustifiesText(_ isJustified: Bool) {
        guard settings.readerJustifiesText != isJustified else { return }
        settings.readerJustifiesText = isJustified
        saveSettings()
    }

    func selectReaderFont(_ font: ReaderFont) {
        guard settings.readerFont != font else { return }
        settings.readerFont = font
        saveSettings()
    }

    /// Clamped here rather than at the call site, so the menu can simply step
    /// and the level can never leave the range the palette will honour.
    func setReaderTextBrightness(_ level: Double) {
        let range = ReaderPagePalette.inkBrightnessRange
        let clamped = min(max(range.lowerBound, level), range.upperBound)
        guard settings.readerTextBrightness != clamped else { return }
        settings.readerTextBrightness = clamped
        saveSettings()
    }

    func setReaderFocus(_ on: Bool) {
        guard isReaderFocused != on else { return }
        isReaderFocused = on
        ReaderFocusWindow.setFullScreen(on)
    }

    /// Called when macOS exits full screen through its own controls or a
    /// system shortcut. This is deliberately separate from `setReaderFocus`:
    /// the window has already changed, so asking it to toggle would race the
    /// notification and could put the app straight back into full screen.
    func readerWindowDidExitFullScreen() {
        guard isReaderFocused else { return }
        isReaderFocused = false
        ReaderFocusWindow.didExitFullScreen()
    }

    /// One step back. Focus mode counts as a step, so the first press gives the
    /// reader back its surroundings rather than closing the book outright.
    func goBack() {
        if isReaderFocused {
            setReaderFocus(false)
            return
        }
        if section == .studio {
            leaveCreate()
            return
        }
        guard canGoBack else { return }
        libraryMovedForward = false
        libraryPath.removeLast()
    }

    /// Only the Library stacks screens, so only the Library has anywhere to go
    /// back to — and Create, which goes back to wherever it was opened from.
    /// Focus mode counts wherever it is on.
    var canGoBack: Bool {
        isReaderFocused || section == .studio || (section == .library && !libraryPath.isEmpty)
    }

    var activeAudioURL: URL? { queue.current?.url }

    var playerTitle: String? { queue.current?.title }

    var playerSubtitle: String? { queue.current?.subtitle }

    /// The generated Studio record behind the current file, when there is
    /// one. Narrated book chapters deliberately do not become projects: the
    /// chapter and its book are the source of truth for those tracks.
    var playingProject: ProjectRecord? {
        guard let url = queue.current?.url else { return nil }
        return projects.first { $0.audioURL == url }
    }

    /// A named route rather than a sheet keeps Now Playing available from
    /// Home, the reader, and every detail screen without creating a second
    /// playback owner.
    func openNowPlaying() {
        setReaderFocus(false)
        section = .nowPlaying
    }

    /// The book the current track came from, when it came from one.
    ///
    /// A narration track carries its chapter's identifier, so the shelf can be
    /// asked rather than the title matched — two books can share a title, and
    /// a Studio render has no book behind it at all.
    var playingBook: BookRecord? {
        guard let track = queue.current else { return nil }
        let current = bookshelf.books.first { $0.id == track.id || $0.chapters.contains { $0.id == track.id } }
        if let current, let snapshot = playbackBookSnapshot,
           current.id == snapshot.id, current.audioURL != track.url { return snapshot }
        return current
    }

    /// How much of the chapter is left. Measured the same way as the elapsed
    /// time beside it: adjusting one for the listening rate and not the other
    /// made a chapter played at 2× read "5:00" and "-2:30" at its midpoint.
    var playbackRemaining: TimeInterval {
        max(0, playbackDuration - playbackPosition)
    }

    func seek(to time: TimeInterval) {
        guard let audioPlayer else { return }
        audioPlayer.currentTime = min(max(0, time), audioPlayer.duration)
        playbackPosition = audioPlayer.currentTime
        saveListeningPosition()
        publishNowPlaying()
    }

    /// Fifteen seconds back or forward, the way every player does it.
    ///
    /// Running off either end carries on into the neighbouring chapter rather
    /// than stopping dead — and backwards it lands fifteen seconds from that
    /// chapter's end, not at its beginning, because skipping back is asking to
    /// hear the last few seconds again.
    func skip(by seconds: TimeInterval) {
        guard let audioPlayer else { return }
        let target = audioPlayer.currentTime + seconds
        if target < 0, queue.hasPrevious {
            guard let previous = queue.retreat() else { return }
            start(previous, secondsBeforeEnd: -target)
            return
        }
        if target > audioPlayer.duration {
            if queue.hasNext {
                playNext()
            } else {
                seek(to: audioPlayer.duration)
            }
            return
        }
        seek(to: target)
    }

    var playingChapterIndex: Int? {
        guard let book = playingBook, book.hasBookAudio else { return nil }
        return book.playbackChapters.lastIndex { ($0.startTime ?? .infinity) <= playbackPosition }
    }

    var hasNextChapter: Bool {
        if let index = playingChapterIndex, let book = playingBook { return index + 1 < book.playbackChapters.count }
        return queue.hasNext
    }

    var hasPreviousChapter: Bool {
        if let index = playingChapterIndex { return index > 0 }
        return queue.hasPrevious
    }

    func playNext() {
        if let index = playingChapterIndex, let book = playingBook {
            if book.playbackChapters.indices.contains(index + 1) { seek(to: book.playbackChapters[index + 1].startTime ?? 0) }
            return
        }
        guard let track = queue.advance() else { return }
        start(track)
    }

    /// Part way into a track, "previous" means the start of this one — which is
    /// what it means everywhere else, and what someone who missed a sentence
    /// is reaching for.
    func playPrevious() {
        if let index = playingChapterIndex, let book = playingBook {
            let start = book.playbackChapters[index].startTime ?? 0
            seek(to: playbackPosition - start > 3 ? start : (book.playbackChapters[max(0, index - 1)].startTime ?? 0))
            return
        }
        if let audioPlayer, audioPlayer.currentTime > 3 {
            seek(to: 0)
            return
        }
        guard let track = queue.retreat() else {
            seek(to: 0)
            return
        }
        start(track)
    }

    func setPlaybackRate(_ rate: Double) {
        guard settings.playbackRate != rate else { return }
        settings.playbackRate = rate
        audioPlayer?.rate = Float(rate)
        saveSettings()
        publishNowPlaying()
    }

    var playbackRate: Double { settings.playbackRate }

    /// Only the sleep timer's fade changes this.
    func setPlaybackVolume(_ volume: Float) {
        audioPlayer?.volume = volume
        progressivePlayer.volume = volume
    }

    func closePlayer() {
        stopPlayback()
    }

    private func installedModelsChanged() {
        voiceCatalogRevision += 1
        if VoiceCatalog.voice(id: selectedVoiceID) == nil {
            selectVoice(VoiceCatalog.defaultVoice)
        }
    }

    func newDraft() {
        if isGenerating || voicePreviewID != nil { cancelGeneration() }
        draftTitle = ""
        draftText = ""
        generationState = .idle
        successMessage = nil
        createFlow.reset()
    }

    func generate() {
        guard !synthesis.isBusy else { return }
        let cleanText = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else {
            generationState = .failed("Enter or import text before generating speech.")
            return
        }
        if let message = missingModelMessage(for: selectedVoiceID) {
            generationState = .failed(message)
            return
        }
        cancelGeneration()
        generationState = .generating
        successMessage = nil
        let generationID = UUID()
        activeGenerationID = generationID

        let title = cleanTitle(draftTitle, fallback: "Atten narration")
        let outputDirectory = URL(fileURLWithPath: settings.outputDirectory, isDirectory: true)
        let filename = uniqueFilename(base: title, in: outputDirectory, format: format)
        let request = GenerationRequest(
            text: cleanText,
            voiceID: selectedVoiceID,
            speed: speed,
            format: format,
            outputDirectory: outputDirectory,
            filename: filename,
            useMPS: settings.useMPS,
            modelID: VoiceCatalog.voice(id: selectedVoiceID)?.modelID
        )

        guard let lease = synthesis.acquire("Creating audio") else { return }
        generationTask = Task { [weak self] in
            guard let self else { return }
            defer { synthesis.release(lease) }
            do {
                let output = try await generator.generate(request)
                try Task.checkCancellation()
                guard activeGenerationID == generationID else { return }
                let now = Date()
                let project = ProjectRecord(
                    title: title,
                    text: cleanText,
                    voiceID: request.voiceID,
                    speed: request.speed,
                    format: request.format,
                    audioPath: output.url.path,
                    createdAt: now,
                    updatedAt: now
                )
                projects.insert(project, at: 0)
                try await repository.save(projects)
                await announceQuarantinedHistory()
                generationState = .ready(output.url)
                successMessage = "Speech is ready to review."
            } catch is CancellationError {
                if activeGenerationID == generationID { generationState = .idle }
            } catch BackendError.cancelled {
                if activeGenerationID == generationID { generationState = .idle }
            } catch {
                if activeGenerationID == generationID {
                    generationState = .failed(error.localizedDescription)
                }
            }
        }
    }

    func cancelGeneration() {
        generationTask?.cancel()
        generationTask = nil
        generator.cancel()
        activeGenerationID = nil
        if isGenerating { generationState = .idle }
        voicePreviewID = nil
    }

    /// Plays, or pauses, one named thing — a project, an export, a preview.
    /// Anything already in the queue keeps the queue.
    func togglePlayback(track: PlaybackTrack) {
        guard audioPlayer?.url == track.url else {
            if queue.move(to: track.url), let found = queue.current {
                start(found)
            } else {
                play(tracks: [track])
            }
            return
        }
        isPlaying ? pause() : resume()
    }

    func togglePlayback(url: URL? = nil) {
        let target = url ?? currentAudioURL
        guard let target else { return }
        guard audioPlayer?.url == target else {
            // Already somewhere in the queue: move to it rather than throwing
            // away what comes after, so playing chapter nine of a book still
            // runs on into chapter ten.
            if queue.move(to: target), let track = queue.current {
                start(track)
            } else {
                play(url: target)
            }
            return
        }
        isPlaying ? pause() : resume()
    }

    func toggleActivePlayback() {
        guard audioPlayer != nil else {
            if let url = currentAudioURL { play(url: url) }
            return
        }
        isPlaying ? pause() : resume()
    }

    func pause() {
        guard isPlaying else { return }
        audioPlayer?.pause()
        saveListeningPosition()
        isPlaying = false
        stopPlaybackTimer()
        publishNowPlaying()
    }

    func resume() {
        guard let audioPlayer, !isPlaying else { return }
        audioPlayer.rate = Float(playbackRate)
        audioPlayer.play()
        isPlaying = true
        startPlaybackTimer()
        publishNowPlaying()
    }

    /// Where a preview of `voice` is cached. A preview of someone's own
    /// sentence is keyed on the sentence too, so each draft hears itself.
    func voicePreviewURL(_ voice: Voice, speaking sentence: String? = nil) -> URL {
        let name = sentence.map { "preview-\(voice.id)-\(ContentHash.of($0).prefix(16))" } ?? "preview-\(voice.id)"
        return directories.applicationSupport
            .appendingPathComponent("Voice Previews", isDirectory: true)
            .appendingPathComponent(name)
            .appendingPathExtension("wav")
    }

    func previewVoice(_ voice: Voice, speaking sentence: String? = nil) {
        let previewURL = voicePreviewURL(voice, speaking: sentence)
        let previewDirectory = previewURL.deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: previewURL.path) {
            togglePlayback(url: previewURL)
            return
        }
        guard !synthesis.isBusy else { return }
        if let message = missingModelMessage(for: voice.id) {
            generationState = .failed(message)
            return
        }
        voicePreviewID = voice.id
        let generationID = UUID()
        activeGenerationID = generationID
        let request = GenerationRequest(
            text: sentence ?? "Welcome to Atten. Let every idea find its voice.",
            voiceID: voice.id,
            speed: 1,
            format: .wav,
            outputDirectory: previewDirectory,
            filename: previewURL.deletingPathExtension().lastPathComponent,
            useMPS: settings.useMPS,
            modelID: voice.modelID
        )
        guard let lease = synthesis.acquire("Previewing \(voice.name)") else { return }
        generationTask = Task { [weak self] in
            guard let self else { return }
            defer { voicePreviewID = nil; synthesis.release(lease) }
            do {
                let output = try await generator.generate(request)
                guard activeGenerationID == generationID else { return }
                play(url: output.url)
            } catch is CancellationError {
                return
            } catch BackendError.cancelled {
                return
            } catch {
                if activeGenerationID == generationID {
                    generationState = .failed(error.localizedDescription)
                }
            }
        }
    }

    func selectVoice(_ voice: Voice) {
        selectedVoiceID = voice.id
        settings.selectedVoiceID = voice.id
        saveSettings()
    }

    func toggleFavorite(_ voice: Voice) {
        if settings.favoriteVoiceIDs.contains(voice.id) {
            settings.favoriteVoiceIDs.remove(voice.id)
        } else {
            settings.favoriteVoiceIDs.insert(voice.id)
        }
        saveSettings()
    }

    func applySettings() {
        settings.selectedVoiceID = selectedVoiceID
        settings.defaultSpeed = speed
        settings.defaultFormat = format
        saveSettings()
    }

    func openBookImportPanel() {
        let panel = NSOpenPanel()
        panel.title = "Add to Atten"
        // Built from the same list the shelf accepts a drop against, so the
        // panel and the drop target can never disagree about what opens.
        panel.allowedContentTypes = DocumentImporter.supportedExtensions
            .compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        returnToShelf()
        Task { [weak self] in
            guard let self else { return }
            for url in urls {
                await bookshelf.importBook(from: url, defaults: settings)
            }
        }
    }

    func export(_ project: ProjectRecord) {
        guard FileManager.default.fileExists(atPath: project.audioPath) else {
            generationState = .failed("The audio file for this project is missing.")
            return
        }
        let panel = NSSavePanel()
        panel.title = "Export from Atten"
        panel.nameFieldStringValue = project.audioURL.lastPathComponent
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let destination = panel.url {
            do {
                _ = try exportService.copyAudio(from: project.audioURL, to: destination)
                successMessage = "Exported \(destination.lastPathComponent)."
            } catch {
                generationState = .failed("Export failed: \(error.localizedDescription)")
            }
        }
    }

    private(set) var isExportingBook = false

    func exportBook(_ book: BookRecord) {
        guard !isExportingBook, book.hasBookAudio, let source = book.audioURL else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Audio]
        panel.nameFieldStringValue = ExportService.safeFilename(book.title) + ".m4a"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        isExportingBook = true
        Task {
            defer { isExportingBook = false }
            do {
                try await BookAudioExport.export(source, to: destination)
                bookshelf.successMessage = "Audiobook exported to \(destination.lastPathComponent)."
            } catch {
                bookshelf.errorMessage = "Export failed: \(error.localizedDescription). Choose a writable folder and try again."
            }
        }
    }

    func exportCurrent() {
        if let book = playingBook, book.hasBookAudio { exportBook(book); return }
        guard let url = currentAudioURL,
              let project = projects.first(where: { $0.audioPath == url.path }) else { return }
        export(project)
    }

    func reveal(_ project: ProjectRecord) {
        NSWorkspace.shared.activateFileViewerSelecting([project.audioURL])
    }

    func revealBookSource(_ book: BookRecord) {
        NSWorkspace.shared.activateFileViewerSelecting([book.sourceURL])
    }

    /// Opens Atten's own data folder — the base library holding the books,
    /// narrations, exports, and history — rather than the export folder, which
    /// the user can move elsewhere.
    func openSaveFolder() {
        let base = directories.applicationSupport
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        NSWorkspace.shared.open(base)
    }

    func rename(_ project: ProjectRecord, to name: String) {
        do {
            let newURL = try exportService.renamedAudio(at: project.audioURL, name: name)
            AudioMetadataStore.shared.forget(project.audioURL)
            guard let index = projects.firstIndex(where: { $0.id == project.id }) else { return }
            projects[index].title = newURL.deletingPathExtension().lastPathComponent
            projects[index].audioPath = newURL.path
            projects[index].updatedAt = Date()
            if currentAudioURL == project.audioURL { generationState = .ready(newURL) }
            Task { try? await repository.save(projects) }
            successMessage = "Renamed to \(newURL.lastPathComponent)."
        } catch {
            generationState = .failed("Rename failed: \(error.localizedDescription)")
        }
    }

    func duplicate(_ project: ProjectRecord) {
        createFlow.reset()
        draftTitle = "\(project.title) copy"
        draftText = project.text
        selectedVoiceID = project.voiceID
        speed = project.speed
        format = project.format
        generationState = .idle
    }

    func regenerate(_ project: ProjectRecord) {
        duplicate(project)
        createFlow.generate()
    }

    func delete(_ project: ProjectRecord, includingAudio: Bool = false) {
        if includingAudio, FileManager.default.fileExists(atPath: project.audioPath) {
            do {
                try FileManager.default.removeItem(at: project.audioURL)
                AudioMetadataStore.shared.forget(project.audioURL)
            } catch {
                generationState = .failed("The project audio could not be deleted: \(error.localizedDescription)")
                return
            }
        }

        if audioPlayer?.url == project.audioURL {
            stopPlayback()
        }
        if currentAudioURL == project.audioURL {
            generationState = .idle
        }
        projects.removeAll { $0.id == project.id }
        let projectsToSave = projects
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.repository.save(projectsToSave)
            } catch {
                self.generationState = .failed(
                    "The project was removed here, but its history could not be saved: \(error.localizedDescription)"
                )
            }
        }
        successMessage = includingAudio
            ? "Project and audio deleted."
            : "Project deleted. Its audio remains on disk."
    }

    func chooseOutputDirectory() {
        let panel = NSOpenPanel()
        panel.title = "Choose Atten Export Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            settings.outputDirectory = url.path
            saveSettings()
        }
    }

    func dismissStatus() {
        successMessage = nil
        if case .failed = generationState { generationState = .idle }
    }

    func listen(to book: BookRecord, chapter: BookChapter? = nil) {
        guard book.hasBookAudio, let url = book.audioURL else {
            bookshelf.narrate(book.id, useMPS: settings.useMPS)
            return
        }
        if activeAudioURL == url {
            if let chapter { seek(to: chapter.startTime ?? 0); if !isPlaying { toggleActivePlayback() } }
            else { toggleActivePlayback() }
        } else {
            saveListeningPosition()
            queue = PlaybackQueue(tracks: book.narrationTracks)
            playbackBookSnapshot = book
            if let track = queue.current {
                start(track, position: chapter?.startTime ?? book.listeningPosition)
            }
        }
    }

    /// Plays `tracks` back to back, starting at `index`.
    ///
    /// Each is a separate file on disk, so a book can be narrated chapter by
    /// chapter and still listened to as one piece.
    func play(
        tracks: [PlaybackTrack], startingAt index: Int = 0,
        atPosition position: TimeInterval = 0, autoplay: Bool = true
    ) {
        guard !tracks.isEmpty else { return }
        saveListeningPosition()
        queue = PlaybackQueue(tracks: tracks, startingAt: index)
        playbackBookSnapshot = bookshelf.books.first { $0.id == queue.current?.id }
        guard let track = queue.current else { return }
        start(track, autoplay: autoplay, position: position)
    }

    /// One file, with nothing before or after it — a preview, a sample, a
    /// finished draft.
    private func play(url: URL, subtitle: String? = nil) {
        let project = projects.first { $0.audioURL == url }
        let isVoicePreview = url.path.contains("/Voice Previews/")
        let title = project?.title
            ?? (isVoicePreview ? "Voice preview" : nil)
        let source = subtitle
            ?? project.map { project in
                let voice = VoiceCatalog.voice(id: project.voiceID)?.name ?? project.voiceID
                return "Studio · \(voice)"
            }
        let track = if let title {
            PlaybackTrack(url: url, title: title, subtitle: source)
        } else {
            PlaybackTrack(url: url, subtitle: source)
        }
        play(tracks: [track])
    }

    private func start(_ track: PlaybackTrack, secondsBeforeEnd: TimeInterval? = nil, autoplay: Bool = true, position: Double = 0) {
        do {
            let player = try AVAudioPlayer(contentsOf: track.url)
            let delegate = AudioPlaybackDelegate { [weak self] in
                Task { @MainActor in self?.trackFinished() }
            }
            audioDelegate = delegate
            player.delegate = delegate
            // Set before preparing, or the rate is ignored on first play.
            player.enableRate = true
            player.isMeteringEnabled = true
            player.prepareToPlay()
            player.rate = Float(playbackRate)
            player.currentTime = min(max(0, position), player.duration)
            if let secondsBeforeEnd {
                player.currentTime = max(0, player.duration - secondsBeforeEnd)
            }
            if autoplay { player.play() }
            audioPlayer = player
            levelMeter.player = player
            isPlaying = autoplay
            playbackDuration = player.duration
            playbackPosition = player.currentTime
            if autoplay { startPlaybackTimer() }
            bookshelf.cleanRetiredAudio()
            publishNowPlaying()
        } catch {
            audioPlayer = nil
            isPlaying = false
            queue = PlaybackQueue()
            nowPlaying.clear()
            generationState = .failed("Audio playback failed: \(error.localizedDescription)")
        }
    }

    private func trackFinished() {
        if queue.hasNext {
            playNext()
            return
        }
        isPlaying = false
        stopPlaybackTimer()
        playbackPosition = playbackDuration
        saveListeningPosition()
        publishNowPlaying()
    }

    private func stopPlayback() {
        saveListeningPosition()
        audioPlayer?.stop()
        audioPlayer = nil
        queue = PlaybackQueue()
        isPlaying = false
        stopPlaybackTimer()
        playbackPosition = 0
        playbackDuration = 0
        playbackBookSnapshot = nil
        bookshelf.cleanRetiredAudio()
        nowPlaying.clear()
    }

    func prepareForTermination() {
        cancelGeneration()
        stopPlayback()
        progressivePlayer.stop()
    }

    /// The keyboard's play key, Control Center, and a pair of headphones all
    /// reach the player through here. While a narration is generating and
    /// nothing else is queued, they reach progressive playback instead.
    private func startRemoteCommands() {
        nowPlaying.start(
            NowPlayingCenter.Commands(
                play: { [weak self] in self?.remotePlayOrPause(playing: true) },
                pause: { [weak self] in self?.remotePlayOrPause(playing: false) },
                toggle: { [weak self] in
                    guard let self else { return }
                    queue.current != nil ? toggleActivePlayback() : progressivePlayer.toggle()
                },
                next: { [weak self] in self?.playNext() },
                previous: { [weak self] in self?.playPrevious() },
                skip: { [weak self] seconds in self?.skip(by: seconds) },
                seek: { [weak self] time in
                    guard let self else { return }
                    queue.current != nil ? seek(to: time) : progressivePlayer.seek(to: time)
                }
            )
        )
    }

    private func remotePlayOrPause(playing: Bool) {
        guard queue.current != nil else {
            playing ? progressivePlayer.play() : progressivePlayer.pause()
            return
        }
        playing ? resume() : pause()
    }

    /// Now Playing while progressive playback, rather than the ordinary
    /// player, is what a listener is following — the ordinary queue always
    /// wins the display if both are somehow active at once.
    private func publishProgressiveNowPlaying() {
        guard queue.current == nil else { return }
        guard let bookID = progressivePlayer.bookID, let book = bookshelf.book(id: bookID) else {
            nowPlaying.clear()
            return
        }
        nowPlaying.update(
            track: PlaybackTrack(id: bookID, url: book.sourceURL, title: book.title, subtitle: "Narrating…"),
            chapter: progressivePlayer.activeSentence.flatMap { sentence in
                book.chapters.count > 1 && book.chapters.indices.contains(sentence.chapterIndex)
                    ? book.chapters[sentence.chapterIndex].title : nil
            },
            isPlaying: progressivePlayer.isPlaying,
            position: progressivePlayer.position,
            duration: progressivePlayer.duration,
            rate: 1,
            hasNext: false,
            hasPrevious: false
        )
    }

    private func publishNowPlaying() {
        publishedChapterTitle = playingChapterTitle
        nowPlaying.update(
            track: queue.current,
            chapter: publishedChapterTitle,
            isPlaying: isPlaying,
            position: playbackPosition,
            duration: playbackDuration,
            rate: playbackRate,
            hasNext: hasNextChapter,
            hasPrevious: hasPreviousChapter
        )
    }

    /// Position is read often enough for the scrubber to move smoothly and no
    /// more. The system runs its own clock between the updates it is told
    /// about, so Now Playing is refreshed when something changes rather than
    /// several times a second.
    @ObservationIgnored private var lastPositionSave = Date.distantPast
    @ObservationIgnored private var publishedChapterTitle: String?

    func saveListeningPosition() {
        guard let book = playingBook, book.audioURL == bookshelf.book(id: book.id)?.audioURL else { return }
        bookshelf.saveListeningPosition(playbackPosition, for: book.id)
        lastPositionSave = Date()
    }

    private func startPlaybackTimer() {
        stopPlaybackTimer()
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let player = self.audioPlayer else { return }
                self.playbackPosition = player.currentTime
                if Date().timeIntervalSince(self.lastPositionSave) >= 5 { self.saveListeningPosition() }
                if self.playingChapterTitle != self.publishedChapterTitle { self.publishNowPlaying() }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        playbackTimer = timer
    }

    private func stopPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = nil
    }

    private func saveSettings() {
        do { try settingsStore.save(settings) }
        catch { generationState = .failed("Settings could not be saved: \(error.localizedDescription)") }
    }

    private func cleanTitle(_ value: String, fallback: String) -> String {
        let clean = ExportService.safeFilename(value)
        return clean.isEmpty ? fallback : clean
    }

    private func uniqueFilename(base: String, in directory: URL, format: AudioFormat) -> String {
        let clean = cleanTitle(base, fallback: "Atten narration")
        var candidate = clean
        var counter = 2
        while FileManager.default.fileExists(
            atPath: directory.appendingPathComponent(candidate)
                .appendingPathExtension(format.rawValue).path
        ) {
            candidate = "\(clean) \(counter)"
            counter += 1
        }
        return candidate
    }

}

private final class AudioPlaybackDelegate: NSObject, AVAudioPlayerDelegate, @unchecked Sendable {
    private let didFinish: @Sendable () -> Void

    init(didFinish: @escaping @Sendable () -> Void) {
        self.didFinish = didFinish
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        didFinish()
    }
}

/// Full screen belongs to the window, not to a view.
///
/// The reader used to ask for it inline, including from `onDisappear` — asking
/// while SwiftUI was in the middle of tearing the view down left the window and
/// the view hierarchy disagreeing about how big everything was, which is what
/// the interface looked like when it "bugged out". The request is made one turn
/// of the run loop later instead, and only when the window is not already the
/// way it is being asked to be.
@MainActor
enum ReaderFocusWindow {
    // A generation token prevents stale enter/exit tasks from toggling the
    // window after a newer request. The reader's one source of truth remains
    // `AppModel.isReaderFocused`; this is only scheduling bookkeeping.
    private static var requestGeneration = 0

    static func setFullScreen(_ on: Bool) {
        requestGeneration += 1
        let generation = requestGeneration
        // NSApp is nil until the application object exists, which is also the
        // case in tests.
        guard let app = NSApp, let window = app.keyWindow ?? app.mainWindow else { return }
        Task { @MainActor in
            // Entering and leaving can happen before AppKit has completed the
            // first transition. Only the latest intent may toggle the window.
            await Task.yield()
            guard requestGeneration == generation else { return }
            guard window.isVisible,
                  window.styleMask.contains(.fullScreen) != on else { return }
            window.toggleFullScreen(nil)
        }
    }

    static func didExitFullScreen() {
        requestGeneration += 1
    }
}
