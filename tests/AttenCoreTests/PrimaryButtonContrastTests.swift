import XCTest
@testable import Atten
@testable import AttenCore

/// A disabled primary button dims its fill to 40% and keeps its label at
/// `text1`. The label has to stay readable on that fill — WCAG's 3:1 for
/// interface components — on every ground a primary button sits on.
final class PrimaryButtonContrastTests: XCTestCase {
    func testDisabledLabelReadsOnTheDimmedFill() {
        let palette = AttenPalette.atten
        let grounds: [(String, AttenThemeColor)] = [("bg", palette.bg), ("surface1", palette.surface1)]
        for (name, ground) in grounds {
            for (appearance, value) in [("light", \AttenThemeColor.light), ("dark", \AttenThemeColor.dark)] {
                let fill = composite(palette.signal[keyPath: value], alpha: AttenState.disabledOpacity, over: ground[keyPath: value])
                let ratio = WCAG.contrast(palette.text1[keyPath: value], fill)
                XCTAssertGreaterThanOrEqual(
                    ratio, 3,
                    "\(appearance): disabled label on \(name) is \(String(format: "%.2f", ratio)):1"
                )
            }
        }
    }

    /// `color` at `alpha` laid over an opaque `ground`.
    private func composite(_ color: UInt, alpha: Double, over ground: UInt) -> UInt {
        func mix(_ shift: UInt) -> UInt {
            let top = Double((color >> shift) & 0xff), bottom = Double((ground >> shift) & 0xff)
            return UInt((top * alpha + bottom * (1 - alpha)).rounded()) << shift
        }
        return mix(16) | mix(8) | mix(0)
    }
}
