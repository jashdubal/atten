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

    var draftTitle = "Untitled narration"
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
    var startupError: String?
    var voicePreviewID: String?
    var playgroundState: GenerationState = .idle
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

    private var playgroundDirectory: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("Atten", isDirectory: true)
            .appendingPathComponent("Playground", isDirectory: true)
    }

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
        func backendClient() -> any TTSGenerating {
            RetryingBackendClient(wrapping: ProcessBackendClient(), maximumAttempts: 2)
        }
        self.generator = generator ?? backendClient()
        // The bookshelf drives its own client, so cancelling a Studio draft
        // does not stop a book that is halfway through being narrated.
        self.bookshelf = BookshelfModel(
            directories: directories,
            generator: generator ?? backendClient()
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
        self.bookshelf.missingModelID = { [weak self] voiceID in
            self?.requiredModelID(for: voiceID)
        }
        // The interface reads its colours from the store, so the saved theme
        // has to be in place before the first view body runs.
        ThemeStore.shared.theme = loadedSettings.theme
    }

    var selectedVoice: Voice {
        VoiceCatalog.voice(id: selectedVoiceID) ?? VoiceCatalog.defaultVoice
    }

    var currentAudioURL: URL? {
        if case let .ready(url) = generationState { return url }
        return nil
    }

    var isGenerating: Bool { generationState == .generating }

    var isPlaygroundGenerating: Bool { playgroundState == .generating }

    var playgroundAudioURL: URL? {
        if case let .ready(url) = playgroundState { return url }
        return nil
    }

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
        Open Models and download it once — after that this voice works offline like the rest.
        """
    }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        startRemoteCommands()
        await repairQuarantineIfNeeded()
        do {
            try directories.prepare()
            try? resetPlaygroundDirectory()
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

    func installUpdate() {
        guard let release = availableUpdate, !isInstallingUpdate else { return }
        isInstallingUpdate = true
        Task {
            do {
                let stagedApp = try await UpdateChecker.downloadAndStage(release)
                try UpdateChecker.scheduleReplacement(of: Bundle.main.bundleURL, with: stagedApp)
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
    var section = SidebarItem.studio

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

    func openInLibrary(_ route: LibraryRoute) {
        guard libraryPath.last != route else { return }
        libraryMovedForward = true
        libraryPath.append(route)
    }

    /// Back to the shelf in one step, for a book that has just been removed
    /// from under whoever was reading it.
    func returnToShelf() {
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

    func selectReaderPageTheme(_ theme: ReaderPageTheme) {
        guard settings.readerPageTheme != theme else { return }
        settings.readerPageTheme = theme
        saveSettings()
    }

    func selectReaderFont(_ font: ReaderFont) {
        guard settings.readerFont != font else { return }
        settings.readerFont = font
        saveSettings()
    }

    func setReaderFocus(_ on: Bool) {
        guard isReaderFocused != on else { return }
        isReaderFocused = on
        ReaderFocusWindow.setFullScreen(on)
    }

    /// One step back. Focus mode counts as a step, so the first press gives the
    /// reader back its surroundings rather than closing the book outright.
    func goBack() {
        if isReaderFocused {
            setReaderFocus(false)
            return
        }
        guard canGoBack else { return }
        libraryMovedForward = false
        libraryPath.removeLast()
    }

    /// Only the Library stacks screens, so only the Library has anywhere to go
    /// back to. Focus mode counts wherever it is on.
    var canGoBack: Bool {
        isReaderFocused || (section == .library && !libraryPath.isEmpty)
    }

    var activeAudioURL: URL? { queue.current?.url }

    var playerTitle: String? { queue.current?.title }

    var playerSubtitle: String? { queue.current?.subtitle }

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
        publishNowPlaying()
    }

    /// Ten seconds back or forward, the way every player does it.
    ///
    /// Running off either end carries on into the neighbouring chapter rather
    /// than stopping dead — and backwards it lands ten seconds from that
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

    func playNext() {
        guard let track = queue.advance() else { return }
        start(track)
    }

    /// Part way into a track, "previous" means the start of this one — which is
    /// what it means everywhere else, and what someone who missed a sentence
    /// is reaching for.
    func playPrevious() {
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
        stopPlayback()
        generationTask?.cancel()
        draftTitle = "Untitled narration"
        draftText = ""
        generationState = .idle
        successMessage = nil
    }

    func generate() {
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
        stopPlayback()
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

        generationTask = Task { [weak self] in
            guard let self else { return }
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
                play(url: output.url)
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
        if isPlaygroundGenerating { playgroundState = .idle }
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

    func previewVoice(_ voice: Voice) {
        let previewDirectory = directories.applicationSupport
            .appendingPathComponent("Voice Previews", isDirectory: true)
        let previewURL = previewDirectory
            .appendingPathComponent("preview-\(voice.id)")
            .appendingPathExtension("wav")
        if FileManager.default.fileExists(atPath: previewURL.path) {
            togglePlayback(url: previewURL)
            return
        }
        guard !isGenerating, !isPlaygroundGenerating, voicePreviewID == nil else { return }
        if let message = missingModelMessage(for: voice.id) {
            generationState = .failed(message)
            return
        }
        voicePreviewID = voice.id
        let generationID = UUID()
        activeGenerationID = generationID
        let request = GenerationRequest(
            text: "Welcome to Atten. Let every idea find its voice.",
            voiceID: voice.id,
            speed: 1,
            format: .wav,
            outputDirectory: previewDirectory,
            filename: "preview-\(voice.id)",
            useMPS: settings.useMPS,
            modelID: voice.modelID
        )
        generationTask = Task { [weak self] in
            guard let self else { return }
            defer { voicePreviewID = nil }
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

    func generatePlaygroundSample(
        text: String,
        voiceID: String,
        speed: Double,
        format: AudioFormat,
        useMPS: Bool
    ) {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else {
            playgroundState = .failed("Enter a short sample before generating.")
            return
        }
        if let message = missingModelMessage(for: voiceID) {
            playgroundState = .failed(message)
            return
        }

        cancelGeneration()
        stopPlayback()
        do {
            try resetPlaygroundDirectory()
        } catch {
            playgroundState = .failed("The temporary sample folder could not be prepared.")
            return
        }

        playgroundState = .generating
        let generationID = UUID()
        activeGenerationID = generationID
        let request = GenerationRequest(
            text: cleanText,
            voiceID: voiceID,
            speed: speed,
            format: format,
            outputDirectory: playgroundDirectory,
            filename: "sample-\(UUID().uuidString)",
            useMPS: useMPS,
            modelID: VoiceCatalog.voice(id: voiceID)?.modelID
        )

        generationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let output = try await generator.generate(request)
                try Task.checkCancellation()
                guard activeGenerationID == generationID else { return }
                playgroundState = .ready(output.url)
                play(url: output.url)
            } catch is CancellationError {
                if activeGenerationID == generationID { playgroundState = .idle }
            } catch BackendError.cancelled {
                if activeGenerationID == generationID { playgroundState = .idle }
            } catch {
                if activeGenerationID == generationID {
                    playgroundState = .failed(error.localizedDescription)
                }
            }
        }
    }

    func clearPlaygroundSample() {
        cancelGeneration()
        stopPlayback()
        try? resetPlaygroundDirectory()
        playgroundState = .idle
    }

    func usePlaygroundSettingsInStudio(
        text: String,
        voiceID: String,
        speed: Double,
        format: AudioFormat
    ) {
        draftText = text
        selectedVoiceID = voiceID
        self.speed = speed
        self.format = format
        generationState = .idle
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
        ThemeStore.shared.theme = settings.theme
        saveSettings()
    }

    func selectAppearance(_ appearance: AppearancePreference) {
        guard settings.appearance != appearance else { return }
        settings.appearance = appearance
        saveSettings()
    }

    func selectTheme(_ theme: AttenTheme) {
        guard settings.theme != theme else { return }
        settings.theme = theme
        ThemeStore.shared.theme = theme
        saveSettings()
    }

    func importText(from url: URL) {
        guard url.startAccessingSecurityScopedResource() || url.isFileURL else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        do {
            if url.pathExtension.lowercased() == "rtf" {
                draftText = try NSAttributedString(
                    url: url,
                    options: [:],
                    documentAttributes: nil
                ).string
            } else {
                draftText = try String(contentsOf: url, encoding: .utf8)
            }
            draftTitle = url.deletingPathExtension().lastPathComponent
            generationState = .idle
        } catch {
            generationState = .failed("Atten could not read that text file: \(error.localizedDescription)")
        }
    }

    func openImportPanel() {
        let panel = NSOpenPanel()
        panel.title = "Import Text into Atten"
        var contentTypes: [UTType] = [.plainText, .sourceCode, .rtf]
        if let markdown = UTType(filenameExtension: "md") { contentTypes.append(markdown) }
        panel.allowedContentTypes = contentTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url { importText(from: url) }
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

    func exportCurrent() {
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

    /// Opens the folder finished audio lands in. The export folder can be moved
    /// anywhere, and the one it points at can be deleted or living on a volume
    /// that is no longer mounted, so fall back to Atten's own data folder —
    /// which holds the books, narrations, and history — rather than opening
    /// nothing at all.
    func openSaveFolder() {
        let exports = URL(fileURLWithPath: settings.outputDirectory, isDirectory: true)
        try? FileManager.default.createDirectory(at: exports, withIntermediateDirectories: true)
        let target = FileManager.default.fileExists(atPath: exports.path)
            ? exports
            : directories.applicationSupport
        NSWorkspace.shared.open(target)
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
        draftTitle = "\(project.title) copy"
        draftText = project.text
        selectedVoiceID = project.voiceID
        speed = project.speed
        format = project.format
        generationState = .idle
    }

    func regenerate(_ project: ProjectRecord) {
        duplicate(project)
        generate()
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

    /// Plays `tracks` back to back, starting at `index`.
    ///
    /// Each is a separate file on disk, so a book can be narrated chapter by
    /// chapter and still listened to as one piece.
    func play(tracks: [PlaybackTrack], startingAt index: Int = 0) {
        guard !tracks.isEmpty else { return }
        queue = PlaybackQueue(tracks: tracks, startingAt: index)
        guard let track = queue.current else { return }
        start(track)
    }

    /// One file, with nothing before or after it — a preview, a sample, a
    /// finished draft.
    private func play(url: URL, subtitle: String? = nil) {
        play(tracks: [PlaybackTrack(url: url, subtitle: subtitle)])
    }

    private func start(_ track: PlaybackTrack, secondsBeforeEnd: TimeInterval? = nil) {
        do {
            let player = try AVAudioPlayer(contentsOf: track.url)
            let delegate = AudioPlaybackDelegate { [weak self] in
                Task { @MainActor in self?.trackFinished() }
            }
            audioDelegate = delegate
            player.delegate = delegate
            // Set before preparing, or the rate is ignored on first play.
            player.enableRate = true
            player.prepareToPlay()
            player.rate = Float(playbackRate)
            if let secondsBeforeEnd {
                player.currentTime = max(0, player.duration - secondsBeforeEnd)
            }
            player.play()
            audioPlayer = player
            isPlaying = true
            playbackDuration = player.duration
            playbackPosition = player.currentTime
            startPlaybackTimer()
            publishNowPlaying()
        } catch {
            audioPlayer = nil
            isPlaying = false
            queue = PlaybackQueue()
            nowPlaying.clear()
            let message = "Audio playback failed: \(error.localizedDescription)"
            if track.url.path.hasPrefix(playgroundDirectory.path) {
                playgroundState = .failed(message)
            } else {
                generationState = .failed(message)
            }
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
        publishNowPlaying()
    }

    private func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        queue = PlaybackQueue()
        isPlaying = false
        stopPlaybackTimer()
        playbackPosition = 0
        playbackDuration = 0
        nowPlaying.clear()
    }

    /// The keyboard's play key, Control Center, and a pair of headphones all
    /// reach the player through here.
    private func startRemoteCommands() {
        nowPlaying.start(
            NowPlayingCenter.Commands(
                play: { [weak self] in self?.resume() },
                pause: { [weak self] in self?.pause() },
                toggle: { [weak self] in self?.toggleActivePlayback() },
                next: { [weak self] in self?.playNext() },
                previous: { [weak self] in self?.playPrevious() },
                skip: { [weak self] seconds in self?.skip(by: seconds) },
                seek: { [weak self] time in self?.seek(to: time) }
            )
        )
    }

    private func publishNowPlaying() {
        nowPlaying.update(
            track: queue.current,
            isPlaying: isPlaying,
            position: playbackPosition,
            duration: playbackDuration,
            rate: playbackRate,
            hasNext: queue.hasNext,
            hasPrevious: queue.hasPrevious
        )
    }

    /// Position is read often enough for the scrubber to move smoothly and no
    /// more. The system runs its own clock between the updates it is told
    /// about, so Now Playing is refreshed when something changes rather than
    /// several times a second.
    private func startPlaybackTimer() {
        stopPlaybackTimer()
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let player = self.audioPlayer else { return }
                self.playbackPosition = player.currentTime
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

    private func resetPlaygroundDirectory() throws {
        if FileManager.default.fileExists(atPath: playgroundDirectory.path) {
            try FileManager.default.removeItem(at: playgroundDirectory)
        }
        try FileManager.default.createDirectory(
            at: playgroundDirectory,
            withIntermediateDirectories: true
        )
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
    static func setFullScreen(_ on: Bool) {
        // NSApp is nil until the application object exists, which is also the
        // case in tests.
        guard let app = NSApp, let window = app.keyWindow ?? app.mainWindow else { return }
        Task { @MainActor in
            guard window.isVisible,
                  window.styleMask.contains(.fullScreen) != on else { return }
            window.toggleFullScreen(nil)
        }
    }
}
