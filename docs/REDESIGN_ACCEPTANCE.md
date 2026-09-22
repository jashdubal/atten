# Redesign acceptance report

The redesign implementation is integrated on `main` after PR #42.

## Automated evidence

- `swift test`: 197 tests passed.
- `swift build -c release`: passed.
- `git diff --check`: passed.
- `plutil -lint macOS/Info.plist`: passed.
- Windows XAML parsing: passed with `xmllint`.

## Implemented areas

- Home discovery, recent listening and library handoff (#27).
- Library cover shelf, truthful filters, search and import states (#28).
- Audio-first Now Playing for book and Studio audio (#29).
- Centered reader canvas with collapsible tools (#30).
- Safe Zen mode restoration and reduced-motion behavior (#31).
- Studio creation workflow and shared playback handoff (#32).
- Shared motion and interaction feedback (#33).
- Unified import, narration, generation and download status feedback (#34).
- Windows shell/Studio/player refresh and explicit macOS-only parity gaps (#35).

## Environment limitations

- Python backend tests could not collect because the local environment lacks
  `numpy`.
- Windows build and packaged-app checks could not run because this environment
  has no `dotnet`, `pwsh`, or Windows host. The exact commands and manual
  checks remain in `docs/WINDOWS.md`.
- Screenshot matrix, VoiceOver, media-key, and full manual visual acceptance
  still require a macOS GUI test session; no automated screenshot evidence is
  claimed here.
