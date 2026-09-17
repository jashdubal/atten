import Foundation

public enum AudioFormat: String, Codable, CaseIterable, Identifiable, Sendable {
    case mp3
    case wav

    public var id: String { rawValue }
    public var displayName: String { rawValue.uppercased() }
}

public struct Voice: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let language: String
    public let languageCode: String
    public let gender: String
    public let traits: [String]
    public let quality: String
    public let provider: String
    /// Hugging Face repository that synthesizes this voice; nil for Kokoro.
    public let modelID: String?

    public init(
        id: String,
        name: String,
        language: String,
        languageCode: String,
        gender: String,
        traits: [String],
        quality: String,
        provider: String = "Kokoro",
        modelID: String? = nil
    ) {
        self.id = id
        self.name = name
        self.language = language
        self.languageCode = languageCode
        self.gender = gender
        self.traits = traits
        self.quality = quality
        self.provider = provider
        self.modelID = modelID
    }
}

public struct GenerationRequest: Equatable, Sendable {
    public var text: String
    public var voiceID: String
    public var speed: Double
    public var format: AudioFormat
    public var outputDirectory: URL
    public var filename: String
    public var useMPS: Bool
    public var modelID: String?

    public init(
        text: String,
        voiceID: String,
        speed: Double,
        format: AudioFormat,
        outputDirectory: URL,
        filename: String,
        useMPS: Bool = true,
        modelID: String? = nil
    ) {
        self.text = text
        self.voiceID = voiceID
        self.speed = speed
        self.format = format
        self.outputDirectory = outputDirectory
        self.filename = filename
        self.useMPS = useMPS
        self.modelID = modelID
    }
}

public struct GenerationOutput: Equatable, Sendable {
    public let url: URL
    public let segmentCount: Int
    public let sampleRate: Int

    public init(url: URL, segmentCount: Int, sampleRate: Int) {
        self.url = url
        self.segmentCount = segmentCount
        self.sampleRate = sampleRate
    }
}

public struct ProjectRecord: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var text: String
    public var voiceID: String
    public var speed: Double
    public var format: AudioFormat
    public var audioPath: String
    public var createdAt: Date
    public var updatedAt: Date
    public var isLegacyImport: Bool

    public init(
        id: UUID = UUID(),
        title: String,
        text: String,
        voiceID: String,
        speed: Double,
        format: AudioFormat,
        audioPath: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isLegacyImport: Bool = false
    ) {
        self.id = id
        self.title = title
        self.text = text
        self.voiceID = voiceID
        self.speed = speed
        self.format = format
        self.audioPath = audioPath
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isLegacyImport = isLegacyImport
    }

    public var audioURL: URL { URL(fileURLWithPath: audioPath) }

    // A record only needs an audio path to stay useful. Everything else falls
    // back to a sane value so history written by an older or newer Atten — or
    // an unknown format a future version introduced — still loads.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        audioPath = try container.decode(String.self, forKey: .audioPath)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decodeIfPresent(String.self, forKey: .title)
            ?? URL(fileURLWithPath: audioPath).deletingPathExtension().lastPathComponent
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        voiceID = try container.decodeIfPresent(String.self, forKey: .voiceID) ?? "af_heart"
        speed = try container.decodeIfPresent(Double.self, forKey: .speed) ?? 1.0
        format = (try? container.decodeIfPresent(AudioFormat.self, forKey: .format))
            .flatMap { $0 }
            ?? AudioFormat(rawValue: URL(fileURLWithPath: audioPath).pathExtension.lowercased())
            ?? .mp3
        let created = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        createdAt = created
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? created
        isLegacyImport = try container.decodeIfPresent(Bool.self, forKey: .isLegacyImport) ?? false
    }
}

public enum AppearancePreference: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    public var id: String { rawValue }
    public var displayName: String { rawValue.capitalized }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var appearance: AppearancePreference
    public var outputDirectory: String
    public var defaultFormat: AudioFormat
    public var defaultSpeed: Double
    public var selectedVoiceID: String
    public var favoriteVoiceIDs: Set<String>
    public var useMPS: Bool
    /// Downloads that were running or paused, resumed on the next launch.
    public var pendingDownloadModelIDs: Set<String>
    /// Whether Atten contacts GitHub at launch to look for a newer release.
    /// Turning this off keeps a working installation on its current version
    /// indefinitely, with no network use at all.
    public var checksForUpdates: Bool

    public init(
        appearance: AppearancePreference = .system,
        outputDirectory: String,
        defaultFormat: AudioFormat = .mp3,
        defaultSpeed: Double = 1.0,
        selectedVoiceID: String = "af_heart",
        favoriteVoiceIDs: Set<String> = ["af_heart", "af_bella", "bf_emma"],
        useMPS: Bool = true,
        pendingDownloadModelIDs: Set<String> = [],
        checksForUpdates: Bool = true
    ) {
        self.appearance = appearance
        self.outputDirectory = outputDirectory
        self.defaultFormat = defaultFormat
        self.defaultSpeed = defaultSpeed
        self.selectedVoiceID = selectedVoiceID
        self.favoriteVoiceIDs = favoriteVoiceIDs
        self.useMPS = useMPS
        self.pendingDownloadModelIDs = pendingDownloadModelIDs
        self.checksForUpdates = checksForUpdates
    }

    // Every key is optional on the way in. A blob written by an older Atten
    // lacks newer keys, and one written by a newer Atten may hold values this
    // version does not know, such as an appearance or format added later.
    // Neither may cost the user the preferences that still make sense, so each
    // field falls back on its own rather than the whole blob being discarded.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        outputDirectory = try container.decode(String.self, forKey: .outputDirectory)
        appearance = (try? container.decodeIfPresent(AppearancePreference.self, forKey: .appearance))
            .flatMap { $0 } ?? .system
        defaultFormat = (try? container.decodeIfPresent(AudioFormat.self, forKey: .defaultFormat))
            .flatMap { $0 } ?? .mp3
        defaultSpeed = try container.decodeIfPresent(Double.self, forKey: .defaultSpeed) ?? 1.0
        selectedVoiceID = try container.decodeIfPresent(String.self, forKey: .selectedVoiceID)
            ?? "af_heart"
        favoriteVoiceIDs = try container.decodeIfPresent(Set<String>.self, forKey: .favoriteVoiceIDs)
            ?? ["af_heart", "af_bella", "bf_emma"]
        useMPS = try container.decodeIfPresent(Bool.self, forKey: .useMPS) ?? true
        pendingDownloadModelIDs = try container.decodeIfPresent(
            Set<String>.self,
            forKey: .pendingDownloadModelIDs
        ) ?? []
        checksForUpdates = try container.decodeIfPresent(Bool.self, forKey: .checksForUpdates) ?? true
    }
}
