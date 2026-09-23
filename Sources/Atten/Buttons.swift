import SwiftUI

// Atten has three kinds of button and no others.
//
// - Primary: the one thing a screen is for. Signal-filled, 40pt. At most one
//   on a screen, and when it cannot be pressed it says why.
// - Secondary: a real action that is not the point of the screen. Glass,
//   32pt.
// - Tertiary: text alone, for toolbars and the actions around a thing.
//
// An icon that is a hit target rather than something that looks like a
// button — a transport glyph, a cover — uses `.plain`.
//
// Each is a primitive style that draws its own plain button, because a
// `ButtonStyle` never learns that its button has keyboard focus on the Mac and
// so cannot replace the system focus ring with Atten's. A plain button also
// gives the press its dim.

struct AttenPrimaryButtonStyle: PrimitiveButtonStyle {
    /// Shown under the button while it is disabled. A disabled button with no
    /// reason is a puzzle; this is the answer to it. Under rather than beside,
    /// so it never takes width from a button that was given a fixed one.
    var disabledReason: String?

    func makeBody(configuration: Configuration) -> some View {
        AttenPrimaryButtonBody(configuration: configuration, disabledReason: disabledReason)
    }
}

private struct AttenPrimaryButtonBody: View {
    let configuration: PrimitiveButtonStyleConfiguration
    let disabledReason: String?
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: AttenSpacing.xxs) {
            Button(role: configuration.role, action: configuration.trigger) {
                configuration.label
                    .attenText(.callout)
                    .fontWeight(.semibold)
                    .foregroundStyle(AttenColor.signalInk)
                    .padding(.horizontal, AttenSpacing.md)
                    .frame(minHeight: 40)
                    .background(
                        AttenColor.signal,
                        in: RoundedRectangle(cornerRadius: AttenRadius.control, style: .continuous)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(isEnabled ? 1 : AttenState.disabledOpacity)
            .attenFocusRing(cornerRadius: AttenRadius.control)
            if !isEnabled, let disabledReason {
                Text(disabledReason)
                    .attenText(.callout)
                    .foregroundStyle(AttenColor.text2)
                    .lineLimit(1)
            }
        }
    }
}

struct AttenSecondaryButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        AttenSecondaryButtonBody(configuration: configuration)
    }
}

private struct AttenSecondaryButtonBody: View {
    let configuration: PrimitiveButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var isHovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: AttenRadius.control, style: .continuous)
        Button(role: configuration.role, action: configuration.trigger) {
            configuration.label
                .attenText(.callout)
                .foregroundStyle(AttenColor.text1)
                .padding(.horizontal, AttenSpacing.sm)
                .frame(minHeight: 32)
                // The glass tint alone, not a live material: a screen can hold
                // a dozen of these and only three materials.
                .background(reduceTransparency ? AttenColor.surface1 : AttenColor.glass, in: shape)
                .overlay {
                    shape.fill(AttenColor.text1.opacity(AttenState.hoverFill / 2))
                        .opacity(isHovering && isEnabled ? 1 : 0)
                }
                .overlay { shape.strokeBorder(AttenColor.hairline, lineWidth: 1) }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : AttenState.disabledOpacity)
        .attenFocusRing(cornerRadius: AttenRadius.control)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: AttenMotion.hover), value: isHovering)
    }
}

struct AttenTertiaryButtonStyle: PrimitiveButtonStyle {
    /// Holds the label at `text1`, for a tertiary button that stands for the
    /// current choice among several.
    var isSelected = false

    func makeBody(configuration: Configuration) -> some View {
        AttenTertiaryButtonBody(configuration: configuration, isSelected: isSelected)
    }
}

private struct AttenTertiaryButtonBody: View {
    let configuration: PrimitiveButtonStyleConfiguration
    let isSelected: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
        Button(role: configuration.role, action: configuration.trigger) {
            configuration.label
                .attenText(.callout)
                .foregroundStyle(isSelected || (isHovering && isEnabled) ? AttenColor.text1 : AttenColor.text2)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : AttenState.disabledOpacity)
        .attenFocusRing(cornerRadius: AttenRadius.small)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: AttenMotion.hover), value: isHovering)
    }
}

// MARK: - Focus

/// The keyboard focus ring: a 2pt `signal` outline, 2pt clear of the control,
/// with corners concentric to it.
private struct AttenFocusRing: ViewModifier {
    let cornerRadius: CGFloat
    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        let inset = AttenState.focusRingOffset + AttenState.focusRingWidth / 2
        content
            .focused($isFocused)
            .focusEffectDisabled()
            .overlay {
                if isFocused {
                    RoundedRectangle(cornerRadius: cornerRadius + inset, style: .continuous)
                        .stroke(AttenColor.focus, lineWidth: AttenState.focusRingWidth)
                        .padding(-inset)
                        .allowsHitTesting(false)
                }
            }
    }
}

extension View {
    /// Replace the system focus effect on a focusable control with Atten's
    /// ring. The three button styles apply it themselves. A click does not
    /// move focus to a button on the Mac, so the ring appears for keyboard
    /// focus only.
    func attenFocusRing(cornerRadius: CGFloat) -> some View {
        modifier(AttenFocusRing(cornerRadius: cornerRadius))
    }
}
