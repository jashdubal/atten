import AttenCore
import PDFKit
import SwiftUI

/// A plain reading view: contents on the left, the chapter on the right, and
/// the narration of whatever is on screen one click away. PDFs are shown by
/// PDFKit so the original typesetting survives; EPUBs have no fixed pages, so
/// their extracted text is what is read on screen and aloud alike.
struct BookReaderView: View {
    @Bindable var model: AppModel
    let book: BookRecord

    @State private var chapterIndex = 0
    @AppStorage("Atten.readerFontSize") private var fontSize = 16.0

    private static let fontRange = 12.0...28.0

    private var chapter: BookChapter? {
        book.chapters.indices.contains(chapterIndex) ? book.chapters[chapterIndex] : nil
    }

    var body: some View {
        HStack(spacing: 0) {
            contents
            Divider().overlay(AttenColor.separator)
            VStack(spacing: 0) {
                page
                Divider().overlay(AttenColor.separator)
                controls
            }
        }
        .background(AttenBackdrop())
        .navigationTitle(book.title)
        .onAppear {
            if !book.chapters.indices.contains(chapterIndex) { chapterIndex = 0 }
        }
    }

    private var contents: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("> CONTENTS")
                .font(AttenTypography.sectionTitle)
                .foregroundStyle(AttenColor.accent)
                .padding(.horizontal, AttenSpacing.sm)
                .padding(.vertical, AttenSpacing.sm)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(book.chapters.enumerated()), id: \.element.id) { index, item in
                        ContentsRow(
                            number: index + 1,
                            title: item.title,
                            isNarrated: item.isNarrated,
                            isSelected: index == chapterIndex
                        ) {
                            chapterIndex = index
                        }
                    }
                }
                .padding(.horizontal, AttenSpacing.xs)
                .padding(.bottom, AttenSpacing.sm)
            }
        }
        .frame(width: 232)
        .background(AttenColor.sidebar)
    }

    @ViewBuilder private var page: some View {
        if !book.sourceExists {
            AttenEmptyState(
                title: "Source file missing",
                systemImage: "questionmark.folder",
                detail: "Atten's copy of this book is gone. Remove it and add the book again."
            )
        } else if book.format == .pdf {
            PDFPageView(url: book.sourceURL, pageIndex: chapter?.pageIndex)
        } else if let chapter {
            ScrollView {
                VStack(alignment: .leading, spacing: AttenSpacing.md) {
                    Text(chapter.title)
                        .font(.system(size: fontSize * 1.5, weight: .semibold, design: .serif))
                        .foregroundStyle(AttenColor.textPrimary)
                    Text(chapter.text)
                        .font(.system(size: fontSize, design: .serif))
                        .foregroundStyle(AttenColor.textPrimary)
                        .lineSpacing(fontSize * 0.45)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, AttenSpacing.xl)
                .padding(.vertical, AttenSpacing.lg)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .id(chapter.id)
        } else {
            AttenEmptyState(
                title: "Nothing to read",
                systemImage: "text.alignleft",
                detail: "This book has no chapters Atten could read."
            )
        }
    }

    private var controls: some View {
        HStack(spacing: AttenSpacing.sm) {
            Button {
                chapterIndex = max(0, chapterIndex - 1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(AttenSecondaryButtonStyle())
            .disabled(chapterIndex == 0)
            .accessibilityLabel("Previous chapter")

            Button {
                chapterIndex = min(book.chapters.count - 1, chapterIndex + 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(AttenSecondaryButtonStyle())
            .disabled(chapterIndex >= book.chapters.count - 1)
            .accessibilityLabel("Next chapter")

            narrationButton

            Spacer(minLength: 0)

            Text("\(chapterIndex + 1) / \(book.chapters.count)")
                .font(AttenTypography.caption)
                .foregroundStyle(AttenColor.textSecondary)

            if book.format == .epub {
                Button { fontSize = max(Self.fontRange.lowerBound, fontSize - 1) } label: {
                    Image(systemName: "textformat.size.smaller")
                }
                .buttonStyle(AttenSecondaryButtonStyle())
                .disabled(fontSize <= Self.fontRange.lowerBound)
                .accessibilityLabel("Smaller text")

                Button { fontSize = min(Self.fontRange.upperBound, fontSize + 1) } label: {
                    Image(systemName: "textformat.size.larger")
                }
                .buttonStyle(AttenSecondaryButtonStyle())
                .disabled(fontSize >= Self.fontRange.upperBound)
                .accessibilityLabel("Larger text")
            }
        }
        .padding(.horizontal, AttenSpacing.md)
        .padding(.vertical, AttenSpacing.xs)
        .background(AttenColor.surface)
    }

    @ViewBuilder private var narrationButton: some View {
        if model.bookshelf.progress?.bookID == book.id {
            Button("Stop", systemImage: "stop.fill") { model.bookshelf.cancelNarration() }
                .buttonStyle(AttenSecondaryButtonStyle())
        } else if let chapter, chapter.isNarrated, let url = chapter.audioURL {
            Button {
                // Playing from here continues into the rest of the book, the
                // way turning a page would.
                model.playSequence(
                    book.chapters.dropFirst(chapterIndex).compactMap {
                        $0.isNarrated ? $0.audioURL : nil
                    }
                )
            } label: {
                Label(
                    model.isPlaying && model.activeAudioURL == url ? "Playing" : "Listen",
                    systemImage: "play.fill"
                )
            }
            .buttonStyle(AttenPrimaryButtonStyle())
        } else {
            Button {
                model.bookshelf.narrate(
                    book.id,
                    chapters: [chapterIndex],
                    useMPS: model.settings.useMPS
                )
            } label: {
                Label("Narrate this chapter", systemImage: "waveform")
            }
            .buttonStyle(AttenPrimaryButtonStyle())
            .disabled(chapter == nil || model.bookshelf.isNarrating)
        }
    }
}

private struct ContentsRow: View {
    let number: Int
    let title: String
    let isNarrated: Bool
    let isSelected: Bool
    let select: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: select) {
            HStack(spacing: AttenSpacing.xs) {
                Text("\(number)")
                    .font(AttenTypography.caption)
                    .foregroundStyle(AttenColor.textSecondary)
                    .frame(width: 24, alignment: .trailing)
                Text(title)
                    .font(AttenTypography.metadata)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                if isNarrated {
                    Image(systemName: "waveform")
                        .font(.system(size: 9))
                        .foregroundStyle(AttenColor.success)
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(isSelected ? AttenColor.accentHover : AttenColor.textPrimary)
            .padding(.horizontal, AttenSpacing.xs)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: AttenRadius.control))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Chapter \(number), \(title)\(isNarrated ? ", narrated" : "")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .onHover { isHovering = $0 }
    }

    private var background: Color {
        if isSelected { return AttenColor.accent.opacity(0.14) }
        if isHovering { return AttenColor.surfaceMuted.opacity(0.72) }
        return .clear
    }
}

/// PDFKit gives the real page, with its own scrolling, zoom, selection, and
/// find. Jumping to a chapter is a scroll rather than a reload, so the reader
/// keeps their place when they come back to a chapter.
private struct PDFPageView: NSViewRepresentable {
    let url: URL
    let pageIndex: Int?

    final class Coordinator {
        var requestedPage: Int?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.document = PDFDocument(url: url)
        view.backgroundColor = .textBackgroundColor
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
            context.coordinator.requestedPage = nil
        }
        // Only move when the selected chapter changed; otherwise every redraw
        // would yank the reader back to the top of the chapter.
        guard let pageIndex, context.coordinator.requestedPage != pageIndex,
              let page = view.document?.page(at: pageIndex) else { return }
        context.coordinator.requestedPage = pageIndex
        view.go(to: page)
    }
}
