import Foundation

public struct ExportService: Sendable {
    public init() {}

    public func copyAudio(from source: URL, to destination: URL) throws -> URL {
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw CocoaError(.fileNoSuchFile)
        }
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw CocoaError(.fileWriteFileExists)
        }
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }

    public func renamedAudio(at source: URL, name: String) throws -> URL {
        let cleanName = Self.safeFilename(name)
        guard !cleanName.isEmpty else { throw CocoaError(.fileWriteInvalidFileName) }
        let destination = source.deletingLastPathComponent()
            .appendingPathComponent(cleanName)
            .appendingPathExtension(source.pathExtension)
        guard destination != source else { return source }
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw CocoaError(.fileWriteFileExists)
        }
        try FileManager.default.moveItem(at: source, to: destination)
        return destination
    }

    /// Reduces a title to a name every filesystem Atten writes to will accept.
    /// Names are budgeted in bytes, not characters, because one emoji or one
    /// CJK title character costs three or four of the 255 a path component
    /// gets; the backend reserves the rest for its extension and partial-file
    /// suffix. Leading dots are dropped so a title never produces a file the
    /// user cannot see in Finder.
    public static func safeFilename(_ value: String, maximumByteCount: Int = 180) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
            .union(.newlines)
            .union(.controlCharacters)
        var cleaned = value.components(separatedBy: invalid)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while cleaned.hasPrefix(".") { cleaned.removeFirst() }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        while cleaned.utf8.count > maximumByteCount, !cleaned.isEmpty {
            cleaned.removeLast()
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
