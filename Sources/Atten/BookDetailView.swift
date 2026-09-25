import AppKit
import AttenCore
import SwiftUI

struct BookDetailView: View {
    @Bindable var model: AppModel
    let book: BookRecord
    let openReader: () -> Void

    @State private var pendingVoice: Voice?
    @State private var confirmRemoval = false
    @State private var pendingExport: ExportTarget?

    private var shelf: BookshelfModel { model.bookshelf }

    private var progress: BookshelfModel.NarrationProgress? {
        shelf.progress?.bookID == book.id ? shelf.progress : nil
    }

    private var narratedCount: Int { shelf.narratedCount(of: book) }

    /// Waiting its turn behind another narration, not paused.
    private var isWaiting: Bool { shelf.isQueued(book.id) && !shelf.isPaused(book.id) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AttenSpacing.lg) {
                AttenBackButton(title: "Library") { model.goBack() }
                    .frame(maxWidth: .infinity, alignment: .leading)
                header
                LibraryStatusArea(shelf: shelf, showsPreparation: false)
                if !book.sourceExists { missingSourceNotice }
                controls
                chapterList
            }
            .padding(.horizontal, AttenSpacing.xl)
            .padding(.vertical, AttenSpacing.lg)
            .attenScrollPadding()
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
            Button("Change Voice") {
                if let pendingVoice { shelf.updateVoice(pendingVoice.id, for: book.id) }
                pendingVoice = nil
            }
            Button("Keep Current Voice", role: .cancel) { pendingVoice = nil }
        } message: {
            Text("Prepare the book again to use this voice. Your existing audiobook remains available until its replacement is ready.")
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
        .sheet(item: $pendingExport) { target in
            ExportSheet(model: model, target: target)
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
                        .font(AttenTypography.callout.weight(.semibold))
                        .foregroundStyle(AttenColor.textSecondary)
                }
            }
        }
        .frame(width: AttenMetrics.coverGridMinimum, height: AttenMetrics.coverGridMinimum / AttenMetrics.coverAspectRatio)
        .clipShape(RoundedRectangle(cornerRadius: AttenRadius.cover, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AttenRadius.cover, style: .continuous)
                .strokeBorder(AttenColor.glassHighlight, lineWidth: 0.5)
        }
        .shadow(color: AttenColor.shadow.opacity(0.15), radius: 6, y: 2)
        .accessibilityLabel("Cover for \(book.title)")
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: AttenSpacing.md) {
            PageHeader(
                eyebrow: book.format.displayName,
                title: book.title,
                detail: [
                    book.author,
                    "\(book.chapters.count) \(book.format.sectionNoun.lowercased())\(book.chapters.count == 1 ? "" : "s")",
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
            Button("Export…", systemImage: "square.and.arrow.up") {
                pendingExport = ExportTarget(book: book)
            }
            .disabled(!book.hasBookAudio)
            Divider()
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
                    .font(AttenTypography.callout.weight(.semibold))
                    .foregroundStyle(AttenColor.textPrimary)
                Text("Reading and revealing the original file are disabled. Narration already on disk remains available.")
                    .font(AttenTypography.callout)
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

    private var primaryTitle: String {
        if let progress { return progress.isCombining ? "Finalizing…" : "Preparing…" }
        if isWaiting { return "Queued" }
        if shelf.isFullyNarrated(book) { return model.playingBook?.id == book.id && model.isPlaying ? "Pause" : "Listen" }
        return narratedCount > 0 || book.narrationState == .interrupted || book.narrationState == .failed
            ? "Resume Preparation" : "Prepare Audio"
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: AttenSpacing.md) {
            HStack(spacing: AttenSpacing.sm) {
                Button {
                    if shelf.isFullyNarrated(book) { model.listen(to: book) }
                    else { shelf.narrate(book.id, useMPS: model.settings.useMPS) }
                } label: {
                    Label(primaryTitle, systemImage: shelf.isFullyNarrated(book) ? (model.playingBook?.id == book.id && model.isPlaying ? "pause.fill" : "play.fill") : "waveform")
                }
                .buttonStyle(AttenPrimaryButtonStyle(
                    disabledReason: progress == nil && !isWaiting ? "Another narration is running" : nil
                ))
                .disabled(progress != nil || isWaiting || (!shelf.isFullyNarrated(book) && !shelf.canStartNarration))
                .help(shelf.isFullyNarrated(book) ? "Listen to the complete book" : "Prepare the complete audiobook. You can keep reading while it works.")

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
                }
                if book.hasBookAudio && book.needsPreparation {
                    Button("Listen to Existing Audio") { model.listen(to: book) }
                        .buttonStyle(AttenSecondaryButtonStyle())
                }
            }

            if let progress {
                AttenProgressStatus(
                    title: progress.isCombining ? "Finalizing audiobook" : "Preparing audio",
                    detail: progress.isCombining ? "Combining chapters into one audio file" : "Chapter \(min(progress.completed + 1, progress.total)) of \(progress.total): \(progress.chapterTitle)",
                    phase: .active,
                    progress: progress.total > 0 ? progress.fraction : nil,
                    progressLabel: progress.eta
                )
            } else {
                if let failure = book.narrationFailure {
                    Text("Preparation stopped: \(failure) Resume to retry. Completed chapters are saved.")
                        .font(AttenTypography.callout).foregroundStyle(AttenColor.destructive)
                }
                Label(shelf.isFullyNarrated(book) ? "Audiobook ready" : "\(narratedCount) of \(book.chapters.count) \(book.chapters.count == 1 ? "chapter" : "chapters") prepared",
                      systemImage: shelf.isFullyNarrated(book) ? "checkmark.circle" : "waveform")
                    .font(AttenTypography.callout).foregroundStyle(AttenColor.textSecondary)
            }

            Divider().overlay(AttenColor.separator)

            settings
        }
        .attenSurface()
    }

    private var settings: some View {
        HStack(alignment: .bottom, spacing: AttenSpacing.lg) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Voice")
                Picker("Narration voice", selection: voiceBinding) {
                    ForEach(voices) { voice in
                        Text(voice.name).tag(voice.id)
                    }
                }
                .labelsHidden()
                .frame(width: 220)
            }
            if let required = model.requiredModelID(for: book.voiceID) {
                Button("Download Voice Model") { model.library.download(required) }
                    .buttonStyle(AttenSecondaryButtonStyle())
                    .disabled(model.library.downloads[required] != nil)
                    .help("Download once; this voice then works offline")
            } else if let voice = VoiceCatalog.voice(id: book.voiceID) {
                Button("Preview") { model.previewVoice(voice) }
                    .buttonStyle(AttenSecondaryButtonStyle())
                    .disabled(model.synthesis.isBusy)
            }
            Spacer(minLength: 0)
        }
        .font(AttenTypography.callout)
        .foregroundStyle(AttenColor.textSecondary)
        .disabled(progress != nil)
    }

    private var voices: [Voice] {
        _ = model.voiceCatalogRevision
        return VoiceCatalog.all
    }

    /// Confirm replacement settings while preserving the completed recording
    /// until its replacement is ready.
    private var voiceBinding: Binding<String> {
        Binding(
            get: { book.voiceID },
            set: { newValue in
                guard newValue != book.voiceID else { return }
                if narratedCount > 0 || book.hasBookAudio {
                    pendingVoice = VoiceCatalog.voice(id: newValue)
                } else {
                    shelf.updateVoice(newValue, for: book.id)
                }
            }
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
        model.isPlaying && model.activeAudioURL == book.audioURL && model.playbackPosition >= (chapter.startTime ?? 0) && model.playbackPosition < (chapter.endTime ?? .infinity)
    }

    var body: some View {
        HStack(spacing: AttenSpacing.sm) {
            leading

            VStack(alignment: .leading, spacing: 2) {
                Text("\(number). \(chapter.title)")
                    .font(AttenTypography.callout)
                    .foregroundStyle(AttenColor.textPrimary)
                    .lineLimit(1)
                Text(chapter.text.prefix(120))
                    .font(AttenTypography.callout)
                    .foregroundStyle(AttenColor.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(detail)
                .font(AttenTypography.callout)
                .foregroundStyle(AttenColor.textSecondary)
                .frame(width: 96, alignment: .trailing)
        }
        .padding(.horizontal, AttenSpacing.sm)
        .frame(minHeight: 52)
        .background(isHovering ? AttenColor.surfaceMuted.opacity(0.65) : .clear)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("Prepare Complete Audiobook", systemImage: "waveform", action: narrateOne)
                .disabled(book.hasBookAudio || !model.bookshelf.canStartNarration)
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
        } else if book.hasBookAudio {
            Button {
                if isPlaying { model.toggleActivePlayback() } else { model.listen(to: book, chapter: chapter) }
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(AttenTypography.callout.weight(.semibold))
                    .foregroundStyle(AttenColor.accent)
                    .frame(width: 30, height: 30)
                    .background(AttenColor.accent.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: AttenRadius.small))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPlaying ? "Pause \(chapter.title)" : "Play \(chapter.title)")
        } else {
            Image(systemName: "text.alignleft")
                .font(AttenTypography.callout)
                .foregroundStyle(AttenColor.textSecondary)
                .frame(width: 30, height: 30)
                .accessibilityHidden(true)
        }
    }

    private var detail: String {
        if isGenerating { return "generating…" }
        if let start = chapter.startTime {
            let seconds = Int(start)
            return String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
        }
        return metadata?.durationText ?? "—"
    }
}
