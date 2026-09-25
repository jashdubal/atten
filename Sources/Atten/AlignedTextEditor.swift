import AppKit
import AttenCore
import SwiftUI

/// A native editor set in the reading face, its text held to a centred
/// column of about 68 characters however wide the window is.
///
/// While narration runs it stops being an editor in place: the text waits in
/// `text3`, and each stretch the engine finishes turns `text1` with a brief
/// `signal` underline drawn across it.
struct AlignedTextEditor: NSViewRepresentable {
    @Binding var text: String
    let accessibilityLabel: String
    /// How much of `text` (in UTF-16) has been spoken, while narration runs.
    /// Nil while the text is being written.
    var spokenLength: Int?
    /// The sentence sounding right now, while progressive playback follows
    /// this draft. Nil when nothing is playing along with it.
    var playingRange: NSRange?
    var focusesOnAppear = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.focusRingType = .none

        let style = AttenTextStyle.reading
        let textView = ColumnTextView()
        textView.columnWidth = ("0" as NSString).size(withAttributes: [.font: style.nsFont]).width * 68
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = true
        textView.isAutomaticDashSubstitutionEnabled = true
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = style.lineHeight
        paragraph.maximumLineHeight = style.lineHeight
        textView.defaultParagraphStyle = paragraph
        textView.font = style.nsFont
        textView.typingAttributes = Self.attributes(colour: AttenColor.nsTextPrimary)
        textView.insertionPointColor = AttenColor.nsSignal
        textView.string = text
        textView.textStorage?.setAttributes(
            Self.attributes(colour: AttenColor.nsTextPrimary),
            range: NSRange(location: 0, length: (text as NSString).length)
        )
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.setAccessibilityLabel(accessibilityLabel)
        scrollView.documentView = textView
        if focusesOnAppear {
            Task { @MainActor in textView.window?.makeFirstResponder(textView) }
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.text = $text
        guard let textView = scrollView.documentView as? NSTextView else { return }
        textView.isEditable = spokenLength == nil
        if textView.string != text {
            let selection = textView.selectedRanges
            textView.string = text
            let validSelection = selection.filter {
                NSMaxRange($0.rangeValue) <= (text as NSString).length
            }
            textView.selectedRanges = validSelection.isEmpty
                ? [NSValue(range: NSRange(location: (text as NSString).length, length: 0))]
                : validSelection
            coordinator.spokenLength = nil
            coordinator.hasColouredSpoken = false
            markPlaying(nil, in: textView, coordinator: coordinator)
        }
        if spokenLength != coordinator.spokenLength || (spokenLength == nil && coordinator.hasColouredSpoken) {
            colour(textView, spoken: spokenLength, previously: coordinator.spokenLength)
            coordinator.spokenLength = spokenLength
            coordinator.hasColouredSpoken = spokenLength != nil
        }
        if playingRange != coordinator.playingRange {
            markPlaying(playingRange, in: textView, coordinator: coordinator)
            coordinator.playingRange = playingRange
        }
    }

    private static func attributes(colour: NSColor) -> [NSAttributedString.Key: Any] {
        let style = AttenTextStyle.reading
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = style.lineHeight
        paragraph.maximumLineHeight = style.lineHeight
        return [.font: style.nsFont, .paragraphStyle: paragraph, .foregroundColor: colour]
    }

    private func colour(_ textView: NSTextView, spoken: Int?, previously: Int?) {
        guard let storage = textView.textStorage else { return }
        let whole = NSRange(location: 0, length: storage.length)
        guard let spoken else {
            storage.addAttribute(.foregroundColor, value: AttenColor.nsTextPrimary, range: whole)
            return
        }
        let end = min(spoken, storage.length)
        storage.addAttribute(.foregroundColor, value: AttenColor.nsText3, range: whole)
        storage.addAttribute(.foregroundColor, value: AttenColor.nsTextPrimary, range: NSRange(location: 0, length: end))
        // The paragraph break before a stretch is not part of what was said.
        let said = (storage.string as NSString)
        var start = previously ?? end
        while start < end, let scalar = UnicodeScalar(said.character(at: start)),
              CharacterSet.whitespacesAndNewlines.contains(scalar) {
            start += 1
        }
        if previously != nil, end > start {
            sweep(NSRange(location: start, length: end - start), in: textView)
        }
    }

    /// One rect per line a range covers, tight to the words on it: a line's
    /// own rect runs on to the margin past a trailing space.
    private func lineRects(for range: NSRange, layoutManager: NSLayoutManager, container: NSTextContainer) -> [NSRect] {
        let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        var rects: [NSRect] = []
        layoutManager.enumerateLineFragments(forGlyphRange: glyphs) { line, _, _, lineGlyphs, _ in
            let words = NSIntersectionRange(lineGlyphs, glyphs)
            guard words.length > 0 else { return }
            let bounds = layoutManager.boundingRect(forGlyphRange: words, in: container)
            rects.append(NSRect(x: bounds.minX, y: line.minY, width: bounds.width, height: line.height))
        }
        return rects
    }

    /// Draws a hairline of `signal` under the stretch just spoken, left to
    /// right across each of its lines in reading order, then lets it fade.
    private func sweep(_ range: NSRange, in textView: NSTextView) {
        guard let layoutManager = textView.layoutManager,
              let container = textView.textContainer else { return }
        textView.wantsLayer = true
        guard let host = textView.layer else { return }
        let rects = lineRects(for: range, layoutManager: layoutManager, container: container)
        let total = rects.reduce(0) { $0 + $1.width }
        guard total > 0 else { return }

        var colour = AttenColor.nsSignal.cgColor
        textView.effectiveAppearance.performAsCurrentDrawingAppearance {
            colour = AttenColor.nsSignal.cgColor
        }
        let origin = textView.textContainerOrigin
        let sweepDuration = reduceMotion ? 0 : 0.5
        let hold = reduceMotion ? AttenMotion.reducedFade : 0.3
        let now = CACurrentMediaTime()
        var start = 0.0
        var lines: [CALayer] = []
        CATransaction.begin()
        CATransaction.setCompletionBlock {
            for line in lines { line.removeFromSuperlayer() }
        }
        for rect in rects {
            let line = CALayer()
            line.backgroundColor = colour
            line.anchorPoint = CGPoint(x: 0, y: 0.5)
            line.bounds = CGRect(x: 0, y: 0, width: rect.width, height: 1.5)
            // Just under the descenders, clear of the next line.
            line.position = CGPoint(x: rect.minX + origin.x, y: rect.maxY + origin.y - 1)
            line.opacity = 0
            host.addSublayer(line)

            let share = sweepDuration * rect.width / total
            let grow = CABasicAnimation(keyPath: "transform.scale.x")
            grow.fromValue = reduceMotion ? 1 : 0
            grow.toValue = 1
            grow.beginTime = now + start
            grow.duration = max(share, 0.01)
            grow.fillMode = .backwards
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [1, 1, 0]
            fade.keyTimes = [0, 0.7, 1]
            fade.beginTime = now + start
            fade.duration = sweepDuration - start + hold + 0.4
            line.add(grow, forKey: "grow")
            line.add(fade, forKey: "fade")
            start += share
            lines.append(line)
        }
        CATransaction.commit()
    }

    /// Marks the sentence sounding right now with a `signal` underline that
    /// holds steady, unlike `sweep`'s one-off flourish, until the next
    /// sentence takes its place or playback stops.
    private func markPlaying(_ range: NSRange?, in textView: NSTextView, coordinator: Coordinator) {
        for layer in coordinator.playingLayers { layer.removeFromSuperlayer() }
        coordinator.playingLayers = []
        guard let range, let layoutManager = textView.layoutManager, let container = textView.textContainer,
              NSMaxRange(range) <= (textView.string as NSString).length else { return }
        textView.wantsLayer = true
        guard let host = textView.layer else { return }
        var colour = AttenColor.nsSignal.cgColor
        textView.effectiveAppearance.performAsCurrentDrawingAppearance {
            colour = AttenColor.nsSignal.cgColor
        }
        let origin = textView.textContainerOrigin
        let fade = reduceMotion ? AttenMotion.reducedFade : AttenMotion.fast
        for rect in lineRects(for: range, layoutManager: layoutManager, container: container) {
            let line = CALayer()
            line.backgroundColor = colour
            line.bounds = CGRect(x: 0, y: 0, width: rect.width, height: 1.5)
            line.position = CGPoint(x: rect.minX + origin.x, y: rect.maxY + origin.y - 1)
            line.opacity = 0
            host.addSublayer(line)
            let show = CABasicAnimation(keyPath: "opacity")
            show.fromValue = 0
            show.toValue = 1
            show.duration = fade
            line.add(show, forKey: "show")
            line.opacity = 1
            coordinator.playingLayers.append(line)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var spokenLength: Int?
        var hasColouredSpoken = false
        var playingRange: NSRange?
        var playingLayers: [CALayer] = []

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}

/// Keeps its text in a column of `columnWidth`, centred by growing the
/// inset on both sides as the view widens.
private final class ColumnTextView: NSTextView {
    var columnWidth: CGFloat = 600

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        let side = max(AttenSpacing.lg, (newSize.width - columnWidth) / 2)
        if textContainerInset.width != side {
            textContainerInset = NSSize(width: side, height: AttenSpacing.lg)
        }
    }
}
