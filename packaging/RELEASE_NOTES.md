Atten is a fully offline, Apple Silicon-native text-to-speech studio for macOS
14 and newer. This release includes its Python 3.12 runtime, Kokoro, eSpeak NG,
all supported voices, and the pinned Kokoro-82M model. No separate Python,
Homebrew, model download, account, or network connection is required after the
DMG is downloaded.

## Install

1. Download `Atten-macOS-arm64.dmg` and compare its SHA-256 digest with
   `SHA256SUMS.txt`.
2. Open the DMG and drag Atten to Applications.
3. This release is ad-hoc signed, not Apple-notarized. On first launch,
   Control-click Atten and choose **Open**. If macOS still blocks it, use
   **System Settings → Privacy & Security → Open Anyway**.

Do not remove quarantine attributes. Future releases can migrate to Developer
ID signing and notarization without changing the stable download URL.

Source, license notices, the SPDX dependency manifest, and GitHub provenance
attestations are published beside the DMG.

## macOS improvements in this release

Atten for macOS now matches the Windows app's Hugging Face model library: a
new **Models** page searches the Hub as you type, filters by language and by
installed/available, and sorts by downloads, stars, size, provider, or name.
Downloads are resumable, with pause/cancel/delete, live progress, and state
that survives an app restart. Every downloaded model adds a matching voice to
Studio, Playground, and Voices. A new player bar at the bottom of every page
adds seek, play/pause (⌥Space), and close.

Atten now checks GitHub for new releases on launch and via a manual refresh
button in the sidebar, and can download, verify, and install an update in
place on your approval. A subtle GitHub mark in the sidebar links back to
this repository.

## Windows improvements in this release

Atten for Windows gains live Hugging Face model discovery and search, with
filtering by language and sorting by downloads, stars, size, or provider.
Downloads are now resumable, with pause/cancel controls, live speed and ETA,
and state that persists across app restarts.

This release also adds multilingual neural engine support (XTTS-v2,
Kokoro-82M, GGUF, MMS-TTS), including Arabic, German, Spanish, French,
Italian, Portuguese, Russian, Turkish, Dutch, Polish, Japanese, Chinese, and
Hindi voices, plus an integrated audio player bar with seek, play/pause, and
auto-play when generation completes.

## Windows installation

Download `Atten-Windows-x64-Setup.exe` and run it. The guided installer checks
that the computer has 64-bit Windows 10 version 1809 or newer (or Windows 11),
8 GB RAM, and 4 GB free disk space before installation. It includes the local
speech engine, Kokoro model, Python runtime, .NET runtime, and Windows App SDK;
no separate dependency installation or internet connection is needed after the
installer is downloaded. The public Windows build uses CPU inference.
