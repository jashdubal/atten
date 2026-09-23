import Foundation
import Observation

/// Holds a lease until the cancelled task actually finishes unwinding.
@MainActor @Observable
final class SynthesisCoordinator {
    private(set) var activity: String?
    private var lease: UUID?
    var isBusy: Bool { lease != nil }

    func acquire(_ activity: String) -> UUID? {
        guard lease == nil else { return nil }
        let token = UUID()
        lease = token
        self.activity = activity
        return token
    }

    func release(_ token: UUID) {
        guard lease == token else { return }
        lease = nil
        activity = nil
    }
}
