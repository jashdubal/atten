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

## Windows fixes in this release

Atten 0.2.2 and earlier installed correctly on Windows but never opened a
window. The published app was missing its own compiled XAML resources, so it
started, loaded the Windows App SDK, and then terminated while building its
main window, with no error shown. This release fixes that, and the build now
launches the real window on a Windows machine before an installer is
published, so the failure cannot ship again unnoticed.

The installer also now includes the Microsoft Visual C++ runtime the Windows
App SDK depends on, and Atten writes a startup log to
`%LOCALAPPDATA%\Atten\logs\startup.log` so any future launch problem can be
reported precisely.

## Windows installation

Download `Atten-Windows-x64-Setup.exe` and run it. The guided installer checks
that the computer has 64-bit Windows 10 version 1809 or newer (or Windows 11),
8 GB RAM, and 4 GB free disk space before installation. It includes the local
speech engine, Kokoro model, Python runtime, .NET runtime, and Windows App SDK;
no separate dependency installation or internet connection is needed after the
installer is downloaded. The public Windows build uses CPU inference.
