import SwiftUI

/// Legacy destinations become tools within the creation workspace.
struct CreateWorkspace: View {
    @Bindable var model: AppModel
    @State private var showsPreview = false
    @State private var showsVoices = false

    private var selection: Binding<SidebarItem> {
        Binding(get: {
            [.projects, .exports].contains(model.section) ? model.section : .studio
        }, set: { model.section = $0 })
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Create", selection: selection) {
                    Text("Draft").tag(SidebarItem.studio)
                    Text("Projects").tag(SidebarItem.projects)
                    Text("Exports").tag(SidebarItem.exports)
                }
                .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 290)
                Spacer()
                Button("Voices") { showsVoices = true }
                Button("Try a Sample") { showsPreview = true }
            }
            .padding(.horizontal, 24).padding(.vertical, 12)
            Divider()
            switch model.section {
            case .projects: ProjectsView(model: model) { model.section = .studio }
            case .exports: ExportsView(model: model)
            default: StudioView(model: model)
            }
        }
        .onAppear {
            showsPreview = model.section == .playground
            showsVoices = model.section == .voices
        }
        .sheet(isPresented: $showsPreview) {
            toolSheet {
                PlaygroundView(model: model) { showsPreview = false; model.section = .studio }
            }
        }
        .sheet(isPresented: $showsVoices) {
            toolSheet {
                VoicesView(model: model) { showsVoices = false; model.section = .studio }
            }
        }
    }

    private func toolSheet<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Done") { showsPreview = false; showsVoices = false; model.section = .studio }
                    .keyboardShortcut(.cancelAction)
            }.padding(16)
            content()
        }.frame(width: 820, height: 620)
    }
}
