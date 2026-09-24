import SwiftUI

extension View {
    /// Room under a scroll view's last row for the mini player, which floats
    /// over content instead of taking a strip of the window. Put it inside the
    /// scroll view, on its content, so the content still scrolls under the
    /// glass.
    func attenScrollPadding() -> some View {
        padding(.bottom, clearance)
    }

    /// The same room for a `Form`, whose rows cannot be padded from outside.
    func attenFormScrollPadding() -> some View {
        contentMargins(.bottom, clearance, for: .scrollContent)
    }

    private var clearance: CGFloat { AttenMetrics.playerHeight + AttenSpacing.lg }
}
