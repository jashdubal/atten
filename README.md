# Atten

Atten is a native macOS voice studio for local text-to-speech. It pairs a
colorful, minimal SwiftUI interface with the existing Kokoro backend, so text
and generated audio stay on your Mac.

## What Atten includes

- **Studio** — write, paste, import, or drop text; choose and preview a voice;
  adjust supported speed and format settings; generate, review, and export.
- **Playground** — audition any voice, speed, format, and Metal setting with a
  disposable sample that never enters project history.
- **Voices** — search the real Kokoro catalog by language or traits, preview
  voices, and save favorites.
- **Projects** — revisit generations, play them, duplicate their settings,
  regenerate, export, delete project metadata, or explicitly delete its audio.
- **Exports** — preview, rename, save a copy, and reveal audio in Finder.
- **Settings** — inspect backend readiness and configure audio, storage,
  appearance, Metal fallback, and keyboard workflows.

The original `bin/tts` and `bin/play` commands remain compatible.

## Requirements

- macOS 14 or newer
- Xcode 16 or newer with Swift 6
- Python 3.9+ and `uv`
- `espeak-ng` for Kokoro language fallback

## Setup and launch

Install the existing local backend dependencies:

```bash
bin/setup-macos
```

Launch Atten directly from the repository:

```bash
bin/atten
```

The first synthesis can download roughly 330 MB of Kokoro model weights.

## Build a macOS app bundle

```bash
scripts/build-app
open .build/Atten.app
```

The script creates an ad-hoc signed development app at `.build/Atten.app`.
Keep the repository available because this development build runs `cli.py`
through the repository's `uv` environment. You can explicitly point an app at
the backend with `ATTEN_BACKEND_ROOT=/path/to/offline-tts`.

For Swift-only development:

```bash
swift build
swift run Atten
```

## Compatible CLI

Existing automation continues to work:

```bash
bin/tts "Living the dream"
bin/tts -f README.md -v bf_emma -s 1.1 --format wav --play
bin/tts "Hello" --filename greeting --silent
bin/play --latest
```

New machine-readable capabilities are additive:

```bash
bin/tts --list-voices --json
bin/tts "Hello" --json
```

Run `bin/tts --help` for the complete compatible option list and see
[VOICES.md](VOICES.md) for the catalog.

## Data and privacy

- Kokoro synthesis runs locally; it needs no account or API credential.
- Project metadata is atomically stored in `~/Library/Application Support/Atten`.
- New audio defaults to the `Exports` folder beneath that directory.
- Existing files in the repository's `outputs/` folder are discovered without
  being renamed or moved.
- Provider credentials, if a future provider needs them, use macOS Keychain.

## Keyboard shortcuts

| Action | Shortcut |
| --- | --- |
| New Studio draft | Command-N |
| Import text | Command-O |
| Open Studio | Command-1 |
| Open Playground | Command-2 |
| Generate speech | Command-Return |
| Create temporary sample | Option-Command-Return |
| Play or pause | Option-Space |
| Cancel generation | Escape |
| Export current audio | Shift-Command-E |

Atten supports keyboard navigation, VoiceOver labels, light/dark mode, and the
macOS Reduce Motion preference.

## Tests

```bash
swift test
python3 -m unittest discover -s tests -v
```

Run a production build with:

```bash
swift build -c release
```

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for boundaries, compatibility
decisions, and current distribution constraints.
