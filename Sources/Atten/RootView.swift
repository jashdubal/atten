import AppKit
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
    @FocusState private var focusedSidebarItem: SidebarItem?

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
        .font(AttenTypography.body)
        .foregroundStyle(AttenColor.textPrimary)
        .background(WindowTitleHider())
        .toolbar {
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

            VStack(spacing: 2) {
                ForEach(SidebarItem.allCases) { item in
                    SidebarNavigationRow(
                        item: item,
                        isSelected: selectionRaw == item.rawValue
                    ) {
                        selectionRaw = item.rawValue
                        focusedSidebarItem = item
                    }
                    .focused($focusedSidebarItem, equals: item)
                }
            }
            .padding(.horizontal, AttenSpacing.xs)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onMoveCommand(perform: moveSidebarSelection)

            Divider()
                .overlay(AttenColor.separator)

            StatusIndicator(
                title: "KOKORO_82M",
                detail: model.backendIsAvailable ? "STATUS: READY" : "STATUS: OFFLINE",
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

    private func moveSidebarSelection(_ direction: MoveCommandDirection) {
        guard direction == .up || direction == .down else { return }
        let items = SidebarItem.allCases
        let selected = focusedSidebarItem ?? SidebarItem(rawValue: selectionRaw) ?? .studio
        guard let index = items.firstIndex(of: selected) else { return }
        let offset = direction == .down ? 1 : -1
        let nextIndex = min(max(index + offset, items.startIndex), items.index(before: items.endIndex))
        let next = items[nextIndex]
        focusedSidebarItem = next
        selectionRaw = next.rawValue
    }
}

private struct SidebarNavigationRow: View {
    let item: SidebarItem
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.isFocused) private var isFocused
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: AttenSpacing.sm) {
                Image(systemName: item.icon)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .frame(width: 18)
                Text(item.label.uppercased())
                    .font(AttenTypography.control)
                Spacer(minLength: 0)
                if isSelected {
                    Text(">")
                        .font(AttenTypography.control.weight(.bold))
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(isSelected ? AttenColor.accentHover : AttenColor.textPrimary)
            .padding(.horizontal, AttenSpacing.sm)
            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: AttenRadius.control))
            .overlay {
                RoundedRectangle(cornerRadius: AttenRadius.control)
                    .stroke(borderColor, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { isHovering = $0 }
        .accessibilityLabel(item.label)
        .accessibilityHint("Open \(item.label)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var background: Color {
        if isSelected { return AttenColor.accent.opacity(0.14) }
        if isHovering { return AttenColor.surfaceMuted.opacity(0.72) }
        return .clear
    }

    private var borderColor: Color {
        if isFocused { return AttenColor.focus }
        if isSelected { return AttenColor.accent.opacity(0.55) }
        return .clear
    }
}

private struct WindowTitleHider: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        WindowTitleHidingView()
    }

    func updateNSView(_ view: NSView, context: Context) {
        view.window?.titleVisibility = .hidden
    }
}

private final class WindowTitleHidingView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.titleVisibility = .hidden
    }
}
