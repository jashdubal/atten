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
    /// A model this voice cannot speak without. Atten's bundled engine covers
    /// most voices; the rest name the single model that has to be downloaded
    /// once, after which they work offline like everything else.
    public let requiresModelID: String?

    public init(
        id: String,
        name: String,
        language: String,
        languageCode: String,
        gender: String,
        traits: [String],
        quality: String,
        provider: String = "Kokoro",
        modelID: String? = nil,
        requiresModelID: String? = nil
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
        self.requiresModelID = requiresModelID
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

    /// The SF Symbol shown for the choice in menus and pickers.
    public var icon: String {
        switch self {
        case .system: "desktopcomputer"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }
}

/// How the reader lays a book out.
///
/// A book is pages, so that is the default; the choice is there because a
/// screen is not a book, and someone reading a technical PDF on a small window
/// is better served by scrolling than by pretending.
public enum ReaderViewMode: String, Codable, CaseIterable, Identifiable, Sendable {
    /// One page at a time, turned.
    case page
    /// Two pages facing each other, turned a leaf at a time.
    case spread
    /// One continuous column, scrolled.
    case scroll

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .page: "Single Page"
        case .spread: "Two Pages"
        case .scroll: "Scrolling"
        }
    }

    public var icon: String {
        switch self {
        case .page: "doc.text"
        case .spread: "book.pages"
        case .scroll: "scroll"
        }
    }

    /// How many pages a turn moves through.
    public var pagesPerTurn: Int { self == .spread ? 2 : 1 }

    /// Whether a turn pivots a leaf of the book.
    ///
    /// Only a spread can. A leaf has two sides, and a spread is the only
    /// layout with somewhere for both of them to be: the page it lifts off
    /// and the page it comes down on. Pivoting a single page through a
    /// half-turn sweeps the whole measure of text across the window and shows
    /// the reader the blank back of a sheet on the way, which is a great deal
    /// of movement to read one page further on.
    public var turnsALeaf: Bool { self == .spread }

    public var isPaged: Bool { self != .scroll }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var appearance: AppearancePreference
    public var theme: AttenTheme
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
    /// How fast narration is played back. Separate from `defaultSpeed`, which
    /// is how fast the voice is generated: one is undoable and one is not.
    public var playbackRate: Double
    /// How the reader lays a book out, remembered between books.
    public var readerViewMode: ReaderViewMode
    /// Whether the reader justifies its text, as a printed book does.
    public var readerJustifiesText: Bool
    /// The face the page is set in.
    public var readerFont: ReaderFont
    /// How bright the ink on a typeset page is, as a fraction of the theme's
    /// own. Below 1 the text is carried towards the page's ground, for reading
    /// at night without the glare of full contrast.
    public var readerTextBrightness: Double

    public init(
        appearance: AppearancePreference = .system,
        theme: AttenTheme = .default,
        outputDirectory: String,
        defaultFormat: AudioFormat = .mp3,
        defaultSpeed: Double = 1.0,
        selectedVoiceID: String = "af_heart",
        favoriteVoiceIDs: Set<String> = ["af_heart", "af_bella", "bf_emma"],
        useMPS: Bool = true,
        pendingDownloadModelIDs: Set<String> = [],
        checksForUpdates: Bool = true,
        playbackRate: Double = 1.0,
        readerViewMode: ReaderViewMode = .page,
        readerJustifiesText: Bool = true,
        readerFont: ReaderFont = .default,
        readerTextBrightness: Double = 1.0
    ) {
        self.appearance = appearance
        self.theme = theme
        self.outputDirectory = outputDirectory
        self.defaultFormat = defaultFormat
        self.defaultSpeed = defaultSpeed
        self.selectedVoiceID = selectedVoiceID
        self.favoriteVoiceIDs = favoriteVoiceIDs
        self.useMPS = useMPS
        self.pendingDownloadModelIDs = pendingDownloadModelIDs
        self.checksForUpdates = checksForUpdates
        self.playbackRate = playbackRate
        self.readerViewMode = readerViewMode
        self.readerJustifiesText = readerJustifiesText
        self.readerFont = readerFont
        self.readerTextBrightness = readerTextBrightness
    }

    // Only the export folder is required, because no default for it exists
    // here. Every other key falls back on its own, so a blob written by an
    // older Atten missing newer keys — or by a newer one holding an appearance,
    // theme, or format this version has never heard of — still keeps the
    // preferences that make sense rather than being discarded whole.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        outputDirectory = try container.decode(String.self, forKey: .outputDirectory)
        appearance = (try? container.decodeIfPresent(AppearancePreference.self, forKey: .appearance))
            .flatMap { $0 } ?? .system
        theme = (try? container.decodeIfPresent(AttenTheme.self, forKey: .theme))
            .flatMap { $0 } ?? .default
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
        // Clamped rather than trusted: a rate of zero would look like a player
        // that has silently stopped.
        playbackRate = (try container.decodeIfPresent(Double.self, forKey: .playbackRate))
            .map { min(max(0.5, $0), 3.0) } ?? 1.0
        readerViewMode = (try? container.decodeIfPresent(ReaderViewMode.self, forKey: .readerViewMode))
            .flatMap { $0 } ?? .page
        readerJustifiesText = try container
            .decodeIfPresent(Bool.self, forKey: .readerJustifiesText) ?? true
        readerFont = (try? container
            .decodeIfPresent(ReaderFont.self, forKey: .readerFont))
            .flatMap { $0 } ?? .default
        // Clamped for the same reason the playback rate is: a level written by
        // a version with a wider range must not land outside the one the
        // controls can get back out of.
        readerTextBrightness = (try container
            .decodeIfPresent(Double.self, forKey: .readerTextBrightness))
            .map { min(max(ReaderPagePalette.inkBrightnessRange.lowerBound, $0), ReaderPagePalette.inkBrightnessRange.upperBound) } ?? 1.0
    }
}
