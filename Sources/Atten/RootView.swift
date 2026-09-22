import AppKit
import AttenCore
import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case home
    case nowPlaying
    case library
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
        case .home: "house"
        case .nowPlaying: "waveform.circle"
        case .library: "books.vertical"
        case .studio: "waveform"
        case .playground: "flask"
        case .voices: "person.2"
        case .models: "shippingbox"
        case .projects: "doc.on.doc"
        case .exports: "waveform.badge.magnifyingglass"
        }
    }

    /// Where a destination sits in the sidebar.
    ///
    /// The wireframe's calm comes partly from a short list. Every destination
    /// Atten had is still here and still one click away — the ones you reach
    /// for while listening are simply not mixed in with the ones you reach for
    /// while managing voices and files.
    enum Group: String, CaseIterable, Identifiable {
        case read
        case create
        case manage

        var id: String { rawValue }

        /// The places you go while reading need no heading — they are the top
        /// of the list and there are two of them. The rest are shelves, and a
        /// shelf is easier to skip past when it is named.
        var title: String? {
            switch self {
            case .read: nil
            case .create: "Create"
            case .manage: "Manage"
            }
        }

        var items: [SidebarItem] {
            switch self {
            case .read: [.home, .nowPlaying, .library]
            case .create: [.studio, .playground]
            case .manage: [.voices, .models, .projects, .exports]
            }
        }
    }
}

extension Notification.Name {
    static let attenOpenStudio = Notification.Name("Atten.openStudio")
    static let attenOpenPlayground = Notification.Name("Atten.openPlayground")
}

struct RootView: View {
    @Bindable var model: AppModel
    @SceneStorage("Atten.selectedSection") private var restoredSection = SidebarItem.home.rawValue
    @SceneStorage("Atten.studioDraft") private var restoredDraft = ""
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var screenTitle: AttenScreenTitle?
    @FocusState private var focusedSidebarItem: SidebarItem?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 196, ideal: 208, max: 232)
        } detail: {
            ZStack(alignment: .top) {
                AttenBackdrop()
                AttenAtmosphere()
                detail
            }
            .onAttenScreenTitle { screenTitle = $0 }
            .safeAreaInset(edge: .top, spacing: 0) {
                TopChrome(model: model, title: screenTitle)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .preferredColorScheme(preferredColorScheme)
        .tint(AttenColor.accent)
        .font(AttenTypography.body)
        .foregroundStyle(AttenColor.textPrimary)
        .background(WindowTitleHider())
        .toolbarBackground(AttenColor.appBackground, for: .windowToolbar)
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
            model.section = SidebarItem(rawValue: restoredSection) ?? .home
            if model.draftText.isEmpty { model.draftText = restoredDraft }
            await model.start()
        }
        .onChange(of: model.section) { _, section in restoredSection = section.rawValue }
        // A scene-storage write goes to disk, and this one carried up to
        // 100 KB. Running it on every keystroke made typing in Studio stutter,
        // so it waits for the typing to stop.
        .task(id: model.draftText) {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            restoredDraft = String(model.draftText.prefix(100_000))
        }
        // …and whatever the pause has not caught yet is written on the way out.
        .onReceive(
            NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
        ) { _ in
            restoredDraft = String(model.draftText.prefix(100_000))
        }
        .onReceive(NotificationCenter.default.publisher(for: .attenOpenStudio)) { _ in
            model.section = .studio
        }
        .onReceive(NotificationCenter.default.publisher(for: .attenOpenPlayground)) { _ in
            model.section = .playground
        }
        .onChange(of: model.isReaderFocused) { _, isFocused in
            withAnimation(reduceMotion ? nil : .easeInOut(duration: AttenMotion.standard)) {
                columnVisibility = isFocused ? .detailOnly : .all
            }
        }
        // Leaving full screen by the green button, Mission Control, or the
        // system shortcut is the same intent as leaving focus mode. Without
        // this the sidebar stayed hidden with no way left to bring it back.
        .onReceive(
            NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)
        ) { _ in
            model.setReaderFocus(false)
        }
        .mouseNavigationButtons(back: model.goBack)
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

            VStack(alignment: .leading, spacing: AttenSpacing.md) {
                ForEach(SidebarItem.Group.allCases) { group in
                    VStack(alignment: .leading, spacing: 1) {
                        if let title = group.title {
                            Text(title.uppercased())
                                .font(AttenTypography.caption.weight(.semibold))
                                .tracking(1.1)
                                .foregroundStyle(AttenColor.textSecondary)
                                .padding(.horizontal, AttenSpacing.sm)
                                .padding(.bottom, AttenSpacing.xxs)
                        }
                        ForEach(group.items) { item in
                            SidebarNavigationRow(
                                item: item,
                                isSelected: model.section == item
                            ) {
                                model.section = item
                                focusedSidebarItem = item
                            }
                            .focused($focusedSidebarItem, equals: item)
                        }
                    }
                }
            }
            .padding(.horizontal, AttenSpacing.xs)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onMoveCommand(perform: moveSidebarSelection)
            .accessibilityLabel("Sections")

            Divider()
                .overlay(AttenColor.separator)

            StatusIndicator(
                title: "\(model.library.installed.count) voices installed",
                detail: model.backendIsAvailable ? "Ready" : "Offline",
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

                appearanceMenu

                Button {
                    model.openSaveFolder()
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 12, weight: .medium))
                }
                .help("Open the folder Atten saves into")
                .accessibilityLabel("Open save folder")

                Spacer(minLength: 0)
                Text(model.isInstallingUpdate ? "UPDATING…" : "v\(model.appVersion)")
                    .font(AttenTypography.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(AttenColor.textSecondary)
            .padding(.horizontal, AttenSpacing.md)
            .padding(.vertical, AttenSpacing.sm)
        }
        .background(AttenColor.sidebar.opacity(0.6))
        .background(.ultraThinMaterial)
    }

    /// How Atten looks, which is now one decision rather than two: there is a
    /// single palette, and this picks which side of it the window is drawn in.
    /// Here rather than only in Settings because it is a choice people make by
    /// trying it.
    private var appearanceMenu: some View {
        Menu {
            Picker("Appearance", selection: appearanceSelection) {
                ForEach(AppearancePreference.allCases) { appearance in
                    Label(appearance.displayName, systemImage: appearance.icon)
                        .tag(appearance)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: model.settings.appearance.icon)
                .font(.system(size: 12, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Appearance: \(appearanceSummary)")
        .accessibilityLabel("Appearance")
        .accessibilityValue(appearanceSummary)
    }

    private var appearanceSummary: String {
        model.settings.appearance.displayName
    }

    private var appearanceSelection: Binding<AppearancePreference> {
        Binding(
            get: { model.settings.appearance },
            set: { model.selectAppearance($0) }
        )
    }

    @ViewBuilder private var detail: some View {
        switch model.section {
        case .home:
            HomeView(model: model)
        case .nowPlaying:
            NowPlayingView(model: model)
        case .studio:
            StudioView(model: model)
        case .playground:
            PlaygroundView(model: model) { model.section = .studio }
        case .library:
            LibraryView(model: model)
        case .voices:
            VoicesView(model: model) { model.section = .studio }
        case .models:
            ModelsView(model: model)
        case .projects:
            ProjectsView(model: model) { model.section = .studio }
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
        model.section = .studio
    }

    private func moveSidebarSelection(_ direction: MoveCommandDirection) {
        guard direction == .up || direction == .down else { return }
        let items = SidebarItem.allCases
        let selected = focusedSidebarItem ?? model.section
        guard let index = items.firstIndex(of: selected) else { return }
        let offset = direction == .down ? 1 : -1
        let nextIndex = min(max(index + offset, items.startIndex), items.index(before: items.endIndex))
        let next = items[nextIndex]
        focusedSidebarItem = next
        model.section = next
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
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18)
                Text(item.label)
                    .font(AttenTypography.control)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? AttenColor.accent : AttenColor.textPrimary)
            .padding(.horizontal, AttenSpacing.sm)
            .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: AttenRadius.control, style: .continuous))
            .overlay(alignment: .leading) {
                if isSelected {
                    Capsule()
                        .fill(AttenColor.accent)
                        .frame(width: 2.5, height: 16)
                        .offset(x: -6)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: AttenRadius.control, style: .continuous)
                    .stroke(borderColor, lineWidth: AttenState.focusRingWidth)
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

    /// Selection is carried by the accent ink, not by a filled pill. A list
    /// where the current row is a block of colour reads as a set of buttons;
    /// Apple Music tints the label and leaves the row alone, and a sidebar
    /// that sits beside a page of prose all day should do the same. Only the
    /// pointer gets a fill, and barely.
    private var background: Color {
        if isSelected { return AttenColor.accent.opacity(0.07) }
        return isHovering ? AttenColor.textPrimary.opacity(AttenState.hoverFill / 2) : .clear
    }

    /// Only focus draws an edge. Selection is carried by the fill and the
    /// accent ink, so a list at rest has one mark on it rather than two.
    private var borderColor: Color {
        isFocused ? AttenColor.focus : .clear
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

@MainActor
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

/// The back and forward buttons on a mouse arrive as `otherMouseDown`, and
/// nothing in SwiftUI claims them.
///
/// Left unclaimed they fell through to whatever happened to be under the
/// pointer, so a press in a split view with a nested stack inside it produced a
/// pop that the rest of the interface never heard about — the sidebar, the
/// player, and the reader all kept believing the book was still open. Claimed
/// here, and swallowed, the press means exactly one thing wherever it lands.
private struct MouseNavigationButtons: ViewModifier {
    let back: () -> Void

    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard monitor == nil else { return }
                monitor = NSEvent.addLocalMonitorForEvents(matching: .otherMouseDown) { event in
                    // 3 and 4 are the back and forward buttons on every mouse
                    // that has them. Atten has nowhere forward to go.
                    // A confirmation the user has not answered yet is not a
                    // screen to be navigated out from under.
                    guard event.window?.attachedSheet == nil else { return event }
                    switch event.buttonNumber {
                    case 3:
                        back()
                        return nil
                    case 4:
                        return nil
                    default:
                        return event
                    }
                }
            }
            .onDisappear {
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
            }
    }
}

extension View {
    func mouseNavigationButtons(back: @escaping () -> Void) -> some View {
        modifier(MouseNavigationButtons(back: back))
    }
}

/// The shell's top chrome.
///
/// One region, owned here, holding the screen's name and — once #26 lands —
/// the global compact player. It exists now so that the player has somewhere
/// to go that is not the bottom of the reader, and so screens can start
/// handing their titles up one at a time.
///
/// A screen that has not migrated says nothing, and this collapses to nothing
/// rather than drawing an empty bar above its own header.
private struct TopChrome: View {
    @Bindable var model: AppModel
    let title: AttenScreenTitle?

    /// Either a screen that named itself or something playing is enough to
    /// draw the row. Neither, and there is no bar at all — a reader with no
    /// narration loses no page to chrome it is not using.
    private var isPresent: Bool { title != nil || model.playerTitle != nil }

    var body: some View {
        if isPresent {
            HStack(alignment: .center, spacing: AttenSpacing.sm) {
                VStack(alignment: .leading, spacing: 0) {
                    if let title {
                    Text(title.title)
                        .font(title.isProminent
                            ? AttenTypography.displayTitle
                            : AttenTypography.pageTitle)
                        .foregroundStyle(AttenColor.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if let subtitle = title.subtitle {
                        Text(subtitle)
                            .font(title.isProminent
                                ? AttenTypography.body
                                : AttenTypography.metadata)
                            .foregroundStyle(AttenColor.textSecondary)
                            .lineLimit(1)
                    }
                    }
                }

                Spacer(minLength: AttenSpacing.md)

                GlobalPlayer(model: model)
            }
            .padding(.horizontal, AttenSpacing.page)
            .padding(.top, AttenSpacing.lg)
            .padding(.bottom, AttenSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(AttenColor.separator.opacity(0.5))
                    .frame(height: 0.5)
            }
            .accessibilityElement(children: .contain)
        }
    }
}
