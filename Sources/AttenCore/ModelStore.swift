import Foundation

/// A speech model that exists on disk, either bundled with Atten or downloaded
/// from Hugging Face into the shared backend models directory.
public struct InstalledModel: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let languages: String
    public let byteCount: Int64
    public let isBundled: Bool

    public init(
        id: String,
        name: String,
        languages: String,
        byteCount: Int64,
        isBundled: Bool = false
    ) {
        self.id = id
        self.name = name
        self.languages = languages
        self.byteCount = byteCount
        self.isBundled = isBundled
    }

    public var sizeText: String {
        byteCount > 0
            ? ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
            : "—"
    }
}

/// Mirrors `atten_backend.downloader.get_models_directory` so the app can list,
/// measure, and delete downloaded weights without starting the Python backend.
public struct ModelStore: Sendable {
    public static let kokoroID = "hexgrad/Kokoro-82M"
    public static let xttsID = "coqui/XTTS-v2"

    public let root: URL

    public init(root: URL? = nil, environment: [String: String] = ProcessInfo.processInfo.environment) {
        if let root {
            self.root = root
        } else if let override = environment["ATTEN_MODELS_DIR"], !override.isEmpty {
            self.root = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            self.root = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".local/share/atten/models", isDirectory: true)
        }
    }

    public func directory(for modelID: String) -> URL {
        let folder = isXTTS(modelID) ? "XTTS-v2" : modelID.replacingOccurrences(of: "/", with: "--")
        return root.appendingPathComponent(folder, isDirectory: true)
    }

    public func isXTTS(_ modelID: String) -> Bool {
        modelID.localizedCaseInsensitiveContains("xtts")
    }

    public var isXTTSInstalled: Bool {
        let directory = self.directory(for: Self.xttsID)
        for file in ["config.json", "vocab.json", "model.pth"] {
            let url = directory.appendingPathComponent(file)
            guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 0 else {
                return false
            }
        }
        return true
    }

    /// Lists every complete download. Directories with `.part` files still in
    /// flight are skipped so a paused download never looks installed.
    public func installedModels() -> [InstalledModel] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return contents.compactMap { directory -> InstalledModel? in
            let folder = directory.lastPathComponent
            let modelID = folder == "XTTS-v2"
                ? Self.xttsID
                : folder.replacingOccurrences(of: "--", with: "/")
            guard folder == "XTTS-v2" || folder.contains("--") else { return nil }
            guard isComplete(directory) else { return nil }
            return InstalledModel(
                id: modelID,
                name: modelID.split(separator: "/").last.map(String.init) ?? modelID,
                languages: HuggingFaceCatalog.languageSummary(forModelID: modelID),
                byteCount: byteCount(of: directory)
            )
        }
        .sorted { $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending }
    }

    public func isInstalled(_ modelID: String) -> Bool {
        if modelID.caseInsensitiveCompare(Self.kokoroID) == .orderedSame { return true }
        if isXTTS(modelID) { return isXTTSInstalled }
        return isComplete(directory(for: modelID))
    }

    public func delete(_ modelID: String) throws {
        guard modelID.caseInsensitiveCompare(Self.kokoroID) != .orderedSame else {
            throw ModelStoreError.bundledModelIsNotRemovable
        }
        let directory = self.directory(for: modelID)
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.removeItem(at: directory)
    }

    public func byteCount(of directory: URL) -> Int64 {
        files(in: directory).reduce(into: Int64(0)) { total, url in
            total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    /// Bytes already fetched for a model, including partially downloaded files,
    /// so a paused download can show how much is on disk.
    public func downloadedByteCount(for modelID: String) -> Int64 {
        byteCount(of: directory(for: modelID))
    }

    private func isComplete(_ directory: URL) -> Bool {
        let files = self.files(in: directory)
        guard !files.isEmpty else { return false }
        if files.contains(where: { $0.pathExtension.lowercased() == "part" }) { return false }
        if files.contains(where: { $0.lastPathComponent == ".atten_complete" }) { return true }

        let weightExtensions: Set<String> = [
            "bin", "pt", "pth", "safetensors", "onnx", "gguf", "nemo", "tflite",
        ]
        return files.contains { url in
            guard weightExtensions.contains(url.pathExtension.lowercased()) else { return false }
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return size > 1024 * 1024
        }
    }

    private func files(in directory: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]
        ) else { return [] }
        return enumerator.compactMap { $0 as? URL }.filter { url in
            (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }
    }
}

public enum ModelStoreError: LocalizedError, Sendable {
    case bundledModelIsNotRemovable

    public var errorDescription: String? {
        switch self {
        case .bundledModelIsNotRemovable:
            "Kokoro ships with Atten and cannot be deleted."
        }
    }
}
