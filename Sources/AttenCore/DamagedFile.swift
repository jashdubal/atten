import Foundation

/// A copy of a file Atten could not wholly read, kept beside it before
/// anything is written over it: `books.json` becomes `books.json.corrupt`,
/// then `books.json.2.corrupt` if that name is taken, so an older copy is
/// never replaced. A copy with the same bytes is reused rather than made
/// again, so launching over the same damage does not pile copies up.
public enum CorruptFileBackup {
    @discardableResult
    public static func preserve(_ url: URL) throws -> URL {
        let original = try Data(contentsOf: url)
        var candidate = url.appendingPathExtension("corrupt")
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            if (try? Data(contentsOf: candidate)) == original { return candidate }
            candidate = url.appendingPathExtension("\(counter)").appendingPathExtension("corrupt")
            counter += 1
        }
        try original.write(to: candidate, options: .withoutOverwriting)
        return candidate
    }
}

/// Reads the records of a damaged JSON array one at a time.
///
/// A save cut short by a crash or a full disk leaves an array with no end,
/// which no JSON parser accepts, so decoding the file whole — or even as an
/// array of optional records — keeps nothing. Every element that finished
/// being written is still intact, though, and this finds them.
public enum JSONArraySalvage {
    /// Each element of `data` that decodes as `T`, in order. Elements that do
    /// not decode are skipped, and so is one the file ends in the middle of.
    public static func decode<T: Decodable>(_ type: T.Type, from data: Data, using decoder: JSONDecoder) -> [T] {
        elements(in: data).compactMap { try? decoder.decode(T.self, from: $0) }
    }

    /// The raw bytes of every complete element of the top-level array, or
    /// nothing when the data is not an array at all.
    static func elements(in data: Data) -> [Data] {
        let bytes = [UInt8](data)
        var index = 0
        func isSpace(_ byte: UInt8) -> Bool { byte == 0x20 || byte == 0x0A || byte == 0x0D || byte == 0x09 }
        while index < bytes.count, isSpace(bytes[index]) { index += 1 }
        guard index < bytes.count, bytes[index] == UInt8(ascii: "[") else { return [] }
        index += 1

        var elements: [Data] = []
        var start: Int?
        var depth = 0
        var inString = false
        var escaped = false
        while index < bytes.count {
            let byte = bytes[index]
            if inString {
                if escaped { escaped = false }
                else if byte == UInt8(ascii: "\\") { escaped = true }
                else if byte == UInt8(ascii: "\"") { inString = false }
            } else if byte == UInt8(ascii: "\"") {
                inString = true
                if start == nil { start = index }
            } else if byte == UInt8(ascii: "{") || byte == UInt8(ascii: "[") {
                if start == nil { start = index }
                depth += 1
            } else if byte == UInt8(ascii: "}") || byte == UInt8(ascii: "]") {
                if depth == 0 {
                    // The array's own end; a bare value before it is complete.
                    if let first = start { elements.append(Data(bytes[first..<index])) }
                    return elements
                }
                depth -= 1
                if depth == 0, let first = start {
                    elements.append(Data(bytes[first...index]))
                    start = nil
                }
            } else if byte == UInt8(ascii: ",") {
                if depth == 0, let first = start {
                    elements.append(Data(bytes[first..<index]))
                    start = nil
                }
            } else if !isSpace(byte), start == nil {
                start = index
            }
            index += 1
        }
        // The file ended inside the array: whatever was in flight is lost.
        return elements
    }
}
