import SwiftUI

enum AttenColor {
    static let forest = Color(light: 0x176B52, dark: 0x6ED6A8)
    static let moss = Color(light: 0x6D8E3E, dark: 0xA9D66F)
    static let river = Color(light: 0x2389A5, dark: 0x64CBE3)
    static let sunlight = Color(light: 0xF4B942, dark: 0xFFD36A)
    static let berry = Color(light: 0xB14D75, dark: 0xF08CB5)
    static let wildflower = Color(light: 0x8067C7, dark: 0xB9A4F2)
    static let parchment = Color(light: 0xFFF9EC, dark: 0x28271F)
    static let wood = Color(light: 0x79583D, dark: 0xC6A27E)
    static let ink = Color(light: 0x24322C, dark: 0xEBF2ED)
    static let secondaryInk = Color(light: 0x617068, dark: 0xAAB8B0)
    static let surface = Color(light: 0xFFFFFF, dark: 0x222A26)
    static let surfaceRaised = Color(light: 0xFFFCF4, dark: 0x2C3530)
    static let divider = Color(light: 0xDDE5DD, dark: 0x465149)

    static let meadowGradient = LinearGradient(
        colors: [forest, river, wildflower],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let sunriseGradient = LinearGradient(
        colors: [sunlight, berry],
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
    static let xs: CGFloat = 6
    static let sm: CGFloat = 10
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
}

struct AttenCardModifier: ViewModifier {
    var padding: CGFloat = AttenSpacing.md

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(AttenColor.surfaceRaised)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AttenColor.divider.opacity(0.7), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
    }
}

extension View {
    func attenCard(padding: CGFloat = AttenSpacing.md) -> some View {
        modifier(AttenCardModifier(padding: padding))
    }
}

struct AttenPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(minHeight: 40)
            .background(AttenColor.meadowGradient.opacity(isEnabled ? 1 : 0.45))
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .shadow(color: AttenColor.forest.opacity(configuration.isPressed ? 0.08 : 0.2), radius: 6, y: 3)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct ForestBackdrop: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            AttenColor.parchment
            Circle()
                .fill(AttenColor.river.opacity(0.10))
                .frame(width: 420, height: 420)
                .blur(radius: 4)
                .offset(x: 340, y: -250)
            Circle()
                .fill(AttenColor.sunlight.opacity(0.11))
                .frame(width: 360, height: 360)
                .offset(x: -400, y: 280)
            if !reduceMotion {
                Canvas { context, size in
                    for index in 0..<18 {
                        let x = CGFloat((index * 89) % 100) / 100 * size.width
                        let y = CGFloat((index * 47) % 100) / 100 * size.height
                        let rect = CGRect(x: x, y: y, width: 3, height: 3)
                        context.fill(Path(ellipseIn: rect), with: .color(AttenColor.moss.opacity(0.12)))
                    }
                }
            }
        }
        .ignoresSafeArea()
    }
}

struct AttenLogo: View {
    var compact = false

    var body: some View {
        HStack(spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: compact ? 8 : 11, style: .continuous)
                    .fill(AttenColor.meadowGradient)
                Image(systemName: "leaf.fill")
                    .foregroundStyle(.white)
                    .rotationEffect(.degrees(-18))
                Image(systemName: "waveform")
                    .font(.system(size: compact ? 8 : 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.88))
                    .offset(y: compact ? 7 : 9)
            }
            .frame(width: compact ? 30 : 38, height: compact ? 30 : 38)
            .accessibilityHidden(true)

            if !compact {
                Text("Atten")
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundStyle(AttenColor.ink)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Atten")
    }
}

struct StatusBanner: View {
    enum Kind { case success, error }
    let kind: Kind
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: AttenSpacing.sm) {
            Image(systemName: kind == .success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(kind == .success ? AttenColor.forest : AttenColor.berry)
            Text(message)
                .font(.callout)
                .foregroundStyle(AttenColor.ink)
            Spacer()
            Button(action: dismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(12)
        .background((kind == .success ? AttenColor.forest : AttenColor.berry).opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct SectionHeader: View {
    let eyebrow: String
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(eyebrow.uppercased())
                .font(.caption.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(AttenColor.forest)
            Text(title)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(AttenColor.ink)
            Text(detail)
                .font(.callout)
                .foregroundStyle(AttenColor.secondaryInk)
        }
    }
}
