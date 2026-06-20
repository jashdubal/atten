"""Provider-independent generation orchestration for Atten."""

from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
import shutil
from tempfile import TemporaryDirectory
from typing import Callable, Optional
import os
import uuid

from .catalog import voice_for_id


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


@dataclass(frozen=True)
class GenerationRequest:
    text: str
    voice: str = "af_heart"
    speed: float = 1.0
    output_format: str = "mp3"
    output_directory: Path = Path("outputs")
    filename: Optional[str] = None


@dataclass(frozen=True)
class GenerationResult:
    output_path: Path
    segment_count: int
    sample_rate: int


class KokoroProvider:
    """Lazily creates one Kokoro pipeline per requested language."""

    def __init__(self, model_root=None):
        self._pipelines = {}
        self._espeak_assets = None
        configured_root = model_root or os.environ.get("ATTEN_MODEL_ROOT")
        self._model_root = Path(configured_root).resolve() if configured_root else None
        self._model = None
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
                    ).eval()
                self._pipelines[language_code] = KPipeline(
                    lang_code=language_code, model=self._model
                )
            else:
                self._pipelines[language_code] = KPipeline(lang_code=language_code)

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

    def read(self, path):
        import soundfile as sf

        audio, _sample_rate = sf.read(str(path))
        return audio


class GenerationService:
    """Synthesizes segments and atomically publishes one audio file."""

    def __init__(self, provider=None, audio_io=None):
        self.provider = provider or KokoroProvider()
        self.audio_io = audio_io or SoundFileAudioIO()

    def generate(
        self,
        request: GenerationRequest,
        progress: Optional[Callable[[int], None]] = None,
    ) -> GenerationResult:
        text = request.text.strip()
        if not text:
            raise ValueError("Text cannot be empty.")
        if request.speed <= 0:
            raise ValueError("Speed must be greater than zero.")
        if request.output_format not in {"mp3", "wav"}:
            raise ValueError("Output format must be mp3 or wav.")

        output_directory = Path(request.output_directory).expanduser()
        output_directory.mkdir(parents=True, exist_ok=True)
        filename = request.filename or datetime.now().strftime("%y-%m-%d-%H-%M-%S")
        output_path = output_directory / f"{filename}.{request.output_format}"
        if output_path.exists():
            raise FileExistsError(f"File '{output_path}' already exists.")

        temporary_output = output_directory / (
            f".{filename}.atten-{uuid.uuid4().hex}.part.{request.output_format}"
        )
        segment_count = 0

        try:
            with TemporaryDirectory(prefix="atten-") as temporary_directory:
                segment_paths = []
                for index, (_graphemes, _phonemes, audio) in enumerate(
                    self.provider.segments(text, request.voice, request.speed)
                ):
                    segment_path = Path(temporary_directory) / (
                        f"segment-{index}.{request.output_format}"
                    )
                    self.audio_io.write(segment_path, audio)
                    segment_paths.append(segment_path)
                    segment_count += 1
                    if progress:
                        progress(segment_count)

                if not segment_paths:
                    raise RuntimeError("The TTS provider returned no audio.")

                merged_audio = []
                for segment_path in segment_paths:
                    merged_audio.extend(self.audio_io.read(segment_path))
                self.audio_io.write(temporary_output, merged_audio)
                os.replace(temporary_output, output_path)
        finally:
            temporary_output.unlink(missing_ok=True)

        return GenerationResult(
            output_path=output_path.resolve(),
            segment_count=segment_count,
            sample_rate=self.audio_io.sample_rate,
        )
