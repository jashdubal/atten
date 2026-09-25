import AttenCore
import SwiftUI

/// Choosing a narrator: every voice as a card, narrowed by language, gender
/// and tone, each one ready to say the draft's own first sentence.
struct CastingSheet: View {
    @Bindable var model: AppModel
    /// Recasting a book rather than Create's draft: the voice it has now,
    /// and what choosing another does. Previews then say Atten's own line,
    /// since the draft's first sentence belongs to another text.
    var currentVoiceID: String?
    var cast: ((Voice) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var accent: String?
    @State private var gender: String?
    @State private var tone: String?

    private var flow: CreateFlowModel { model.createFlow }

    private var profiles: [VoiceProfile] {
        _ = model.voiceCatalogRevision
        return VoiceCatalog.all.map(VoiceProfile.init(voice:))
    }

    /// A trait written in lowercase is how a voice sounds; a capitalised one
    /// ("British", "Spanish") is where it is from, which language covers.
    private static func tones(of voice: Voice) -> [String] {
        voice.traits.filter { $0.first?.isLowercase == true }
    }

    private var filtered: [Voice] {
        VoiceCatalog.all.filter { voice in
            let profile = VoiceProfile(voice: voice)
            return (accent == nil || profile.accent == accent)
                && (gender == nil || voice.gender == gender)
                && (tone == nil || Self.tones(of: voice).contains(tone!))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Narrator")
                    .attenText(.title2)
                    .foregroundStyle(AttenColor.text1)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(AttenTertiaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
            }
            .padding([.horizontal, .top], AttenSpacing.lg)
            .padding(.bottom, AttenSpacing.md)

            VStack(alignment: .leading, spacing: AttenSpacing.xs) {
                FilterChipRow(title: "Language", options: FilterChipRow.ranked(profiles.map(\.accent)), selection: $accent)
                FilterChipRow(title: "Gender", options: FilterChipRow.ranked(profiles.map(\.gender)), selection: $gender)
                FilterChipRow(title: "Tone", options: FilterChipRow.ranked(VoiceCatalog.all.flatMap(Self.tones(of:))).filter { tone in
                    VoiceCatalog.all.count { Self.tones(of: $0).contains(tone) } > 1
                }, label: { $0.prefix(1).uppercased() + $0.dropFirst() }, selection: $tone)
            }
            .padding(.horizontal, AttenSpacing.lg)
            .padding(.bottom, AttenSpacing.md)

            Rectangle().fill(AttenColor.hairline).frame(height: 1)

            ScrollView {
                if filtered.isEmpty {
                    Text("No voices")
                        .attenText(.callout)
                        .foregroundStyle(AttenColor.text2)
                        .frame(maxWidth: .infinity)
                        .padding(AttenSpacing.xxl)
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 210), spacing: AttenSpacing.sm)],
                        spacing: AttenSpacing.sm
                    ) {
                        ForEach(filtered) { voice in
                            CastingCard(
                                model: model,
                                voice: voice,
                                isSelected: voice.id == (currentVoiceID ?? flow.voice.id),
                                previewFlow: cast == nil ? flow : nil
                            ) {
                                (cast ?? flow.cast)(voice)
                                dismiss()
                            }
                        }
                    }
                    .padding(AttenSpacing.lg)
                    .attenScrollPadding()
                }
            }
        }
        .frame(width: 780, height: 640)
        .background(AttenColor.bg)
    }
}

private struct CastingCard: View {
    @Bindable var model: AppModel
    let voice: Voice
    let isSelected: Bool
    let previewFlow: CreateFlowModel?
    let choose: () -> Void
    @State private var isHovering = false

    var body: some View {
        let profile = VoiceProfile(voice: voice)
        let shape = RoundedRectangle(cornerRadius: AttenRadius.card, style: .continuous)
        let isPlaying = model.isPlaying && model.activeAudioURL == (previewFlow.map { $0.previewURL(for: voice) } ?? model.voicePreviewURL(voice))
        Button(action: choose) {
            VStack(alignment: .leading, spacing: AttenSpacing.sm) {
                HStack(alignment: .top) {
                    VoiceWaveformAvatar(profile: profile, size: 40, isSpeaking: isPlaying)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AttenColor.text1)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.displayName)
                        .attenText(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(AttenColor.text1)
                    Text(profile.descriptor)
                        .attenText(.callout)
                        .foregroundStyle(AttenColor.text2)
                        .lineLimit(2, reservesSpace: true)
                }
                Text(model.requiredModelID(for: voice.id) == nil ? profile.gender : "\(profile.gender) · Needs model")
                    .attenText(.label)
                    .foregroundStyle(AttenColor.text3)
            }
            .padding(AttenSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AttenColor.surface1, in: shape)
            .overlay { shape.fill(AttenColor.text1.opacity(isHovering ? AttenState.hoverFill / 2 : 0)) }
            .overlay {
                shape.strokeBorder(isSelected ? AttenColor.text1 : AttenColor.hairline, lineWidth: isSelected ? 1.5 : 1)
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .attenFocusRing(cornerRadius: AttenRadius.card)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: AttenMotion.hover), value: isHovering)
        .overlay(alignment: .bottomTrailing) {
            PreviewButton(model: model, flow: previewFlow, voice: voice, showsTitle: false)
                .padding(AttenSpacing.sm)
        }
        .accessibilityLabel("\(profile.displayName), \(profile.descriptor)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
