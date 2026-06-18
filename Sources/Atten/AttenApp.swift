import AttenCore
import SwiftUI

@main
struct AttenApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("Atten") {
            RootView(model: model)
                .frame(minWidth: 820, minHeight: 600)
        }
        .defaultSize(width: 1080, height: 700)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Studio Draft") {
                    model.newDraft()
                    NotificationCenter.default.post(name: .attenOpenStudio, object: nil)
                }
                    .keyboardShortcut("n")
            }
            CommandGroup(after: .importExport) {
                Button("Import Text…") {
                    model.openImportPanel()
                    NotificationCenter.default.post(name: .attenOpenStudio, object: nil)
                }
                    .keyboardShortcut("o")
                Button("Export Current Audio…") { model.exportCurrent() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    .disabled(model.currentAudioURL == nil)
            }
            CommandMenu("Speech") {
                Button("Generate Speech") { model.generate() }
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(model.isGenerating || model.isPlaygroundGenerating)
                Button("Cancel Generation") { model.cancelGeneration() }
                    .keyboardShortcut(.escape, modifiers: [])
                    .disabled(!model.isGenerating && !model.isPlaygroundGenerating)
                Divider()
                Button(model.isPlaying ? "Pause" : "Play") { model.toggleActivePlayback() }
                    .keyboardShortcut(.space, modifiers: [.option])
                    .disabled(model.currentAudioURL == nil)
            }
            CommandMenu("Navigate") {
                Button("Studio") {
                    NotificationCenter.default.post(name: .attenOpenStudio, object: nil)
                }
                .keyboardShortcut("1")
                Button("Playground") {
                    NotificationCenter.default.post(name: .attenOpenPlayground, object: nil)
                }
                .keyboardShortcut("2")
            }
        }

        Settings {
            SettingsView(model: model)
                .frame(width: 680, height: 520)
        }
    }
}
