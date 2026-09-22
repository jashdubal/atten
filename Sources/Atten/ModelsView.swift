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
                                    availableWidth: proxy.size.width,
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
                .padding(.horizontal, proxy.size.width < 700 ? AttenSpacing.lg : AttenSpacing.xl)
                .padding(.vertical, AttenSpacing.lg)
                .frame(maxWidth: 1120, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .top)
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
        HStack(alignment: .bottom) {
            PageHeader(
                eyebrow: "Models",
                title: "Model library",
                detail: "Discover Hugging Face speech models and keep them offline."
            )
            Spacer()
            AttenSearchField(prompt: "Search Hugging Face", text: queryBinding)
                .frame(maxWidth: 240)
            if library.isSearching {
                ProgressView().controlSize(.small)
            }
            Text("\(library.installed.count) installed")
                .font(AttenTypography.metadata)
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
        HStack(spacing: AttenSpacing.sm) {
            Picker("Language", selection: library.language) {
                Text(ModelLibrary.allLanguages).tag(ModelLibrary.allLanguages)
                ForEach(HuggingFaceCatalog.languages, id: \.self) { Text($0).tag($0) }
            }
            .frame(width: 200)

            Picker("Show", selection: library.installFilter) {
                ForEach(ModelLibrary.InstallFilter.allCases) { Text($0.rawValue).tag($0) }
            }
            .frame(width: 230)

            Picker("Sort", selection: library.sort) {
                ForEach(HFSort.allCases) { Text($0.rawValue).tag($0) }
            }
            .frame(width: 210)

            Spacer()

            Button {
                self.library.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(self.library.isSearching)
            .help("Refresh")
            .accessibilityLabel("Refresh")
        }
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
                    .foregroundStyle(isInstalled ? AttenColor.success : AttenColor.accent)
                    .frame(width: 36, height: 36)
                    .background(AttenColor.surfaceMuted)
                    .clipShape(RoundedRectangle(cornerRadius: AttenRadius.control))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: AttenSpacing.xs) {
                        Text(model.name)
                            .font(AttenTypography.control.weight(.semibold))
                        if !model.author.isEmpty {
                            Text(model.author)
                                .font(AttenTypography.caption)
                                .foregroundStyle(AttenColor.textSecondary)
                        }
                    }
                    Text(model.languages)
                        .font(AttenTypography.caption)
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
                progress(download)
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
        .font(AttenTypography.caption)
        .foregroundStyle(AttenColor.textSecondary)
        .labelStyle(.titleAndIcon)
    }

    @ViewBuilder private var actions: some View {
        switch download?.phase {
        case .downloading:
            Button("Pause", systemImage: "pause.fill", action: onPause)
                .buttonStyle(.bordered)
                .controlSize(.small)
            cancelButton
        case .paused, .failed:
            Button("Resume", systemImage: "arrow.down.circle", action: onDownload)
                .buttonStyle(.borderedProminent)
                .tint(AttenColor.accent)
                .controlSize(.small)
            cancelButton
        case nil:
            if isBundled {
                Text("BUNDLED")
                    .font(AttenTypography.caption.weight(.semibold))
                    .foregroundStyle(AttenColor.success)
            } else if isInstalled {
                Text("INSTALLED")
                    .font(AttenTypography.caption.weight(.semibold))
                    .foregroundStyle(AttenColor.success)
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Delete \(model.id)")
                .accessibilityLabel("Delete \(model.id)")
            } else {
                Button("Download", systemImage: "arrow.down.circle", action: onDownload)
                    .buttonStyle(.borderedProminent)
                    .tint(AttenColor.accent)
                    .controlSize(.small)
            }
        }
    }

    private var cancelButton: some View {
        Button(action: onCancel) { Image(systemName: "xmark") }
            .buttonStyle(.borderless)
            .help("Cancel and remove partial files")
            .accessibilityLabel("Cancel download of \(model.id)")
    }

    private func progress(_ state: ModelLibrary.DownloadState) -> some View {
        let phase: AttenTaskPhase
        switch state.phase {
        case .downloading: phase = .active
        case .paused: phase = .cancelled
        case .failed: phase = .error
        }
        let metadata = [
            state.progress.sizeText,
            state.progress.speed,
            state.progress.eta.isEmpty ? "" : "ETA \(state.progress.eta)",
        ]
        .filter { !$0.isEmpty }
        .joined(separator: " · ")

        return AttenProgressStatus(
            title: "Download \(model.name)",
            detail: statusText(state),
            phase: phase,
            progress: state.progress.fraction,
            progressLabel: state.progress.fraction == nil ? nil : "\(state.progress.percent)%",
            metadata: metadata.isEmpty ? nil : metadata
        )
    }

    private func statusText(_ state: ModelLibrary.DownloadState) -> String {
        if case let .failed(message) = state.phase { return "Stopped: \(message)" }
        return state.progress.status
    }

}
