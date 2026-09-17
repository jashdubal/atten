import CryptoKit
import Foundation

/// A newer Atten release published on GitHub.
public struct AppRelease: Equatable, Sendable {
    public let version: String
    public let notes: String
    public let pageURL: URL
    public let dmgURL: URL
    public let checksumsURL: URL?
}

public enum UpdateChecker {
    public static let repositoryURL = URL(string: "https://github.com/jashdubal/atten")!
    static let latestReleaseURL = URL(string: "https://api.github.com/repos/jashdubal/atten/releases/latest")!
    static let dmgName = "Atten-macOS-arm64.dmg"
    static let checksumsName = "SHA256SUMS.txt"

    /// Returns the latest release when it is newer than `currentVersion`.
    /// Throws when offline or GitHub is unreachable, so callers can stay silent.
    public static func newerRelease(than currentVersion: String) async throws -> AppRelease? {
        var request = URLRequest(url: latestReleaseURL, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        guard let release = parseRelease(data) else { return nil }
        return isVersion(release.version, newerThan: currentVersion) ? release : nil
    }

    static func parseRelease(_ data: Data) -> AppRelease? {
        struct Payload: Decodable {
            struct Asset: Decodable {
                let name: String
                let browser_download_url: URL
            }
            let tag_name: String
            let body: String?
            let html_url: URL
            let draft: Bool
            let prerelease: Bool
            let assets: [Asset]
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
              !payload.draft, !payload.prerelease,
              let dmg = payload.assets.first(where: { $0.name == dmgName })
        else { return nil }
        let version = payload.tag_name.hasPrefix("v") ? String(payload.tag_name.dropFirst()) : payload.tag_name
        return AppRelease(
            version: version,
            notes: payload.body ?? "",
            pageURL: payload.html_url,
            dmgURL: dmg.browser_download_url,
            checksumsURL: payload.assets.first { $0.name == checksumsName }?.browser_download_url
        )
    }

    public static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        func parts(_ version: String) -> [Int] {
            version.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        }
        let lhs = parts(candidate), rhs = parts(current)
        for index in 0..<max(lhs.count, rhs.count) {
            let left = index < lhs.count ? lhs[index] : 0
            let right = index < rhs.count ? rhs[index] : 0
            if left != right { return left > right }
        }
        return false
    }

    /// Finds the expected SHA-256 for `fileName` in a `shasum`-style listing.
    static func expectedChecksum(for fileName: String, in listing: String) -> String? {
        for line in listing.split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            if fields.count == 2, fields[1] == fileName { return fields[0].lowercased() }
        }
        return nil
    }

    public enum InstallError: LocalizedError {
        case checksumMismatch
        case checksumUnavailable
        case incompleteDownload
        case command(String)

        public var errorDescription: String? {
            switch self {
            case .checksumMismatch: "The downloaded update failed its integrity check."
            case .checksumUnavailable:
                "That release does not publish checksums, so Atten will not install it. You can download it yourself from the releases page."
            case .incompleteDownload:
                "The downloaded update is missing its speech engine or model, so it was not installed."
            case let .command(message): message
            }
        }
    }

    /// Downloads the release DMG, verifies it against the published checksums,
    /// and copies the contained Atten.app into a fresh staging directory.
    public static func downloadAndStage(_ release: AppRelease) async throws -> URL {
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttenUpdate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)

        let (downloaded, _) = try await URLSession.shared.download(from: release.dmgURL)
        let dmg = staging.appendingPathComponent(dmgName)
        try FileManager.default.moveItem(at: downloaded, to: dmg)

        // Verification is not optional. A release without published checksums
        // is not installed at all, so nothing can quietly replace a working
        // Atten with bytes that were never checked.
        guard let checksumsURL = release.checksumsURL else { throw InstallError.checksumUnavailable }
        let (data, _) = try await URLSession.shared.data(from: checksumsURL)
        guard let expected = expectedChecksum(for: dmgName, in: String(decoding: data, as: UTF8.self)),
              try sha256(of: dmg) == expected
        else { throw InstallError.checksumMismatch }

        let mountPoint = staging.appendingPathComponent("mount", isDirectory: true)
        try run("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-readonly", "-mountpoint", mountPoint.path])
        defer { try? run("/usr/bin/hdiutil", ["detach", mountPoint.path, "-force"]) }
        let stagedApp = staging.appendingPathComponent("Atten.app", isDirectory: true)
        try run("/usr/bin/ditto", [mountPoint.appendingPathComponent("Atten.app").path, stagedApp.path])
        guard isCompleteApp(stagedApp) else { throw InstallError.incompleteDownload }
        try? FileManager.default.removeItem(at: dmg)
        return stagedApp
    }

    /// An update is only worth swapping in if it can actually speak offline,
    /// so the staged bundle must carry its executable, its engine, and its
    /// model before the working copy is touched.
    static func isCompleteApp(_ app: URL) -> Bool {
        let resources = app.appendingPathComponent("Contents/Resources", isDirectory: true)
        let required = [
            app.appendingPathComponent("Contents/MacOS/Atten"),
            resources.appendingPathComponent("Backend/atten-backend/atten-backend"),
            resources.appendingPathComponent("Models/Kokoro-82M/kokoro-v1_0.pth"),
        ]
        return required.allSatisfy { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Spawns a detached helper that waits for this process to exit, swaps the
    /// app bundle in place, and relaunches it. The caller should terminate next.
    ///
    /// The working copy is moved aside rather than deleted, and is put back if
    /// the new bundle cannot take its place — so a swap that fails halfway
    /// leaves the user with the Atten they already had, never with none.
    public static func scheduleReplacement(of installedApp: URL, with stagedApp: URL) throws {
        let script = """
        while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.5; done
        previous="$1.atten-previous"
        rm -rf "$previous"
        if mv "$1" "$previous"; then
            if mv "$2" "$1"; then
                rm -rf "$previous"
            else
                mv "$previous" "$1"
            fi
        fi
        xattr -dr com.apple.quarantine "$1" 2>/dev/null
        open "$1"
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, "sh", installedApp.path, stagedApp.path]
        try process.run()
    }

    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func run(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw InstallError.command("\(URL(fileURLWithPath: executable).lastPathComponent) failed while installing the update.")
        }
    }
}
