import AppKit
import AttenCore
import SwiftUI
import UniformTypeIdentifiers

struct StudioView: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsAdvancedSettings = false
    @State private var isDropTargeted = false
    @State private var hasEditedDraft = false
    @State private var cancellationNotice = false
    @State private var pasteNotice: String?
    @State private var completedDraftText: String?

    private enum StudioState {
        case idle
        case empty
        case ready
        case generating
        case cancelled
        case completed
        case error(String)
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: AttenSpacing.lg) {
                    header
                    statusArea
                    workspace(width: proxy.size.width, height: proxy.size.height)

                    if let audioURL = model.currentAudioURL, isCompletedState {
                        PlaybackCard(model: model, url: audioURL)
                            .transition(
                                AttenMotion.transition(
                                    .overlay(edge: .bottom),
                                    reduceMotion: reduceMotion
                                )
                            )
                    }
                }
                .padding(.horizontal, proxy.size.width < 700 ? AttenSpacing.lg : AttenSpacing.xl)
                .padding(.vertical, AttenSpacing.lg)
                .frame(maxWidth: 1180, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .animation(
            AttenMotion.transitionAnimation(
                AttenMotion.standard,
                reduceMotion: reduceMotion
            ),
            value: model.currentAudioURL
        )
        .onChange(of: model.draftText) { _, _ in
            hasEditedDraft = true
            cancellationNotice = false
            pasteNotice = nil
            completedDraftText = nil
        }
        .onChange(of: model.generationState) { _, state in
            switch state {
            case .generating, .failed:
                cancellationNotice = false
            case .ready:
                cancellationNotice = false
                completedDraftText = model.draftText
            case .idle:
                // The model intentionally returns to idle after cancellation;
                // the local notice keeps that useful distinction visible here.
                break
            }
        }
        .onChange(of: model.selectedVoiceID) { _, _ in
            completedDraftText = nil
            model.applySettings()
        }
        .onChange(of: model.speed) { _, _ in
            completedDraftText = nil
            model.applySettings()
        }
        .onChange(of: model.format) { _, _ in
            completedDraftText = nil
            model.applySettings()
        }
        .onChange(of: model.settings.useMPS) { _, _ in
            completedDraftText = nil
            model.applySettings()
        }
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: AttenSpacing.md) {
            PageHeader(
                eyebrow: "Studio",
                title: "Create speech",
                detail: "Write naturally, then turn your words into audio on this Mac."
            )
            Spacer()
            statePill
        }
    }

    private var statePill: some View {
        Label(stateLabel, systemImage: stateIcon)
            .font(AttenTypography.metadata.weight(.medium))
            .foregroundStyle(stateColor)
            .padding(.horizontal, AttenSpacing.xs)
            .padding(.vertical, AttenSpacing.xxs)
            .background(AttenColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: AttenRadius.control))
            .overlay {
                RoundedRectangle(cornerRadius: AttenRadius.control)
                    .stroke(stateColor.opacity(0.7), lineWidth: 1)
            }
            .accessibilityLabel("Studio status: \(stateLabel)")
    }

    @ViewBuilder private var statusArea: some View {
        if let pasteNotice {
            StatusBanner(kind: .success, message: pasteNotice) { self.pasteNotice = nil }
        }
        if let success = model.successMessage, !isCompletedState {
            StatusBanner(kind: .success, message: success, dismiss: model.dismissStatus)
        }
        if case .completed = studioState {
            AttenProgressStatus(
                title: "Speech ready",
                detail: "The generated audio is ready in the shared player and Projects.",
                phase: .success
            )
        } else if case let .error(message) = studioState {
            errorBanner(message)
        } else if case .cancelled = studioState {
            cancelledBanner
        }
    }

    @ViewBuilder private func workspace(width: CGFloat, height: CGFloat) -> some View {
        let workspaceHeight = max(500, height - 190)
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
                    .frame(minHeight: max(410, height - 300))
                inspectorPane
            }
        }
    }

    private var editorPane: some View {
        VStack(alignment: .leading, spacing: AttenSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: AttenSpacing.xxs) {
                    Label("Script", systemImage: "text.alignleft")
                        .font(AttenTypography.sectionTitle)
                        .foregroundStyle(AttenColor.textPrimary)
                    Text(editorPrompt)
                        .font(AttenTypography.caption)
                        .foregroundStyle(AttenColor.textSecondary)
                }
                Spacer()
                Text("\(wordCount) words · \(model.draftText.count) characters")
                    .font(AttenTypography.metadata)
                    .foregroundStyle(AttenColor.textSecondary)
                    .accessibilityLabel("\(wordCount) words, \(model.draftText.count) characters")
            }

            TextField("Project title", text: $model.draftTitle)
                .textFieldStyle(.plain)
                .font(AttenTypography.sectionTitle)
                .padding(.horizontal, AttenSpacing.sm)
                .frame(height: 38)
                .attenInput()
                .accessibilityLabel("Project title")

            ZStack(alignment: .topLeading) {
                AlignedTextEditor(text: $model.draftText, accessibilityLabel: "Speech text")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityHint("Enter the text Atten should speak. You can paste text or drop a file here.")

                if model.draftText.isEmpty {
                    VStack(alignment: .leading, spacing: AttenSpacing.xxs) {
                        Text(hasEditedDraft ? "Your script is empty" : "Start writing here…")
                            .font(AttenTypography.body)
                            .foregroundStyle(AttenColor.textSecondary)
                        Text("Paste text, import a file, or drop one anywhere in the editor.")
                            .font(AttenTypography.metadata)
                            .foregroundStyle(AttenColor.textSecondary.opacity(0.82))
                    }
                    .padding(AttenSpacing.md)
                    .allowsHitTesting(false)
                }
            }
            .frame(minHeight: 350)
            .attenInput()
            .overlay {
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: AttenRadius.control)
                        .stroke(AttenColor.focus, style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                        .accessibilityHidden(true)
                }
            }
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first else { return false }
                model.importText(from: url)
                hasEditedDraft = true
                return true
            } isTargeted: { isDropTargeted = $0 }

            HStack(spacing: AttenSpacing.xs) {
                Button("Import File", systemImage: "doc.badge.plus") {
                    model.openImportPanel()
                    hasEditedDraft = true
                }
                .buttonStyle(AttenSecondaryButtonStyle())
                .keyboardShortcut("o")
                .help("Import a UTF-8 text, Markdown, source, or RTF file")

                Button("Paste", systemImage: "doc.on.clipboard") {
                    pasteFromClipboard()
                }
                .buttonStyle(AttenSecondaryButtonStyle())
                .keyboardShortcut("v", modifiers: [.command, .shift])
                .help("Paste plain text from the clipboard")

                Spacer()
                Label("Saved automatically", systemImage: "checkmark")
                    .font(AttenTypography.caption)
                    .foregroundStyle(AttenColor.textSecondary)
                if !model.draftText.isEmpty {
                    Button("Clear") {
                        model.draftText = ""
                        hasEditedDraft = true
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AttenColor.textSecondary)
                    .accessibilityHint("Removes the current script")
                }
            }
        }
        .padding(.trailing, AttenSpacing.md)
    }

    private var inspectorPane: some View {
        VStack(alignment: .leading, spacing: AttenSpacing.md) {
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
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Voice")

                HStack(spacing: AttenSpacing.xs) {
                    VoiceAvatar(voice: model.selectedVoice, size: 32)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(model.selectedVoice.name)
                            .font(AttenTypography.control.weight(.semibold))
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
                    .accessibilityHint("Plays a short sample using the shared player")
                }
                .padding(AttenSpacing.xs)
                .background(AttenColor.surfaceMuted)
                .clipShape(RoundedRectangle(cornerRadius: AttenRadius.control))
            }

            Divider().overlay(AttenColor.separator)

            InspectorSection(title: "Output") {
                HStack(spacing: AttenSpacing.sm) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Speed")
                            .font(AttenTypography.caption)
                            .foregroundStyle(AttenColor.textSecondary)
                        Text(String(format: "%.2f×", model.speed))
                            .font(AttenTypography.control.monospacedDigit().weight(.medium))
                    }
                    Slider(value: $model.speed, in: 0.5...2, step: 0.05) {
                        Text("Speech speed")
                    }
                    .accessibilityValue(String(format: "%.2f times", model.speed))
                    .accessibilityHint("Adjusts how quickly the generated speech is read")
                }

                Picker("Format", selection: $model.format) {
                    ForEach(AudioFormat.allCases) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Audio format")
            }

            DisclosureGroup("Advanced", isExpanded: $showsAdvancedSettings) {
                VStack(alignment: .leading, spacing: AttenSpacing.sm) {
                    Toggle("Use Metal acceleration fallback", isOn: $model.settings.useMPS)
                        .font(AttenTypography.body)
                    Text("Most people can leave this on. It helps compatible Macs generate speech locally.")
                        .font(AttenTypography.caption)
                        .foregroundStyle(AttenColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, AttenSpacing.xs)
            }
            .font(AttenTypography.control)
            .animation(
                AttenMotion.animation(
                    AttenMotion.panel,
                    reduceMotion: reduceMotion
                ),
                value: showsAdvancedSettings
            )

            Spacer(minLength: AttenSpacing.xs)

            generationAction

            Text("Speech stays on this Mac. Completed audio also appears in Projects and the shared player.")
                .font(AttenTypography.caption)
                .foregroundStyle(AttenColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHint("Your generated audio is available in the shared player and Projects")
        }
        .attenSurface(padding: AttenSpacing.md, elevated: true)
    }

    @ViewBuilder private var generationAction: some View {
        switch studioState {
        case .generating:
            VStack(alignment: .leading, spacing: AttenSpacing.xs) {
                AttenProgressStatus(
                    title: "Generating speech",
                    detail: "The local speech backend is working. Progress is indeterminate because it does not report a fraction.",
                    phase: .active
                )
                Button("Cancel generation", role: .cancel) {
                    cancellationNotice = true
                    model.cancelGeneration()
                }
                .buttonStyle(AttenSecondaryButtonStyle())
                .frame(maxWidth: .infinity)
                .keyboardShortcut(.escape, modifiers: [])
                .accessibilityHint("Stops this generation and keeps your script so you can try again")
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Generating speech")
        case .cancelled:
            Button {
                model.generate()
            } label: {
                Label("Generate Again", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(AttenPrimaryButtonStyle())
            .keyboardShortcut(.return, modifiers: [.command])
            .accessibilityHint("Starts speech generation again using your current script and settings")
        case .completed:
            Button {
                model.toggleActivePlayback()
            } label: {
                Label(model.isPlaying ? "Pause in Player" : "Play in Player", systemImage: model.isPlaying ? "pause.fill" : "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(AttenPrimaryButtonStyle())
            .accessibilityHint("Hands the completed audio to the shared player")
        case .error:
            Button {
                model.generate()
            } label: {
                Label("Try Again", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(AttenPrimaryButtonStyle())
            .disabled(model.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .keyboardShortcut(.return, modifiers: [.command])
        case .idle, .empty, .ready:
            Button {
                model.generate()
            } label: {
                Label("Generate Speech", systemImage: "waveform")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(AttenPrimaryButtonStyle())
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(model.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityHint(
                model.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "Enter or paste text before generating speech"
                    : "Generates speech locally with the selected voice"
            )
        }
    }

    private var studioState: StudioState {
        if model.isGenerating { return .generating }
        if case let .failed(message) = model.generationState { return .error(message) }
        if case .ready = model.generationState, isCompletedState { return .completed }
        if cancellationNotice { return .cancelled }
        if model.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return hasEditedDraft ? .empty : .idle
        }
        return .ready
    }

    private var isCompletedState: Bool {
        if case .ready = model.generationState, completedDraftText == model.draftText { return true }
        return false
    }

    private var stateLabel: String {
        switch studioState {
        case .idle: "Idle"
        case .empty: "Empty script"
        case .ready: "Ready to generate"
        case .generating: "Generating"
        case .cancelled: "Cancelled"
        case .completed: "Completed"
        case .error: "Needs attention"
        }
    }

    private var stateIcon: String {
        switch studioState {
        case .idle, .ready: "circle"
        case .empty: "square.dashed"
        case .generating: "arrow.triangle.2.circlepath"
        case .cancelled: "pause.circle"
        case .completed: "checkmark.circle.fill"
        case .error: "exclamationmark.triangle.fill"
        }
    }

    private var stateColor: Color {
        switch studioState {
        case .error: AttenColor.destructive
        case .cancelled: AttenColor.warning
        case .completed: AttenColor.success
        case .generating: AttenColor.accent
        case .idle, .empty, .ready: AttenColor.textSecondary
        }
    }

    private var editorPrompt: String {
        switch studioState {
        case .idle: "Your words become a local narration."
        case .empty: "Add some text to enable Generate Speech."
        case .ready: "Review your script before generating."
        case .generating: "You can keep this script and cancel at any time."
        case .cancelled: "Your script is safe. Generate again when ready."
        case .completed: "Your narration is ready in the shared player."
        case .error: "Fix the issue below, then try again."
        }
    }

    private var cancelledBanner: some View {
        HStack(spacing: AttenSpacing.xs) {
            Image(systemName: "pause.circle.fill").foregroundStyle(AttenColor.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text("Generation cancelled")
                    .font(AttenTypography.control.weight(.semibold))
                Text("Your script and settings are still here. Generate again when ready.")
                    .font(AttenTypography.caption)
                    .foregroundStyle(AttenColor.textSecondary)
            }
            Spacer()
            Button("Dismiss") { cancellationNotice = false }
                .buttonStyle(.plain)
                .foregroundStyle(AttenColor.textSecondary)
        }
        .padding(AttenSpacing.sm)
        .background(AttenColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: AttenRadius.control))
        .overlay { RoundedRectangle(cornerRadius: AttenRadius.control).stroke(AttenColor.warning, lineWidth: 1) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Generation cancelled. Your script and settings are still here.")
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: AttenSpacing.xs) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(AttenColor.destructive)
            VStack(alignment: .leading, spacing: AttenSpacing.xxs) {
                Text("Generation needs attention")
                    .font(AttenTypography.control.weight(.semibold))
                Text(message)
                    .font(AttenTypography.body)
                    .foregroundStyle(AttenColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: AttenSpacing.sm) {
                    Button("Try Again") { model.generate() }
                        .buttonStyle(.bordered)
                        .disabled(model.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if message.localizedCaseInsensitiveContains("model") {
                        Button("Open Models") { model.section = .models }
                            .buttonStyle(.bordered)
                    }
                    Button("Dismiss") { model.dismissStatus() }
                        .buttonStyle(.plain)
                        .foregroundStyle(AttenColor.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(AttenSpacing.sm)
        .background(AttenColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: AttenRadius.control))
        .overlay { RoundedRectangle(cornerRadius: AttenRadius.control).stroke(AttenColor.destructive, lineWidth: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Generation error: \(message)")
    }

    private func pasteFromClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
            pasteNotice = "There is no plain text in the clipboard to paste."
            return
        }
        model.draftText = text
        model.generationState = .idle
        hasEditedDraft = true
        pasteNotice = "Pasted \(wordCount) words into your script."
    }

    private var groupedLanguages: [String] {
        _ = model.voiceCatalogRevision
        return Array(Set(VoiceCatalog.all.map(\.language))).sorted()
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
                    .font(AttenTypography.control.weight(.semibold))
                    .foregroundStyle(AttenColor.onAccent)
                    .frame(width: 36, height: 36)
                    .background(AttenColor.accent)
                    .clipShape(RoundedRectangle(cornerRadius: AttenRadius.control))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.isPlaying ? "Pause audio" : "Play audio")

            VStack(alignment: .leading, spacing: 2) {
                Text(url.deletingPathExtension().lastPathComponent)
                    .font(AttenTypography.control.weight(.semibold))
                    .lineLimit(1)
                Text(model.playerTitle != nil
                    ? (model.isPlaying ? "Completed · Playing in shared player" : "Completed · Ready in shared player")
                    : "Completed · Ready to review · \(url.pathExtension.uppercased())")
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
            .buttonStyle(AttenPrimaryButtonStyle())
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
            RoundedRectangle(cornerRadius: AttenRadius.small)
                .fill(AttenColor.surfaceMuted)
                .overlay {
                    RoundedRectangle(cornerRadius: AttenRadius.small)
                        .stroke(avatarColor.opacity(0.7), lineWidth: 1)
                }
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
