import AttenCore
import SwiftUI

/// The small waveform glyph that says "this one, right now" — the one place
/// besides a transport control or the primary button that draws in `signal`.
struct PlayingGlyph: View {
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
            // Without this, the clip and the stroke overlay each cast their
            // own shadow instead of the one flattened shape casting a single
            // shadow — visible in dark appearance as a second, rectangular
            // outline offset to the cover's lower right.
            .compositingGroup()
            .shadow(color: AttenColor.cover(tint).opacity(0.35), radius: 6, y: 2)
    }
}

extension AttenCore.LibraryItem {
    /// What a generated cover seeds itself from: the content hash when one is
    /// known, or the item's own id so a record that predates hashing still
    /// gets a stable cover rather than a new one every launch.
    var coverSeedKey: String { contentHash ?? id.uuidString }
}
