import AppKit
import AttenCore
import Foundation
import SwiftUI
import XCTest
@testable import Atten

/// Offscreen renders of a model download in each state (#114) — in
/// Settings → Models, on a casting card and in Voices — and of Create with
/// Generate held back for a voice whose model is missing, and of a book's
/// page cast in such a voice (#118). The downloader is a stub, so nothing is
/// fetched. Gated behind `ATTEN_RENDER_DIR`, like
/// `VoicesSettingsRenderTests`, whose hosting-window harness this shares.
@MainActor
final class ModelStatesRenderTests: XCTestCase {
    func testModelStatesRenderInBothAppearances() async throws {
        guard let renderDirPath = ProcessInfo.processInfo.environment["ATTEN_RENDER_DIR"] else {
            throw XCTSkip("Set ATTEN_RENDER_DIR to render the model states")
        }
        let renderDir = URL(fileURLWithPath: renderDirPath, isDirectory: true)
        try FileManager.default.createDirectory(at: renderDir, withIntermediateDirectories: true)

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttenModelStatesRender-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "AttenModelStatesRender.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let failures = [
            "facebook/mms-tts-deu": "Download failed: [Errno 28] No space left on device",
            "facebook/mms-tts-spa": "Download failed: <urlopen error [Errno 8] nodename nor servname provided, or not known>",
            "facebook/mms-tts-cmn": "Download failed: <urlopen error [Errno 8] nodename nor servname provided, or not known>",
        ]
        let library = ModelLibrary(
            store: ModelStore(root: directory.appendingPathComponent("models", isDirectory: true)),
            downloader: StubDownloader { modelID in throw BackendError.processFailed(failures[modelID] ?? "") },
            sizeCacheURL: directory.appendingPathComponent("sizes.json")
        )
        let model = AppModel(
            directories: AppDirectories(applicationSupport: directory),
            settingsStore: SettingsStore(defaults: defaults),
            generator: ImmediateGenerator(),
            library: library
        )
        library.rescanInstalled()
        library.discovered = ModelLibrary.fallbackModels
        for modelID in failures.keys { library.download(modelID) }
        for _ in 0..<200 where library.downloads.values.contains(where: { $0.phase == .downloading }) {
            try await Task.sleep(for: .milliseconds(10))
        }
        let downloading = ModelLibrary.DownloadState(
            phase: .downloading,
            progress: ModelDownloadProgress(
                percent: 42, status: "Downloading model.safetensors (2/5)", speed: "3.1 MB/s",
                eta: "52s", sizeText: "122.0 MB / 290.0 MB"
            )
        )
        library.downloads["facebook/mms-tts-ara"] = downloading
        library.downloads["facebook/mms-tts-jpn"] = downloading
        library.downloads["facebook/mms-tts-fra"] = downloading
        library.downloads["facebook/mms-tts-fra"]?.progress.percent = 18
        library.downloads["facebook/mms-tts-fra"]?.progress.sizeText = "52.0 MB / 290.0 MB"
        library.pause("facebook/mms-tts-fra")

        let voices = try ["af_heart", "jf_alpha", "zf_xiaoyan", "hf_ananya"].map { try XCTUnwrap(VoiceCatalog.voice(id: $0)) }
        model.selectVoice(voices[0])
        model.settingsTab = "models"

        for dark in [false, true] {
            let suffix = dark ? "dark" : "light"
            try await render(SettingsView(model: model), dark: dark, size: CGSize(width: 1000, height: 980), to: renderDir.appendingPathComponent("models-\(suffix).png"))
            try await render(
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: AttenSpacing.sm)], spacing: AttenSpacing.sm) {
                    ForEach(voices) { voice in
                        CastingCard(model: model, voice: voice, isSelected: voice.id == "af_heart", previewFlow: model.createFlow) {}
                    }
                }
                .padding(AttenSpacing.lg),
                dark: dark, size: CGSize(width: 780, height: 420),
                to: renderDir.appendingPathComponent("casting-\(suffix).png")
            )
            try await render(
                VStack(spacing: 1) {
                    ForEach(voices) { voice in
                        VoiceRow(
                            voice: voice, requiredModelID: model.requiredModelID(for: voice.id), library: library,
                            isSelected: voice.id == "af_heart", isFavorite: false, isPreviewing: false, isPlaying: false,
                            canPreview: model.requiredModelID(for: voice.id) == nil,
                            select: {}, favorite: {}, preview: {}
                        )
                    }
                }
                .padding(.vertical, AttenSpacing.xxs)
                .background(AttenColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: AttenRadius.card))
                .padding(AttenSpacing.lg),
                dark: dark, size: CGSize(width: 900, height: 300),
                to: renderDir.appendingPathComponent("voices-\(suffix).png")
            )
        }

        model.selectVoice(voices[3])
        model.section = .studio
        model.createFlow.startWriting()
        model.createFlow.title = "Letters Home"
        model.createFlow.text = "The monsoon came early that year, and the letters stopped."
        for dark in [false, true] {
            try await render(
                CreateInspector(model: model, flow: model.createFlow),
                dark: dark, size: CGSize(width: 320, height: 640),
                to: renderDir.appendingPathComponent("create-\(dark ? "dark" : "light").png")
            )
        }

        // A book cast in a voice whose model is missing (#118): not yet
        // started, then mid-download.
        let book = try model.bookshelf.saveDraft(
            title: "Letters Home",
            text: "The monsoon came early that year, and the letters stopped.",
            voiceID: voices[3].id,
            defaults: model.settings
        )
        let bookModelID = try XCTUnwrap(model.requiredModelID(for: book.voiceID))
        for (name, state) in [("needs-download", nil), ("downloading", downloading)] {
            library.downloads[bookModelID] = state
            for dark in [false, true] {
                try await render(
                    BookDetailView(model: model, book: book) {}.environment(\.attenIsOffscreenRender, true),
                    dark: dark, size: CGSize(width: 960, height: 520),
                    to: renderDir.appendingPathComponent("book-\(name)-\(dark ? "dark" : "light").png")
                )
            }
        }
    }

    private struct StubDownloader: ModelDownloading {
        let run: @Sendable (String) async throws -> Void
        func download(_ modelID: String, progress: @escaping @Sendable (ModelDownloadProgress) -> Void) async throws {
            try await run(modelID)
        }
        func stop(_ modelID: String) {}
    }

    private enum RenderError: Error { case empty }

    private func render(_ view: some View, dark: Bool, size: CGSize, to url: URL) async throws {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        NSApplication.shared.appearance = appearance
        let host = NSHostingView(rootView:
            view
                .frame(width: size.width, height: size.height)
                .background(AttenColor.bg)
                .environment(\.colorScheme, dark ? .dark : .light)
        )
        host.appearance = appearance
        let window = NSWindow(
            contentRect: NSRect(origin: CGPoint(x: -20_000, y: -20_000), size: size),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.appearance = appearance
        window.contentView = host
        for _ in 0..<6 {
            host.layoutSubtreeIfNeeded()
            try? await Task.sleep(for: .milliseconds(250))
        }
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw RenderError.empty }
        appearance?.performAsCurrentDrawingAppearance {
            host.cacheDisplay(in: host.bounds, to: bitmap)
        }
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw RenderError.empty }
        try png.write(to: url)
        window.contentView = nil
    }
}
