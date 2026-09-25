import AttenCore
import SwiftUI

/// The player, full window: the playing cover as light, the words being
/// spoken in the reading face, and the transport at the foot.
///
/// A view over `AppModel`, not another player. Everything it plays, seeks
/// and skips goes through the same `AVAudioPlayer` the mini player and the
/// system's media keys address.
struct ReadAlongView: View {
    @Bindable var model: AppModel
    /// Shared with the mini player, which grows into this.
    let namespace: Namespace.ID

    @State private var script = ReadAlongScript.empty
    /// Chapter names over the sentence each chapter starts on, for a book
    /// played as one recording.
    @State private var headings: [Int: String] = [:]
    @State private var playhead = ReadAlongPlayhead()
    @State private var scroll = ReadAlongScroll()

    var body: some View {
        ZStack {
            AttenColor.bg
                .overlay { AmbientFieldLayer(pausedStrength: 0.5) }
                .ignoresSafeArea()
            if model.queue.current == nil {
                VStack(spacing: AttenSpacing.md) {
                    AttenEmptyState(title: "Nothing playing", systemImage: "waveform", detail: "")
                    Button("Library") { model.returnToShelf() }
                        .buttonStyle(AttenTertiaryButtonStyle())
                }
            } else {
                player
            }
        }
        .task(id: model.queue.current?.id) { await loadScript() }
    }

    private var player: some View {
        ZStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        ReadAlongHero(model: model, namespace: namespace, scroll: scroll)
                        sentences
                    }
                    .frame(maxWidth: 680)
                    .padding(.horizontal, AttenSpacing.xl)
                    // Room for the transport, which is taller than the
                    // mini player the standard clearance is sized for.
                    .padding(.bottom, AttenSpacing.xxl)
                    .attenScrollPadding()
                    .frame(maxWidth: .infinity)
                }
                .coordinateSpace(name: ReadAlongScroll.space)
                .onPreferenceChange(ReadAlongScroll.OffsetKey.self) { offset in
                    MainActor.assumeIsolated { scroll.scrolled(to: offset) }
                }
                .background {
                    ReadAlongFollower(proxy: proxy, playhead: playhead, scroll: scroll)
                }
            }
            VStack {
                ReadAlongHeader(model: model, scroll: scroll)
                Spacer()
                ReadAlongTransport(model: model, namespace: namespace, script: script, playhead: playhead)
            }
            .padding(.horizontal, AttenSpacing.lg)
            .padding(.vertical, AttenSpacing.sm)
        }
        .background {
            ReadAlongClock(model: model, script: script, playhead: playhead)
            ReadAlongKeys(model: model, script: script, playhead: playhead)
        }
    }

    private var sentences: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(script.sentences) { sentence in
                SentenceRow(
                    sentence: sentence,
                    heading: headings[sentence.id],
                    startsParagraph: sentence.id > 0
                        && script.sentences[sentence.id - 1].paragraph != sentence.paragraph,
                    showsWords: script.hasWordTimings,
                    playhead: playhead,
                    scroll: scroll
                ) {
                    model.seek(to: sentence.start)
                    scroll.follow()
                }
                .id(sentence.id)
            }
        }
    }

    /// Word timings sit beside a book's recording. A recording without them —
    /// and a Create project, which never has them — is followed by the
    /// sentence, with times estimated from each sentence's length.
    private func loadScript() async {
        playhead.set(nil)
        guard let track = model.queue.current else {
            script = .empty
            return
        }
        let book = model.playingBook
        let project = model.playingProject
        let duration = model.playbackDuration
        let loaded = await Task.detached(priority: .userInitiated) { () -> ReadAlongScript in
            if book != nil, let timings = try? NarrationTimings.load(beside: track.url) {
                return ReadAlongScript(timings: timings)
            }
            if let book, book.hasBookAudio, book.audioURL == track.url {
                let chapters = book.playbackChapters
                return ReadAlongScript(estimating: chapters.map {
                    ($0.text, $0.startTime ?? 0, $0.endTime ?? duration)
                })
            }
            if let chapter = book?.chapters.first(where: { $0.id == track.id }) {
                return ReadAlongScript(estimating: [(chapter.text, 0, duration)])
            }
            if let project { return ReadAlongScript(estimating: [(project.text, 0, duration)]) }
            return .empty
        }.value
        guard !Task.isCancelled else { return }
        script = loaded
        headings = Self.headings(for: book, trackURL: track.url, in: loaded)
        playhead.set(loaded.locate(time: model.levelMeter.currentTime))
        scroll.follow()
    }

    private static func headings(for book: BookRecord?, trackURL: URL, in script: ReadAlongScript) -> [Int: String] {
        guard let book, book.hasBookAudio, book.audioURL == trackURL,
              book.playbackChapters.count > 1 else { return [:] }
        var headings: [Int: String] = [:]
        for chapter in book.playbackChapters {
            let start = chapter.startTime ?? 0
            if let first = script.sentences.first(where: { $0.start >= start - 0.05 }), headings[first.id] == nil {
                headings[first.id] = chapter.title
            }
        }
        return headings
    }
}

// MARK: - Playhead

/// Where the voice is, published only when it moves to another word — a few
/// times a second — never once per frame.
///
/// The sentence and the word are held apart so that a new word re-draws the
/// one sentence it is in, and only a new sentence re-draws the rest.
@MainActor
@Observable
final class ReadAlongPlayhead {
    private(set) var sentence: Int?
    private(set) var word: Range<Int>?

    func set(_ place: ReadAlongPlace?) {
        if sentence != place?.sentence { sentence = place?.sentence }
        if word != place?.word { word = place?.word }
    }
}

/// Reads the player's clock every frame while it plays and moves the
/// playhead when the word under it changes. The binary search runs every
/// frame; the model hears about a word, not a frame.
private struct ReadAlongClock: View {
    let model: AppModel
    let script: ReadAlongScript
    let playhead: ReadAlongPlayhead

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: !model.isPlaying)) { context in
            let place = locate(context.date)
            Color.clear.onChange(of: place, initial: true) { _, place in playhead.set(place) }
        }
        // A seek while paused moves the playhead with no frame to notice it.
        .onChange(of: model.playbackPosition) { _, _ in playhead.set(locate(.now)) }
        .accessibilityHidden(true)
    }

    private func locate(_: Date) -> ReadAlongPlace? {
        script.locate(time: model.levelMeter.currentTime)
    }
}

// MARK: - Scrolling

/// How far the page has scrolled, and whether the page is following the
/// voice. Scrolling by hand stops the following for a few seconds, the way
/// lyrics do, so a reader can look back without being pulled away.
@MainActor
@Observable
final class ReadAlongScroll {
    static let space = "readalong"
    static let collapseDistance: CGFloat = 260
    static let resumeAfter: Duration = .seconds(4)

    /// How far the top of the page has moved up, in points.
    private(set) var offset: CGFloat = 0
    private(set) var isFollowing = true
    /// Bumped to ask the follower to bring the current sentence back.
    private(set) var recall = 0

    @ObservationIgnored private var programmaticUntil = Date.distantPast
    @ObservationIgnored private var resume: Task<Void, Never>?

    /// 0 with the cover at full size, 1 once it has become the header.
    var collapse: Double { min(1, max(0, Double(offset / Self.collapseDistance))) }

    func scrolled(to minY: CGFloat) {
        let moved = -minY
        guard abs(moved - offset) >= 0.5 else { return }
        offset = moved
        guard Date() > programmaticUntil else { return }
        isFollowing = false
        resume?.cancel()
        resume = Task { [weak self] in
            try? await Task.sleep(for: Self.resumeAfter)
            guard !Task.isCancelled else { return }
            self?.follow()
        }
    }

    /// Follow the voice again, now.
    func follow() {
        resume?.cancel()
        isFollowing = true
        recall += 1
    }

    /// The follower is about to scroll; what moves in the next moment is not
    /// the reader's hand.
    func willScroll() {
        programmaticUntil = Date().addingTimeInterval(0.9)
    }

    struct OffsetKey: PreferenceKey {
        static let defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
    }
}

/// Keeps the sentence being spoken a little above the middle of the window.
private struct ReadAlongFollower: View {
    let proxy: ScrollViewProxy
    let playhead: ReadAlongPlayhead
    let scroll: ReadAlongScroll
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Color.clear
            .onChange(of: playhead.sentence) { _, _ in bringCurrentIntoView() }
            .onChange(of: scroll.recall) { _, _ in bringCurrentIntoView() }
    }

    private func bringCurrentIntoView() {
        guard scroll.isFollowing, let sentence = playhead.sentence else { return }
        scroll.willScroll()
        withAnimation(AttenMotion.animation(.large, reduceMotion: reduceMotion)) {
            proxy.scrollTo(sentence, anchor: UnitPoint(x: 0.5, y: 0.4))
        }
    }
}

// MARK: - Text

private struct SentenceRow: View {
    let sentence: ReadAlongSentence
    let heading: String?
    let startsParagraph: Bool
    let showsWords: Bool
    let playhead: ReadAlongPlayhead
    let scroll: ReadAlongScroll
    let seek: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let distance = playhead.sentence.map { abs($0 - sentence.id) } ?? 0
        VStack(alignment: .leading, spacing: AttenSpacing.sm) {
            if let heading {
                Text(heading)
                    .attenText(.label)
                    .foregroundStyle(AttenColor.text3)
                    .padding(.top, AttenSpacing.xl)
                    .accessibilityAddTraits(.isHeader)
            }
            Button(action: seek) {
                text(isCurrent: distance == 0)
                    .attenText(.reading)
                    .foregroundStyle(AttenColor.text1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .opacity(Self.opacity(distance))
                    .blur(radius: reduceMotion || !scroll.isFollowing ? 0 : Self.blur(distance))
                    .animation(.easeInOut(duration: AttenMotion.state), value: distance)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Plays from this sentence")
        }
        .padding(.top, startsParagraph ? AttenSpacing.lg : AttenSpacing.xs)
    }

    /// The word being spoken is underlined in `signal`; the rest of the
    /// sentence is plain text.
    private func text(isCurrent: Bool) -> Text {
        guard isCurrent, showsWords, let word = playhead.word, word.upperBound <= sentence.text.count else {
            return Text(sentence.text)
        }
        let characters = Array(sentence.text)
        return Text(String(characters[..<word.lowerBound]))
            + Text(String(characters[word])).underline(true, color: AttenColor.signal)
            + Text(String(characters[word.upperBound...]))
    }

    /// Full strength on the sentence being spoken, falling to 40% three
    /// sentences away.
    static func opacity(_ distance: Int) -> Double {
        switch distance {
        case 0: 1
        case 1: 0.7
        case 2: 0.52
        default: 0.4
        }
    }

    static func blur(_ distance: Int) -> CGFloat {
        switch distance {
        case 0: 0
        case 1: 1
        case 2: 1.5
        default: 2
        }
    }
}

// MARK: - Cover and header

/// The large cover at the top of the page. Scrolling shrinks and fades it,
/// and the header takes over.
private struct ReadAlongHero: View {
    @Bindable var model: AppModel
    let namespace: Namespace.ID
    let scroll: ReadAlongScroll

    var body: some View {
        let collapse = scroll.collapse
        VStack(spacing: AttenSpacing.md) {
            PlayingArtwork(model: model, height: 280)
                .matchedGeometryEffect(id: PlayerMatch.cover, in: namespace)
                .shadow(color: AttenColor.shadow.opacity(0.25), radius: 24, y: 12)
                .scaleEffect(1 - 0.2 * collapse, anchor: .bottom)
                .opacity(1 - collapse)
            VStack(spacing: AttenSpacing.xxs) {
                Text(model.playerTitle ?? "")
                    .attenText(.title1)
                    .foregroundStyle(AttenColor.text1)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .matchedGeometryEffect(id: PlayerMatch.title, in: namespace)
                if let subtitle {
                    Text(subtitle)
                        .attenText(.callout)
                        .foregroundStyle(AttenColor.text2)
                        .lineLimit(1)
                }
            }
            .opacity(1 - collapse)
            actions
        }
        .padding(.top, AttenSpacing.xxl)
        .padding(.bottom, AttenSpacing.xl)
        .frame(maxWidth: .infinity)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: ReadAlongScroll.OffsetKey.self,
                    value: proxy.frame(in: .named(ReadAlongScroll.space)).minY
                )
            }
        }
    }

    private var subtitle: String? {
        let parts = [model.playerSubtitle, model.queue.position].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    @ViewBuilder private var actions: some View {
        HStack(spacing: AttenSpacing.lg) {
            if let book = model.playingBook {
                Button("Read") {
                    model.section = .library
                    model.openInLibrary(.reader(book.id))
                }
                Button("Details") {
                    model.section = .library
                    model.openInLibrary(.book(book.id))
                }
            } else if model.playingProject != nil {
                Button("Open in Create") { model.section = .studio }
            }
        }
        .buttonStyle(AttenTertiaryButtonStyle())
    }
}

/// The cover and title, small, once the large cover has scrolled away.
private struct ReadAlongHeader: View {
    @Bindable var model: AppModel
    let scroll: ReadAlongScroll

    var body: some View {
        let shown = min(1, max(0, (scroll.collapse - 0.6) / 0.4))
        HStack(spacing: AttenSpacing.sm) {
            PlayingArtwork(model: model, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.playerTitle ?? "")
                    .attenText(.callout)
                    .fontWeight(.semibold)
                    .foregroundStyle(AttenColor.text1)
                    .lineLimit(1)
                if let subtitle = model.playerSubtitle {
                    Text(subtitle)
                        .attenText(.callout)
                        .foregroundStyle(AttenColor.text2)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(AttenSpacing.xs)
        .frame(maxWidth: 680)
        .attenGlass(cornerRadius: AttenRadius.card)
        .opacity(shown)
        .offset(y: -8 * (1 - shown))
        .allowsHitTesting(shown > 0.5)
        .accessibilityHidden(shown < 0.5)
    }
}

/// Names shared with the mini player for the flight between the two.
enum PlayerMatch {
    static let cover = "player.cover"
    static let title = "player.title"
    static let play = "player.play"
}

// MARK: - Transport

struct ReadAlongTransport: View {
    @Bindable var model: AppModel
    let namespace: Namespace.ID
    let script: ReadAlongScript
    let playhead: ReadAlongPlayhead

    @State private var isShowingChapters = false
    @State private var isShowingBookmarks = false
    @Environment(\.attenIsOffscreenRender) private var isOffscreenRender

    private var hasChapters: Bool {
        (model.playingBook?.playbackChapters.count ?? 0) > 1 || model.queue.tracks.count > 1
    }

    /// The recording's own chapters, when it has more than one.
    private var chapters: [ListeningMap.Chapter] {
        guard let map = model.listeningMap, map.chapters.count > 1 else { return [] }
        return map.chapters
    }

    var body: some View {
        VStack(spacing: AttenSpacing.xs) {
            HStack(spacing: AttenSpacing.sm) {
                Text(PlaybackFormat.timeText(model.playbackPosition))
                    .frame(minWidth: 44, alignment: .leading)
                ScrubBar(
                    position: model.playbackPosition,
                    duration: model.playbackDuration,
                    seek: model.seek(to:),
                    neutral: true,
                    chapters: chapters
                )
                Text("-" + PlaybackFormat.timeText(model.playbackRemaining))
                    .frame(minWidth: 44, alignment: .trailing)
            }
            .attenText(.label)
            .foregroundStyle(AttenColor.text2)
            // The scrubber names the chapter under the pointer just below
            // itself, over the row of buttons.
            .zIndex(1)

            ZStack {
                HStack(spacing: 0) {
                    VoiceLevelGlyph(model: model)
                    if !chapters.isEmpty { chapterButton }
                    if model.playingBook != nil { bookmarkButton }
                    Spacer()
                    SleepTimerControl(timer: model.sleepTimer)
                    speed
                        .padding(.leading, AttenSpacing.xs)
                }
                HStack(spacing: AttenSpacing.xs) {
                    if hasChapters {
                        transportButton("backward.end.fill", "Previous chapter",
                                        enabled: model.hasPreviousChapter || model.playbackPosition > 3,
                                        action: model.playPrevious)
                    }
                    transportButton("gobackward.15", "Back 15 seconds") {
                        model.skip(by: -NowPlayingCenter.skipInterval)
                    }
                    ReadAlongPlayButton(model: model)
                        .matchedGeometryEffect(id: PlayerMatch.play, in: namespace)
                    transportButton("goforward.15", "Forward 15 seconds") {
                        model.skip(by: NowPlayingCenter.skipInterval)
                    }
                    if hasChapters {
                        transportButton("forward.end.fill", "Next chapter",
                                        enabled: model.hasNextChapter, action: model.playNext)
                    }
                }
            }
        }
        .padding(.horizontal, AttenSpacing.md)
        .padding(.vertical, AttenSpacing.sm)
        .frame(maxWidth: 680)
        .attenGlass(cornerRadius: AttenRadius.panel)
        .matchedGeometryEffect(id: "player", in: namespace)
    }

    private var chapterButton: some View {
        PlayerToolButton(systemImage: "list.bullet", label: "Chapters") { isShowingChapters = true }
            .popover(isPresented: $isShowingChapters, arrowEdge: .top) { chapterList }
    }

    private var chapterList: some View {
        let map = model.listeningMap
        return PlayerChapterList(
            chapters: chapters,
            current: map?.chapterIndex(at: model.playbackPosition)
        ) { chapter in
            model.seek(to: chapter.start)
            if !model.isPlaying { model.toggleActivePlayback() }
            isShowingChapters = false
        }
    }

    private var bookmarkButton: some View {
        PlayerToolButton(systemImage: "bookmark", label: "Bookmarks") { isShowingBookmarks = true }
            .popover(isPresented: $isShowingBookmarks, arrowEdge: .top) { bookmarkList }
    }

    private var bookmarkList: some View {
        let book = model.playingBook
        let map = model.listeningMap
        let entries = (book?.bookmarks ?? []).map { bookmark in
            PlayerBookmarkList.Entry(
                bookmark: bookmark,
                chapterTitle: book.flatMap { book in
                    book.chapters.indices.contains(bookmark.location.chapterIndex)
                        ? book.chapters[bookmark.location.chapterIndex].title : nil
                } ?? book?.title ?? "",
                time: map?.chapters.contains { $0.index == bookmark.location.chapterIndex } == true
                    ? model.time(of: bookmark, script: script) : nil
            )
        }
        return PlayerBookmarkList(
            entries: entries,
            add: { model.addBookmark(sentence: playhead.sentence, of: script) },
            jump: { entry in
                guard let time = entry.time else { return }
                model.seek(to: time)
                if !model.isPlaying { model.toggleActivePlayback() }
                isShowingBookmarks = false
            },
            remove: { entry in
                guard let book else { return }
                model.bookshelf.removeBookmark(entry.bookmark.id, from: book.id)
            }
        )
    }

    private func transportButton(
        _ systemImage: String,
        _ label: String,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(AttenColor.text1)
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : AttenState.disabledOpacity)
        .help(label)
        .accessibilityLabel(label)
    }

    /// Speed is cheap to change and undoable, so it sits here, one click
    /// away, rather than being asked for before anything plays.
    @ViewBuilder private var speed: some View {
        if isOffscreenRender {
            speedLabel
        } else {
            speedMenu
        }
    }

    private var speedLabel: some View {
        Text(PlaybackFormat.rateText(model.playbackRate))
            .attenText(.label)
            .foregroundStyle(AttenColor.text2)
    }

    private var speedMenu: some View {
        Menu {
            ForEach(PlaybackFormat.rates, id: \.self) { rate in
                Button {
                    model.setPlaybackRate(rate)
                } label: {
                    if rate == model.playbackRate {
                        Label(PlaybackFormat.rateText(rate), systemImage: "checkmark")
                    } else {
                        Text(PlaybackFormat.rateText(rate))
                    }
                }
            }
        } label: {
            speedLabel
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Listening speed")
        .accessibilityLabel("Listening speed")
        .accessibilityValue(PlaybackFormat.rateText(model.playbackRate))
    }
}

/// Play and pause, with a glow that breathes with the voice while it plays.
private struct ReadAlongPlayButton: View {
    @Bindable var model: AppModel

    var body: some View {
        Button(action: model.toggleActivePlayback) {
            Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(AttenColor.bg)
                .frame(width: 52, height: 52)
                .background(Circle().fill(AttenColor.text1))
                .contentTransition(.symbolEffect(.replace))
                .contentShape(Circle())
                .background {
                    if model.isPlaying {
                        VoiceLevel(model: model) { level in
                            Circle()
                                .fill(AttenColor.signal)
                                .blur(radius: 10)
                                .scaleEffect(1 + 0.22 * level)
                                .opacity(0.25 + 0.35 * level)
                        }
                        .transition(.opacity)
                    }
                }
        }
        .buttonStyle(.plain)
        .attenFocusRing(cornerRadius: 26)
        .help(model.isPlaying ? "Pause (Space)" : "Play (Space)")
        .accessibilityLabel(model.isPlaying ? "Pause" : "Play")
        .animation(.easeInOut(duration: AttenMotion.state), value: model.isPlaying)
    }
}

/// Four bars that rise and fall with the voice. Signal while it speaks.
private struct VoiceLevelGlyph: View {
    @Bindable var model: AppModel
    private static let shape: [CGFloat] = [0.55, 1, 0.75, 0.4]

    var body: some View {
        VoiceLevel(model: model) { level in
            HStack(spacing: 2) {
                ForEach(Self.shape.indices, id: \.self) { index in
                    Capsule()
                        .frame(width: 3, height: 16)
                        .scaleEffect(y: model.isPlaying ? Self.shape[index] * (0.3 + 0.7 * level) : 0.2)
                }
            }
            .foregroundStyle(model.isPlaying ? AttenColor.signal : AttenColor.text3)
        }
        .frame(width: 40, height: 40, alignment: .leading)
        .accessibilityHidden(true)
    }
}

/// Hands `content` the voice's level, fresh every frame while it plays.
/// Under Reduce Motion the level holds still at a middle value.
private struct VoiceLevel<Content: View>: View {
    let model: AppModel
    @ViewBuilder let content: (Double) -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static var heldLevel: Double { 0.5 }

    var body: some View {
        if reduceMotion {
            content(Self.heldLevel)
        } else {
            TimelineView(.animation(minimumInterval: nil, paused: !model.isPlaying)) { context in
                content(model.levelMeter.level(at: context.date))
            }
        }
    }
}

// MARK: - Keyboard

/// Space plays and pauses; the arrows skip fifteen seconds; ⌘D marks the
/// sentence being spoken, as it marks the page in the Reader.
private struct ReadAlongKeys: View {
    let model: AppModel
    let script: ReadAlongScript
    let playhead: ReadAlongPlayhead

    var body: some View {
        ZStack {
            Button("Add bookmark") {
                model.addBookmark(sentence: playhead.sentence, of: script)
            }
            .keyboardShortcut("d", modifiers: .command)
            Button("Play or pause", action: model.toggleActivePlayback)
                .keyboardShortcut(.space, modifiers: [])
            Button("Back 15 seconds") { model.skip(by: -NowPlayingCenter.skipInterval) }
                .keyboardShortcut(.leftArrow, modifiers: [])
            Button("Forward 15 seconds") { model.skip(by: NowPlayingCenter.skipInterval) }
                .keyboardShortcut(.rightArrow, modifiers: [])
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
