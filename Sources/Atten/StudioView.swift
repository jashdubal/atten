import AttenCore
import SwiftUI
import UniformTypeIdentifiers

struct StudioView: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsOutputSettings = true
    @State private var isDropTargeted = false

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: AttenSpacing.lg) {
                    header
                    statusArea
                    workspace(width: proxy.size.width, height: proxy.size.height)

                    if let audioURL = model.currentAudioURL {
                        PlaybackCard(model: model, url: audioURL)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .padding(.horizontal, proxy.size.width < 700 ? AttenSpacing.lg : AttenSpacing.xl)
                .padding(.vertical, AttenSpacing.lg)
                .frame(maxWidth: 1180, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .animation(
            reduceMotion ? nil : .easeInOut(duration: AttenMotion.standard),
            value: model.currentAudioURL
        )
        .onChange(of: model.selectedVoiceID) { _, _ in model.applySettings() }
        .onChange(of: model.speed) { _, _ in model.applySettings() }
        .onChange(of: model.format) { _, _ in model.applySettings() }
        .onChange(of: model.settings.useMPS) { _, _ in model.applySettings() }
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: AttenSpacing.md) {
            PageHeader(
                eyebrow: "Studio",
                title: "Create speech",
                detail: "Write, choose a voice, and generate locally."
            )
            Spacer()
            Button("Import…", systemImage: "doc.badge.plus") {
                model.openImportPanel()
            }
            .buttonStyle(.bordered)
            .keyboardShortcut("o")
            .help("Import a UTF-8 text, Markdown, source, or RTF file")
        }
    }

    @ViewBuilder private var statusArea: some View {
        if let success = model.successMessage {
            StatusBanner(kind: .success, message: success, dismiss: model.dismissStatus)
        }
        if case let .failed(message) = model.generationState {
            StatusBanner(kind: .error, message: message, dismiss: model.dismissStatus)
        }
    }

    @ViewBuilder private func workspace(width: CGFloat, height: CGFloat) -> some View {
        let workspaceHeight = max(430, height - 205)
        let contentWidth = width - (width < 700 ? 48 : 64)
        if contentWidth >= 760 {
            HSplitView {
                editorPane
                    .frame(minWidth: 440, maxWidth: .infinity, minHeight: workspaceHeight)
                inspectorPane
                    .frame(minWidth: 280, idealWidth: 304, maxWidth: 340, minHeight: workspaceHeight)
            }
            .frame(minHeight: workspaceHeight)
        } else {
            VStack(alignment: .leading, spacing: AttenSpacing.md) {
                editorPane
                    .frame(minHeight: max(360, height - 310))
                inspectorPane
            }
        }
    }

    private var editorPane: some View {
        VStack(alignment: .leading, spacing: AttenSpacing.sm) {
            HStack {
                Label("Script", systemImage: "text.alignleft")
                    .font(AttenTypography.sectionTitle)
                    .foregroundStyle(AttenColor.textPrimary)
                Spacer()
                Text("\(wordCount) words · \(model.draftText.count) characters")
                    .font(AttenTypography.metadata)
                    .foregroundStyle(AttenColor.textSecondary)
            }

            TextField("Project title", text: $model.draftTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 16, weight: .semibold))
                .padding(.horizontal, AttenSpacing.sm)
                .frame(height: 36)
                .attenInput()
                .accessibilityLabel("Project title")

            ZStack(alignment: .topLeading) {
                AlignedTextEditor(text: $model.draftText, accessibilityLabel: "Speech text")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityHint("Enter the text Atten should speak")

                if model.draftText.isEmpty {
                    VStack(alignment: .leading, spacing: AttenSpacing.xxs) {
                        Text("Start writing here…")
                            .foregroundStyle(AttenColor.textSecondary)
                        Text("Drop a compatible text file here to import it.")
                            .font(AttenTypography.metadata)
                            .foregroundStyle(AttenColor.textSecondary.opacity(0.82))
                    }
                    .padding(AttenSpacing.sm)
                    .allowsHitTesting(false)
                }
            }
            .frame(minHeight: 300)
            .attenInput()
            .overlay {
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: AttenRadius.control)
                        .stroke(
                            AttenColor.focus,
                            style: StrokeStyle(lineWidth: 2, dash: [5, 4])
                        )
                }
            }
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first else { return false }
                model.importText(from: url)
                return true
            } isTargeted: { isDropTargeted = $0 }

            HStack {
                Label("Saved automatically as a draft", systemImage: "checkmark")
                    .font(AttenTypography.caption)
                    .foregroundStyle(AttenColor.textSecondary)
                Spacer()
                if !model.draftText.isEmpty {
                    Button("Clear") { model.draftText = "" }
                        .buttonStyle(.plain)
                        .foregroundStyle(AttenColor.textSecondary)
                }
            }
        }
        .padding(.trailing, AttenSpacing.md)
    }

    private var inspectorPane: some View {
        VStack(alignment: .leading, spacing: AttenSpacing.lg) {
            InspectorSection(title: "Voice") {
                Picker("Voice", selection: $model.selectedVoiceID) {
                    ForEach(groupedLanguages, id: \.self) { language in
                        Section(language) {
                            ForEach(VoiceCatalog.all.filter { $0.language == language }) { voice in
                                Text("\(voice.name) · \(voice.gender)").tag(voice.id)
                            }
                        }
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)

                HStack(spacing: AttenSpacing.xs) {
                    VoiceAvatar(voice: model.selectedVoice, size: 36)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(model.selectedVoice.name)
                            .font(.system(size: 13, weight: .semibold))
                        Text("\(model.selectedVoice.language) · \(model.selectedVoice.gender)")
                            .font(AttenTypography.caption)
                            .foregroundStyle(AttenColor.textSecondary)
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
                .padding(AttenSpacing.xs)
                .background(AttenColor.surfaceMuted)
                .clipShape(RoundedRectangle(cornerRadius: AttenRadius.control))
            }

            Divider().overlay(AttenColor.separator)

            DisclosureGroup("Output settings", isExpanded: $showsOutputSettings) {
                VStack(alignment: .leading, spacing: AttenSpacing.md) {
                    VStack(alignment: .leading, spacing: AttenSpacing.xs) {
                        HStack {
                            Text("Speed")
                            Spacer()
                            Text(String(format: "%.2f×", model.speed))
                                .monospacedDigit()
                                .foregroundStyle(AttenColor.accent)
                        }
                        Slider(value: $model.speed, in: 0.5...2, step: 0.05) {
                            Text("Speech speed")
                        }
                    }

                    Picker("Format", selection: $model.format) {
                        ForEach(AudioFormat.allCases) { format in
                            Text(format.displayName).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)

                    Toggle("Metal acceleration fallback", isOn: $model.settings.useMPS)
                        .font(AttenTypography.body)
                }
                .padding(.top, AttenSpacing.sm)
            }
            .font(.system(size: 13, weight: .medium))

            Spacer(minLength: 0)

            generationAction

            Text("Speech generation stays on this Mac. The first run may download the Kokoro model.")
                .font(AttenTypography.caption)
                .foregroundStyle(AttenColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .attenSurface(padding: AttenSpacing.md, elevated: true)
    }

    @ViewBuilder private var generationAction: some View {
        if model.isGenerating {
            VStack(spacing: AttenSpacing.xs) {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Generating speech…")
                    Spacer()
                }
                .font(AttenTypography.body)
                .foregroundStyle(AttenColor.textSecondary)

                Button("Cancel Generation", role: .cancel) { model.cancelGeneration() }
                    .buttonStyle(AttenSecondaryButtonStyle())
                    .frame(maxWidth: .infinity)
                    .keyboardShortcut(.escape, modifiers: [])
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Generating speech")
        } else {
            Button {
                model.generate()
            } label: {
                Label("Generate Speech", systemImage: "waveform")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(AttenPrimaryButtonStyle())
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(model.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityHint("Generates speech locally with the selected Kokoro voice")
        }
    }

    private var groupedLanguages: [String] {
        Array(Set(VoiceCatalog.all.map(\.language))).sorted()
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
        HStack(spacing: AttenSpacing.sm) {
            Button { model.togglePlayback(url: url) } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(light: 0xFFFFFF, dark: 0x17111D))
                    .frame(width: 36, height: 36)
                    .background(AttenColor.accent)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.isPlaying ? "Pause audio" : "Play audio")

            VStack(alignment: .leading, spacing: 2) {
                Text(url.deletingPathExtension().lastPathComponent)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text("Ready to review · \(url.pathExtension.uppercased())")
                    .font(AttenTypography.caption)
                    .foregroundStyle(AttenColor.textSecondary)
            }

            Spacer(minLength: AttenSpacing.xs)

            Menu {
                Button("Reveal in Finder", systemImage: "folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                if model.currentProject != nil {
                    Divider()
                    Button("Delete Project…", systemImage: "trash", role: .destructive) {
                        showsDeleteConfirmation = true
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel("Audio actions")

            Button("Export…", systemImage: "square.and.arrow.up") {
                model.exportCurrent()
            }
            .buttonStyle(.borderedProminent)
            .tint(AttenColor.accent)
        }
        .attenSurface(padding: AttenSpacing.sm)
        .confirmationDialog(
            "Delete this project?",
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            if let project = model.currentProject {
                Button("Delete Project", role: .destructive) { model.delete(project) }
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
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            Circle().fill(avatarColor.opacity(0.18))
            Image(systemName: voice.gender == "Female" ? "person.fill" : "person.fill")
                .font(.system(size: size * 0.40, weight: .medium))
                .foregroundStyle(avatarColor)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var avatarColor: Color {
        switch voice.languageCode {
        case "b", "f": AttenColor.accentSecondary
        case "e", "i", "p": AttenColor.warning
        default: AttenColor.accent
        }
    }
}
