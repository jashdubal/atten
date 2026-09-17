import Foundation

public struct AppDirectories: Sendable {
    public let applicationSupport: URL
    public let projectsFile: URL
    public let defaultExports: URL

    public init(applicationSupport: URL? = nil) {
        // Application Support is always present in practice, but a home
        // directory that has been emptied or remounted must not crash Atten on
        // launch, so fall back to the conventional path rather than unwrapping.
        let base = applicationSupport ?? (
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Library/Application Support", isDirectory: true)
        ).appendingPathComponent("Atten", isDirectory: true)
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

    /// Set when `load` had to set an unreadable history file aside, so the app
    /// can tell the user where their old history went instead of silently
    /// starting over.
    public private(set) var quarantinedFileURL: URL?
    /// Whether this session ever read the file successfully. Until it has,
    /// saving must not replace whatever is already on disk.
    private var hasReadExistingFile = false

    public init(fileURL: URL) {
        self.fileURL = fileURL
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()
    }

    /// Reads project history. A file that cannot be decoded — truncated by a
    /// crash, hand-edited, or written by a version this one does not
    /// understand — is moved aside rather than left in place, because the next
    /// save would otherwise overwrite it and turn one bad launch into
    /// permanent data loss.
    public func load() throws -> [ProjectRecord] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            hasReadExistingFile = true
            return []
        }
        let data = try Data(contentsOf: fileURL)
        if let projects = try? decoder.decode([ProjectRecord].self, from: data) {
            hasReadExistingFile = true
            return projects
        }

        // The file is not wholly readable. Keep every record that still decodes
        // rather than discarding a long history over one damaged entry.
        let salvaged = (try? decoder.decode([Salvaged].self, from: data))?
            .compactMap(\.record) ?? []
        // Only once the damaged file is safely aside may saving proceed. If the
        // move fails, this throws with the guard still armed, so the file the
        // user's history lives in is not written over.
        quarantinedFileURL = try quarantine()
        hasReadExistingFile = true
        return salvaged
    }

    /// One array element that is kept when it decodes and skipped when it does not.
    private struct Salvaged: Decodable {
        let record: ProjectRecord?

        init(from decoder: Decoder) throws {
            record = try? ProjectRecord(from: decoder)
        }
    }

    /// Moves the unreadable file next to itself with a timestamped name.
    private func quarantine() throws -> URL {
        let stamp = ISO8601DateFormatter.string(
            from: Date(),
            timeZone: TimeZone(secondsFromGMT: 0) ?? .current,
            formatOptions: [.withYear, .withMonth, .withDay, .withTime]
        )
        .replacingOccurrences(of: ":", with: "-")
        let destination = fileURL
            .deletingLastPathComponent()
            .appendingPathComponent("\(fileURL.deletingPathExtension().lastPathComponent)-unreadable-\(stamp).json")
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: fileURL, to: destination)
        return destination
    }

    /// Writes history atomically. If this session never managed to read the
    /// existing file — an unreadable disk, a permission change — that file is
    /// preserved under a new name first, because overwriting it would destroy
    /// history Atten was simply unable to open today.
    public func save(_ projects: [ProjectRecord]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if !hasReadExistingFile, FileManager.default.fileExists(atPath: fileURL.path) {
            quarantinedFileURL = try quarantine()
            hasReadExistingFile = true
        }
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
