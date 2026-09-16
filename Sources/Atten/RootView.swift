import AppKit
import AttenCore
import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case studio
    case playground
    case voices
    case models
    case projects
    case exports

    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    var icon: String {
        switch self {
        case .studio: "waveform"
        case .playground: "flask"
        case .voices: "person.2"
        case .models: "shippingbox"
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
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if model.playerTitle != nil {
                    PlayerBar(model: model)
                }
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
        .alert(
            "Atten \(model.availableUpdate?.version ?? "") is available",
            isPresented: updateAlert
        ) {
            Button("Install and Relaunch") { model.installUpdate() }
            Button("Later", role: .cancel) { model.availableUpdate = nil }
        } message: {
            Text("You have \(model.appVersion). The update downloads in the background and Atten relaunches when it is ready.")
        }
        .alert("Check for updates", isPresented: updateMessageAlert) {
            Button("OK", role: .cancel) { model.updateMessage = nil }
        } message: {
            Text(model.updateMessage ?? "")
        }
        .alert("Update failed", isPresented: updateErrorAlert) {
            Button("OK", role: .cancel) { model.updateError = nil }
        } message: {
            Text(model.updateError ?? "Unknown error")
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
                title: "\(model.library.installed.count) MODELS",
                detail: model.backendIsAvailable ? "STATUS: READY" : "STATUS: OFFLINE",
                isAvailable: model.backendIsAvailable
            )
            .padding([.horizontal, .top], AttenSpacing.md)

            HStack(spacing: AttenSpacing.sm) {
                Link(destination: UpdateChecker.repositoryURL) {
                    Image(nsImage: GitHubMark.image)
                        .resizable()
                        .frame(width: 14, height: 14)
                }
                .help("View source code on GitHub")
                .accessibilityLabel("Source code on GitHub")

                Button {
                    Task { await model.checkForUpdate(manual: true) }
                } label: {
                    if model.isCheckingForUpdate {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .medium))
                    }
                }
                .disabled(model.isCheckingForUpdate || model.isInstallingUpdate)
                .help("Check for updates")
                .accessibilityLabel("Check for updates")

                Spacer(minLength: 0)
                Text(model.isInstallingUpdate ? "UPDATING…" : "v\(model.appVersion)")
                    .font(AttenTypography.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(AttenColor.textSecondary)
            .padding(.horizontal, AttenSpacing.md)
            .padding(.vertical, AttenSpacing.sm)
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
        case .models:
            ModelsView(model: model)
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

    private var updateAlert: Binding<Bool> {
        Binding(
            get: { model.availableUpdate != nil && !model.isInstallingUpdate },
            set: { _ in }
        )
    }

    private var updateMessageAlert: Binding<Bool> {
        Binding(
            get: { model.updateMessage != nil },
            set: { if !$0 { model.updateMessage = nil } }
        )
    }

    private var updateErrorAlert: Binding<Bool> {
        Binding(
            get: { model.updateError != nil },
            set: { if !$0 { model.updateError = nil } }
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

private enum GitHubMark {
    static let image: NSImage = {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16"><path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z"/></svg>
        """
        let image = NSImage(data: Data(svg.utf8)) ?? NSImage()
        image.isTemplate = true
        return image
    }()
}
