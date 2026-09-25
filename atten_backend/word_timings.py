"""Word times for voices that do not report their own.

Kokoro says when each word was spoken. XTTS and MMS only return audio, so
their words are placed here from the audio itself: the pauses a voice leaves
are found by loudness, the words between two pauses share that stretch by
their syllables, and a word ending in punctuation is the one a pause is
most likely to follow.
"""

import re
import unicodedata

FRAME_SECONDS = 0.01
MINIMUM_GAP_SECONDS = 0.12
# A frame is quiet when it is 30 dB below the segment's loud frames.
RELATIVE_THRESHOLD = 10 ** (-30 / 20)
# How much nearer a pause may sit to some other word's end before a word that
# ends in punctuation stops being the one it is given to.
PUNCTUATION_PULL_SECONDS = 0.35
# What leaving a pause inside a run of words costs, and how many may be.
UNMATCHED_GAP_SECONDS = 0.5
MAXIMUM_UNMATCHED_GAPS = 3

# A Chinese or Japanese character is its own word, since those scripts put no
# spaces between words; anything else runs to the next space.
_TOKEN = re.compile(r"[\u3040-\u30ff\u3400-\u9fff]|[^\s\u3040-\u30ff\u3400-\u9fff]+")
_EDGE_PUNCTUATION = re.compile(r"^[\W_]+|[\W_]+$")
_TRAILING_PUNCTUATION = re.compile(r"[\W_]*$")
_PAUSING_PUNCTUATION = re.compile(r"[,.;:!?،؛؟，。；：！？、]")
_VOWELS = re.compile(r"[aeiouyаеёиоуыэюяіїєαεηιουω]+")


def _syllables(word):
    """Roughly how long a word takes to say, in syllables."""
    letters = "".join(
        character for character in unicodedata.normalize("NFD", word.lower())
        if not unicodedata.combining(character)
    )
    count = len(_VOWELS.findall(letters)) + sum(character.isdigit() for character in letters)
    # Scripts that write few or no vowels are counted by length instead.
    return count or max(1.0, len(letters) / 2.5)


def _words(text):
    """Each word as [text without its surrounding punctuation, syllables,
    whether punctuation after it invites a pause]."""
    words = []
    for token in _TOKEN.findall(text or ""):
        core = _EDGE_PUNCTUATION.sub("", token)
        pauses = bool(_PAUSING_PUNCTUATION.search(_TRAILING_PUNCTUATION.search(token).group()))
        if core:
            words.append([core, _syllables(core), pauses])
        elif words and pauses:
            # Punctuation standing on its own belongs to the word before it.
            words[-1][2] = True
    return words


def _speech_and_gaps(audio, sample_rate):
    """Where speech starts and ends, and the pauses inside it, in seconds."""
    import numpy as np

    samples = np.asarray(audio, dtype=np.float32).reshape(-1)
    duration = len(samples) / sample_rate
    frame = max(1, int(round(FRAME_SECONDS * sample_rate)))
    count = len(samples) // frame
    if count == 0:
        return 0.0, duration, []
    rms = np.sqrt(np.mean(samples[: count * frame].reshape(count, frame) ** 2, axis=1))
    loud = rms > RELATIVE_THRESHOLD * np.percentile(rms, 95)
    if not loud.any():
        return 0.0, duration, []
    indices = np.flatnonzero(loud)
    first, last = int(indices[0]), int(indices[-1])
    gaps = []
    minimum = MINIMUM_GAP_SECONDS / FRAME_SECONDS
    for before, after in zip(indices[:-1].tolist(), indices[1:].tolist()):
        if after - before - 1 >= minimum:
            gaps.append(((before + 1) * frame / sample_rate, after * frame / sample_rate))
    return first * frame / sample_rate, min(duration, (last + 1) * frame / sample_rate), gaps


def _islands(weights, punctuated, anchors):
    """Which words each stretch of speech between two pauses holds.

    `anchors` are where speech starts, each pause, and where speech ends,
    counted in time something is being said. Each stretch should hold about
    as many syllables as its length allows, a stretch rather ends on
    punctuation, and a pause is left inside a stretch only when no split
    there fits. Returns [(first anchor, last anchor, first word, end word)].
    """
    import numpy as np

    words, last = len(weights), len(anchors) - 1
    cumulative = np.concatenate([[0.0], np.cumsum(weights)])
    rate = anchors[-1] / cumulative[-1]
    pull = np.zeros(words + 1)
    pull[1:words] = [PUNCTUATION_PULL_SECONDS if ended else 0.0 for ended in punctuated[:-1]]
    cost = np.full((last + 1, words + 1), np.inf)
    cost[0, 0] = 0.0
    previous = {}
    for anchor in range(1, last + 1):
        # A pause sits between two words; where speech ends, after the last.
        boundaries = range(1, words) if anchor < last else [words]
        for earlier in range(max(0, anchor - 1 - MAXIMUM_UNMATCHED_GAPS), anchor):
            length = anchors[anchor] - anchors[earlier]
            skipped = (anchor - earlier - 1) * UNMATCHED_GAP_SECONDS
            for boundary in boundaries:
                options = (cost[earlier, :boundary] + skipped
                           + np.abs(length - rate * (cumulative[boundary] - cumulative[:boundary])))
                best = int(np.argmin(options))
                value = options[best] - pull[boundary]
                if value < cost[anchor, boundary]:
                    cost[anchor, boundary] = value
                    previous[anchor, boundary] = (earlier, best)
    if (last, words) not in previous:
        # More pauses than the words can explain: treat the speech as one run.
        return [(0, last, 0, words)]
    islands, anchor, boundary = [], last, words
    while anchor > 0:
        earlier, first = previous[anchor, boundary]
        islands.append((earlier, anchor, first, boundary))
        anchor, boundary = earlier, first
    return islands[::-1]


def estimate_word_timings(text, audio, sample_rate):
    """`[{text, start, end}]` for each word of `text` in `audio`, in seconds
    from the start of the segment — the shape Kokoro's own timings take."""
    words = _words(text)
    if not words or len(audio) == 0:
        return []
    speech_start, speech_end, gaps = _speech_and_gaps(audio, sample_rate)

    # Positions counted in time something is being said, so a pause the
    # words are spread across takes none of their share.
    anchors, silent = [0.0], 0.0
    for start, end in gaps:
        anchors.append(start - speech_start - silent)
        silent += end - start
    anchors.append(speech_end - speech_start - silent)

    def real(voiced):
        return speech_start + voiced + sum(
            end - start for (start, end), at in zip(gaps, anchors[1:]) if at < voiced
        )

    weights = [weight for _, weight, _ in words]
    timings = []
    for earlier, anchor, first, last in _islands(weights, [ended for *_, ended in words], anchors):
        # Within one stretch, the words share its time by syllables.
        start = gaps[earlier - 1][1] if earlier else speech_start
        end = gaps[anchor - 1][0] if anchor <= len(gaps) else speech_end
        span, total = anchors[anchor] - anchors[earlier], sum(weights[first:last])
        voiced = anchors[earlier]
        for index in range(first, last):
            voiced += span * weights[index] / total
            word_end = end if index == last - 1 else real(voiced)
            timings.append({"text": words[index][0], "start": round(start, 4), "end": round(word_end, 4)})
            start = word_end
    return timings
