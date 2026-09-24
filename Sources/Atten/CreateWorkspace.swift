import SwiftUI

/// Create, full-window, over whichever place it was opened from.
struct CreateWorkspace: View {
    @Bindable var model: AppModel
    let backTitle: String
    let leave: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                AttenBackButton(title: backTitle, action: leave)
                Spacer()
            }
            .padding(.horizontal, 24).padding(.vertical, 12)
            Divider()
            StudioView(model: model)
        }
    }
}
