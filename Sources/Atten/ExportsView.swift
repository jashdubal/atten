import AttenCore
import SwiftUI

struct ExportsView: View {
    @Bindable var model: AppModel
    @State private var query = ""

    private var exports: [ProjectRecord] {
        model.projects.filter {
            FileManager.default.fileExists(atPath: $0.audioPath)
                && (query.isEmpty
                    || "\($0.title) \($0.audioURL.lastPathComponent)"
                        .localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: AttenSpacing.lg) {
                    header
                    statusArea

                    if exports.isEmpty {
                        AttenEmptyState(
                            title: query.isEmpty ? "No audio exports" : "No matching exports",
                            systemImage: "waveform.badge.magnifyingglass",
                            detail: query.isEmpty
                                ? "Generate speech in Studio and it will appear here."
                                : "Try a different search term."
                        )
                        .attenSurface()
                    } else {
                        exportList(isWide: proxy.size.width >= 860)
                    }
                }
                .padding(.horizontal, proxy.size.width < 700 ? AttenSpacing.lg : AttenSpacing.xl)
                .padding(.vertical, AttenSpacing.lg)
                .frame(maxWidth: 1120, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .searchable(text: $query, placement: .toolbar, prompt: "Search exports")
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            PageHeader(
                eyebrow: "Exports",
                title: "Audio files",
                detail: "Preview, rename, reveal, or save a copy."
            )
            Spacer()
            Text("\(exports.count) files")
                .font(AttenTypography.metadata)
                .foregroundStyle(AttenColor.textSecondary)
        }
    }

    @ViewBuilder private var statusArea: some View {
        if let success = model.successMessage {
            StatusBanner(kind: .success, message: success, dismiss: model.dismissStatus)
        }
        if case let .failed(message) = model.generationState {
            StatusBanner(kind: .error, message: message, dismiss: model.dismissStatus)
        }
    }

    private func exportList(isWide: Bool) -> some View {
        VStack(spacing: 0) {
            if isWide {
                HStack(spacing: AttenSpacing.sm) {
                    Text("Name").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Format").frame(width: 64, alignment: .leading)
                    Text("Size").frame(width: 82, alignment: .leading)
                    Text("Created").frame(width: 130, alignment: .leading)
                    Text("Duration").frame(width: 66, alignment: .leading)
                    Color.clear.frame(width: 34)
                }
                .font(AttenTypography.caption.weight(.semibold))
                .foregroundStyle(AttenColor.textSecondary)
                .padding(.horizontal, AttenSpacing.sm)
                .frame(height: 34)
                Divider().overlay(AttenColor.separator)
            }

            LazyVStack(spacing: 0) {
                ForEach(exports) { project in
                    ExportRow(model: model, project: project, isWide: isWide)
                    if project.id != exports.last?.id {
                        Divider()
                            .padding(.leading, 52)
                            .overlay(AttenColor.separator.opacity(0.8))
                    }
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

private struct ExportRow: View {
    @Bindable var model: AppModel
    let project: ProjectRecord
    let isWide: Bool
    @State private var name: String
    @State private var editingName = false
    @State private var isHovering = false

    init(model: AppModel, project: ProjectRecord, isWide: Bool) {
        self.model = model
        self.project = project
        self.isWide = isWide
        _name = State(initialValue: project.title)
    }

    private var metadata: AudioFileMetadata {
        AudioFileMetadata(url: project.audioURL)
    }

    private var isPlaying: Bool {
        model.isPlaying && model.activeAudioURL == project.audioURL
    }

    var body: some View {
        HStack(spacing: AttenSpacing.sm) {
            Button { model.togglePlayback(url: project.audioURL) } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(AttenTypography.caption.weight(.semibold))
                    .foregroundStyle(AttenColor.accent)
                    .frame(width: 30, height: 30)
                    .background(AttenColor.accent.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: AttenRadius.small))
            }
            .buttonStyle(.plain)
            .help(isPlaying ? "Pause \(project.title)" : "Preview \(project.title)")
            .accessibilityLabel(isPlaying ? "Pause \(project.title)" : "Preview \(project.title)")

            VStack(alignment: .leading, spacing: 3) {
                if editingName {
                    TextField("Export name", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { commitRename() }
                } else {
                    Text(project.audioURL.lastPathComponent)
                        .font(AttenTypography.control.weight(.semibold))
                        .foregroundStyle(AttenColor.textPrimary)
                        .lineLimit(1)
                }
                if !isWide {
                    Text("\(project.format.displayName) · \(metadata.sizeText) · \(metadata.durationText) · \(creationDate.formatted(date: .abbreviated, time: .omitted))")
                        .font(AttenTypography.caption)
                        .foregroundStyle(AttenColor.textSecondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isWide {
                Text(project.format.displayName).frame(width: 64, alignment: .leading)
                Text(metadata.sizeText).frame(width: 82, alignment: .leading)
                Text(creationDate.formatted(date: .abbreviated, time: .shortened))
                    .frame(width: 130, alignment: .leading)
                Text(metadata.durationText).frame(width: 66, alignment: .leading)
            }

            if editingName {
                Button("Cancel") {
                    name = project.title
                    editingName = false
                }
                .controlSize(.small)
                Button("Rename") { commitRename() }
                    .buttonStyle(.borderedProminent)
                    .tint(AttenColor.accent)
                    .controlSize(.small)
            } else {
                Menu { actionMenu } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 28, height: 28)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 30)
                .accessibilityLabel("Actions for \(project.title)")
            }
        }
        .font(AttenTypography.metadata)
        .foregroundStyle(AttenColor.textSecondary)
        .padding(.horizontal, AttenSpacing.sm)
        .frame(minHeight: isWide ? 54 : 64)
        .background(isHovering ? AttenColor.surfaceMuted.opacity(0.65) : .clear)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .contextMenu { actionMenu }
    }

    private var creationDate: Date {
        metadata.creationDate ?? project.createdAt
    }

    @ViewBuilder private var actionMenu: some View {
        Button("Rename…", systemImage: "pencil") { editingName = true }
        Button("Reveal in Finder", systemImage: "folder") { model.reveal(project) }
        Button("Export a Copy…", systemImage: "square.and.arrow.up") { model.export(project) }
    }

    private func commitRename() {
        model.rename(project, to: name)
        editingName = false
    }
}
