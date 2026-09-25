"""A disk that fills up in the middle of a narration or an export.

The quick tests fake the failing write. The slow one, run with
ATTEN_STRESS_TESTS=1 on macOS, fills a real 20 MB disk image mounted in a
temporary folder, and always detaches it again.
"""

import errno
import os
from pathlib import Path
import subprocess
import sys
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

from atten_backend.service import GenerationRequest, GenerationService, SoundFileAudioIO


class Provider:
    """Yields `count` segments of `seconds` of quiet noise each."""

    def __init__(self, count, seconds):
        self.count, self.seconds = count, seconds

    def segments(self, text, voice, speed):
        import numpy as np

        for _ in range(self.count):
            yield ("Words.", None, np.full(int(24000 * self.seconds), 0.01, dtype="float32"))


def leftovers(directory):
    return sorted(path.name for path in Path(directory).rglob("*") if path.is_file())


class FullDiskTests(unittest.TestCase):
    def test_a_segment_that_cannot_be_written_names_the_full_disk(self):
        # A narration writes its segments to the library's own disk. libsndfile
        # reported that disk filling up as a bare "System error".
        with TemporaryDirectory() as directory:
            audio_io = SoundFileAudioIO()

            def fail(path, audio):
                raise RuntimeError("Error opening file: System error.")

            audio_io.write = fail
            segments = Path(directory) / "segments"
            with patch("atten_backend.service._disk_is_full", return_value=True):
                with self.assertRaisesRegex(RuntimeError, "is full"):
                    GenerationService(Provider(1, 0.1), audio_io).generate(GenerationRequest(
                        text="Words.", output_directory=Path(directory), segments_directory=segments,
                    ))
            self.assertEqual(leftovers(directory), [])

    def test_an_export_that_cannot_be_written_names_the_full_disk_and_leaves_nothing(self):
        with TemporaryDirectory() as directory:
            source = Path(directory) / "source.wav"
            SoundFileAudioIO().write(source, [0.1] * 2400)
            destination = Path(directory) / "out" / "export.wav"
            real_replace = os.replace

            def full(*args):
                raise OSError(errno.ENOSPC, "No space left on device")

            with patch("atten_backend.service.os.replace", side_effect=full):
                with self.assertRaisesRegex(RuntimeError, "is full"):
                    SoundFileAudioIO().transcode(source, destination)
            self.assertIs(os.replace, real_replace)
            self.assertEqual(leftovers(destination.parent), [])


@unittest.skipUnless(
    os.environ.get("ATTEN_STRESS_TESTS") == "1" and sys.platform == "darwin",
    "Set ATTEN_STRESS_TESTS=1 on macOS to fill a real disk image",
)
class RealFullDiskTests(unittest.TestCase):
    def setUp(self):
        self.scratch = TemporaryDirectory()
        root = Path(self.scratch.name)
        self.image = root / "full.dmg"
        self.volume = root / "volume"
        self.volume.mkdir()
        subprocess.run(["hdiutil", "create", "-size", "20m", "-fs", "HFS+", "-volname", "AttenFull",
                        str(self.image)], check=True, capture_output=True)
        subprocess.run(["hdiutil", "attach", str(self.image), "-mountpoint", str(self.volume),
                        "-nobrowse", "-noverify", "-noautoopen"], check=True, capture_output=True)
        # Detach even when a test fails, and before the folder it is in goes.
        self.addCleanup(self.scratch.cleanup)
        self.addCleanup(subprocess.run, ["hdiutil", "detach", str(self.volume), "-force"],
                        capture_output=True)

    def test_narration_segments_on_a_full_disk_fail_plainly_and_leave_nothing(self):
        output = self.volume / "Narrations" / "chapter-1"
        segments = output / "segments"
        # Two minutes a segment is about 5.5 MB; the fourth cannot fit.
        with self.assertRaisesRegex(RuntimeError, "is full"):
            GenerationService(Provider(6, 120), SoundFileAudioIO()).generate(GenerationRequest(
                text="Words.", output_directory=output, filename="001 Chapter", segments_directory=segments,
            ))
        # Segments already written stay for the app to discard with the
        # chapter; nothing partial is published and no hidden file is left.
        self.assertFalse((output / "001 Chapter.mp3").exists())
        self.assertEqual([name for name in leftovers(output) if not name.startswith("seg-")], [])

    def test_a_merge_on_a_full_disk_fails_plainly_and_publishes_nothing(self):
        output = self.volume / "Exports"
        with self.assertRaisesRegex(RuntimeError, "is full"):
            GenerationService(Provider(4, 120), SoundFileAudioIO()).generate(GenerationRequest(
                text="Words.", output_directory=output, filename="Too long", output_format="wav",
            ))
        self.assertEqual(leftovers(output), [])

    def test_an_export_to_a_full_disk_fails_plainly_and_leaves_nothing(self):
        source = Path(self.scratch.name) / "source.wav"
        SoundFileAudioIO().write(source, [0.01] * (24000 * 600))
        destination = self.volume / "Book.wav"
        with self.assertRaisesRegex(RuntimeError, "is full"):
            SoundFileAudioIO().transcode(source, destination)
        self.assertEqual(leftovers(self.volume), [])


if __name__ == "__main__":
    unittest.main()
