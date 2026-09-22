import AttenCore
import SwiftUI

enum ReaderPanelTab: String, CaseIterable, Identifiable {
    case contents
    case bookmarks

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var icon: String { self == .contents ? "list.bullet" : "bookmark" }
}

/// Everything about the book that is not the book: where you are in it, where
/// you have been, and where a word you remember turns up. Typing in the field
/// takes the panel over, because a search is what you want to look at while
/// you are searching; clearing it hands the panel back.
struct ReaderSidePanel: View {
    let book: BookRecord
    let chapterIndex: Int
    let pagination: ReaderPagination
    let currentLocation: ReadingLocation
    @Binding var tab: ReaderPanelTab
    @Binding var query: String
    let hits: [ReaderHit]
    let isSearching: Bool
    let selectedHitID: String?
    /// The chapter being read aloud right now, if this book is what is playing.
    let playingChapterIndex: Int?
    let selectChapter: (Int) -> Void
    let selectHit: (ReaderHit) -> Void
    let selectBookmark: (Bookmark) -> Void
    let removeBookmark: (Bookmark) -> Void
    @FocusState.Binding var isSearchFocused: Bool

    private var isSearchingBook: Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider().overlay(AttenColor.separator.opacity(0.6))
            if isSearchingBook {
                results
            } else {
                tabs
                list
            }
        }
        .frame(width: 268)
        .background(AttenColor.sidebar)
    }

    // MARK: Search

    private var searchField: some View {
        HStack(spacing: AttenSpacing.xs) {
            Image(systemName: "magnifyingglass")
                .font(AttenTypography.caption)
                .foregroundStyle(AttenColor.textSecondary)
            TextField("Search this book", text: $query)
                .textFieldStyle(.plain)
                .font(AttenTypography.metadata)
                .focused($isSearchFocused)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(AttenTypography.caption)
                        .foregroundStyle(AttenColor.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, AttenSpacing.xs)
        .frame(height: 30)
        .attenInput()
        .padding(AttenSpacing.sm)
    }

    @ViewBuilder private var results: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: AttenSpacing.xs) {
                Text("RESULTS")
                    .font(AttenTypography.sectionTitle)
                    .foregroundStyle(AttenColor.accent)
                Spacer(minLength: 0)
                if isSearching {
                    ProgressView().controlSize(.mini)
                } else {
                    Text("\(hits.count)")
                        .font(AttenTypography.caption)
                        .foregroundStyle(AttenColor.textSecondary)
                }
            }
            .padding(.horizontal, AttenSpacing.sm)
            .padding(.bottom, AttenSpacing.xs)

            if hits.isEmpty, !isSearching {
                Text("No passage in this book matches that.")
                    .font(AttenTypography.caption)
                    .foregroundStyle(AttenColor.textSecondary)
                    .padding(.horizontal, AttenSpacing.sm)
                    .frame(maxHeight: .infinity, alignment: .top)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(hits) { hit in
                            SearchResultRow(
                                hit: hit,
                                chapterTitle: chapterTitle(hit.chapterIndex),
                                page: page(of: hit),
                                isSelected: hit.id == selectedHitID
                            ) {
                                selectHit(hit)
                            }
                        }
                    }
                    .padding(.horizontal, AttenSpacing.xs)
                    .padding(.bottom, AttenSpacing.sm)
                }
            }
        }
    }

    // MARK: Contents and bookmarks

    private var tabs: some View {
        Picker("", selection: $tab) {
            ForEach(ReaderPanelTab.allCases) { item in
                Label(item.label, systemImage: item.icon).tag(item)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .padding(.horizontal, AttenSpacing.sm)
        .padding(.vertical, AttenSpacing.xs)
    }

    @ViewBuilder private var list: some View {
        switch tab {
        case .contents:
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(book.chapters.enumerated()), id: \.element.id) { index, item in
                            ContentsRow(
                                number: index + 1,
                                title: item.title,
                                page: pagination.startPage(ofChapter: index),
                                isNarrated: item.isNarrated,
                                isPlaying: index == playingChapterIndex,
                                isSelected: index == chapterIndex,
                                hasBookmark: book.bookmarks.contains { $0.location.chapterIndex == index }
                            ) {
                                selectChapter(index)
                            }
                            .id(index)
                        }
                    }
                    .padding(.horizontal, AttenSpacing.xs)
                    .padding(.bottom, AttenSpacing.sm)
                }
                // Following the reader is the whole point of a contents list;
                // one that has to be scrolled to find your place is not one.
                .onChange(of: chapterIndex) { _, index in
                    withAnimation { proxy.scrollTo(index, anchor: .center) }
                }
            }
        case .bookmarks:
            if book.bookmarks.isEmpty {
                VStack(spacing: AttenSpacing.xs) {
                    Image(systemName: "bookmark")
                        .font(.system(size: 18))
                        .foregroundStyle(AttenColor.textSecondary)
                    Text("Nothing marked yet. Press ⌘D on a page worth coming back to.")
                        .font(AttenTypography.caption)
                        .foregroundStyle(AttenColor.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(AttenSpacing.md)
                .frame(maxHeight: .infinity, alignment: .top)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(book.bookmarks) { bookmark in
                            BookmarkRow(
                                bookmark: bookmark,
                                chapterTitle: chapterTitle(bookmark.location.chapterIndex),
                                page: page(of: bookmark.location),
                                isCurrent: bookmark.location.isAt(currentLocation),
                                select: { selectBookmark(bookmark) },
                                remove: { removeBookmark(bookmark) }
                            )
                        }
                    }
                    .padding(.horizontal, AttenSpacing.xs)
                    .padding(.bottom, AttenSpacing.sm)
                }
            }
        }
    }

    private func chapterTitle(_ index: Int) -> String {
        book.chapters.indices.contains(index) ? book.chapters[index].title : book.title
    }

    private func page(of hit: ReaderHit) -> Int {
        if let pageIndex = hit.pageIndex { return pageIndex + 1 }
        return pagination.startPage(ofChapter: hit.chapterIndex)
    }

    private func page(of location: ReadingLocation) -> Int {
        if let pageIndex = location.pageIndex { return pageIndex + 1 }
        return pagination.startPage(ofChapter: location.chapterIndex)
    }
}

// MARK: - Rows

private struct RowBackground: ViewModifier {
    let isSelected: Bool
    let isHovering: Bool

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, AttenSpacing.xs)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: AttenRadius.control))
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(isSelected ? AttenColor.accent : .clear)
                    .frame(width: 2)
            }
            .contentShape(Rectangle())
    }

    private var color: Color {
        if isSelected { return AttenColor.accent.opacity(0.14) }
        if isHovering { return AttenColor.surfaceMuted.opacity(0.72) }
        return .clear
    }
}

private struct ContentsRow: View {
    let number: Int
    let title: String
    let page: Int
    let isNarrated: Bool
    let isPlaying: Bool
    let isSelected: Bool
    let hasBookmark: Bool
    let select: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: select) {
            HStack(alignment: .firstTextBaseline, spacing: AttenSpacing.xs) {
                Text("\(number)")
                    .font(AttenTypography.caption)
                    .foregroundStyle(AttenColor.textSecondary)
                    .frame(width: 22, alignment: .trailing)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AttenTypography.metadata)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: AttenSpacing.xxs) {
                        Text("p. \(page)")
                        if isPlaying {
                            Image(systemName: "speaker.wave.2.fill")
                                .foregroundStyle(AttenColor.accent)
                        } else if isNarrated {
                            Image(systemName: "waveform")
                                .foregroundStyle(AttenColor.success)
                        }
                        if hasBookmark {
                            Image(systemName: "bookmark.fill")
                                .foregroundStyle(AttenColor.accentSecondary)
                        }
                    }
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(AttenColor.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? AttenColor.accentHover : AttenColor.textPrimary)
            .modifier(RowBackground(isSelected: isSelected, isHovering: isHovering))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(
            "Chapter \(number), \(title), page \(page)\(stateDescription)"
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var stateDescription: String {
        if isPlaying { return ", playing now" }
        return isNarrated ? ", narrated" : ""
    }
}

private struct BookmarkRow: View {
    let bookmark: Bookmark
    let chapterTitle: String
    let page: Int
    let isCurrent: Bool
    let select: () -> Void
    let remove: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: select) {
            HStack(alignment: .top, spacing: AttenSpacing.xs) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(bookmark.excerpt)
                        .font(.system(size: 11, design: .serif))
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                    Text("\(chapterTitle) · p. \(page)")
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(AttenColor.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if isHovering {
                    Button(action: remove) {
                        Image(systemName: "trash")
                            .font(AttenTypography.caption)
                            .foregroundStyle(AttenColor.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove bookmark")
                }
            }
            .foregroundStyle(isCurrent ? AttenColor.accentHover : AttenColor.textPrimary)
            .modifier(RowBackground(isSelected: isCurrent, isHovering: isHovering))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel("Bookmark in \(chapterTitle), page \(page). \(bookmark.excerpt)")
    }
}

private struct SearchResultRow: View {
    let hit: ReaderHit
    let chapterTitle: String
    let page: Int
    let isSelected: Bool
    let select: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 3) {
                Text(snippet)
                    .font(.system(size: 11, design: .serif))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                Text("\(chapterTitle) · p. \(page)")
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(AttenColor.textSecondary)
                    .lineLimit(1)
            }
            .foregroundStyle(AttenColor.textPrimary)
            .modifier(RowBackground(isSelected: isSelected, isHovering: isHovering))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel("\(hit.before)\(hit.match)\(hit.after), in \(chapterTitle), page \(page)")
    }

    private var snippet: AttributedString {
        var result = AttributedString(hit.before)
        var match = AttributedString(hit.match)
        match.backgroundColor = AttenColor.readerHighlight
        match.foregroundColor = AttenColor.readerText
        result.append(match)
        result.append(AttributedString(hit.after))
        return result
    }
}
