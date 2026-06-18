# Atten architecture and migration plan

## Repository audit

The original project is a Python 3.9+ command-line application. `cli.py` owns
argument parsing, Kokoro model setup, synthesis, segment merging, cleanup, and
optional playback. `play.py` provides cross-platform playback. Shell scripts in
`bin/` select `uv` or system Python. Dependency metadata is duplicated across
`pyproject.toml`, `uv.lock`, `pixi.toml`, and `pixi.lock`.

There is one real TTS provider: the local `kokoro` package using
`hexgrad/Kokoro-82M`. The CLI currently initializes an American-English
pipeline (`lang_code='a'`) and exposes voice, speed, MP3/WAV output, MPS
fallback, preview-only playback, source-file input, and custom output paths.
The documented voice catalog includes American and British English, Spanish,
French, Italian, and Brazilian Portuguese, but the fixed pipeline means only
American English is wired correctly today.

Persistence consists only of generated files in `outputs/`; there is no project
metadata, favorites, settings, database, secret, account, network API, or
environment-variable contract. File names are timestamp-based unless supplied.
Existing compatibility surfaces are the `bin/tts` and `bin/play` commands,
their flags, the default `outputs` directory, and the generated audio files.

There was no automated test suite. The two MP3 files currently present under
`outputs/` are untracked user data and are deliberately left untouched.

## Migration approach

Atten adds a native SwiftUI macOS application as a Swift package while retaining
the Python CLI. A small, testable Python service layer will separate provider,
generation, and export behavior from command parsing. A machine-readable CLI
mode will form the process boundary used by Swift without changing existing
human-readable CLI behavior.

The native app is divided into:

- `AttenCore`: models, persistence, backend process client, file export, and
  application state with no SwiftUI dependency where practical.
- `Atten`: SwiftUI application shell, reusable design system, feature views,
  commands, accessibility, and AppKit integrations.
- `AttenCoreTests`: deterministic tests using temporary directories and fake
  backend runners; synthesis model downloads are not required.
- `tests/`: Python unit tests for generation orchestration and CLI compatibility.

Native project records are stored as JSON in Application Support under the new
Atten directory. On first use, the app also discovers existing audio in the
repository's `outputs/` directory, preserving prior CLI output rather than
renaming or moving it. Swift preferences use an Atten suite while reading any
documented legacy keys before writing the new keys.

Kokoro is fully local and requires no credentials. Settings will state this
explicitly. A Keychain-backed credential store is included at the provider
boundary for future providers, but the interface will not present fake API-key
controls for Kokoro.

## Delivery sequence

1. Extract and test the Python backend contract while preserving all CLI flags.
2. Add Atten package metadata, application shell, models, and design tokens.
3. Implement Studio generation, cancellation, progress, playback, and export.
4. Implement the real Kokoro voice library, favorites, projects, and exports.
5. Add settings, Keychain boundary, restoration, menus, shortcuts, drag/drop,
   accessibility, reduced-motion behavior, and light/dark appearance.
6. Verify Python and Swift tests, debug/release builds, documentation, and launch
   workflow after each milestone.

## Constraints

- The Python environment and Kokoro model remain external to the `.app` in this
  repository. A distributable signed app would need an embedded runtime/model or
  an installer; development builds locate the repository backend.
- Kokoro model startup and first-run model download can be slow. The native UI
  must remain responsive and allow cancellation while a child process runs.
- Only controls supported by Kokoro are exposed: voice, language (derived from
  voice), speed, and WAV/MP3 format.
