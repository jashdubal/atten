import AppKit
import AttenCore
import SwiftUI
import UniformTypeIdentifiers

/// What "Export…" is exporting: a finished narration, whether it came from a
/// book or a legacy project. The sheet only ever needs a name and a source
/// file — everything else about where that audio came from is the caller's
/// business, not the export flow's.
struct ExportTarget: Identifiable {
    let id = UUID()
    let title: String
    let sourceURL: URL
    /// M4A only makes sense for a whole audiobook — a legacy project's own
    /// narration format is already MP3 or WAV.
    let allowsM4A: Bool

    init?(book: BookRecord) {
        guard let sourceURL = book.audioURL else { return nil }
        title = book.title
        self.sourceURL = sourceURL
        allowsM4A = true
    }

    init(project: ProjectRecord) {
        title = project.title
        sourceURL = project.audioURL
        allowsM4A = false
    }
}

enum ExportAudioFormat: String, CaseIterable, Identifiable, Hashable {
    case mp3, wav, m4a

    var id: String { rawValue }
    var title: String { rawValue.uppercased() }

    var contentType: UTType {
        switch self {
        case .mp3: .mp3
        case .wav: .wav
        case .m4a: .mpeg4Audio
        }
    }
}

/// Export becomes a real screen rather than an instant save panel: choose a
/// format, then choose where. WAV and M4A are encoded with AVFoundation; MP3
/// goes through the backend's own transcoder, since AVFoundation has no MP3
/// encoder on macOS.
struct ExportSheet: View {
    @Bindable var model: AppModel
    let target: ExportTarget

    @Environment(\.dismiss) private var dismiss
    @State private var format: ExportAudioFormat = .mp3
    @State private var isExporting = false
    @State private var errorMessage: String?

    private var availableFormats: [ExportAudioFormat] {
        target.allowsM4A ? [.mp3, .wav, .m4a] : [.mp3, .wav]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AttenSpacing.lg) {
            Text("Export “\(target.title)”")
                .attenText(.title2)
                .foregroundStyle(AttenColor.text1)
                .lineLimit(1)

            VStack(alignment: .leading, spacing: AttenSpacing.sm) {
                Text("Format").attenText(.label).foregroundStyle(AttenColor.text2)
                Picker("Format", selection: $format) {
                    ForEach(availableFormats) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            if let errorMessage {
                Text(errorMessage)
                    .attenText(.callout)
                    .foregroundStyle(AttenColor.destructive)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(AttenTertiaryButtonStyle())
                Button(isExporting ? "Exporting…" : "Export…", action: export)
                    .buttonStyle(AttenPrimaryButtonStyle())
                    .disabled(isExporting)
            }
        }
        .padding(AttenSpacing.xl)
        .frame(width: 360)
        .onAppear {
            if !availableFormats.contains(format) { format = .mp3 }
        }
    }

    private func export() {
        let panel = NSSavePanel()
        panel.title = "Export from Atten"
        panel.allowedContentTypes = [format.contentType]
        panel.nameFieldStringValue = ExportService.safeFilename(target.title) + "." + format.rawValue
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        isExporting = true
        errorMessage = nil
        let format = format
        let source = target.sourceURL
        Task {
            defer { isExporting = false }
            do {
                switch format {
                case .mp3: try await TranscodeService.mp3(from: source, to: destination)
                case .wav: try await WAVAudioExport.export(source, to: destination)
                case .m4a: try await BookAudioExport.export(source, to: destination)
                }
                model.bookshelf.successMessage = "Exported \(destination.lastPathComponent)."
                dismiss()
            } catch {
                errorMessage = "Export failed: \(error.localizedDescription)"
            }
        }
    }
}
