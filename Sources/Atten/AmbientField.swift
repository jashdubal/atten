import AppKit
import AttenCore
import CoreImage
import SwiftUI

/// The playing cover as light: a heavily blurred, low-opacity field behind
/// the content, taken from whatever is playing.
///
/// Built once per item into a small pre-blurred bitmap, so drawing it costs a
/// scaled image and nothing more — a live blur behind scrolling text would be
/// paid for on every frame.
struct AmbientField: Equatable {
    /// What is playing. The field crossfades when this changes.
    let id: String
    let image: CGImage
    /// The strongest opacity at which `text1` still reads at 4.5:1 on every
    /// part of the field, in each appearance.
    let lightOpacity: Double
    let darkOpacity: Double

    static func == (lhs: AmbientField, rhs: AmbientField) -> Bool { lhs.id == rhs.id }

    /// How strong the field would like to be before the contrast check has
    /// its say. Light pages show colour more readily than dark ones.
    static let preferredLightOpacity = 0.34
    static let preferredDarkOpacity = 0.5

    /// Cover pixels are sampled on this grid, then drawn up to four times
    /// the size and blurred.
    private static let grid = (width: 24, height: 36)
    private static let upscale = 4

    /// The field for a cover, or for a generated cover's seed when there is
    /// no artwork.
    @MainActor
    static func make(id: String, cover: NSImage?, seed: CoverSeed) -> AmbientField? {
        let source = cover?.cgImage(forProposedRect: nil, context: nil, hints: nil) ?? render(seed)
        guard let source, let pixels = sample(source, width: grid.width, height: grid.height) else { return nil }
        // Each pixel is held to the ambient band — a moderate lightness and a
        // quiet chroma — so a white page or a neon title becomes light, not a
        // hot spot.
        let calmed = pixels.map { hex -> UInt in
            let rgb = OKLCH(red: Double((hex >> 16) & 0xff) / 255,
                            green: Double((hex >> 8) & 0xff) / 255,
                            blue: Double(hex & 0xff) / 255)
            let ambient = CoverPalette.ambientColor(from: OKLCHColor(lightness: rgb.l, chroma: rgb.c, hue: rgb.h))
            return OKLCH(ambient.lightness, ambient.chroma, ambient.hue).hex
        }
        // Checked against every pixel that will be drawn, not the grid.
        guard let blurred = blur(calmed),
              let shown = sample(blurred, width: blurred.width, height: blurred.height) else { return nil }
        AttenAmbient.shared.set(average(shown))
        let palette = AttenPalette.atten
        return AmbientField(
            id: id,
            image: blurred,
            lightOpacity: AmbientContrast.opacity(
                samples: shown, ground: palette.bg.light, text: palette.text1.light,
                preferred: preferredLightOpacity
            ),
            darkOpacity: AmbientContrast.opacity(
                samples: shown, ground: palette.bg.dark, text: palette.text1.dark,
                preferred: preferredDarkOpacity
            )
        )
    }

    private static func context(width: Int, height: Int) -> CGContext? {
        CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    /// The generated cover's colour fields, drawn the way `GeneratedCover`
    /// draws them.
    private static func render(_ seed: CoverSeed) -> CGImage? {
        let width = grid.width * upscale, height = grid.height * upscale
        guard let context = context(width: width, height: height) else { return nil }
        func cgColor(_ color: OKLCHColor, alpha: Double = 1) -> CGColor {
            let rgb = color.srgb()
            return CGColor(srgbRed: rgb.r, green: rgb.g, blue: rgb.b, alpha: alpha)
        }
        context.setFillColor(cgColor(OKLCHColor(lightness: 0.3, chroma: 0.05, hue: seed.hue)))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        for blob in seed.blobs {
            let colors = [cgColor(blob.color, alpha: 0.75), cgColor(blob.color, alpha: 0)] as CFArray
            guard let gradient = CGGradient(colorsSpace: nil, colors: colors, locations: [0, 1]) else { continue }
            let center = CGPoint(x: blob.x * Double(width), y: (1 - blob.y) * Double(height))
            context.drawRadialGradient(
                gradient, startCenter: center, startRadius: 0,
                endCenter: center, endRadius: blob.radius * Double(width) * 1.4, options: []
            )
        }
        return context.makeImage()
    }

    /// The image drawn at `width` × `height`, as 0xRRGGBB.
    private static func sample(_ image: CGImage, width: Int, height: Int) -> [UInt]? {
        guard let context = context(width: width, height: height) else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { return nil }
        let bytes = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        return (0..<(width * height)).map { index in
            UInt(bytes[index * 4]) << 16 | UInt(bytes[index * 4 + 1]) << 8 | UInt(bytes[index * 4 + 2])
        }
    }

    private static func blur(_ pixels: [UInt]) -> CGImage? {
        guard let small = context(width: grid.width, height: grid.height),
              let data = small.data else { return nil }
        let bytes = data.bindMemory(to: UInt8.self, capacity: pixels.count * 4)
        for (index, hex) in pixels.enumerated() {
            bytes[index * 4] = UInt8((hex >> 16) & 0xff)
            bytes[index * 4 + 1] = UInt8((hex >> 8) & 0xff)
            bytes[index * 4 + 2] = UInt8(hex & 0xff)
            bytes[index * 4 + 3] = 255
        }
        guard let image = small.makeImage() else { return nil }
        let size = CGRect(x: 0, y: 0, width: grid.width * upscale, height: grid.height * upscale)
        let scaled = CIImage(cgImage: image)
            .transformed(by: CGAffineTransform(scaleX: CGFloat(upscale), y: CGFloat(upscale)))
            .clampedToExtent()
            .applyingGaussianBlur(sigma: Double(upscale) * 3)
            .cropped(to: size)
        return CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
            .createCGImage(scaled, from: size)
    }

    private static func average(_ pixels: [UInt]) -> OKLCH {
        var sum = (r: 0.0, g: 0.0, b: 0.0)
        for hex in pixels {
            sum.r += Double((hex >> 16) & 0xff)
            sum.g += Double((hex >> 8) & 0xff)
            sum.b += Double(hex & 0xff)
        }
        let count = Double(max(1, pixels.count)) * 255
        return OKLCH(red: sum.r / count, green: sum.g / count, blue: sum.b / count)
    }
}

/// Holds the field for what is playing, and builds the next one when that
/// changes.
@MainActor
@Observable
final class AmbientFieldStore {
    private(set) var field: AmbientField?
    @ObservationIgnored private var cache: [String: AmbientField] = [:]

    func update(for model: AppModel) async {
        guard let artwork = PlayingArtwork.Source(model: model) else {
            field = nil
            return
        }
        if let cached = cache[artwork.id] {
            field = cached
            return
        }
        var cover: NSImage?
        if let book = artwork.book {
            await model.bookshelf.covers.load(book)
            cover = model.bookshelf.covers.cover(for: book.id)
        }
        guard !Task.isCancelled else { return }
        let made = AmbientField.make(id: artwork.id, cover: cover, seed: CoverSeed.cached(contentHash: artwork.seed))
        cache[artwork.id] = made
        field = made
    }
}

private struct AmbientFieldKey: EnvironmentKey {
    static var defaultValue: AmbientField? { nil }
}

private struct AmbientIsLiveKey: EnvironmentKey {
    static var defaultValue: Bool { false }
}

extension EnvironmentValues {
    /// The playing cover's field, for ``AttenBackdrop`` to draw.
    var attenAmbientField: AmbientField? {
        get { self[AmbientFieldKey.self] }
        set { self[AmbientFieldKey.self] = newValue }
    }

    /// Whether the voice is playing right now rather than paused.
    var attenAmbientIsLive: Bool {
        get { self[AmbientIsLiveKey.self] }
        set { self[AmbientIsLiveKey.self] = newValue }
    }
}

/// The field itself, drawn at the opacity its contrast check allows.
struct AmbientFieldLayer: View {
    /// How much of the field stays while paused. Behind the whole app it goes
    /// out, since only a voice that is live glows; the player keeps a little.
    var pausedStrength = 0.0

    @Environment(\.attenAmbientField) private var field
    @Environment(\.attenAmbientIsLive) private var isLive
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.attenReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let field {
                Image(decorative: field.image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .opacity(colorScheme == .dark ? field.darkOpacity : field.lightOpacity)
                    .id(field.id)
                    .transition(.opacity)
            }
        }
        .opacity(isLive ? 1 : pausedStrength)
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .animation(.easeInOut(duration: reduceMotion ? AttenMotion.reducedFade : AttenMotion.ambient), value: field)
        .animation(.easeInOut(duration: reduceMotion ? AttenMotion.reducedFade : AttenMotion.ambient), value: isLive)
    }
}

extension View {
    /// Builds the field for whatever `model` is playing and hands it to every
    /// ``AttenBackdrop`` below.
    func attenAmbientField(_ model: AppModel) -> some View {
        modifier(AmbientFieldProvider(model: model))
    }
}

private struct AmbientFieldProvider: ViewModifier {
    let model: AppModel
    @State private var store = AmbientFieldStore()

    func body(content: Content) -> some View {
        content
            .environment(\.attenAmbientField, store.field)
            .environment(\.attenAmbientIsLive, model.isPlaying)
            .task(id: PlayingArtwork.Source(model: model)?.id) { await store.update(for: model) }
    }
}
