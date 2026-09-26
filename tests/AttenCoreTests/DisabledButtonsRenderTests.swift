import AppKit
import AttenCore
import Foundation
import SwiftUI
import XCTest
@testable import Atten

/// Offscreen renders of a disabled primary, secondary and tertiary button
/// together (#121), in both appearances. Gated behind `ATTEN_RENDER_DIR`,
/// like `VoicesSettingsRenderTests`, whose hosting-window harness this
/// shares.
@MainActor
final class DisabledButtonsRenderTests: XCTestCase {
    func testDisabledButtonsRenderInBothAppearances() async throws {
        guard let renderDirPath = ProcessInfo.processInfo.environment["ATTEN_RENDER_DIR"] else {
            throw XCTSkip("Set ATTEN_RENDER_DIR to render the disabled buttons")
        }
        let renderDir = URL(fileURLWithPath: renderDirPath, isDirectory: true)
        try FileManager.default.createDirectory(at: renderDir, withIntermediateDirectories: true)

        let view = VStack(alignment: .leading, spacing: AttenSpacing.lg) {
            Button("Generate") {}
                .buttonStyle(AttenPrimaryButtonStyle(disabledReason: "Add some text first"))
                .disabled(true)
            Button("Cast to book") {}
                .buttonStyle(AttenSecondaryButtonStyle())
                .disabled(true)
            Button("Delete") {}
                .buttonStyle(AttenTertiaryButtonStyle())
                .disabled(true)
        }
        .padding(AttenSpacing.lg)

        for dark in [false, true] {
            try await render(
                view, dark: dark, size: CGSize(width: 320, height: 220),
                to: renderDir.appendingPathComponent("disabled-buttons-\(dark ? "dark" : "light").png")
            )
        }
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
