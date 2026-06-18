import AttenCore
import SwiftUI
import UniformTypeIdentifiers

struct StudioView: View {
    @Bindable var model: AppModel
    @State private var showsAdvanced = false
    @State private var isDropTargeted = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AttenSpacing.lg) {
                SectionHeader(
                    eyebrow: "Studio",
                    title: "Give your words a voice",
                    detail: "Write or import text, choose a voice, and create audio locally on your Mac."
                )

                statusArea

                HStack(alignment: .top, spacing: AttenSpacing.lg) {
                    editorCard
                        .frame(minWidth: 420, maxWidth: .infinity)
                    controlsCard
                        .frame(width: 286)
                }

                if model.isGenerating {
                    generationProgress
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if let audioURL = model.currentAudioURL {
                    PlaybackCard(model: model, url: audioURL)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .padding(AttenSpacing.xl)
            .frame(maxWidth: 1040, alignment: .topLeading)
        }
        .animation(.easeInOut(duration: 0.2), value: model.isGenerating)
        .onChange(of: model.selectedVoiceID) { _, _ in model.applySettings() }
        .onChange(of: model.speed) { _, _ in model.applySettings() }
        .onChange(of: model.format) { _, _ in model.applySettings() }
    }

    @ViewBuilder private var statusArea: some View {
        if let success = model.successMessage {
            StatusBanner(kind: .success, message: success, dismiss: model.dismissStatus)
        }
        if case let .failed(message) = model.generationState {
            StatusBanner(kind: .error, message: message, dismiss: model.dismissStatus)
        }
    }

    private var editorCard: some View {
        VStack(alignment: .leading, spacing: AttenSpacing.md) {
            HStack {
                Label("Script", systemImage: "text.alignleft")
                    .font(.headline)
                    .foregroundStyle(AttenColor.ink)
                Spacer()
                Button("Import…", systemImage: "doc.badge.plus") {
                    model.openImportPanel()
                }
                .buttonStyle(.borderless)
                .keyboardShortcut("o")
                .help("Import a UTF-8 text, Markdown, source, or RTF file")
            }

            TextField("Project title", text: $model.draftTitle)
                .textFieldStyle(.plain)
                .font(.title3.weight(.semibold))
                .padding(.horizontal, 11)
                .frame(height: 34)
                .pixelInput()
                .accessibilityLabel("Project title")

            ZStack(alignment: .topLeading) {
                AlignedTextEditor(text: $model.draftText, accessibilityLabel: "Speech text")
                    .frame(minHeight: 260)
                    .accessibilityLabel("Speech text")
                    .accessibilityHint("Enter the text Atten should speak")

                if model.draftText.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Start writing here…")
                            .foregroundStyle(AttenColor.secondaryInk)
                        Text("You can also drop a text file into this editor.")
                            .font(.caption)
                            .foregroundStyle(AttenColor.secondaryInk.opacity(0.8))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)
                    .allowsHitTesting(false)
                }
            }
            .pixelInput()
            .overlay {
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(AttenColor.river, style: StrokeStyle(lineWidth: 2, dash: [6]))
                }
            }
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first else { return false }
                model.importText(from: url)
                return true
            } isTargeted: { isDropTargeted = $0 }

            HStack {
                Text("\(wordCount) words • \(model.draftText.count) characters")
                    .font(.caption)
                    .foregroundStyle(AttenColor.secondaryInk)
                Spacer()
                if model.draftText.isEmpty {
                    Label("Drop text files here", systemImage: "arrow.down.doc")
                        .font(.caption)
                        .foregroundStyle(AttenColor.river)
                }
            }
        }
        .attenCard(padding: AttenSpacing.lg)
    }

    private var controlsCard: some View {
        VStack(alignment: .leading, spacing: AttenSpacing.lg) {
            VStack(alignment: .leading, spacing: AttenSpacing.sm) {
                Text("Voice")
                    .font(.headline)
                Picker("Voice", selection: $model.selectedVoiceID) {
                    ForEach(Dictionary(grouping: VoiceCatalog.all, by: \.language).keys.sorted(), id: \.self) { language in
                        Section(language) {
                            ForEach(VoiceCatalog.all.filter { $0.language == language }) { voice in
                                Text("\(voice.name) · \(voice.gender)").tag(voice.id)
                            }
                        }
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)

                HStack(spacing: 9) {
                    VoiceAvatar(voice: model.selectedVoice, size: 42)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.selectedVoice.name).font(.subheadline.weight(.semibold))
                        Text("\(model.selectedVoice.language) • \(model.selectedVoice.provider)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        model.previewVoice(model.selectedVoice)
                    } label: {
                        if model.voicePreviewID == model.selectedVoice.id {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "play.fill")
                        }
                    }
                    .buttonStyle(.borderless)
                    .help("Preview \(model.selectedVoice.name)")
                    .accessibilityLabel("Preview \(model.selectedVoice.name)")
                }
                .padding(10)
                .background(AttenColor.forest.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }

            DisclosureGroup("Voice settings", isExpanded: $showsAdvanced) {
                VStack(alignment: .leading, spacing: AttenSpacing.md) {
                    HStack {
                        Text("Speed")
                        Spacer()
                        Text(String(format: "%.2f×", model.speed))
                            .monospacedDigit()
                            .foregroundStyle(AttenColor.forest)
                    }
                    Slider(value: $model.speed, in: 0.5...2, step: 0.05) {
                        Text("Speech speed")
                    } minimumValueLabel: {
                        Text("0.5×").font(.caption2)
                    } maximumValueLabel: {
                        Text("2×").font(.caption2)
                    }

                    Picker("Format", selection: $model.format) {
                        ForEach(AudioFormat.allCases) { format in
                            Text(format.displayName).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityHint("Choose MP3 for smaller files or WAV for uncompressed audio")
                }
                .padding(.top, AttenSpacing.sm)
            }

            Divider()

            if model.isGenerating {
                Button("Cancel", role: .cancel) { model.cancelGeneration() }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                    .keyboardShortcut(.escape, modifiers: [])
            } else {
                Button {
                    model.generate()
                } label: {
                    Label("Generate Speech", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(AttenPrimaryButtonStyle())
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(model.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityHint("Generates speech locally with the selected Kokoro voice")
            }

            Text("Generation stays on this Mac. First use may download the Kokoro model.")
                .font(.caption)
                .foregroundStyle(AttenColor.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .attenCard(padding: AttenSpacing.lg)
    }

    private var generationProgress: some View {
        HStack(spacing: AttenSpacing.md) {
            ProgressView()
                .controlSize(.large)
                .tint(AttenColor.forest)
            VStack(alignment: .leading, spacing: 3) {
                Text("Growing your audio…")
                    .font(.headline)
                    .foregroundStyle(AttenColor.ink)
                Text("Kokoro is synthesizing locally. You can cancel at any time.")
                    .font(.callout)
                    .foregroundStyle(AttenColor.secondaryInk)
            }
            Spacer()
            Button("Cancel") { model.cancelGeneration() }
        }
        .attenCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Generating speech")
    }

    private var wordCount: Int {
        model.draftText.split(whereSeparator: \.isWhitespace).count
    }
}

struct PlaybackCard: View {
    @Bindable var model: AppModel
    let url: URL
    @State private var showsDeleteConfirmation = false

    var body: some View {
        HStack(spacing: AttenSpacing.md) {
            Button {
                model.togglePlayback(url: url)
            } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(AttenColor.sunriseGradient)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.isPlaying ? "Pause audio" : "Play audio")

            VStack(alignment: .leading, spacing: 4) {
                Text(url.deletingPathExtension().lastPathComponent)
                    .font(.headline)
                    .lineLimit(1)
                Label("Ready to review", systemImage: "waveform")
                    .font(.caption)
                    .foregroundStyle(AttenColor.forest)
            }

            Spacer()
            if model.currentProject != nil {
                Button("Delete", systemImage: "trash", role: .destructive) {
                    showsDeleteConfirmation = true
                }
                .help("Delete this project")
            }
            Button("Reveal", systemImage: "folder") {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            Button("Export…", systemImage: "square.and.arrow.up") {
                model.exportCurrent()
            }
            .buttonStyle(.borderedProminent)
            .tint(AttenColor.forest)
        }
        .attenCard()
        .confirmationDialog(
            "Delete this project?",
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            if let project = model.currentProject {
                Button("Delete Project", role: .destructive) {
                    model.delete(project)
                }
                if !project.isLegacyImport {
                    Button("Delete Project and Audio", role: .destructive) {
                        model.delete(project, includingAudio: true)
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Deleting only the project keeps its audio file on disk.")
        }
    }
}

struct VoiceAvatar: View {
    let voice: Voice
    var size: CGFloat = 48

    var body: some View {
        ZStack {
            Circle()
                .fill(gradient)
            Image(systemName: voice.gender == "Female" ? "leaf.fill" : "tree.fill")
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var gradient: LinearGradient {
        switch voice.languageCode {
        case "b": LinearGradient(colors: [AttenColor.river, AttenColor.wildflower], startPoint: .top, endPoint: .bottom)
        case "e", "i", "p": AttenColor.sunriseGradient
        case "f": LinearGradient(colors: [AttenColor.berry, AttenColor.wildflower], startPoint: .topLeading, endPoint: .bottomTrailing)
        default: AttenColor.meadowGradient
        }
    }
}
