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

## Distribution

Release builds embed a PyInstaller one-directory Python 3.12 helper and the
pinned Kokoro model beneath the app bundle. The Swift client resolves the
bundled installation before development overrides, launches it directly, and
forces an offline environment. Repository builds continue to locate `cli.py`
through `ATTEN_BACKEND_ROOT`, the current directory, or the development app's
ancestor directories.

## Library: PDF and EPUB narration

Books are read into chapters entirely in Swift. PDFs go through PDFKit, whose
outline supplies the chapter breaks and whose pages supply the text; a PDF with
no outline is sliced into ten-page sections so a chapter stays a manageable unit
of work. EPUBs are unpacked with `ditto`, read through `META-INF/container.xml`
and the OPF spine, and flattened from XHTML by `XMLParser`, falling back to tag
stripping for the books that are not well-formed XML. Nothing was added to the
Python backend or the bundled helper, so the DMG does not grow and the process
contract is unchanged.

A whole book is far too much text for one call to the speech engine, so the
Library narrates one chapter per call and saves after each. Progress is real,
cancelling costs only the chapter in flight, and a second run resumes where the
first stopped. The chapters stay separate files: `AppModel.playSequence` plays
them back to back, which gives continuous listening without re-encoding a
fourteen-hour audiobook into a third container format. Changing a book's voice,
speed, or format discards its narration rather than leaving one book read in two
voices, and the user is told what that costs before it happens.

Atten's own copy of each book lives beside the project history in Application
Support, so the shelf keeps working after the original file is moved or deleted.
`books.json` salvages per-record like `projects.json`, and a lost shelf costs
nothing that re-importing cannot rebuild.

Kokoro model startup can be slow. The native UI remains responsive and allows
cancellation while the child process runs.
- Only controls supported by Kokoro are exposed: voice, language (derived from
  voice), speed, and WAV/MP3 format.

## Themes

Seven palettes ship, spanning a plain white page and a green-on-black console,
because the same app is used by people who want no colour at all and people who
want their tools to look like something. Each theme defines a full light *and*
dark palette, so picking a theme and picking light or dark stay two separate
decisions that combine.

The mechanism is deliberately invisible to feature code. `AttenColor` exposes
semantic roles — `surface`, `textSecondary`, `readerHighlight` — and resolves
each through `ThemeStore.shared`, an `@Observable` holder of the current
`AttenPalette`. Reading one of those roles inside a view body registers as an
observed access, so changing the theme repaints every view that draws with it
without any view, modifier, or button style knowing that themes exist. The rule
for new UI is simply to name a role rather than a colour; it is themed for free.

AppKit is the exception, since an `NSView` keeps whatever colour it was last
handed. `AlignedTextEditor` and the reader's `PDFView` therefore take the
current theme as a property so SwiftUI drives an update, and re-apply colours
only when it actually changed — recolouring an `NSTextView` re-attributes the
whole document and must not happen per keystroke.

`ThemeTests` holds every palette to WCAG contrast minimums in both appearances:
7:1 for body text, 4.5:1 for secondary text and button labels, and the 3:1 that
WCAG sets for interface components against accent and status colours. A new
theme that is pretty but unreadable fails the suite.
