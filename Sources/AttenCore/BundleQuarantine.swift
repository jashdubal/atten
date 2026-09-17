import Foundation

/// macOS marks everything inside a downloaded disk image as quarantined.
/// Approving Atten at first launch normally clears the whole bundle, but when
/// it does not — the app was copied out of an archive, moved by a script, or
/// approved in a way that only covered the outer bundle — the quarantine flag
/// stays on the bundled speech engine, and macOS kills that helper the moment
/// Atten runs it. The user sees a generation that stops with no explanation.
///
/// Atten repairs this itself: the user has already approved this app, so
/// clearing the flag from its own bundle grants nothing new.
public enum BundleQuarantine {
    public static let attributeName = "com.apple.quarantine"

    /// Whether macOS still marks this file as downloaded.
    public static func isQuarantined(_ url: URL) -> Bool {
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return false }
            return getxattr(path, attributeName, nil, 0, 0, XATTR_NOFOLLOW) >= 0
        }
    }

    /// Clears the flag from a bundle and everything inside it. Returns whether
    /// the file that matters — the engine Atten has to launch — came out clean.
    @discardableResult
    public static func clear(from bundle: URL, verifying helper: URL) -> Bool {
        guard isQuarantined(helper) else { return true }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        process.arguments = ["-d", "-r", attributeName, bundle.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()

        return !isQuarantined(helper)
    }
}
