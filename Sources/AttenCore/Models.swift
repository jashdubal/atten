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

    public init(
        id: String,
        name: String,
        language: String,
        languageCode: String,
        gender: String,
        traits: [String],
        quality: String,
        provider: String = "Kokoro"
    ) {
        self.id = id
        self.name = name
        self.language = language
        self.languageCode = languageCode
        self.gender = gender
        self.traits = traits
        self.quality = quality
        self.provider = provider
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

    public init(
        text: String,
        voiceID: String,
        speed: Double,
        format: AudioFormat,
        outputDirectory: URL,
        filename: String,
        useMPS: Bool = true
    ) {
        self.text = text
        self.voiceID = voiceID
        self.speed = speed
        self.format = format
        self.outputDirectory = outputDirectory
        self.filename = filename
        self.useMPS = useMPS
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

    public init(
        appearance: AppearancePreference = .system,
        outputDirectory: String,
        defaultFormat: AudioFormat = .mp3,
        defaultSpeed: Double = 1.0,
        selectedVoiceID: String = "af_heart",
        favoriteVoiceIDs: Set<String> = ["af_heart", "af_bella", "bf_emma"],
        useMPS: Bool = true
    ) {
        self.appearance = appearance
        self.outputDirectory = outputDirectory
        self.defaultFormat = defaultFormat
        self.defaultSpeed = defaultSpeed
        self.selectedVoiceID = selectedVoiceID
        self.favoriteVoiceIDs = favoriteVoiceIDs
        self.useMPS = useMPS
    }
}
