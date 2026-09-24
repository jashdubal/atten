import SwiftUI

// Glass is chrome only.
//
// It is for the things that float over content — the sidebar, the mini
// player, a sheet or popover — and never for content itself: a card of books
// is not glass. A live material is expensive and busy, so no screen shows more
// than three at once. The secondary button takes the glass tint without the
// material for the same reason.

private struct AttenGlass: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background {
                if reduceTransparency {
                    shape.fill(AttenColor.surface1)
                } else {
                    shape.fill(.ultraThinMaterial)
                        .overlay { shape.fill(AttenColor.glass) }
                }
            }
            .clipShape(shape)
            .overlay { shape.strokeBorder(AttenColor.hairline, lineWidth: 1) }
            // The 1pt edge along the top that catches the light. It fades out
            // down the sides so the corners do not draw a ring.
            .overlay {
                shape.inset(by: 1)
                    .strokeBorder(
                        LinearGradient(
                            colors: [AttenColor.glassHighlight, AttenColor.glassHighlight.opacity(0)],
                            startPoint: .top,
                            endPoint: .center
                        ),
                        lineWidth: 1
                    )
                    .allowsHitTesting(false)
            }
            .shadow(color: AttenColor.glassShadow, radius: 20, y: 12)
    }
}

extension View {
    /// Frosted chrome: the system's thinnest material under Atten's glass
    /// tint, a hairline edge, a lit top edge and a soft shadow. Under Reduce
    /// Transparency it is an opaque `surface1` with the same edge.
    func attenGlass(cornerRadius: CGFloat) -> some View {
        modifier(AttenGlass(cornerRadius: cornerRadius))
    }
}
