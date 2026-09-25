from pathlib import Path
from tempfile import TemporaryDirectory
import types
import unittest

import numpy as np

from atten_backend.service import GenerationRequest, GenerationService
from atten_backend.word_timings import estimate_word_timings
from test_backend import FakeAudioIO, FakeProvider

RATE = 24000


def bursts(spans, duration, seed=0):
    """A tone over each (start, end) span and a faint hiss everywhere else."""
    random = np.random.default_rng(seed)
    audio = random.normal(0, 0.0005, int(duration * RATE)).astype(np.float32)
    for start, end in spans:
        time = np.arange(int(start * RATE), int(end * RATE)) / RATE
        audio[int(start * RATE):int(start * RATE) + len(time)] += (
            random.uniform(0.2, 0.6) * np.sin(2 * np.pi * random.uniform(120, 300) * time)
        )
    return audio


class WordTimingTestCase(unittest.TestCase):
    def assertLandsOn(self, words, spans):
        self.assertEqual(len(words), len(spans))
        for word, (start, end) in zip(words, spans):
            self.assertAlmostEqual(word["start"], start, delta=0.04, msg=word)
            self.assertAlmostEqual(word["end"], end, delta=0.04, msg=word)


class EstimatedWordTimingTests(WordTimingTestCase):
    def test_word_boundaries_land_on_the_gaps_between_bursts(self):
        # The bursts are only roughly as long as the syllables say, so only
        # the gaps can put every boundary where it is.
        text = "Extraordinarily a cat sat, beside the unimaginable dog."
        lengths = [0.8, 0.2, 0.15, 0.25, 0.5, 0.12, 0.7, 0.22]
        pauses = [0.15, 0.2, 0.13, 0.25, 0.15, 0.18, 0.3]
        spans, start = [], 0.1
        for length, pause in zip(lengths, pauses + [0]):
            spans.append((start, start + length))
            start += length + pause
        words = estimate_word_timings(text, bursts(spans, start + 0.3), RATE)
        self.assertEqual([word["text"] for word in words],
                         ["Extraordinarily", "a", "cat", "sat", "beside", "the", "unimaginable", "dog"])
        self.assertLandsOn(words, spans)

    def test_a_single_pause_goes_to_the_punctuation(self):
        # One pause and two phrases: by syllables alone the pause would follow
        # "jumped", but the comma puts it after "fox".
        text = "The quick brown fox, jumped over the lazy dog."
        words = estimate_word_timings(text, bursts([(0.2, 1.3), (1.5, 2.9)], 3.2), RATE)
        fox, jumped = words[3], words[4]
        self.assertEqual((fox["text"], jumped["text"]), ("fox", "jumped"))
        self.assertAlmostEqual(fox["end"], 1.3, delta=0.04)
        self.assertAlmostEqual(jumped["start"], 1.5, delta=0.04)
        self.assertAlmostEqual(words[0]["start"], 0.2, delta=0.04)
        self.assertAlmostEqual(words[-1]["end"], 2.9, delta=0.04)
        for before, after in zip(words, words[1:]):
            self.assertLessEqual(before["end"], after["start"])

    def test_a_pause_shorter_than_the_minimum_is_not_a_boundary(self):
        words = estimate_word_timings("cat dog", bursts([(0.0, 0.5), (0.58, 1.0)], 1.0), RATE)
        self.assertAlmostEqual(words[0]["end"], 0.5, delta=0.04)
        self.assertEqual(words[0]["end"], words[1]["start"])

    def test_an_empty_segment_has_no_words(self):
        audio = bursts([(0.1, 0.5)], 1.0)
        self.assertEqual(estimate_word_timings("", audio, RATE), [])
        self.assertEqual(estimate_word_timings(None, audio, RATE), [])
        self.assertEqual(estimate_word_timings(" — … ", audio, RATE), [])
        self.assertEqual(estimate_word_timings("Hello", [], RATE), [])

    def test_a_single_word_spans_the_speech(self):
        words = estimate_word_timings("Hello!", bursts([(0.12, 0.61)], 1.0), RATE)
        self.assertEqual([word["text"] for word in words], ["Hello"])
        self.assertLandsOn(words, [(0.12, 0.61)])

    def test_silence_and_audio_shorter_than_a_frame_spread_words_over_it(self):
        words = estimate_word_timings("a b", np.zeros(RATE, dtype=np.float32), RATE)
        self.assertEqual([(word["start"], word["end"]) for word in words], [(0, 0.5), (0.5, 1.0)])
        self.assertEqual(estimate_word_timings("a", [0.1], RATE), [{"text": "a", "start": 0, "end": 0.0}])

    def test_words_without_spaces_are_timed_one_character_at_a_time(self):
        words = estimate_word_timings("你好，世界。", bursts([(0.1, 1.0)], 1.0), RATE)
        self.assertEqual([word["text"] for word in words], ["你", "好", "世", "界"])


class GenerationWordTimingTests(WordTimingTestCase):
    def generate(self, provider, pause=None):
        events = []
        with TemporaryDirectory() as directory:
            root = Path(directory)
            GenerationService(provider, FakeAudioIO()).generate(
                GenerationRequest(text="unused", output_directory=root, filename="book",
                                  output_format="wav", segments_directory=root / "segments",
                                  pause=pause),
                segment_ready=events.append,
            )
        return events

    def test_kokoro_timings_pass_through_unchanged(self):
        kokoro = [{"text": "Hello", "start": 0.03, "end": 0.2}, {"text": "there", "start": 0.9, "end": 1.1}]

        class Result:
            tokens = [types.SimpleNamespace(text=word["text"], start_ts=word["start"], end_ts=word["end"])
                      for word in kokoro]

            def __iter__(self):
                return iter(("Hello there", "phonemes", bursts([(0.1, 0.4), (0.6, 1.2)], 1.5)))

        provider = FakeProvider()
        provider.segments = lambda *_: iter([Result()])
        self.assertEqual(self.generate(provider)[0]["words"], kokoro)

    def test_a_voice_without_word_times_has_them_estimated_under_every_pause(self):
        spans = [(0.1, 0.5), (0.7, 1.2)]
        provider = FakeProvider()
        provider.segments = lambda *_: iter([("Hello, there.", "Hello, there.", bursts(spans, 1.5))])
        for pause in (None, "short", "long"):
            words = self.generate(provider, pause)[0]["words"]
            self.assertEqual([word["text"] for word in words], ["Hello", "there"])
            self.assertLandsOn(words, spans)


if __name__ == "__main__":
    unittest.main()
