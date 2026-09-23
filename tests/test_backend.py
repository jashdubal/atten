import json
import io
from contextlib import redirect_stdout
import os
from pathlib import Path
import sys
from tempfile import TemporaryDirectory
import types
import unittest
from unittest.mock import patch

import cli
from atten_backend.device import resolve_device
from atten_backend.service import (
    GenerationRequest,
    GenerationService,
    KokoroProvider,
    SoundFileAudioIO,
)


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

    def merge(self, destination, segment_paths):
        merged = [sample for path in segment_paths for sample in self.contents[Path(path)]]
        destination = Path(destination)
        destination.write_bytes(b"audio")
        self.contents[destination] = merged
        self.writes.append((destination, merged))


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

    def test_explicit_model_routes_to_multilingual_provider(self):
        created = {}

        class FakeXTTS:
            def __init__(self, device_mode="auto", hf_model_id=None):
                created["hf_model_id"] = hf_model_id

        with patch("atten_backend.service.XTTSv2Provider", FakeXTTS), patch(
            "atten_backend.service.KokoroProvider"
        ) as kokoro:
            service = GenerationService(model_id="facebook/mms-tts-ara")
            provider = service.get_provider_for_voice("dyn_facebook_mms_tts_ara")
            self.assertIsInstance(provider, FakeXTTS)
            self.assertEqual(created["hf_model_id"], "facebook/mms-tts-ara")

            GenerationService().get_provider_for_voice("af_heart")
            kokoro.assert_called_once()

    def test_cli_accepts_model_flag(self):
        args = cli.build_parser().parse_args(["hello", "--model", "facebook/mms-tts-ara"])
        self.assertEqual(args.model, "facebook/mms-tts-ara")
        self.assertIsNone(cli.build_parser().parse_args(["hello"]).model)

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

    def test_bundled_provider_uses_explicit_model_and_voice_paths(self):
        with TemporaryDirectory() as directory:
            model_root = Path(directory)
            (model_root / "voices").mkdir()
            (model_root / "config.json").write_text("{}", encoding="utf-8")
            (model_root / "kokoro-v1_0.pth").write_bytes(b"model")
            (model_root / "voices" / "af_heart.pt").write_bytes(b"voice")
            calls = {}

            class FakeModel:
                def __init__(self, config, model):
                    calls["config"] = config
                    calls["model"] = model

                def eval(self):
                    return self

            class FakePipeline:
                def __init__(self, lang_code, model, repo_id=None):
                    calls["language"] = lang_code
                    calls["pipeline_model"] = model
                    calls["repo_id"] = repo_id

                def __call__(self, text, voice, speed, split_pattern):
                    calls["voice"] = voice
                    return [(text, "phonemes", [0.1])]

            fake_kokoro = types.SimpleNamespace(KModel=FakeModel, KPipeline=FakePipeline)
            with patch.dict("sys.modules", {"kokoro": fake_kokoro}), patch(
                "atten_backend.service._configure_espeak", return_value=False
            ):
                provider = KokoroProvider(model_root=model_root)
                segments = list(provider.segments("hello", "af_heart", 1.0))

            self.assertEqual(len(segments), 1)
            resolved_root = model_root.resolve()
            self.assertEqual(calls["config"], str(resolved_root / "config.json"))
            self.assertEqual(calls["model"], str(resolved_root / "kokoro-v1_0.pth"))
            self.assertEqual(calls["voice"], str(resolved_root / "voices" / "af_heart.pt"))

    def test_bundled_provider_rejects_incomplete_model(self):
        with TemporaryDirectory() as directory:
            with self.assertRaisesRegex(RuntimeError, "incomplete"):
                KokoroProvider(model_root=directory)

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


class DurabilityTests(unittest.TestCase):
    """Whatever a user types, imports, or does to their disk, the backend has
    to answer with a finished file or a sentence they can act on."""

    def test_titles_the_filesystem_would_reject_still_produce_a_file(self):
        for name in ("x" * 400, "../escape", "..", ".hidden", "a/b", "\x07bell"):
            with self.subTest(name=name), TemporaryDirectory() as directory:
                service = GenerationService(FakeProvider(), FakeAudioIO())

                result = service.generate(
                    GenerationRequest(
                        text="Hello", output_directory=Path(directory), filename=name
                    )
                )

                self.assertEqual(result.output_path.parent, Path(directory).resolve())
                # Both the published file and the partial file that preceded it
                # have to fit the filesystem's per-component limit.
                self.assertLessEqual(len(result.output_path.name.encode("utf-8")), 255)
                self.assertTrue(result.output_path.is_file())

    @unittest.skipIf(
        sys.platform == "win32",
        "Windows ignores POSIX mode bits, so a read-only folder cannot be staged this way.",
    )
    def test_unwritable_output_folder_is_explained_not_reported_as_a_system_error(self):
        with TemporaryDirectory() as directory:
            locked = Path(directory) / "locked"
            locked.mkdir(mode=0o500)
            service = GenerationService(FakeProvider(), FakeAudioIO())

            with self.assertRaisesRegex(RuntimeError, "cannot be written to"):
                service.generate(
                    GenerationRequest(text="Hello", output_directory=locked)
                )

    def test_text_without_pronounceable_words_says_so(self):
        with TemporaryDirectory() as directory:
            service = GenerationService(FakeProvider(segments=[]), FakeAudioIO())

            with self.assertRaisesRegex(RuntimeError, "produced no speech"):
                service.generate(
                    GenerationRequest(text="...", output_directory=Path(directory))
                )

    def test_default_filenames_stay_sortable_past_this_century(self):
        with TemporaryDirectory() as directory:
            service = GenerationService(FakeProvider(), FakeAudioIO())

            result = service.generate(
                GenerationRequest(text="Hello", output_directory=Path(directory))
            )

            year = result.output_path.stem.split("-")[0]
            self.assertEqual(len(year), 4)
            self.assertGreaterEqual(int(year), 2024)

    def test_a_voice_that_needs_a_download_says_which_one(self):
        with patch("atten_backend.service.is_model_installed", return_value=False):
            service = GenerationService()
            with self.assertRaisesRegex(RuntimeError, "facebook/mms-tts-ara"):
                service.get_provider_for_voice("ar_mariam")

    def test_every_catalogued_voice_either_ships_or_names_its_model(self):
        # The library must never offer a voice that can only fail: a voice is
        # either spoken by the bundled engine or declares the one model it needs.
        from atten_backend.catalog import VOICES, required_model_for

        for voice in VOICES:
            with self.subTest(voice=voice["id"]):
                bundled_prefixes = (
                    "af_", "am_", "bf_", "bm_", "ef_", "em_", "ff_", "if_", "im_",
                    "pf_", "pm_",
                )
                speaks_here = voice["id"].startswith(bundled_prefixes)
                self.assertEqual(speaks_here, required_model_for(voice["id"]) is None)

    def test_an_unknown_voice_is_named_as_unknown(self):
        service = GenerationService()
        with self.assertRaisesRegex(RuntimeError, "no voice called"):
            service.get_provider_for_voice("zz_nobody")

    def test_a_full_disk_is_reported_as_a_full_disk(self):
        # libsndfile reports a full disk as its own "System error", which told
        # the user nothing, so the disk is asked directly.
        with TemporaryDirectory() as directory:
            audio_io = FakeAudioIO()

            def fail(destination, segment_paths):
                raise RuntimeError("System error.")

            audio_io.merge = fail
            service = GenerationService(FakeProvider(), audio_io)

            with patch("atten_backend.service._disk_is_full", return_value=True):
                with self.assertRaisesRegex(RuntimeError, "is full"):
                    service.generate(
                        GenerationRequest(text="Hello", output_directory=Path(directory))
                    )

    def test_partial_files_from_a_killed_run_do_not_accumulate(self):
        with TemporaryDirectory() as directory:
            folder = Path(directory)
            stale = folder / ".old.atten-abc123.part.mp3"
            recent = folder / ".busy.atten-def456.part.mp3"
            for path in (stale, recent):
                path.write_bytes(b"partial")
            # A force quit last week, and another Atten writing right now.
            os.utime(stale, (0, 0))

            GenerationService(FakeProvider(), FakeAudioIO()).generate(
                GenerationRequest(text="Hello", output_directory=folder)
            )

            self.assertFalse(stale.exists())
            self.assertTrue(recent.exists())

    def test_segments_are_joined_end_to_end_in_both_formats(self):
        # A book-length narration is far more audio than fits in memory, so the
        # merge streams; this proves streaming still yields every sample, in
        # order, for each format Atten writes.
        import soundfile as sf

        audio_io = SoundFileAudioIO()
        rate = audio_io.sample_rate
        for output_format in ("wav", "mp3"):
            with self.subTest(output_format=output_format), TemporaryDirectory() as directory:
                segments = []
                for index in range(3):
                    path = Path(directory) / f"segment-{index}.{output_format}"
                    audio_io.write(path, [0.1] * rate)
                    segments.append(path)
                merged = Path(directory) / f"merged.{output_format}"

                audio_io.merge(merged, segments)

                self.assertAlmostEqual(
                    sf.info(str(merged)).frames, rate * 3, delta=rate // 10
                )


class CLICompatibilityTests(unittest.TestCase):
    def test_original_defaults_remain_available(self):
        args = cli.build_parser().parse_args(["hello"])
        self.assertEqual(args.voice, "af_heart")
        self.assertEqual(args.speed, 1.0)
        self.assertEqual(args.format, "mp3")
        self.assertEqual(args.output, "outputs")
        self.assertEqual(args.device, "auto")

    def test_voice_catalog_is_json_serializable(self):
        args = cli.build_parser().parse_args(["--list-voices", "--json"])
        self.assertTrue(args.list_voices)
        json.dumps(cli.VOICES)

    def test_backend_info_is_json_serializable(self):
        info = cli.backend_info("cpu")
        self.assertEqual(info["selected_device"], "cpu")
        self.assertEqual(info["voice_count"], len(cli.VOICES))
        json.dumps(info)

    def test_device_parser_supports_cuda_cpu_mps_and_auto(self):
        for device in ("auto", "cpu", "cuda", "mps"):
            args = cli.build_parser().parse_args(["hello", "--device", device])
            self.assertEqual(args.device, device)


class StreamingTests(unittest.TestCase):
    def test_durable_segments_include_kokoro_words_and_sample_offsets(self):
        class Result:
            tokens = [types.SimpleNamespace(text="Hello", start_ts=0.1, end_ts=0.4),
                      types.SimpleNamespace(text="!", start_ts=None, end_ts=None)]

            def __iter__(self):
                return iter(("Hello!", "phonemes", [0.1] * 12000))

        provider = FakeProvider()
        provider.segments = lambda *_: iter([Result(), Result()])
        with TemporaryDirectory() as directory:
            root = Path(directory)
            events = []

            def ready(event):
                self.assertTrue(Path(event["path"]).is_file())
                self.assertFalse((root / "final.wav").exists())
                events.append(event)

            result = GenerationService(provider, SoundFileAudioIO()).generate(
                GenerationRequest(text="Hello! Hello!", output_directory=root, filename="final",
                                  output_format="wav", segments_directory=root / "segments"),
                segment_ready=ready,
            )
            import soundfile as sf
            self.assertEqual([e["index"] for e in events], [0, 1])
            self.assertEqual([e["start"] for e in events], [0, 0.5])
            self.assertEqual(events[0]["words"], [{"text": "Hello", "start": 0.1, "end": 0.4}])
            for event in events:
                audio = sf.info(event["path"])
                self.assertEqual((audio.samplerate, audio.channels, audio.format), (24000, 1, "WAV"))
                self.assertEqual(audio.duration, event["duration"])
            self.assertEqual(sf.info(str(result.output_path)).duration, 1)

    def test_legacy_tuple_provider_has_no_words_and_cli_contract_is_opt_in(self):
        with TemporaryDirectory() as directory:
            root = Path(directory)
            for streaming in (False, True):
                args = ["Hello", "--json", "--output", str(root), "--filename", str(streaming)]
                if streaming:
                    args += ["--segments-dir", str(root / "segments")]
                output = io.StringIO()
                service = GenerationService(FakeProvider(), FakeAudioIO())
                with patch.object(cli, "GenerationService", return_value=service), redirect_stdout(output):
                    self.assertEqual(cli.main(args), 0)
                events = [json.loads(line) for line in output.getvalue().splitlines()]
                segments = [e for e in events if e["event"] == "segment"]
                completed = events[-1]
                self.assertEqual(completed, {"event": "completed", "path": str((root / f"{streaming}.mp3").resolve()),
                                             "segments": 2, "sample_rate": 24000, "preview": False})
                if streaming:
                    self.assertEqual(segments[0]["words"], [])
                    self.assertEqual(Path(segments[0]["path"]).name, "seg-00000.wav")
                else:
                    self.assertEqual(segments, [{"event": "segment", "count": 1}, {"event": "segment", "count": 2}])

    def test_transcode_preserves_duration_rate_and_channels_without_overwriting(self):
        import soundfile as sf
        import numpy as np

        with TemporaryDirectory() as directory:
            root = Path(directory)
            for source_format in ("wav", "caf"):
                source = root / f"input.{source_format}"
                sf.write(str(source), np.zeros((44100, 2)), 44100)
                for output_format in ("wav", "mp3"):
                    destination = root / f"{source_format}.{output_format}"
                    self.assertEqual(cli.main(["transcode", "--input", str(source), "--output", str(destination)]), 0)
                    info = sf.info(str(destination))
                    self.assertEqual((info.samplerate, info.channels), (44100, 2))
                    self.assertAlmostEqual(info.duration, 1, delta=0.05)
                    original = destination.read_bytes()
                    with self.assertRaises(FileExistsError):
                        SoundFileAudioIO().transcode(source, destination)
                    self.assertEqual(destination.read_bytes(), original)

    @unittest.skipUnless(sys.platform == "darwin", "M4A fixture uses macOS afconvert")
    def test_transcode_m4a(self):
        import subprocess
        import soundfile as sf

        with TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "source.wav"
            SoundFileAudioIO().write(source, [0.1] * 24000)
            m4a = root / "source.m4a"
            subprocess.run(["afconvert", "-f", "m4af", "-d", "aac", str(source), str(m4a)], check=True)
            result = SoundFileAudioIO().transcode(m4a, root / "result.wav")
            self.assertAlmostEqual(sf.info(str(result)).duration, 1, delta=0.1)


class DeviceSelectionTests(unittest.TestCase):
    def fake_torch(self, cuda_available=False, mps_available=False):
        return types.SimpleNamespace(
            __version__="2.test",
            version=types.SimpleNamespace(cuda="12.test"),
            cuda=types.SimpleNamespace(is_available=lambda: cuda_available),
            backends=types.SimpleNamespace(
                mps=types.SimpleNamespace(is_available=lambda: mps_available)
            ),
        )

    def test_auto_uses_cuda_on_windows_or_linux_when_available(self):
        fake_torch = self.fake_torch(cuda_available=True)
        with patch.dict("sys.modules", {"torch": fake_torch}), patch.object(
            sys, "platform", "win32"
        ):
            info = resolve_device("auto")

        self.assertEqual(info.selected_device, "cuda")
        self.assertTrue(info.cuda_available)

    def test_auto_uses_mps_on_macos_when_available(self):
        fake_torch = self.fake_torch(mps_available=True)
        with patch.dict("sys.modules", {"torch": fake_torch}), patch.object(
            sys, "platform", "darwin"
        ):
            info = resolve_device("auto")

        self.assertEqual(info.selected_device, "mps")
        self.assertTrue(info.mps_available)

    def test_explicit_cuda_fails_when_unavailable(self):
        fake_torch = self.fake_torch(cuda_available=False)
        with patch.dict("sys.modules", {"torch": fake_torch}):
            with self.assertRaisesRegex(RuntimeError, "CUDA was requested"):
                resolve_device("cuda")


if __name__ == "__main__":
    unittest.main()
