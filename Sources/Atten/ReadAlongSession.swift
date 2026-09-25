import AttenCore
import Foundation
import SwiftUI

/// What the full player is following: the ordinary queue, or a narration
/// heard while it is still being generated (P5).
///
/// The queue wins when both are somehow active, as it does for the media
/// keys and Now Playing. When a narration finishes and hands off to its
/// assembled file, the source moves from one to the other in the same
/// moment, so the player never has nothing to show in between.
@MainActor
struct ReadAlongSession {
    enum Source: Hashable {
        case queue(track: UUID)
        case progressive(book: UUID)
    }

    let model: AppModel

    var source: Source? {
        if let track = model.queue.current { return .queue(track: track.id) }
        if let book = model.progressiveBook { return .progressive(book: book.id) }
        return nil
    }

    var isProgressive: Bool {
        if case .progressive = source { return true }
        return false
    }

    /// The book being heard, from either source.
    var book: BookRecord? { model.playingBook ?? model.progressiveBook }

    var title: String? { model.playerTitle ?? model.progressiveBook?.title }

    var subtitle: String? { isProgressive ? "Narrating…" : model.playerSubtitle }

    var position: TimeInterval { isProgressive ? model.progressivePlayer.position : model.playbackPosition }

    /// Only what has been generated so far, while narrating: the scrubber
    /// cannot reach past it.
    var duration: TimeInterval { isProgressive ? model.progressivePlayer.duration : model.playbackDuration }

    var remaining: TimeInterval { isProgressive ? max(0, duration - position) : model.playbackRemaining }

    var isPlaying: Bool { isProgressive ? model.progressivePlayer.isPlaying : model.isPlaying }

    /// Playback has run into the end of what has been generated.
    var isCatchingUp: Bool { isProgressive && model.progressivePlayer.state == .catchingUp }

    /// The position right now, fresh every frame, for following word by word.
    var clock: TimeInterval {
        isProgressive ? model.progressivePlayer.currentTime : model.levelMeter.currentTime
    }

    /// Changes whenever the script has to be built again: another track, or
    /// another segment of the narration.
    var scriptKey: ScriptKey {
        ScriptKey(source: source, segments: isProgressive ? model.progressivePlayer.timeline.placed.count : 0)
    }

    struct ScriptKey: Equatable {
        let source: Source?
        let segments: Int
    }

    var listeningMap: ListeningMap? {
        guard isProgressive else { return model.listeningMap }
        guard let book = model.progressiveBook else { return nil }
        return Self.listeningMap(book: book, timeline: model.progressivePlayer.timeline)
    }

    func seek(to time: TimeInterval) {
        isProgressive ? model.progressivePlayer.seek(to: time) : model.seek(to: time)
    }

    func skip(by seconds: TimeInterval) {
        isProgressive ? model.progressivePlayer.seek(to: position + seconds) : model.skip(by: seconds)
    }

    func toggle() {
        isProgressive ? model.progressivePlayer.toggle() : model.toggleActivePlayback()
    }

    func addBookmark(sentence index: Int?, of script: ReadAlongScript) {
        guard isProgressive else { return model.addBookmark(sentence: index, of: script) }
        guard let book = model.progressiveBook, let map = listeningMap else { return }
        model.addBookmark(sentence: index, of: script, in: book, map: map, at: position)
    }

    func time(of bookmark: Bookmark, script: ReadAlongScript) -> TimeInterval? {
        listeningMap?.time(of: bookmark.location, excerpt: bookmark.excerpt, script: script)
    }

    // MARK: - Narration so far

    /// Each chapter narrated so far, from its first segment to the next
    /// chapter's. The last runs to the end of what has been generated.
    nonisolated static func listeningMap(book: BookRecord, timeline: ProgressiveTimeline) -> ListeningMap {
        var starts: [(index: Int, start: Double)] = []
        for entry in timeline.placed where starts.last?.index != entry.chapterIndex {
            starts.append((entry.chapterIndex, entry.start))
        }
        return ListeningMap(chapters: starts.enumerated().compactMap { position, chapter in
            guard book.chapters.indices.contains(chapter.index) else { return nil }
            let text = book.chapters[chapter.index]
            return ListeningMap.Chapter(
                index: chapter.index, title: text.title, text: text.text, pageIndex: text.pageIndex,
                start: chapter.start,
                end: starts.indices.contains(position + 1) ? starts[position + 1].start : timeline.duration
            )
        })
    }

    /// The segments heard so far, word-timed. An engine that times no words
    /// has them estimated, as the finished recording's timings do.
    nonisolated static func script(for timeline: ProgressiveTimeline) -> ReadAlongScript {
        ReadAlongScript(timings: NarrationTimings(
            segments: timeline.narrationTimings.segments.map { $0.estimatingMissingWords() }
        ))
    }

    /// The text still waiting to be narrated: the rest of the chapter being
    /// generated, then every later chapter not yet narrated.
    nonisolated static func remainder(of book: BookRecord, after timeline: ProgressiveTimeline) -> [ReadAlongRemainder] {
        guard let last = timeline.placed.last, book.chapters.indices.contains(last.chapterIndex) else { return [] }
        let current = book.chapters[last.chapterIndex].text
        let words = current.split(whereSeparator: \.isWhitespace)
        let spoken = last.wordsBefore + last.wordCount
        var parts: [ReadAlongRemainder] = []
        func add(_ text: Substring, heading: String?) {
            let paragraphs = text.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            for (index, paragraph) in paragraphs.enumerated() {
                parts.append(ReadAlongRemainder(id: parts.count, heading: index == 0 ? heading : nil, text: paragraph))
            }
        }
        if spoken < words.count { add(current[words[spoken].startIndex...], heading: nil) }
        for chapter in book.chapters[(last.chapterIndex + 1)...] where !chapter.isNarrated {
            add(Substring(chapter.text), heading: chapter.title)
        }
        return parts
    }
}

/// A paragraph not yet narrated, shown after the sentences that have been.
struct ReadAlongRemainder: Identifiable, Equatable, Sendable {
    let id: Int
    /// The chapter's title, over its first paragraph.
    let heading: String?
    let text: String
}

extension AppModel {
    /// The book being listened to as it narrates, while nothing is queued.
    var progressiveBook: BookRecord? {
        guard queue.current == nil, let id = progressivePlayer.bookID else { return nil }
        return bookshelf.book(id: id)
    }
}

/// Text the voice has not reached because it has not been generated yet,
/// waiting in `text3` the way Create shows a narration catching up.
struct RemainderRow: View {
    let part: ReadAlongRemainder

    var body: some View {
        VStack(alignment: .leading, spacing: AttenSpacing.sm) {
            if let heading = part.heading {
                Text(heading)
                    .attenText(.label)
                    .foregroundStyle(AttenColor.text3)
                    .padding(.top, AttenSpacing.xl)
                    .accessibilityAddTraits(.isHeader)
            }
            Text(part.text)
                .attenText(.reading)
                .foregroundStyle(AttenColor.text3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, AttenSpacing.lg)
        .accessibilityHint("Not narrated yet")
    }
}
