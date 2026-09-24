import Foundation

/// The check that keeps text readable over the ambient field.
///
/// The field is the playing cover, blurred and laid over the window's ground
/// at some opacity. What text actually sits on is that blend, so the check is
/// made against the blend: every sampled colour of the field, over the
/// ground, at the opacity about to be used.
public enum AmbientContrast {
    /// `top` laid over `ground` at `opacity`, blended in gamma-encoded sRGB
    /// the way the window compositor blends layers.
    public static func composite(_ top: UInt, over ground: UInt, opacity: Double) -> UInt {
        let alpha = min(max(opacity, 0), 1)
        func channel(_ shift: UInt) -> UInt {
            let a = Double((top >> shift) & 0xff), b = Double((ground >> shift) & 0xff)
            return UInt((a * alpha + b * (1 - alpha)).rounded()) << shift
        }
        return channel(16) | channel(8) | channel(0)
    }

    /// The strongest opacity, no more than `preferred`, at which `text` reads
    /// at `minimum` or better on every sample laid over `ground`. Zero when
    /// even the ground alone fails, which the palette tests rule out.
    public static func opacity(
        samples: [UInt],
        ground: UInt,
        text: UInt,
        preferred: Double,
        minimum: Double = 4.5
    ) -> Double {
        var opacity = min(max(preferred, 0), 1)
        while opacity > 0, samples.contains(where: {
            WCAG.contrast(text, composite($0, over: ground, opacity: opacity)) < minimum
        }) {
            opacity = max(0, opacity - 0.02)
        }
        return opacity
    }
}
