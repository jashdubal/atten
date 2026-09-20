import AppKit
import AttenCore
import SwiftUI

/// A native editor with one explicit text inset so the insertion point,
/// entered text, and SwiftUI placeholder share the same origin.
struct AlignedTextEditor: NSViewRepresentable {
    @Binding var text: String
    let accessibilityLabel: String
    /// Read here, in the owning view's body, so SwiftUI notices a theme change
    /// and updates this editor with it. AppKit keeps whatever colour it was
    /// handed, so the new one has to be pushed in.
    var theme: AttenTheme = ThemeStore.shared.theme

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.focusRingType = .exterior

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.string = text
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = true
        textView.isAutomaticDashSubstitutionEnabled = true
        textView.font = NSFont.preferredFont(forTextStyle: .body)
        applyTheme(to: textView)
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 13, height: 12)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.setAccessibilityLabel(accessibilityLabel)
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.text = $text
        guard let textView = scrollView.documentView as? NSTextView else { return }
        // Recolouring re-attributes the whole document, so only do it when the
        // theme actually changed rather than on every keystroke.
        if context.coordinator.appliedTheme != theme {
            context.coordinator.appliedTheme = theme
            applyTheme(to: textView)
        }
        guard textView.string != text else { return }
        let selection = textView.selectedRanges
        textView.string = text
        let validSelection = selection.filter {
            NSMaxRange($0.rangeValue) <= (text as NSString).length
        }
        textView.selectedRanges = validSelection.isEmpty
            ? [NSValue(range: NSRange(location: (text as NSString).length, length: 0))]
            : validSelection
    }

    private func applyTheme(to textView: NSTextView) {
        textView.textColor = AttenColor.nsTextPrimary
        textView.insertionPointColor = AttenColor.nsAccent
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var appliedTheme = ThemeStore.shared.theme

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}
