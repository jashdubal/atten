import AttenCore
import SwiftUI

/// A deterministic mesh-like cover for anything in the Library with no art of
/// its own: a few soft blobs from its `CoverSeed`, drawn with a `Canvas`
/// rather than `MeshGradient` (macOS 15) or a stack of `RadialGradient`
/// views, so a grid of hundreds of these costs one draw call each and no
/// per-cell view hierarchy.
///
/// Silent work is desaturated and dimmed; a generating one rises back to full
/// colour as it finishes; a voiced one is drawn in full and, while it is the
/// thing playing, carries a small animating waveform glyph. Nothing here
/// comes from `AttenColor` — a generated cover is content, like a book's real
/// jacket, and its colour comes from its `CoverSeed` the same way a real
/// jacket's comes from its art.
struct GeneratedCoverView: View {
    let title: String
    let sourceLabel: String?
    let seed: CoverSeed
    var state: AttenCore.LibraryItemState = .voiced
    var isPlaying = false

    private var backdrop: OKLCHColor { OKLCHColor(lightness: 0.22, chroma: 0.05, hue: seed.hue) }
    private var ink: OKLCHColor { OKLCHColor(lightness: 0.97, chroma: 0.01, hue: seed.hue) }

    /// How far along the cover has risen out of silence: 0 while silent, 1
    /// once voiced, and whatever `.generating` reports in between.
    private var colorProgress: Double {
        switch state {
        case .silent: 0
        case .generating(let progress): max(0, min(1, progress))
        case .voiced: 1
        }
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color(backdrop)
            Canvas { context, size in
                for blob in seed.blobs {
                    let center = CGPoint(x: blob.x * size.width, y: blob.y * size.height)
                    let radius = blob.radius * max(size.width, size.height)
                    let color = Color(blob.color)
                    let gradient = Gradient(stops: [
                        .init(color: color, location: 0),
                        .init(color: color.opacity(0), location: 1),
                    ])
                    context.fill(
                        Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                        with: .radialGradient(gradient, center: center, startRadius: 0, endRadius: radius)
                    )
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .attenText(.title1)
                    .foregroundStyle(Color(ink))
                    .lineLimit(3)
                    .minimumScaleFactor(0.4)
                if let sourceLabel {
                    Text(sourceLabel.uppercased())
                        .attenText(.label)
                        .foregroundStyle(Color(ink).opacity(0.72))
                        .lineLimit(1)
                }
            }
            .padding(16)
        }
        .overlay(alignment: .topTrailing) {
            if isPlaying { PlayingGlyph().padding(10) }
        }
        // 0.35/-0.2 at rest for silent work, full colour once voiced; a
        // generation in progress eases between the two as it completes.
        .saturation(0.35 + 0.65 * colorProgress)
        .brightness(-0.2 + 0.2 * colorProgress)
        .accessibilityHidden(true)
    }
}

/// The small waveform glyph that says "this one, right now" — the one place
/// besides a transport control or the primary button that draws in `signal`.
private struct PlayingGlyph: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAnimating = false

    private let heights: [CGFloat] = [7, 12, 9]

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(heights.indices, id: \.self) { index in
                Capsule()
                    .fill(AttenColor.signal)
                    .frame(width: 2.5, height: isAnimating ? heights[index] : 5)
            }
        }
        .frame(height: 14)
        .padding(.horizontal, 5)
        .padding(.vertical, 4)
        .background(AttenColor.glass, in: Capsule())
        .onAppear { isAnimating = !reduceMotion }
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.55).repeatForever(autoreverses: true),
            value: isAnimating
        )
    }
}

extension View {
    /// The frame every cover in the Library draws inside: a hairline inner
    /// border, `AttenRadius.cover`, and a shadow tinted by the art itself —
    /// the book's dominant colour for real art, its seed's hue for a
    /// generated one — rather than a flat black one.
    func attenCoverFrame(tint: OKLCHColor) -> some View {
        modifier(AttenCoverFrame(tint: tint))
    }
}

private struct AttenCoverFrame: ViewModifier {
    let tint: OKLCHColor

    func body(content: Content) -> some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: AttenRadius.cover, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AttenRadius.cover, style: .continuous)
                    .strokeBorder(AttenColor.glassHighlight, lineWidth: 0.5)
            }
            .shadow(color: Color(tint).opacity(0.35), radius: 6, y: 2)
    }
}

extension AttenCore.LibraryItem {
    /// What a generated cover seeds itself from: the content hash when one is
    /// known, or the item's own id so a record that predates hashing still
    /// gets a stable cover rather than a new one every launch.
    var coverSeedKey: String { contentHash ?? id.uuidString }
}
