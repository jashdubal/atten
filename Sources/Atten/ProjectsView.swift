import AttenCore
import SwiftUI

struct ProjectsView: View {
    @Bindable var model: AppModel
    let openStudio: () -> Void
    @State private var query = ""
    @State private var projectToDelete: ProjectRecord?

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: AttenSpacing.lg) {
                    header
                    statusArea

                    if filteredProjects.isEmpty {
                        emptyState
                    } else {
                        projectList(isWide: proxy.size.width >= 820)
                    }
                }
                .padding(.horizontal, proxy.size.width < 700 ? AttenSpacing.lg : AttenSpacing.xl)
                .padding(.vertical, AttenSpacing.lg)
                .frame(maxWidth: 1120, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .searchable(text: $query, placement: .toolbar, prompt: "Search projects")
        .confirmationDialog(
            "Delete this project from Atten?",
            isPresented: Binding(
                get: { projectToDelete != nil },
                set: { if !$0 { projectToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Project", role: .destructive) {
                if let projectToDelete { model.delete(projectToDelete) }
                projectToDelete = nil
            }
            if let projectToDelete, !projectToDelete.isLegacyImport {
                Button("Delete Project and Audio", role: .destructive) {
                    model.delete(projectToDelete, includingAudio: true)
                    self.projectToDelete = nil
                }
            }
            Button("Cancel", role: .cancel) { projectToDelete = nil }
        } message: {
            Text("Choose whether the generated audio should remain on disk.")
        }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            PageHeader(
                eyebrow: "Projects",
                title: "Project library",
                detail: "Return to previous generations or make another take."
            )
            Spacer()
            Text("\(filteredProjects.count) projects")
                .font(AttenTypography.metadata)
                .foregroundStyle(AttenColor.textSecondary)
        }
    }

    private var emptyState: some View {
        VStack(spacing: AttenSpacing.md) {
            AttenEmptyState(
                title: query.isEmpty ? "No projects yet" : "No matching projects",
                systemImage: "doc.on.doc",
                detail: query.isEmpty
                    ? "Completed Studio generations will appear here."
                    : "Try a different search term."
            )
            if query.isEmpty {
                Button("Open Studio", action: openStudio)
                    .buttonStyle(AttenPrimaryButtonStyle())
                    .fixedSize()
                    .padding(.bottom, AttenSpacing.lg)
            }
        }
        .attenSurface()
    }

    @ViewBuilder private var statusArea: some View {
        if let success = model.successMessage {
            StatusBanner(kind: .success, message: success, dismiss: model.dismissStatus)
        }
        if case let .failed(message) = model.generationState {
            StatusBanner(kind: .error, message: message, dismiss: model.dismissStatus)
        }
    }

    private func projectList(isWide: Bool) -> some View {
        VStack(spacing: 0) {
            if isWide {
                HStack(spacing: AttenSpacing.sm) {
                    Text("Project").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Voice").frame(width: 120, alignment: .leading)
                    Text("Updated").frame(width: 135, alignment: .leading)
                    Text("Details").frame(width: 100, alignment: .leading)
                    Color.clear.frame(width: 70)
                }
                .font(AttenTypography.caption.weight(.semibold))
                .foregroundStyle(AttenColor.textSecondary)
                .padding(.horizontal, AttenSpacing.sm)
                .frame(height: 34)
                Divider().overlay(AttenColor.separator)
            }

            LazyVStack(spacing: 0) {
                ForEach(filteredProjects) { project in
                    ProjectRow(
                        model: model,
                        project: project,
                        isWide: isWide,
                        duplicate: {
                            model.duplicate(project)
                            openStudio()
                        },
                        regenerate: {
                            model.regenerate(project)
                            openStudio()
                        },
                        delete: { projectToDelete = project }
                    )
                    if project.id != filteredProjects.last?.id {
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

    private var filteredProjects: [ProjectRecord] {
        guard !query.isEmpty else { return model.projects }
        return model.projects.filter { project in
            let voice = VoiceCatalog.voice(id: project.voiceID)?.name ?? project.voiceID
            return "\(project.title) \(project.text) \(voice)"
                .localizedCaseInsensitiveContains(query)
        }
    }
}

private struct ProjectRow: View {
    @Bindable var model: AppModel
    let project: ProjectRecord
    let isWide: Bool
    let duplicate: () -> Void
    let regenerate: () -> Void
    let delete: () -> Void

    @State private var isHovering = false

    private var voice: Voice {
        VoiceCatalog.voice(id: project.voiceID) ?? VoiceCatalog.all[0]
    }

    private var fileExists: Bool {
        FileManager.default.fileExists(atPath: project.audioPath)
    }

    private var isPlaying: Bool {
        model.isPlaying && model.activeAudioURL == project.audioURL
    }

    private var metadata: AudioFileMetadata {
        AudioFileMetadata(url: project.audioURL)
    }

    var body: some View {
        HStack(spacing: AttenSpacing.sm) {
            Button { model.togglePlayback(url: project.audioURL) } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(fileExists ? AttenColor.accent : AttenColor.textSecondary)
                    .frame(width: 30, height: 30)
                    .background(AttenColor.accent.opacity(fileExists ? 0.10 : 0.04))
                    .clipShape(RoundedRectangle(cornerRadius: AttenRadius.small))
            }
            .buttonStyle(.plain)
            .disabled(!fileExists)
            .help(fileExists ? "Play \(project.title)" : "Audio file is missing")
            .accessibilityLabel(isPlaying ? "Pause \(project.title)" : "Play \(project.title)")

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: AttenSpacing.xs) {
                    Text(project.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AttenColor.textPrimary)
                        .lineLimit(1)
                    if project.isLegacyImport {
                        Text("Imported")
                            .font(AttenTypography.caption)
                            .foregroundStyle(AttenColor.warning)
                    }
                    if !fileExists {
                        Label("Missing", systemImage: "exclamationmark.triangle")
                            .font(AttenTypography.caption)
                            .foregroundStyle(AttenColor.destructive)
                    }
                }
                Text(project.text)
                    .font(AttenTypography.metadata)
                    .foregroundStyle(AttenColor.textSecondary)
                    .lineLimit(1)
                if !isWide {
                    Text("\(voice.name) · \(project.format.displayName) · \(metadata.durationText) · \(project.updatedAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(AttenTypography.caption)
                        .foregroundStyle(AttenColor.textSecondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isWide {
                Text(voice.name)
                    .frame(width: 120, alignment: .leading)
                Text(project.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    .frame(width: 135, alignment: .leading)
                Text("\(project.format.displayName) · \(metadata.durationText)")
                    .frame(width: 100, alignment: .leading)
            }

            Menu { actionMenu } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 28, height: 28)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 30)
            .accessibilityLabel("Actions for \(project.title)")
        }
        .font(AttenTypography.metadata)
        .foregroundStyle(AttenColor.textSecondary)
        .padding(.horizontal, AttenSpacing.sm)
        .frame(minHeight: isWide ? 64 : 72)
        .background(isHovering ? AttenColor.surfaceMuted.opacity(0.65) : .clear)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .contextMenu { actionMenu }
    }

    @ViewBuilder private var actionMenu: some View {
        if !project.isLegacyImport {
            Button("Duplicate in Studio", systemImage: "plus.square.on.square", action: duplicate)
            Button("Regenerate", systemImage: "arrow.clockwise", action: regenerate)
            Divider()
        }
        Button("Export…", systemImage: "square.and.arrow.up") { model.export(project) }
            .disabled(!fileExists)
        Button("Reveal in Finder", systemImage: "folder") { model.reveal(project) }
            .disabled(!fileExists)
        Divider()
        Button("Delete Project…", systemImage: "trash", role: .destructive, action: delete)
    }
}
