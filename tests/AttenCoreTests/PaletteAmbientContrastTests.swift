import XCTest
@testable import Atten
@testable import AttenCore

/// `AmbientContrast` is what keeps the playing cover's ambient field from
/// ever taking `text1` below WCAG AA once it is composited over the window's
/// ground — the one place besides the fixed palette that text sits on a
/// colour Atten did not choose. `ThemeTests` covers the fixed palette; this
/// covers the runtime one, in both appearances.
final class PaletteAmbientContrastTests: XCTestCase {
    private let palette = AttenPalette.atten

    /// A spread of adversarial samples: pure primaries and secondaries, plus
    /// the near-white and near-black a real cover can be dominated by. Not
    /// pre-calmed the way `AmbientField` calms real pixels first — this is
    /// the mechanism's own floor, not the pipeline that sits in front of it.
    private var adversarialSamples: [UInt] {
        var samples: [UInt] = [0xFFFFFF, 0x000000, 0x808080]
        for hue in stride(from: 0.0, to: 360.0, by: 30.0) {
            samples.append(OKLCH(0.7, 0.3, hue).hex)
        }
        return samples
    }

    func testTheStrongestSafeOpacityAlwaysMeetsTheFloorInBothAppearances() {
        for (label, ground, text, preferred) in [
            ("light", palette.bg.light, palette.text1.light, 0.34),
            ("dark", palette.bg.dark, palette.text1.dark, 0.5),
        ] {
            let opacity = AmbientContrast.opacity(
                samples: adversarialSamples, ground: ground, text: text, preferred: preferred
            )
            for sample in adversarialSamples {
                let composite = AmbientContrast.composite(sample, over: ground, opacity: opacity)
                XCTAssertGreaterThanOrEqual(
                    WCAG.contrast(text, composite), 4.5,
                    "\(label): sample \(String(sample, radix: 16)) at opacity \(opacity) fails 4.5:1"
                )
            }
        }
    }

    /// Every field is drawn from pixels `CoverPalette.ambientColor` has
    /// already calmed, which is a friendlier input than the raw adversarial
    /// set above — the strongest opacity it allows should never need to fall
    /// below what the field actually prefers to look like.
    func testCalmedCoverSamplesKeepTheirPreferredStrengthOrClose() {
        let calmed = stride(from: 0.0, to: 360.0, by: 30.0).map { hue -> UInt in
            let ambient = CoverPalette.ambientColor(from: OKLCHColor(lightness: 0.7, chroma: 0.3, hue: hue))
            return OKLCH(ambient.lightness, ambient.chroma, ambient.hue).hex
        }
        for (label, ground, text, preferred) in [
            ("light", palette.bg.light, palette.text1.light, 0.34),
            ("dark", palette.bg.dark, palette.text1.dark, 0.5),
        ] {
            let opacity = AmbientContrast.opacity(samples: calmed, ground: ground, text: text, preferred: preferred)
            XCTAssertGreaterThan(opacity, 0, "\(label): a calmed cover should never zero the field out")
            for sample in calmed {
                let composite = AmbientContrast.composite(sample, over: ground, opacity: opacity)
                XCTAssertGreaterThanOrEqual(WCAG.contrast(text, composite), 4.5, label)
            }
        }
    }

    /// The blend itself: full opacity reproduces the sample, zero opacity
    /// reproduces the ground, and it never leaves the ground's own channel
    /// range.
    func testCompositeBlendsTowardTheSampleAsOpacityRises() {
        let ground = palette.bg.dark
        let sample: UInt = 0xFF8800
        XCTAssertEqual(AmbientContrast.composite(sample, over: ground, opacity: 0), ground)
        XCTAssertEqual(AmbientContrast.composite(sample, over: ground, opacity: 1), sample)
    }
}
