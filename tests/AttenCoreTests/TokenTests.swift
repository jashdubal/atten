import SwiftUI
import XCTest
@testable import Atten
@testable import AttenCore

final class TokenTests: XCTestCase {
    func testSpacingStaysOnTheScale() {
        let scale: Set<CGFloat> = [4, 8, 12, 16, 24, 32, 48, 64]
        for value in [
            AttenSpacing.xxs, AttenSpacing.xs, AttenSpacing.sm, AttenSpacing.md,
            AttenSpacing.lg, AttenSpacing.xl, AttenSpacing.xxl, AttenSpacing.xxxl, AttenSpacing.page,
        ] {
            XCTAssertTrue(scale.contains(value), "\(value) is not on the spacing scale")
        }
    }

    func testRadii() {
        XCTAssertEqual(AttenRadius.small, 6)
        XCTAssertEqual(AttenRadius.control, 10)
        XCTAssertEqual(AttenRadius.card, 14)
        XCTAssertEqual(AttenRadius.panel, 20)
        XCTAssertEqual(AttenRadius.cover, 8)
        XCTAssertEqual(AttenRadius.pill, 999)
    }

    /// A button 8pt inside a 14pt card takes a 6pt corner; padding past the
    /// radius leaves it square rather than negative.
    func testNestedCornersAreConcentric() {
        XCTAssertEqual(AttenRadius.concentric(outer: AttenRadius.card, padding: 8), 6)
        XCTAssertEqual(AttenRadius.concentric(outer: AttenRadius.control, padding: 16), 0)
    }

    func testTypeScale() {
        let expected: [(AttenTextStyle, CGFloat, CGFloat, CGFloat)] = [
            (.display, 34, 40, -0.022),
            (.title1, 28, 34, -0.02),
            (.title2, 22, 28, -0.015),
            (.body, 15, 22, -0.005),
            (.callout, 13, 18, 0),
            (.label, 11, 14, 0.08),
            (.reading, 18, 29, 0),
        ]
        for (style, size, lineHeight, tracking) in expected {
            XCTAssertEqual(style.size, size, "\(style)")
            XCTAssertEqual(style.lineHeight, lineHeight, "\(style)")
            XCTAssertEqual(style.tracking, tracking, "\(style)")
            XCTAssertGreaterThanOrEqual(style.lineSpacing, 0, "\(style)")
        }
        XCTAssertTrue(AttenTextStyle.label.isUppercased)
        XCTAssertEqual(AttenTextStyle.allCases.filter(\.isUppercased), [.label])
    }

    @MainActor
    func testAmbientIsClampedWhenSet() {
        let ambient = AttenAmbient()
        let text = AttenPalette.atten.text1.dark
        XCTAssertGreaterThanOrEqual(WCAG.contrast(text, ambient.tint.hex), 4.5, "the neutral default")

        ambient.set(OKLCH(0.9, 0.3, 120))
        XCTAssertLessThanOrEqual(ambient.tint.c, OKLCH.ambientMaximumChroma)
        XCTAssertGreaterThanOrEqual(WCAG.contrast(text, ambient.tint.hex), 4.5)

        ambient.reset()
        XCTAssertEqual(ambient.tint, AttenAmbient.clamped(AttenAmbient.neutral))
    }
}
