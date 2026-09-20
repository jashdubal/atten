import AppKit
import SwiftUI

// MARK: - One page

/// One typeset page, drawn by the same machinery that decided where it ends.
///
/// A SwiftUI `Text` would break the lines again with its own rules, and a page
/// that fills to the pixel in one is a page with a widow in the other. This
/// draws the range TextKit gave us, at the size TextKit measured.
struct ReaderPage: NSViewRepresentable {
    let layout: ReaderChapterLayout
    let pageIndex: Int
    let style: ReaderPageStyle
    /// Lit up behind every match while a search is running.
    let highlight: String

    func makeNSView(context: Context) -> NSTextView {
        let view = NSTextView()
        view.isEditable = false
        view.isSelectable = true
        view.drawsBackground = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.isVerticallyResizable = false
        view.isHorizontallyResizable = false
        view.linkTextAttributes = [:]
        return view
    }

    func updateNSView(_ view: NSTextView, context: Context) {
        view.textContainer?.size = style.pageSize
        view.frame = CGRect(origin: .zero, size: style.pageSize)
        let range = layout.range(ofPage: pageIndex)
        guard range.length > 0, NSMaxRange(range) <= layout.text.length else {
            view.textStorage?.setAttributedString(NSAttributedString())
            return
        }
        let page = NSMutableAttributedString(
            attributedString: layout.text.attributedSubstring(from: range)
        )
        applyHighlight(to: page)
        view.textStorage?.setAttributedString(page)
    }

    private func applyHighlight(to page: NSMutableAttributedString) {
        let needle = highlight.trimmingCharacters(in: .whitespacesAndNewlines)
        guard needle.count >= 2 else { return }
        let text = page.string as NSString
        var searched = NSRange(location: 0, length: text.length)
        while searched.length > 0 {
            let found = text.range(
                of: needle,
                options: [.caseInsensitive, .diacriticInsensitive],
                range: searched
            )
            guard found.location != NSNotFound, found.length > 0 else { return }
            page.addAttribute(
                .backgroundColor,
                value: AttenColor.palette.readerHighlight.nsColor,
                range: found
            )
            let next = NSMaxRange(found)
            searched = NSRange(location: next, length: max(0, text.length - next))
        }
    }
}

// MARK: - Turning it

enum ReaderTurn: Equatable {
    case forward
    case backward
}

/// A leaf of the book, mid-turn.
///
/// A page in a book pivots on the spine, and both of its sides are pages: the
/// side facing you before the turn and the side facing you after it. That is
/// the whole trick — a leaf is rotated about its inner edge, its front is what
/// you were reading, its back is what you are about to read, and the pages that
/// follow sit underneath waiting to be uncovered. Rotating past ninety degrees
/// hides the front and shows the back, which has to be flipped in x or it would
/// read backwards, as the back of a real page would if paper were transparent.
struct TurningLeaf<Front: View, Back: View>: View {
    /// 0 is flat and unturned, 1 is flat against the other side.
    let progress: Double
    let turn: ReaderTurn
    @ViewBuilder let front: Front
    @ViewBuilder let back: Back

    private var angle: Double {
        (turn == .forward ? -180 : 180) * progress
    }

    private var isShowingBack: Bool { progress > 0.5 }

    /// Paper catches the light as it lifts and loses it as it falls, and the
    /// page underneath darkens in the leaf's shadow. Without this the page
    /// turns like a card being dealt rather than like paper.
    private var shade: Double {
        let lift = 1 - abs(progress - 0.5) * 2
        return lift * 0.30
    }

    var body: some View {
        ZStack {
            front.opacity(isShowingBack ? 0 : 1)
            back
                .scaleEffect(x: -1, y: 1)
                .opacity(isShowingBack ? 1 : 0)
        }
        .overlay {
            LinearGradient(
                colors: [.black.opacity(shade * 0.5), .black.opacity(shade)],
                startPoint: turn == .forward ? .trailing : .leading,
                endPoint: turn == .forward ? .leading : .trailing
            )
            .allowsHitTesting(false)
        }
        .rotation3DEffect(
            .degrees(angle),
            axis: (x: 0, y: 1, z: 0),
            anchor: turn == .forward ? .leading : .trailing,
            // Shallow on purpose. A strong perspective makes the page look as
            // though it is being thrown at the reader.
            perspective: 0.36
        )
        // A leaf standing up casts across the gutter, and the shadow is what
        // separates it from the page it is uncovering.
        .shadow(
            color: .black.opacity(shade * 0.9),
            radius: 18 * (1 - abs(progress - 0.5) * 2),
            x: turn == .forward ? -10 : 10
        )
    }
}

/// The paper a page is printed on.
struct ReaderPaper: View {
    var body: some View {
        AttenColor.readerSurface
    }
}
