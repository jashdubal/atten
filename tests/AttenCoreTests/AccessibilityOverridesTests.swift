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

    /// What views under the root actually read. Unset, they read the
    /// system's own values. The system is read in the same offscreen render
    /// rather than from `NSWorkspace`, because an offscreen render never sees
    /// the system settings, and CI's runner has both on.
    func testTheRootModifierReachesTheEnvironment() throws {
        let forced = AttenAccessibilityOverrides(environment: [
            "ATTEN_QA_REDUCE_MOTION": "1",
            "ATTEN_QA_REDUCE_TRANSPARENCY": "1",
        ])
        XCTAssertEqual(try read(forced), .init(reduceMotion: true, reduceTransparency: true))

        XCTAssertEqual(try read(AttenAccessibilityOverrides(environment: [:])), try read(nil))
    }

    /// Only the root reads the system's keys; every other view reads the
    /// Atten keys, or the override would not reach it. AppKit code goes
    /// through `AttenAccessibilityOverrides.reducesMotion` the same way.
    func testNoViewReadsTheSystemSettingsDirectly() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Atten")
        let files = try FileManager.default.contentsOfDirectory(atPath: sources.path)
            .filter { $0.hasSuffix(".swift") && $0 != "AccessibilityOverrides.swift" }
        XCTAssertFalse(files.isEmpty, "found no sources at \(sources.path)")

        let patterns = [#"\.accessibilityReduceMotion"#, #"\.accessibilityReduceTransparency"#, "accessibilityDisplayShouldReduce"]
        var violations: [String] = []
        for file in files {
            let source = try String(contentsOf: sources.appendingPathComponent(file), encoding: .utf8)
            for (index, line) in source.components(separatedBy: .newlines).enumerated()
            where patterns.contains(where: { line.contains($0) }) {
                violations.append("\(file):\(index + 1): \(line.trimmingCharacters(in: .whitespaces))")
            }
        }
        XCTAssertEqual(violations, [], "read attenReduceMotion / attenReduceTransparency instead")
    }

    private struct Seen: Equatable {
        var reduceMotion: Bool
        var reduceTransparency: Bool
    }

    private final class Box { var seen: Seen? }

    /// Reads what every view under the root reads.
    private struct Probe: View {
        let box: Box
        @Environment(\.attenReduceMotion) private var reduceMotion
        @Environment(\.attenReduceTransparency) private var reduceTransparency

        var body: some View {
            box.seen = Seen(reduceMotion: reduceMotion, reduceTransparency: reduceTransparency)
            return Color.clear.frame(width: 1, height: 1)
        }
    }

    /// Reads the system's own values.
    private struct SystemProbe: View {
        let box: Box
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

        var body: some View {
            box.seen = Seen(reduceMotion: reduceMotion, reduceTransparency: reduceTransparency)
            return Color.clear.frame(width: 1, height: 1)
        }
    }

    /// Under the root modifier with `overrides`, or with none, the system's.
    private func read(_ overrides: AttenAccessibilityOverrides?) throws -> Seen {
        let box = Box()
        if let overrides {
            _ = ImageRenderer(content: Probe(box: box).attenAccessibilityOverrides(overrides)).nsImage
        } else {
            _ = ImageRenderer(content: SystemProbe(box: box)).nsImage
        }
        return try XCTUnwrap(box.seen, "the probe was never drawn")
    }
}
