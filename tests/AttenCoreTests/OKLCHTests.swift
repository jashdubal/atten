import XCTest
@testable import AttenCore

final class OKLCHTests: XCTestCase {
    func testTheEndsOfTheLightnessAxisAreBlackAndWhite() {
        XCTAssertEqual(OKLCH(0, 0, 0).hex, 0x000000)
        XCTAssertEqual(OKLCH(1, 0, 0).hex, 0xFFFFFF)
    }

    /// sRGB red, green and blue at their published OKLCH coordinates.
    func testKnownReferenceColours() {
        XCTAssertEqual(OKLCH(0.627955, 0.257683, 29.2339).hex, 0xFF0000)
        XCTAssertEqual(OKLCH(0.866440, 0.294827, 142.4953).hex, 0x00FF00)
        XCTAssertEqual(OKLCH(0.452014, 0.313214, 264.0520).hex, 0x0000FF)
    }

    /// Atten's own ground converts out to sRGB and back to where it started.
    func testTheGroundRoundTrips() {
        let ground = OKLCH(0.14, 0.008, 265)
        let rgb = ground.sRGB
        let back = OKLCH(red: rgb.red, green: rgb.green, blue: rgb.blue)
        XCTAssertEqual(back.l, ground.l, accuracy: 1e-6)
        XCTAssertEqual(back.c, ground.c, accuracy: 1e-6)
        XCTAssertEqual(back.h, ground.h, accuracy: 1e-3)
    }

    /// A colour past the edge of sRGB keeps its lightness and hue and gives up
    /// chroma, rather than having a channel clipped and shifting hue.
    func testOutOfGamutColoursGiveUpChromaNotHue() {
        let vivid = OKLCH(0.7, 0.35, 200)
        XCTAssertFalse(vivid.isInSRGBGamut)
        let rgb = vivid.sRGB
        let mapped = OKLCH(red: rgb.red, green: rgb.green, blue: rgb.blue)
        XCTAssertEqual(mapped.l, 0.7, accuracy: 0.01)
        XCTAssertEqual(mapped.h, 200, accuracy: 1)
        XCTAssertLessThan(mapped.c, 0.35)
    }

    func testContrastRunsFromOneToTwentyOne() {
        XCTAssertEqual(WCAG.contrast(0xFFFFFF, 0x000000), 21, accuracy: 1e-9)
        XCTAssertEqual(WCAG.contrast(0x000000, 0xFFFFFF), 21, accuracy: 1e-9)
        XCTAssertEqual(WCAG.contrast(0x777777, 0x777777), 1, accuracy: 1e-9)
    }

    // MARK: - Ambient

    func testAmbientIsHeldToAMidLightnessAndAQuietChroma() {
        let white: UInt = 0xFFFFFF
        let neon = OKLCH(0.95, 0.3, 140).clampedForAmbient(text: white)
        XCTAssertLessThanOrEqual(neon.c, OKLCH.ambientMaximumChroma)
        XCTAssertLessThanOrEqual(neon.l, OKLCH.ambientLightness.upperBound)

        let dark = OKLCH(0.1, 0.05, 30).clampedForAmbient(text: white)
        XCTAssertEqual(dark.l, OKLCH.ambientLightness.lowerBound, accuracy: 1e-9)
        XCTAssertEqual(dark.h, 30)
    }

    /// Whatever is proposed, the text on it stays readable.
    func testAmbientDarkensUntilTextReads() {
        let text: UInt = 0xF5F5F5
        for hue in stride(from: 0.0, to: 360, by: 30) {
            let ambient = OKLCH(0.65, 0.12, hue).clampedForAmbient(text: text)
            XCTAssertGreaterThanOrEqual(WCAG.contrast(text, ambient.hex), 4.5, "hue \(hue)")
            XCTAssertLessThan(ambient.l, 0.65, "hue \(hue) was not darkened")
        }
    }
}
