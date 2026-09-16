import Foundation

/// One text-to-speech repository discovered on the Hugging Face Hub.
public struct HFModel: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let author: String
    public let downloads: Int
    public let likes: Int
    public let languageCodes: [String]
    public let languages: String
    public var byteCount: Int64

    public init(
        id: String,
        name: String,
        author: String,
        downloads: Int,
        likes: Int,
        languageCodes: [String],
        languages: String,
        byteCount: Int64
    ) {
        self.id = id
        self.name = name
        self.author = author
        self.downloads = downloads
        self.likes = likes
        self.languageCodes = languageCodes
        self.languages = languages
        self.byteCount = byteCount
    }

    public var sizeText: String {
        byteCount > 0
            ? ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
            : "Unknown size"
    }

    public var downloadsText: String {
        switch downloads {
        case 1_000_000...: String(format: "%.1fM downloads", Double(downloads) / 1_000_000)
        case 1_000...: String(format: "%.1fK downloads", Double(downloads) / 1_000)
        default: "\(downloads) downloads"
        }
    }

    public var likesText: String {
        likes >= 1_000 ? String(format: "%.1fk", Double(likes) / 1_000) : "\(likes)"
    }

    public func supports(language: String) -> Bool {
        guard let codes = HuggingFaceCatalog.codes(forLanguage: language) else { return true }
        return languageCodes.contains { codes.contains($0) }
    }
}

public enum HFSort: String, CaseIterable, Identifiable, Sendable {
    case mostDownloads = "Most downloads"
    case mostStars = "Most stars"
    case smallestSize = "Smallest size"
    case largestSize = "Largest size"
    case provider = "Provider (A–Z)"
    case modelName = "Model name (A–Z)"

    public var id: String { rawValue }

    var apiParameter: String { self == .mostStars ? "likes" : "downloads" }
}

/// Discovers compatible TTS repositories on the Hugging Face Hub and resolves
/// their exact download size from the repository file manifest.
public struct HuggingFaceCatalog: Sendable {
    public static let userAgent = "Atten/0.2.4"

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Search

    public func search(query: String, language: String?, sort: HFSort) async -> [HFModel] {
        var models: [String: HFModel] = [:]
        for url in Self.queryURLs(query: query, language: language, sort: sort) {
            guard let items = try? await fetchModels(from: url) else { continue }
            for model in items where models[model.id] == nil {
                models[model.id] = model
            }
        }
        return Array(models.values)
    }

    private func fetchModels(from url: URL) async throws -> [HFModel] {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
        let entries = try JSONDecoder().decode([HFEntry].self, from: data)
        return entries.compactMap(\.model)
    }

    static func queryURLs(query: String, language: String?, sort: HFSort) -> [URL] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var queries: [String] = []

        if !trimmed.isEmpty {
            let escaped = trimmed.addingPercentEncoding(
                withAllowedCharacters: .urlQueryAllowed
            ) ?? trimmed
            queries.append("search=\(escaped)&limit=60")
        }

        if let language, let codes = codes(forLanguage: language) {
            for code in codes {
                queries.append("search=mms-tts-\(code)&limit=30")
                queries.append("filter=\(code)&limit=30")
                queries.append("search=vits-\(code)&limit=20")
            }
        } else if trimmed.isEmpty {
            queries.append("search=facebook/mms-tts&limit=100")
            queries.append("search=kokoro&limit=40")
            queries.append("search=xtts&limit=40")
            queries.append("other=vits&limit=60")
            queries.append("search=espnet&limit=25")
            queries.append("search=speecht5&limit=25")
        }

        let expansions = ["likes", "downloads", "safetensors", "gguf", "tags", "cardData"]
            .map { "expand[]=\($0)" }
            .joined(separator: "&")

        return queries.compactMap { parameters in
            URL(string: "https://huggingface.co/api/models?pipeline_tag=text-to-speech"
                + "&\(parameters)&sort=\(sort.apiParameter)&direction=-1&\(expansions)")
        }
    }

    // MARK: - Exact size

    /// Sums the files the downloader actually fetches, so the advertised size
    /// matches what lands on disk.
    public func exactByteCount(for modelID: String) async -> Int64 {
        guard let url = URL(
            string: "https://huggingface.co/api/models/\(modelID)/tree/main?recursive=true"
        ) else { return 0 }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let entries = try? JSONDecoder().decode([TreeEntry].self, from: data) else { return 0 }

        let files = entries
            .filter { $0.type == "file" }
            .map { ($0.path, Int64($0.size ?? 0)) }
        return Self.downloadableByteCount(of: files)
    }

    /// Mirrors `downloader.get_hf_repo_files`: skip media and duplicated
    /// weights, and keep only one quantization per GGUF model part.
    static func downloadableByteCount(of files: [(String, Int64)]) -> Int64 {
        let ignoredExtensions = [
            ".png", ".jpg", ".jpeg", ".gif", ".mp4", ".wav", ".flac", ".mp3",
            ".gitattributes", ".gitignore",
        ]
        let safetensorStems = Set(
            files.map(\.0)
                .filter { $0.lowercased().hasSuffix(".safetensors") }
                .map { String($0.dropLast(".safetensors".count)) }
        )

        var total: Int64 = 0
        var ggufGroups: [String: [(quantization: String, size: Int64)]] = [:]

        for (path, size) in files {
            let lower = path.lowercased()
            if ignoredExtensions.contains(where: lower.hasSuffix) { continue }
            if lower.contains("assets/") || lower.contains("demo/") || lower.contains("examples/") {
                continue
            }
            if lower.hasSuffix(".gguf") {
                let (base, quantization) = quantization(of: path)
                ggufGroups[base, default: []].append((quantization, size))
                continue
            }
            if [".pt", ".bin", ".pth", ".ckpt"].contains(where: lower.hasSuffix) {
                let stem = (path as NSString).deletingPathExtension
                if safetensorStems.contains(stem) { continue }
            }
            total += size
        }

        let preference = ["Q4_K_M", "Q8_0", "BF16", "Q5_K_M", "Q6_K", "F16", "F32"]
        for group in ggufGroups.values {
            let chosen = preference.lazy
                .compactMap { quantization in group.first { $0.quantization == quantization } }
                .first ?? group[0]
            total += chosen.size
        }
        return total
    }

    private static func quantization(of path: String) -> (base: String, quantization: String) {
        let pattern = "[-_](q[0-9]_[a-z0-9_]+|bf16|f16|f32|q8_0|q4_k_m|q5_k_m)\\.gguf$"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(
                  in: path,
                  range: NSRange(path.startIndex..., in: path)
              ),
              let whole = Range(match.range, in: path),
              let range = Range(match.range(at: 1), in: path) else {
            return (path, "RAW")
        }
        return (String(path[..<whole.lowerBound]), path[range].uppercased())
    }

    // MARK: - Compatibility

    /// The backend can only synthesize with Kokoro, XTTS-v2 and VITS/MMS style
    /// checkpoints, so everything else is filtered out of discovery.
    static func isCompatible(id: String, tags: [String]) -> Bool {
        guard !id.isEmpty else { return false }

        let unsupported = [
            "qwen", "moss", "magpie", "chatterbox", "supertonic", "audio.cpp",
            "omnivoice", "voxcpm", "irodori", "sanotts", "kaburi", "breeze-tts",
            "auk", "zerotts", "kahya", "chattts", "fishaudio", "fish-speech",
            "f5-tts", "cosyvoice",
        ]
        let lowercased = id.lowercased()
        if unsupported.contains(where: lowercased.contains) { return false }

        let supported = [
            "mms-tts", "kokoro", "xtts", "kakao-enterprise/vits", "ylacombe/vits",
            "espnet/", "matthijs/vits", "rodrigo-v/vits", "csukuangfj/vits",
            "microsoft/speecht5",
        ]
        if supported.contains(where: lowercased.contains) { return true }

        let supportedTags: Set<String> = ["vits", "mms-tts", "mms", "kokoro", "xtts", "speecht5"]
        return tags.contains { supportedTags.contains($0.lowercased()) }
    }

    // MARK: - Languages

    public static let languages: [String] = [
        "Arabic", "English", "German", "Spanish", "French", "Italian", "Portuguese",
        "Russian", "Turkish", "Dutch", "Polish", "Japanese", "Chinese", "Hindi",
        "Korean", "Vietnamese", "Indonesian", "Ukrainian", "Greek", "Hebrew", "Czech",
        "Romanian", "Hungarian", "Danish", "Norwegian", "Finnish", "Swedish", "Thai",
        "Tamil", "Telugu", "Urdu", "Bengali", "Persian", "Swahili", "Catalan",
    ]

    static let languageCodes: [String: [String]] = [
        "Arabic": ["ara", "arb", "ar"], "English": ["eng", "en"], "German": ["deu", "de"],
        "Spanish": ["spa", "es"], "French": ["fra", "fr"], "Italian": ["ita", "it"],
        "Portuguese": ["por", "pt"], "Russian": ["rus", "ru"], "Turkish": ["tur", "tr"],
        "Dutch": ["nld", "nl"], "Polish": ["pol", "pl"], "Japanese": ["jpn", "ja"],
        "Chinese": ["cmn", "zho", "zh"], "Hindi": ["hin", "hi"], "Korean": ["kor", "ko"],
        "Vietnamese": ["vie", "vi"], "Indonesian": ["ind", "id"], "Ukrainian": ["ukr", "uk"],
        "Greek": ["ell", "el"], "Hebrew": ["heb", "he"], "Czech": ["ces", "cs"],
        "Romanian": ["ron", "ro"], "Hungarian": ["hun", "hu"], "Danish": ["dan", "da"],
        "Norwegian": ["nor", "no"], "Finnish": ["fin", "fi"], "Swedish": ["swe", "sv"],
        "Thai": ["tha", "th"], "Tamil": ["tam", "ta"], "Telugu": ["tel", "te"],
        "Urdu": ["urd", "ur"], "Bengali": ["ben", "bn"], "Persian": ["pes", "fas", "fa"],
        "Swahili": ["swh", "sw"], "Catalan": ["cat", "ca"],
    ]

    static let codeLanguages: [String: String] = languageCodes.reduce(into: [:]) { result, entry in
        for code in entry.value { result[code] = entry.key }
    }

    static func codes(forLanguage language: String) -> [String]? {
        languageCodes[language]
    }

    /// Best-effort language label for a model that was found on disk rather than
    /// through discovery.
    public static func languageSummary(forModelID id: String) -> String {
        if id.caseInsensitiveCompare(ModelStore.kokoroID) == .orderedSame {
            return "English, Spanish, French, Italian, Portuguese, Japanese, Chinese, Hindi"
        }
        if id.localizedCaseInsensitiveContains("xtts") {
            return "Arabic, German, Russian, Turkish, Dutch, Polish, and 16+ languages"
        }
        let suffix = id.split(separator: "-").last.map { String($0).lowercased() } ?? ""
        return codeLanguages[suffix] ?? "Multilingual"
    }

    // MARK: - Hub payloads

    private struct HFEntry: Decodable {
        let id: String
        let downloads: Int?
        let likes: Int?
        let tags: [String]?
        let safetensors: Safetensors?
        let cardData: CardData?

        /// The Hub reports parameter counts per dtype, not bytes.
        struct Safetensors: Decodable {
            let parameters: [String: Int64]?

            var estimatedByteCount: Int64 {
                (parameters ?? [:]).reduce(into: Int64(0)) { total, entry in
                    let width: Int64 = switch entry.key.uppercased() {
                    case "F64", "I64", "U64": 8
                    case "F32", "I32", "U32": 4
                    case "F16", "BF16", "I16", "U16": 2
                    default: 1
                    }
                    total += entry.value * width
                }
            }
        }

        struct CardData: Decodable { let language: LanguageValue? }

        enum LanguageValue: Decodable {
            case single(String)
            case many([String])
            case other

            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let value = try? container.decode(String.self) {
                    self = .single(value)
                } else if let values = try? container.decode([String].self) {
                    self = .many(values)
                } else {
                    self = .other
                }
            }

            var values: [String] {
                switch self {
                case let .single(value): [value]
                case let .many(values): values
                case .other: []
                }
            }
        }

        var model: HFModel? {
            let tags = self.tags ?? []
            guard HuggingFaceCatalog.isCompatible(id: id, tags: tags) else { return nil }

            var codes: [String] = []
            for value in (cardData?.language?.values ?? []) + tags {
                let code = value.hasPrefix("language:")
                    ? String(value.dropFirst("language:".count)).lowercased()
                    : value.lowercased()
                if !code.isEmpty, !codes.contains(code) { codes.append(code) }
            }
            if id.lowercased().hasPrefix("facebook/mms-tts-") {
                let code = String(id.lowercased().dropFirst("facebook/mms-tts-".count))
                if !codes.contains(code) { codes.append(code) }
            }

            var names: [String] = []
            for code in codes {
                if let name = HuggingFaceCatalog.codeLanguages[code], !names.contains(name) {
                    names.append(name)
                }
            }
            var summary = names.prefix(5).joined(separator: ", ")
            if names.count > 5 { summary += ", +\(names.count - 5) more" }
            if summary.isEmpty { summary = HuggingFaceCatalog.languageSummary(forModelID: id) }

            let parts = id.split(separator: "/")
            return HFModel(
                id: id,
                name: parts.count > 1 ? String(parts[1]) : id,
                author: parts.count > 1 ? String(parts[0]) : "",
                downloads: downloads ?? 0,
                likes: likes ?? 0,
                languageCodes: codes,
                languages: summary,
                byteCount: safetensors?.estimatedByteCount ?? 0
            )
        }
    }

    private struct TreeEntry: Decodable {
        let type: String
        let path: String
        let size: Int64?
    }
}

/// Exact repository sizes are expensive to resolve, so they are kept between
/// launches next to the app's other state.
public actor ModelSizeCache {
    private let fileURL: URL
    private var sizes: [String: Int64]

    public init(fileURL: URL) {
        self.fileURL = fileURL
        let data = try? Data(contentsOf: fileURL)
        self.sizes = data.flatMap { try? JSONDecoder().decode([String: Int64].self, from: $0) } ?? [:]
    }

    public func byteCount(for modelID: String) -> Int64? { sizes[modelID] }

    public func store(_ byteCount: Int64, for modelID: String) {
        guard byteCount > 0, sizes[modelID] != byteCount else { return }
        sizes[modelID] = byteCount
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? JSONEncoder().encode(sizes).write(to: fileURL, options: .atomic)
    }
}
