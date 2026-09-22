import Foundation
import XCTest
@testable import Atten
@testable import AttenCore

/// The one control that gets someone out of a screen has to be findable
/// without hunting for it.
///
/// It used to be secondary-coloured text on no background at all, which became
/// a button only once the pointer was already on it.
final class BackButtonTests: XCTestCase {
    /// WCAG sets 3:1 for the visual boundary of a control against what is
    /// behind it. The button's edge is drawn in the accent for exactly this
    /// reason: the separator, which it used to use, sits near 1.4:1.
    func testTheButtonsEdgeIsVisibleAgainstEveryScreenItSitsOn() {
        let palette = AttenPalette.atten
        for (name, behind) in backgrounds(of: palette) {
            for appearance in [false, true] {
                let edge = value(palette.accent, dark: appearance)
                XCTAssertGreaterThanOrEqual(
                    contrast(edge, value(behind, dark: appearance)),
                    3.0,
                    "\(appearance ? "dark" : "light"): the back button's edge on \(name)"
                )
            }
        }
    }

    /// And its label has to be readable on its own fill, at the bar for body
    /// text rather than the one for decoration.
    func testTheButtonsLabelIsReadableOnItsOwnFill() {
        let palette = AttenPalette.atten
        for appearance in [false, true] {
            let fill = value(palette.surfaceElevated, dark: appearance)
            XCTAssertGreaterThanOrEqual(
                contrast(value(palette.textPrimary, dark: appearance), fill), 7.0,
                "\(appearance ? "dark" : "light"): the back button's title"
            )
            XCTAssertGreaterThanOrEqual(
                contrast(value(palette.accent, dark: appearance), fill), 3.0,
                "\(appearance ? "dark" : "light"): the back button's chevron"
            )
        }
    }

    /// Hovering it fills with the accent, so the label has to survive that.
    func testTheButtonStaysReadableWhileHovered() {
        let palette = AttenPalette.atten
        for appearance in [false, true] {
            XCTAssertGreaterThanOrEqual(
                contrast(
                    value(palette.onAccent, dark: appearance),
                    value(palette.accent, dark: appearance)
                ),
                4.5,
                "\(appearance ? "dark" : "light"): the back button under the pointer"
            )
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
