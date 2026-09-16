"""Arabic and Multilingual synthesis provider for Atten using Transformers & VITS."""

from pathlib import Path
import re
import numpy as np
from typing import Dict, Generator, Tuple
import torch

from .downloader import get_models_directory, is_xtts_installed
from .device import resolve_device

MMS_LANGUAGE_MAP = {
    "ar": "facebook/mms-tts-ara",
    "de": "facebook/mms-tts-deu",
    "ru": "facebook/mms-tts-rus",
    "tr": "facebook/mms-tts-tur",
    "nl": "facebook/mms-tts-nld",
    "pl": "facebook/mms-tts-pol",
    "hi": "facebook/mms-tts-hin",
    "es": "facebook/mms-tts-spa",
    "fr": "facebook/mms-tts-fra",
    "it": "facebook/mms-tts-ita",
    "pt": "facebook/mms-tts-por",
    "ja": "facebook/mms-tts-jpn",
    "zh": "facebook/mms-tts-cmn",
    "en": "facebook/mms-tts-eng",
    "ko": "facebook/mms-tts-kor",
    "vi": "facebook/mms-tts-vie",
    "id": "facebook/mms-tts-ind",
    "uk": "facebook/mms-tts-ukr",
    "el": "facebook/mms-tts-ell",
    "he": "facebook/mms-tts-heb",
    "cs": "facebook/mms-tts-ces",
    "ro": "facebook/mms-tts-ron",
    "hu": "facebook/mms-tts-hun",
    "da": "facebook/mms-tts-dan",
    "no": "facebook/mms-tts-nor",
    "fi": "facebook/mms-tts-fin",
    "sv": "facebook/mms-tts-swe",
    "th": "facebook/mms-tts-tha",
    "ta": "facebook/mms-tts-tam",
    "tel": "facebook/mms-tts-tel",
    "ur": "facebook/mms-tts-urd",
    "bn": "facebook/mms-tts-ben",
    "fa": "facebook/mms-tts-pes",
    "sw": "facebook/mms-tts-swh",
    "ca": "facebook/mms-tts-cat",
}


def _resample_and_speed(
    audio: np.ndarray,
    orig_sr: int = 16000,
    target_sr: int = 24000,
    speed: float = 1.0,
    pitch_factor: float = 1.0,
) -> np.ndarray:
    """Resamples audio from orig_sr to target_sr and applies speed scaling and persona pitch adjustment."""
    if speed <= 0:
        speed = 1.0
    if pitch_factor <= 0:
        pitch_factor = 1.0
    target_length = max(1, int(len(audio) * (target_sr / orig_sr) / speed))
    x_old = np.linspace(0, 1, len(audio), endpoint=False)
    x_new = np.linspace(0, 1, target_length, endpoint=False)
    resampled = np.interp(x_new, x_old, audio).astype(np.float32)

    if abs(pitch_factor - 1.0) > 0.01:
        pitch_len = max(1, int(len(resampled) / pitch_factor))
        x_p_old = np.linspace(0, 1, len(resampled), endpoint=False)
        x_p_new = np.linspace(0, 1, pitch_len, endpoint=False)
        pitched = np.interp(x_p_new, x_p_old, resampled).astype(np.float32)
        x_final = np.linspace(0, 1, len(resampled), endpoint=False)
        x_s = np.linspace(0, 1, len(pitched), endpoint=False)
        resampled = np.interp(x_final, x_s, pitched).astype(np.float32)

    return resampled


class XTTSv2Provider:
    """TTS provider for Arabic (العربية) and Multilingual neural synthesis."""

    def __init__(self, model_root: Path = None, device_mode: str = "auto", hf_model_id: str = None):
        self.device_info = resolve_device(device_mode)
        self._model_dir = model_root or (get_models_directory() / "XTTS-v2")
        self._models: Dict[str, Tuple[object, object]] = {}
        self._coqui_model = None
        self._coqui_config = None
        self._hf_model_id = hf_model_id
        if hf_model_id and "xtts" in hf_model_id.lower():
            self._hf_model_id = None

    def _local_directory_for(self, model_id: str) -> Path:
        """Returns the on-disk directory the downloader uses for a Hugging Face repo."""
        return get_models_directory() / model_id.replace("/", "--")

    def _ensure_loaded(self, language: str = "ar"):
        # An explicitly requested Hugging Face repo wins over language guessing.
        if self._hf_model_id:
            if self._hf_model_id in self._models:
                return
            from transformers import AutoTokenizer, VitsModel

            local_dir = self._local_directory_for(self._hf_model_id)
            load_path = str(local_dir) if (local_dir / "config.json").is_file() else self._hf_model_id
            tokenizer = AutoTokenizer.from_pretrained(load_path)
            model = VitsModel.from_pretrained(load_path)
            if hasattr(model, "to"):
                model.to(self.device_info.selected_device)
            model.eval()
            self._models[self._hf_model_id] = (tokenizer, model)
            return

        # If Coqui model already loaded
        if self._coqui_model is not None:
            return

        # Check if Coqui TTS library is installed with full weights
        if is_xtts_installed():
            try:
                from TTS.tts.configs.xtts_config import XttsConfig
                from TTS.tts.models.xtts import Xtts

                config_path = self._model_dir / "config.json"
                vocab_path = self._model_dir / "vocab.json"
                model_path = self._model_dir / "model.pth"
                speakers_path = self._model_dir / "speakers_xtts.pth"

                config = XttsConfig()
                config.load_json(str(config_path))
                self._coqui_model = Xtts.init_from_config(config)
                self._coqui_model.load_checkpoint(
                    config,
                    checkpoint_path=str(model_path),
                    vocab_path=str(vocab_path),
                    speaker_file_path=str(speakers_path) if speakers_path.exists() else None,
                    eval=True,
                    use_deepspeed=False,
                )
                if hasattr(self._coqui_model, "to"):
                    self._coqui_model.to(self.device_info.selected_device)
                self._coqui_config = config
                return
            except Exception:
                pass

        # Robust built-in VITS / MMS-TTS neural model
        if language in self._models:
            return

        from transformers import AutoTokenizer, VitsModel

        model_id = MMS_LANGUAGE_MAP.get(language, f"facebook/mms-tts-{language}")
        models_dir = get_models_directory()
        local_dir = models_dir / model_id.replace("/", "--")
        load_path = str(local_dir) if (local_dir / "config.json").is_file() else model_id

        try:
            tokenizer = AutoTokenizer.from_pretrained(load_path)
            model = VitsModel.from_pretrained(load_path)
        except Exception:
            # Fallback to Arabic if requested model not found
            fallback_id = "facebook/mms-tts-ara"
            fallback_dir = models_dir / fallback_id.replace("/", "--")
            fallback_path = str(fallback_dir) if (fallback_dir / "config.json").is_file() else fallback_id
            tokenizer = AutoTokenizer.from_pretrained(fallback_path)
            model = VitsModel.from_pretrained(fallback_path)

        if hasattr(model, "to"):
            model.to(self.device_info.selected_device)
        model.eval()
        self._models[language] = (tokenizer, model)

    def segments(
        self, text: str, voice: str, speed: float
    ) -> Generator[Tuple[str, str, np.ndarray], None, None]:
        from .catalog import voice_for_id
        meta = voice_for_id(voice)
        language = meta.get("language_code", "ar")
        if language in ("a", "b", "e", "f", "i", "p", "j", "z", "h"):
            language = "en"
        elif len(language) > 2:
            rev_map = {v.split("-")[-1]: k for k, v in MMS_LANGUAGE_MAP.items()}
            language = rev_map.get(language, "ar")

        if language not in MMS_LANGUAGE_MAP and "_" in voice:
            p = voice.split("_")[0]
            if p in MMS_LANGUAGE_MAP:
                language = p

        self._ensure_loaded(language=language)
        if self._hf_model_id:
            language = self._hf_model_id

        if self._coqui_model is not None:
            lines = [line.strip() for line in text.split("\n") if line.strip()]
            for line in lines:
                outputs = self._coqui_model.synthesize(
                    line,
                    self._coqui_config,
                    speaker_name=voice,
                    language=language,
                    speed=speed,
                )
                audio = outputs["wav"]
                if isinstance(audio, list):
                    audio = np.array(audio, dtype=np.float32)
                yield (line, line, audio)
            return

        # Voice persona pitch adjustment for different readers
        vid = voice.lower()
        gender = meta.get("gender", "").lower()
        pitch = 1.0
        if any(m in vid for m in ("omar", "zayd", "dmitry", "thorsten", "ahmet", "ruben", "jan")) or gender == "male":
            pitch = 0.92
        elif any(f in vid for f in ("layla", "mariam", "eva", "elena", "elif", "fleur", "maja")) or gender == "female":
            pitch = 1.08

        # MMS VITS synthesis
        tokenizer, model = self._models.get(language, next(iter(self._models.values())))
        chunks = [
            chunk.strip()
            for chunk in re.split(r"[\n\r]+|[.!?؟؛]+", text)
            if chunk.strip()
        ]
        if not chunks:
            chunks = [text.strip()]

        for chunk in chunks:
            if not chunk:
                continue
            inputs = tokenizer(chunk, return_tensors="pt")
            if "input_ids" not in inputs or inputs["input_ids"] is None or inputs["input_ids"].numel() == 0:
                continue

            input_ids = inputs["input_ids"].long()
            if hasattr(model, "device"):
                input_ids = input_ids.to(model.device)

            model_inputs = {"input_ids": input_ids}
            if "attention_mask" in inputs and inputs["attention_mask"] is not None and inputs["attention_mask"].numel() > 0:
                model_inputs["attention_mask"] = inputs["attention_mask"].long().to(input_ids.device)

            with torch.no_grad():
                output = model(**model_inputs).waveform

            raw_audio = output.squeeze().cpu().numpy()
            if raw_audio.ndim == 0 or len(raw_audio) == 0:
                continue
            sr = getattr(model.config, "sampling_rate", 16000)
            resampled_audio = _resample_and_speed(
                raw_audio, orig_sr=sr, target_sr=24000, speed=speed, pitch_factor=pitch
            )
            yield (chunk, chunk, resampled_audio)
