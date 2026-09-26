import AttenCore
import SwiftUI

private enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case audio
    case storage
    case appearance
    case models
    case shortcuts

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct SettingsView: View {
    @Bindable var model: AppModel
    @Environment(\.openURL) private var openURL

    private var tab: SettingsTab { SettingsTab(rawValue: model.settingsTab) ?? .general }

    var body: some View {
        // One column: the title, the tabs and every section share its
        // leading edge.
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: AttenSpacing.md) {
                Text("Settings").font(AttenTypography.title2)
                Picker("Settings", selection: $model.settingsTab) {
                    ForEach(SettingsTab.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            .padding(.horizontal, SettingsColumn.gutter)
            .padding(.top, AttenSpacing.lg)
            .padding(.bottom, AttenSpacing.md)

            switch tab {
            case .general: SettingsPane { generalSections }
            case .audio: SettingsPane { audioSections }
            case .storage: SettingsPane { storageSections }
            case .appearance: SettingsPane { appearanceSections }
            case .models: ModelsView(model: model)
            case .shortcuts: SettingsPane { shortcutsSections }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AttenColor.appBackground)
        .tint(AttenColor.signal)
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

    @ViewBuilder private var generalSections: some View {
        SettingsSection("Kokoro 82M") {
            SettingsRow("Status") {
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
            SettingsDivider()
            SettingsRow("Use Metal acceleration fallback") {
                SettingsSwitch(label: "Use Metal acceleration fallback", isOn: $model.settings.useMPS)
            }
            .help("Sets PYTORCH_ENABLE_MPS_FALLBACK for the local Kokoro process")
        }

        SettingsSection("Updates", footer: "Speech never uses the network; only this check does.") {
            SettingsRow("Check GitHub for new versions at launch") {
                SettingsSwitch(label: "Check GitHub for new versions at launch", isOn: $model.settings.checksForUpdates)
            }
            SettingsDivider()
            SettingsRow("Version") {
                HStack(spacing: AttenSpacing.sm) {
                    Text(model.isInstallingUpdate ? "Updating…" : model.appVersion)
                        .foregroundStyle(AttenColor.textSecondary)
                    if model.isCheckingForUpdate {
                        ProgressView().controlSize(.small)
                    }
                    Button("Check for Updates") {
                        Task { await model.checkForUpdate(manual: true) }
                    }
                    .buttonStyle(AttenSecondaryButtonStyle())
                    .disabled(model.isCheckingForUpdate || model.isInstallingUpdate)
                }
            }
            SettingsDivider()
            SettingsRow("Source code") {
                Button("View on GitHub") { openURL(UpdateChecker.repositoryURL) }
                    .buttonStyle(AttenTertiaryButtonStyle())
            }
        }
    }

    @ViewBuilder private var audioSections: some View {
        SettingsSection("Generation defaults") {
            SettingsRow("Voice") {
                Picker("Voice", selection: $model.selectedVoiceID) {
                    ForEach(VoiceCatalog.all) { voice in
                        let profile = VoiceProfile(voice: voice)
                        Text("\(profile.displayName) — \(profile.accent)").tag(voice.id)
                    }
                }
                .labelsHidden()
                .frame(width: 270)
            }
            SettingsDivider()
            SettingsRow("Speech speed") {
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
            SettingsDivider()
            SettingsRow("File format") {
                Picker("File format", selection: $model.format) {
                    ForEach(AudioFormat.allCases) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
            }
        }
    }

    @ViewBuilder private var storageSections: some View {
        SettingsSection("Generated audio") {
            SettingsRow("Export folder") {
                HStack(spacing: AttenSpacing.xs) {
                    Text(model.settings.outputDirectory)
                        .font(AttenTypography.callout)
                        .foregroundStyle(AttenColor.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 290, alignment: .trailing)
                    Button("Choose…") { model.chooseOutputDirectory() }
                        .buttonStyle(AttenSecondaryButtonStyle())
                    Button("Show in Finder") { model.openSaveFolder() }
                        .buttonStyle(AttenSecondaryButtonStyle())
                }
            }
        }
    }

    @ViewBuilder private var appearanceSections: some View {
        SettingsSection("Light or dark") {
            SettingsRow("Appearance") {
                Picker("Appearance", selection: $model.settings.appearance) {
                    ForEach(AppearancePreference.allCases) { appearance in
                        Text(appearance.displayName).tag(appearance)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
            }
        }
    }

    @ViewBuilder private var shortcutsSections: some View {
        shortcuts("Create", [
            ("New", "⌘N"),
            ("Add to Library", "⌘O"),
            ("Import into Create", "⌘I"),
            ("Generate speech", "⌘↩"),
            ("Export current audio", "⇧⌘E"),
        ])
        shortcuts("Library and reader", [
            ("Open Library", "⌘1"),
            ("Open Voices", "⌘2"),
            ("Open Settings", "⌘,"),
            ("Search the Library", "⌘F"),
            ("Find in book", "⌘F"),
        ])
        shortcuts("Playback", [
            ("Play or pause", "Space"),
            ("Play or pause (anywhere)", "⌥Space"),
            ("Skip back 15 seconds", "←"),
            ("Skip forward 15 seconds", "→"),
            ("Bookmark the sentence playing", "⌘D"),
            ("Cancel generation", "Esc"),
        ])
    }

    private func shortcuts(_ title: String, _ rows: [(action: String, keys: String)]) -> some View {
        SettingsSection(title) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 { SettingsDivider() }
                ShortcutRow(action: row.action, keys: row.keys)
            }
        }
    }
}

/// Where the title and every section start, and how wide they may grow.
enum SettingsColumn {
    static let gutter = AttenSpacing.xl
    static let maxWidth: CGFloat = 720
}

private struct SettingsPane<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AttenSpacing.lg) {
                content
            }
            .frame(maxWidth: SettingsColumn.maxWidth, alignment: .leading)
            .padding(.horizontal, SettingsColumn.gutter)
            .padding(.top, AttenSpacing.xs)
            .attenScrollPadding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A titled card of rows, as a grouped form draws one but on the page's own
/// column.
private struct SettingsSection<Content: View>: View {
    let title: String
    var footer: String?
    @ViewBuilder let content: Content

    init(_ title: String, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: AttenRadius.card, style: .continuous)
        VStack(alignment: .leading, spacing: AttenSpacing.xs) {
            Text(title)
                .attenText(.label)
                .foregroundStyle(AttenColor.text3)
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .padding(.horizontal, AttenSpacing.md)
            .background(AttenColor.surface1, in: shape)
            .overlay { shape.strokeBorder(AttenColor.hairline, lineWidth: 1) }
            if let footer {
                Text(footer)
                    .attenText(.callout)
                    .foregroundStyle(AttenColor.text2)
                    .lineLimit(1)
            }
        }
    }
}

private struct SettingsRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        HStack(spacing: AttenSpacing.md) {
            Text(label).foregroundStyle(AttenColor.text1)
            Spacer(minLength: 0)
            content
        }
        .frame(minHeight: 44)
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Rectangle().fill(AttenColor.hairline).frame(height: 1)
    }
}

/// A switch whose label is the row it sits in.
private struct SettingsSwitch: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(label, isOn: $isOn)
            .toggleStyle(AttenSwitchStyle())
    }
}

/// The system switch's off track nearly vanishes on a light card, so Atten
/// draws its own: off is a `text3` track, which holds 3:1 against the card in
/// both appearances, and on is `signal`, a selected control.
private struct AttenSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        AttenSwitch(configuration: configuration)
    }
}

private struct AttenSwitch: View {
    let configuration: ToggleStyleConfiguration
    @Environment(\.attenReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let isOn = configuration.isOn
        Button { configuration.isOn.toggle() } label: {
            Capsule()
                .fill(isOn ? AttenColor.signal : AttenColor.text3)
                .frame(width: 32, height: 18)
                .overlay(alignment: .leading) {
                    Circle()
                        .fill(AttenColor.surface1)
                        .frame(width: 14, height: 14)
                        .offset(x: isOn ? 16 : 2)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : AttenState.disabledOpacity)
        .attenFocusRing(cornerRadius: 9)
        .animation(AttenMotion.animation(.small, reduceMotion: reduceMotion), value: isOn)
        .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
    }
}

private struct ShortcutRow: View {
    let action: String
    let keys: String

    var body: some View {
        SettingsRow(action) {
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
