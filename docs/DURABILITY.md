# Durability on macOS

Atten is meant to still work on a Mac that nobody maintains, years after the
last release, with no account and no server. This records what that promise
covers, what it does not, what was tested to establish it, and what a
maintainer must not break.

## What is guaranteed

**Speech never needs the network.** The app bundle carries its own Python
runtime, the Kokoro model, and the eSpeak data the phonemizer needs. Nothing on
the generation path opens a connection, and nothing on it can be switched off by
someone else. Verified by running every bundled voice through the packaged app
with `HTTP_PROXY`, `HTTPS_PROXY` and `ALL_PROXY` pointed at a closed port, so any
attempted fetch fails immediately instead of succeeding quietly:
`scripts/smoke-packaged-backend` does this on every release build.

**Every voice the app offers can speak.** A voice either runs on the bundled
engine or declares in `resources/voices.json` the one model it needs. The
backend routes on that declaration and, when the model is not on disk, says
which model to download and that the voice works offline afterwards. The smoke
test exercises every voice that claims to need nothing.

**State written by any version is readable by any other.** Project history and
settings decode field by field, so a file written by an older or newer Atten
keeps everything that still applies rather than being discarded whole. A history
file that cannot be read is moved aside, never overwritten, and records that
still decode are kept.

**Memory does not grow with the length of the narration.** Segments are streamed
into the output file rather than concatenated in memory, so a book-length text
costs no more than a short one. Measured: joining 20 minutes of audio held
1,155 MB before this change and effectively nothing after.

**The app cannot be left in a broken state by an update.** The installed copy is
moved aside rather than deleted, and restored if the new bundle cannot take its
place. A release without published checksums is refused, and a staged bundle is
installed only if it carries its executable, engine and model.

**Update checks are optional.** Turning them off in Settings leaves an
installation that never touches the network at all and stays on its version
indefinitely.

## What is best-effort

**Discovering and downloading Hugging Face models.** This is the one feature
that depends on an outside service. When the Hub cannot be reached, the Models
screen says so and falls back to a built-in list; everything already installed
keeps working. If the Hub ever disappears, Atten keeps every model already on
disk and loses only the ability to find new ones.

**Update checks.** They depend on GitHub's API. Failures are silent at launch
and reported only when the user asks. If GitHub changes or disappears, the app
never notices anything but a failed check.

**Running on a future macOS.** Atten is an arm64 app that targets macOS 14. No
maintainer can guarantee what a macOS twenty years from now will run. The
mitigations available today are taken: no dependency on system Python, no
dependency on anything outside the bundle, and a minimum-version floor that is
honest.

## Current distribution status

The September 2026 candidate is Developer ID signed, including the nested speech
runtime. Signing verification and an offline packaged synthesis check passed.
Notarization and stapling remain pending the maintainer's notarytool Keychain
profile. A signed candidate is not yet an accepted distribution release.

Release packaging now requires signing and notarization by default. The explicit
`ATTEN_LOCAL_VALIDATION=1` escape hatch is for local ad-hoc builds only.
Developer ID builds skip the legacy quarantine repair. Update installation checks
the app's developer identity and Gatekeeper assessment before replacing the app.
Previously published ad-hoc releases retain their documented installation path.

Whole-book preparation checkpoints completed chapters, keeps the previous
recording during replacement, and commits final metadata before deleting
recoverable files. Cancellation and relaunch leave unfinished work available for
explicit resumption. A 30-minute assembly test used about 30.3 MiB peak process
RSS, compared with 31.3 MiB for the short assembly test on this Mac. This measures
assembly, not synthesis-model memory. Current evidence and remaining hardware
checks are in [the acceptance report](REDESIGN_ACCEPTANCE.md).

## Earlier release testing

Against the packaged, signed app from a release build, not the development
checkout, because the bundled engine, the bundled model and Gatekeeper only
exist there.

- All 57 catalogued voices, offline. 37 produced audio; the 20 that could not
  are the ones that now declare a required model.
- A downloaded model end to end: `facebook/mms-tts-ara` fetched once, then
  Arabic synthesized with the network unavailable.
- Adversarial text: empty, whitespace, punctuation only, emoji only, digits,
  right-to-left script, control characters, and a 50,000-character paragraph
  that produced 50 minutes of audio.
- Adversarial names: 400 characters, 200 emoji, `..`, leading dots, embedded
  path separators, and collisions with an existing export.
- Filesystem hostility: read-only export folder, a folder several levels deep
  that did not exist, and a full disk.
- State hostility: history that is not JSON, history truncated mid-write,
  history with one damaged record, history and settings written by a version
  with unknown fields and unknown enum values, and an empty voice catalog.
- The update swap's four failure modes, each confirmed to leave a working app.
- A quarantined copy taken straight from the release DMG.

## Rules for maintainers

1. Nothing on the speech path may open a connection. The smoke test enforces
   this; do not weaken it.
2. Every voice added to `resources/voices.json` either runs on the bundled
   engine or declares `requires_model`.
3. New fields in `AppSettings` and `ProjectRecord` decode with
   `decodeIfPresent` and a default. Never add a required key.
4. Never overwrite a state file that failed to load.
5. Audio is streamed to disk, never accumulated in memory.
6. The updater verifies before it installs and keeps the old app until the new
   one is in place.
