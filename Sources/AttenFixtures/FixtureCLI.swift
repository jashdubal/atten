import AttenCore
import AttenFixtureKit
import Foundation

/// `make-fixture-library` (#107): writes a realistic library into an empty
/// directory, so the coordinator's live QA has something believable to look
/// at without generating real narration through the speech engine.
@main
enum FixtureCLI {
    static func main() async {
        do {
            let options = try Options(arguments: Array(CommandLine.arguments.dropFirst()))
            try await run(options)
        } catch let error as CLIError {
            FileHandle.standardError.write(Data((error.message + "\n").utf8))
            exit(1)
        } catch {
            FileHandle.standardError.write(Data(("make-fixture-library: \(error.localizedDescription)\n").utf8))
            exit(1)
        }
    }

    private struct Options {
        var count: Int
        var directory: URL
        var voicedFraction: Double

        init(arguments: [String]) throws {
            var count: Int?
            var directory: URL?
            var voicedFraction = 0.3
            var index = 0
            while index < arguments.count {
                let flag = arguments[index]
                func value() throws -> String {
                    index += 1
                    guard index < arguments.count else { throw CLIError("\(flag) needs a value") }
                    return arguments[index]
                }
                switch flag {
                case "--count":
                    guard let parsed = Int(try value()), parsed > 0 else { throw CLIError("--count must be a positive integer") }
                    count = parsed
                case "--dir":
                    directory = URL(fileURLWithPath: try value(), isDirectory: true)
                case "--voiced-fraction":
                    guard let parsed = Double(try value()), (0...1).contains(parsed) else {
                        throw CLIError("--voiced-fraction must be between 0 and 1")
                    }
                    voicedFraction = parsed
                default:
                    throw CLIError("Unknown argument: \(flag)")
                }
                index += 1
            }
            guard let count else { throw CLIError("--count is required") }
            guard let directory else { throw CLIError("--dir is required") }
            self.count = count
            self.directory = directory
            self.voicedFraction = voicedFraction
        }
    }

    private struct CLIError: Error { let message: String; init(_ message: String) { self.message = message } }

    private static func run(_ options: Options) async throws {
        let target = options.directory.standardizedFileURL.resolvingSymlinksInPath()
        try refuseLiveLibrary(target)
        try refuseNonEmpty(target)

        let directories = AppDirectories(applicationSupport: target)
        let built = try LibraryFixture.build(count: options.count, voicedFraction: options.voicedFraction, in: directories)
        try await BookLibraryStore(fileURL: directories.booksFile).save(built.books)
        try LibraryFixture.saveQueue(built.queue, to: directories)

        let voiced = built.books.count { $0.narrationState == .ready }
        let interrupted = built.books.count { $0.narrationState == .interrupted }
        print("""
        Wrote \(built.books.count) books to \(target.path)
          voiced: \(voiced), mid-narration: \(interrupted), queued: \(built.queue.count), \
        drafts: \(built.books.count - voiced - interrupted - built.queue.count)
        Load it with: ATTEN_DATA_DIRECTORY=\(target.path) swift run Atten
        """)
    }

    /// The one hard rule: never let this tool anywhere near a real library.
    private static func refuseLiveLibrary(_ target: URL) throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let live = home.appendingPathComponent("Library/Application Support/Atten", isDirectory: true)
            .standardizedFileURL.resolvingSymlinksInPath()
        guard target != live, !target.path.hasPrefix(live.path + "/") else {
            throw CLIError("Refusing to write into \(live.path) — pass a scratch --dir instead.")
        }
    }

    private static func refuseNonEmpty(_ target: URL) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: target.path, isDirectory: &isDirectory) else { return }
        guard isDirectory.boolValue else { throw CLIError("\(target.path) exists and is not a directory") }
        let contents = try FileManager.default.contentsOfDirectory(atPath: target.path)
        guard contents.isEmpty else { throw CLIError("\(target.path) is not empty — pass an empty or missing --dir") }
    }
}
