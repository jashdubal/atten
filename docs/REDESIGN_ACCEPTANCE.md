# Mac overhaul acceptance report — 2026-09-22

Status: **unpublished Developer ID–signed candidate; not yet notarized or approved
for distribution**. Scope is macOS 14+ on Apple Silicon. Windows, payments, new
speech engines, and publishing are outside this work.

## Addendum — 2026-09-23: chrome, motion and Library follow-ups (#43, #44, #45)

Closes #43, #44 and #45. The neutral charcoal palette from the 2026-09-22 pass
is kept as the dark appearance of record; #45's separate navy palette does not
land. Its motion half does:

- **Motion (#45):** destination/overlay transitions are a plain crossfade, the
  pressed-control cue is a brief opacity dim instead of a scale, the hover lift
  on Home's shelf jackets is removed, and every non-Reader shadow (elevation
  tokens, the primary button, book/audio artwork, the play button) is capped at
  radius 6 / opacity ≤0.15. The unused `brandGradient` glow token is removed.
  The Reader's page-turn animation, its shadows, and the reader page palette
  are unchanged.
- **Chrome (#44):** the light-mode chrome gradient is gone — sidebar, top
  chrome and the detail column now share one flat ground per appearance.
  Sidebar row selection is a faint tint plus a 2pt accent leading mark instead
  of a strong tonal fill; the focus ring, `.isSelected` trait and arrow-key
  navigation are unchanged. The floating player capsule lost its material,
  gradient stroke and heavy shadow in favor of a solid surface, a hairline
  border and the same restrained elevation shadow used elsewhere.
- **Library (#43):** sort choice now persists across launches; the sort menu
  hides (rather than shows disabled) under the Recently Added filter, which
  already sorts newest-first; the filter+sort combination rule moved into
  `BookshelfModel.books(for:query:sort:)`, now covered by a test. The
  missing-cover jacket uses theme-aware colors instead of fixed paper tones,
  and no longer prints "ATTEN LIBRARY" filler when a book has no author.
  Removing a book now asks for confirmation, since it deletes the source file
  and any narration. The card's spoken VoiceOver value states its ready/narration
  status, matching what's shown on screen.

`swift test` (221 tests) and `swift build -c release` both pass. This is
automated evidence only — the manual GUI checks listed under Outstanding
release gates below (spoken VoiceOver, keyboard-only acceptance, reduced-motion
visual inspection, physical media keys, light/dark screenshot capture) were not
performed for this addendum.

## Addendum — 2026-09-24: UI overhaul P7 — final pass (#55)

Closes #55. The last phase of the UI overhaul (`docs/design-system.md` covers
the token/component reference this phase adds):

- **Dead code:** `HomeView.swift` (480 lines, zero references outside its own
  file; its one reusable piece, `BookJacket`, moved into
  `ContinueListeningHero.swift`, its sole consumer) and AppModel's Playground
  sample API and separate text-import API (`importText`/`openImportPanel`,
  distinct from `CreateFlowModel`'s own live import) are removed, along with
  the tests that only exercised them. `ProjectsView`, `ExportsView` and
  `PlaygroundView` no longer existed under those names by the start of this
  phase. The ~130 deprecated typography call sites were already migrated to
  the P1 type scale; the now-unreferenced deprecated aliases
  (`AttenTypography.caption`/`.control`/etc., `AttenRadius.player`) and two
  unused `AttenMetrics` fields are removed (`coverGridMinimum` was in fact
  still needed — `BookDetailView`'s cover frame now uses it instead of a
  duplicated magic number).
- **OKLCH consolidation:** `CoverPalette`'s own sRGB↔OKLab conversion is
  replaced with a thin bridge onto P1's `OKLCH` in `AttenCore`, so the
  gamut-mapping math exists once. `OKLCHColor.srgb()` now preserves hue on an
  out-of-gamut colour instead of naively clamping each channel.
  `OKLCHTests`/`CoverPaletteTests` stay green, unchanged.
- **Contrast:** `PaletteAmbientContrastTests` extends the palette's contrast
  coverage from the fixed palette (`ThemeTests`) to the runtime ambient field —
  `AmbientContrast`'s opacity search is verified to hold `text1` at 4.5:1
  against an adversarial sample set, the calmed samples the field actually
  draws from, and the raw composite blend, in both appearances.
- **Keyboard:** *Import into Create* moves from the conflicting ⇧⌘O onto ⌘I,
  matching Create's own local import button. The Library gets its own ⌘F
  (through a new optional external-focus binding on `AttenSearchField`,
  mounted only on the shelf page so it can never contend with the Reader's
  own ⌘F). Space play/pause and arrow-key 15s skip already existed, scoped to
  the Read-Along player. Settings → Shortcuts is rewritten to match what's
  actually bound and drops the row for the removed Playground sample.
- **Focus ring:** fixed showing on the first sidebar control at launch under
  system Keyboard Navigation — a new `attenHasUsedKeyboard` environment
  value, published from one `NSEvent` keyDown monitor at the window root,
  gates both `AttenFocusRing` and the sidebar's own focus border so a ring
  only appears once a key has actually been pressed.
- **Accessibility:** the Settings speed `Slider` gets an explicit
  accessibility label and value (it had none; `LabeledContent`'s row label
  doesn't substitute for the control's own). Reduce Motion's "static level"
  requirement was already centralized in `VoiceLevel` (holds at 0.5 rather
  than sampling per frame); a `ReadAlongPlayButton` property that duplicated
  and never read that check is removed. Reduce Transparency was already
  centralized in `Glass.swift`/`Buttons.swift`.

`swift build -c release`, `swift test` (357 tests, up from 354 — 3 new
ambient-contrast tests), and `uv run python -m unittest discover -s tests -p
'test_*.py'` all pass. This is automated evidence only.

**Not done in this pass, and left for a coordinator with the live app:**
Reduce Motion/Reduce Transparency visual inspection per screen, full
keyboard-only navigation acceptance of Create and the Library, spoken
VoiceOver acceptance beyond the one control fixed above, and the Instruments
(Animation Hitches / Core Animation FPS) trace scrolling a 500-item Library
with playback and the ambient field active. These all need the GUI, which
this pass was explicitly asked not to launch; the code paths they'd exercise
(reduceMotion/reduceTransparency environment reads, accessibility labels,
the focus-ring gate) are in place and covered where `swift test` can reach
them — the `Atten` executable target's views themselves are outside
`AttenCoreTests`' coverage, same as the rest of the app.

## Addendum — 2026-09-24: Library offscreen QA (#68)

Closes #68. P4 (#62) shipped the Library grid without ever being seen on
screen, and the live check stayed blocked while the portrait monitor was
disconnected (see the previous addendum's note about needing the GUI).
`LibraryRenderTests` renders the shelf, the dedupe toast and the export sheet
with SwiftUI's `ImageRenderer`, in both appearances, gated behind
`ATTEN_RENDER_DIR` so CI never runs it:

- The fixture covers all four Library states at once: a silent draft, a book
  partway through narration, a fully voiced book (doubling as the Continue
  Listening hero), and a legacy `projects.json` entry. It goes through the
  real `BookshelfModel.load()`/`importBook` paths rather than poking private
  state, so the toast render triggers the actual dedupe flow by importing the
  same text twice.
- **The one fix:** `ImageRenderer` draws nothing for a `ScrollView`'s content
  (confirmed empirically — the first render of the shelf came back as a flat
  background with no cards, text, or hero; `library-qa-before-blank.jpg`).
  `LibraryView.swift` now reads a new `attenIsOffscreenRender` environment
  value and swaps the shelf's `ScrollView` for a plain `VStack` around the
  same `shelfContent(availableWidth:)` when it's set — never set outside this
  test, so the real app is unaffected. `library-qa-shelf-{light,dark}.jpg`,
  `library-qa-toast-{light,dark}.jpg` and `library-qa-export-{light,dark}.jpg`
  are the resulting renders.
- `TextField`, `Menu` and the segmented `Picker` each render as a plain
  yellow "unsupported" placeholder in every screenshot — a pre-existing
  `ImageRenderer`/AppKit limitation (also seen in P6's read-along work), not
  a Library defect; the search field, sort menu, each card's overflow menu,
  and the export format picker all still work in the real app.

A first pass called this done with no further fixes; a coordinator review of
the renders found eight real defects against `docs/design-system.md`, since
fixed on the same branch:

- **Two primary buttons on one screen.** The hero's "Listen" competed with
  "New" for the app's one signal-filled button; it's `AttenSecondaryButtonStyle`
  now, like "Open" beside it (`ContinueListeningHero.swift`).
- **Help text.** The header's "Your books and documents, ready when you are."
  and the shelf's permanent "Drop a PDF, EPUB…" hint were both instructions a
  control already conveys (the empty state says the same thing when the
  shelf actually is empty); both removed (`LibraryView.swift`).
- **An unlabeled progress ring beside "Listen"** read as a stuck loading
  spinner rather than listening progress shown nowhere else — removed rather
  than given a caption that would just duplicate the meter pattern used
  elsewhere. Its removal also exposed the real cause of a large empty gap
  under the hero's text: `shelfContent` rendered inside a `GeometryReader`
  under `isOffscreenRender`, which unlike the real `ScrollView` proposes its
  full fixed height to its child, so every `Spacer` in the tree — including
  the hero's — stretched to fill the render canvas. Fixed with `.fixedSize(
  horizontal: false, vertical: true)` on the offscreen render path only
  (`LibraryView.swift`).
- **A cover's shadow rendering as a second, offset rectangle in dark
  appearance.** `AttenCoverFrame` clipped, stroked, and shadowed a cover
  without a `.compositingGroup()`, so the clip and the stroke overlay each
  cast their own shadow instead of one shape casting one
  (`LibraryCoverChrome.swift`).
- **Grid covers not lining up.** `LazyVGrid` centers a cell within its row by
  default; cards with a narration meter or "Ready to listen" line are taller
  than one with neither, so shorter covers above them drifted down. Fixed
  with `alignment: .top` on the `GridItem` (`LibraryView.swift`).
- **The same book showing a different generated-cover hue per appearance.**
  Root cause was in the fixture, not production code:
  `BookshelfModel.existingBook(withContentHash:)` lazily computes and caches
  a book's content hash the first time anything checks for a duplicate, and
  the render test's fixture gave every book the same placeholder chapter
  text, so this collided two different books onto the same hash (and so the
  same cover seed) once that backfill ran. Fixed by giving each fixture book
  distinct text and settling the shelf's final state — the "Old Friends"
  duplicate import included — before either appearance is rendered, so light
  and dark always render from identical state (`LibraryRenderTests.swift`).
- **A card's caption repeating its cover's own text.** A `BookCard` with no
  real cover art already prints title and author/format onto the generated
  cover's own face; for a book with no author, the caption below it repeated
  the exact same format name a second time. Now that caption is only shown
  when there's a real author to show, or when there's real cover art with no
  baked-in label of its own (`LibraryView.swift`).

`swift test` (381 tests, 4 skipped), `uv run python -m unittest discover -s
tests -p 'test_*.py'` (40 tests) and `swift build -c release` all pass after
these fixes. The live on-screen check with the real GUI is still owed once
the portrait monitor is back.

## Addendum — 2026-09-24: cleanup from #71 and #73 (#75)

Closes #75.

- **The cover shadow's dark-appearance halo, still there after #73's
  `.compositingGroup()` fix.** That fix removed the double-shadow outline, but
  the one remaining shadow kept using `AttenColor.cover(tint)` at `tint`'s own
  lightness (~0.6 for a generated cover's seed hue, or a real cover's
  extracted dominant colour) — a colour meant to be seen at, not cast a shadow
  in. `AttenColor.cover` fixes a colour's appearance on purpose ("Covers are
  content and keep their colours in both appearances"), so that mid lightness
  reads as an ordinary dim shadow next to light mode's near-white page, but as
  a lighter halo next to dark mode's near-black one, most visible where the
  shadow's `y: 2` offset carries it past the cover's own edge. `AttenCoverFrame`
  now shadows with a copy of `tint` whose lightness is capped at 0.25 before
  it reaches `AttenColor.cover`, keeping the hue the shadow is tinted by
  without keeping a highlight's lightness (`LibraryCoverChrome.swift`).
  Re-rendered `library-qa-shelf-{dark,light}.jpg` and
  `library-qa-toast-{dark,light}.jpg`; the pre-fix renders are kept alongside
  as `library-qa-{shelf,toast}-before-cleanup-{dark,light}.jpg` for
  comparison.
- **Pronunciation in previews.** `CreateFlowModel.preview(_:)` and
  `previewURL(for:)` — the narrator card's Preview button and, through it,
  every card in the casting sheet — sent the draft's first sentence straight
  to the generator, so a preview never said a pronunciation the way `narrate`
  (`BookshelfModel.swift`) would. Both now run that sentence through the same
  `PronouncedText` substitution first. The preview cache is already keyed on
  a hash of the sentence it was asked to speak (`AppModel.voicePreviewURL`),
  so sending it the pronounced text — rather than adding pronunciations as a
  separate key input — both fixes the substitution and makes the cache miss
  exactly when what the voice would actually say changes, and not otherwise
  (`CreateFlowModel.swift`).
- **Pronunciation list padding.** `PronunciationList`'s own `ScrollView(
  .vertical)` (Create → Advanced) has no `attenScrollPadding()`, but it
  doesn't need one: that call exists so a page-level scroll view's last row
  doesn't land under the floating player, and this box is a small, internally
  height-capped list inside `CreateInspector`'s column, which already reserves
  `AttenMetrics.playerHeight` under its own footer whenever the player is
  showing — clearance this box sits well above regardless of how many rows it
  holds. Left as-is; the existing comment saying so stands. `swift test`'s
  `ScrollPaddingTests` doesn't flag it either, since its regex only matches a
  bare `ScrollView {`, not this one's `ScrollView(.vertical) {`.

`swift test`, `uv run python -m unittest discover -s tests -p 'test_*.py'`
and `swift build -c release` all pass. No GUI: the live on-screen check is
the coordinator's, same as the addendum above.

## Addendum — 2026-09-24: the cover halo, still there after capping at 0.25 (#75)

A coordinator review of PR #76's own render found the previous entry's fix
insufficient: `library-qa-shelf-dark.jpg` still showed a ~25px band along
each cover's right edge and a thin one below, dense enough on the JPEG to
read as a hard-edged rectangle rather than a fading shadow — plausibly a
grid cell or background sized wider than the cover, not a shadow at all.
Re-rendering with the shadow's opacity forced to `0` settled it either way:
the band vanished completely, so `AttenCoverFrame`'s shadow was always the
whole cause — `LibraryView`'s grid sizes the jacket and its column correctly,
and the sharp-looking edge was just how a lightness-0.25 shadow, still five
times brighter than the near-black page, degrades under JPEG's quantizing of
a low-contrast gradient. Every other shadow in the app is cast in
`AttenColor.shadow` — pure black in both appearances, so it all but
disappears against a dark page and only ever darkens a light one; this
shadow, tinted by the cover's own hue for the reason `attenCoverFrame`'s own
doc comment gives, now pins that tint's lightness at 0.05 rather than 0.25 —
close enough to black to do the same disappearing act in dark appearance
while keeping its hue in light appearance, where the lower lightness reads
as a slightly more present but still ordinary shadow. Re-rendered
`library-qa-shelf-{dark,light}.jpg` and `library-qa-toast-{dark,light}.jpg`
again; this addendum's own pre-fix renders are kept as
`library-qa-{shelf,toast}-before-cover-box-fix-{dark,light}.jpg`, and
`library-qa-cover-edge-zoom-{dark,light}.jpg` crops a cover's right edge
from both side by side.

`swift test` (382 tests, 4 skipped), `uv run python -m unittest discover -s
tests -p 'test_*.py'` (40 tests) and `swift build -c release` all pass. No
GUI: the live on-screen check is the coordinator's.

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
