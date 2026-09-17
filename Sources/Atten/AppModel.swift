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
    private(set) var activeAudioURL: URL?
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
    @ObservationIgnored private var playbackTimer: Timer?

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
        self.generator = generator ?? RetryingBackendClient(
            wrapping: ProcessBackendClient(),
            maximumAttempts: 2
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
            if let quarantined = await repository.quarantinedFileURL {
                startupError = """
                Atten could not read its project history, so the old file was kept at \
                \(quarantined.path) and a fresh history was started. \
                Your audio files were not touched.
                """
            }
        } catch {
            startupError = error.localizedDescription
        }
        library.start()
        if settings.checksForUpdates { await checkForUpdate() }
    }

    var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.3.1"
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

    var playerTitle: String? {
        activeAudioURL?.deletingPathExtension().lastPathComponent
    }

    func seek(to time: TimeInterval) {
        guard let audioPlayer else { return }
        audioPlayer.currentTime = min(max(0, time), audioPlayer.duration)
        playbackPosition = audioPlayer.currentTime
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

    func togglePlayback(url: URL? = nil) {
        let target = url ?? currentAudioURL
        guard let target else { return }
        if audioPlayer?.url == target, audioPlayer?.isPlaying == true {
            audioPlayer?.pause()
            isPlaying = false
            stopPlaybackTimer()
        } else if audioPlayer?.url == target {
            audioPlayer?.play()
            isPlaying = true
            startPlaybackTimer()
        } else {
            play(url: target)
        }
    }

    func toggleActivePlayback() {
        togglePlayback(url: audioPlayer?.url ?? currentAudioURL)
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

    func rename(_ project: ProjectRecord, to name: String) {
        do {
            let newURL = try exportService.renamedAudio(at: project.audioURL, name: name)
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

    private func play(url: URL) {
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            let delegate = AudioPlaybackDelegate { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    self.isPlaying = false
                    self.stopPlaybackTimer()
                    self.playbackPosition = self.playbackDuration
                }
            }
            audioDelegate = delegate
            audioPlayer?.delegate = delegate
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
            activeAudioURL = url
            isPlaying = true
            playbackDuration = audioPlayer?.duration ?? 0
            playbackPosition = 0
            startPlaybackTimer()
        } catch {
            activeAudioURL = nil
            isPlaying = false
            let message = "Audio playback failed: \(error.localizedDescription)"
            if url.path.hasPrefix(playgroundDirectory.path) {
                playgroundState = .failed(message)
            } else {
                generationState = .failed(message)
            }
        }
    }

    private func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        activeAudioURL = nil
        isPlaying = false
        stopPlaybackTimer()
        playbackPosition = 0
        playbackDuration = 0
    }

    private func startPlaybackTimer() {
        stopPlaybackTimer()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
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
