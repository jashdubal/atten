import AttenCore
import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case studio
    case playground
    case voices
    case projects
    case exports

    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    var icon: String {
        switch self {
        case .studio: "waveform"
        case .playground: "flask"
        case .voices: "person.2"
        case .projects: "doc.on.doc"
        case .exports: "waveform.badge.magnifyingglass"
        }
    }
}

extension Notification.Name {
    static let attenOpenStudio = Notification.Name("Atten.openStudio")
    static let attenOpenPlayground = Notification.Name("Atten.openPlayground")
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
                .navigationSplitViewColumnWidth(min: 220, ideal: 228, max: 248)
        } detail: {
            ZStack {
                AttenBackdrop()
                detail
            }
        }
        .navigationSplitViewStyle(.balanced)
        .preferredColorScheme(preferredColorScheme)
        .tint(AttenColor.accent)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                AttenLogo(compact: true)
            }
            ToolbarItem(placement: .primaryAction) {
                ToolbarIconButton(
                    title: "New Studio draft (⌘N)",
                    systemImage: "square.and.pencil"
                ) {
                    openNewDraft()
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
        .onReceive(NotificationCenter.default.publisher(for: .attenOpenStudio)) { _ in
            selectionRaw = SidebarItem.studio.rawValue
        }
        .onReceive(NotificationCenter.default.publisher(for: .attenOpenPlayground)) { _ in
            selectionRaw = SidebarItem.playground.rawValue
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
                .padding(.horizontal, AttenSpacing.md)
                .padding(.top, AttenSpacing.md)
                .padding(.bottom, AttenSpacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)

            List(selection: selection) {
                Section {
                    ForEach(SidebarItem.allCases) { item in
                        Label(item.label, systemImage: item.icon)
                            .font(.system(size: 13, weight: .medium))
                            .frame(minHeight: 32)
                            .tag(item)
                            .listRowInsets(
                                EdgeInsets(top: 1, leading: 10, bottom: 1, trailing: 10)
                            )
                            .accessibilityHint("Open \(item.label)")
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            Divider()
                .overlay(AttenColor.separator)

            StatusIndicator(
                title: "Kokoro 82M",
                detail: model.backendIsAvailable ? "Local backend ready" : "Backend not found",
                isAvailable: model.backendIsAvailable
            )
            .padding(AttenSpacing.md)
        }
        .background(AttenColor.sidebar)
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

    private func openNewDraft() {
        model.newDraft()
        selectionRaw = SidebarItem.studio.rawValue
    }
}
