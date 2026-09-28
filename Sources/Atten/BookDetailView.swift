import AppKit
import AttenCore
import SwiftUI

struct BookDetailView: View {
    @Bindable var model: AppModel
    let book: BookRecord
    let openReader: () -> Void

    @State private var pendingVoice: Voice?
    @State private var isCasting = false
    /// Chosen in the casting sheet, and acted on once it has closed so a
    /// confirmation never has to open over it.
    @State private var castVoice: Voice?
    @State private var confirmRemoval = false
    @State private var pendingExport: ExportTarget?
    @Environment(\.attenIsOffscreenRender) private var isOffscreenRender

    private var shelf: BookshelfModel { model.bookshelf }

    private var progress: BookshelfModel.NarrationProgress? {
        shelf.progress?.bookID == book.id ? shelf.progress : nil
    }

    private var narratedCount: Int { shelf.narratedCount(of: book) }

    /// Waiting its turn behind another narration, not paused.
    private var isWaiting: Bool { shelf.isQueued(book.id) && !shelf.isPaused(book.id) }

    /// Chapters are left to narrate in a voice whose model isn't here yet.
    /// The narrator card offers the download.
    private var voiceNeedsDownload: Bool {
        narratedCount < book.chapters.count && model.requiredModelID(for: book.voiceID) != nil
    }

    var body: some View {
        Group {
            // `ImageRenderer` draws nothing inside a `ScrollView`; see
            // `attenIsOffscreenRender`.
            if isOffscreenRender {
                page.fixedSize(horizontal: false, vertical: true)
                    .frame(maxHeight: .infinity, alignment: .top)
            } else {
                ScrollView { page }
            }
        }
        .background(AttenBackdrop())
        .navigationTitle(book.title)
        .task(id: book.id) { await shelf.covers.load(book) }
        .sheet(isPresented: $isCasting, onDismiss: applyCast) {
            CastingSheet(model: model, currentVoiceID: book.voiceID) { castVoice = $0 }
        }
        // A new narrator means narrating again, which is what makes it worth
        // asking about: the dialog says so, and confirming starts it.
        .confirmationDialog(
            "Regenerate \(book.title) with \(pendingVoice.map { VoiceProfile(voice: $0).displayName } ?? "the new voice")?",
            isPresented: Binding(
                get: { pendingVoice != nil },
                set: { if !$0 { pendingVoice = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Change and Regenerate") {
                if let pendingVoice {
                    shelf.updateVoice(pendingVoice.id, for: book.id)
                    if shelf.canStartNarration { shelf.narrate(book.id, useMPS: model.settings.useMPS) }
                }
                pendingVoice = nil
            }
            Button("Keep Current Voice", role: .cancel) { pendingVoice = nil }
        } message: {
            Text(book.hasBookAudio
                ? "Changing the narrator regenerates the whole audiobook. The current recording stays playable until the new one is ready."
                : "Changing the narrator regenerates the chapters already narrated.")
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

    private var page: some View {
        VStack(alignment: .leading, spacing: AttenSpacing.lg) {
            AttenBackButton(title: "Library") { model.goBack() }
                .frame(maxWidth: .infinity, alignment: .leading)
            header
            LibraryStatusArea(shelf: shelf, showsPreparation: false)
            if !book.sourceExists { missingSourceNotice }
            chapterList
        }
        .padding(.horizontal, AttenSpacing.xl)
        .padding(.vertical, AttenSpacing.lg)
        .attenScrollPadding()
        .frame(maxWidth: 1120, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var isPlayingBook: Bool { model.playingBook?.id == book.id && model.isPlaying }

    /// The Library card's cover, at the size of a page rather than a shelf,
    /// under the same matched id so opening a card carries its cover here.
    private var header: some View {
        HStack(alignment: .top, spacing: AttenSpacing.xl) {
            BookJacket(
                book: book,
                cover: shelf.covers.cover(for: book.id),
                height: 240,
                dominantColor: shelf.covers.dominantColor(for: book.id),
                isPlaying: isPlayingBook
            )
            .attenMatchedCover(book.id)

            VStack(alignment: .leading, spacing: AttenSpacing.lg) {
                HStack(alignment: .top, spacing: AttenSpacing.sm) {
                    titleBlock
                    actionsMenu
                }
                controls
                BookNarratorCard(model: model, book: book, isLocked: progress != nil) { isCasting = true }
                    .frame(maxWidth: 520, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Author, then counts. A generated cover already prints the format on
    /// its face, so it is named here only beside real art — as the Library
    /// card does.
    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: AttenSpacing.xs) {
            Text(book.title)
                .attenText(.title1)
                .foregroundStyle(AttenColor.text1)
                .fixedSize(horizontal: false, vertical: true)
            Text(
                [
                    book.author,
                    shelf.covers.cover(for: book.id) == nil ? nil : book.format.displayName,
                    "\(book.chapters.count) \(book.format.sectionNoun.lowercased())\(book.chapters.count == 1 ? "" : "s")",
                    "\(book.wordCount.formatted()) words",
                    book.bookmarks.isEmpty
                        ? nil
                        : "\(book.bookmarks.count) bookmark\(book.bookmarks.count == 1 ? "" : "s")",
                ]
                .compactMap { $0 }
                .joined(separator: " · ")
            )
            .attenText(.body)
            .foregroundStyle(AttenColor.text2)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The Library card's ⋯, so a book offers the same things from its page
    /// as from the shelf — less Open, since this is where Open leads.
    private var actionsMenu: some View {
        Menu {
            Button("Read", systemImage: "text.alignleft", action: openReader)
                .disabled(!book.sourceExists)
            Divider()
            Button("Export…", systemImage: "square.and.arrow.up") {
                pendingExport = ExportTarget(book: book)
            }
            .disabled(!book.hasBookAudio)
            Button("Reveal Source in Finder", systemImage: "folder") {
                model.revealBookSource(book)
            }
            .disabled(!book.sourceExists)
            Divider()
            Button("Remove from Library", systemImage: "trash", role: .destructive) {
                confirmRemoval = true
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AttenColor.textPrimary)
                .frame(width: 28, height: 24)
                .background(AttenColor.surface.opacity(0.92), in: RoundedRectangle(cornerRadius: 4))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .tint(AttenColor.text1)
        .fixedSize()
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

    /// Signal belongs to voice, so only Listen is primary; preparing audio
    /// is a secondary action until there is something to hear.
    private var controls: some View {
        VStack(alignment: .leading, spacing: AttenSpacing.md) {
            HStack(spacing: AttenSpacing.sm) {
                primaryButton

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
                    progressLabel: shelf.remainingLabel(for: book.id)
                )
            } else {
                if let failure = book.narrationFailure {
                    Text("Preparation stopped: \(failure) Resume to retry. Completed chapters are saved.")
                        .font(AttenTypography.callout).foregroundStyle(AttenColor.destructive)
                }
                if shelf.isFullyNarrated(book) {
                    Label("Ready to listen", systemImage: "headphones")
                        .font(AttenTypography.callout).foregroundStyle(AttenColor.textSecondary)
                } else if voiceNeedsDownload {
                    Text("Voice needs download")
                        .font(AttenTypography.callout).foregroundStyle(AttenColor.textSecondary)
                } else if !isWaiting && !shelf.canStartNarration {
                    Text("Another narration is running")
                        .font(AttenTypography.callout).foregroundStyle(AttenColor.textSecondary)
                } else if narratedCount > 0 {
                    Label("\(narratedCount) of \(book.chapters.count) \(book.chapters.count == 1 ? "chapter" : "chapters") prepared",
                          systemImage: "waveform")
                        .font(AttenTypography.callout).foregroundStyle(AttenColor.textSecondary)
                }
            }
        }
    }

    @ViewBuilder private var primaryButton: some View {
        let isListenable = shelf.isFullyNarrated(book)
        let button = Button {
            if isListenable { model.listen(to: book) }
            else { shelf.narrate(book.id, useMPS: model.settings.useMPS) }
        } label: {
            Label(primaryTitle, systemImage: isListenable ? (isPlayingBook ? "pause.fill" : "play.fill") : "waveform")
        }
        .disabled(progress != nil || isWaiting || (!isListenable && (!shelf.canStartNarration || voiceNeedsDownload)))
        .help(isListenable ? "Listen to the complete book" : "Prepare the complete audiobook. You can keep reading while it works.")
        if isListenable {
            button.buttonStyle(AttenPrimaryButtonStyle())
        } else {
            button.buttonStyle(AttenSecondaryButtonStyle())
        }
    }

    /// Acts on the sheet's choice. A voice with nothing narrated in it yet
    /// just changes; one that means narrating again asks first.
    private func applyCast() {
        guard let voice = castVoice else { return }
        castVoice = nil
        guard voice.id != book.voiceID else { return }
        if narratedCount > 0 || book.hasBookAudio {
            pendingVoice = voice
        } else {
            shelf.updateVoice(voice.id, for: book.id)
        }
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
                // A section named after its book (a one-section document)
                // would repeat the page's title; its opening words say more.
                if chapter.title == book.title {
                    Text("\(number). \(chapter.text.prefix(120))")
                        .font(AttenTypography.callout)
                        .foregroundStyle(AttenColor.textPrimary)
                        .lineLimit(1)
                } else {
                    Text("\(number). \(chapter.title)")
                        .font(AttenTypography.callout)
                        .foregroundStyle(AttenColor.textPrimary)
                        .lineLimit(1)
                    Text(chapter.text.prefix(120))
                        .font(AttenTypography.callout)
                        .foregroundStyle(AttenColor.textSecondary)
                        .lineLimit(1)
                }
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
            // A chapter placed in the book's recording already knows its
            // length; measuring its file would measure the whole book.
            guard chapter.narratedDuration == nil, let url = chapter.audioURL, chapter.isNarrated else {
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
        guard let duration = chapter.narratedDuration ?? metadata?.duration, duration.isFinite else { return "—" }
        return ListenEstimator.durationLabel(duration)
    }
}
