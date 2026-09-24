import Foundation
import XCTest
@testable import Atten
@testable import AttenCore

/// The one control that gets someone out of a screen has to be findable
/// without hunting for it.
///
/// It used to be secondary-coloured text on no background at all, which became
/// a button only once the pointer was already on it. It is a secondary button
/// now: glass at rest, with the title in `text1`.
final class BackButtonTests: XCTestCase {
    /// The title and chevron are what make it findable, so they are held to
    /// the bar for body text on every screen it sits on.
    func testTheButtonsLabelIsReadableOnEveryScreenItSitsOn() {
        let palette = AttenPalette.atten
        for (name, behind) in backgrounds(of: palette) {
            for appearance in [false, true] {
                XCTAssertGreaterThanOrEqual(
                    contrast(value(palette.text1, dark: appearance), value(behind, dark: appearance)),
                    7.0,
                    "\(appearance ? "dark" : "light"): the back button's title on \(name)"
                )
            }
        }
    }

    /// …and on its own fill: the glass tint as it lands on the ground, or
    /// `surface1` when Reduce Transparency makes it opaque.
    func testTheButtonsLabelIsReadableOnItsOwnFill() {
        let palette = AttenPalette.atten
        for appearance in [false, true] {
            let glass = composite(
                value(palette.glass, dark: appearance),
                alpha: appearance ? palette.glass.darkAlpha : palette.glass.lightAlpha,
                over: value(palette.bg, dark: appearance)
            )
            for (name, fill) in [("glass", glass), ("surface1", value(palette.surface1, dark: appearance))] {
                XCTAssertGreaterThanOrEqual(
                    contrast(value(palette.text1, dark: appearance), fill), 7.0,
                    "\(appearance ? "dark" : "light"): the back button's title on \(name)"
                )
            }
        }
    }

    // MARK: -

    private func backgrounds(
        of palette: AttenPalette
    ) -> [(String, AttenThemeColor)] {
        [("appBackground", palette.appBackground), ("surface", palette.surface)]
    }

    private func value(_ color: AttenThemeColor, dark: Bool) -> UInt {
        dark ? color.dark : color.light
    }

    private func composite(_ color: UInt, alpha: Double, over ground: UInt) -> UInt {
        func mix(_ shift: UInt) -> UInt {
            let top = Double((color >> shift) & 0xff), bottom = Double((ground >> shift) & 0xff)
            return UInt((top * alpha + bottom * (1 - alpha)).rounded()) << shift
        }
        return mix(16) | mix(8) | mix(0)
    }

    private func contrast(_ first: UInt, _ second: UInt) -> Double {
        let a = luminance(first)
        let b = luminance(second)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    private func luminance(_ hex: UInt) -> Double {
        func channel(_ raw: UInt) -> Double {
            let value = Double(raw) / 255
            return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel((hex >> 16) & 0xff)
            + 0.7152 * channel((hex >> 8) & 0xff)
            + 0.0722 * channel(hex & 0xff)
    }
}
