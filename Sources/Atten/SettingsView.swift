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
        TabView {
            SettingsPane(title: "Provider", detail: "Local speech synthesis status and acceleration.") {
                providerForm
            }
            .tabItem { Label("Provider", systemImage: SettingsCategory.provider.icon) }

            SettingsPane(title: "Audio", detail: "Defaults used for new Studio generations.") {
                audioForm
            }
            .tabItem { Label("Audio", systemImage: SettingsCategory.audio.icon) }

            SettingsPane(title: "Storage", detail: "Where Atten keeps generated audio and project history.") {
                storageForm
            }
            .tabItem { Label("Storage", systemImage: SettingsCategory.storage.icon) }

            SettingsPane(title: "Appearance", detail: "Match macOS or choose a specific appearance.") {
                appearanceForm
            }
            .tabItem { Label("Appearance", systemImage: SettingsCategory.appearance.icon) }

            SettingsPane(title: "Shortcuts", detail: "Keyboard commands available throughout Atten.") {
                shortcutsForm
            }
            .tabItem { Label("Shortcuts", systemImage: SettingsCategory.shortcuts.icon) }
        }
        .tint(AttenColor.accent)
        .onChange(of: model.settings) { _, _ in model.applySettings() }
        .onChange(of: model.selectedVoiceID) { _, _ in model.applySettings() }
        .onChange(of: model.speed) { _, _ in model.applySettings() }
        .onChange(of: model.format) { _, _ in model.applySettings() }
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
                        Text(String(format: "%.2f×", model.speed))
                            .monospacedDigit()
                            .frame(width: 48, alignment: .trailing)
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
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(AttenColor.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(width: 290, alignment: .trailing)
                        Button("Choose…") { model.chooseOutputDirectory() }
                    }
                }
            }

            Section {
                Text("Existing audio in the original outputs folder is discovered without being moved.")
                    .font(AttenTypography.metadata)
                    .foregroundStyle(AttenColor.textSecondary)
            }
        }
        .formStyle(.grouped)
    }

    private var appearanceForm: some View {
        Form {
            Section("Theme") {
                Picker("Appearance", selection: $model.settings.appearance) {
                    ForEach(AppearancePreference.allCases) { appearance in
                        Text(appearance.displayName).tag(appearance)
                    }
                }
                .pickerStyle(.segmented)

                Text("Motion and transparency follow your macOS accessibility preferences.")
                    .font(AttenTypography.metadata)
                    .foregroundStyle(AttenColor.textSecondary)
            }
        }
        .formStyle(.grouped)
    }

    private var shortcutsForm: some View {
        Form {
            Section("Studio") {
                ShortcutRow(action: "New Studio draft", keys: "⌘N")
                ShortcutRow(action: "Import text", keys: "⌘O")
                ShortcutRow(action: "Generate speech", keys: "⌘↩")
                ShortcutRow(action: "Export current audio", keys: "⇧⌘E")
            }
            Section("Navigation and playback") {
                ShortcutRow(action: "Open Studio", keys: "⌘1")
                ShortcutRow(action: "Open Playground", keys: "⌘2")
                ShortcutRow(action: "Create temporary sample", keys: "⌥⌘↩")
                ShortcutRow(action: "Play or pause", keys: "⌥Space")
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
                Text(title).font(.system(size: 20, weight: .semibold))
                Text(detail)
                    .font(AttenTypography.body)
                    .foregroundStyle(AttenColor.textSecondary)
            }
            .padding(.horizontal, AttenSpacing.lg)
            .padding(.top, AttenSpacing.lg)

            content
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
                .font(.system(size: 12, weight: .medium, design: .rounded))
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
