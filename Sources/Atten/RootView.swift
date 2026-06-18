import AttenCore
import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case studio
    case voices
    case projects
    case exports
    case settings

    var id: String { rawValue }

    var label: String { rawValue.capitalized }

    var icon: String {
        switch self {
        case .studio: "waveform.badge.mic"
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

    private var selection: Binding<SidebarItem?> {
        Binding(
            get: { SidebarItem(rawValue: selectionRaw) ?? .studio },
            set: { selectionRaw = ($0 ?? .studio).rawValue }
        )
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 190, ideal: 215, max: 250)
        } detail: {
            ZStack {
                ForestBackdrop()
                detail
            }
        }
        .preferredColorScheme(preferredColorScheme)
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
                        .tag(item)
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

    private var startupAlert: Binding<Bool> {
        Binding(
            get: { model.startupError != nil },
            set: { if !$0 { model.startupError = nil } }
        )
    }
}
