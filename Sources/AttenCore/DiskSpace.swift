import Foundation

public enum DiskSpace {
    /// The error to report for a write into `directory` that failed. When the
    /// disk is (all but) full that is the reason, whatever the error says:
    /// AVFoundation reports a full disk as a bare "error -40", which tells
    /// the user nothing. The margin matches the speech engine's.
    public static func explain(_ error: Error, writingTo directory: URL, margin: Int = 8 * 1_048_576) -> Error {
        // A fresh URL, because resource values are cached on the instance.
        let values = try? URL(fileURLWithPath: directory.path).resourceValues(forKeys: [.volumeAvailableCapacityKey])
        guard let free = values?.volumeAvailableCapacity, free < margin else { return error }
        return CocoaError(.fileWriteOutOfSpace, userInfo: [NSURLErrorKey: directory, NSUnderlyingErrorKey: error])
    }
}
