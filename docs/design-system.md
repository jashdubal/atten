# Atten design system

Atten draws with a small, closed set of tokens and components. This is the
reference for what they are and the rules that keep the app looking like one
thing. It does not repeat the rationale in `docs/ui-overhaul-plan.md` or the
phase-by-phase history in `docs/REDESIGN_ACCEPTANCE.md`.

## Principles

1. **Things with a voice glow.** Chrome — the sidebar, toolbars, buttons — is
   nearly colorless. Color and light come only from content (covers, the
   ambient tint) and active audio (playing, generating). `AttenColor.signal`
   is reserved for voice-live states: playing, generating, the current word,
   the primary button, a focus ring. Nowhere else.
2. **Library is the place; Create is a verb.** The Library is where books
   live; Create is a flow you pass through, not a destination with its own
   identity.
3. **Ask only for decisions that are expensive to reverse.** Voice is
   expensive to change (it means regenerating audio), so Atten asks. Speed
   and export format are cheap to change later, so Atten doesn't ask for them
   up front.
4. **Show knowledge, not instructions.** No help text or subtitles explaining
   what a control does. Show the estimated duration, the generation time, the
   per-sentence progress — real state, not a caption.
5. **Feel:** calm, precise, a "Vision Pro app on a Mac." No neon, no
   cyberpunk, no sparkle icons, no gradient-filled text, no glow outside
   voice-live states, no pure black, no violet/"AI purple." No glass on
   content cards. No dashed drop zones. No duplicated information on a
   screen.

## Tokens

All of it lives in `Sources/Atten/DesignSystem.swift` and
`Sources/Atten/ThemePalette.swift`. Views only ever reach for these — never a
raw hex, `.black`, `.white`, or `Color(red:...)`. `NoRawColorTests` enforces
this for every file in `Sources/Atten` except the token files themselves and
the Reader (`Reader*.swift`, `BookReaderView.swift`), which draws the page in
its own content palette, not chrome.

### Color — `AttenColor`

Every role is a light/dark pair defined once in `AttenPalette` (in
`ThemePalette.swift`) and resolved through AppKit's dynamic `NSColor`, so a
view that names a role gets the right side of the pair for free — there is
nothing to observe. Roles: `bg`, `surface1`, `glass`, `hairline`, `text1/2/3`,
`signal`, `signalInk`, plus the semantic aliases used across most screens
(`surface`, `surfaceElevated`, `textPrimary`, `accent`, `destructive`, and so
on — all of them resolve to the same `AttenPalette`). `AttenColor.ambient` is
the one color that isn't fixed: it's the tint taken from whatever is playing,
set through `AttenAmbient` and checked at runtime by `AmbientContrast` so
text over it never drops below WCAG minimums.

`AttenColor.voice(hue:)` and `AttenColor.cover(_:)` are the two places a
color is allowed to come from content (a voice's hue, a generated cover) —
covers keep their color in both appearances, because they're content.

Contrast is enforced by `ThemeTests.testThePaletteIsReadableInBothAppearances`
and `PaletteAmbientContrastTests`: body text ≥ 4.5:1, large/label/accent text
≥ 3:1, both against the fixed palette and against the worst-case sampled
`ambient` composite, in both appearances.

### Spacing — `AttenSpacing`

Eight fixed steps: 4, 8, 12, 16, 24, 32, 48, 64 (`xxs` through `xxxl`, plus
`page` = 48 for the gutter a page of content keeps from the window edge). A
gap that isn't one of these is a gap nobody chose.

### Radius — `AttenRadius`

`small` (6), `control` (10), `card` (14), `panel` (20), `cover` (8, softer so
a grid of covers reads as objects), `pill` (999, fully rounded). Nested
shapes are **concentric**: `AttenRadius.concentric(outer:padding:)` gives the
inner shape `outer - padding`, so the gap between two curves is even all the
way round — that's what makes a button look intentional inside its card
rather than pinched.

### Motion — `AttenMotion`

Two springs, both stiffness/damping tuned so nothing bounces:

- `.small` (400/34) — a control, a chip, a row.
- `.large` (260/30) — a panel, a sheet, the player opening.

Duration fades: 120ms hover, 200ms state change, 800ms for the ambient tint
(light moving, not an event, so it's slow on purpose). Only transform,
opacity and blur are animated — never layout.

`AttenMotion.animation(_:reduceMotion:)` and `.transitionAnimation` are the
only way a screen should reach for these: pass `attenReduceMotion` from the
environment (never `accessibilityReduceMotion`, which only the window root
reads, so the `ATTEN_QA_REDUCE_MOTION` override reaches every view; the same
goes for `attenReduceTransparency`), and under Reduce Motion every spring becomes a 150ms
fade (`reducedFade`) or, for a state-only change, no animation at all — the
state still changes, it just doesn't animate getting there.

### Type — `AttenTypography` / `AttenTextStyle`

One scale: `display` (34), `title1` (28), `title2` (22), `body` (15),
`callout` (13), `label` (11, monospaced, uppercase, tabular digits — for
metadata that shouldn't jitter as it counts), `reading` (18/29, New York
serif, for prose someone reads rather than scans). Apply a step with
`.attenText(_:)`, which also sets tracking, line height and case — don't set
`.font` directly with one of these.

## Components

- **Buttons** (`Buttons.swift`) — three kinds and no others:
  - `AttenPrimaryButtonStyle`: the one thing a screen is for. Signal-filled,
    40pt, at most one per screen. When disabled, its fill dims to 40% opacity
    and its label turns `text1`, so the label still reads at 3:1 on the dimmed
    fill; it shows the reason as text underneath rather than leaving a puzzle.
  - `AttenSecondaryButtonStyle`: glass, 32pt, for a real action that isn't
    the point of the screen.
  - `AttenTertiaryButtonStyle`: text only (`text2` → `text1` on hover), for
    toolbars and the actions around a thing.
  - An icon that's a hit target rather than something styled to look like a
    button (a transport glyph, a cover) uses `.plain` instead.
  - All three draw their own focus ring (`attenFocusRing`) rather than using
    the system one, because a `ButtonStyle` never learns whether its button
    has keyboard focus.
- **Glass** (`Glass.swift`) — chrome only: the sidebar, the mini player, a
  sheet or popover. Never content — a card of books is not glass. At most
  three live materials on screen at once, because a material is expensive.
  Under Reduce Transparency, `.attenGlass` falls back to an opaque
  `surface1` with the same hairline edge.
- **Elevation** (`attenElevated`, `AttenElevation`) — a uniform hairline plus
  a small shadow (radius ≤ 6, opacity ≤ 0.10). `.raised` is the default for a
  card or panel; `.floating` is for something over everything else, like a
  popover.

## Motion, transparency and keyboard

- **Reduce Motion:** every spring collapses to a 150ms fade; a state-only
  change (not an insertion/removal) becomes instant instead, so the new
  state is still communicated without a distracting fade. No blur-on-distance
  and the ambient field stops animating.
- **Reduce Transparency:** every `.attenGlass` surface becomes opaque
  `surface1`.
- **Keyboard:** every control that isn't a native `Button`/`Toggle`/`Slider`
  still exposes accessible focus and an `.accessibilityLabel`. The one
  app-wide focus ring (`AttenFocusRing`) only appears after a real keyboard
  interaction — not merely because the system's Full Keyboard Access
  auto-focused the first control at launch.
- **Shortcuts:** Space play/pause, ⌘N new, ⌘I import, ⌘↩ generate, ←/→ skip
  15s (in the Read-Along player), ⌘F search the Library. The Library's ⌘F is
  only in the view hierarchy on the shelf page, and the Reader mounts its own
  ⌘F only while it's on screen, so the two never contend for the same key.
  ⌘D bookmarks in both the Reader (the page) and the Read-Along player (the
  sentence being spoken); each mounts it only while on screen, and the two
  are never on screen together.
  See Settings → Shortcuts for the full list.

## The don'ts

- No raw hex, `.black`, `.white`, or ad hoc `Color(red:...)` outside the
  token files and the Reader.
- No glass on content — only on chrome that floats over it.
- No more than one primary button per screen.
- No help/subtitle text explaining a control; show real state instead.
- No neon, cyberpunk, sparkle icons, gradient-filled text, glow outside
  voice-live states, pure black, or violet/"AI purple."
- No dashed drop zones.
- No duplicated information on one screen.
- No layout animation — only transform, opacity and blur.
