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
}
