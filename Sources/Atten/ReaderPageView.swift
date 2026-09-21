import AppKit
import AttenCore
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

    /// What was last put into the text view.
    ///
    /// A page turn animates, so SwiftUI evaluates the body of every page on
    /// the spread on every frame of it — and setting the whole of a page's
    /// text storage sixty times a second while it is also being transformed is
    /// what made a turn stutter. Nothing about a page's text changes during a
    /// turn, so this remembers enough to know that and do nothing.
    final class Coordinator {
        var applied: Applied?

        struct Applied: Equatable {
            /// The chapter's text is a reference type built once, so its
            /// identity settles this without comparing a chapter of prose.
            let text: ObjectIdentifier
            let pageIndex: Int
            let style: ReaderPageStyle
            let highlight: String
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

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
        let wanted = Coordinator.Applied(
            text: ObjectIdentifier(layout.text),
            pageIndex: pageIndex,
            style: style,
            highlight: highlight
        )
        guard context.coordinator.applied != wanted else { return }
        context.coordinator.applied = wanted

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
                value: NSColor(hex: style.palette.highlight),
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
        return lift * 0.18
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

/// The page, which has no edges.
///
/// This used to draw a sheet: a gradient, a lit top edge, a corner radius and
/// a shadow, lying in a darker well. That put a visible rectangle around the
/// text, and a reader who can see the edges of the page is looking at the app
/// rather than at the book. Apple Books draws no page at all — the window is
/// the page, and the margins are what make it one. So does this.
struct ReaderSheet: View {
    let palette: ReaderPagePalette

    var body: some View { Color(hex: palette.background) }
}

/// Catches a two-finger swipe, or a turn of a mouse wheel, over the page.
///
/// A book on a trackpad is turned by pushing the page sideways. Nothing in
/// SwiftUI reports a scroll over a view that is not a scroll view, and a view
/// placed on top to catch them would take the reader's ability to select a
/// sentence, so the events are read before they are dispatched — the same way
/// the back button on a mouse is.
///
/// What comes back is a request rather than a call, because the monitor is
/// installed once and would otherwise hold the first copy of the view it was
/// given — still believing, after a change of layout, that a turn moves one
/// page when it now moves two.
private struct SwipeToTurn: ViewModifier {
    @Binding var request: ReaderTurnRequest?

    @State private var monitor: Any?
    @State private var tracker = Tracker()

    /// Roughly one deliberate flick. Below this a swipe is someone resting
    /// their fingers on the trackpad.
    private static let threshold: CGFloat = 28
    /// A trackpad keeps sending deltas after the fingers lift, so a turn is
    /// followed by a moment in which another cannot happen.
    private static let quiet: TimeInterval = 0.45

    private final class Tracker {
        var isPointerOverPage = false
        var travelled: CGFloat = 0
        var lastTurn = Date.distantPast
    }

    func body(content: Content) -> some View {
        content
            .onHover { tracker.isPointerOverPage = $0 }
            .onAppear {
                guard monitor == nil else { return }
                let tracker = tracker
                monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                    // Only over the page, never out from under a sheet, and
                    // never a vertical scroll.
                    guard tracker.isPointerOverPage,
                          event.window?.attachedSheet == nil,
                          // The glide after the fingers lift is the same flick
                          // still arriving; counting it turns three pages.
                          event.momentumPhase == [],
                          abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) * 1.5
                    else { return event }

                    guard Date().timeIntervalSince(tracker.lastTurn) > Self.quiet else {
                        // Still settling from the last turn. Swallowed rather
                        // than banked, or the leftovers turn another page.
                        tracker.travelled = 0
                        return nil
                    }
                    if event.phase == .began { tracker.travelled = 0 }
                    tracker.travelled += event.scrollingDeltaX
                    guard abs(tracker.travelled) >= Self.threshold else { return event }

                    tracker.lastTurn = Date()
                    // Pushing the page to the left brings the next one in, the
                    // way a sheet of paper moves under a finger — which is the
                    // other way round when the system is not inverting the
                    // direction for us.
                    let pushedLeft = event.isDirectionInvertedFromDevice
                        ? tracker.travelled > 0
                        : tracker.travelled < 0
                    tracker.travelled = 0
                    request = ReaderTurnRequest(direction: pushedLeft ? .forward : .backward)
                    return nil
                }
            }
            .onDisappear {
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
            }
    }
}

extension View {
    func swipeToTurn(into request: Binding<ReaderTurnRequest?>) -> some View {
        modifier(SwipeToTurn(request: request))
    }
}
