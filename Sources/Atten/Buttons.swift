import AppKit
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
                    // Disabled, only the fill dims. `signalInk` dimmed with
                    // it all but vanished; `text1` holds 3:1 on the dimmed
                    // fill in both appearances.
                    .foregroundStyle(isEnabled ? AttenColor.signalInk : AttenColor.text1)
                    .padding(.horizontal, AttenSpacing.md)
                    .frame(minHeight: 40)
                    .background(
                        AttenColor.signal.opacity(isEnabled ? 1 : AttenState.disabledOpacity),
                        in: RoundedRectangle(cornerRadius: AttenRadius.control, style: .continuous)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(AttenPressDimButtonStyle())
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

/// The press dim alone. `.plain` also fades a disabled label by about half
/// again, on top of whatever a style already dims for disabled, which is what
/// lost "Generate" in dark mode; each style draws its own disabled look.
private struct AttenPressDimButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? AttenState.pressedOpacity : 1)
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
    @Environment(\.attenReduceTransparency) private var reduceTransparency
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
                //
                // Disabled, only the fill dims, same as the primary: `text1`
                // dimmed with it lost the 3:1 a label needs on its own fill.
                .background(
                    (reduceTransparency ? AttenColor.surface1 : AttenColor.glass)
                        .opacity(isEnabled ? 1 : AttenState.disabledOpacity),
                    in: shape
                )
                .overlay {
                    shape.fill(AttenColor.text1.opacity(AttenState.hoverFill / 2))
                        .opacity(isHovering && isEnabled ? 1 : 0)
                }
                .overlay { shape.strokeBorder(AttenColor.hairline, lineWidth: 1) }
                .contentShape(Rectangle())
        }
        .buttonStyle(AttenPressDimButtonStyle())
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
                // A tertiary label has no fill of its own to dim, and fading
                // the label the way the rule fades a fill took it under 3:1
                // on its ground; `text3` is Atten's own 3:1 tier instead.
                .foregroundStyle(
                    isEnabled ? (isSelected || isHovering ? AttenColor.text1 : AttenColor.text2) : AttenColor.text3
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(AttenPressDimButtonStyle())
        .attenFocusRing(cornerRadius: AttenRadius.small)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: AttenMotion.hover), value: isHovering)
    }
}

// MARK: - Focus

/// Whether a key has been pressed yet this launch.
///
/// With system Keyboard Navigation on, macOS gives some control focus before
/// the reader has touched a key, which made a ring appear on the first button
/// at launch as if it had been reached on purpose. Gating every ring on this
/// keeps it for keyboard use only, not whatever focus a window opens with.
private struct AttenKeyboardInteractionKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var attenHasUsedKeyboard: Bool {
        get { self[AttenKeyboardInteractionKey.self] }
        set { self[AttenKeyboardInteractionKey.self] = newValue }
    }
}

/// Watches for the first key press and publishes it down as
/// `attenHasUsedKeyboard`. One instance, at the root of the window.
private struct AttenKeyboardInteractionTracking: ViewModifier {
    @State private var hasUsedKeyboard = false
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .environment(\.attenHasUsedKeyboard, hasUsedKeyboard)
            .onAppear {
                guard monitor == nil else { return }
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    hasUsedKeyboard = true
                    return event
                }
            }
            .onDisappear {
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
            }
    }
}

extension View {
    /// Marks the root of a window so its focus rings only show once the
    /// reader has actually used a key.
    func attenKeyboardInteractionTracking() -> some View {
        modifier(AttenKeyboardInteractionTracking())
    }
}

/// The keyboard focus ring: a 2pt `signal` outline, 2pt clear of the control,
/// with corners concentric to it.
private struct AttenFocusRing: ViewModifier {
    let cornerRadius: CGFloat
    @FocusState private var isFocused: Bool
    @Environment(\.attenHasUsedKeyboard) private var hasUsedKeyboard

    func body(content: Content) -> some View {
        let inset = AttenState.focusRingOffset + AttenState.focusRingWidth / 2
        content
            .focused($isFocused)
            .focusEffectDisabled()
            .overlay {
                if isFocused, hasUsedKeyboard {
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
