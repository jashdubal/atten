import AppKit
import AttenCore
import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case library
    case voices
    case settings
    /// Create is a verb, not a place: it opens full-window from "+ New" or
    /// ⌘N and is never a row in the sidebar.
    case studio
    /// Opened from the player, over whichever place it was opened from.
    case nowPlaying

    var id: String { rawValue }
    var label: String { self == .studio ? "Create" : (self == .nowPlaying ? "Now Playing" : rawValue.capitalized) }
    static let primaryItems: [SidebarItem] = [.library, .voices, .settings]
    /// The sidebar row that stands for this screen.
    var workspace: SidebarItem {
        switch self {
        case .studio, .nowPlaying: .library
        default: self
        }
    }

    /// Scene storage from every earlier shell lands somewhere that still
    /// exists. Home, Now Playing, Draft, Projects, Exports and the playground
    /// all live in the Library now, and Models is a tab in Settings. Create is
    /// never restored: it opens only through "+ New".
    static func restored(_ raw: String) -> SidebarItem {
        switch raw {
        case "voices": .voices
        case "settings", "models": .settings
        default: .library
        }
    }

    var icon: String {
        switch self {
        case .library: "books.vertical"
        case .voices: "person.2"
        case .settings: "gearshape"
        case .studio: "waveform"
        case .nowPlaying: "waveform.circle"
        }
    }
}

extension Notification.Name {
    static let attenOpenStudio = Notification.Name("Atten.openStudio")
}

struct RootView: View {
    @Bindable var model: AppModel
    @SceneStorage("Atten.selectedSection") private var restoredSection = SidebarItem.library.rawValue
    @SceneStorage("Atten.studioDraft") private var restoredDraft = ""
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var screenTitle: AttenScreenTitle?
    @Namespace private var playerNamespace
    @Namespace private var coverNamespace
    @FocusState private var focusedSidebarItem: SidebarItem?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
                .toolbar(removing: model.section == .studio ? .sidebarToggle : nil)
        } detail: {
            ZStack(alignment: .top) {
                AttenBackdrop()
                animatedDetail
            }
            .environment(\.attenCoverNamespace, coverNamespace)
            .attenAmbientField(model)
            .overlay(alignment: .top) {
                CreateToast(flow: model.createFlow).padding(.top, AttenSpacing.sm)
            }
            .onAttenScreenTitle { screenTitle = $0 }
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    TopChrome(model: model, title: screenTitle)
                    // Create shows its own narration in its inspector.
                    if let activity = model.synthesis.activity, model.section != .studio {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text(activity).font(AttenTypography.callout)
                            Spacer()
                            Button("Stop") {
                                if model.bookshelf.isNarrating { model.bookshelf.cancelNarration() }
                                else { model.cancelGeneration() }
                            }
                            .controlSize(.small)
                        }
                        .padding(.horizontal, 24).padding(.vertical, 8)
                        .background(AttenColor.surface)
                    }
                    if model.isExportingBook {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("Exporting audiobook…").font(AttenTypography.callout)
                            Spacer()
                        }.padding(.horizontal, 24).padding(.vertical, 8)
                    }
                }
            }
            // Floats over the content column rather than taking a strip of
            // it; every scroll view leaves room under its last row with
            // `attenScrollPadding()`.
            .overlay(alignment: .bottom) {
                // Now Playing is the player grown to the whole window.
                if (model.playerTitle != nil || model.progressivePlayer.bookID != nil), model.section != .nowPlaying {
                    GlobalPlayer(model: model, isCompact: model.section == .studio, namespace: playerNamespace)
                        .padding(.horizontal, AttenSpacing.lg)
                        .padding(.bottom, AttenSpacing.sm)
                }
            }
            .animation(AttenMotion.animation(.large, reduceMotion: reduceMotion), value: model.section == .studio)
            .animation(AttenMotion.animation(.large, reduceMotion: reduceMotion), value: model.section == .nowPlaying)
        }
        .navigationSplitViewStyle(.balanced)
        .preferredColorScheme(preferredColorScheme)
        .tint(AttenColor.signal)
        .font(AttenTypography.body)
        .foregroundStyle(AttenColor.textPrimary)
        .background(WindowTitleHider())
        .toolbarBackground(AttenColor.appBackground, for: .windowToolbar)
        .task {
            model.section = SidebarItem.restored(restoredSection)
            await model.start()
            // Drafts are books on the shelf now. The last Studio draft, kept
            // here before they were, is put there once and then let go.
            if !restoredDraft.isEmpty, model.createFlow.importLegacyDraft(restoredDraft) {
                restoredDraft = ""
            }
        }
        .onChange(of: model.section) { oldSection, section in
            restoredSection = section.rawValue
            screenTitle = nil
            // Create takes the whole window, and gives the sidebar back on
            // the way out.
            if section == .studio || oldSection == .studio {
                withAnimation(AttenMotion.animation(AttenMotion.transition, reduceMotion: reduceMotion)) {
                    columnVisibility = section == .studio ? .detailOnly : .all
                }
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
        ) { _ in
            model.createFlow.saveNow()
            model.saveListeningPosition()
        }
        .onReceive(NotificationCenter.default.publisher(for: .attenOpenStudio)) { _ in
            model.section = .studio
        }
        .onChange(of: model.isReaderFocused) { _, isFocused in
            withAnimation(AttenMotion.animation(AttenMotion.transition, reduceMotion: reduceMotion)) {
                columnVisibility = isFocused ? .detailOnly : .all
            }
        }
        // Leaving full screen by the green button, Mission Control, or the
        // system shortcut is the same intent as leaving focus mode. Without
        // this the sidebar stayed hidden with no way left to bring it back.
        .onReceive(
            NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)
        ) { note in
            // Full-screen notifications are process-wide. A sheet or another
            // window leaving full screen must not alter the reader's state.
            guard let window = note.object as? NSWindow,
                  window == NSApp?.keyWindow || window == NSApp?.mainWindow else { return }
            model.readerWindowDidExitFullScreen()
        }
        .mouseNavigationButtons(back: model.goBack)
        .attenKeyboardInteractionTracking()
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

    /// Peer sections dissolve in place; directional travel is reserved for
    /// opening a destination within a section.
    private var animatedDetail: some View {
        ZStack {
            detail
                .id(model.section)
                .transition(
                    AttenMotion.transition(
                        .fade,
                        reduceMotion: reduceMotion
                    )
                )
        }
        .animation(
            AttenMotion.transitionAnimation(AttenMotion.transition, reduceMotion: reduceMotion),
            value: model.section
        )
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Atten")
                .attenText(.label)
                .foregroundStyle(AttenColor.text3)
                .padding(.horizontal, AttenSpacing.sm)
                .padding(.top, AttenSpacing.md)
                .padding(.bottom, AttenSpacing.xxs)
                .accessibilityAddTraits(.isHeader)

            ForEach(SidebarItem.primaryItems) { item in
                SidebarNavigationRow(item: item, isSelected: model.section.workspace == item) {
                    if item == .library { model.returnToShelf() }
                    else { model.section = item }
                    focusedSidebarItem = item
                }
                .focused($focusedSidebarItem, equals: item)
            }

            Spacer(minLength: 0)
            NarrationQueueIndicator(model: model)
                .padding(.bottom, AttenSpacing.sm)
        }
        .padding(.horizontal, AttenSpacing.xs)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onMoveCommand(perform: moveSidebarSelection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sections")
        // No background of its own: the system's sidebar material shows
        // through, which is the only vibrancy the chrome needs.
    }

    @ViewBuilder private var detail: some View {
        switch model.section {
        case .library:
            LibraryView(model: model)
        case .voices:
            VoicesView(model: model) { model.section = .studio }
        case .settings:
            SettingsView(model: model)
        case .studio:
            CreateWorkspace(model: model, backTitle: model.sectionBeforeCreate.label) {
                model.leaveCreate()
            }
        case .nowPlaying:
            ReadAlongView(model: model, namespace: playerNamespace)
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

    private func moveSidebarSelection(_ direction: MoveCommandDirection) {
        guard direction == .up || direction == .down else { return }
        let items = SidebarItem.primaryItems
        let selected = focusedSidebarItem ?? model.section.workspace
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
    @Environment(\.attenHasUsedKeyboard) private var hasUsedKeyboard
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: AttenSpacing.sm) {
                Image(systemName: item.icon)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18)
                Text(item.label)
                    .font(AttenTypography.callout)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? AttenColor.textPrimary : AttenColor.textSecondary)
            .padding(.horizontal, AttenSpacing.sm)
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: AttenRadius.control, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AttenRadius.control, style: .continuous)
                    .stroke(borderColor, lineWidth: AttenState.focusRingWidth)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { isHovering = $0 }
        .animation(
            AttenMotion.animation(AttenMotion.fast, reduceMotion: reduceMotion),
            value: isSelected
        )
        .accessibilityLabel(item.label)
        .accessibilityHint("Open \(item.label)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Selection is a faint tint and nothing more: chrome carries no colour
    /// of its own. Keyboard focus keeps its own outline.
    private var background: Color {
        if isSelected { return AttenColor.textPrimary.opacity(AttenState.hoverFill) }
        return isHovering ? AttenColor.textPrimary.opacity(AttenState.hoverFill / 2) : .clear
    }

    /// Keyboard focus adds a visible outline without changing the selection.
    private var borderColor: Color {
        isFocused && hasUsedKeyboard ? AttenColor.focus : .clear
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

/// Compact screen heading. The reader supplies its own navigation strip.
private struct TopChrome: View {
    @Bindable var model: AppModel
    let title: AttenScreenTitle?

    private var isReader: Bool {
        guard model.section == .library else { return false }
        if case .reader = model.libraryPath.last { return true }
        return false
    }

    var body: some View {
        if title != nil && !isReader && !model.isReaderFocused {
            heading
                .padding(.horizontal, AttenSpacing.lg)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AttenColor.appBackground)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(AttenColor.separator.opacity(0.5))
                        .frame(height: 0.5)
                }
                .accessibilityElement(children: .contain)
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let title {
                Text(title.title)
                    .font(title.isProminent ? AttenTypography.display : AttenTypography.body.weight(.semibold))
                    .foregroundStyle(AttenColor.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }
}
