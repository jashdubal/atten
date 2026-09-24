import AttenCore
import AVFoundation
import AttenCore
import SwiftUI

/// The semantic colours every view draws with.
///
/// Each role carries a light and a dark value, and resolves against whichever
/// appearance the window is drawn in. There is nothing to observe: appearance
/// is handled underneath by AppKit's dynamic colours, so a view that names a
/// role gets the right side of the pair for free.
///
/// The roles are the ones ``AttenPalette`` is built from — `bg` through
/// `signalInk`. The older names below them are what the screens were written
/// against, and resolve to those roles until each screen is moved over.
enum AttenColor {
    static var bg: Color { palette.bg.color }
    static var surface1: Color { palette.surface1.color }
    static var glass: Color { palette.glass.color }
    static var hairline: Color { palette.hairline.color }
    static var text1: Color { palette.text1.color }
    static var text2: Color { palette.text2.color }
    static var text3: Color { palette.text3.color }
    /// Voice that is live: playing, generating, the current word, the primary
    /// button, a focus ring. Nothing else is drawn in it.
    static var signal: Color { palette.signal.color }
    static var signalInk: Color { palette.signalInk.color }
    static var glassHighlight: Color { palette.glassHighlight.color }
    static var glassShadow: Color { palette.glassShadow.color }
    /// Apply with the opacity the elevation asks for.
    static var shadow: Color { palette.shadow.color }
    /// The tint taken from what is playing. Set it through ``AttenAmbient``.
    @MainActor static var ambient: Color { AttenAmbient.shared.color }

    static var appBackground: Color { palette.appBackground.color }
    static var sidebar: Color { palette.sidebar.color }
    static var surface: Color { palette.surface.color }
    static var surfaceElevated: Color { palette.surfaceElevated.color }
    static var surfaceMuted: Color { palette.surfaceMuted.color }
    static var separator: Color { palette.separator.color }

    static var textPrimary: Color { palette.textPrimary.color }
    static var textSecondary: Color { palette.textSecondary.color }
    static var textMuted: Color { palette.textMuted.color }
    static var border: Color { palette.hairline.color }
    static var accent: Color { palette.accent.color }
    static var accentHover: Color { palette.accentHover.color }
    static var accentSecondary: Color { palette.accentSecondary.color }
    static var success: Color { palette.success.color }
    static var warning: Color { palette.warning.color }
    static var destructive: Color { palette.destructive.color }
    static var focus: Color { palette.signal.color }
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
    static var nsText3: NSColor { palette.text3.nsColor }
    static var nsSignal: NSColor { palette.signal.nsColor }

    /// A voice's own colour, from its `VoiceProfile` hue: content, not chrome,
    /// so it is drawn only where the voice itself is shown.
    static func voice(hue: Double) -> Color {
        AttenThemeColor(light: OKLCH(0.58, 0.11, hue), dark: OKLCH(0.76, 0.11, hue)).color
    }

    /// A colour a generated cover was designed in. Covers are content and keep
    /// their colours in both appearances.
    static func cover(_ color: OKLCHColor) -> Color {
        Color(hex: OKLCH(color.lightness, color.chroma, color.hue).hex)
    }

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

extension Color {
    /// Cover art and its dominant colour are the one place colour comes from
    /// content rather than the palette — a generated cover's blobs, an
    /// ambient wash, a shadow tinted by what a book's jacket actually looks
    /// like. `CoverPalette` hands back an `OKLCHColor`; this is where it
    /// becomes something a view can draw.
    init(_ oklch: OKLCHColor) {
        let srgb = oklch.srgb()
        self.init(.sRGB, red: srgb.r, green: srgb.g, blue: srgb.b)
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
                color: AttenColor.shadow.opacity(elevation.shadowOpacity),
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

/// The only distances Atten lays things out with: 4, 8, 12, 16, 24, 32, 48
/// and 64. A gap that is not one of these is a gap nobody chose.
enum AttenSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
    static let xxxl: CGFloat = 64
    /// The gutter a page of content keeps from the window edge when there is
    /// room for it. The wireframe's calm comes mostly from this number.
    static let page: CGFloat = xxl
}

enum AttenRadius {
    static let small: CGFloat = 6
    static let control: CGFloat = 10
    static let card: CGFloat = 14
    static let panel: CGFloat = 20
    /// Book and project artwork. Softer than a control so a grid of covers
    /// reads as objects rather than as buttons.
    static let cover: CGFloat = 8
    /// Fully rounded — segmented filters, chapter pills, the transport ring.
    static let pill: CGFloat = 999
    /// The compact player in the top chrome and its expanded panel.
    @available(*, deprecated, renamed: "card")
    static let player: CGFloat = card

    /// The radius of a shape nested inside another.
    ///
    /// Nested corners are concentric: the inner radius is the outer radius
    /// minus the padding between them, so the gap between the two curves is
    /// the same all the way round. Giving both the same radius is what makes a
    /// button look pinched inside its card.
    static func concentric(outer: CGFloat, padding: CGFloat) -> CGFloat {
        max(outer - padding, 0)
    }
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

    /// A fade under the pointer.
    static let hover = 0.12
    /// A fade between two states of the same thing.
    static let state = 0.2
    /// The ambient tint changing behind the player. Slow on purpose: it is
    /// light moving, not an event.
    static let ambient = 0.8
    /// What every spring becomes under Reduce Motion.
    static let reducedFade = 0.15

    /// The two springs anything that moves uses. Animate transform, opacity
    /// and blur with them; never layout.
    enum Spring {
        /// A control, a chip, a row: quick and without bounce.
        case small
        /// A panel, a sheet, the player opening.
        case large

        var stiffness: Double {
            switch self {
            case .small: 400
            case .large: 260
            }
        }

        var damping: Double {
            switch self {
            case .small: 34
            case .large: 30
            }
        }
    }

    static func spring(_ spring: Spring) -> Animation {
        .interpolatingSpring(stiffness: spring.stiffness, damping: spring.damping)
    }

    /// The spring, or a short fade when the reader has asked for less motion.
    static func animation(_ spring: Spring, reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: reducedFade) : self.spring(spring)
    }

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
    static let disabledOpacity = 0.4
    /// The ring drawn around whatever has keyboard focus…
    static let focusRingWidth: CGFloat = 2
    /// …and how far clear of the control it sits.
    static let focusRingOffset: CGFloat = 2
}

/// Sizes the player and the cover grid are built from, so the mini player
/// and the scroll views it floats over agree without either owning the
/// other's file.
enum AttenMetrics {
    /// Height of the mini player's pill.
    static let playerHeight: CGFloat = 64
    /// The expanded player panel's width when it opens as a popover.
    static let expandedPlayerWidth: CGFloat = 380
    /// A cover in a shelf grid, at its smallest. Grids size themselves in
    /// multiples of this with `.adaptive`.
    static let coverGridMinimum: CGFloat = 132
    /// Books are taller than they are wide; this is the ratio covers are drawn
    /// at when the artwork itself is missing or the wrong shape.
    static let coverAspectRatio: CGFloat = 2.0 / 3.0
}

/// One step of Atten's type scale: size, line height, weight and tracking.
///
/// UI text is the system face. `label` is the one monospaced style — small
/// caps-height metadata, uppercased, with digits that do not jitter as they
/// count — and `reading` is New York, for prose a person reads rather than
/// scans.
enum AttenTextStyle: CaseIterable {
    case display
    case title1
    case title2
    case body
    case callout
    case label
    case reading

    var size: CGFloat {
        switch self {
        case .display: 34
        case .title1: 28
        case .title2: 22
        case .body: 15
        case .callout: 13
        case .label: 11
        case .reading: 18
        }
    }

    var lineHeight: CGFloat {
        switch self {
        case .display: 40
        case .title1: 34
        case .title2: 28
        case .body: 22
        case .callout: 18
        case .label: 14
        case .reading: 29
        }
    }

    var weight: Font.Weight {
        switch self {
        case .display, .title1: .bold
        case .title2: .semibold
        case .body, .reading: .regular
        case .callout, .label: .medium
        }
    }

    /// Letter spacing in ems; multiplied by the size to get points.
    var tracking: CGFloat {
        switch self {
        case .display: -0.022
        case .title1: -0.02
        case .title2: -0.015
        case .body: -0.005
        case .callout, .reading: 0
        case .label: 0.08
        }
    }

    var isUppercased: Bool { self == .label }

    var font: Font {
        switch self {
        case .label: .system(size: size, weight: weight, design: .monospaced).monospacedDigit()
        case .reading: .system(size: size, weight: weight, design: .serif)
        default: .system(size: size, weight: weight)
        }
    }

    /// The same face for AppKit text.
    var nsFont: NSFont {
        switch self {
        case .label: .monospacedSystemFont(ofSize: size, weight: nsWeight)
        case .reading:
            NSFont.systemFont(ofSize: size).fontDescriptor.withDesign(.serif)
                .flatMap { NSFont(descriptor: $0, size: size) } ?? .systemFont(ofSize: size)
        default: .systemFont(ofSize: size, weight: nsWeight)
        }
    }

    /// The leading SwiftUI adds on top of the face's own line height to land
    /// on ``lineHeight``.
    var lineSpacing: CGFloat {
        let face = nsFont
        let natural = face.ascender - face.descender + face.leading
        return max(lineHeight - natural, 0)
    }

    private var nsWeight: NSFont.Weight {
        switch weight {
        case .bold: .bold
        case .semibold: .semibold
        case .medium: .medium
        default: .regular
        }
    }
}

/// Atten's type.
///
/// The fonts of ``AttenTextStyle``, for the places that only take a `Font`.
/// Anything that sets text on its own should use ``SwiftUI/View/attenText(_:)``
/// instead, which also applies the style's tracking, line height and case.
///
/// The names below the scale are what screens were written against. They
/// resolve to the nearest step of the scale until each screen is moved over.
enum AttenTypography {
    static let display = AttenTextStyle.display.font
    static let title1 = AttenTextStyle.title1.font
    static let title2 = AttenTextStyle.title2.font
    static let body = AttenTextStyle.body.font
    static let callout = AttenTextStyle.callout.font
    static let label = AttenTextStyle.label.font
    static let reading = AttenTextStyle.reading.font

    @available(*, deprecated, renamed: "display")
    static let displayTitle = display
    @available(*, deprecated, renamed: "title2")
    static let pageTitle = title2
    /// Body size at the weight a section heading had.
    @available(*, deprecated, message: "Use .attenText(.body) with a weight")
    static let sectionTitle = body.weight(.semibold)
    @available(*, deprecated, renamed: "callout")
    static let control = callout
    @available(*, deprecated, renamed: "callout")
    static let metadata = callout
    @available(*, deprecated, renamed: "callout")
    static let caption = callout
    /// Elapsed and remaining time.
    @available(*, deprecated, renamed: "label")
    static let timecode = label
    /// A number that sits next to the control that changes it — 1.1×, 120%.
    @available(*, deprecated, renamed: "label")
    static let readout = label
}

private struct AttenTextModifier: ViewModifier {
    let style: AttenTextStyle

    func body(content: Content) -> some View {
        content
            .font(style.font)
            .tracking(style.tracking * style.size)
            .lineSpacing(style.lineSpacing)
            .textCase(style.isUppercased ? .uppercase : nil)
    }
}

extension View {
    /// Set text in one step of the scale: its font, tracking, line height,
    /// and — for `label` — upper case and tabular digits.
    func attenText(_ style: AttenTextStyle) -> some View {
        modifier(AttenTextModifier(style: style))
    }
}

struct AttenBackdrop: View {
    var body: some View {
        AttenColor.appBackground
            .overlay { AmbientFieldLayer() }
            .ignoresSafeArea()
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

struct ToolbarIconButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void
    var isEnabled = true

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(AttenTypography.callout)
                .frame(width: 30, height: 30)
        }
        .buttonStyle(AttenTertiaryButtonStyle())
        .disabled(!isEnabled)
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
/// It draws as a button at rest rather than only under the pointer: the one
/// control that gets someone out of a screen should not be the least visible
/// thing on it.
struct AttenBackButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AttenSpacing.xxs) {
                Image(systemName: "chevron.backward")
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: 190)
            .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(AttenSecondaryButtonStyle())
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
                .font(AttenTypography.callout)
                .foregroundStyle(AttenColor.textSecondary)
                .accessibilityHidden(true)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(AttenTypography.callout)
                .focused($isFocused)
                .accessibilityLabel(prompt)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(AttenTypography.callout)
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
                .stroke(isFocused ? AttenColor.focus : .clear, lineWidth: 1)
        }
        .onExitCommand { text = "" }
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
                .font(AttenTypography.title2)
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
                .font(AttenTypography.callout.weight(.semibold))
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
                    .font(AttenTypography.callout.weight(.semibold))
                    .foregroundStyle(AttenColor.textPrimary)
                Text(detail)
                    .font(AttenTypography.callout)
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
                    .font(AttenTypography.callout.monospacedDigit())
                    .foregroundStyle(AttenColor.textSecondary)
                }
            }

            Spacer(minLength: AttenSpacing.xs)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(AttenSecondaryButtonStyle())
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
                Text(title).font(AttenTypography.callout)
                Text(detail)
                    .font(AttenTypography.callout)
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
                        .font(AttenTypography.callout)
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
