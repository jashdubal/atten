import AppKit
import AttenCore
import SwiftUI

/// Create's states: an empty stage, the editor with its inspector, the same
/// editor read-only while it is queued or narrated, and the finished cover.
struct CreateView: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var flow: CreateFlowModel { model.createFlow }

    var body: some View {
        @Bindable var flow = flow
        ZStack {
            switch flow.state {
            case .empty:
                CreateEmptyStage(flow: flow)
                    .transition(.opacity)
            case .editing, .generating, .queued:
                editor
                    .transition(.opacity)
            case .done:
                CreateDoneStage(flow: flow, book: flow.finishedBookID.flatMap(model.bookshelf.book(id:)))
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(AttenMotion.transitionAnimation(AttenMotion.state, reduceMotion: reduceMotion), value: flow.state)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first, flow.state == .empty || flow.state == .editing else { return false }
            flow.importDocument(from: url)
            return true
        } isTargeted: { targeted in
            withAnimation(AttenMotion.animation(AttenMotion.state, reduceMotion: reduceMotion)) {
                flow.isDropTargeted = targeted
            }
        }
        .sheet(isPresented: $flow.isCasting) {
            CastingSheet(model: model)
        }
        // Text handed over by a route into Create that is not typing — a
        // duplicated project — becomes a draft on the shelf like any other.
        .onAppear { if !flow.text.isEmpty { flow.scheduleSave() } }
    }

    private var editor: some View {
        HStack(spacing: 0) {
            CreateEditorColumn(model: model, flow: flow)
                .opacity(flow.isDropTargeted ? 0.5 : 1)
            Rectangle()
                .fill(AttenColor.hairline)
                .frame(width: 1)
            CreateInspector(model: model, flow: flow)
                .frame(width: 320)
        }
    }
}

// MARK: - Empty

private struct CreateEmptyStage: View {
    @Bindable var flow: CreateFlowModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: AttenSpacing.lg) {
            dropTarget
            VStack(spacing: AttenSpacing.md) {
                HStack(spacing: AttenSpacing.xs) {
                    Button("Import file", systemImage: "doc", action: flow.openImportPanel)
                        .keyboardShortcut("i")
                    Button("Paste", systemImage: "doc.on.clipboard", action: flow.paste)
                    Button("Start writing", systemImage: "pencil", action: flow.startWriting)
                }
                .buttonStyle(AttenSecondaryButtonStyle())
                .disabled(flow.importingName != nil)

                Text(CreateFlowModel.formats)
                    .attenText(.label)
                    .foregroundStyle(AttenColor.text3)

                Button("Try a sample", action: flow.loadSample)
                    .buttonStyle(AttenTertiaryButtonStyle())
                    .disabled(flow.importingName != nil)
            }
            .opacity(flow.isDropTargeted ? 0.4 : 1)
        }
        .frame(maxWidth: 560)
        .padding(AttenSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            // The rest of the window dims while a document is over it.
            AttenColor.scrim
                .opacity(flow.isDropTargeted ? 0.18 : 0)
                .ignoresSafeArea()
        }
    }

    private var dropTarget: some View {
        let shape = RoundedRectangle(cornerRadius: AttenRadius.panel, style: .continuous)
        return VStack(spacing: AttenSpacing.sm) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(flow.isDropTargeted ? AttenColor.signal : AttenColor.text3)
            Text("Drop a document.")
                .attenText(.title2)
                .foregroundStyle(AttenColor.text1)
            if let name = flow.importingName {
                HStack(spacing: AttenSpacing.xs) {
                    ProgressView().controlSize(.small)
                    Text(name)
                        .attenText(.label)
                        .foregroundStyle(AttenColor.text2)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            } else if let failure = flow.errorMessage {
                Text(failure)
                    .attenText(.callout)
                    .foregroundStyle(AttenColor.destructive)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(AttenSpacing.lg)
        .frame(maxWidth: .infinity)
        .frame(height: 260)
        .background(AttenColor.surface1, in: shape)
        .overlay {
            shape.strokeBorder(AttenColor.hairline, lineWidth: 1)
        }
        .overlay {
            shape.strokeBorder(AttenColor.signal, lineWidth: 1.5)
                .opacity(flow.isDropTargeted ? 1 : 0)
        }
        .shadow(color: AttenColor.signal.opacity(flow.isDropTargeted ? 0.35 : 0), radius: 24)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Editor

/// About 68 characters of the reading face, which is where the editor holds
/// its text; the title and status share the same column.
private let createEditorColumnWidth = ("0" as NSString)
    .size(withAttributes: [.font: AttenTextStyle.reading.nsFont]).width * 68

private struct CreateEditorColumn: View {
    @Bindable var model: AppModel
    @Bindable var flow: CreateFlowModel

    var body: some View {
        let extent = flow.spokenExtent
        let isGenerating = flow.state == .generating
        let isLocked = isGenerating || flow.state == .queued
        VStack(spacing: 0) {
            TextField("Title", text: $flow.title, prompt: Text(flow.resolvedTitle.isEmpty ? "Untitled" : flow.resolvedTitle).foregroundStyle(AttenColor.text3))
                .textFieldStyle(.plain)
                .attenText(.title1)
                .foregroundStyle(AttenColor.text1)
                .disabled(isLocked)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: createEditorColumnWidth, alignment: .leading)
                .padding(.horizontal, AttenSpacing.lg)
                .padding(.top, AttenSpacing.xl)
                .accessibilityLabel("Title")

            AlignedTextEditor(
                text: $flow.text,
                accessibilityLabel: "Text to narrate",
                spokenLength: isLocked ? (extent?.utf16Offset ?? 0) : nil,
                playingRange: isGenerating ? flow.playingSentenceRange.map { NSRange(location: $0.location, length: $0.length) } : nil,
                focusesOnAppear: flow.text.isEmpty
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            CreateStatusFooter(flow: flow, playerTitle: model.playerTitle)
        }
    }
}

/// The word count, listen estimate and save state below the editor, in the
/// same units the inspector uses (#101).
struct CreateStatusFooter: View {
    let flow: CreateFlowModel
    var playerTitle: String?

    var body: some View {
        Text(status)
            .attenText(.label)
            .foregroundStyle(AttenColor.text3)
            .frame(maxWidth: createEditorColumnWidth, alignment: .leading)
            .padding(.horizontal, AttenSpacing.lg)
            .padding(.vertical, AttenSpacing.sm)
            // Clear of the player's ring, which floats at the bottom.
            .padding(.bottom, playerTitle == nil ? 0 : AttenMetrics.playerHeight)
            .accessibilityLabel(status.lowercased())
    }

    private var status: String {
        var parts = [
            ListenEstimator.wordsLabel(flow.wordCount),
            ListenEstimator.listenLabel(flow.listenDuration),
        ]
        if flow.isSaved { parts.append("SAVED") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Done

private struct CreateDoneStage: View {
    let flow: CreateFlowModel
    let book: BookRecord?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasLanded = false

    var body: some View {
        VStack {
            if let book {
                GeneratedCover(title: book.title, contentHash: book.contentHash ?? book.title)
                    .frame(width: 220)
                    .attenMatchedCover(book.id)
                    .shadow(color: AttenColor.shadow.opacity(0.3), radius: 30, y: 16)
                    .scaleEffect(hasLanded || reduceMotion ? 1 : 0.92)
                    .opacity(hasLanded || reduceMotion ? 1 : 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            withAnimation(AttenMotion.animation(.large, reduceMotion: reduceMotion)) { hasLanded = true }
            try? await Task.sleep(for: .milliseconds(1400))
            guard !Task.isCancelled else { return }
            withAnimation(AttenMotion.animation(.large, reduceMotion: reduceMotion)) {
                flow.leaveForLibrary()
            }
        }
    }
}
