import AVFoundation
import SwiftUI

enum AttenColor {
    // Cool terminal palette: crisp cyan and violet over graphite/navy surfaces.
    static let appBackground = Color(light: 0xF3F7FC, dark: 0x080C14)
    static let sidebar = Color(light: 0xE8EFF8, dark: 0x0C121E)
    static let surface = Color(light: 0xFFFFFF, dark: 0x101826)
    static let surfaceElevated = Color(light: 0xF8FBFF, dark: 0x141E2E)
    static let surfaceMuted = Color(light: 0xDDE8F5, dark: 0x1A2940)
    static let separator = Color(light: 0xB7C6D9, dark: 0x273852)

    static let textPrimary = Color(light: 0x101827, dark: 0xE7EEF8)
    static let textSecondary = Color(light: 0x51647B, dark: 0x8FA2BA)
    static let accent = Color(light: 0x007EA7, dark: 0x5DDBFF)
    static let accentHover = Color(light: 0x005F7A, dark: 0x91E8FF)
    static let accentSecondary = Color(light: 0x6848D8, dark: 0xA78BFA)
    static let success = Color(light: 0x177A50, dark: 0x4ADE80)
    static let warning = Color(light: 0xA23E65, dark: 0xF472B6)
    static let destructive = Color(light: 0xB42346, dark: 0xFB7185)
    static let focus = accentHover
    static let onAccent = Color(light: 0xF7FCFF, dark: 0x061018)
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
    static let small: CGFloat = 4
    static let control: CGFloat = 4
    static let card: CGFloat = 6
}

enum AttenMotion {
    static let fast = 0.14
    static let standard = 0.18
}

enum AttenTypography {
    static let pageTitle = Font.system(size: 24, weight: .semibold, design: .monospaced)
    static let sectionTitle = Font.system(size: 14, weight: .semibold, design: .monospaced)
    static let body = Font.system(size: 13, design: .monospaced)
    static let control = Font.system(size: 13, weight: .medium, design: .monospaced)
    static let metadata = Font.system(size: 11, design: .monospaced)
    static let caption = Font.system(size: 11, design: .monospaced)
}

struct AttenBackdrop: View {
    var body: some View {
        AttenColor.appBackground.ignoresSafeArea()
    }
}

struct AttenSurfaceModifier: ViewModifier {
    var padding: CGFloat
    var elevated: Bool

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(elevated ? AttenColor.surfaceElevated : AttenColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: AttenRadius.card))
            .overlay {
                RoundedRectangle(cornerRadius: AttenRadius.card)
                    .stroke(AttenColor.separator, lineWidth: 1)
            }
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        label
            .font(AttenTypography.control.weight(.semibold))
            .foregroundStyle(AttenColor.onAccent.opacity(isEnabled ? 1 : 0.55))
            .padding(.horizontal, AttenSpacing.md)
            .frame(minHeight: 40)
            .background(fillColor.opacity(isEnabled ? 1 : 0.42))
            .clipShape(RoundedRectangle(cornerRadius: AttenRadius.control))
            .scaleEffect(isPressed && !reduceMotion ? 0.99 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: AttenMotion.fast), value: isPressed)
            .onHover { isHovering = $0 }
    }

    private var fillColor: Color {
        if isPressed { return AttenColor.accent.opacity(0.78) }
        return isHovering ? AttenColor.accentHover : AttenColor.accent
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

private struct AttenSecondaryButtonBody: View {
    let label: AnyView
    let isPressed: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
        label
            .font(AttenTypography.control)
            .foregroundStyle(AttenColor.textPrimary.opacity(isEnabled ? 1 : 0.45))
            .padding(.horizontal, AttenSpacing.sm)
            .frame(minHeight: 34)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: AttenRadius.control))
            .overlay {
                RoundedRectangle(cornerRadius: AttenRadius.control)
                    .stroke(isHovering ? AttenColor.accent : AttenColor.separator, lineWidth: 1)
            }
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

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(AttenTypography.control)
                .frame(width: 30, height: 30)
                .foregroundStyle(isHovering ? AttenColor.accentHover : AttenColor.textPrimary)
                .background(isHovering ? AttenColor.surfaceMuted : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: AttenRadius.small))
                .overlay {
                    RoundedRectangle(cornerRadius: AttenRadius.small)
                        .stroke(isHovering ? AttenColor.separator : Color.clear, lineWidth: 1)
                }
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
                RoundedRectangle(cornerRadius: AttenRadius.small)
                    .fill(AttenColor.appBackground)
                    .overlay {
                        RoundedRectangle(cornerRadius: AttenRadius.small)
                            .stroke(AttenColor.accent, lineWidth: 1)
                    }
                Image(systemName: "waveform")
                    .font(.system(size: compact ? 12 : 15, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AttenColor.accent)
            }
            .frame(width: compact ? 28 : 34, height: compact ? 28 : 34)
            .accessibilityHidden(true)

            if !compact {
                Text("ATTEN_")
                    .font(.system(size: 18, weight: .semibold, design: .monospaced))
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
            Text("> \(eyebrow.uppercased())")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(0.8)
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
            Text("> \(title.uppercased())")
                .font(AttenTypography.sectionTitle)
                .foregroundStyle(AttenColor.accent)
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
        .background(AttenColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: AttenRadius.control))
        .overlay {
            RoundedRectangle(cornerRadius: AttenRadius.control)
                .stroke(color, lineWidth: 1)
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
                Text(title.uppercased()).font(AttenTypography.metadata.weight(.semibold))
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

struct AudioFileMetadata: Equatable {
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
