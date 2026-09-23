import AVFoundation
import SwiftUI

private struct AttenMutedControlsKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var attenMutedControls: Bool {
        get { self[AttenMutedControlsKey.self] }
        set { self[AttenMutedControlsKey.self] = newValue }
    }
}

/// The semantic colours every view draws with.
///
/// Each role carries a light and a dark value, and resolves against whichever
/// appearance the window is drawn in. There is nothing to observe: appearance
/// is handled underneath by AppKit's dynamic colours, so a view that names a
/// role gets the right side of the pair for free.
enum AttenColor {
    static var appBackground: Color { palette.appBackground.color }
    static var sidebar: Color { palette.sidebar.color }
    static var surface: Color { palette.surface.color }
    static var surfaceElevated: Color { palette.surfaceElevated.color }
    static var surfaceMuted: Color { palette.surfaceMuted.color }
    static var separator: Color { palette.separator.color }

    static var textPrimary: Color { palette.textPrimary.color }
    static var textSecondary: Color { palette.textSecondary.color }
    static var textMuted: Color { Color(light: 0x626873, dark: 0x979797) }
    static var border: Color { Color.primary.opacity(0.10) }
    static var accent: Color { palette.accent.color }
    static var accentHover: Color { palette.accentHover.color }
    static var accentSecondary: Color { palette.accentSecondary.color }
    static var success: Color { palette.success.color }
    static var warning: Color { palette.warning.color }
    static var destructive: Color { palette.destructive.color }
    static var focus: Color { palette.accentHover.color }
    static var onAccent: Color { palette.onAccent.color }
    /// The filled part of any progress line — import, narration, download,
    /// playback — and the groove it runs in.
    static var progress: Color { palette.accent.color }
    static var progressTrack: Color { palette.surfaceMuted.color }

    /// Long-form text in the chrome around the page — the snippets under a
    /// search result. The page itself is printed in the theme's reader
    /// colours, which ``BookReaderView`` resolves.
    static var readerText: Color { palette.readerText.color }
    /// Behind a search match or the passage being read aloud. Usually drawn at
    /// full opacity; tint it down when several highlights overlap.
    static var readerHighlight: Color { palette.readerHighlight.color }
    /// Apply with an opacity to dim whatever a focused view pushes back.
    static var scrim: Color { palette.scrim.color }

    /// The AppKit form of the same roles, for the views that are not SwiftUI.
    static var nsTextPrimary: NSColor { palette.textPrimary.nsColor }
    static var nsAccent: NSColor { palette.accent.nsColor }

    static var palette: AttenPalette { .atten }
}

extension Color {
    init(light: UInt, dark: UInt) {
        self.init(nsColor: NSColor(light: light, dark: dark))
    }

    /// One fixed colour, for the few things that do not follow the appearance
    /// of the app — the reader's page decides its own.
    init(hex: UInt) {
        self.init(nsColor: NSColor(hex: hex))
    }
}

extension NSColor {
    convenience init(light: UInt, dark: UInt) {
        self.init(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        }
    }

    convenience init(hex: UInt) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: 1
        )
    }
}

/// How far off the page a surface sits.
enum AttenElevation {
    /// Flush with the ground — a list row, a field.
    case flush
    /// A card, a panel, the compact player.
    case raised
    /// A popover or a sheet, over everything.
    case floating

    var shadowRadius: CGFloat {
        switch self {
        case .flush: 0
        case .raised: 4
        case .floating: 6
        }
    }

    var shadowY: CGFloat {
        switch self {
        case .flush: 0
        case .raised: 1
        case .floating: 2
        }
    }

    var shadowOpacity: Double {
        switch self {
        case .flush: 0
        case .raised: 0.08
        case .floating: 0.10
        }
    }
}

/// Quiet surfaces use a uniform hairline and a small shadow.
struct AttenElevatedSurface: ViewModifier {
    var elevation: AttenElevation = .raised
    var radius: CGFloat = AttenRadius.card
    var fill: Color?

    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .background(fill ?? AttenColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(AttenColor.separator.opacity(scheme == .dark ? 0.75 : 0.55), lineWidth: 1)
            }
            .shadow(
                color: .black.opacity(elevation.shadowOpacity),
                radius: elevation.shadowRadius,
                y: elevation.shadowY
            )
    }
}

extension View {
    /// Apply the shared surface treatment.
    func attenElevated(
        _ elevation: AttenElevation = .raised,
        radius: CGFloat = AttenRadius.card,
        fill: Color? = nil
    ) -> some View {
        modifier(AttenElevatedSurface(elevation: elevation, radius: radius, fill: fill))
    }

}

enum AttenSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 40
    /// The gutter a page of content keeps from the window edge when there is
    /// room for it. The wireframe's calm comes mostly from this number.
    static let page: CGFloat = 56
}

enum AttenRadius {
    static let small: CGFloat = 6
    static let control: CGFloat = 8
    static let card: CGFloat = 12
    /// Book and project artwork. Softer than a control so a grid of covers
    /// reads as objects rather than as buttons.
    static let cover: CGFloat = 8
    /// The compact player in the top chrome and its expanded panel.
    static let player: CGFloat = 14
    /// Fully rounded — segmented filters, chapter pills, the transport ring.
    static let pill: CGFloat = 999
}

/// How long things take, and what they are allowed to do while they take it.
///
/// Every duration here is short enough to read as a response to input rather
/// than as an effect. `accessibilityReduceMotion` is honoured at the call site
/// through ``AttenMotion/animation(_:reduceMotion:)``, which is the only way a
/// screen should be reaching for these.
enum AttenMotion {
    static let fast = 0.12
    static let standard = 0.18
    /// Panel disclosure settles quickly without overshoot.
    static let panel = 0.22
    /// Section changes and Zen enter/exit.
    static let transition = 0.20

    /// A brief crossfade shared by destination and overlay changes. Nothing
    /// slides — a panel never moves the reader's page underneath it, and a
    /// destination change reads as a state change rather than travel.
    enum Transition {
        case destination(forward: Bool)
        case overlay(edge: Edge)
        case fade
    }

    /// The animation for a state change, or `nil` when the reader has asked
    /// the system for less motion. Returning `nil` makes `withAnimation` and
    /// `.animation(_:value:)` apply the change instantly while keeping the
    /// state cue itself, which is what Reduce Motion asks for.
    static func animation(_ duration: Double, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : settle(duration)
    }

    /// A crossfade for the cases where something has to replace something else
    /// and a slide would be motion for its own sake.
    static func fade(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeInOut(duration: fast)
    }

    /// Use this when a view is inserted or removed. Reduce Motion keeps a
    /// short crossfade for orientation; state-only changes should use
    /// ``animation(_:reduceMotion:)`` and become instant instead.
    static func transitionAnimation(_ duration: Double, reduceMotion: Bool) -> Animation? {
        reduceMotion ? .easeInOut(duration: min(duration, fast)) : settle(duration)
    }

    /// A prompt start and a quiet finish, with no bounce or overshoot.
    private static func settle(_ duration: Double) -> Animation {
        .timingCurve(0.22, 1, 0.36, 1, duration: duration)
    }

    static func transition(
        _ transition: Transition,
        reduceMotion: Bool
    ) -> AnyTransition {
        // Every case reads as a crossfade now; the enum and its cases stay so
        // call sites can keep naming what kind of change this is.
        .opacity
    }
}

/// A shared press cue for controls that intentionally use a custom visual
/// rather than one of Atten's filled button styles.
private struct AttenPressFeedback: ViewModifier {
    let isPressed: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(isPressed ? AttenState.pressedOpacity : 1)
            .animation(
                AttenMotion.animation(AttenMotion.fast, reduceMotion: reduceMotion),
                value: isPressed
            )
    }
}

struct AttenFeedbackButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(AttenPressFeedback(isPressed: configuration.isPressed))
    }
}

/// What a control looks like under the pointer, under the finger, and when it
/// is the one selected.
///
/// Held as tokens rather than as literals in each button so that hover means
/// one thing across the sidebar, a cover card and the transport.
enum AttenState {
    /// Lift applied to a surface under the pointer.
    static let hoverFill = 0.08
    /// …and while it is being pressed, where the control darkens instead.
    static let pressedFill = 0.16
    /// A pressed control dims to this opacity.
    static let pressedOpacity = 0.85
    /// Everything disabled fades to here rather than greying its own colours.
    static let disabledOpacity = 0.42
    /// The ring drawn around whatever has keyboard focus.
    static let focusRingWidth: CGFloat = 2.5
}

/// Sizes the player and the cover grid are built from, so the compact player
/// in the top chrome and a cover on Home agree without either owning the
/// other's file.
enum AttenMetrics {
    /// Height of the compact player's row in the top chrome.
    static let compactPlayerHeight: CGFloat = 52
    /// The artwork thumbnail inside it.
    static let compactPlayerArtwork: CGFloat = 36
    /// The expanded player panel's width when it opens as a popover.
    static let expandedPlayerWidth: CGFloat = 380
    /// A cover in a shelf grid, at its smallest. Grids size themselves in
    /// multiples of this with `.adaptive`.
    static let coverGridMinimum: CGFloat = 132
    /// Books are taller than they are wide; this is the ratio covers are drawn
    /// at when the artwork itself is missing or the wrong shape.
    static let coverAspectRatio: CGFloat = 2.0 / 3.0
}

/// Atten's type.
///
/// The app used to be set entirely in monospace, which read as a terminal —
/// the one thing a long-form reading app should not look like. UI text is the
/// system face now, at deliberate weights; monospace is kept for the two
/// places it carries meaning, a timecode that must not jitter as it counts and
/// a numeric readout beside a slider.
enum AttenTypography {
    static let displayTitle = Font.system(size: 30, weight: .semibold)
    static let pageTitle = Font.system(size: 22, weight: .semibold)
    static let sectionTitle = Font.system(size: 15, weight: .semibold)
    static let body = Font.system(size: 13)
    static let control = Font.system(size: 13, weight: .medium)
    static let metadata = Font.system(size: 11)
    static let caption = Font.system(size: 11)
    /// Elapsed and remaining time. Monospaced digits so the line does not
    /// twitch once a second.
    static let timecode = Font.system(size: 11, weight: .medium).monospacedDigit()
    /// A number that sits next to the control that changes it — 1.1×, 120%.
    static let readout = Font.system(size: 12, weight: .medium).monospacedDigit()
}

struct AttenBackdrop: View {
    var body: some View {
        AttenColor.appBackground.ignoresSafeArea()
    }
}

/// Light chrome fades into the same ground as the reading page.
/// Dark chrome uses the darker charcoal sidebar surface.
struct AttenSurfaceModifier: ViewModifier {
    var padding: CGFloat
    var elevated: Bool

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .attenElevated(
                elevated ? .floating : .raised,
                fill: elevated ? AttenColor.surfaceElevated : AttenColor.surface
            )
    }
}

extension View {
    func attenSurface(
        padding: CGFloat = AttenSpacing.md,
        elevated: Bool = false
    ) -> some View {
        modifier(AttenSurfaceModifier(padding: padding, elevated: elevated))
    }

}

struct AttenPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        AttenPrimaryButtonBody(
            label: AnyView(configuration.label),
            isPressed: configuration.isPressed
        )
    }
}

private struct AttenPrimaryButtonBody: View {
    let label: AnyView
    let isPressed: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.attenMutedControls) private var muted
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        label
            .font(AttenTypography.control.weight(.semibold))
            .foregroundStyle((muted ? AttenColor.textSecondary : AttenColor.onAccent).opacity(isEnabled ? 1 : 0.55))
            .padding(.horizontal, AttenSpacing.md)
            .frame(minHeight: 38)
            .background {
                RoundedRectangle(cornerRadius: AttenRadius.control, style: .continuous)
                    .fill(muted
                        ? (isHovering ? AttenColor.surfaceElevated : AttenColor.surface)
                        : (isHovering ? AttenColor.accentHover : AttenColor.accent))
                    .brightness(isPressed ? -0.05 : 0)
            }
            .clipShape(RoundedRectangle(cornerRadius: AttenRadius.control, style: .continuous))
            .overlay {
                if muted {
                    RoundedRectangle(cornerRadius: AttenRadius.control)
                        .strokeBorder(AttenColor.separator.opacity(0.65), lineWidth: 1)
                }
            }
            .opacity(isEnabled ? 1 : AttenState.disabledOpacity)
            .modifier(AttenPressFeedback(isPressed: isPressed))
            .animation(AttenMotion.animation(AttenMotion.standard, reduceMotion: reduceMotion), value: isHovering)
            .onHover { isHovering = $0 }
    }
}

struct AttenSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        AttenSecondaryButtonBody(
            label: AnyView(configuration.label),
            isPressed: configuration.isPressed
        )
    }
}

private struct AttenControlSurface: ViewModifier {
    let muted: Bool
    let background: Color

    func body(content: Content) -> some View {
        if muted {
            content
                .background(background, in: RoundedRectangle(cornerRadius: AttenRadius.control))
                .overlay {
                    RoundedRectangle(cornerRadius: AttenRadius.control)
                        .strokeBorder(AttenColor.separator.opacity(0.65), lineWidth: 1)
                }
        } else {
            content.attenElevated(.flush, radius: AttenRadius.control, fill: background)
        }
    }
}

private struct AttenSecondaryButtonBody: View {
    let label: AnyView
    let isPressed: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.attenMutedControls) private var muted
    @State private var isHovering = false

    var body: some View {
        label
            .font(AttenTypography.control)
            .foregroundStyle((muted ? AttenColor.textSecondary : AttenColor.textPrimary).opacity(isEnabled ? 1 : 0.45))
            .padding(.horizontal, AttenSpacing.sm)
            .frame(minHeight: 34)
            .modifier(AttenControlSurface(muted: muted, background: background))
            .modifier(AttenPressFeedback(isPressed: isPressed))
            .onHover { isHovering = $0 }
    }

    private var background: Color {
        if isPressed { return AttenColor.surfaceMuted.opacity(0.72) }
        return isHovering ? AttenColor.surfaceMuted : AttenColor.surface
    }
}

struct ToolbarIconButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void
    var isEnabled = true
    @Environment(\.attenMutedControls) private var muted

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(AttenTypography.control)
                .frame(width: 30, height: 30)
                .foregroundStyle(muted ? AttenColor.textSecondary : (isHovering ? AttenColor.accentHover : AttenColor.textPrimary))
                .background(isHovering ? AttenColor.surfaceMuted : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: AttenRadius.small))
                .overlay {
                    RoundedRectangle(cornerRadius: AttenRadius.small)
                        .stroke(isHovering ? AttenColor.separator : Color.clear, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .buttonStyle(AttenFeedbackButtonStyle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.42)
        .onHover { isHovering = $0 }
        .help(title)
        .accessibilityLabel(title)
    }
}

/// Back out of a screen that was opened from another.
///
/// The Library used to get this for free from `NavigationStack`, along with a
/// detail column that could no longer be changed from the sidebar. The button
/// is worth keeping; the trap is not.
///
/// It draws as a button at rest rather than only under the pointer. It used to
/// be secondary-coloured text on nothing at all, which meant the one control
/// that gets someone out of a screen was the least visible thing on it — and
/// worst in the themes that are deliberately low contrast, where secondary
/// text is dim by design. The ink is primary, the fill and the border are
/// there before anyone goes looking, and hovering moves it to the accent
/// rather than being what reveals it.
struct AttenBackButton: View {
    let title: String
    let action: () -> Void

    @State private var isHovering = false
    @Environment(\.attenMutedControls) private var muted
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var foreground: Color {
        muted ? AttenColor.textSecondary : (isHovering ? AttenColor.onAccent : AttenColor.textPrimary)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: AttenSpacing.xxs) {
                Image(systemName: "chevron.backward")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(muted ? AttenColor.textSecondary : (isHovering ? AttenColor.onAccent : AttenColor.accent))
                Text(title)
                    .font(AttenTypography.control)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(foreground)
            }
            .padding(.horizontal, AttenSpacing.sm)
            .frame(maxWidth: 190)
            .frame(height: 28)
            .fixedSize(horizontal: true, vertical: false)
            .background(muted
                ? (isHovering ? AttenColor.surfaceElevated : AttenColor.surface)
                : (isHovering ? AttenColor.accent : AttenColor.surfaceElevated))
            .clipShape(RoundedRectangle(cornerRadius: AttenRadius.control))
            .overlay {
                RoundedRectangle(cornerRadius: AttenRadius.control)
                    // The accent rather than the separator: every theme keeps
                    // its accent at 3:1 against its surfaces, which is the bar
                    // WCAG sets for the edge of a control, and the separator
                    // sits at 1.4:1 — a hairline nobody is going to find.
                    .strokeBorder(muted ? AttenColor.separator.opacity(0.65) : AttenColor.accent, lineWidth: muted ? 1 : 1.5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .buttonStyle(AttenFeedbackButtonStyle())
        .onHover { isHovering = $0 }
        .animation(
            AttenMotion.animation(AttenMotion.fast, reduceMotion: reduceMotion),
            value: isHovering
        )
        .help("Back to \(title) (⌘[)")
        .accessibilityLabel("Back to \(title)")
    }
}

/// Atten's own search field.
///
/// `.searchable(placement: .toolbar)` puts the field in the window toolbar,
/// which works on a screen that is only ever itself. The Library is a stack —
/// shelf, book, reader — and only the shelf has a field, so navigating added
/// and removed a toolbar item on every push and pop and the toolbar shuffled
/// its contents each time. A field that belongs to the page it searches stays
/// where it is put.
struct AttenSearchField: View {
    let prompt: String
    @Binding var text: String
    var height: CGFloat = 30

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: AttenSpacing.xs) {
            Image(systemName: "magnifyingglass")
                .font(AttenTypography.caption)
                .foregroundStyle(AttenColor.textSecondary)
                .accessibilityHidden(true)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(AttenTypography.metadata)
                .focused($isFocused)
                .accessibilityLabel(prompt)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(AttenTypography.caption)
                        .foregroundStyle(AttenColor.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, height > 30 ? 14 : AttenSpacing.xs)
        .frame(height: height)
        .attenInput()
        .overlay {
            RoundedRectangle(cornerRadius: AttenRadius.control)
                .stroke(isFocused ? AttenColor.accent : .clear, lineWidth: 1)
        }
        .onExitCommand { text = "" }
    }
}

struct AttenLogo: View {
    var compact = false
    @Environment(\.attenMutedControls) private var muted

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if compact {
                Image(systemName: "waveform")
                    .font(.system(size: 15, weight: .medium))
            } else {
                Text("Atten")
                    .font(.system(size: 20, weight: .semibold))

            }
        }
        .foregroundStyle(muted ? AttenColor.textSecondary : AttenColor.textPrimary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Atten")
    }
}

struct PageHeader: View {
    let eyebrow: String
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: AttenSpacing.xxs) {
            Text(eyebrow.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(AttenColor.accent)
            Text(title)
                .font(AttenTypography.pageTitle)
                .foregroundStyle(AttenColor.textPrimary)
            Text(detail)
                .font(AttenTypography.body)
                .foregroundStyle(AttenColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct InspectorSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AttenSpacing.sm) {
            Text(title.uppercased())
                .font(AttenTypography.metadata.weight(.semibold))
                .tracking(1.4)
                .foregroundStyle(AttenColor.textSecondary)
            content
        }
    }
}

struct StatusBanner: View {
    enum Kind { case success, warning, error, cancelled }

    let kind: Kind
    let message: String
    let dismiss: () -> Void

    private var color: Color {
        switch kind {
        case .success: AttenColor.success
        case .warning: AttenColor.warning
        case .error: AttenColor.destructive
        case .cancelled: AttenColor.warning
        }
    }

    private var icon: String {
        switch kind {
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.circle.fill"
        case .error: "exclamationmark.triangle.fill"
        case .cancelled: "pause.circle.fill"
        }
    }

    var body: some View {
        HStack(spacing: AttenSpacing.xs) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(message)
                .font(AttenTypography.body)
                .foregroundStyle(AttenColor.textPrimary)
            Spacer()
            Button(action: dismiss) { Image(systemName: "xmark") }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, AttenSpacing.sm)
        .frame(minHeight: 38)
        .background(AttenColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: AttenRadius.control))
        .overlay {
            RoundedRectangle(cornerRadius: AttenRadius.control)
                .stroke(color, lineWidth: 1)
        }
        // Keep the dismiss control discoverable while announcing the banner
        // itself as one status region.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(message)
    }
}

/// A common, honest presentation for work that may be active, complete,
/// stopped, or failed. A missing fraction intentionally renders an
/// indeterminate spinner; callers must not invent a percentage for a backend
/// that does not report one.
enum AttenTaskPhase: Equatable {
    case idle
    case active
    case success
    case error
    case cancelled
}

struct AttenProgressStatus: View {
    let title: String
    let detail: String
    let phase: AttenTaskPhase
    let progress: Double?
    let progressLabel: String?
    let metadata: String?
    let actionTitle: String?
    let action: (() -> Void)?

    init(
        title: String,
        detail: String,
        phase: AttenTaskPhase,
        progress: Double? = nil,
        progressLabel: String? = nil,
        metadata: String? = nil,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.detail = detail
        self.phase = phase
        self.progress = progress
        self.progressLabel = progressLabel
        self.metadata = metadata
        self.actionTitle = actionTitle
        self.action = action
    }

    private var color: Color {
        switch phase {
        case .idle: AttenColor.textSecondary
        case .active: AttenColor.accent
        case .success: AttenColor.success
        case .error: AttenColor.destructive
        case .cancelled: AttenColor.warning
        }
    }

    private var icon: String {
        switch phase {
        case .idle: "circle"
        case .active: "arrow.triangle.2.circlepath"
        case .success: "checkmark.circle.fill"
        case .error: "exclamationmark.triangle.fill"
        case .cancelled: "pause.circle.fill"
        }
    }

    private var spokenStatus: String {
        [title, detail, progressLabel, metadata].compactMap { $0 }.joined(separator: ". ")
    }

    var body: some View {
        HStack(alignment: .top, spacing: AttenSpacing.xs) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: AttenSpacing.xxs) {
                Text(title)
                    .font(AttenTypography.control.weight(.semibold))
                    .foregroundStyle(AttenColor.textPrimary)
                Text(detail)
                    .font(AttenTypography.caption)
                    .foregroundStyle(AttenColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let progress {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(color)
                } else if phase == .active {
                    ProgressView()
                        .controlSize(.small)
                }

                if progressLabel != nil || metadata != nil {
                    HStack(spacing: AttenSpacing.sm) {
                        if let progressLabel { Text(progressLabel) }
                        if let metadata { Text(metadata) }
                    }
                    .font(AttenTypography.caption.monospacedDigit())
                    .foregroundStyle(AttenColor.textSecondary)
                }
            }

            Spacer(minLength: AttenSpacing.xs)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(AttenSpacing.sm)
        .background(AttenColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: AttenRadius.control))
        .overlay {
            RoundedRectangle(cornerRadius: AttenRadius.control)
                .stroke(color.opacity(0.8), lineWidth: 1)
        }
        // The optional action (for example, Stop) must remain a separate
        // accessible control rather than being swallowed by the status text.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(spokenStatus)
        .accessibilityAddTraits(phase == .active ? .updatesFrequently : [])
    }
}

struct StatusIndicator: View {
    let title: String
    let detail: String
    let isAvailable: Bool

    var body: some View {
        HStack(spacing: AttenSpacing.xs) {
            Circle()
                .fill(isAvailable ? AttenColor.success : AttenColor.destructive)
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(AttenTypography.metadata.weight(.medium))
                Text(detail)
                    .font(AttenTypography.caption)
                    .foregroundStyle(AttenColor.textSecondary)
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }
}

struct AttenEmptyState: View {
    let title: String
    let systemImage: String
    let detail: String

    var body: some View {
        ContentUnavailableView(
            title,
            systemImage: systemImage,
            description: Text(detail)
        )
        .foregroundStyle(AttenColor.textSecondary)
        .frame(maxWidth: .infinity, minHeight: 300)
    }
}

struct FormRow<Content: View>: View {
    let label: String
    let detail: String?
    @ViewBuilder let content: Content

    init(label: String, detail: String? = nil, @ViewBuilder content: () -> Content) {
        self.label = label
        self.detail = detail
        self.content = content()
    }

    var body: some View {
        LabeledContent {
            content
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                if let detail {
                    Text(detail)
                        .font(AttenTypography.caption)
                        .foregroundStyle(AttenColor.textSecondary)
                }
            }
        }
    }
}

private struct AttenInputModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(AttenColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: AttenRadius.control))
            .overlay {
                RoundedRectangle(cornerRadius: AttenRadius.control, style: .continuous)
                    .stroke(AttenColor.separator, lineWidth: 1)
            }
    }
}

extension View {
    func attenInput() -> some View { modifier(AttenInputModifier()) }

    func attenContentTypography() -> some View {
        font(AttenTypography.body)
            .foregroundStyle(AttenColor.textPrimary)
    }
}

struct AudioFileMetadata: Equatable, Sendable {
    let byteCount: Int64?
    let creationDate: Date?
    let duration: TimeInterval?

    init(url: URL) {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey])
        byteCount = values?.fileSize.map(Int64.init)
        creationDate = values?.creationDate

        if let file = try? AVAudioFile(forReading: url), file.fileFormat.sampleRate > 0 {
            duration = Double(file.length) / file.fileFormat.sampleRate
        } else {
            duration = nil
        }
    }

    var sizeText: String {
        guard let byteCount else { return "Unknown" }
        return ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }

    var durationText: String {
        guard let duration, duration.isFinite else { return "—" }
        let seconds = max(0, Int(duration.rounded()))
        if seconds >= 3_600 {
            return String(format: "%d:%02d:%02d", seconds / 3_600, (seconds / 60) % 60, seconds % 60)
        }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
