import CoreGraphics
import Foundation

/// A colour in the OKLCH space: lightness (0…1), chroma (0…~0.4, moderate is
/// roughly 0.05–0.15), and hue in degrees. Chosen over sRGB or HSB because
/// equal steps in L, C and H look like equal steps to the eye, which is what
/// makes a deterministic seed produce a cover that reads as intentional
/// rather than as noise.
///
/// P1 (foundations) was expected to land its own OKLCH type for the whole
/// app; it hadn't landed when this was written, so the small conversion this
/// file needs lives here instead, under `OKLab`. If P1's version has since
/// landed, the two should be consolidated onto one.
public struct OKLCHColor: Equatable, Sendable {
    public let lightness: Double
    public let chroma: Double
    public let hue: Double

    public init(lightness: Double, chroma: Double, hue: Double) {
        self.lightness = lightness
        self.chroma = chroma
        self.hue = hue
    }

    init(lab: OKLab) {
        let chroma = (lab.a * lab.a + lab.b * lab.b).squareRoot()
        var degrees = atan2(lab.b, lab.a) * 180 / .pi
        if degrees < 0 { degrees += 360 }
        lightness = lab.L
        self.chroma = chroma
        hue = degrees
    }

    var lab: OKLab {
        let radians = hue * .pi / 180
        return OKLab(L: lightness, a: chroma * cos(radians), b: chroma * sin(radians))
    }

    /// Gamma-encoded sRGB in 0...1, clamped into range — OKLab reaches colours
    /// outside the sRGB gamut, and this only needs something drawable.
    public func srgb() -> (r: Double, g: Double, b: Double) {
        lab.toSRGB()
    }
}

/// A deterministic mesh-like cover for a book with no real artwork: a few
/// soft radial blobs, positioned and coloured from the book's content hash so
/// the same book always gets the same cover and different books can be told
/// apart at a glance.
public struct CoverSeed: Equatable, Sendable {
    public let hue: Double
    public let blobs: [CoverBlob]

    // TODO(embedding-hue): derive hue from a local text embedding when one is bundled.
    public init(contentHash: String) {
        var rng = SplitMix64(seed: CoverPalette.fnv1a(contentHash))
        let baseHue = CoverPalette.avoidingVioletBand(rng.nextUnit() * 360)
        hue = baseHue
        let count = 3 + Int(rng.next() % 2)
        blobs = (0..<count).map { _ in
            let jitter = rng.nextUnit() * 50 - 25
            let blobHue = CoverPalette.avoidingVioletBand(baseHue + jitter)
            let lightness = 0.55 + rng.nextUnit() * 0.17
            let chroma = 0.09 + rng.nextUnit() * 0.05
            let x = 0.15 + rng.nextUnit() * 0.7
            let y = 0.15 + rng.nextUnit() * 0.7
            let radius = 0.35 + rng.nextUnit() * 0.3
            return CoverBlob(x: x, y: y, radius: radius, color: OKLCHColor(lightness: lightness, chroma: chroma, hue: blobHue))
        }
    }
}

/// One radial blob of a generated cover. Position, radius and size are
/// normalized to a 0...1 cover, so the caller can draw it at any size.
public struct CoverBlob: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let radius: Double
    public let color: OKLCHColor
}

public enum CoverPalette {
    /// The colour a piece of real cover art is dominated by: downsamples the
    /// image, clusters its pixels in OKLab with k-means, and returns the
    /// centroid of the largest cluster that isn't close to grey — a busy
    /// cover's white page or black spine shouldn't win over its actual colour.
    public static func dominantColor(of image: CGImage, sampleSize: Int = 16, clusters k: Int = 5) -> OKLCHColor {
        let points = pixels(of: image, gridSize: sampleSize).map(OKLab.init(srgb:))
        guard !points.isEmpty else { return OKLCHColor(lightness: 0.6, chroma: 0.1, hue: 0) }
        let clusters = kMeans(points: points, k: min(k, points.count))
        let candidates = clusters.filter { !isNearNeutral($0.centroid) }
        let chosen = (candidates.isEmpty ? clusters : candidates)
            .max { $0.members.count < $1.members.count }
        return OKLCHColor(lab: chosen?.centroid ?? points[0])
    }

    /// A colour derived from cover art (or a `CoverSeed`), adjusted so it can
    /// sit as an ambient wash behind content: lightness and chroma pulled into
    /// a moderate range, then darkened, if it still needs to be, until it
    /// reads at at least 4.5:1 against a near-white `oklch(0.97 0 0)` page.
    public static func ambientColor(from color: OKLCHColor) -> OKLCHColor {
        let chroma = min(color.chroma, 0.12)
        var lightness = min(max(color.lightness, 0.45), 0.65)
        let reference = OKLab(L: 0.97, a: 0, b: 0)
        while lightness > 0 {
            let candidate = OKLCHColor(lightness: lightness, chroma: chroma, hue: color.hue).lab
            if contrastRatio(candidate, reference) >= 4.5 { break }
            lightness -= 0.01
        }
        return OKLCHColor(lightness: max(lightness, 0), chroma: chroma, hue: color.hue)
    }

    public static func contrastRatio(_ a: OKLCHColor, _ b: OKLCHColor) -> Double {
        contrastRatio(a.lab, b.lab)
    }

    // MARK: - Hue

    /// Keeps a hue out of "AI purple" (roughly magenta through violet) by
    /// shifting anything landing there just past the band's far edge.
    static func avoidingVioletBand(_ hue: Double) -> Double {
        let wrapped = hue.truncatingRemainder(dividingBy: 360)
        let normalized = wrapped < 0 ? wrapped + 360 : wrapped
        guard (270..<320).contains(normalized) else { return normalized }
        return (normalized + 50).truncatingRemainder(dividingBy: 360)
    }

    static func fnv1a(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }

    // MARK: - Sampling

    private static func pixels(of image: CGImage, gridSize: Int) -> [(r: Double, g: Double, b: Double)] {
        var buffer = [UInt8](repeating: 0, count: gridSize * gridSize * 4)
        guard let context = CGContext(
            data: &buffer,
            width: gridSize,
            height: gridSize,
            bitsPerComponent: 8,
            bytesPerRow: gridSize * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return [] }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: gridSize, height: gridSize))

        var result: [(r: Double, g: Double, b: Double)] = []
        result.reserveCapacity(gridSize * gridSize)
        for index in 0..<(gridSize * gridSize) {
            let offset = index * 4
            guard buffer[offset + 3] > 10 else { continue } // skip near-transparent pixels
            result.append((
                Double(buffer[offset]) / 255,
                Double(buffer[offset + 1]) / 255,
                Double(buffer[offset + 2]) / 255
            ))
        }
        return result
    }

    // MARK: - k-means

    private struct Cluster {
        var centroid: OKLab
        var members: [OKLab]
    }

    /// A fixed seed, not one derived from the input, so the same image always
    /// clusters the same way regardless of how many pixels it samples to.
    private static let clusterSeed: UInt64 = 0x5eed_c0de

    private static func kMeans(points: [OKLab], k: Int, iterations: Int = 8) -> [Cluster] {
        guard k > 0, !points.isEmpty else { return [] }
        var rng = SplitMix64(seed: clusterSeed)
        var centroids = (0..<k).map { _ in points[Int(rng.next() % UInt64(points.count))] }
        var assignments = [Int](repeating: 0, count: points.count)

        for _ in 0..<iterations {
            for (index, point) in points.enumerated() {
                var bestDistance = Double.greatestFiniteMagnitude
                var bestCluster = 0
                for (clusterIndex, centroid) in centroids.enumerated() {
                    let distance = point.squaredDistance(to: centroid)
                    if distance < bestDistance {
                        bestDistance = distance
                        bestCluster = clusterIndex
                    }
                }
                assignments[index] = bestCluster
            }
            for clusterIndex in 0..<k {
                let members = points.indices.filter { assignments[$0] == clusterIndex }.map { points[$0] }
                guard !members.isEmpty else { continue }
                centroids[clusterIndex] = OKLab(
                    L: members.map(\.L).reduce(0, +) / Double(members.count),
                    a: members.map(\.a).reduce(0, +) / Double(members.count),
                    b: members.map(\.b).reduce(0, +) / Double(members.count)
                )
            }
        }

        return (0..<k).map { clusterIndex in
            let members = points.indices.filter { assignments[$0] == clusterIndex }.map { points[$0] }
            return Cluster(centroid: centroids[clusterIndex], members: members)
        }
    }

    private static func isNearNeutral(_ lab: OKLab) -> Bool {
        (lab.a * lab.a + lab.b * lab.b).squareRoot() < 0.02
    }

    // MARK: - WCAG contrast

    private static func contrastRatio(_ x: OKLab, _ y: OKLab) -> Double {
        let lx = relativeLuminance(of: x)
        let ly = relativeLuminance(of: y)
        let (hi, lo) = lx >= ly ? (lx, ly) : (ly, lx)
        return (hi + 0.05) / (lo + 0.05)
    }

    private static func relativeLuminance(of lab: OKLab) -> Double {
        let linear = lab.toLinearSRGB()
        func clamped(_ c: Double) -> Double { min(max(c, 0), 1) }
        return 0.2126 * clamped(linear.r) + 0.7152 * clamped(linear.g) + 0.0722 * clamped(linear.b)
    }
}

/// Minimal OKLab math: sRGB in, OKLab out, and back. See the note on
/// `OKLCHColor` about consolidating with P1's token conversion once it lands.
struct OKLab: Equatable {
    var L: Double
    var a: Double
    var b: Double

    init(L: Double, a: Double, b: Double) {
        self.L = L
        self.a = a
        self.b = b
    }

    init(srgb: (r: Double, g: Double, b: Double)) {
        let r = Self.linearize(srgb.r)
        let g = Self.linearize(srgb.g)
        let b = Self.linearize(srgb.b)

        let l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
        let m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
        let s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b

        let l_ = Self.cbrt(l), m_ = Self.cbrt(m), s_ = Self.cbrt(s)

        L = 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_
        a = 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_
        self.b = 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_
    }

    func toLinearSRGB() -> (r: Double, g: Double, b: Double) {
        let l_ = L + 0.3963377774 * a + 0.2158037573 * b
        let m_ = L - 0.1055613458 * a - 0.0638541728 * b
        let s_ = L - 0.0894841775 * a - 1.2914855480 * b

        let l = l_ * l_ * l_, m = m_ * m_ * m_, s = s_ * s_ * s_

        let r = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
        let g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
        let b = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
        return (r, g, b)
    }

    func toSRGB() -> (r: Double, g: Double, b: Double) {
        let linear = toLinearSRGB()
        return (Self.gammaEncode(linear.r), Self.gammaEncode(linear.g), Self.gammaEncode(linear.b))
    }

    func squaredDistance(to other: OKLab) -> Double {
        let dl = L - other.L, da = a - other.a, db = b - other.b
        return dl * dl + da * da + db * db
    }

    private static func linearize(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    private static func gammaEncode(_ c: Double) -> Double {
        let clamped = min(max(c, 0), 1)
        return clamped <= 0.0031308 ? clamped * 12.92 : 1.055 * pow(clamped, 1 / 2.4) - 0.055
    }

    private static func cbrt(_ x: Double) -> Double {
        x < 0 ? -pow(-x, 1.0 / 3.0) : pow(x, 1.0 / 3.0)
    }
}

/// A small, fast, fully deterministic PRNG (SplitMix64). Swift's `Hashable`
/// hashing is randomised per process and unsuitable for anything — a cover
/// seed, a cluster's starting centroids — that has to look the same the next
/// time Atten launches.
struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A double in [0, 1).
    mutating func nextUnit() -> Double {
        Double(next() >> 11) * (1.0 / Double(1 << 53))
    }
}
