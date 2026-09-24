import Foundation

/// A colour in OKLCH: perceptual lightness, chroma and hue.
///
/// Atten's tokens are written in OKLCH because lightness there means what it
/// says — two roles at the same L read as equally bright whatever their hue —
/// so a light appearance can be derived from the dark one by mirroring L
/// rather than by hand-picking hex. The conversion runs once, when the
/// palette is built: OKLCH → OKLab → linear sRGB → sRGB, with chroma reduced
/// until the colour fits in sRGB.
public struct OKLCH: Equatable, Sendable {
    /// Lightness, 0 (black) to 1 (white).
    public var l: Double
    /// Chroma, 0 for a neutral. sRGB tops out a little under 0.33.
    public var c: Double
    /// Hue in degrees.
    public var h: Double
    public var alpha: Double

    public init(_ l: Double, _ c: Double, _ h: Double, alpha: Double = 1) {
        self.l = l
        self.c = c
        self.h = h
        self.alpha = alpha
    }

    /// The colour an sRGB triple (0…1, gamma-encoded) is, for round trips.
    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        let r = Self.linear(red), g = Self.linear(green), b = Self.linear(blue)
        let lms = (
            cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b),
            cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b),
            cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        )
        let okL = 0.2104542553 * lms.0 + 0.7936177850 * lms.1 - 0.0040720468 * lms.2
        let okA = 1.9779984951 * lms.0 - 2.4285922050 * lms.1 + 0.4505937099 * lms.2
        let okB = 0.0259040371 * lms.0 + 0.7827717662 * lms.1 - 0.8086757660 * lms.2
        let hue = atan2(okB, okA) * 180 / .pi
        self.init(okL, (okA * okA + okB * okB).squareRoot(), hue < 0 ? hue + 360 : hue, alpha: alpha)
    }

    /// Linear-light sRGB, before any clamping. Channels outside 0…1 mean the
    /// colour is outside the sRGB gamut.
    public var linearSRGB: (red: Double, green: Double, blue: Double) {
        let radians = h * .pi / 180
        let a = c * cos(radians), b = c * sin(radians)
        let lms = (
            pow(l + 0.3963377774 * a + 0.2158037573 * b, 3),
            pow(l - 0.1055613458 * a - 0.0638541728 * b, 3),
            pow(l - 0.0894841775 * a - 1.2914855480 * b, 3)
        )
        return (
            4.0767416621 * lms.0 - 3.3077115913 * lms.1 + 0.2309699292 * lms.2,
            -1.2684380046 * lms.0 + 2.6097574011 * lms.1 - 0.3413193965 * lms.2,
            -0.0041960863 * lms.0 - 0.7034186147 * lms.1 + 1.7076147010 * lms.2
        )
    }

    public var isInSRGBGamut: Bool {
        let rgb = linearSRGB
        let tolerance = 1e-6
        return [rgb.red, rgb.green, rgb.blue].allSatisfy { $0 >= -tolerance && $0 <= 1 + tolerance }
    }

    /// Gamma-encoded sRGB, 0…1. A colour outside the gamut keeps its
    /// lightness and hue and gives up chroma until it fits, which is how CSS
    /// maps OKLCH too; what is left over from rounding is clamped.
    public var sRGB: (red: Double, green: Double, blue: Double) {
        var mapped = self
        if !isInSRGBGamut {
            var low = 0.0, high = c
            for _ in 0..<32 {
                mapped.c = (low + high) / 2
                if mapped.isInSRGBGamut { low = mapped.c } else { high = mapped.c }
            }
            mapped.c = low
        }
        let rgb = mapped.linearSRGB
        return (Self.encoded(rgb.red), Self.encoded(rgb.green), Self.encoded(rgb.blue))
    }

    /// The sRGB colour as 0xRRGGBB, ignoring alpha.
    public var hex: UInt {
        let rgb = sRGB
        func byte(_ value: Double) -> UInt { UInt((value * 255).rounded()) }
        return byte(rgb.red) << 16 | byte(rgb.green) << 8 | byte(rgb.blue)
    }

    private static func linear(_ value: Double) -> Double {
        value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }

    private static func encoded(_ value: Double) -> Double {
        let v = min(max(value, 0), 1)
        return v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055
    }
}

extension OKLCH {
    /// The lightness and chroma an ambient tint may have. Outside this band a
    /// cover's colour either swallows the text on it or turns into neon.
    public static let ambientLightness = 0.45...0.65
    public static let ambientMaximumChroma = 0.12

    /// A proposed ambient colour made safe to put text on: lightness held to
    /// ``ambientLightness``, chroma to ``ambientMaximumChroma``, and then
    /// darkened until `text` reads on it at `minimumContrast` or better.
    public func clampedForAmbient(text: UInt, minimumContrast: Double = 4.5) -> OKLCH {
        var clamped = OKLCH(
            min(max(l, Self.ambientLightness.lowerBound), Self.ambientLightness.upperBound),
            min(max(c, 0), Self.ambientMaximumChroma),
            h,
            alpha: alpha
        )
        while clamped.l > 0, WCAG.contrast(text, clamped.hex) < minimumContrast {
            clamped.l = max(0, clamped.l - 0.01)
        }
        return clamped
    }
}

/// WCAG 2.1 relative luminance and contrast, on 0xRRGGBB colours.
public enum WCAG {
    public static func relativeLuminance(_ hex: UInt) -> Double {
        func channel(_ raw: UInt) -> Double {
            let value = Double(raw) / 255
            return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel((hex >> 16) & 0xff)
            + 0.7152 * channel((hex >> 8) & 0xff)
            + 0.0722 * channel(hex & 0xff)
    }

    /// From 1 (the same colour) to 21 (black on white).
    public static func contrast(_ first: UInt, _ second: UInt) -> Double {
        let a = relativeLuminance(first), b = relativeLuminance(second)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}
