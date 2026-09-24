import AppKit
import AttenCore
import SwiftUI

@main
struct AttenApp: App {
    @NSApplicationDelegateAdaptor(AttenAppDelegate.self) private var appDelegate
    @State private var model: AppModel = {
        if let path = ProcessInfo.processInfo.environment["ATTEN_DATA_DIRECTORY"] {
            let defaults = UserDefaults(suiteName: "Atten.Validation.\(URL(fileURLWithPath: path).lastPathComponent)")!
            return AppModel(
                directories: AppDirectories(applicationSupport: URL(fileURLWithPath: path)),
                settingsStore: SettingsStore(defaults: defaults)
            )
        }
        return AppModel()
    }()

    var body: some Scene {
        Window("Atten", id: "main") {
            RootView(model: model)
                .onAppear { appDelegate.model = model }
                .frame(minWidth: 960, minHeight: 700)
                .onOpenURL { url in
                    Task {
                        await model.start()
                        model.returnToShelf()
                        await model.bookshelf.importBook(from: url, defaults: model.settings)
                    }
                }
        }
        .defaultSize(width: 1180, height: 780)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New") {
                    model.newDraft()
                    NotificationCenter.default.post(name: .attenOpenStudio, object: nil)
                }
                    .keyboardShortcut("n")
            }
            CommandGroup(after: .importExport) {
                Button("Add to Library…") { model.openBookImportPanel() }
                    .keyboardShortcut("o")
                Button("Import into Create…") {
                    model.section = .studio
                    model.createFlow.openImportPanel()
                }.keyboardShortcut("o", modifiers: [.command, .shift])
                Button("Export Current Audio…") { model.exportCurrent() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    .disabled(model.currentAudioURL == nil && model.playingBook?.hasBookAudio != true)
            }
            CommandMenu("Speech") {
                Button("Generate") { model.createFlow.generate() }
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(model.section != .studio || !model.createFlow.canGenerate)
                Button("Stop Preparation") {
                    if model.bookshelf.isNarrating { model.bookshelf.cancelNarration() }
                    else { model.cancelGeneration() }
                }
                    .keyboardShortcut(.escape, modifiers: [])
                    .disabled(!model.synthesis.isBusy)
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
                Button("Back 15 Seconds") { model.skip(by: -NowPlayingCenter.skipInterval) }
                    .disabled(model.queue.isEmpty)
                Button("Forward 15 Seconds") { model.skip(by: NowPlayingCenter.skipInterval) }
                    .disabled(model.queue.isEmpty)
                Button("Previous") { model.playPrevious() }
                    .disabled(model.queue.isEmpty)
                Button("Next") { model.playNext() }
                    .disabled(!model.hasNextChapter)
            }
            CommandMenu("Navigate") {
                Button("Back") { model.goBack() }
                    .keyboardShortcut("[", modifiers: .command)
                    .disabled(!model.canGoBack)
                Divider()
                Button("Library") { model.returnToShelf() }
                .keyboardShortcut("1")
                Button("Voices") { model.section = .voices }
                .keyboardShortcut("2")
            }
            // Settings is a place in the window now, not a second window.
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { model.section = .settings }
                    .keyboardShortcut(",")
            }
        }
    }
}

@MainActor
final class AttenAppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model else { return .terminateNow }
        model.prepareForTermination()
        Task {
            do {
                try await model.bookshelf.stopAndSave()
                try model.finishPendingUpdate()
                sender.reply(toApplicationShouldTerminate: true)
            } catch {
                model.cancelPendingUpdate()
                let alert = NSAlert()
                alert.messageText = "Your library could not be saved"
                alert.informativeText = error.localizedDescription
                alert.addButton(withTitle: "Keep Atten Open")
                alert.addButton(withTitle: "Quit Without Saving")
                sender.reply(toApplicationShouldTerminate: alert.runModal() == .alertSecondButtonReturn)
            }
        }
        return .terminateLater
    }
}
