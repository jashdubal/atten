import CoreGraphics
import Foundation

/// A colour in the OKLCH space: lightness (0…1), chroma (0…~0.4, moderate is
/// roughly 0.05–0.15), and hue in degrees. Chosen over sRGB or HSB because
/// equal steps in L, C and H look like equal steps to the eye, which is what
/// makes a deterministic seed produce a cover that reads as intentional
/// rather than as noise.
///
/// Named fields rather than ``OKLCH`` because a cover's palette code reads
/// better as `lightness`/`chroma`/`hue` than `l`/`c`/`h`; the sRGB and gamut
/// math itself lives once, in ``OKLCH``, and `OKLab` below only bridges to it.
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

    /// Gamma-encoded sRGB in 0...1. A colour outside the sRGB gamut keeps its
    /// lightness and hue and gives up chroma until it fits, via ``OKLCH``.
    public func srgb() -> (r: Double, g: Double, b: Double) {
        let mapped = OKLCH(lightness, chroma, hue).sRGB
        return (mapped.red, mapped.green, mapped.blue)
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

/// OKLab in its rectangular form — the shape k-means clustering wants, since
/// averaging cluster members only makes sense on a linear axis, unlike hue's
/// wraparound degrees. The sRGB and gamut math itself is ``OKLCH``'s; this
/// only rotates between its polar (l, c, h) and this file's rectangular
/// (L, a, b).
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
        self = OKLab(oklch: OKLCH(red: srgb.r, green: srgb.g, blue: srgb.b))
    }

    private init(oklch: OKLCH) {
        let radians = oklch.h * .pi / 180
        L = oklch.l
        a = oklch.c * cos(radians)
        b = oklch.c * sin(radians)
    }

    private var oklch: OKLCH {
        let chroma = (a * a + b * b).squareRoot()
        var hue = atan2(b, a) * 180 / .pi
        if hue < 0 { hue += 360 }
        return OKLCH(L, chroma, hue)
    }

    func toLinearSRGB() -> (r: Double, g: Double, b: Double) {
        let linear = oklch.linearSRGB
        return (linear.red, linear.green, linear.blue)
    }

    func squaredDistance(to other: OKLab) -> Double {
        let dl = L - other.L, da = a - other.a, db = b - other.b
        return dl * dl + da * da + db * db
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
