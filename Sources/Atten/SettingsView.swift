import AttenCore
import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        ZStack {
            ForestBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: AttenSpacing.lg) {
                    SectionHeader(
                        eyebrow: "Settings",
                        title: "Make Atten yours",
                        detail: "Configure the real Kokoro backend, audio defaults, storage, appearance, and shortcuts."
                    )

                    providerSection
                    audioSection
                    storageSection
                    appearanceSection
                    shortcutsSection
                }
                .padding(AttenSpacing.xl)
                .frame(maxWidth: 820, alignment: .topLeading)
            }
        }
        .onChange(of: model.settings) { _, _ in model.applySettings() }
    }

    private var providerSection: some View {
        SettingsCard(title: "Provider", icon: "cpu") {
            HStack(spacing: AttenSpacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AttenColor.meadowGradient)
                    Image(systemName: "leaf.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                }
                .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Kokoro 82M")
                            .font(.headline)
                        Text("Offline")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(AttenColor.forest.opacity(0.14))
                            .clipShape(Capsule())
                    }
                    Text("Local speech synthesis. No account, network API, or credential is required.")
                        .font(.callout)
                        .foregroundStyle(AttenColor.secondaryInk)
                }
                Spacer()
                Label(
                    model.backendIsAvailable ? "Ready" : "Not found",
                    systemImage: model.backendIsAvailable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                )
                .foregroundStyle(model.backendIsAvailable ? AttenColor.forest : AttenColor.berry)
            }

            Divider()

            LabeledContent("Credentials") {
                Text("None required")
                    .foregroundStyle(.secondary)
            }
            Text("Atten’s provider boundary stores any future secrets in macOS Keychain, never in project files or preferences.")
                .font(.caption)
                .foregroundStyle(AttenColor.secondaryInk)

            Toggle("Use Metal acceleration fallback", isOn: $model.settings.useMPS)
                .help("Sets PYTORCH_ENABLE_MPS_FALLBACK for the local Kokoro process")
        }
    }

    private var audioSection: some View {
        SettingsCard(title: "Audio defaults", icon: "speaker.wave.2") {
            LabeledContent("Default voice") {
                Picker("Default voice", selection: $model.selectedVoiceID) {
                    ForEach(VoiceCatalog.all) { voice in
                        Text("\(voice.name) — \(voice.language)").tag(voice.id)
                    }
                }
                .labelsHidden()
                .frame(width: 260)
            }

            LabeledContent("Speech speed") {
                HStack {
                    Slider(value: $model.speed, in: 0.5...2, step: 0.05)
                        .frame(width: 180)
                    Text(String(format: "%.2f×", model.speed))
                        .monospacedDigit()
                        .frame(width: 48, alignment: .trailing)
                }
            }

            LabeledContent("File format") {
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

    private var storageSection: some View {
        SettingsCard(title: "Storage", icon: "internaldrive") {
            LabeledContent("Generated audio") {
                HStack {
                    Text(model.settings.outputDirectory)
                        .font(.caption.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 330, alignment: .trailing)
                    Button("Choose…") { model.chooseOutputDirectory() }
                }
            }
            Text("Project metadata is stored in Application Support/Atten. Existing files in the original outputs folder are discovered without being moved.")
                .font(.caption)
                .foregroundStyle(AttenColor.secondaryInk)
        }
    }

    private var appearanceSection: some View {
        SettingsCard(title: "Appearance", icon: "paintpalette") {
            LabeledContent("Theme") {
                Picker("Theme", selection: $model.settings.appearance) {
                    ForEach(AppearancePreference.allCases) { appearance in
                        Text(appearance.displayName).tag(appearance)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 260)
            }
            Text("Motion and transparency follow your macOS accessibility preferences.")
                .font(.caption)
                .foregroundStyle(AttenColor.secondaryInk)
        }
    }

    private var shortcutsSection: some View {
        SettingsCard(title: "Keyboard shortcuts", icon: "keyboard") {
            ShortcutRow(action: "New Studio draft", keys: "⌘N")
            ShortcutRow(action: "Import text", keys: "⌘O")
            ShortcutRow(action: "Generate speech", keys: "⌘↩")
            ShortcutRow(action: "Play or pause", keys: "Space")
            ShortcutRow(action: "Cancel generation", keys: "Esc")
            ShortcutRow(action: "Export current audio", keys: "⇧⌘E")
        }
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AttenSpacing.md) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(AttenColor.ink)
            content
        }
        .attenCard(padding: AttenSpacing.lg)
    }
}

private struct ShortcutRow: View {
    let action: String
    let keys: String

    var body: some View {
        LabeledContent(action) {
            Text(keys)
                .font(.system(.body, design: .rounded, weight: .semibold))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(AttenColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(AttenColor.divider)
                }
        }
        .accessibilityElement(children: .combine)
    }
}
