# Mac overhaul acceptance report — 2026-09-22

Status: **unpublished Developer ID–signed candidate; not yet notarized or approved
for distribution**. Scope is macOS 14+ on Apple Silicon. Windows, payments, new
speech engines, and publishing are outside this work.

## Implemented

- Library and Create are the primary workspaces. Library opens by default and
  combines import, search, books, and continue listening. Old destinations map
  into the new workspaces. Native file opening selects Library, including from
  Create. Create contains drafts, projects, exports, and contextual voice previews;
  model management lives in Settings.
- Book details provide whole-book Prepare Audio / Resume Preparation / Listen.
  Reading stays available during preparation. Compact and expanded players share
  playback state, chapter navigation, seeking, and independent listening speed.
  Finishing preparation or launching the app never starts playback.
- Dark appearance uses neutral charcoal surfaces based on the supplied reference:
  #1E1E1E content, #141414 sidebar, #222222 surfaces, #383838 borders, and muted gray
  controls. System appearance remains the default. Reader tools stay collapsible,
  PDF layout and existing reflowable imports remain supported.
- One synthesis lease coordinates books, Create, and previews. Completed chapter
  checkpoints survive cancellation and interruption. Relaunch requires explicit
  resumption. Readiness checks audio and chapter metadata. Finalization streams
  bounded buffers, commits metadata before cleanup, and retains recoverable work
  on failure. Replacement keeps the previous recording until its successor commits.
- Reading and listening positions are independent. Playback restores paused;
  missing audio becomes repairable. Book export writes M4A transactionally.
  Import, extraction, inspection, synthesis, and assembly avoid main-thread work.
- Existing IDs, projects, exports, settings, legacy chapter recordings, and CLI
  contracts are retained. New persistence fields decode with defaults. Quit
  flushes pending persistence before exit or scheduling an update swap.
- Release tooling signs nested executable code and the app with Developer ID,
  hardened runtime, and timestamps; normal builds require notarization/stapling.
  Updates require the expected bundle ID/team and Gatekeeper assessment.

## Automated evidence

Host: Apple Silicon, macOS 26.2 (25C56). This does not replace testing the macOS 14
minimum supported version.

| Check | Result |
| --- | --- |
| Baseline Swift tests before this overhaul | 202 passed; existing dirty reader/playback/assembly work retained |
| Final `ATTEN_RUN_PERFORMANCE=1 swift test` | **218 passed, 0 failures** |
| `.venv/bin/python -m unittest discover -s tests -v` | **25 passed**; system Python lacked numpy, so the repository environment was used |
| `swift build -c release` | Passed; final build 22.89 seconds |
| Packaged offline voice sweep | All 37 bundled voices in MP3 and WAV passed |
| Final signed app offline synthesis | Passed |
| Mounted candidate DMG offline synthesis | Passed |
| App deep/strict signature verification | Passed, including mounted app |
| DMG signature verification | Passed |
| Plist lint, shell syntax, `git diff --check` | Passed |

Regression coverage includes synthesis and finalization cancellation, app
interruption, backend failure and explicit checkpoint resumption, competing
requests, corrupted audio, damaged library metadata preservation, final metadata
write failure, failed assembly, replacement while the old recording is loaded,
paused position restoration, navigation from Create to Library, M4A export and
failed-export destination preservation, legacy readiness/navigation defaults,
and assembled chapter offsets.

A 30-minute, 43.2-million-frame assembly used 31,784,960 bytes peak process RSS
(30.3 MiB); the short assembly used 32,817,152 bytes (31.3 MiB), measured with
`/usr/bin/time -l xcrun xctest`. This tests bounded assembly memory, not synthesis
model memory. A fresh process with two prepared test books exposed its accessible
window in 0.476 seconds on this already-running Mac. No pre-change launch timing
was recorded, so a launch-speed improvement is not claimed.

## Actual app verification

An isolated validation bundle and data directories were used. The user's normal
library and previous validation profile were preserved. Screenshots are native
window captures, not mockups. “Minimum” means the app-enforced 960-wide window
with a 700-point minimum content area; typical captures use a 1080×760 window.

| State | Typical light / dark | Minimum light / dark |
| --- | --- | --- |
| Empty Library | [Light](assets/finish-validation/library-empty-light.png) / [Dark](assets/finish-validation/library-empty-dark.png) | [Light](assets/finish-validation/library-empty-minimum-light.png) / [Dark](assets/finish-validation/library-empty-minimum-dark.png) |
| Populated Library | [Light](assets/finish-validation/library-light.png) / [Dark](assets/finish-validation/library-dark.png) | [Light](assets/finish-validation/library-minimum-light.png) / [Dark](assets/finish-validation/library-minimum-dark.png) |
| Preparing | [Light](assets/finish-validation/preparing-light.png) / [Dark](assets/finish-validation/preparing-dark.png) | [Light](assets/finish-validation/preparing-minimum-light.png) / [Dark](assets/finish-validation/preparing-minimum-dark.png) |
| Failed preparation | [Light](assets/finish-validation/failed-light.png) / [Dark](assets/finish-validation/failed-dark.png) | [Light](assets/finish-validation/failed-minimum-light.png) / [Dark](assets/finish-validation/failed-minimum-dark.png) |

Additional views: [book detail](assets/finish-validation/book-detail-dark.png),
[light detail](assets/finish-validation/book-detail-light.png),
[reader](assets/finish-validation/reader-dark.png),
[minimum reader](assets/finish-validation/reader-minimum-dark.png),
[minimum Create](assets/finish-validation/create-minimum-dark.png),
[light Create](assets/finish-validation/create-minimum-light.png), and
[Now Playing](assets/finish-validation/now-playing-dark.png).

The real GUI journey completed: empty launch → TXT import → read → prepare →
finalize → listen → pause → quit → relaunch paused at the same 14.775-second
position → M4A export. The exported file passed `afinfo` inspection (26.65 seconds,
24 kHz mono AAC). A read-only test narration directory caused a real preparation
failure; restoring directory access and choosing Resume Preparation succeeded.
Preparation completion left playback stopped. Accessibility inspection confirmed
labels for navigation, voice, speed, preparation, chapter playback, and player
controls. Cmd-1/Cmd-2 navigation and native save-panel keyboard actions were used.

The visual pass fixed a disappearing voice label, a crowded speech-speed label,
a Create action below the fold, and file opening that imported successfully but
left Create selected. This is not a claim of complete keyboard-only or spoken
VoiceOver acceptance.

## Candidate artifacts and provenance

The signed app and candidate DMG are under `.build/release-candidate/`. The
source archive, SBOM, and checksums are release-build outputs and were not
generated for this local candidate:

- `Atten.app`
- `Atten-macOS-arm64-candidate.dmg` — signed, **not notarized**
- `Atten-corresponding-source.tar.gz`, `Atten-sbom.spdx.json`, and
  `SHA256SUMS.txt` — generated by the clean release build before publication
- `validation/` — build, test, memory, launch, and packaging logs

Identity: `Developer ID Application: Jashraj Dubal (BK6ZPY7AD9)`.
The candidate retains bundle version 0.3.2 and is not a new published release.
It uses the existing staged backend/model bundle that passed the full voice
sweep, with the final Swift release executable and updated resources. Nested
components were Developer ID signed and verified; the app envelope was re-signed
after each executable update. A clean, tagged production build is still required.
No credentials were added to source, and no release was published.

## Outstanding release gates

1. Supply the existing **notarytool Keychain profile name**; credentials stay in
   Keychain. Submit, staple, and assess the app, then rebuild/sign/notarize/staple
   the DMG. Developer ID signing alone does not complete this gate.
2. Verify a quarantined downloaded installation and an update from the prior
   published release on a clean supported Mac, including macOS 14. Local mounted
   DMG validation is not equivalent to that test.
3. Complete spoken VoiceOver and full keyboard-only acceptance, reduced-motion
   visual inspection, physical media keys, and sleep/wake playback. Automated
   motion/interaction tests and AX inspection passed, but those hardware/manual
   checks have not been claimed.
4. Configure the documented CI signing/notarization secrets, assign the intended
   new release version, and build from a reviewed clean commit. Publishing remains
   a separate action.
