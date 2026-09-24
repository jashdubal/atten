import AttenCore
import SwiftUI

/// Studio generations from before books, on the shelf with everything else.
///
/// They are `LibraryItem.project`s: read from `projects.json` and never
/// migrated. This keeps them reachable and playable now that Projects and
/// Exports are no longer places of their own; the Library's visual pass gives
/// them their final look.
struct LibraryProjectsSection: View {
    @Bindable var model: AppModel
    let items: [AttenCore.LibraryItem]
    let isWide: Bool

    @State private var projectToDelete: ProjectRecord?
    @State private var projectToRename: ProjectRecord?
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: AttenSpacing.sm) {
            Text("Projects")
                .attenText(.label)
                .foregroundStyle(AttenColor.text3)
                .accessibilityAddTraits(.isHeader)
            LazyVStack(spacing: 0) {
                ForEach(items) { item in
                    if case let .project(project) = item {
                        ProjectRow(
                            model: model,
                            project: project,
                            isWide: isWide,
                            duplicate: {
                                model.duplicate(project)
                                model.section = .studio
                            },
                            regenerate: {
                                model.regenerate(project)
                                model.section = .studio
                            },
                            rename: {
                                name = project.title
                                projectToRename = project
                            },
                            delete: { projectToDelete = project }
                        )
                        if item.id != items.last?.id {
                            Divider()
                                .padding(.leading, 52)
                                .overlay(AttenColor.separator.opacity(0.8))
                        }
                    }
                }
            }
        }
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
        .alert(
            "Rename audio file",
            isPresented: Binding(
                get: { projectToRename != nil },
                set: { if !$0 { projectToRename = nil } }
            )
        ) {
            TextField("Name", text: $name)
            Button("Rename") {
                if let projectToRename { model.rename(projectToRename, to: name) }
                projectToRename = nil
            }
            Button("Cancel", role: .cancel) { projectToRename = nil }
        }
    }
}

private struct ProjectRow: View {
    @Bindable var model: AppModel
    let project: ProjectRecord
    let isWide: Bool
    let duplicate: () -> Void
    let regenerate: () -> Void
    let rename: () -> Void
    let delete: () -> Void

    @State private var isHovering = false
    /// Filled in once the file has been measured, off the main thread. A row
    /// that measured it while drawing reopened the file on every redraw.
    @State private var metadata: AudioFileMetadata?

    private var voice: Voice {
        VoiceCatalog.voice(id: project.voiceID) ?? VoiceCatalog.defaultVoice
    }

    private var fileExists: Bool {
        FileManager.default.fileExists(atPath: project.audioPath)
    }

    private var isPlaying: Bool {
        model.isPlaying && model.activeAudioURL == project.audioURL
    }

    var body: some View {
        HStack(spacing: AttenSpacing.sm) {
            Button {
                model.togglePlayback(
                    track: PlaybackTrack(
                        id: project.id,
                        url: project.audioURL,
                        title: project.title,
                        subtitle: voice.name
                    )
                )
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(AttenTypography.caption.weight(.semibold))
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
                        .font(AttenTypography.control.weight(.semibold))
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
                    Text("\(voice.name) · \(project.format.displayName) · \(durationText) · \(project.updatedAt.formatted(date: .abbreviated, time: .omitted))")
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
                Text("\(project.format.displayName) · \(durationText)")
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
        .audioMetadata(of: project.audioURL) { metadata = $0 }
    }

    private var durationText: String { metadata?.durationText ?? "—" }

    @ViewBuilder private var actionMenu: some View {
        if !project.isLegacyImport {
            Button("Duplicate in Studio", systemImage: "plus.square.on.square", action: duplicate)
            Button("Regenerate", systemImage: "arrow.clockwise", action: regenerate)
            Divider()
        }
        Button("Rename…", systemImage: "pencil", action: rename)
            .disabled(!fileExists)
        Button("Export…", systemImage: "square.and.arrow.up") { model.export(project) }
            .disabled(!fileExists)
        Button("Reveal in Finder", systemImage: "folder") { model.reveal(project) }
            .disabled(!fileExists)
        Divider()
        Button("Delete Project…", systemImage: "trash", role: .destructive, action: delete)
    }
}
