import json
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

import cli
from atten_backend.service import GenerationRequest, GenerationService


class FakeProvider:
    def __init__(self, segments=None, error=None):
        self.audio_segments = segments if segments is not None else [[0.1], [0.2]]
        self.error = error
        self.calls = []

    def segments(self, text, voice, speed):
        self.calls.append((text, voice, speed))
        if self.error:
            raise self.error
        for audio in self.audio_segments:
            yield (None, None, audio)


class FakeAudioIO:
    sample_rate = 24000

    def __init__(self):
        self.contents = {}
        self.writes = []

    def write(self, path, audio):
        path = Path(path)
        path.write_bytes(b"audio")
        self.contents[path] = list(audio)
        self.writes.append((path, list(audio)))

    def read(self, path):
        return self.contents[Path(path)]


class GenerationServiceTests(unittest.TestCase):
    def test_generation_merges_segments_and_reports_progress(self):
        with TemporaryDirectory() as directory:
            progress = []
            provider = FakeProvider([[0.1, 0.2], [0.3]])
            audio_io = FakeAudioIO()
            service = GenerationService(provider, audio_io)

            result = service.generate(
                GenerationRequest(
                    text="Hello woods",
                    voice="bf_emma",
                    speed=1.2,
                    output_format="wav",
                    output_directory=Path(directory),
                    filename="greeting",
                ),
                progress.append,
            )

            self.assertEqual(result.output_path.name, "greeting.wav")
            self.assertEqual(result.segment_count, 2)
            self.assertEqual(progress, [1, 2])
            self.assertEqual(provider.calls, [("Hello woods", "bf_emma", 1.2)])
            self.assertEqual(audio_io.writes[-1][1], [0.1, 0.2, 0.3])

    def test_provider_failure_does_not_publish_partial_file(self):
        with TemporaryDirectory() as directory:
            service = GenerationService(
                FakeProvider(error=RuntimeError("model failed")), FakeAudioIO()
            )
            with self.assertRaisesRegex(RuntimeError, "model failed"):
                service.generate(
                    GenerationRequest(text="Hello", output_directory=Path(directory))
                )
            self.assertEqual(list(Path(directory).iterdir()), [])

    def test_existing_export_is_never_overwritten(self):
        with TemporaryDirectory() as directory:
            existing = Path(directory) / "saved.mp3"
            existing.write_bytes(b"keep")
            service = GenerationService(FakeProvider(), FakeAudioIO())
            with self.assertRaises(FileExistsError):
                service.generate(
                    GenerationRequest(
                        text="Hello",
                        output_directory=Path(directory),
                        filename="saved",
                    )
                )
            self.assertEqual(existing.read_bytes(), b"keep")

    def test_empty_text_and_invalid_format_are_rejected(self):
        service = GenerationService(FakeProvider(), FakeAudioIO())
        with self.assertRaises(ValueError):
            service.generate(GenerationRequest(text="  "))
        with self.assertRaises(ValueError):
            service.generate(GenerationRequest(text="Hello", output_format="flac"))


class CLICompatibilityTests(unittest.TestCase):
    def test_original_defaults_remain_available(self):
        args = cli.build_parser().parse_args(["hello"])
        self.assertEqual(args.voice, "af_heart")
        self.assertEqual(args.speed, 1.0)
        self.assertEqual(args.format, "mp3")
        self.assertEqual(args.output, "outputs")

    def test_voice_catalog_is_json_serializable(self):
        args = cli.build_parser().parse_args(["--list-voices", "--json"])
        self.assertTrue(args.list_voices)
        json.dumps(cli.VOICES)


if __name__ == "__main__":
    unittest.main()
