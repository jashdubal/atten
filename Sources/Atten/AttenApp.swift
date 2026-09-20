import AttenCore
import SwiftUI

@main
struct AttenApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("Atten") {
            RootView(model: model)
                .frame(minWidth: 960, minHeight: 700)
        }
        .defaultSize(width: 1180, height: 780)
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
                    // Whatever is in the player, not only a Studio draft: a
                    // book being listened to is the commonest case by far.
                    .disabled(model.queue.isEmpty && model.currentAudioURL == nil)
                // No key equivalents here on purpose. A main-menu shortcut wins
                // over the responder chain, and every arrow combination worth
                // having is already spoken for: ⌥← and ⌥→ move a text cursor
                // by words, and ⌥⌘← and ⌥⌘→ are the reader's own chapter keys.
                // The media keys on the keyboard reach all four through
                // NowPlayingCenter, which is where macOS expects to find them.
                Button("Back 10 Seconds") { model.skip(by: -NowPlayingCenter.skipInterval) }
                    .disabled(model.queue.isEmpty)
                Button("Forward 10 Seconds") { model.skip(by: NowPlayingCenter.skipInterval) }
                    .disabled(model.queue.isEmpty)
                Button("Previous") { model.playPrevious() }
                    .disabled(model.queue.isEmpty)
                Button("Next") { model.playNext() }
                    .disabled(!model.queue.hasNext)
            }
            CommandMenu("Navigate") {
                Button("Back") { model.goBack() }
                    .keyboardShortcut("[", modifiers: .command)
                    .disabled(!model.canGoBack)
                Divider()
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
