import AttenCore
import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case studio
    case playground
    case voices
    case projects
    case exports
    case settings

    var id: String { rawValue }

    var label: String { rawValue.capitalized }

    var icon: String {
        switch self {
        case .studio: "waveform.badge.mic"
        case .playground: "flask"
        case .voices: "person.wave.2"
        case .projects: "square.stack.3d.up"
        case .exports: "arrow.up.doc"
        case .settings: "gearshape"
        }
    }
}

struct RootView: View {
    @Bindable var model: AppModel
    @SceneStorage("Atten.selectedSection") private var selectionRaw = SidebarItem.studio.rawValue
    @SceneStorage("Atten.studioDraft") private var restoredDraft = ""
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showsShortcuts = false

    private var selection: Binding<SidebarItem?> {
        Binding(
            get: { SidebarItem(rawValue: selectionRaw) ?? .studio },
            set: { selectionRaw = ($0 ?? .studio).rawValue }
        )
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 172, ideal: 184, max: 210)
        } detail: {
            ZStack {
                ForestBackdrop()
                detail
            }
        }
        .preferredColorScheme(preferredColorScheme)
        .tint(AttenColor.forest)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                AttenLogo(compact: true)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    model.newDraft()
                    selectionRaw = SidebarItem.studio.rawValue
                } label: {
                    Label("New Draft", systemImage: "square.and.pencil")
                }
                .help("New draft (⌘N)")

                Button {
                    model.openImportPanel()
                    selectionRaw = SidebarItem.studio.rawValue
                } label: {
                    Label("Import", systemImage: "doc.badge.plus")
                }
                .help("Import text (⌘O)")

                Button {
                    selectionRaw = SidebarItem.studio.rawValue
                } label: {
                    Label("Studio", systemImage: "waveform.badge.mic")
                }
                .keyboardShortcut("1")
                .help("Open Studio (⌘1)")

                Button {
                    selectionRaw = SidebarItem.playground.rawValue
                } label: {
                    Label("Playground", systemImage: "flask")
                }
                .keyboardShortcut("2")
                .help("Open Playground (⌘2)")

                Button {
                    model.generate()
                    selectionRaw = SidebarItem.studio.rawValue
                } label: {
                    Label("Generate", systemImage: "sparkles")
                }
                .disabled(
                    model.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || model.isGenerating
                        || model.isPlaygroundGenerating
                )
                .help("Generate speech (⌘↩)")

                Button { model.togglePlayback(url: toolbarAudioURL) } label: {
                    Label(model.isPlaying ? "Pause" : "Play", systemImage: model.isPlaying ? "pause.fill" : "play.fill")
                }
                .disabled(toolbarAudioURL == nil)
                .help("Play or pause (⌥Space)")

                Button { model.exportCurrent() } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .disabled(model.currentAudioURL == nil)
                .help("Export current audio (⇧⌘E)")

                if model.isGenerating || model.isPlaygroundGenerating {
                    Button(role: .cancel) { model.cancelGeneration() } label: {
                        Label("Cancel", systemImage: "stop.fill")
                    }
                    .help("Cancel generation (Esc)")
                }

                Button { showsShortcuts.toggle() } label: {
                    Label("Shortcuts", systemImage: "keyboard")
                }
                .help("Show keyboard shortcuts")
                .popover(isPresented: $showsShortcuts, arrowEdge: .bottom) {
                    ShortcutGuide()
                }
            }
        }
        .task {
            if model.draftText.isEmpty { model.draftText = restoredDraft }
            await model.start()
        }
        .onChange(of: model.draftText) { _, newValue in
            restoredDraft = String(newValue.prefix(100_000))
        }
        .alert("Atten could not finish starting", isPresented: startupAlert) {
            Button("OK", role: .cancel) { model.startupError = nil }
        } message: {
            Text(model.startupError ?? "Unknown error")
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            AttenLogo()
                .padding(.horizontal, 14)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)

            List(selection: selection) {
                ForEach(SidebarItem.allCases) { item in
                    Label(item.label, systemImage: item.icon)
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .tag(item)
                        .listRowBackground(
                            selectionRaw == item.rawValue
                                ? AttenColor.sunlight.opacity(0.16)
                                : Color.clear
                        )
                        .accessibilityHint("Open \(item.label)")
                }
            }
            .listStyle(.sidebar)

            HStack(spacing: 8) {
                Circle()
                    .fill(model.backendIsAvailable ? AttenColor.forest : AttenColor.berry)
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Kokoro • Offline")
                        .font(.caption.weight(.semibold))
                    Text(model.backendIsAvailable ? "Backend ready" : "Backend not found")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(14)
            .accessibilityElement(children: .combine)
        }
        .background(AttenColor.surface)
    }

    @ViewBuilder private var detail: some View {
        switch SidebarItem(rawValue: selectionRaw) ?? .studio {
        case .studio:
            StudioView(model: model)
        case .playground:
            PlaygroundView(model: model) { selectionRaw = SidebarItem.studio.rawValue }
        case .voices:
            VoicesView(model: model) { selectionRaw = SidebarItem.studio.rawValue }
        case .projects:
            ProjectsView(model: model) { selectionRaw = SidebarItem.studio.rawValue }
        case .exports:
            ExportsView(model: model)
        case .settings:
            SettingsView(model: model)
        }
    }

    private var preferredColorScheme: ColorScheme? {
        switch model.settings.appearance {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    private var toolbarAudioURL: URL? {
        if selectionRaw == SidebarItem.playground.rawValue {
            return model.playgroundAudioURL
        }
        return model.currentAudioURL
    }

    private var startupAlert: Binding<Bool> {
        Binding(
            get: { model.startupError != nil },
            set: { if !$0 { model.startupError = nil } }
        )
    }
}

private struct ShortcutGuide: View {
    private let shortcuts = [
        ("New draft", "⌘N"),
        ("Import text", "⌘O"),
        ("Open Studio", "⌘1"),
        ("Open Playground", "⌘2"),
        ("Generate speech", "⌘↩"),
        ("Create temp sample", "⌥⌘↩"),
        ("Play or pause", "⌥Space"),
        ("Cancel generation", "Esc"),
        ("Export audio", "⇧⌘E"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Atten shortcuts", systemImage: "keyboard")
                .font(.headline)
            Divider()
            ForEach(shortcuts, id: \.0) { shortcut in
                HStack {
                    Text(shortcut.0)
                    Spacer()
                    Text(shortcut.1)
                        .font(.system(.callout, design: .monospaced, weight: .semibold))
                        .foregroundStyle(AttenColor.forest)
                }
            }
        }
        .padding(16)
        .frame(width: 260)
    }
}
