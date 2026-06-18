import AttenCore
import SwiftUI

struct ProjectsView: View {
    @Bindable var model: AppModel
    let openStudio: () -> Void
    @State private var query = ""
    @State private var projectToDelete: ProjectRecord?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AttenSpacing.lg) {
                SectionHeader(
                    eyebrow: "Projects",
                    title: "Your growing library",
                    detail: "Return to previous generations, reuse their settings, or make another take."
                )

                if filteredProjects.isEmpty {
                    ContentUnavailableView {
                        Label(query.isEmpty ? "No projects yet" : "No matching projects", systemImage: "square.stack.3d.up")
                    } description: {
                        Text(query.isEmpty ? "Your completed Studio generations will appear here." : "Try a different search term.")
                    } actions: {
                        if query.isEmpty {
                            Button("Open Studio", action: openStudio)
                                .buttonStyle(AttenPrimaryButtonStyle())
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 420)
                    .attenCard()
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredProjects) { project in
                            ProjectRow(
                                model: model,
                                project: project,
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
                        }
                    }
                }
            }
            .padding(AttenSpacing.xl)
            .frame(maxWidth: 1050, alignment: .topLeading)
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
            Button("Cancel", role: .cancel) { projectToDelete = nil }
        } message: {
            Text("The audio file remains on disk and can still be found in Exports.")
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
    let duplicate: () -> Void
    let regenerate: () -> Void
    let delete: () -> Void

    private var voice: Voice {
        VoiceCatalog.voice(id: project.voiceID) ?? VoiceCatalog.all[0]
    }

    var body: some View {
        HStack(spacing: AttenSpacing.md) {
            Button {
                model.togglePlayback(url: project.audioURL)
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AttenColor.river.opacity(0.12))
                    Image(systemName: "play.fill")
                        .foregroundStyle(AttenColor.river)
                }
                .frame(width: 48, height: 48)
            }
            .buttonStyle(.plain)
            .disabled(!FileManager.default.fileExists(atPath: project.audioPath))
            .accessibilityLabel("Play \(project.title)")

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Text(project.title)
                        .font(.headline)
                        .foregroundStyle(AttenColor.ink)
                    if project.isLegacyImport {
                        Text("Imported")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AttenColor.sunlight.opacity(0.18))
                            .clipShape(Capsule())
                    }
                }
                Text(project.text)
                    .font(.callout)
                    .foregroundStyle(AttenColor.secondaryInk)
                    .lineLimit(1)
                Text("\(voice.name) • \(String(format: "%.2f×", project.speed)) • \(project.format.displayName) • \(project.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Menu {
                Button("Duplicate in Studio", systemImage: "plus.square.on.square", action: duplicate)
                Button("Regenerate", systemImage: "arrow.clockwise", action: regenerate)
                Divider()
                Button("Export…", systemImage: "square.and.arrow.up") { model.export(project) }
                Button("Reveal in Finder", systemImage: "folder") { model.reveal(project) }
                Divider()
                Button("Delete Project", systemImage: "trash", role: .destructive, action: delete)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 30)
            .accessibilityLabel("Actions for \(project.title)")
        }
        .attenCard()
    }
}
