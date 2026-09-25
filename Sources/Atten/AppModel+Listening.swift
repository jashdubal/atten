import AttenCore
import Foundation

/// Chapters, bookmarks and the sleep timer, over the one player `AppModel`
/// already owns.
extension AppModel {
    /// Where the chapters of what is playing lie in its recording. Nil for
    /// anything that is not a book.
    var listeningMap: ListeningMap? {
        guard let track = queue.current, let book = playingBook else { return nil }
        if book.hasBookAudio, book.audioURL == track.url {
            return ListeningMap(book: book, duration: playbackDuration)
        }
        guard let index = book.chapters.firstIndex(where: { $0.id == track.id }) else { return nil }
        return ListeningMap(chapter: index, of: book, duration: playbackDuration)
    }

    /// The chapter being heard, for a recording that has more than one.
    var playingChapterTitle: String? {
        guard let map = listeningMap, map.chapters.count > 1,
              let index = map.chapterIndex(at: playbackPosition) else { return nil }
        return map.chapters[index].title
    }

    // MARK: - Bookmarks

    /// Marks the sentence being spoken, in the book's own bookmark list, so
    /// the Reader shows it as well.
    func addBookmark(sentence index: Int?, of script: ReadAlongScript) {
        let sentence = index.flatMap { script.sentences.indices.contains($0) ? script.sentences[$0] : nil }
        guard let book = playingBook, let map = listeningMap,
              let location = map.location(at: sentence?.start ?? playbackPosition, sentence: sentence?.text)
        else { return }
        let spoken = sentence.map { ListeningMap.normalized($0.text) } ?? ""
        let excerpt = spoken.isEmpty
            ? map.chapters.first { $0.index == location.chapterIndex }?.title ?? book.title
            : String(spoken.prefix(160))
        bookshelf.addBookmark(at: location, excerpt: excerpt, in: book.id)
    }

    /// When a bookmark, made here or in the Reader, is spoken.
    func time(of bookmark: Bookmark, script: ReadAlongScript) -> TimeInterval? {
        listeningMap?.time(of: bookmark.location, excerpt: bookmark.excerpt, script: script)
    }

    // MARK: - Sleep timer

    func connectSleepTimer() {
        sleepTimer.observe = { [weak self] in self?.sleepTimerPlayback() ?? .init(isPlaying: false) }
        sleepTimer.setVolume = { [weak self] volume in self?.setPlaybackVolume(volume) }
        sleepTimer.pause = { [weak self] in
            guard let self else { return }
            queue.current != nil ? pause() : progressivePlayer.pause()
        }
    }

    /// The ordinary player wins when both are somehow active, as it does for
    /// the media keys.
    private func sleepTimerPlayback() -> SleepTimer.Playback {
        if let track = queue.current {
            let map = listeningMap
            let index = map?.chapterIndex(at: playbackPosition)
            let end = index.flatMap { map?.chapters[$0].end } ?? playbackDuration
            return SleepTimer.Playback(
                isPlaying: isPlaying,
                secondsToChapterEnd: max(0, end - playbackPosition) / max(0.1, playbackRate),
                chapter: "\(track.id)#\(index ?? 0)"
            )
        }
        let progressive = progressivePlayer
        return SleepTimer.Playback(
            isPlaying: progressive.state == .playing,
            secondsToChapterEnd: progressive.chapterEnd.map { max(0, $0 - progressive.position) },
            chapter: progressive.activeSentence.map { "\(progressive.bookID?.uuidString ?? "")#\($0.chapterIndex)" }
        )
    }
}
