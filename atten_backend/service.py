"""Provider-independent generation orchestration for Atten."""

from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
import shutil
import subprocess
from tempfile import TemporaryDirectory
from typing import Callable, Optional
import errno
import os
import time
import uuid

from .catalog import is_known_voice, required_model_for, voice_for_id
from .device import resolve_device
from .word_timings import estimate_word_timings


def _configure_espeak():
    """Point phonemizer at the bundled eSpeak library and data."""
    import espeakng_loader
    from phonemizer.backend.espeak.wrapper import EspeakWrapper

    library = Path(espeakng_loader.get_library_path())
    data = Path(espeakng_loader.get_data_path())
    temporary_assets = None

    # eSpeak 1.52 silently falls back to its compiled-in data directory when
    # its runtime resource path is long. This is common in CI/build folders,
    # so stage only these small assets under the system's short temp path.
    if max(len(str(library)), len(str(data))) > 150:
        temporary_assets = TemporaryDirectory(prefix="atten-espeak-")
        root = Path(temporary_assets.name)
        staged_library = root / library.name
        staged_data = root / data.name
        shutil.copy2(library, staged_library)
        shutil.copytree(data, staged_data)
        library, data = staged_library, staged_data

    EspeakWrapper.set_library(str(library))
    EspeakWrapper.set_data_path(str(data))
    return temporary_assets


def _disk_is_full(directory, margin=8 * 1024 * 1024):
    """Whether the volume has so little room left that a failed write is best
    explained as a full disk."""
    try:
        return shutil.disk_usage(directory).free < margin
    except OSError:
        return False


def _full_disk_error(error, directory):
    """A plain "the disk is full" for a write that failed because it is, or
    None. libsndfile reports a full disk as its own "System error", so the
    disk itself is asked rather than the message read."""
    if getattr(error, "errno", None) == errno.ENOSPC or _disk_is_full(directory):
        return RuntimeError(
            f"The disk holding '{directory}' is full, so the audio "
            "could not be saved. Free some space or choose another folder."
        )
    return None


def _remove_abandoned_partials(directory, older_than_seconds=24 * 60 * 60):
    """Clears partial files left by a run that was killed before it finished.

    A generation writes to a hidden file and renames it into place, so a crash
    or a force quit leaves that hidden file behind. Over years of use those
    would pile up unseen in the user's export folder. Only files older than a
    day are touched, so a second Atten generating into the same folder right
    now is never disturbed.
    """
    cutoff = time.time() - older_than_seconds
    try:
        candidates = list(directory.glob(".*.atten-*.part.*"))
    except OSError:
        return
    for path in candidates:
        try:
            if path.is_file() and path.stat().st_mtime < cutoff:
                path.unlink()
        except OSError:
            continue


def safe_filename(name, reserved=0):
    """Reduces a requested name to one the filesystem will actually accept.

    Titles arrive here as whatever the user typed or imported, so they can
    carry path separators, control characters, leading dots, or hundreds of
    characters. `reserved` is the space the caller still needs for extensions
    and suffixes; the budget is counted in bytes because a title in a
    non-Latin script costs several bytes per character.
    """
    cleaned = "".join(
        "-" if character in '/\\:*?"<>|' or ord(character) < 32 else character
        for character in str(name)
    ).strip()
    cleaned = cleaned.lstrip(".").strip() or "atten-audio"

    budget = max(1, 255 - reserved)
    encoded = cleaned.encode("utf-8")
    if len(encoded) > budget:
        cleaned = encoded[:budget].decode("utf-8", "ignore").rstrip() or "atten-audio"
    return cleaned


# How a pause length changes the silence that ends each segment. Normal is the
# voice's own pause, so a request that names no pause sounds as it always has.
PAUSE_LENGTHS = ("short", "normal", "long")
LONG_PAUSE_SECONDS = 0.6
SHORT_PAUSE_SECONDS = 0.05
SILENCE_THRESHOLD = 0.01


def apply_pause(audio, pause, sample_rate):
    """Returns a segment's audio with its closing silence lengthened or cut.

    Only the end of the segment changes, so word times within it still hold
    and the segments after it simply start later or sooner.
    """
    if pause is None or pause == "normal":
        return audio
    import numpy as np

    samples = np.asarray(audio, dtype=np.float32).reshape(-1)
    if pause == "long":
        silence = np.zeros(int(round(LONG_PAUSE_SECONDS * sample_rate)), dtype=np.float32)
        return np.concatenate([samples, silence])
    loud = np.flatnonzero(np.abs(samples) > SILENCE_THRESHOLD)
    end = (loud[-1] + 1 if loud.size else 0) + int(round(SHORT_PAUSE_SECONDS * sample_rate))
    return samples[:end]


@dataclass(frozen=True)
class GenerationRequest:
    text: str
    voice: str = "af_heart"
    speed: float = 1.0
    output_format: str = "mp3"
    output_directory: Path = Path("outputs")
    filename: Optional[str] = None
    segments_directory: Optional[Path] = None
    pause: Optional[str] = None


@dataclass(frozen=True)
class GenerationResult:
    output_path: Path
    segment_count: int
    sample_rate: int


class KokoroProvider:
    """Lazily creates one Kokoro pipeline per requested language."""

    def __init__(self, model_root=None, device_mode="auto"):
        self._pipelines = {}
        self._espeak_assets = None
        configured_root = model_root or os.environ.get("ATTEN_MODEL_ROOT")
        self._model_root = Path(configured_root).resolve() if configured_root else None
        self._model = None
        self.device_info = resolve_device(device_mode)
        if self._model_root:
            required = [
                self._model_root / "config.json",
                self._model_root / "kokoro-v1_0.pth",
                self._model_root / "voices",
            ]
            missing = [str(path) for path in required if not path.exists()]
            if missing:
                raise RuntimeError(
                    "Bundled Kokoro model is incomplete; missing: " + ", ".join(missing)
                )

    def segments(self, text, voice, speed):
        language_code = voice_for_id(voice)["language_code"]
        if language_code not in self._pipelines:
            from kokoro import KModel, KPipeline

            if self._espeak_assets is None:
                self._espeak_assets = _configure_espeak() or False

            if self._model_root:
                if self._model is None:
                    self._model = KModel(
                        config=str(self._model_root / "config.json"),
                        model=str(self._model_root / "kokoro-v1_0.pth"),
                    )
                    if hasattr(self._model, "to"):
                        self._model = self._model.to(self.device_info.selected_device)
                    self._model = self._model.eval()
                self._pipelines[language_code] = KPipeline(
                    lang_code=language_code, model=self._model, repo_id="hexgrad/Kokoro-82M"
                )
            else:
                pipeline = KPipeline(lang_code=language_code, repo_id="hexgrad/Kokoro-82M")
                pipeline_model = getattr(pipeline, "model", None)
                if hasattr(pipeline_model, "to"):
                    pipeline_model.to(self.device_info.selected_device)
                self._pipelines[language_code] = pipeline

        voice_reference = voice
        if self._model_root:
            voice_path = self._model_root / "voices" / f"{voice}.pt"
            if not voice_path.is_file():
                raise RuntimeError(f"Bundled Kokoro voice is missing: {voice}.pt")
            voice_reference = str(voice_path)
        return self._pipelines[language_code](
            text, voice=voice_reference, speed=speed, split_pattern=r"\n+"
        )


class SoundFileAudioIO:
    sample_rate = 24000

    def write(self, path, audio):
        import soundfile as sf

        sf.write(str(path), audio, self.sample_rate)

    def transcode(self, source, destination):
        """Decode locally and stream through the same libsndfile MP3/WAV writer."""
        import soundfile as sf

        source, destination = Path(source), Path(destination)
        if source.suffix.lower() not in {".wav", ".caf", ".m4a"}:
            raise ValueError("Input format must be wav, caf, or m4a.")
        if destination.suffix.lower() not in {".mp3", ".wav"}:
            raise ValueError("Output format must be mp3 or wav.")
        if destination.exists():
            raise FileExistsError(f"File '{destination}' already exists.")
        destination.parent.mkdir(parents=True, exist_ok=True)
        temporary = destination.with_name(
            f".{destination.stem}.atten-{uuid.uuid4().hex}.part{destination.suffix}"
        )
        try:
            with TemporaryDirectory(prefix="atten-transcode-") as directory:
                decoded = source
                if source.suffix.lower() == ".m4a":
                    decoded = Path(directory) / "decoded.wav"
                    if shutil.which("afconvert"):
                        command = ["afconvert", "-f", "WAVE", "-d", "LEI16", str(source), str(decoded)]
                    elif shutil.which("ffmpeg"):
                        command = ["ffmpeg", "-nostdin", "-v", "error", "-i", str(source), str(decoded)]
                    else:
                        raise RuntimeError("M4A decoding requires afconvert or ffmpeg.")
                    subprocess.run(command, check=True, capture_output=True)
                try:
                    with sf.SoundFile(str(decoded)) as audio:
                        with sf.SoundFile(str(temporary), mode="w", samplerate=audio.samplerate,
                                          channels=audio.channels) as output:
                            for block in audio.blocks(blocksize=audio.samplerate * 30, dtype="float32"):
                                output.write(block)
                    os.replace(temporary, destination)
                except Exception as error:
                    full = _full_disk_error(error, destination.parent)
                    if full:
                        raise full from error
                    raise
        finally:
            temporary.unlink(missing_ok=True)
        return destination.resolve()

    def merge(self, destination, segment_paths):
        """Joins segments into one file a block at a time.

        Whole books are a supported input, and an hour of speech is far too
        much to hold in memory at once, so nothing larger than a block is ever
        resident regardless of how long the text is.
        """
        import soundfile as sf

        block_frames = self.sample_rate * 30
        with sf.SoundFile(
            str(destination), mode="w", samplerate=self.sample_rate, channels=1
        ) as output:
            for segment_path in segment_paths:
                with sf.SoundFile(str(segment_path)) as segment:
                    for block in segment.blocks(blocksize=block_frames, dtype="float32"):
                        output.write(block)


from .xtts_provider import XTTSv2Provider
from .downloader import is_model_installed


class GenerationService:
    """Synthesizes segments and atomically publishes one audio file."""

    def __init__(self, provider=None, audio_io=None, device_mode="auto", engine="auto", model_id=None):
        self.device_mode = device_mode
        self.engine = engine
        self.model_id = model_id
        self._explicit_provider = provider
        self._kokoro_provider = None
        self._xtts_provider = None
        self.audio_io = audio_io or SoundFileAudioIO()

    @property
    def provider(self):
        return self._explicit_provider or self.get_provider_for_voice("af_heart")

    def get_provider_for_voice(self, voice: str):
        if self._explicit_provider:
            return self._explicit_provider

        # A voice that names its own model is answered by that model alone.
        # Atten never reaches the network to speak, so a model that is not on
        # disk is a missing download to report, not a request to make.
        required = required_model_for(voice) if self.model_id is None else None
        if required:
            if not is_model_installed(required):
                raise RuntimeError(
                    f"The voice '{voice}' speaks through the {required} model, which is "
                    "not downloaded yet. Open Models, download it once, and this voice "
                    "works offline from then on."
                )
            if self._xtts_provider is None:
                self._xtts_provider = XTTSv2Provider(
                    device_mode=self.device_mode, hf_model_id=required
                )
            return self._xtts_provider

        if self.model_id is None and not is_known_voice(voice):
            raise RuntimeError(
                f"There is no voice called '{voice}'. Run with --list-voices to see "
                "every voice this copy of Atten can speak."
            )

        # Every Japanese, Chinese and Hindi voice declares a model above, so
        # those prefixes are handled there and never reach this list.
        kokoro_prefixes = ("af_", "am_", "bf_", "bm_", "ef_", "em_", "ff_", "if_", "im_", "pf_", "pm_")
        uses_kokoro = self.model_id is None or "kokoro" in self.model_id.lower()
        if self.engine != "xtts-v2" and uses_kokoro and voice.startswith(kokoro_prefixes):
            if self._kokoro_provider is None:
                self._kokoro_provider = KokoroProvider(device_mode=self.device_mode)
            return self._kokoro_provider

        if self._xtts_provider is None:
            self._xtts_provider = XTTSv2Provider(
                device_mode=self.device_mode, hf_model_id=self.model_id
            )
        return self._xtts_provider

    def generate(
        self,
        request: GenerationRequest,
        progress: Optional[Callable[[int], None]] = None,
        segment_ready: Optional[Callable[[dict], None]] = None,
    ) -> GenerationResult:
        text = request.text.strip()
        if not text:
            raise ValueError("Text cannot be empty.")
        if request.speed <= 0:
            raise ValueError("Speed must be greater than zero.")
        if request.output_format not in {"mp3", "wav"}:
            raise ValueError("Output format must be mp3 or wav.")
        if request.pause is not None and request.pause not in PAUSE_LENGTHS:
            raise ValueError("Pause must be short, normal, or long.")

        # The finished file and the hidden partial file that precedes it both
        # have to fit the filesystem's limit on one path component, so the name
        # is budgeted against the longer of the two.
        partial_suffix = f".atten-{uuid.uuid4().hex}.part.{request.output_format}"
        filename = safe_filename(
            request.filename or datetime.now().strftime("%Y-%m-%d-%H-%M-%S"),
            reserved=len(partial_suffix.encode("utf-8")) + 1,
        )
        output_directory = Path(request.output_directory).expanduser()
        try:
            output_directory.mkdir(parents=True, exist_ok=True)
        except OSError as error:
            raise RuntimeError(
                f"The folder '{output_directory}' could not be created: {error.strerror}. "
                "Choose a different folder for generated audio."
            ) from error
        if not os.access(output_directory, os.W_OK):
            raise RuntimeError(
                f"The folder '{output_directory}' cannot be written to. It may be "
                "read-only, or on a disk that is disconnected or full. Choose a "
                "different folder for generated audio."
            )
        output_path = output_directory / f"{filename}.{request.output_format}"
        if output_path.exists():
            raise FileExistsError(f"File '{output_path}' already exists.")

        _remove_abandoned_partials(output_directory)
        temporary_output = output_directory / f".{filename}{partial_suffix}"
        segment_count = 0

        try:
            with TemporaryDirectory(prefix="atten-") as temporary_directory:
                segment_paths = []
                provider = self.get_provider_for_voice(request.voice)
                offset = 0.0
                segments_directory = request.segments_directory
                if segments_directory is not None:
                    segments_directory = Path(segments_directory).expanduser().resolve()
                    segments_directory.mkdir(parents=True, exist_ok=True)
                for index, result in enumerate(provider.segments(text, request.voice, request.speed)):
                    graphemes, _phonemes, audio = result
                    audio = apply_pause(audio, request.pause, self.audio_io.sample_rate)
                    if segments_directory is None:
                        segment_path = Path(temporary_directory) / f"segment-{index}.{request.output_format}"
                    else:
                        segment_path = segments_directory / f"seg-{index:05d}.wav"
                    try:
                        self.audio_io.write(segment_path, audio)
                        if segments_directory is not None:
                            # Close and sync the WAV before announcing that it can be read.
                            with segment_path.open("rb") as segment_file:
                                os.fsync(segment_file.fileno())
                    except Exception as error:
                        # A narration keeps its segments on the library's
                        # disk, which can fill up long before the export does.
                        full = _full_disk_error(error, segment_path.parent)
                        if full:
                            raise full from error
                        raise
                    if segments_directory is not None:
                        duration = len(audio) / self.audio_io.sample_rate
                        words = []
                        for token in getattr(result, "tokens", None) or []:
                            start, end = getattr(token, "start_ts", None), getattr(token, "end_ts", None)
                            if start is not None and end is not None:
                                words.append({"text": token.text, "start": float(start), "end": float(end)})
                        if not words:
                            # A voice that reports no word times has them read from its audio.
                            words = estimate_word_timings(graphemes, audio, self.audio_io.sample_rate)
                        if segment_ready:
                            segment_ready({"index": index, "path": str(segment_path),
                                           "text": graphemes or "", "start": offset,
                                           "duration": duration, "words": words})
                        offset += duration
                    segment_paths.append(segment_path)
                    segment_count += 1
                    if progress:
                        progress(segment_count)

                if not segment_paths:
                    raise RuntimeError(
                        "This text produced no speech. Add words the selected "
                        "voice can pronounce and try again."
                    )

                # Only the writing is translated. A failure anywhere else —
                # a missing model, a provider that crashed — keeps its own
                # message instead of being blamed on the disk.
                try:
                    self.audio_io.merge(temporary_output, segment_paths)
                    os.replace(temporary_output, output_path)
                except Exception as error:
                    full = _full_disk_error(error, output_directory)
                    if full:
                        raise full from error
                    raise
        finally:
            temporary_output.unlink(missing_ok=True)

        return GenerationResult(
            output_path=output_path.resolve(),
            segment_count=segment_count,
            sample_rate=self.audio_io.sample_rate,
        )
