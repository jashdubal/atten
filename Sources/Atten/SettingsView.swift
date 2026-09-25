import AttenCore
import SwiftUI

private enum SettingsCategory: String, CaseIterable, Identifiable {
    case provider
    case audio
    case storage
    case appearance
    case shortcuts

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var icon: String {
        switch self {
        case .provider: "cpu"
        case .audio: "speaker.wave.2"
        case .storage: "internaldrive"
        case .appearance: "paintpalette"
        case .shortcuts: "keyboard"
        }
    }
}

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        TabView(selection: $model.settingsTab) {
            SettingsPane(title: "General", detail: "Speech stays on this Mac.") {
                providerForm
            }
            .tabItem { Label("General", systemImage: SettingsCategory.provider.icon) }.tag("general")

            SettingsPane(title: "Audio", detail: "Defaults used for new audio.") {
                audioForm
            }
            .tabItem { Label("Audio", systemImage: SettingsCategory.audio.icon) }.tag("audio")

            SettingsPane(title: "Storage", detail: "Where Atten keeps generated audio and project history.") {
                storageForm
            }
            .tabItem { Label("Storage", systemImage: SettingsCategory.storage.icon) }.tag("storage")

            SettingsPane(title: "Appearance", detail: "Match macOS or choose a specific appearance.") {
                appearanceForm
            }
            .tabItem { Label("Appearance", systemImage: SettingsCategory.appearance.icon) }.tag("appearance")

            ModelsView(model: model)
                .tabItem { Label("Models", systemImage: "shippingbox") }.tag("models")

            SettingsPane(title: "Shortcuts", detail: "Keyboard commands available throughout Atten.") {
                shortcutsForm
            }
            .tabItem { Label("Shortcuts", systemImage: SettingsCategory.shortcuts.icon) }.tag("shortcuts")
        }
        .tint(AttenColor.accent)
        .font(AttenTypography.body)
        .foregroundStyle(AttenColor.textPrimary)
        .preferredColorScheme(preferredColorScheme)
        .onChange(of: model.settings) { _, _ in model.applySettings() }
        .onChange(of: model.selectedVoiceID) { _, _ in model.applySettings() }
        .onChange(of: model.speed) { _, _ in model.applySettings() }
        .onChange(of: model.format) { _, _ in model.applySettings() }
    }

    private var preferredColorScheme: ColorScheme? {
        switch model.settings.appearance {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    private var providerForm: some View {
        Form {
            Section("Kokoro 82M") {
                FormRow(label: "Status", detail: "Offline synthesis; no account or API credential required.") {
                    Label(
                        model.backendIsAvailable ? "Ready" : "Not found",
                        systemImage: model.backendIsAvailable
                            ? "checkmark.circle.fill"
                            : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(
                        model.backendIsAvailable ? AttenColor.success : AttenColor.destructive
                    )
                }

                FormRow(label: "Credentials") {
                    Text("None required").foregroundStyle(AttenColor.textSecondary)
                }

                Toggle("Use Metal acceleration fallback", isOn: $model.settings.useMPS)
                    .help("Sets PYTORCH_ENABLE_MPS_FALLBACK for the local Kokoro process")
            }

            Section("Updates") {
                Toggle("Check GitHub for new versions at launch", isOn: $model.settings.checksForUpdates)
                    .help("Turn this off to keep this version indefinitely and never use the network")

                Text("Speech generation never uses the network. Turning this off makes Atten fully offline; you can still check manually here.")
                    .font(AttenTypography.callout)
                    .foregroundStyle(AttenColor.textSecondary)

                LabeledContent("Version") {
                    HStack(spacing: AttenSpacing.sm) {
                        Text(model.isInstallingUpdate ? "Updating…" : model.appVersion)
                            .foregroundStyle(AttenColor.textSecondary)
                        if model.isCheckingForUpdate {
                            ProgressView().controlSize(.small)
                        }
                        Button("Check for Updates") {
                            Task { await model.checkForUpdate(manual: true) }
                        }
                        .disabled(model.isCheckingForUpdate || model.isInstallingUpdate)
                    }
                }

                LabeledContent("Source code") {
                    Link("View on GitHub", destination: UpdateChecker.repositoryURL)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var audioForm: some View {
        Form {
            Section("Generation defaults") {
                FormRow(label: "Voice") {
                    Picker("Voice", selection: $model.selectedVoiceID) {
                        ForEach(VoiceCatalog.all) { voice in
                            Text("\(voice.name) — \(voice.language)").tag(voice.id)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 270)
                }

                FormRow(label: "Speech speed") {
                    HStack {
                        Slider(value: $model.speed, in: 0.5...2, step: 0.05)
                            .frame(width: 190)
                            .accessibilityLabel("Speech speed")
                            .accessibilityValue(String(format: "%.2f×", model.speed))
                        Text(String(format: "%.2f×", model.speed))
                            .monospacedDigit()
                            .frame(width: 48, alignment: .trailing)
                            .accessibilityHidden(true)
                    }
                }

                FormRow(label: "File format") {
                    Picker("File format", selection: $model.format) {
                        ForEach(AudioFormat.allCases) { format in
                            Text(format.displayName).tag(format)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var storageForm: some View {
        Form {
            Section("Generated audio") {
                FormRow(
                    label: "Export folder",
                    detail: "Project metadata remains in Application Support/Atten."
                ) {
                    HStack(spacing: AttenSpacing.xs) {
                        Text(model.settings.outputDirectory)
                            .font(AttenTypography.callout)
                            .foregroundStyle(AttenColor.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(width: 290, alignment: .trailing)
                        Button("Choose…") { model.chooseOutputDirectory() }
                        Button("Show in Finder") { model.openSaveFolder() }
                    }
                }
            }

            Section {
                Text("Existing audio in the original outputs folder is discovered without being moved.")
                    .font(AttenTypography.callout)
                    .foregroundStyle(AttenColor.textSecondary)
            }
        }
        .formStyle(.grouped)
    }

    private var appearanceForm: some View {
        Form {
            Section("Light or dark") {
                Picker("Appearance", selection: $model.settings.appearance) {
                    ForEach(AppearancePreference.allCases) { appearance in
                        Text(appearance.displayName).tag(appearance)
                    }
                }
                .pickerStyle(.segmented)

                Text("Atten has one palette, drawn light or dark. Motion and transparency follow your macOS accessibility preferences.")
                    .font(AttenTypography.callout)
                    .foregroundStyle(AttenColor.textSecondary)
            }
        }
        .formStyle(.grouped)
    }

    private var shortcutsForm: some View {
        Form {
            Section("Create") {
                ShortcutRow(action: "New", keys: "⌘N")
                ShortcutRow(action: "Add to Library", keys: "⌘O")
                ShortcutRow(action: "Import into Create", keys: "⌘I")
                ShortcutRow(action: "Generate speech", keys: "⌘↩")
                ShortcutRow(action: "Export current audio", keys: "⇧⌘E")
            }
            Section("Library and reader") {
                ShortcutRow(action: "Open Library", keys: "⌘1")
                ShortcutRow(action: "Open Voices", keys: "⌘2")
                ShortcutRow(action: "Open Settings", keys: "⌘,")
                ShortcutRow(action: "Search the Library", keys: "⌘F")
                ShortcutRow(action: "Find in book", keys: "⌘F")
            }
            Section("Playback") {
                ShortcutRow(action: "Play or pause", keys: "Space")
                ShortcutRow(action: "Play or pause (anywhere)", keys: "⌥Space")
                ShortcutRow(action: "Skip back 15 seconds", keys: "←")
                ShortcutRow(action: "Skip forward 15 seconds", keys: "→")
                ShortcutRow(action: "Bookmark the sentence playing", keys: "⌘D")
                ShortcutRow(action: "Cancel generation", keys: "Esc")
            }
        }
        .formStyle(.grouped)
    }
}

private struct SettingsPane<Content: View>: View {
    let title: String
    let detail: String
    @ViewBuilder let content: Content

    init(title: String, detail: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.detail = detail
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AttenSpacing.md) {
            VStack(alignment: .leading, spacing: AttenSpacing.xxs) {
                Text(title)
                    .font(AttenTypography.title2)
                    .foregroundStyle(AttenColor.textPrimary)
                Text(detail)
                    .font(AttenTypography.body)
                    .foregroundStyle(AttenColor.textSecondary)
            }
            .padding(.horizontal, AttenSpacing.lg)
            .padding(.top, AttenSpacing.lg)

            // The form's own grey would cut the pane in two under its header.
            content.scrollContentBackground(.hidden)
                .attenFormScrollPadding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AttenColor.appBackground)
    }
}

private struct ShortcutRow: View {
    let action: String
    let keys: String

    var body: some View {
        LabeledContent(action) {
            Text(keys)
                .font(AttenTypography.label)
                .foregroundStyle(AttenColor.textSecondary)
                .padding(.horizontal, AttenSpacing.xs)
                .padding(.vertical, AttenSpacing.xxs)
                .background(AttenColor.surfaceMuted)
                .clipShape(RoundedRectangle(cornerRadius: AttenRadius.small))
                .overlay {
                    RoundedRectangle(cornerRadius: AttenRadius.small)
                        .stroke(AttenColor.separator, lineWidth: 1)
                }
        }
        .accessibilityElement(children: .combine)
    }
}
