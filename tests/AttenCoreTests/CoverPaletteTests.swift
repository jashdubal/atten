import AttenCore
import CoreGraphics
import XCTest

final class CoverPaletteTests: XCTestCase {
    // MARK: - CoverSeed

    func testCoverSeedIsDeterministic() {
        let first = CoverSeed(contentHash: "abc123")
        let second = CoverSeed(contentHash: "abc123")
        XCTAssertEqual(first, second)
    }

    func testDifferentHashesUsuallyProduceDifferentSeeds() {
        let first = CoverSeed(contentHash: "abc123")
        let second = CoverSeed(contentHash: "def456")
        XCTAssertNotEqual(first, second)
    }

    func testCoverSeedHasThreeOrFourBlobs() {
        for hash in ["a", "book", "another book", "0123456789abcdef"] {
            let seed = CoverSeed(contentHash: hash)
            XCTAssertTrue((3...4).contains(seed.blobs.count), hash)
        }
    }

    func testCoverSeedNeverLandsInTheVioletBand() {
        for i in 0..<200 {
            let seed = CoverSeed(contentHash: "hash-\(i)")
            XCTAssertFalse((270..<320).contains(seed.hue), "seed hue \(seed.hue)")
            for blob in seed.blobs {
                XCTAssertFalse((270..<320).contains(blob.color.hue), "blob hue \(blob.color.hue)")
            }
        }
    }

    func testCoverSeedUsesModerateChroma() {
        for i in 0..<50 {
            let seed = CoverSeed(contentHash: "hash-\(i)")
            for blob in seed.blobs {
                XCTAssertLessThan(blob.color.chroma, 0.2)
                XCTAssertGreaterThan(blob.color.chroma, 0)
            }
        }
    }

    // MARK: - ambientColor

    func testAmbientColorClampsLightnessAndChroma() {
        let vivid = OKLCHColor(lightness: 0.95, chroma: 0.3, hue: 140)
        let ambient = CoverPalette.ambientColor(from: vivid)
        XCTAssertLessThanOrEqual(ambient.lightness, 0.65)
        XCTAssertLessThanOrEqual(ambient.chroma, 0.12)
    }

    func testAmbientColorMeetsTheContrastFloorAgainstTheReferencePage() {
        let reference = OKLCHColor(lightness: 0.97, chroma: 0, hue: 0)
        for hue in stride(from: 0.0, to: 360.0, by: 30.0) {
            let candidate = OKLCHColor(lightness: 0.6, chroma: 0.15, hue: hue)
            let ambient = CoverPalette.ambientColor(from: candidate)
            XCTAssertGreaterThanOrEqual(CoverPalette.contrastRatio(ambient, reference), 4.5, "hue \(hue)")
        }
    }

    func testAmbientColorIsDeterministic() {
        let color = OKLCHColor(lightness: 0.8, chroma: 0.2, hue: 45)
        XCTAssertEqual(CoverPalette.ambientColor(from: color), CoverPalette.ambientColor(from: color))
    }

    // MARK: - dominantColor

    func testDominantColorPicksTheMorePopulousNonNeutralCluster() {
        // Mostly a saturated blue with a small red corner: blue must win.
        let image = try! Self.solidImage(width: 32, height: 32, regions: [
            (CGRect(x: 0, y: 0, width: 32, height: 32), (0.1, 0.2, 0.9)),
            (CGRect(x: 0, y: 0, width: 6, height: 6), (0.9, 0.1, 0.1)),
        ])
        let dominant = CoverPalette.dominantColor(of: image)
        // Blue has a higher hue than red; the assertion that matters is that
        // the small red corner did not win.
        XCTAssertGreaterThan(dominant.hue, 180)
    }

    func testDominantColorIgnoresANearNeutralMajority() {
        // Mostly white/grey, with a real colour in a real minority.
        let image = try! Self.solidImage(width: 32, height: 32, regions: [
            (CGRect(x: 0, y: 0, width: 32, height: 32), (0.95, 0.95, 0.95)),
            (CGRect(x: 0, y: 0, width: 10, height: 32), (0.9, 0.15, 0.15)),
        ])
        let dominant = CoverPalette.dominantColor(of: image)
        XCTAssertGreaterThan(dominant.chroma, 0.02)
    }

    func testDominantColorIsDeterministicForTheSameImage() {
        let image = try! Self.solidImage(width: 16, height: 16, regions: [
            (CGRect(x: 0, y: 0, width: 16, height: 16), (0.2, 0.6, 0.3)),
        ])
        XCTAssertEqual(CoverPalette.dominantColor(of: image), CoverPalette.dominantColor(of: image))
    }

    // MARK: - Helpers

    private static func solidImage(
        width: Int,
        height: Int,
        regions: [(rect: CGRect, rgb: (Double, Double, Double))]
    ) throws -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        for region in regions {
            context.setFillColor(red: region.rgb.0, green: region.rgb.1, blue: region.rgb.2, alpha: 1)
            context.fill(region.rect)
        }
        return try XCTUnwrap(context.makeImage())
    }
}
