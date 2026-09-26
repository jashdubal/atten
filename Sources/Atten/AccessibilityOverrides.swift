import AppKit
import SwiftUI

/// A QA hook: `ATTEN_QA_REDUCE_MOTION=1` and `ATTEN_QA_REDUCE_TRANSPARENCY=1`
/// turn Reduce Motion and Reduce Transparency on for one launch, so both can
/// be checked live without changing a system-wide setting. Read once, at
/// launch. Unset, the system's own settings apply untouched.
struct AttenAccessibilityOverrides: Equatable {
    var reduceMotion = false
    var reduceTransparency = false

    init(environment: [String: String]) {
        reduceMotion = environment["ATTEN_QA_REDUCE_MOTION"] == "1"
        reduceTransparency = environment["ATTEN_QA_REDUCE_TRANSPARENCY"] == "1"
    }

    static let launch = AttenAccessibilityOverrides(environment: ProcessInfo.processInfo.environment)

    func reducesMotion(system: Bool) -> Bool { reduceMotion || system }
    func reducesTransparency(system: Bool) -> Bool { reduceTransparency || system }

    /// For AppKit code, in place of reading `NSWorkspace` directly. SwiftUI
    /// views read `accessibilityReduceMotion` from the environment, which
    /// `attenAccessibilityOverrides()` sets.
    static var reducesMotion: Bool {
        launch.reducesMotion(system: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    static var reducesTransparency: Bool {
        launch.reducesTransparency(system: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency)
    }
}

extension View {
    /// Applies the launch overrides to everything under the window's root.
    func attenAccessibilityOverrides(_ overrides: AttenAccessibilityOverrides = .launch) -> some View {
        transformEnvironment(\._accessibilityReduceMotion) { if overrides.reduceMotion { $0 = true } }
            .transformEnvironment(\._accessibilityReduceTransparency) { if overrides.reduceTransparency { $0 = true } }
    }
}
