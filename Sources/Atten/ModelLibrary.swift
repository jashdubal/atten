import AttenCore
import Foundation
import Observation

/// Discovery, download, and on-disk state for Hugging Face speech models.
@MainActor
@Observable
final class ModelLibrary {
    enum DownloadPhase: Equatable {
        case downloading
        case paused
        case failed(ModelDownloadFailure)
    }

    struct DownloadState: Equatable {
        var phase: DownloadPhase
        var progress: ModelDownloadProgress
        /// Distinguishes a resumed download from the paused run it replaced.
        var attempt = UUID()
    }

    enum InstallFilter: String, CaseIterable, Identifiable {
        case all = "All models"
        case installed = "Installed"
        case available = "Available to download"

        var id: String { rawValue }
    }

    static let allLanguages = "All languages"

    var discovered: [HFModel] = []
    var installed: [InstalledModel] = []
    var downloads: [String: DownloadState] = [:]
    var isSearching = false
    var searchError: String?
    var lastMessage: String?
    var cancelledMessage: String?

    var query = "" {
        didSet { if query != oldValue { scheduleSearch() } }
    }
    var language = allLanguages {
        didSet { if language != oldValue { scheduleSearch(immediately: true) } }
    }
    var sort = HFSort.mostDownloads {
        didSet { if sort != oldValue { scheduleSearch(immediately: true) } }
    }
    var installFilter = InstallFilter.all

    /// Called whenever the set of installed models changes, so the voice
    /// catalog and Studio pickers can refresh.
    @ObservationIgnored var onInstalledModelsChanged: (() -> Void)?

    @ObservationIgnored private let store: ModelStore
    @ObservationIgnored private let catalog: HuggingFaceCatalog
    @ObservationIgnored private let downloader: any ModelDownloading
    @ObservationIgnored private let sizeCache: ModelSizeCache
    /// Pending downloads persist in the app settings so they resume on launch.
    @ObservationIgnored var loadPendingDownloads: () -> Set<String> = { [] }
    @ObservationIgnored var savePendingDownloads: (Set<String>) -> Void = { _ in }
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var downloadTasks: [String: Task<Void, Never>] = [:]

    init(
        store: ModelStore = ModelStore(),
        catalog: HuggingFaceCatalog = HuggingFaceCatalog(),
        downloader: any ModelDownloading = ProcessModelDownloader(),
        sizeCacheURL: URL
    ) {
        self.store = store
        self.catalog = catalog
        self.downloader = downloader
        self.sizeCache = ModelSizeCache(fileURL: sizeCacheURL)
    }

    // MARK: - Lifecycle

    func start() {
        rescanInstalled()
        scheduleSearch(immediately: true)
        for modelID in loadPendingDownloads() where !store.isInstalled(modelID) {
            download(modelID)
        }
        savePendingDownloads(loadPendingDownloads().filter { !store.isInstalled($0) })
    }

    func rescanInstalled() {
        installed = [
            InstalledModel(
                id: ModelStore.kokoroID,
                name: "Kokoro-82M",
                languages: HuggingFaceCatalog.languageSummary(forModelID: ModelStore.kokoroID),
                byteCount: 0,
                isBundled: true
            ),
        ] + store.installedModels()
        VoiceCatalog.setInstalledModels(installed)
        onInstalledModelsChanged?()
    }

    // MARK: - Discovery

    var visibleModels: [HFModel] {
        var models = discovered
        // Installed models stay listed even when the Hub search no longer returns them.
        for model in installed where !models.contains(where: { $0.id == model.id }) {
            models.append(HFModel(
                id: model.id,
                name: model.name,
                author: model.id.split(separator: "/").first.map(String.init) ?? "",
                downloads: 0,
                likes: 0,
                languageCodes: [],
                languages: model.languages,
                byteCount: model.byteCount
            ))
        }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        models = models.filter { model in
            if language != Self.allLanguages, !model.supports(language: language),
               !model.languages.localizedCaseInsensitiveContains(language) {
                return false
            }
            switch installFilter {
            case .all: break
            case .installed: if !isInstalled(model.id) { return false }
            case .available: if isInstalled(model.id) { return false }
            }
            guard !trimmed.isEmpty else { return true }
            return [model.id, model.name, model.author, model.languages]
                .contains { $0.localizedCaseInsensitiveContains(trimmed) }
        }

        switch sort {
        case .mostDownloads: models.sort { $0.downloads > $1.downloads }
        case .mostStars: models.sort { $0.likes > $1.likes }
        case .smallestSize: models.sort { sortableSize($0) < sortableSize($1) }
        case .largestSize: models.sort { $0.byteCount > $1.byteCount }
        case .provider:
            models.sort { ($0.author.lowercased(), $0.name.lowercased()) < ($1.author.lowercased(), $1.name.lowercased()) }
        case .modelName:
            models.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        return models
    }

    func refresh() { scheduleSearch(immediately: true) }

    private func sortableSize(_ model: HFModel) -> Int64 {
        model.byteCount > 0 ? model.byteCount : .max
    }

    private func scheduleSearch(immediately: Bool = false) {
        searchTask?.cancel()
        let query = self.query
        let language = self.language == Self.allLanguages ? nil : self.language
        let sort = self.sort
        searchTask = Task { [weak self] in
            if !immediately {
                try? await Task.sleep(for: .milliseconds(400))
            }
            guard let self, !Task.isCancelled else { return }
            isSearching = true
            let results = await catalog.search(query: query, language: language, sort: sort)
            guard !Task.isCancelled else { return }
            isSearching = false

            if results.isEmpty {
                searchError = discovered.isEmpty
                    ? "Hugging Face could not be reached. Installed models are still available."
                    : nil
                if discovered.isEmpty { discovered = Self.fallbackModels }
            } else {
                searchError = nil
                discovered = await withCachedSizes(results)
            }
            await resolveExactSizes()
        }
    }

    private func withCachedSizes(_ models: [HFModel]) async -> [HFModel] {
        var resolved: [HFModel] = []
        for var model in models {
            if let cached = await sizeCache.byteCount(for: model.id) { model.byteCount = cached }
            resolved.append(model)
        }
        return resolved
    }

    /// Replaces estimated sizes with exact manifest totals, a few at a time,
    /// and caches them so later launches show them instantly.
    private func resolveExactSizes() async {
        var uncached: [String] = []
        for model in discovered where await sizeCache.byteCount(for: model.id) == nil {
            uncached.append(model.id)
        }

        let catalog = self.catalog
        for batch in stride(from: 0, to: uncached.count, by: 4).map({ Array(uncached[$0..<min($0 + 4, uncached.count)]) }) {
            guard !Task.isCancelled else { return }
            let sizes = await withTaskGroup(of: (String, Int64).self) { group in
                for modelID in batch {
                    group.addTask { (modelID, await catalog.exactByteCount(for: modelID)) }
                }
                var sizes: [String: Int64] = [:]
                for await (modelID, size) in group { sizes[modelID] = size }
                return sizes
            }
            for (modelID, size) in sizes where size > 0 {
                await sizeCache.store(size, for: modelID)
                if let index = discovered.firstIndex(where: { $0.id == modelID }) {
                    discovered[index].byteCount = size
                }
            }
        }
    }

    // MARK: - Installation

    func isInstalled(_ modelID: String) -> Bool {
        installed.contains { $0.id.caseInsensitiveCompare(modelID) == .orderedSame }
    }

    func download(_ modelID: String) {
        guard downloads[modelID]?.phase != .downloading, !isInstalled(modelID) else { return }

        lastMessage = nil
        cancelledMessage = nil

        var pending = loadPendingDownloads()
        pending.insert(modelID)
        savePendingDownloads(pending)

        let previous = downloads[modelID]?.progress ?? ModelDownloadProgress()
        let attempt = UUID()
        downloads[modelID] = DownloadState(
            phase: .downloading,
            progress: ModelDownloadProgress(
                percent: previous.percent,
                status: "Connecting to Hugging Face…",
                sizeText: previous.sizeText
            ),
            attempt: attempt
        )

        let downloader = self.downloader
        let pausedRun = downloadTasks[modelID]
        // The library lives as long as the app, so tasks may hold it strongly.
        downloadTasks[modelID] = Task {
            // A quick pause → resume must not overlap two writers on the same files.
            await pausedRun?.value
            do {
                try await downloader.download(modelID) { update in
                    Task { @MainActor in
                        guard self.isCurrent(modelID, attempt) else { return }
                        self.downloads[modelID]?.progress = update
                    }
                }
                guard isCurrent(modelID, attempt) else { return }
                finishDownload(modelID)
            } catch BackendError.cancelled {
                // Pause and cancel update state themselves.
            } catch {
                guard isCurrent(modelID, attempt) else { return }
                downloads[modelID]?.phase = .failed(ModelDownloadFailure(error))
                downloads[modelID]?.progress.speed = ""
                downloads[modelID]?.progress.eta = ""
            }
        }
    }

    private func isCurrent(_ modelID: String, _ attempt: UUID) -> Bool {
        downloads[modelID]?.attempt == attempt && downloads[modelID]?.phase == .downloading
    }

    /// Stops the backend process; its `.part` files let `download` resume later.
    func pause(_ modelID: String) {
        guard downloads[modelID]?.phase == .downloading else { return }
        downloader.stop(modelID)
        downloads[modelID]?.phase = .paused
        downloads[modelID]?.progress.status = "Paused. Resume picks up where it stopped."
        downloads[modelID]?.progress.speed = ""
        downloads[modelID]?.progress.eta = ""
    }

    func cancel(_ modelID: String) {
        cancelledMessage = nil
        downloader.stop(modelID)
        let task = downloadTasks[modelID]
        downloads[modelID] = nil
        removePending(modelID)
        let store = self.store
        Task { [weak self] in
            // Wait for the process to exit before removing its partial files.
            await task?.value
            try? store.delete(modelID)
            self?.cancelledMessage = "Cancelled \(modelID) and removed partial files."
            self?.rescanInstalled()
        }
    }

    func delete(_ modelID: String) {
        cancelledMessage = nil
        do {
            try store.delete(modelID)
            downloads[modelID] = nil
            removePending(modelID)
            lastMessage = "Deleted \(modelID) and freed its disk space."
        } catch {
            lastMessage = "Could not delete \(modelID): \(error.localizedDescription)"
        }
        rescanInstalled()
    }

    private func finishDownload(_ modelID: String) {
        cancelledMessage = nil
        downloads[modelID] = nil
        removePending(modelID)
        lastMessage = "\(modelID) is ready to use in Studio."
        rescanInstalled()
    }

    private func removePending(_ modelID: String) {
        var pending = loadPendingDownloads()
        pending.remove(modelID)
        savePendingDownloads(pending)
    }

    // MARK: - Offline fallback

    static let fallbackModels: [HFModel] = [
        HFModel(
            id: ModelStore.kokoroID, name: "Kokoro-82M", author: "hexgrad",
            downloads: 11_500_000, likes: 6_900,
            languageCodes: ["en", "es", "fr", "it", "pt", "ja", "zh", "hi"],
            languages: HuggingFaceCatalog.languageSummary(forModelID: ModelStore.kokoroID),
            byteCount: 327_000_000
        ),
        HFModel(
            id: ModelStore.xttsID, name: "XTTS-v2", author: "coqui",
            downloads: 7_300_000, likes: 3_800,
            languageCodes: ["ar", "de", "ru", "tr", "nl", "pl", "es", "fr", "it", "pt", "ja", "zh", "hi", "ko"],
            languages: HuggingFaceCatalog.languageSummary(forModelID: ModelStore.xttsID),
            byteCount: 1_870_000_000
        ),
        HFModel(
            id: "facebook/mms-tts-ara", name: "mms-tts-ara", author: "facebook",
            downloads: 1_200_000, likes: 1_450, languageCodes: ["ar", "ara"],
            languages: "Arabic", byteCount: 145_000_000
        ),
        HFModel(
            id: "facebook/mms-tts-eng", name: "mms-tts-eng", author: "facebook",
            downloads: 890_000, likes: 940, languageCodes: ["en", "eng"],
            languages: "English", byteCount: 145_000_000
        ),
        HFModel(
            id: "facebook/mms-tts-deu", name: "mms-tts-deu", author: "facebook",
            downloads: 450_000, likes: 620, languageCodes: ["de", "deu"],
            languages: "German", byteCount: 145_000_000
        ),
        HFModel(
            id: "facebook/mms-tts-spa", name: "mms-tts-spa", author: "facebook",
            downloads: 580_000, likes: 790, languageCodes: ["es", "spa"],
            languages: "Spanish", byteCount: 145_000_000
        ),
        HFModel(
            id: "facebook/mms-tts-fra", name: "mms-tts-fra", author: "facebook",
            downloads: 390_000, likes: 510, languageCodes: ["fr", "fra"],
            languages: "French", byteCount: 145_000_000
        ),
    ]
}
