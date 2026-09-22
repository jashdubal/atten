import SwiftUI

/// How a screen tells the shell what to call it.
///
/// The shell owns one title row in the top chrome. Without this, Home,
/// Library, Reader and Studio would each need an edit to `RootView` to get a
/// title up there, which is exactly the file four teams cannot all be editing
/// at once.
///
/// A screen that says nothing gets nothing: the row collapses, and the screen
/// keeps drawing its own header until its owner migrates it. That is what lets
/// the screens move over one at a time rather than all in one commit.
///
/// ```swift
/// LibraryView(model: model)
///     .attenScreenTitle("Library", subtitle: "24 books")
/// ```
///
/// **Actions** do not need anything new: a screen puts its own buttons in the
/// window toolbar with SwiftUI's `.toolbar`, which already composes from any
/// depth without the shell knowing about it.
///
/// ```swift
/// .toolbar { ToolbarItem(placement: .primaryAction) { … } }
/// ```
struct AttenScreenTitle: Equatable, Sendable {
    var title: String
    var subtitle: String?
    /// Whether this title is the screen's hero rather than a label above it.
    ///
    /// Home's greeting is the largest thing on the screen; Library's name is
    /// a label. One flag rather than letting each screen post its own font,
    /// which is how a shared chrome stops being shared.
    var isProminent: Bool = false
}

private struct ScreenTitleKey: PreferenceKey {
    static let defaultValue: AttenScreenTitle? = nil

    static func reduce(value: inout AttenScreenTitle?, nextValue: () -> AttenScreenTitle?) {
        // The innermost screen wins. A reader pushed over the shelf names the
        // book; the shelf underneath it does not get a say.
        if let next = nextValue() { value = next }
    }
}

extension View {
    /// Name this screen in the shell's top chrome.
    func attenScreenTitle(
        _ title: String,
        subtitle: String? = nil,
        prominent: Bool = false
    ) -> some View {
        preference(
            key: ScreenTitleKey.self,
            value: AttenScreenTitle(title: title, subtitle: subtitle, isProminent: prominent)
        )
    }

    /// Read what the screen inside asked to be called. The shell calls this;
    /// screens do not.
    func onAttenScreenTitle(_ handler: @escaping (AttenScreenTitle?) -> Void) -> some View {
        onPreferenceChange(ScreenTitleKey.self, perform: handler)
    }
}
