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
