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
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: AttenSpacing.lg) {
                    header

                    if case let .failed(message) = model.playgroundState {
                        StatusBanner(kind: .error, message: message) {
                            model.playgroundState = .idle
                        }
                    }

                    workspace(width: proxy.size.width, height: proxy.size.height)

                    if let audioURL = model.playgroundAudioURL {
                        temporaryPlayback(url: audioURL)
                    }
                }
                .padding(.horizontal, proxy.size.width < 700 ? AttenSpacing.lg : AttenSpacing.xl)
                .padding(.vertical, AttenSpacing.lg)
                .frame(maxWidth: 1180, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: AttenSpacing.md) {
            PageHeader(
                eyebrow: "Playground",
                title: "Audition a voice",
                detail: "Try a short sample without adding it to Projects."
            )
            Spacer()
            Label("Temporary", systemImage: "clock")
                .font(AttenTypography.metadata.weight(.medium))
                .foregroundStyle(AttenColor.accentSecondary)
                .padding(.horizontal, AttenSpacing.xs)
                .padding(.vertical, AttenSpacing.xxs)
                .background(AttenColor.accentSecondary.opacity(0.10))
                .clipShape(Capsule())
        }
    }

    @ViewBuilder private func workspace(width: CGFloat, height: CGFloat) -> some View {
        let workspaceHeight = max(410, height - 205)
        if width >= 760 {
            HSplitView {
                sampleEditor
                    .frame(minWidth: 440, maxWidth: .infinity, minHeight: workspaceHeight)
                sampleInspector
                    .frame(minWidth: 280, idealWidth: 304, maxWidth: 340, minHeight: workspaceHeight)
            }
            .frame(minHeight: workspaceHeight)
        } else {
            VStack(alignment: .leading, spacing: AttenSpacing.md) {
                sampleEditor.frame(minHeight: max(330, height - 330))
                sampleInspector
            }
        }
    }

    private var sampleEditor: some View {
        VStack(alignment: .leading, spacing: AttenSpacing.sm) {
            HStack {
                Label("Sample text", systemImage: "text.bubble")
                    .font(AttenTypography.sectionTitle)
                Spacer()
                Text("\(sampleText.count)/500")
                    .font(AttenTypography.metadata.monospacedDigit())
                    .foregroundStyle(
                        sampleText.count > 500 ? AttenColor.destructive : AttenColor.textSecondary
                    )
            }

            ZStack(alignment: .topLeading) {
                AlignedTextEditor(text: $sampleText, accessibilityLabel: "Playground sample text")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if sampleText.isEmpty {
                    Text("Write a short line to audition…")
                        .foregroundStyle(AttenColor.textSecondary)
                        .padding(AttenSpacing.sm)
                        .allowsHitTesting(false)
                }
            }
            .frame(minHeight: 280)
            .attenInput()

            HStack {
                Text("Short samples make voice comparisons faster.")
                    .font(AttenTypography.caption)
                    .foregroundStyle(AttenColor.textSecondary)
                Spacer()
                if !sampleText.isEmpty {
                    Button("Clear text") { sampleText = "" }
                        .buttonStyle(.plain)
                        .foregroundStyle(AttenColor.textSecondary)
                }
            }
        }
        .padding(.trailing, AttenSpacing.md)
    }

    private var sampleInspector: some View {
        VStack(alignment: .leading, spacing: AttenSpacing.lg) {
            InspectorSection(title: "Sample settings") {
                Picker("Voice", selection: $voiceID) {
                    ForEach(groupedLanguages, id: \.self) { language in
                        Section(language) {
                            ForEach(VoiceCatalog.all.filter { $0.language == language }) { voice in
                                Text("\(voice.name) · \(voice.gender)").tag(voice.id)
                            }
                        }
                    }
                }

                HStack(spacing: AttenSpacing.xs) {
                    VoiceAvatar(voice: voice, size: 36)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(voice.name).font(.system(size: 13, weight: .semibold))
                        Text("\(voice.language) · \(voice.gender)")
                            .font(AttenTypography.caption)
                            .foregroundStyle(AttenColor.textSecondary)
                    }
                }
            }

            Divider().overlay(AttenColor.separator)

            VStack(alignment: .leading, spacing: AttenSpacing.md) {
                VStack(alignment: .leading, spacing: AttenSpacing.xs) {
                    HStack {
                        Text("Speed")
                        Spacer()
                        Text(String(format: "%.2f×", speed))
                            .monospacedDigit()
                            .foregroundStyle(AttenColor.accent)
                    }
                    Slider(value: $speed, in: 0.5...2, step: 0.05)
                }

                Picker("Format", selection: $format) {
                    ForEach(AudioFormat.allCases) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .pickerStyle(.segmented)

                Toggle("Metal acceleration fallback", isOn: $useMPS)
                    .font(AttenTypography.body)
            }

            Spacer(minLength: 0)

            if model.isPlaygroundGenerating {
                VStack(spacing: AttenSpacing.xs) {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Creating sample…")
                        Spacer()
                    }
                    .font(AttenTypography.body)
                    .foregroundStyle(AttenColor.textSecondary)
                    Button("Cancel", role: .cancel) { model.cancelGeneration() }
                        .buttonStyle(AttenSecondaryButtonStyle())
                        .frame(maxWidth: .infinity)
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
                    Label("Create Sample", systemImage: "flask.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(AttenPrimaryButtonStyle())
                .keyboardShortcut(.return, modifiers: [.command, .option])
                .disabled(
                    sampleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || sampleText.count > 500
                )
            }
        }
        .attenSurface(padding: AttenSpacing.md, elevated: true)
    }

    private func temporaryPlayback(url: URL) -> some View {
        HStack(spacing: AttenSpacing.sm) {
            Button { model.togglePlayback(url: url) } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .foregroundStyle(Color(light: 0xFFFFFF, dark: 0x17111D))
                    .frame(width: 36, height: 36)
                    .background(AttenColor.accent)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.isPlaying ? "Pause temporary sample" : "Play temporary sample")

            VStack(alignment: .leading, spacing: 2) {
                Text("\(voice.name) sample").font(.system(size: 13, weight: .semibold))
                Text("Temporary · replaced by the next sample")
                    .font(AttenTypography.caption)
                    .foregroundStyle(AttenColor.textSecondary)
            }
            Spacer()
            Button("Clear") { model.clearPlaygroundSample() }
                .buttonStyle(.bordered)
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
            .tint(AttenColor.accent)
        }
        .attenSurface(padding: AttenSpacing.sm)
    }

    private var groupedLanguages: [String] {
        Array(Set(VoiceCatalog.all.map(\.language))).sorted()
    }
}
