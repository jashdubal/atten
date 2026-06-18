import SwiftUI

enum AttenColor {
    // Semantic application layers
    static let appBackground = Color(light: 0xF2ECEF, dark: 0x17111D)
    static let sidebar = Color(light: 0xEAE2E8, dark: 0x130F19)
    static let surface = Color(light: 0xF9F5F3, dark: 0x211827)
    static let surfaceElevated = Color(light: 0xFFFFFF, dark: 0x2B2031)
    static let surfaceMuted = Color(light: 0xEEE6ED, dark: 0x2F2436)
    static let separator = Color(light: 0xD7CAD4, dark: 0x43364A)

    // Semantic content and actions
    static let textPrimary = Color(light: 0x291F2C, dark: 0xF2E9E4)
    static let textSecondary = Color(light: 0x716475, dark: 0xB9AABD)
    static let accent = Color(light: 0x317C82, dark: 0x87C9CC)
    static let accentSecondary = Color(light: 0x9F5F78, dark: 0xC68FA6)
    static let success = Color(light: 0x3B7F5B, dark: 0x7EB89A)
    static let warning = Color(light: 0x966A2B, dark: 0xD5AE78)
    static let destructive = Color(light: 0xAA3E4B, dark: 0xD9828F)
    static let focus = Color(light: 0x246D73, dark: 0xA0DADD)

    // Compatibility names used while feature views migrate to semantic tokens.
    static let forest = accent
    static let moss = accentSecondary
    static let river = accent
    static let sunlight = warning
    static let berry = destructive
    static let wildflower = accentSecondary
    static let parchment = appBackground
    static let wood = textSecondary
    static let ink = textPrimary
    static let secondaryInk = textSecondary
    static let surfaceRaised = surfaceElevated
    static let divider = separator
    static let soil = sidebar
    static let sky = surfaceMuted

    static let meadowGradient = LinearGradient(
        colors: [accentSecondary, accent],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let sunriseGradient = LinearGradient(
        colors: [accentSecondary, warning],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

extension Color {
    init(light: UInt, dark: UInt) {
        self.init(
            nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                return NSColor(hex: isDark ? dark : light)
            }
        )
    }
}

extension NSColor {
    convenience init(hex: UInt) {
        self.init(
            calibratedRed: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: 1
        )
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
}

enum AttenRadius {
    static let small: CGFloat = 6
    static let control: CGFloat = 8
    static let card: CGFloat = 12
}

enum AttenMotion {
    static let fast = 0.14
    static let standard = 0.18
}

enum AttenTypography {
    static let pageTitle = Font.system(size: 28, weight: .semibold)
    static let sectionTitle = Font.system(size: 17, weight: .semibold)
    static let body = Font.system(size: 13)
    static let metadata = Font.system(size: 12)
    static let caption = Font.system(size: 11)
}

struct AttenBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            AttenColor.appBackground
            if !reduceTransparency {
                RadialGradient(
                    colors: [AttenColor.accentSecondary.opacity(0.10), .clear],
                    center: UnitPoint(x: 0.88, y: 0.04),
                    startRadius: 12,
                    endRadius: 560
                )
            }
        }
        .ignoresSafeArea()
    }
}

// Kept as a compatibility wrapper for feature views migrated in later commits.
typealias ForestBackdrop = AttenBackdrop

struct AttenSurfaceModifier: ViewModifier {
    var padding: CGFloat
    var elevated: Bool

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(elevated ? AttenColor.surfaceElevated : AttenColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: AttenRadius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AttenRadius.card, style: .continuous)
                    .stroke(AttenColor.separator.opacity(0.72), lineWidth: 1)
            }
            .shadow(
                color: Color.black.opacity(elevated ? 0.12 : 0.06),
                radius: elevated ? 8 : 3,
                y: elevated ? 3 : 1
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

    func attenCard(padding: CGFloat = AttenSpacing.md) -> some View {
        attenSurface(padding: padding)
    }
}

struct AttenPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color(light: 0xFFFFFF, dark: 0x17111D))
            .padding(.horizontal, AttenSpacing.md)
            .frame(minHeight: 40)
            .background(
                AttenColor.accent.opacity(
                    isEnabled ? (configuration.isPressed ? 0.76 : 1) : 0.36
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: AttenRadius.control, style: .continuous))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(
                reduceMotion ? nil : .easeOut(duration: AttenMotion.fast),
                value: configuration.isPressed
            )
    }
}

struct AttenSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(AttenColor.textPrimary.opacity(isEnabled ? 1 : 0.45))
            .padding(.horizontal, AttenSpacing.sm)
            .frame(minHeight: 34)
            .background(
                AttenColor.surfaceMuted.opacity(configuration.isPressed ? 0.70 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: AttenRadius.control, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AttenRadius.control, style: .continuous)
                    .stroke(AttenColor.separator, lineWidth: 1)
            }
    }
}

struct ToolbarIconButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void
    var isEnabled = true

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 30, height: 30)
                .background(isHovering ? AttenColor.surfaceMuted : .clear)
                .clipShape(RoundedRectangle(cornerRadius: AttenRadius.small))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.42)
        .onHover { isHovering = $0 }
        .help(title)
        .accessibilityLabel(title)
    }
}

struct AttenLogo: View {
    var compact = false

    var body: some View {
        HStack(spacing: AttenSpacing.xs) {
            ZStack {
                RoundedRectangle(cornerRadius: compact ? 6 : 8, style: .continuous)
                    .fill(AttenColor.accentSecondary)
                Image(systemName: "waveform")
                    .font(.system(size: compact ? 12 : 15, weight: .semibold))
                    .foregroundStyle(AttenColor.appBackground)
            }
            .frame(width: compact ? 28 : 34, height: compact ? 28 : 34)
            .accessibilityHidden(true)

            if !compact {
                Text("Atten")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(AttenColor.textPrimary)
            }
        }
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
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(1.1)
                .foregroundStyle(AttenColor.accentSecondary)
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

typealias SectionHeader = PageHeader

struct InspectorSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AttenSpacing.sm) {
            Text(title)
                .font(AttenTypography.sectionTitle)
                .foregroundStyle(AttenColor.textPrimary)
            content
        }
    }
}

struct StatusBanner: View {
    enum Kind { case success, warning, error }

    let kind: Kind
    let message: String
    let dismiss: () -> Void

    private var color: Color {
        switch kind {
        case .success: AttenColor.success
        case .warning: AttenColor.warning
        case .error: AttenColor.destructive
        }
    }

    private var icon: String {
        switch kind {
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.circle.fill"
        case .error: "exclamationmark.triangle.fill"
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
        .background(color.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: AttenRadius.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AttenRadius.control, style: .continuous)
                .stroke(color.opacity(0.28), lineWidth: 1)
        }
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
                Text(title).font(AttenTypography.metadata.weight(.semibold))
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
            .clipShape(RoundedRectangle(cornerRadius: AttenRadius.control, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AttenRadius.control, style: .continuous)
                    .stroke(AttenColor.separator, lineWidth: 1)
            }
    }
}

extension View {
    func attenInput() -> some View { modifier(AttenInputModifier()) }
    func pixelInput() -> some View { attenInput() }
}
