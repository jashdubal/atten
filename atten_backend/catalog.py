"""Shared Kokoro voice catalog used by the CLI and native apps."""

import json
from pathlib import Path
import sys


def _catalog_candidates():
    roots = []
    if getattr(sys, "_MEIPASS", None):
        roots.append(Path(sys._MEIPASS))
    roots.extend(
        [
            Path(__file__).resolve().parents[1],
            Path.cwd(),
        ]
    )
    for root in roots:
        yield root / "resources" / "voices.json"


def load_voices():
    for path in _catalog_candidates():
        if path.is_file():
            with path.open(encoding="utf-8") as stream:
                return json.load(stream)
    raise RuntimeError("Atten voice catalog is missing: resources/voices.json")


VOICES = load_voices()


def required_model_for(voice_id):
    """The Hugging Face model a voice needs, or None when Atten's own engine
    speaks it. Voices in languages the bundled Kokoro model cannot pronounce
    declare the one model that can."""
    return voice_for_id(voice_id).get("requires_model")


def is_known_voice(voice_id):
    return any(voice["id"] == voice_id for voice in VOICES)


def voice_for_id(voice_id):
    """Return catalog metadata for a voice, or a compatible inferred entry."""
    return next(
        (voice for voice in VOICES if voice["id"] == voice_id),
        {
            "id": voice_id,
            "name": voice_id,
            "language": "Unknown",
            "language_code": voice_id[:1] or "a",
            "gender": "Unknown",
            "traits": [],
            "quality": "Unrated",
        },
    )
