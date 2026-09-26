import Foundation

/// Why a model download stopped, reduced to what someone can act on. The
/// backend reports Python's own wording ("[Errno 28] No space left on
/// device", "HTTP Error 404: Not Found"), which is never shown as is.
public enum ModelDownloadFailure: Equatable, Sendable {
    case offline
    case diskFull
    case notFound
    case needsAccess
    case engineMissing
    case other

    public init(_ error: Error) {
        switch error {
        case BackendError.backendNotFound: self = .engineMissing
        case let BackendError.processFailed(message): self.init(message: message)
        default: self.init(message: error.localizedDescription)
        }
    }

    public init(message: String) {
        let text = message.lowercased()
        func mentions(_ phrases: String...) -> Bool { phrases.contains { text.contains($0) } }
        if mentions("no space left", "errno 28", "disk is full") {
            self = .diskFull
        } else if mentions("http error 401", "http error 403") {
            self = .needsAccess
        } else if mentions("http error 404", "no files found for hugging face") {
            self = .notFound
        } else if mentions(
            "urlopen error", "nodename nor servname", "name or service not known",
            "temporary failure in name resolution", "network is unreachable", "timed out",
            "connection reset", "connection refused", "connection aborted", "remote end closed",
            "incompleteread", "internet connection appears to be offline"
        ) {
            self = .offline
        } else {
            self = .other
        }
    }

    public var message: String {
        switch self {
        case .offline: "No internet connection"
        case .diskFull: "Not enough disk space"
        case .notFound: "Not found on Hugging Face"
        case .needsAccess: "Needs access on Hugging Face"
        case .engineMissing: "Speech engine not found"
        case .other: "Download didn’t finish"
        }
    }
}
