# Atten architecture


## Current Mac architecture — September 2026

The two primary workspaces are Library and Create. Library owns import, reading,
whole-book preparation, and return-to-listening. Create contains drafts, projects,
exports, and contextual voice previews. Model management lives in Settings.
Legacy navigation destinations map to these workspaces. Compact and expanded
players share one playback controller.

`SynthesisCoordinator` grants one UUID-scoped lease across book preparation,
Create, and voice previews. Cancellation retains the lease until the underlying
task exits. Reading and existing audio playback remain available during synthesis.

`BookRecord` persists unprepared, preparing, interrupted, failed, finalizing, and
ready narration states with backward-compatible defaults. On decode, unfinished
work becomes interrupted; loading never starts generation. Readiness requires a
real audio file and a contiguous, valid chapter timeline. Library loading checks
audio headers and durations off the main actor. Existing chapter recordings can
be finalized explicitly without regenerating valid checkpoints.

`BookshelfModel` serializes metadata writes and checkpoints each completed
chapter. `BookAudioAssembler` streams through bounded 65,536-frame buffers into
a unique CAF file. Metadata is committed before chapter files are removed.
Failed assembly or persistence preserves recoverable work. Replacement narration
retains the previous playable file and timeline until the replacement commits;
a loaded old recording is retained until playback releases it.

Listening position is independent of reading position. Selection and position
restore paused. Preparation and Create completion never start playback. Book
export uses a temporary M4A file and only replaces the destination on success.
Imports and audio inspection run off the main actor. Quit waits for cancellation
and queued persistence; an update swap is scheduled only after that succeeds.

Developer ID signing covers nested executable components and the app, with
hardened runtime and secure timestamps. Release packaging requires notarization
and stapling. Staged updates must pass a signature requirement pinned to Atten's
bundle ID and developer team, plus Gatekeeper assessment. See DEPLOYMENT.md.

The following audit records the original migration context; it is historical,
not a description of the current feature set.

## Original repository audit

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

## Streaming generation and word timings

Generation remains backward compatible without `--segments-dir`: the legacy
`segment` count events, merged audio, and `completed` payload are unchanged.
With `--json --segments-dir <directory>`, each segment is closed and synced as
`seg-00000.wav`, `seg-00001.wav`, etc. (24 kHz mono) before its NDJSON event:

```json
{"event":"segment","index":0,"path":"/tmp/segments/seg-00000.wav","text":"Hello.","start":0.0,"duration":0.8,"words":[{"text":"Hello","start":0.0,"end":0.6}]}
```

`start` is the segment's offset in the final recording; word `start`/`end` are
seconds relative to that segment. Kokoro's `Result.tokens` supply timestamps;
XTTS/MMS and languages without token timing emit an empty `words` array. Swift
estimates missing words by sentence and word character counts. Segment files
remain in the caller-owned directory, including completed segments after failure.
Use a separate directory for each generation.

`TTSGenerating.generateStream` yields progress and segments while the process
runs, then completion only after a successful exit. Failures yield `.failed` and
finish with an error; cancellation terminates the child. The whole-file API and
its retry policy are unchanged. Streams are not retried because consumers may
already have used an emitted segment. Legacy generators can use the default
whole-file stream adapter.

Each chapter recording has its own directory with `timings.json` and `segments/`.
Assembly offsets segment starts by decoded chapter durations and writes a
book-level `timings.json` beside the combined CAF in a unique recording directory,
so replacement generation cannot overwrite a previous recording's timings.
Word offsets stay segment-relative. `NarrationTimings.load(beside:)` returns nil
for older recordings without a sidecar, and `locate(time:)` binary-searches both
segments and words. It returns array positions, segment -1 for an empty timeline,
and a nil word during silence or outside the recording. No book/project schema
migration is required.

`cli.py transcode --input <file.wav|.caf|.m4a> --output <file.mp3|.wav> [--json]`
streams decoded audio through the existing libsndfile writer, preserving sample
rate and channels. M4A decoding uses macOS `afconvert` (or installed `ffmpeg` on
other platforms); WAV/CAF need no external decoder. Existing destinations are
rejected and output is published atomically. JSON mode emits `completed` with
`path`, or `error` with `message` and a nonzero exit status.
