import XCTest
@testable import Atten

final class MotionTests: XCTestCase {
    func testReduceMotionRemovesStateAnimationButKeepsTransitionCrossfade() {
        XCTAssertNil(AttenMotion.animation(AttenMotion.standard, reduceMotion: true))
        XCTAssertNotNil(AttenMotion.animation(AttenMotion.standard, reduceMotion: false))
        XCTAssertNotNil(
            AttenMotion.transitionAnimation(
                AttenMotion.panel,
                reduceMotion: true
            )
        )
    }

    func testMotionPrimitivesExposeAllPurposefulTransitionKinds() {
        _ = AttenMotion.transition(.destination(forward: true), reduceMotion: false)
        _ = AttenMotion.transition(.overlay(edge: .leading), reduceMotion: false)
        _ = AttenMotion.transition(.fade, reduceMotion: true)
    }

    /// Nothing lingers long enough to compete with reading or listening.
    func testMotionDurationsStayBrief() {
        XCTAssertLessThanOrEqual(AttenMotion.fast, 0.25)
        XCTAssertLessThanOrEqual(AttenMotion.standard, 0.25)
        XCTAssertLessThanOrEqual(AttenMotion.panel, 0.25)
        XCTAssertLessThanOrEqual(AttenMotion.transition, 0.25)
        XCTAssertLessThanOrEqual(AttenMotion.hover, 0.25)
        XCTAssertLessThanOrEqual(AttenMotion.state, 0.25)
    }

    func testSpringsMatchTheirTokens() {
        XCTAssertEqual(AttenMotion.Spring.small.stiffness, 400)
        XCTAssertEqual(AttenMotion.Spring.small.damping, 34)
        XCTAssertEqual(AttenMotion.Spring.large.stiffness, 260)
        XCTAssertEqual(AttenMotion.Spring.large.damping, 30)
        XCTAssertEqual(
            AttenMotion.animation(.small, reduceMotion: false),
            .interpolatingSpring(stiffness: 400, damping: 34)
        )
    }

    /// Under Reduce Motion a spring becomes a short fade rather than nothing,
    /// so the change still has a cue.
    func testReduceMotionTurnsSpringsIntoAShortFade() {
        for spring: AttenMotion.Spring in [.small, .large] {
            XCTAssertEqual(
                AttenMotion.animation(spring, reduceMotion: true),
                .easeInOut(duration: 0.15)
            )
        }
    }

    func testFadeDurations() {
        XCTAssertEqual(AttenMotion.hover, 0.12)
        XCTAssertEqual(AttenMotion.state, 0.2)
        XCTAssertEqual(AttenMotion.ambient, 0.8)
    }

    /// Shadows read as a hairline of depth, not as ornament.
    func testElevationShadowsStayRestrained() {
        for elevation: AttenElevation in [.flush, .raised, .floating] {
            XCTAssertLessThanOrEqual(elevation.shadowRadius, 6)
            XCTAssertLessThanOrEqual(elevation.shadowOpacity, 0.12)
        }
    }

    /// A pressed control dims instead of shrinking.
    func testPressedStateIsASubtleDim() {
        XCTAssertGreaterThanOrEqual(AttenState.pressedOpacity, 0.8)
        XCTAssertLessThan(AttenState.pressedOpacity, 1)
    }
}
