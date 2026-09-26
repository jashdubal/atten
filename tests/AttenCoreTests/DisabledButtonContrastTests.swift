import XCTest
@testable import Atten
@testable import AttenCore

/// Disabled secondary and tertiary buttons, like the primary
/// (`PrimaryButtonContrastTests`), never dim their label directly: `.plain`
/// used to fade a disabled label by about half again on top of whatever a
/// style already dimmed, which is what crushed it under 3:1. Secondary dims
/// only its fill and keeps `text1`; tertiary has no fill to dim, so it swaps
/// to the `text3` token instead of fading at all.
final class DisabledButtonContrastTests: XCTestCase {
    private let palette = AttenPalette.atten

    private struct Appearance {
        let name: String
        let color: KeyPath<AttenThemeColor, UInt>
        let alpha: KeyPath<AttenThemeColor, Double>
    }

    private let appearances: [Appearance] = [
        Appearance(name: "light", color: \.light, alpha: \.lightAlpha),
        Appearance(name: "dark", color: \.dark, alpha: \.darkAlpha),
    ]

    private var grounds: [(String, AttenThemeColor)] {
        [("bg", palette.bg), ("surface1", palette.surface1)]
    }

    func testSecondaryDisabledLabelReadsOnTheDimmedGlass() {
        for (groundName, ground) in grounds {
            for appearance in appearances {
                let g = ground[keyPath: appearance.color]
                let glassOverGround = AmbientContrast.composite(
                    palette.glass[keyPath: appearance.color],
                    over: g,
                    opacity: palette.glass[keyPath: appearance.alpha] * AttenState.disabledOpacity
                )
                let ratio = WCAG.contrast(palette.text1[keyPath: appearance.color], glassOverGround)
                XCTAssertGreaterThanOrEqual(
                    ratio, 3,
                    "\(appearance.name): disabled secondary label on \(groundName) is \(String(format: "%.2f", ratio)):1"
                )
            }
        }
    }

    /// Reduce Transparency swaps the glass tint for opaque `surface1`.
    func testSecondaryDisabledLabelReadsWithReduceTransparency() {
        for (groundName, ground) in grounds {
            for appearance in appearances {
                let g = ground[keyPath: appearance.color]
                let fill = AmbientContrast.composite(
                    palette.surface1[keyPath: appearance.color], over: g, opacity: AttenState.disabledOpacity
                )
                let ratio = WCAG.contrast(palette.text1[keyPath: appearance.color], fill)
                XCTAssertGreaterThanOrEqual(
                    ratio, 3,
                    "\(appearance.name): disabled secondary label (reduced transparency) on \(groundName) is \(String(format: "%.2f", ratio)):1"
                )
            }
        }
    }

    /// Tertiary has no fill of its own; the label sits straight on the
    /// ground, at the fixed `text3` disabled tone whether or not it was
    /// selected.
    func testTertiaryDisabledLabelReadsOnTheGround() {
        for (groundName, ground) in grounds {
            for appearance in appearances {
                let g = ground[keyPath: appearance.color]
                let ratio = WCAG.contrast(palette.text3[keyPath: appearance.color], g)
                XCTAssertGreaterThanOrEqual(
                    ratio, 3,
                    "\(appearance.name): disabled tertiary label on \(groundName) is \(String(format: "%.2f", ratio)):1"
                )
            }
        }
    }
}
