import AttenCore
import SwiftUI

struct ExportsView: View {
    @Bindable var model: AppModel
    @State private var query = ""

    private var exports: [ProjectRecord] {
        model.projects.filter {
            FileManager.default.fileExists(atPath: $0.audioPath)
                && (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AttenSpacing.lg) {
                SectionHeader(
                    eyebrow: "Exports",
                    title: "Ready for the trail",
                    detail: "Preview, rename, save a copy, or reveal generated audio in Finder."
                )

                if exports.isEmpty {
                    ContentUnavailableView(
                        "No audio exports",
                        systemImage: "arrow.up.doc",
                        description: Text("Generate speech in Studio and it will appear here.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 420)
                    .attenCard()
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(exports) { project in
                            ExportRow(model: model, project: project)
                        }
                    }
                }
            }
            .padding(AttenSpacing.xl)
            .frame(maxWidth: 1000, alignment: .topLeading)
        }
        .searchable(text: $query, placement: .toolbar, prompt: "Search exports")
    }
}

private struct ExportRow: View {
    @Bindable var model: AppModel
    let project: ProjectRecord
    @State private var name: String
    @State private var editingName = false

    init(model: AppModel, project: ProjectRecord) {
        self.model = model
        self.project = project
        _name = State(initialValue: project.title)
    }

    var body: some View {
        HStack(spacing: AttenSpacing.md) {
            Button { model.togglePlayback(url: project.audioURL) } label: {
                Image(systemName: "waveform")
                    .font(.title2)
                    .foregroundStyle(AttenColor.river)
                    .frame(width: 48, height: 48)
                    .background(AttenColor.river.opacity(0.11))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Preview \(project.title)")

            VStack(alignment: .leading, spacing: 5) {
                if editingName {
                    TextField("Export name", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { commitRename() }
                } else {
                    Text(project.title)
                        .font(.headline)
                        .foregroundStyle(AttenColor.ink)
                }
                Text("\(project.format.displayName) • \(fileSize) • \(project.audioURL.deletingLastPathComponent().lastPathComponent)")
                    .font(.caption)
                    .foregroundStyle(AttenColor.secondaryInk)
            }

            Spacer()

            if editingName {
                Button("Cancel") {
                    name = project.title
                    editingName = false
                }
                Button("Rename") { commitRename() }
                    .buttonStyle(.borderedProminent)
                    .tint(AttenColor.forest)
            } else {
                Button("Rename", systemImage: "pencil") { editingName = true }
                Button("Reveal", systemImage: "folder") { model.reveal(project) }
                Button("Export…", systemImage: "square.and.arrow.up") { model.export(project) }
                    .buttonStyle(.borderedProminent)
                    .tint(AttenColor.forest)
            }
        }
        .attenCard()
    }

    private var fileSize: String {
        guard let values = try? project.audioURL.resourceValues(forKeys: [.fileSizeKey]),
              let bytes = values.fileSize else { return "Unknown size" }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private func commitRename() {
        model.rename(project, to: name)
        editingName = false
    }
}
