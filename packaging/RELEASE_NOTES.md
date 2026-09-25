# Atten 0.4.0 — a redesigned Atten for Mac

Atten is a fully offline, Apple Silicon-native text-to-speech studio for macOS
14 and newer. This release includes its Python 3.12 runtime, Kokoro, eSpeak NG,
all supported voices, and the pinned Kokoro-82M model. No separate Python,
Homebrew, model download, account, or network connection is required after the
DMG is downloaded.

- **Library, Create and the read-along player.** Your books and projects live
  in one Library with generated covers, search and filters. Create takes a
  draft from text to finished audio in one place. The player follows the text
  word by word as it reads.
- **Listen while it generates.** Playback starts as soon as the first sentence
  is ready, not when the whole book is done.
- **A faster engine.** The speech model loads once and stays ready, so each
  generation, preview and sample starts sooner.
- **Pronunciation and pauses.** Tell a book how to say a word, and choose a
  short, normal or long pause between paragraphs.
- **Chapters, bookmarks and a sleep timer.** Jump between chapters from the
  player, bookmark a place and find it again in the Reader, and fall asleep to
  a timer that fades out gently.
- **A generation queue.** Start another book while one is generating and it
  waits its turn. Pause, reorder or remove queued books, and get a notification
  when one finishes.
- **Reliability.** Very long books, damaged library files, a full disk and an
  engine that stops unexpectedly are all handled, with a clear message where
  something needs your attention.

## Install

1. Download `Atten-macOS-arm64.dmg` and compare its SHA-256 digest with
   `SHA256SUMS.txt`.
2. Open the DMG and drag Atten to Applications.
3. This release is not Apple-notarized, so macOS blocks the first launch with
   "Apple could not verify Atten is free of malware". Double-click Atten,
   dismiss the warning, then open **System Settings → Privacy & Security**,
   scroll to Security, and choose **Open Anyway**. You do this once. On
   macOS 15 and newer this is the only route; the older Control-click →
   **Open** shortcut no longer works for applications that are not notarized.

Do not remove quarantine attributes. Future releases can migrate to
notarization without changing the stable download URL.

Source, license notices, the SPDX dependency manifest, and GitHub provenance
attestations are published beside the DMG.

## Windows installation

Download `Atten-Windows-x64-Setup.exe` and run it. The guided installer checks
that the computer has 64-bit Windows 10 version 1809 or newer (or Windows 11),
8 GB RAM, and 4 GB free disk space before installation. It includes the local
speech engine, Kokoro model, Python runtime, .NET runtime, and Windows App SDK;
no separate dependency installation or internet connection is needed after the
installer is downloaded. The public Windows build uses CPU inference.
