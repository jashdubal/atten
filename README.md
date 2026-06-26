<p align="center">
  <img src="Sources/Atten/Resources/AttenIcon.svg" width="92" alt="Atten icon">
</p>

<h1 align="center">Atten</h1>

<p align="center">
  Natural text-to-speech that runs entirely on your computer.<br>
  No cloud. No subscription. No API key.
</p>

<p align="center">
  <a href="https://github.com/jashdubal/atten/releases/latest/download/Atten-macOS-arm64.dmg"><strong>Download for Mac</strong></a>
  ·
  <a href="https://github.com/jashdubal/atten/releases/latest/download/Atten-Windows-x64.zip"><strong>Download for Windows</strong></a>
  ·
  <a href="https://jashdubal.github.io/atten/">Website</a>
  ·
  <a href="#command-line">Command line</a>
</p>

<p align="center">
  <a href="https://github.com/jashdubal/atten/releases/latest/download/Atten-macOS-arm64.dmg"><img src="https://img.shields.io/github/downloads/jashdubal/atten/Atten-macOS-arm64.dmg?style=flat-square&amp;label=DMG%20downloads&amp;labelColor=0a101b&amp;color=197f99" alt="Total Atten DMG downloads"></a>
  <a href="https://github.com/jashdubal/atten/releases/latest/download/Atten-Windows-x64.zip"><img src="https://img.shields.io/github/downloads/jashdubal/atten/Atten-Windows-x64.zip?style=flat-square&amp;label=Windows%20downloads&amp;labelColor=0a101b&amp;color=197f99" alt="Total Atten Windows downloads"></a>
</p>

<p align="center">
  <sub>Free and open source · macOS 14+ Apple Silicon · Windows x64 preview</sub>
</p>

<p align="center">
  <img src="docs/assets/atten_screenshot.png" alt="Atten local text-to-speech studio" width="960">
</p>

## Local speech, without the setup

Atten is a local voice studio powered by the bundled
[Kokoro 82M](https://huggingface.co/hexgrad/Kokoro-82M) model. Your text and
generated audio stay on your computer, and the complete engine works offline after
installation.

- Create MP3 or WAV audio with 37 voices
- Preview voices, speed, format, and acceleration settings in the Playground
- Keep projects and exports organized in one native app
- Import text, regenerate previous work, and export anywhere
- Use the compatible CLI for scripts and automation

## Install

### macOS

1. **[Download the latest DMG](https://github.com/jashdubal/atten/releases/latest/download/Atten-macOS-arm64.dmg).**
2. Open it and drag **Atten** into **Applications**.
3. Launch Atten and start generating speech—everything required is included.

Atten currently requires an Apple Silicon Mac running macOS 14 or newer. The
release is ad-hoc signed and not yet notarized. If macOS blocks the first launch,
Control-click Atten, choose **Open**, then confirm. See the
[installation notes](DEPLOYMENT.md#user-installation-and-gatekeeper) for the
alternative Privacy & Security flow and download verification.

### Windows

1. **[Download the Windows x64 preview](https://github.com/jashdubal/atten/releases/latest/download/Atten-Windows-x64.zip).**
2. Extract the ZIP.
3. Run **Atten.Windows.exe**.

The Windows package uses CPU execution and works on any supported x64 Windows
10/11 machine. CUDA-aware backend support is available in the codebase and can
be packaged with `scripts/build-windows.ps1 -BackendFlavor cuda`, but public
release automation currently publishes the CPU preview package. The Windows app
is a preview while installer signing, MSIX packaging, and UI parity work
continue.

## Command line

The original local commands remain available for automation:

```bash
bin/tts "Living the dream"
bin/tts -f README.md -v bf_emma -s 1.1 --format wav --play
bin/tts "Hello" --filename greeting --silent
bin/play --latest
```

Machine-readable output is supported too:

```bash
bin/tts --list-voices --json
bin/tts --backend-info --device auto --json
bin/tts "Hello" --device cpu --json
bin/tts "Hello" --device auto --json
```

`--device auto` selects Metal/MPS on macOS when available, CUDA on Windows/Linux
when PyTorch can use it, and CPU otherwise. Explicit `--device cuda` and
`--device mps` fail loudly if the requested accelerator is unavailable.

Run `bin/tts --help` for every option, or browse the [voice catalog](VOICES.md).

## Develop locally

### macOS app

You will need an Apple Silicon Mac with macOS 14+, Xcode 16 with Swift 6,
Python 3.12, and [`uv`](https://docs.astral.sh/uv/).

```bash
bin/setup-macos
bin/atten
```

The development setup downloads roughly 350 MB of model weights. Published
DMGs already include the pinned model and do not require Python or Homebrew.

Build and open a development app bundle:

```bash
scripts/build-app-macos
open .build/Atten.app
```

Or work on the Swift package directly:

```bash
swift build
swift run Atten
```

The development app uses the repository's backend environment. To use a
backend elsewhere, set `ATTEN_BACKEND_ROOT=/path/to/offline-tts`.

### Windows app

You will need Windows 10 1809+ or Windows 11 x64, Visual Studio 2022 with
Windows App SDK tooling, .NET 10 SDK, Python 3.12, `uv`, and PyInstaller.

```powershell
uv sync --frozen --group release --no-editable
dotnet build apps/windows/Atten.Windows/Atten.Windows.csproj -c Debug -r win-x64
```

Build a Windows preview package on Windows:

```powershell
scripts/build-windows.ps1 -BackendFlavor cpu
scripts/build-windows.ps1 -BackendFlavor cuda
```

See [Windows port notes](docs/WINDOWS.md) for packaging status and remaining
production-release work.

## Test

```bash
swift test
python3 -m unittest discover -s tests -v
swift build -c release
```

## Privacy and storage

- Synthesis is local and requires no account, credentials, or internet access.
- macOS project metadata lives in `~/Library/Application Support/Atten`.
- Windows project metadata lives in `%LOCALAPPDATA%\Atten`.
- Generated audio defaults to the `Exports` folder inside the platform app-data directory.
- Existing audio under the repository's `outputs/` folder is discovered in place.

See the [architecture notes](docs/ARCHITECTURE.md) for implementation details
and [deployment guide](DEPLOYMENT.md) for release packaging and verification.

## License

Atten is available under the [GNU GPL v3 or later](LICENSE).
