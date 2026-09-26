import AppKit
import SwiftUI
import XCTest
@testable import Atten

/// `ATTEN_QA_REDUCE_MOTION` and `ATTEN_QA_REDUCE_TRANSPARENCY` force the
/// settings on for QA, and change nothing when unset.
@MainActor
final class AccessibilityOverridesTests: XCTestCase {
    func testTheVariablesTurnTheSettingsOn() {
        let overrides = AttenAccessibilityOverrides(environment: [
            "ATTEN_QA_REDUCE_MOTION": "1",
            "ATTEN_QA_REDUCE_TRANSPARENCY": "1",
        ])
        XCTAssertTrue(overrides.reducesMotion(system: false))
        XCTAssertTrue(overrides.reducesTransparency(system: false))
    }

    func testUnsetTheSystemValueStands() {
        for environment in [[:], ["ATTEN_QA_REDUCE_MOTION": "0", "ATTEN_QA_REDUCE_TRANSPARENCY": ""]] {
            let overrides = AttenAccessibilityOverrides(environment: environment)
            for system in [false, true] {
                XCTAssertEqual(overrides.reducesMotion(system: system), system)
                XCTAssertEqual(overrides.reducesTransparency(system: system), system)
            }
        }
    }

    /// The test runner sets neither variable, so the AppKit-facing values
    /// are the system's.
    func testTheLaunchValuesDefaultToTheSystem() {
        XCTAssertEqual(AttenAccessibilityOverrides.launch, AttenAccessibilityOverrides(environment: [:]))
        XCTAssertEqual(
            AttenAccessibilityOverrides.reducesMotion,
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )
        XCTAssertEqual(
            AttenAccessibilityOverrides.reducesTransparency,
            NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        )
    }

    /// What views under the root actually read. Unset, the modifier leaves
    /// alone whatever the view would read without it. That is compared with
    /// a bare render rather than with `NSWorkspace`, because an offscreen
    /// render never sees the system settings, and CI's runner has both on.
    func testTheRootModifierReachesTheEnvironment() throws {
        let forced = AttenAccessibilityOverrides(environment: [
            "ATTEN_QA_REDUCE_MOTION": "1",
            "ATTEN_QA_REDUCE_TRANSPARENCY": "1",
        ])
        XCTAssertEqual(try read(forced), .init(reduceMotion: true, reduceTransparency: true))

        XCTAssertEqual(try read(AttenAccessibilityOverrides(environment: [:])), try read(nil))
    }

    private struct Seen: Equatable {
        var reduceMotion: Bool
        var reduceTransparency: Bool
    }

    private final class Box { var seen: Seen? }

    private struct Probe: View {
        let box: Box
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

        var body: some View {
            box.seen = Seen(reduceMotion: reduceMotion, reduceTransparency: reduceTransparency)
            return Color.clear.frame(width: 1, height: 1)
        }
    }

    private func read(_ overrides: AttenAccessibilityOverrides?) throws -> Seen {
        let box = Box()
        if let overrides {
            _ = ImageRenderer(content: Probe(box: box).attenAccessibilityOverrides(overrides)).nsImage
        } else {
            _ = ImageRenderer(content: Probe(box: box)).nsImage
        }
        return try XCTUnwrap(box.seen, "the probe was never drawn")
    }
}
