import AttenCore
import SwiftUI

/// Who narrates, drawn the same wherever a narrator is shown: the voice's
/// avatar in its own colour, its name, how it sounds and where it is from.
struct NarratorIdentity: View {
    let profile: VoiceProfile
    let isSpeaking: Bool

    var body: some View {
        HStack(spacing: AttenSpacing.sm) {
            VoiceWaveformAvatar(profile: profile, size: 48, isSpeaking: isSpeaking)
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.displayName)
                    .attenText(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(AttenColor.text1)
                // Traits and accent on lines of their own, so neither
                // wraps into the other in a narrow column.
                if !profile.traits.isEmpty {
                    Text(profile.traits)
                        .attenText(.callout)
                        .foregroundStyle(AttenColor.text2)
                        .lineLimit(1)
                }
                Text(profile.accent)
                    .attenText(.callout)
                    .foregroundStyle(AttenColor.text2)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }
}

/// A book's narrator, as Create shows a draft's: who reads it, a preview of
/// how they sound, and the way to cast someone else.
struct BookNarratorCard: View {
    @Bindable var model: AppModel
    let book: BookRecord
    /// Narrating now: the voice can't change under it.
    let isLocked: Bool
    let change: () -> Void

    var body: some View {
        let voice = VoiceCatalog.voice(id: book.voiceID) ?? VoiceCatalog.defaultVoice
        let profile = VoiceProfile(voice: voice)
        HStack(spacing: AttenSpacing.md) {
            NarratorIdentity(
                profile: profile,
                isSpeaking: model.isPlaying && model.activeAudioURL == model.voicePreviewURL(voice)
            )
            if let required = model.requiredModelID(for: voice.id) {
                Button("Download Voice Model") { model.library.download(required) }
                    .buttonStyle(AttenSecondaryButtonStyle())
                    .disabled(model.library.downloads[required] != nil)
                    .help("Download once; this voice then works offline")
            } else {
                PreviewButton(model: model, flow: nil, voice: voice)
            }
            Button("Change", action: change)
                .buttonStyle(AttenSecondaryButtonStyle())
                .disabled(isLocked)
        }
        .padding(AttenSpacing.md)
        .background(AttenColor.surface1, in: RoundedRectangle(cornerRadius: AttenRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AttenRadius.card, style: .continuous)
                .strokeBorder(AttenColor.hairline, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Narrator: \(profile.displayName)")
    }
}
