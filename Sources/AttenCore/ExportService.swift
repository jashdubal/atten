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

    public static func safeFilename(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
            .union(.newlines)
            .union(.controlCharacters)
        return value.components(separatedBy: invalid)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
