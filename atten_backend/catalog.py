"""The Kokoro voices exposed by Atten.

The catalog mirrors the voices documented by the original project. Keeping it
in code gives the native application a stable, machine-readable capability
contract without pretending the backend supports settings it does not.
"""

VOICES = [
    {"id": "af_heart", "name": "Heart", "language": "English (US)", "language_code": "a", "gender": "Female", "traits": ["warm", "expressive"], "quality": "A"},
    {"id": "af_bella", "name": "Bella", "language": "English (US)", "language_code": "a", "gender": "Female", "traits": ["bright", "confident"], "quality": "A-"},
    {"id": "af_nicole", "name": "Nicole", "language": "English (US)", "language_code": "a", "gender": "Female", "traits": ["calm", "studio"], "quality": "B-"},
    {"id": "af_aoede", "name": "Aoede", "language": "English (US)", "language_code": "a", "gender": "Female", "traits": ["clear"], "quality": "C+"},
    {"id": "af_kore", "name": "Kore", "language": "English (US)", "language_code": "a", "gender": "Female", "traits": ["clear"], "quality": "C+"},
    {"id": "af_sarah", "name": "Sarah", "language": "English (US)", "language_code": "a", "gender": "Female", "traits": ["natural"], "quality": "C+"},
    {"id": "af_alloy", "name": "Alloy", "language": "English (US)", "language_code": "a", "gender": "Female", "traits": ["balanced"], "quality": "C"},
    {"id": "af_nova", "name": "Nova", "language": "English (US)", "language_code": "a", "gender": "Female", "traits": ["bright"], "quality": "C"},
    {"id": "af_sky", "name": "Sky", "language": "English (US)", "language_code": "a", "gender": "Female", "traits": ["light"], "quality": "C-"},
    {"id": "af_river", "name": "River", "language": "English (US)", "language_code": "a", "gender": "Female", "traits": ["soft"], "quality": "D"},
    {"id": "af_jessica", "name": "Jessica", "language": "English (US)", "language_code": "a", "gender": "Female", "traits": ["conversational"], "quality": "D"},
    {"id": "am_fenrir", "name": "Fenrir", "language": "English (US)", "language_code": "a", "gender": "Male", "traits": ["grounded"], "quality": "C+"},
    {"id": "am_michael", "name": "Michael", "language": "English (US)", "language_code": "a", "gender": "Male", "traits": ["natural"], "quality": "C+"},
    {"id": "am_puck", "name": "Puck", "language": "English (US)", "language_code": "a", "gender": "Male", "traits": ["playful"], "quality": "C+"},
    {"id": "am_echo", "name": "Echo", "language": "English (US)", "language_code": "a", "gender": "Male", "traits": ["steady"], "quality": "D"},
    {"id": "am_eric", "name": "Eric", "language": "English (US)", "language_code": "a", "gender": "Male", "traits": ["direct"], "quality": "D"},
    {"id": "am_liam", "name": "Liam", "language": "English (US)", "language_code": "a", "gender": "Male", "traits": ["soft"], "quality": "D"},
    {"id": "am_onyx", "name": "Onyx", "language": "English (US)", "language_code": "a", "gender": "Male", "traits": ["deep"], "quality": "D"},
    {"id": "am_santa", "name": "Santa", "language": "English (US)", "language_code": "a", "gender": "Male", "traits": ["character"], "quality": "D-"},
    {"id": "am_adam", "name": "Adam", "language": "English (US)", "language_code": "a", "gender": "Male", "traits": ["plainspoken"], "quality": "F+"},
    {"id": "bf_emma", "name": "Emma", "language": "English (UK)", "language_code": "b", "gender": "Female", "traits": ["warm", "British"], "quality": "B-"},
    {"id": "bf_isabella", "name": "Isabella", "language": "English (UK)", "language_code": "b", "gender": "Female", "traits": ["bright", "British"], "quality": "C"},
    {"id": "bf_alice", "name": "Alice", "language": "English (UK)", "language_code": "b", "gender": "Female", "traits": ["gentle", "British"], "quality": "D"},
    {"id": "bf_lily", "name": "Lily", "language": "English (UK)", "language_code": "b", "gender": "Female", "traits": ["light", "British"], "quality": "D"},
    {"id": "bm_fable", "name": "Fable", "language": "English (UK)", "language_code": "b", "gender": "Male", "traits": ["storytelling", "British"], "quality": "C"},
    {"id": "bm_george", "name": "George", "language": "English (UK)", "language_code": "b", "gender": "Male", "traits": ["steady", "British"], "quality": "C"},
    {"id": "bm_lewis", "name": "Lewis", "language": "English (UK)", "language_code": "b", "gender": "Male", "traits": ["conversational", "British"], "quality": "D+"},
    {"id": "bm_daniel", "name": "Daniel", "language": "English (UK)", "language_code": "b", "gender": "Male", "traits": ["direct", "British"], "quality": "D"},
    {"id": "ef_dora", "name": "Dora", "language": "Spanish", "language_code": "e", "gender": "Female", "traits": ["Spanish"], "quality": "Unrated"},
    {"id": "em_alex", "name": "Alex", "language": "Spanish", "language_code": "e", "gender": "Male", "traits": ["Spanish"], "quality": "Unrated"},
    {"id": "em_santa", "name": "Santa", "language": "Spanish", "language_code": "e", "gender": "Male", "traits": ["character", "Spanish"], "quality": "Unrated"},
    {"id": "ff_siwis", "name": "Siwis", "language": "French", "language_code": "f", "gender": "Female", "traits": ["clear", "French"], "quality": "B-"},
    {"id": "if_sara", "name": "Sara", "language": "Italian", "language_code": "i", "gender": "Female", "traits": ["warm", "Italian"], "quality": "C"},
    {"id": "im_nicola", "name": "Nicola", "language": "Italian", "language_code": "i", "gender": "Male", "traits": ["steady", "Italian"], "quality": "C"},
    {"id": "pf_dora", "name": "Dora", "language": "Portuguese (Brazil)", "language_code": "p", "gender": "Female", "traits": ["Brazilian"], "quality": "Unrated"},
    {"id": "pm_alex", "name": "Alex", "language": "Portuguese (Brazil)", "language_code": "p", "gender": "Male", "traits": ["Brazilian"], "quality": "Unrated"},
    {"id": "pm_santa", "name": "Santa", "language": "Portuguese (Brazil)", "language_code": "p", "gender": "Male", "traits": ["character", "Brazilian"], "quality": "Unrated"},
]


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
