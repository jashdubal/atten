import AttenCore
import SwiftUI

// The player's chapter list, bookmarks and sleep timer. None of them is the
// voice itself, so none of them takes `signal`: they are tertiary controls in
// the transport's quieter colours.

/// A small icon control in the transport, quieter than the transport's own
/// buttons.
struct PlayerToolButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(isHovering ? AttenColor.text1 : AttenColor.text2)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .attenFocusRing(cornerRadius: AttenRadius.small)
        .accessibilityLabel(label)
    }
}

// MARK: - Chapters

struct PlayerChapterList: View {
    let chapters: [ListeningMap.Chapter]
    let current: Int?
    let select: (ListeningMap.Chapter) -> Void

    var body: some View {
        PlayerPanel(title: "Chapters") {
            ForEach(Array(chapters.enumerated()), id: \.element.index) { position, chapter in
                PlayerPanelRow(isCurrent: position == current, action: { select(chapter) }) {
                    HStack(spacing: AttenSpacing.xs) {
                        Image(systemName: "waveform")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AttenColor.text2)
                            .opacity(position == current ? 1 : 0)
                            .frame(width: 14)
                        Text(chapter.title)
                            .attenText(.callout)
                            .fontWeight(position == current ? .semibold : .medium)
                            .foregroundStyle(AttenColor.text1)
                            .lineLimit(1)
                        Spacer(minLength: AttenSpacing.xs)
                        Text(PlaybackFormat.timeText(chapter.duration))
                            .attenText(.label)
                            .foregroundStyle(AttenColor.text2)
                    }
                }
                .accessibilityLabel("\(chapter.title), \(PlaybackFormat.timeText(chapter.duration))")
                .accessibilityAddTraits(position == current ? .isSelected : [])
            }
        }
    }
}

// MARK: - Bookmarks

struct PlayerBookmarkList: View {
    struct Entry: Identifiable {
        let bookmark: Bookmark
        let chapterTitle: String
        let time: TimeInterval?

        var id: UUID { bookmark.id }
    }

    let entries: [Entry]
    let add: () -> Void
    let jump: (Entry) -> Void
    let remove: (Entry) -> Void

    var body: some View {
        PlayerPanel(title: "Bookmarks", accessory: {
            Button(action: add) {
                Label("Add", systemImage: "plus")
            }
            .buttonStyle(AttenTertiaryButtonStyle())
            .accessibilityLabel("Add bookmark")
        }) {
            if entries.isEmpty {
                Text("No bookmarks")
                    .attenText(.callout)
                    .foregroundStyle(AttenColor.text3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, AttenSpacing.sm)
                    .padding(.vertical, AttenSpacing.xs)
            }
            ForEach(entries) { entry in
                PlayerPanelRow(isCurrent: false, action: { jump(entry) }) {
                    HStack(alignment: .top, spacing: AttenSpacing.xs) {
                        VStack(alignment: .leading, spacing: AttenSpacing.xxs) {
                            Text(entry.bookmark.excerpt)
                                .attenText(.callout)
                                .foregroundStyle(AttenColor.text1)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Text(detail(entry))
                                .attenText(.label)
                                .foregroundStyle(AttenColor.text2)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Button { remove(entry) } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(AttenColor.text3)
                                .frame(width: 20, height: 20)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove bookmark")
                    }
                }
                .accessibilityLabel("Bookmark in \(detail(entry)). \(entry.bookmark.excerpt)")
            }
        }
    }

    private func detail(_ entry: Entry) -> String {
        [entry.chapterTitle, entry.time.map(PlaybackFormat.timeText)].compactMap { $0 }.joined(separator: " · ")
    }
}

// MARK: - Sleep timer

/// The moon, and while a timer runs, how long is left.
struct SleepTimerControl: View {
    let timer: SleepTimer

    @Environment(\.attenIsOffscreenRender) private var isOffscreenRender

    var body: some View {
        HStack(spacing: AttenSpacing.xxs) {
            if timer.choice != nil {
                Text(readout)
                    .attenText(.label)
                    .foregroundStyle(AttenColor.text2)
                    .accessibilityLabel("Sleep timer, \(readout) left")
            }
            // `Menu` is drawn by AppKit, which an offscreen render leaves as
            // a placeholder; the label alone stands in for it there.
            if isOffscreenRender {
                icon
            } else {
                Menu {
                    Button { timer.set(nil) } label: { item("Off", isOn: timer.choice == nil) }
                    Divider()
                    ForEach(SleepTimer.Choice.all, id: \.self) { choice in
                        Button { timer.set(choice) } label: { item(choice.title, isOn: timer.choice == choice) }
                    }
                } label: {
                    icon
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .tint(timer.choice == nil ? AttenColor.text2 : AttenColor.text1)
                .fixedSize()
                .accessibilityLabel("Sleep timer")
            }
        }
    }

    private var icon: some View {
        Image(systemName: timer.choice == nil ? "moon.zzz" : "moon.zzz.fill")
            .font(.system(size: 14, weight: .regular))
            .foregroundStyle(timer.choice == nil ? AttenColor.text2 : AttenColor.text1)
            .frame(width: 32, height: 32)
    }

    private var readout: String {
        timer.remaining.map(PlaybackFormat.timeText) ?? "Chapter"
    }

    @ViewBuilder private func item(_ title: String, isOn: Bool) -> some View {
        if isOn { Label(title, systemImage: "checkmark") } else { Text(title) }
    }
}

// MARK: - Panel

/// The popover both lists sit in.
private struct PlayerPanel<Accessory: View, Content: View>: View {
    let title: String
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var content: () -> Content

    @Environment(\.attenIsOffscreenRender) private var isOffscreenRender

    init(
        title: String,
        @ViewBuilder accessory: @escaping () -> Accessory = { EmptyView() },
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.accessory = accessory
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AttenSpacing.xs) {
            HStack {
                Text(title)
                    .attenText(.label)
                    .foregroundStyle(AttenColor.text2)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                accessory()
            }
            .padding(.horizontal, AttenSpacing.sm)
            // A `ScrollView` draws nothing offscreen, so a render lays the
            // rows out flat.
            if isOffscreenRender {
                rows
            } else {
                // A popover is a window of its own, which the mini player
                // never covers, so it takes none of `attenScrollPadding`'s room.
                ScrollView(.vertical) { rows }
                    .frame(maxHeight: 360)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, AttenSpacing.sm)
        .padding(.horizontal, AttenSpacing.xxs)
        .frame(width: 340)
    }

    private var rows: some View {
        LazyVStack(alignment: .leading, spacing: 0) { content() }
    }
}

private struct PlayerPanelRow<Label: View>: View {
    let isCurrent: Bool
    let action: () -> Void
    @ViewBuilder var label: () -> Label

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            label()
                .padding(.horizontal, AttenSpacing.sm)
                .padding(.vertical, AttenSpacing.xs)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    AttenColor.text1.opacity(isCurrent || isHovering ? AttenState.hoverFill : 0),
                    in: RoundedRectangle(cornerRadius: AttenRadius.small)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
