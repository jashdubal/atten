import AttenCore
import SwiftUI

struct PlaygroundView: View {
    @Bindable var model: AppModel
    let openStudio: () -> Void

    @State private var sampleText = "The creek is bright this morning, and the meadow is ready for a new story."
    @State private var voiceID = "af_heart"
    @State private var speed = 1.0
    @State private var format = AudioFormat.wav
    @State private var useMPS = true

    private var voice: Voice {
        VoiceCatalog.voice(id: voiceID) ?? VoiceCatalog.all[0]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AttenSpacing.lg) {
                SectionHeader(
                    eyebrow: "Playground",
                    title: "Try a voice before planting it",
                    detail: "Experiment freely. Samples are temporary and never added to Projects."
                )

                if case let .failed(message) = model.playgroundState {
                    StatusBanner(kind: .error, message: message) {
                        model.playgroundState = .idle
                    }
                }

                HStack(alignment: .top, spacing: AttenSpacing.lg) {
                    sampleCard
                        .frame(minWidth: 420, maxWidth: .infinity)
                    settingsCard
                        .frame(width: 286)
                }

                if let audioURL = model.playgroundAudioURL {
                    temporaryPlayback(url: audioURL)
                }
            }
            .padding(AttenSpacing.xl)
            .frame(maxWidth: 1040, alignment: .topLeading)
        }
    }

    private var sampleCard: some View {
        VStack(alignment: .leading, spacing: AttenSpacing.md) {
            HStack {
                Label("Sample text", systemImage: "text.bubble")
                    .font(.headline)
                Spacer()
                Text("\(sampleText.count)/500")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(sampleText.count > 500 ? AttenColor.berry : AttenColor.secondaryInk)
            }

            ZStack(alignment: .topLeading) {
                AlignedTextEditor(text: $sampleText, accessibilityLabel: "Playground sample text")
                    .frame(minHeight: 230)
                if sampleText.isEmpty {
                    Text("Write a short line to audition…")
                        .foregroundStyle(AttenColor.secondaryInk)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 13)
                        .allowsHitTesting(false)
                }
            }
            .pixelInput()

            Text("Short samples make comparing voices faster.")
                .font(.caption)
                .foregroundStyle(AttenColor.secondaryInk)
        }
        .attenCard(padding: AttenSpacing.lg)
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: AttenSpacing.md) {
            Label("Sample settings", systemImage: "slider.horizontal.3")
                .font(.headline)

            Picker("Voice", selection: $voiceID) {
                ForEach(Dictionary(grouping: VoiceCatalog.all, by: \.language).keys.sorted(), id: \.self) { language in
                    Section(language) {
                        ForEach(VoiceCatalog.all.filter { $0.language == language }) { voice in
                            Text("\(voice.name) · \(voice.gender)").tag(voice.id)
                        }
                    }
                }
            }

            HStack(spacing: AttenSpacing.sm) {
                VoiceAvatar(voice: voice, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(voice.name).font(.subheadline.weight(.semibold))
                    Text(voice.language).font(.caption).foregroundStyle(.secondary)
                }
            }

            Divider()

            HStack {
                Text("Speed")
                Spacer()
                Text(String(format: "%.2f×", speed))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(AttenColor.forest)
            }
            Slider(value: $speed, in: 0.5...2, step: 0.05)

            Picker("Format", selection: $format) {
                ForEach(AudioFormat.allCases) { format in
                    Text(format.displayName).tag(format)
                }
            }
            .pickerStyle(.segmented)

            Toggle("Metal fallback", isOn: $useMPS)
                .help("Use PyTorch Metal fallback when supported")

            Divider()

            if model.isPlaygroundGenerating {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Growing sample…").font(.callout)
                    Spacer()
                    Button("Cancel") { model.cancelGeneration() }
                }
            } else {
                Button {
                    model.generatePlaygroundSample(
                        text: String(sampleText.prefix(500)),
                        voiceID: voiceID,
                        speed: speed,
                        format: format,
                        useMPS: useMPS
                    )
                } label: {
                    Label("Create Temporary Sample", systemImage: "flask.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(AttenPrimaryButtonStyle())
                .keyboardShortcut(.return, modifiers: [.command, .option])
                .disabled(sampleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sampleText.count > 500)
            }
        }
        .attenCard(padding: AttenSpacing.lg)
    }

    private func temporaryPlayback(url: URL) -> some View {
        HStack(spacing: AttenSpacing.md) {
            Button { model.togglePlayback(url: url) } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(AttenColor.sunriseGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.isPlaying ? "Pause temporary sample" : "Play temporary sample")

            VStack(alignment: .leading, spacing: 2) {
                Text("Temporary \(voice.name) sample")
                    .font(.headline)
                Text("Not saved to Projects • deleted when cleared or replaced")
                    .font(.caption)
                    .foregroundStyle(AttenColor.secondaryInk)
            }
            Spacer()
            Button("Clear", systemImage: "trash") { model.clearPlaygroundSample() }
            Button("Use in Studio", systemImage: "arrow.right") {
                model.usePlaygroundSettingsInStudio(
                    text: sampleText,
                    voiceID: voiceID,
                    speed: speed,
                    format: format
                )
                openStudio()
            }
            .buttonStyle(.borderedProminent)
            .tint(AttenColor.forest)
        }
        .attenCard()
    }
}
