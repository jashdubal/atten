import AppKit
import AttenCore
import SwiftUI

struct BookDetailView: View {
    @Bindable var model: AppModel
    let book: BookRecord
    let openReader: () -> Void

    @State private var pendingVoice: Voice?
    @State private var confirmRemoval = false

    private var shelf: BookshelfModel { model.bookshelf }

    private var progress: BookshelfModel.NarrationProgress? {
        shelf.progress?.bookID == book.id ? shelf.progress : nil
    }

    private var narratedCount: Int { shelf.narratedCount(of: book) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AttenSpacing.lg) {
                AttenBackButton(title: "Library") { model.goBack() }
                    .frame(maxWidth: .infinity, alignment: .leading)
                header
                LibraryStatusArea(shelf: shelf)
                if !book.sourceExists { missingSourceNotice }
                controls
                chapterList
            }
            .padding(.horizontal, AttenSpacing.xl)
            .padding(.vertical, AttenSpacing.lg)
            .frame(maxWidth: 1120, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(AttenBackdrop())
        .navigationTitle(book.title)
        .task(id: book.id) { await shelf.covers.load(book) }
        .confirmationDialog(
            "Re-narrate \(book.title) with the new voice?",
            isPresented: Binding(
                get: { pendingVoice != nil },
                set: { if !$0 { pendingVoice = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Change Voice and Clear Narration", role: .destructive) {
                if let pendingVoice { shelf.updateVoice(pendingVoice.id, for: book.id) }
                pendingVoice = nil
            }
            Button("Keep Current Voice", role: .cancel) { pendingVoice = nil }
        } message: {
            Text("\(narratedCount) narrated chapters would be deleted so the whole book is read in one voice.")
        }
        .confirmationDialog(
            "Remove \(book.title) from your library?",
            isPresented: $confirmRemoval,
            titleVisibility: .visible
        ) {
            Button("Remove Book and Narration", role: .destructive) { shelf.remove(book.id) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Atten's copy of the book and every chapter it narrated are deleted. The original file is untouched.")
        }
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: AttenSpacing.lg) {
                cover
                VStack(alignment: .leading, spacing: AttenSpacing.md) {
                    titleBlock
                    actionsMenu
                }
            }
            VStack(alignment: .leading, spacing: AttenSpacing.md) {
                HStack(alignment: .top, spacing: AttenSpacing.md) {
                    cover
                    titleBlock
                }
                actionsMenu
            }
        }
    }

    private var cover: some View {
        ZStack {
            if let image = shelf.covers.cover(for: book.id) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(
                    colors: [AttenColor.surfaceElevated, AttenColor.surfaceMuted],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                VStack(spacing: AttenSpacing.xs) {
                    Image(systemName: book.format.icon)
                        .font(.system(size: 26))
                        .foregroundStyle(AttenColor.accent.opacity(0.8))
                    Text(book.format.displayName)
                        .font(AttenTypography.caption.weight(.semibold))
                        .foregroundStyle(AttenColor.textSecondary)
                }
            }
        }
        .frame(width: 132, height: 198)
        .clipShape(RoundedRectangle(cornerRadius: AttenRadius.cover, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AttenRadius.cover, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
        .accessibilityLabel("Cover for \(book.title)")
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: AttenSpacing.md) {
            PageHeader(
                eyebrow: book.format.displayName,
                title: book.title,
                detail: [
                    book.author,
                    "\(book.chapters.count) \(book.format.sectionNoun.lowercased())s",
                    "\(book.wordCount.formatted()) words",
                    book.bookmarks.isEmpty
                        ? nil
                        : "\(book.bookmarks.count) bookmark\(book.bookmarks.count == 1 ? "" : "s")",
                ]
                .compactMap { $0 }
                .joined(separator: " · ")
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actionsMenu: some View {
        Menu {
            Button("Reveal Source in Finder", systemImage: "folder") {
                model.revealBookSource(book)
            }
            .disabled(!book.sourceExists)
            Divider()
            Button("Remove from Library…", systemImage: "trash", role: .destructive) {
                confirmRemoval = true
            }
        } label: {
            Label("Actions", systemImage: "ellipsis")
                .labelStyle(.iconOnly)
                .frame(width: 30, height: 30)
        }
        .menuStyle(.borderlessButton)
        .accessibilityLabel("Actions for \(book.title)")
    }

    private var missingSourceNotice: some View {
        HStack(alignment: .top, spacing: AttenSpacing.xs) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AttenColor.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text("Source file unavailable")
                    .font(AttenTypography.control.weight(.semibold))
                    .foregroundStyle(AttenColor.textPrimary)
                Text("Reading and revealing the original file are disabled. Narration already on disk remains available.")
                    .font(AttenTypography.caption)
                    .foregroundStyle(AttenColor.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(AttenSpacing.sm)
        .background(AttenColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: AttenRadius.control))
        .overlay {
            RoundedRectangle(cornerRadius: AttenRadius.control)
                .stroke(AttenColor.warning.opacity(0.8), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: AttenSpacing.md) {
            HStack(spacing: AttenSpacing.sm) {
                Button {
                    model.play(tracks: book.narrationTracks)
                } label: {
                    Label("Play all", systemImage: "play.fill")
                }
                .buttonStyle(AttenPrimaryButtonStyle())
                .disabled(narratedCount == 0)
                .help(narratedCount == 0
                    ? "Narrate the book first"
                    : "Play every narrated chapter in order")

                // A book already started opens where it was left off, so the
                // button says so rather than promising the first page.
                Button(
                    book.lastLocation == nil ? "Read" : "Resume",
                    systemImage: "text.alignleft",
                    action: openReader
                )
                .buttonStyle(AttenSecondaryButtonStyle())
                .disabled(!book.sourceExists)

                Spacer(minLength: 0)

                if progress != nil {
                    Button("Stop", systemImage: "stop.fill") { shelf.cancelNarration() }
                        .buttonStyle(AttenSecondaryButtonStyle())
                } else if !shelf.isFullyNarrated(book) {
                    Button {
                        shelf.narrate(book.id, useMPS: model.settings.useMPS)
                    } label: {
                        Label(
                            narratedCount == 0 ? "Narrate book" : "Narrate remaining",
                            systemImage: "waveform"
                        )
                    }
                    .buttonStyle(AttenSecondaryButtonStyle())
                    .disabled(shelf.isNarrating)
                    .help(shelf.isNarrating ? "Another book is being narrated" : "")
                }
            }

            if let progress {
                VStack(alignment: .leading, spacing: AttenSpacing.xxs) {
                    ProgressView(value: progress.fraction)
                        .tint(AttenColor.accent)
                    Text("Chapter \(progress.completed + 1) of \(progress.total) — \(progress.chapterTitle)")
                        .font(AttenTypography.caption)
                        .foregroundStyle(AttenColor.textSecondary)
                        .lineLimit(1)
                }
            } else {
                NarrationMeter(
                    narrated: narratedCount,
                    total: book.chapters.count,
                    isRunning: false
                )
            }

            Divider().overlay(AttenColor.separator)

            settings
        }
        .attenSurface()
    }

    private var settings: some View {
        HStack(alignment: .top, spacing: AttenSpacing.lg) {
            FormRow(label: "Voice") {
                Picker("", selection: voiceBinding) {
                    ForEach(voices) { voice in
                        Text("\(voice.name) · \(voice.language)").tag(voice.id)
                    }
                }
                .labelsHidden()
                .frame(width: 220)
            }
            FormRow(label: "Speed") {
                Picker("", selection: speedBinding) {
                    ForEach([0.75, 0.9, 1.0, 1.15, 1.3, 1.5], id: \.self) { value in
                        Text(String(format: "%.2g×", value)).tag(value)
                    }
                }
                .labelsHidden()
                .frame(width: 90)
            }
            FormRow(label: "Format") {
                Picker("", selection: formatBinding) {
                    ForEach(AudioFormat.allCases) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 120)
            }
            Spacer(minLength: 0)
        }
        .font(AttenTypography.metadata)
        .foregroundStyle(AttenColor.textSecondary)
        .disabled(progress != nil)
    }

    private var voices: [Voice] {
        _ = model.voiceCatalogRevision
        return VoiceCatalog.all
    }

    /// Changing a setting mid-book would leave it narrated in two voices or two
    /// speeds, so anything already generated is cleared — but only after the
    /// user has been told what that costs.
    private var voiceBinding: Binding<String> {
        Binding(
            get: { book.voiceID },
            set: { newValue in
                guard newValue != book.voiceID else { return }
                if narratedCount > 0 {
                    pendingVoice = VoiceCatalog.voice(id: newValue)
                } else {
                    shelf.updateVoice(newValue, for: book.id)
                }
            }
        )
    }

    private var speedBinding: Binding<Double> {
        Binding(
            get: { book.speed },
            set: { shelf.updateSpeed($0, for: book.id) }
        )
    }

    private var formatBinding: Binding<AudioFormat> {
        Binding(
            get: { book.audioFormat },
            set: { shelf.updateFormat($0, for: book.id) }
        )
    }

    private var chapterList: some View {
        VStack(spacing: 0) {
            ForEach(Array(book.chapters.enumerated()), id: \.element.id) { index, chapter in
                ChapterRow(
                    model: model,
                    book: book,
                    chapter: chapter,
                    number: index + 1,
                    isGenerating: progress?.chapterID == chapter.id,
                    narrateOne: {
                        shelf.narrate(book.id, chapters: [index], useMPS: model.settings.useMPS)
                    }
                )
                if chapter.id != book.chapters.last?.id {
                    Divider()
                        .padding(.leading, 52)
                        .overlay(AttenColor.separator.opacity(0.8))
                }
            }
        }
        .background(AttenColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: AttenRadius.card))
        .overlay {
            RoundedRectangle(cornerRadius: AttenRadius.card)
                .stroke(AttenColor.separator.opacity(0.72), lineWidth: 1)
        }
    }
}

private struct ChapterRow: View {
    @Bindable var model: AppModel
    let book: BookRecord
    let chapter: BookChapter
    let number: Int
    let isGenerating: Bool
    let narrateOne: () -> Void

    @State private var isHovering = false
    /// Filled in once the narration has been measured, off the main thread. A
    /// row that measured it while drawing reopened the file on every redraw,
    /// which a book of two hundred chapters felt keenly.
    @State private var metadata: AudioFileMetadata?

    private var isPlaying: Bool {
        model.isPlaying && model.activeAudioURL == chapter.audioURL
    }

    var body: some View {
        HStack(spacing: AttenSpacing.sm) {
            leading

            VStack(alignment: .leading, spacing: 2) {
                Text("\(number). \(chapter.title)")
                    .font(AttenTypography.control)
                    .foregroundStyle(AttenColor.textPrimary)
                    .lineLimit(1)
                Text(chapter.text.prefix(120))
                    .font(AttenTypography.caption)
                    .foregroundStyle(AttenColor.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(detail)
                .font(AttenTypography.caption)
                .foregroundStyle(AttenColor.textSecondary)
                .frame(width: 96, alignment: .trailing)
        }
        .padding(.horizontal, AttenSpacing.sm)
        .frame(minHeight: 52)
        .background(isHovering ? AttenColor.surfaceMuted.opacity(0.65) : .clear)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("Narrate This Chapter", systemImage: "waveform", action: narrateOne)
                .disabled(chapter.isNarrated || model.bookshelf.isNarrating)
        }
        .task(id: chapter.audioPath) {
            guard let url = chapter.audioURL, chapter.isNarrated else {
                metadata = nil
                return
            }
            metadata = await AudioMetadataStore.shared.measure(url)
        }
    }

    @ViewBuilder private var leading: some View {
        if isGenerating {
            ProgressView()
                .controlSize(.small)
                .frame(width: 30, height: 30)
        } else if chapter.isNarrated, let url = chapter.audioURL {
            Button {
                model.togglePlayback(
                    track: PlaybackTrack(
                        id: chapter.id,
                        url: url,
                        title: chapter.title,
                        subtitle: book.title
                    )
                )
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(AttenTypography.caption.weight(.semibold))
                    .foregroundStyle(AttenColor.accent)
                    .frame(width: 30, height: 30)
                    .background(AttenColor.accent.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: AttenRadius.small))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPlaying ? "Pause \(chapter.title)" : "Play \(chapter.title)")
        } else {
            Button(action: narrateOne) {
                Image(systemName: "waveform")
                    .font(AttenTypography.caption)
                    .foregroundStyle(AttenColor.textSecondary)
                    .frame(width: 30, height: 30)
                    .background(AttenColor.surfaceMuted.opacity(isHovering ? 0.8 : 0.35))
                    .clipShape(RoundedRectangle(cornerRadius: AttenRadius.small))
            }
            .buttonStyle(.plain)
            .disabled(model.bookshelf.isNarrating)
            .help("Narrate this chapter")
            .accessibilityLabel("Narrate \(chapter.title)")
        }
    }

    private var detail: String {
        if isGenerating { return "generating…" }
        return metadata?.durationText ?? "—"
    }
}
