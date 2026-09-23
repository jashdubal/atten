# Atten UI overhaul — audit + orchestrated plan

## Context
Jash wants a full visual/UX overhaul of Atten (v0.3.2) per the pasted spec: quiet, nearly colorless chrome where only voice-live states glow; Library as the single home with Create as a flow; generation that shows knowledge (estimates, per-sentence progress) and plays progressively; a read-along player. I coordinate: write issues, dispatch Codex/Claude workers through **Orca** in their own worktrees/branches, review their PRs, run the app and screenshot it, and merge phase by phase. On approval, this file is committed as `docs/ui-overhaul-plan.md` (spec step 2). Your approval here is the "stop and wait" gate.

Decisions already made: **dark + a derived light token set** (System/Light/Dark kept). The **read-along player replaces Now Playing**, and the paged Reader stays as the reading mode (re-tokened only).

(The spec mentions attached screenshots, but none arrived. I'll capture the before-state myself.)

## 1. Audit (spec §0.1)
- **Shell/stack:** native **SwiftUI**, Swift 6, macOS 14+, arm64. It is not Electron or Tauri. There are zero SPM dependencies. The Python sidecar (`atten_backend/`, `cli.py`) runs Kokoro-82M (plus XTTS/MMS for other languages).
- **Styling:** `DesignSystem.swift` (956 lines) + `ThemePalette.swift`. There are 22 light/dark hex roles, a monochrome accent, a type scale (30/22/15/13/11), spacing 4–40, radii 6/8/12/14. Button styles: Primary (16 uses), Secondary (23), Feedback (11), 2 private Library styles, and system `.bordered`/`.borderedProminent` in Voices/Models/Exports. There are no materials or vibrancy anywhere. `accessibilityReduceMotion` is read in 10 files; Reduce Transparency is never handled.
- **Animation:** `AttenMotion`, a single timing curve with no springs and no `matchedGeometryEffect`. The Reader page-turn has its own animations.
- **TTS pipeline:** `ProcessBackendClient` (`AttenCore/BackendClient.swift:73`) starts one process per request.
  - The backend already emits NDJSON `segment` events, but Swift reads stdout only after exit.
  - Segments are written to a temp dir that is deleted, and one file is returned.
  - **Word timestamps exist in Kokoro** (`MToken.start_ts/end_ts`) but are discarded at `service.py:310`.
  - Books have per-chapter checkpointing (`BookshelfModel.narrate`, `:335-492`) and are then assembled into a `.caf` with chapter start/end times.
  - Speed is applied **at generation time**. Playback uses `AVAudioPlayer` (`enableRate`; pitch is preserved by default) with no metering.
  - There is no RTF or duration estimate. The book ETA uses character counts.
- **Data model:**
  - `projects.json` holds `[ProjectRecord]` (text, voice, speed, format, one audio file). A project exists only after a successful generation.
  - `books.json` holds `[BookRecord]`, with chapters, narrationState, and positions.
  - A Draft is not a record: `@SceneStorage` text only. Exports are projects filtered by "file exists".
  - There are no shared IDs and no content hashing. Decoders tolerate new keys, and repositories salvage partial files.
- **Affected screens:** RootView/ScreenChrome/AttenApp (shell, commands), PlayerBar, NowPlayingView, CreateWorkspace/StudioView/PlaygroundView/ProjectsView/ExportsView, LibraryView/BookDetailView/BookCoverStore, VoicesView, SettingsView/ModelsView, HomeView (dead code), and the Reader (tokens only).

## 2. Where the spec doesn't fit (and what we do instead)
| Spec | Atten equivalent |
|---|---|
| CSS custom props, OKLCH | An `AttenToken` enum in Swift. OKLCH→sRGB conversion runs at init (a small `OKLCH` struct in AttenCore, unit-tested). There are dark and derived-light values, resolved through the existing dynamic `NSColor(name:)` provider. |
| "no raw hex" lint rule | A test in `AttenCoreTests` that greps `Sources/Atten` for `Color(hex:`, `.black`, `.white`, `Color(red:` and `NSColor(` outside the token files. The Reader page palette is allowlisted: it is content, not chrome. |
| Framer Motion springs / `layoutId` | SwiftUI `.interpolatingSpring(stiffness:damping:)` (400/34 small, 260/30 large) and `matchedGeometryEffect` + `@Namespace`. |
| `backdrop-filter` glass | `.background(.ultraThinMaterial)` plus a `--glass` tint, hairline stroke, 1pt top specular highlight and shadow, as an `.attenGlass()` modifier. When Reduce Transparency is on, it falls back to `surface1`. |
| Electron vibrancy | Native: `NavigationSplitView`'s sidebar with `.background(.clear)`, or an `NSVisualEffectView(.sidebar)` representable. |
| Overlay scrollbars | Already the macOS default when the system setting is "automatic". I'll remove any forced `.scrollIndicators(.visible)`. |
| `@tanstack/virtual` | `LazyVGrid` is already virtualized. No dependency needed. |
| AnalyserNode + `--level` CSS var | `AVAudioPlayer.isMeteringEnabled` sampled in a `TimelineView(.animation)`, with an envelope follower (30ms/200ms). It is stored in a non-published `LevelMeter` reference type so no SwiftUI invalidation cascades. |
| MediaSource progressive playback | `AVAudioEngine` + `AVAudioPlayerNode.scheduleFile` per segment during generation. Once generation finishes, playback hands off to the assembled file. |
| MeshGradient covers (macOS 15+) | Deterministic layered `RadialGradient`s in a `Canvas`, which works on macOS 14. |
| Export MP3/WAV | AVFoundation can't encode MP3. WAV and M4A are native; MP3 goes through the backend's existing mp3 writer via a new `cli.py transcode` subcommand. |
| Embedding-based hue | There's no local embedding model, so the hue comes from a content hash, with a `TODO(embedding-hue)`. |
| "Pause length / pronunciation" in Advanced | The engine exposes neither today. Advanced shows only what is real: chapter detection (auto / headings / none) and Metal acceleration. Pronunciation is a TODO issue. |

## 3. Data-model approach (reversible, additive; no destructive change)
- **Library item = `BookRecord`.** New Create drafts are saved as `.document` books with one text file in `Library/` and `narrationState = .none`, which is the "silent" state. Generation reuses `BookshelfModel.narrate`, so it gets checkpointing, resume, and "continues if you leave the view" for free.
- **Legacy projects** are never rewritten. `projects.json` and `ProjectRepository` stay. A `LibraryItem` adapter (`enum { book(BookRecord), project(ProjectRecord) }`) presents them as voiced items. They stay playable, exportable, and deletable with the same semantics as before, including never deleting export audio by accident.
- **New optional fields** on `BookRecord`: `contentHash: String?` (SHA-256 of the normalized text, for dedupe) and `voicedAt`. Old builds ignore these keys. Hashes are backfilled lazily in memory; the record is only written when it is next saved anyway.
- **Speed:** new generations use 1.0×. Existing books keep their stored `speed` and audio. The narration-speed picker is removed from BookDetail, and listening speed (0.75–3×) lives in the player. `AppSettings.defaultSpeed` stays decoded but unused.
- **Format:** generation keeps the engine's internal format. Format is chosen in the Export sheet.
- If any step turns out to need a non-additive change, I stop and ask first (spec §0.5).

## 4. Orchestration
Orca worktrees (`orca orchestration worker-start --worktree new-child --agent codex|claude --model …`). There is one GitHub issue per work item, a branch `ui/<nn>-<slug>`, and a PR into `main`. I review each diff, run `swift test` plus the Python tests, and build and run the app. I screenshot it with the window-id harness (see memory) and verify the pid is from that worktree. Then I merge. UI phases merge **in spec order**; the non-UI groundwork runs ahead in parallel. Workers get only the context for their issue: the relevant spec section, the files, the acceptance criteria, and the test commands.

| Wave | Work item (issue → branch) | Agent | Depends on |
|---|---|---|---|
| A | **P1 Foundations**: OKLCH tokens (dark + light), type scale, spacing/radius, `.attenGlass`, sidebar vibrancy, 3-level button system replacing all variants, focus ring, spring tokens, no-raw-color test | Claude Opus 5.5 | — |
| A | **G1 Streaming backend**: Python emits `segment{path, index, duration, words:[{text,start,end}]}` into a stable dir; `TTSGenerating` gains an `AsyncStream<GenerationEvent>` (line-by-line stdout); word timings persisted per chapter as `timings.json` beside the audio; Python + Swift tests | Codex `gpt-6-astra` | — |
| A | **G2 Core logic (AttenCore, pure + tested)**: content hash + dedupe in `importBook`, `VoiceProfile` map (name/descriptor/accent/color from `resources/voices.json`), `ListenEstimator` (155 wpm, per-voice calibration, rolling RTF in settings), deterministic cover seed, OKLab k-means palette + L/C clamp + WCAG contrast check, `LibraryItem` adapter, draft-as-book save | Codex `gpt-6-sol` | — |
| B | **P2 Shell**: sidebar = Library/Voices/Settings (~200pt); `SidebarItem` migration (old SceneStorage values map forward); "+ New"/⌘N; 64pt glass mini-player pill centered in the content column; `attenScrollPadding` (64+24) on every scroll view; top-bar cleanup | Claude Opus 5.5 | P1, G2 |
| C | **P3 Create**: `CreateFlow` state machine (empty→editing→generating→done); full-window drop target; editor + 320pt inspector; narrator card; casting sheet with first-sentence previews cached per voice+draft hash; estimates + trust chip; ⌘↩; the bottom bar, speed and format removed; Playground folded into "Try a sample" | Claude Opus 5.5 | P2, G1 |
| C | **P4 Library**: generated covers, silent/voiced filters + generating saturation, waveform glyph, chips All·Listening·Drafts·Audiobooks, Continue Listening hero, "Already in Library" toast, export sheet (⋯ → Export…) | Codex `gpt-6-terra` (UI spec is concrete) | P2, G2 |
| D | **P5 Progressive playback**: `AVAudioEngine` segment queue during generation, Play enabled at first segment, handoff to assembled file, sentence sweep in the read-only editor | Codex `gpt-6-astra` | P3, G1 |
| D | **P6 Read-along player**: replaces NowPlayingView; ambient field (800ms crossfade), collapsing cover, word underline via binary search per frame, distance fade/blur, click-to-seek, `LevelMeter`, speed 0.75–3×, mini→full `matchedGeometryEffect` | Claude Opus 5.5 | P2, G1 (can start in parallel with P5) |
| E | **P7 Final pass**: a11y audit (contrast incl. runtime ambient, VoiceOver labels, Reduce Motion → 150ms fades/no blur/static level, Reduce Transparency), shortcuts (Space, ⌘N, ⌘I, ⌘↩, ←/→ 15s, ⌘F), Instruments scroll profile, removal of dead code (HomeView, ProjectsView/ExportsView/PlaygroundView, stale metrics), `docs/design-system.md` | Claude Sonnet 5 + my own review | all |

P3 and P4 both touch `AppModel`/`RootView`. P3 merges first, and P4 rebases onto it. There are at most 3 concurrent workers.

## 5. Risks
- **Merge conflicts in `AppModel.swift` (1,337 lines) and `RootView.swift`.** Each worker owns a new file for its feature, and the shared-file edits are kept small.
- **Progressive playback changes the audio stack.** `AVAudioEngine` is used only during generation; finished items keep `AVAudioPlayer`, which keeps the risk to proven paths small.
- **Word timings:** Kokoro only; XTTS/MMS voices fall back to sentence-level timing, which is estimated proportionally within each segment. I'll report where that applies.
- **Per-process model reload** makes the first-segment latency depend on model load (~seconds). Keeping one backend alive is out of scope and will be raised as a follow-up.
- **Light theme** doubles the visual QA. Each phase is screenshotted in both appearances.
- **Shared UserDefaults and Jash's real library** across worktree builds: every run uses `ATTEN_DATA_DIRECTORY=<scratch>` and a copied fixture library, never the live data.
- **Glass limit (≤3 live materials):** sidebar, mini player, and one sheet or popover at a time. This is enforced by review.

## 6. Critical files
- **New:** `Sources/Atten/Tokens.swift`, `Glass.swift`, `CreateFlow*.swift`, `NarratorCard.swift`, `CastingSheet.swift`, `GeneratedCover.swift`, `ReadAlongView.swift`, `LevelMeter.swift`, `ProgressivePlayer.swift`, `ExportSheet.swift`; `Sources/AttenCore/OKLCH.swift`, `VoiceProfile.swift`, `ListenEstimator.swift`, `ContentHash.swift`, `LibraryItem.swift`, `CoverPalette.swift`, `WordTimings.swift`.
- **Modified:** `DesignSystem.swift`, `ThemePalette.swift`, `RootView.swift`, `AttenApp.swift`, `PlayerBar.swift`, `StudioView.swift` (replaced by CreateFlow), `LibraryView.swift`, `BookDetailView.swift`, `BookshelfModel.swift`, `AppModel.swift`, `BackendClient.swift`, `Bookshelf.swift`, `Models.swift`, `atten_backend/service.py`, `cli.py`.
- **Reuse:** `BookshelfModel.narrate` (checkpointed generation), `BookAudioAssembler`, `BookCoverStore` (real-art path), `AppModel.previewVoice` cache pattern (re-keyed voice+text-hash), `VoiceCatalog.bundled`, `DocumentImporter.extract` metadata (title prefill), `ProjectRepository` salvage semantics, the `AttenMotion.animation(_:reduceMotion:)` pattern.

## 7. Verification (every phase, before merge)
1. `swift test` (currently 221 tests, all passing), `uv run python -m unittest discover -s tests -p 'test_*.py'`, `swift build -c release`, and the no-raw-color test.
2. Launch the worktree build with `ATTEN_DATA_DIRECTORY` pointing at a fixture copy. Screenshot each touched screen in dark and light, and check the pid path.
3. Functional smoke: import (epub/pdf/txt) → generate → play → quit/relaunch (persistence) → export. Legacy `projects.json` and `books.json` fixtures from the current `main` must still load and play.
4. From P5 on: first audio plays before generation completes, and the word highlight tracks audio within ±1 word.
5. P7: Reduce Motion and Reduce Transparency toggled on screen, and an Instruments Core Animation fps trace while scrolling a 500-item fixture library with playback running.
6. Per phase, a commit or PR summary listing deviations. I post the summary here after each merge.
