import AttenCore
import SwiftUI

/// A voice's face: a few bars of a waveform, drawn from its id so the same
/// voice always looks the same, in the voice's own hue. While the voice is
/// speaking the bars move.
struct VoiceWaveformAvatar: View {
    let profile: VoiceProfile
    var size: CGFloat = 44
    var isSpeaking = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var heights: [Double] {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in profile.voiceID.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return (0..<7).map { index -> Double in
            let byte = Double((hash >> UInt64(index * 8)) & 0xff)
            return 0.28 + 0.72 * byte / 255
        }
    }

    var body: some View {
        let colour = AttenColor.voice(hue: profile.hue)
        let shape = RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
        TimelineView(.animation(paused: !isSpeaking || reduceMotion)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate * 6
            HStack(spacing: size * 0.05) {
                ForEach(Array(heights.enumerated()), id: \.offset) { index, height in
                    let moving = isSpeaking && !reduceMotion ? 0.55 + 0.45 * abs(sin(phase + Double(index) * 0.9)) : 1
                    Capsule()
                        .fill(colour)
                        .frame(width: size * 0.07, height: size * 0.62)
                        .scaleEffect(y: height * moving, anchor: .center)
                }
            }
        }
        .frame(width: size, height: size)
        .background(colour.opacity(0.14), in: shape)
        .overlay { shape.strokeBorder(colour.opacity(0.28), lineWidth: 1) }
        .accessibilityHidden(true)
    }
}

/// Narration's progress as a waveform filling left to right in `signal`.
/// The fill is a mask that scales, so only a transform animates.
struct GenerationWaveform: View {
    let fraction: Double
    var seed: String = ""

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let barCount = 48

    private var heights: [Double] {
        var state: UInt64 = 0x9e37_79b9_7f4a_7c15
        for byte in seed.utf8 { state = (state ^ UInt64(byte)) &* 0x0000_0100_0000_01b3 }
        return (0..<Self.barCount).map { index in
            state = state &+ 0x9e37_79b9_7f4a_7c15
            var mixed = state
            mixed = (mixed ^ (mixed >> 30)) &* 0xbf58_476d_1ce4_e5b9
            mixed = (mixed ^ (mixed >> 27)) &* 0x94d0_49bb_1331_11eb
            let random = Double((mixed ^ (mixed >> 31)) % 1000) / 1000
            // A gentle swell across the width, so it reads as speech.
            let envelope = 0.45 + 0.55 * sin(Double(index) / Double(Self.barCount - 1) * .pi)
            return max(0.12, envelope * (0.35 + 0.65 * random))
        }
    }

    var body: some View {
        let bars = HStack(alignment: .center, spacing: 2) {
            ForEach(Array(heights.enumerated()), id: \.offset) { _, height in
                Capsule()
                    .frame(maxWidth: .infinity)
                    .scaleEffect(y: height, anchor: .center)
            }
        }
        ZStack {
            bars.foregroundStyle(AttenColor.text3.opacity(0.35))
            bars.foregroundStyle(AttenColor.signal)
                .mask(alignment: .leading) {
                    Rectangle()
                        .scaleEffect(x: min(1, max(0, fraction)), anchor: .leading)
                }
        }
        .frame(height: 36)
        .animation(AttenMotion.animation(.small, reduceMotion: reduceMotion), value: fraction)
        .accessibilityElement()
        .accessibilityLabel("Narration progress")
        .accessibilityValue("\(Int(fraction * 100)) percent")
    }
}

/// The cover anything in the Library with no art of its own is given: soft
/// colour fields seeded from its text, and its title set in the reading
/// face. Create's finished stage draws one at full colour; the Library draws
/// the same view desaturated for a silent draft, rising back to full colour
/// as narration completes, with a small waveform glyph while it plays — the
/// two have to agree, since a freshly finished book's cover flies from one
/// into its slot in the other via `attenMatchedCover`.
struct GeneratedCover: View {
    let title: String
    let contentHash: String
    var sourceLabel: String?
    var state: AttenCore.LibraryItemState = .voiced
    var isPlaying = false
    /// Off for a thumbnail too small to print the title legibly.
    var showsTitle = true

    /// How far the cover has risen out of silence: 0 while silent, 1 once
    /// voiced, and whatever `.generating` reports in between.
    private var colorProgress: Double {
        switch state {
        case .silent: 0
        case .generating(let progress): max(0, min(1, progress))
        case .voiced: 1
        }
    }

    var body: some View {
        let seed = CoverSeed(contentHash: contentHash)
        GeometryReader { geometry in
            let size = geometry.size
            ZStack(alignment: .bottomLeading) {
                AttenColor.cover(OKLCHColor(lightness: 0.3, chroma: 0.05, hue: seed.hue))
                ForEach(Array(seed.blobs.enumerated()), id: \.offset) { _, blob in
                    Circle()
                        .fill(AttenColor.cover(blob.color))
                        .frame(width: size.width * blob.radius * 2, height: size.width * blob.radius * 2)
                        .position(x: size.width * blob.x, y: size.height * blob.y)
                        .opacity(0.75)
                        .blur(radius: size.width * 0.12)
                }
                if showsTitle {
                    VStack(alignment: .leading, spacing: size.width * 0.02) {
                        Text(title)
                            .font(.system(size: max(12, size.width * 0.1), weight: .regular, design: .serif))
                            .foregroundStyle(AttenColor.cover(OKLCHColor(lightness: 0.97, chroma: 0.01, hue: seed.hue)))
                            .lineLimit(4)
                        if let sourceLabel {
                            Text(sourceLabel.uppercased())
                                .attenText(.label)
                                .foregroundStyle(AttenColor.cover(OKLCHColor(lightness: 0.97, chroma: 0.01, hue: seed.hue)).opacity(0.72))
                                .lineLimit(1)
                        }
                    }
                    .padding(size.width * 0.09)
                }
            }
        }
        .aspectRatio(AttenMetrics.coverAspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: AttenRadius.cover, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if isPlaying { PlayingGlyph().padding(8) }
        }
        // 0.35/-0.2 at rest for silent work, full colour once voiced; a
        // generation in progress eases between the two as it completes.
        .saturation(0.35 + 0.65 * colorProgress)
        .brightness(-0.2 + 0.2 * colorProgress)
        .accessibilityHidden(true)
    }
}

// MARK: - The cover's flight to the Library

private struct CoverNamespaceKey: EnvironmentKey {
    static var defaultValue: Namespace.ID? { nil }
}

extension EnvironmentValues {
    /// Shared by Create's finished cover and the Library's jackets, so a new
    /// audiobook's cover travels into its slot on the shelf.
    var attenCoverNamespace: Namespace.ID? {
        get { self[CoverNamespaceKey.self] }
        set { self[CoverNamespaceKey.self] = newValue }
    }
}

private struct MatchedCover: ViewModifier {
    let id: UUID
    @Environment(\.attenCoverNamespace) private var namespace

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedGeometryEffect(id: id, in: namespace)
        } else {
            content
        }
    }
}

extension View {
    func attenMatchedCover(_ id: UUID) -> some View {
        modifier(MatchedCover(id: id))
    }
}

// MARK: - Added to Library

/// Floats over whatever screen the finished narration lands on.
struct CreateToast: View {
    @Bindable var flow: CreateFlowModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if flow.toastBookID != nil {
                HStack(spacing: AttenSpacing.md) {
                    Label("Added to Library", systemImage: "checkmark")
                        .attenText(.callout)
                        .foregroundStyle(AttenColor.text1)
                    Button("Undo", action: flow.undoNarration)
                        .buttonStyle(AttenTertiaryButtonStyle())
                }
                .padding(.horizontal, AttenSpacing.md)
                .frame(height: 40)
                .attenGlass(cornerRadius: 20)
                .transition(
                    reduceMotion
                        ? .opacity
                        : .opacity.combined(with: .scale(scale: 0.96)).combined(with: .offset(y: -8))
                )
                .accessibilityElement(children: .contain)
            }
        }
        .animation(AttenMotion.animation(.small, reduceMotion: reduceMotion), value: flow.toastBookID)
    }
}
