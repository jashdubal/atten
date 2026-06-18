import SwiftUI

enum AttenColor {
    static let forest = Color(light: 0x007C91, dark: 0x54E6F1)
    static let moss = Color(light: 0x5B4BC4, dark: 0xB79AFF)
    static let river = Color(light: 0x008DA8, dark: 0x38D7FF)
    static let sunlight = Color(light: 0xE4775E, dark: 0xFFB36B)
    static let berry = Color(light: 0xB00068, dark: 0xFF5CAD)
    static let wildflower = Color(light: 0x7442B8, dark: 0xC39BFF)
    static let parchment = Color(light: 0xF4ECFF, dark: 0x130B26)
    static let wood = Color(light: 0x75509C, dark: 0xA66BD4)
    static let ink = Color(light: 0x24133F, dark: 0xFFF3FF)
    static let secondaryInk = Color(light: 0x675778, dark: 0xCDB9DD)
    static let surface = Color(light: 0xFFF8FF, dark: 0x1A1033)
    static let surfaceRaised = Color(light: 0xF2E8FF, dark: 0x271748)
    static let divider = Color(light: 0xB89BD5, dark: 0x684785)
    static let soil = Color(light: 0xD9C5ED, dark: 0x2B124C)
    static let sky = Color(light: 0xBFEFFF, dark: 0x2A1B58)

    static let meadowGradient = LinearGradient(
        colors: [berry, wildflower, river],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let sunriseGradient = LinearGradient(
        colors: [sunlight, berry, wildflower],
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
    static let xs: CGFloat = 5
    static let sm: CGFloat = 8
    static let md: CGFloat = 13
    static let lg: CGFloat = 18
    static let xl: CGFloat = 22
}

struct AttenCardModifier: ViewModifier {
    var padding: CGFloat = AttenSpacing.md

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(AttenColor.surfaceRaised)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(AttenColor.wildflower.opacity(0.55), lineWidth: 1)
            }
            .shadow(color: AttenColor.berry.opacity(0.10), radius: 12, y: 5)
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
            .frame(minHeight: 36)
            .background(AttenColor.meadowGradient.opacity(isEnabled ? 1 : 0.45))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(.white.opacity(0.22), lineWidth: 1)
            }
            .shadow(
                color: AttenColor.berry.opacity(configuration.isPressed ? 0.08 : 0.30),
                radius: configuration.isPressed ? 2 : 9,
                y: 3
            )
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct ForestBackdrop: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [
                        AttenColor.parchment,
                        AttenColor.sky.opacity(0.62),
                        AttenColor.wildflower.opacity(0.16),
                        AttenColor.parchment,
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                vaporSun
                    .frame(width: 260, height: 260)
                    .position(x: proxy.size.width * 0.76, y: proxy.size.height * 0.28)

                Canvas { context, size in
                    let horizon = size.height * 0.62
                    let gridColor = AttenColor.river.opacity(0.16)

                    for index in 0...10 {
                        let progress = CGFloat(index) / 10
                        let y = horizon + pow(progress, 1.65) * (size.height - horizon)
                        var line = Path()
                        line.move(to: CGPoint(x: 0, y: y))
                        line.addLine(to: CGPoint(x: size.width, y: y))
                        context.stroke(line, with: .color(gridColor), lineWidth: 1)
                    }

                    for index in -7...7 {
                        let destinationX = size.width / 2 + CGFloat(index) * size.width / 7
                        var line = Path()
                        line.move(to: CGPoint(x: size.width / 2, y: horizon))
                        line.addLine(to: CGPoint(x: destinationX, y: size.height))
                        context.stroke(line, with: .color(gridColor), lineWidth: 1)
                    }

                    for index in 0..<24 {
                        let x = CGFloat((index * 83) % 97) / 97 * size.width
                        let y = CGFloat((index * 41) % 53) / 53 * horizon
                        let star = CGRect(x: x, y: y, width: 3, height: 3)
                        context.fill(
                            Path(ellipseIn: star),
                            with: .color(AttenColor.berry.opacity(0.20))
                        )
                    }
                }
            }
        }
        .ignoresSafeArea()
    }

    private var vaporSun: some View {
        ZStack {
            Circle()
                .fill(AttenColor.sunriseGradient)
                .shadow(color: AttenColor.berry.opacity(0.22), radius: 24)
            VStack(spacing: 10) {
                Spacer().frame(height: 132)
                ForEach(0..<6, id: \.self) { index in
                    Rectangle()
                        .fill(AttenColor.parchment.opacity(0.72))
                        .frame(height: CGFloat(index + 1) * 2)
                }
                Spacer(minLength: 0)
            }
            .clipShape(Circle())
        }
        .opacity(0.42)
    }
}

struct AttenLogo: View {
    var compact = false

    var body: some View {
        HStack(spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: compact ? 5 : 7, style: .continuous)
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
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(AttenColor.wildflower.opacity(0.35), lineWidth: 1)
        }
    }
}

struct SectionHeader: View {
    let eyebrow: String
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(eyebrow.uppercased())
                .font(.system(.caption, design: .monospaced, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(AttenColor.forest)
            Text(title)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(AttenColor.ink)
            Text(detail)
                .font(.callout)
                .foregroundStyle(AttenColor.secondaryInk)
        }
    }
}

private struct PixelInputModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(AttenColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(AttenColor.river.opacity(0.52), lineWidth: 1)
            }
            .shadow(color: AttenColor.wildflower.opacity(0.10), radius: 6, y: 2)
    }
}

extension View {
    func pixelInput() -> some View {
        modifier(PixelInputModifier())
    }
}
