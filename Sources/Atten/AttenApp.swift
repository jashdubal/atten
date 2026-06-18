import AttenCore
import SwiftUI

@main
struct AttenApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("Atten") {
            RootView(model: model)
                .frame(minWidth: 980, minHeight: 650)
        }
        .defaultSize(width: 1180, height: 760)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Studio Draft") { model.newDraft() }
                    .keyboardShortcut("n")
            }
            CommandGroup(after: .importExport) {
                Button("Import Text…") { model.openImportPanel() }
                    .keyboardShortcut("o")
                Button("Export Current Audio…") { model.exportCurrent() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    .disabled(model.currentAudioURL == nil)
            }
            CommandMenu("Speech") {
                Button("Generate Speech") { model.generate() }
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(model.isGenerating)
                Button("Cancel Generation") { model.cancelGeneration() }
                    .keyboardShortcut(.escape, modifiers: [])
                    .disabled(!model.isGenerating)
                Divider()
                Button(model.isPlaying ? "Pause" : "Play") { model.togglePlayback() }
                    .keyboardShortcut(.space, modifiers: [.option])
                    .disabled(model.currentAudioURL == nil)
            }
        }

        Settings {
            SettingsView(model: model)
                .frame(width: 620, height: 560)
        }
    }
}
