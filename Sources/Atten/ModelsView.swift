import AttenCore
import SwiftUI

struct ModelsView: View {
    @Bindable var model: AppModel
    @State private var pendingDeletion: String?

    private var library: ModelLibrary { model.library }

    var body: some View {
        @Bindable var library = model.library
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: AttenSpacing.lg) {
                    header
                    statusArea
                    filters(library: $library)

                    let models = library.visibleModels
                    if models.isEmpty {
                        AttenEmptyState(
                            title: library.isSearching ? "Searching Hugging Face…" : "No models found",
                            systemImage: "shippingbox",
                            detail: "Try another search, language, or filter."
                        )
                        .attenSurface()
                    } else {
                        LazyVStack(spacing: 1) {
                            ForEach(models) { hfModel in
                                ModelRow(
                                    model: hfModel,
                                    isInstalled: library.isInstalled(hfModel.id),
                                    isBundled: hfModel.id == ModelStore.kokoroID,
                                    download: library.downloads[hfModel.id],
                                    availableWidth: min(proxy.size.width, SettingsColumn.maxWidth),
                                    onDownload: { library.download(hfModel.id) },
                                    onPause: { library.pause(hfModel.id) },
                                    onCancel: { library.cancel(hfModel.id) },
                                    onDelete: { pendingDeletion = hfModel.id }
                                )
                                if hfModel.id != models.last?.id {
                                    Divider().overlay(AttenColor.separator.opacity(0.8))
                                }
                            }
                        }
                        .padding(.vertical, AttenSpacing.xxs)
                        .background(AttenColor.surface)
                        .clipShape(RoundedRectangle(cornerRadius: AttenRadius.card))
                        .overlay {
                            RoundedRectangle(cornerRadius: AttenRadius.card)
                                .stroke(AttenColor.separator.opacity(0.72), lineWidth: 1)
                        }
                    }
                }
                // Settings' column, under its title and tabs.
                .frame(maxWidth: SettingsColumn.maxWidth, alignment: .topLeading)
                .padding(.horizontal, SettingsColumn.gutter)
                .padding(.top, AttenSpacing.xs)
                .attenScrollPadding()
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .confirmationDialog(
            "Delete \(pendingDeletion ?? "model")?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let pendingDeletion { library.delete(pendingDeletion) }
                pendingDeletion = nil
            }
        } message: {
            Text("The downloaded weights are removed from disk. You can download them again later.")
        }
    }

    private var queryBinding: Binding<String> {
        Binding(get: { library.query }, set: { library.query = $0 })
    }

    private var header: some View {
        HStack(spacing: AttenSpacing.sm) {
            AttenSearchField(prompt: "Search Hugging Face", text: queryBinding)
                .frame(maxWidth: 320)
            if library.isSearching {
                ProgressView().controlSize(.small)
            }
            Spacer()
            Text("\(library.installed.count) installed")
                .font(AttenTypography.callout)
                .foregroundStyle(AttenColor.textSecondary)
        }
    }

    @ViewBuilder private var statusArea: some View {
        if let message = library.lastMessage {
            StatusBanner(kind: .success, message: message) { library.lastMessage = nil }
        }
        if let message = library.cancelledMessage {
            StatusBanner(kind: .cancelled, message: message) { library.cancelledMessage = nil }
        }
        if let error = library.searchError {
            StatusBanner(kind: .warning, message: error) { library.searchError = nil }
        }
    }

    private func filters(library: Bindable<ModelLibrary>) -> some View {
        HStack(spacing: AttenSpacing.md) {
            quietMenu("Language", value: self.library.language) {
                Picker("Language", selection: library.language) {
                    Text(ModelLibrary.allLanguages).tag(ModelLibrary.allLanguages)
                    ForEach(HuggingFaceCatalog.languages, id: \.self) { Text($0).tag($0) }
                }
            }
            quietMenu("Show", value: self.library.installFilter.rawValue) {
                Picker("Show", selection: library.installFilter) {
                    ForEach(ModelLibrary.InstallFilter.allCases) { Text($0.rawValue).tag($0) }
                }
            }
            quietMenu("Sort by", value: self.library.sort.rawValue) {
                Picker("Sort by", selection: library.sort) {
                    ForEach(HFSort.allCases) { Text($0.rawValue).tag($0) }
                }
            }

            Spacer()

            Button {
                self.library.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(AttenTertiaryButtonStyle())
            .disabled(self.library.isSearching)
            .help("Refresh")
            .accessibilityLabel("Refresh")
        }
    }

    /// A label and a borderless menu, as the Library's "Sort by" is drawn.
    private func quietMenu(_ title: String, value: String, @ViewBuilder picker: () -> some View) -> some View {
        HStack(spacing: AttenSpacing.xs) {
            Text(title)
                .foregroundStyle(AttenColor.textMuted)
            Menu {
                picker()
            } label: {
                Text(value)
            }
            .menuStyle(.borderlessButton)
            .tint(AttenColor.text2)
            .fixedSize()
        }
        .font(AttenTypography.callout)
    }
}

private struct ModelRow: View {
    let model: HFModel
    let isInstalled: Bool
    let isBundled: Bool
    let download: ModelLibrary.DownloadState?
    let availableWidth: CGFloat
    let onDownload: () -> Void
    let onPause: () -> Void
    let onCancel: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: AttenSpacing.xs) {
            HStack(spacing: AttenSpacing.sm) {
                Image(systemName: isInstalled ? "checkmark.seal.fill" : "shippingbox")
                    .font(.system(size: 18))
                    .foregroundStyle(isInstalled ? AttenColor.success : AttenColor.text2)
                    .frame(width: 36, height: 36)
                    .background(AttenColor.surfaceMuted)
                    .clipShape(RoundedRectangle(cornerRadius: AttenRadius.control))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: AttenSpacing.xs) {
                        Text(model.name)
                            .font(AttenTypography.callout.weight(.semibold))
                        if !model.author.isEmpty {
                            Text(model.author)
                                .font(AttenTypography.callout)
                                .foregroundStyle(AttenColor.textSecondary)
                        }
                    }
                    Text(model.languages)
                        .font(AttenTypography.callout)
                        .foregroundStyle(AttenColor.textSecondary)
                        .lineLimit(1)
                }
                .frame(minWidth: 180, alignment: .leading)

                Spacer(minLength: AttenSpacing.xs)

                if availableWidth >= 820 {
                    metadata
                }

                actions
            }

            if let download {
                ModelDownloadStatus(state: download, retry: onDownload)
                    .padding(.leading, 48)
            }
        }
        .padding(.horizontal, AttenSpacing.sm)
        .padding(.vertical, AttenSpacing.xs)
        .frame(minHeight: 58)
        .background(isHovering ? AttenColor.surfaceMuted.opacity(0.65) : .clear)
        .onHover { isHovering = $0 }
        .contextMenu {
            Link("View on Hugging Face", destination: URL(string: "https://huggingface.co/\(model.id)")!)
        }
        .accessibilityElement(children: .contain)
    }

    private var metadata: some View {
        HStack(spacing: AttenSpacing.sm) {
            if model.downloads > 0 {
                Label(model.downloadsText, systemImage: "arrow.down.circle")
            }
            if model.likes > 0 {
                Label(model.likesText, systemImage: "star")
            }
            Text(model.sizeText)
                .frame(minWidth: 70, alignment: .trailing)
        }
        .font(AttenTypography.callout)
        .foregroundStyle(AttenColor.textSecondary)
        .labelStyle(.titleAndIcon)
    }

    @ViewBuilder private var actions: some View {
        switch download?.phase {
        case .downloading:
            Button("Pause", systemImage: "pause.fill", action: onPause)
                .buttonStyle(AttenSecondaryButtonStyle())
            cancelButton
        case .paused:
            Button("Resume", systemImage: "arrow.down.circle", action: onDownload)
                .buttonStyle(AttenSecondaryButtonStyle())
            cancelButton
        case .failed:
            // Retry sits beside the reason, under the row.
            cancelButton
        case nil:
            if isBundled {
                Text("BUNDLED")
                    .font(AttenTypography.callout.weight(.semibold))
                    .foregroundStyle(AttenColor.success)
            } else if isInstalled {
                Text("INSTALLED")
                    .font(AttenTypography.callout.weight(.semibold))
                    .foregroundStyle(AttenColor.success)
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .tint(AttenColor.text2)
                .help("Delete \(model.id)")
                .accessibilityLabel("Delete \(model.id)")
            } else {
                Button("Download", systemImage: "arrow.down.circle", action: onDownload)
                    .buttonStyle(AttenSecondaryButtonStyle())
            }
        }
    }

    private var cancelButton: some View {
        Button(action: onCancel) { Image(systemName: "xmark") }
            .buttonStyle(.borderless)
            .tint(AttenColor.text2)
            .help("Cancel and remove partial files")
            .accessibilityLabel("Cancel download of \(model.id)")
    }

}
