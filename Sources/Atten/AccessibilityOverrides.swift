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
    /// views read `attenReduceMotion` from the environment, which
    /// `attenAccessibilityOverrides()` sets.
    static var reducesMotion: Bool {
        launch.reducesMotion(system: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    static var reducesTransparency: Bool {
        launch.reducesTransparency(system: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency)
    }
}

private struct AttenReduceMotionKey: EnvironmentKey {
    static let defaultValue = false
}

private struct AttenReduceTransparencyKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// The system's Reduce Motion, or the QA override. Views read this, never
    /// `accessibilityReduceMotion`, so the override needs no private SwiftUI
    /// setter.
    var attenReduceMotion: Bool {
        get { self[AttenReduceMotionKey.self] }
        set { self[AttenReduceMotionKey.self] = newValue }
    }

    /// The system's Reduce Transparency, or the QA override.
    var attenReduceTransparency: Bool {
        get { self[AttenReduceTransparencyKey.self] }
        set { self[AttenReduceTransparencyKey.self] = newValue }
    }
}

/// The one place the system's settings are read: at the window root, where
/// they are published down, with the overrides applied, as the Atten keys.
private struct AttenAccessibilityRoot: ViewModifier {
    let overrides: AttenAccessibilityOverrides
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency

    func body(content: Content) -> some View {
        content
            .environment(\.attenReduceMotion, overrides.reducesMotion(system: systemReduceMotion))
            .environment(\.attenReduceTransparency, overrides.reducesTransparency(system: systemReduceTransparency))
    }
}

extension View {
    /// Applies the launch overrides to everything under the window's root.
    func attenAccessibilityOverrides(_ overrides: AttenAccessibilityOverrides = .launch) -> some View {
        modifier(AttenAccessibilityRoot(overrides: overrides))
    }
}
