import Foundation

public struct AppDirectories: Sendable {
    public let applicationSupport: URL
    public let projectsFile: URL
    public let defaultExports: URL

    public init(applicationSupport: URL? = nil) {
        let base = applicationSupport ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("Atten", isDirectory: true)
        self.applicationSupport = base
        self.projectsFile = base.appendingPathComponent("projects.json")
        self.defaultExports = base.appendingPathComponent("Exports", isDirectory: true)
    }

    public func prepare() throws {
        try FileManager.default.createDirectory(
            at: applicationSupport,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: defaultExports,
            withIntermediateDirectories: true
        )
    }
}

public actor ProjectRepository {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL) {
        self.fileURL = fileURL
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()
    }

    public func load() throws -> [ProjectRecord] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        return try decoder.decode(
            [ProjectRecord].self,
            from: Data(contentsOf: fileURL)
        )
    }

    public func save(_ projects: [ProjectRecord]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoder.encode(projects).write(to: fileURL, options: .atomic)
    }
}

public struct SettingsStore: @unchecked Sendable {
    public static let currentKey = "com.jashdubal.Atten.settings.v1"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load(defaultOutputDirectory: URL) -> AppSettings {
        if let data = defaults.data(forKey: Self.currentKey),
           let settings = try? JSONDecoder().decode(AppSettings.self, from: data) {
            return settings
        }

        // The CLI never persisted settings. These names cover early development
        // builds so users do not lose preferences during the Atten rename.
        let legacyVoice = defaults.string(forKey: "tts.selectedVoice") ?? "af_heart"
        let legacySpeed = defaults.object(forKey: "tts.speed") as? Double ?? 1.0
        let legacyFormat = defaults.string(forKey: "tts.outputFormat")
            .flatMap(AudioFormat.init(rawValue:)) ?? .mp3
        let legacyDirectory = defaults.string(forKey: "tts.outputDirectory")
            ?? defaultOutputDirectory.path

        return AppSettings(
            outputDirectory: legacyDirectory,
            defaultFormat: legacyFormat,
            defaultSpeed: legacySpeed,
            selectedVoiceID: legacyVoice
        )
    }

    public func save(_ settings: AppSettings) throws {
        let data = try JSONEncoder().encode(settings)
        defaults.set(data, forKey: Self.currentKey)
    }
}

public enum LegacyOutputImporter {
    public static func discover(
        in directory: URL,
        excluding projects: [ProjectRecord]
    ) -> [ProjectRecord] {
        let existingPaths = Set(projects.map {
            URL(fileURLWithPath: $0.audioPath).resolvingSymlinksInPath().path
        })
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .creationDateKey]
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )) ?? []

        return files.compactMap { url in
            let canonicalURL = url.resolvingSymlinksInPath()
            guard ["mp3", "wav"].contains(url.pathExtension.lowercased()),
                  !existingPaths.contains(canonicalURL.path) else { return nil }
            let values = try? url.resourceValues(forKeys: keys)
            guard values?.isRegularFile == true else { return nil }
            let date = values?.creationDate ?? Date()
            return ProjectRecord(
                title: url.deletingPathExtension().lastPathComponent,
                text: "Imported from the original Offline TTS output folder.",
                voiceID: "af_heart",
                speed: 1.0,
                format: AudioFormat(rawValue: url.pathExtension.lowercased()) ?? .mp3,
                audioPath: canonicalURL.path,
                createdAt: date,
                updatedAt: date,
                isLegacyImport: true
            )
        }
        .sorted { $0.createdAt > $1.createdAt }
    }
}
