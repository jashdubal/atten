import AppKit
import AttenCore
import Foundation
import SwiftUI
import XCTest
@testable import Atten

/// Offscreen renders of Voices and every Settings tab (#108), in both
/// appearances. These screens are mostly AppKit-backed controls — `Form`,
/// `Toggle`, `Slider`, `TextField` — which `ImageRenderer` draws as
/// placeholders, so each is hosted in an `NSHostingView` inside a borderless
/// window that is never ordered onto a screen, and drawn with
/// `cacheDisplay`. Gated behind `ATTEN_RENDER_DIR` so it never runs on CI.
@MainActor
final class VoicesSettingsRenderTests: XCTestCase {
    func testVoicesAndSettingsRenderInBothAppearances() async throws {
        guard let renderDirPath = ProcessInfo.processInfo.environment["ATTEN_RENDER_DIR"] else {
            throw XCTSkip("Set ATTEN_RENDER_DIR to render Voices and Settings")
        }
        let renderDir = URL(fileURLWithPath: renderDirPath, isDirectory: true)
        try FileManager.default.createDirectory(at: renderDir, withIntermediateDirectories: true)

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttenVoicesSettingsRender-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "AttenVoicesSettingsRender.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(
            directories: AppDirectories(applicationSupport: directory),
            settingsStore: SettingsStore(defaults: defaults),
            generator: ImmediateGenerator()
        )
        model.settings.outputDirectory = "~/Music/Atten"
        model.settings.favoriteVoiceIDs = ["bf_emma"]
        // One switch off and one on, to judge both states' contrast.
        model.settings.useMPS = false
        model.settings.checksForUpdates = true
        model.selectVoice(try XCTUnwrap(VoiceCatalog.voice(id: "af_heart")))

        let size = CGSize(width: 1000, height: 760)
        for dark in [false, true] {
            let suffix = dark ? "dark" : "light"
            try await render(VoicesView(model: model) {}, dark: dark, size: size, to: renderDir.appendingPathComponent("voices-\(suffix).png"))
            for tab in ["general", "audio", "storage", "appearance", "models", "shortcuts"] {
                model.settingsTab = tab
                try await render(SettingsView(model: model), dark: dark, size: size, to: renderDir.appendingPathComponent("settings-\(tab)-\(suffix).png"))
            }
        }
    }

    private enum RenderError: Error { case empty }

    private func render(_ view: some View, dark: Bool, size: CGSize, to url: URL) async throws {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        NSApplication.shared.appearance = appearance
        // The detail column sits on the window's own background in the app.
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
        // Dynamic colours resolve against the current drawing appearance.
        appearance?.performAsCurrentDrawingAppearance {
            host.cacheDisplay(in: host.bounds, to: bitmap)
        }
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw RenderError.empty }
        try png.write(to: url)
        window.contentView = nil
    }
}
