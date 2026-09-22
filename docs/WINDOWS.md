# Windows port

The Windows app lives in `apps/windows/Atten.Windows` and is a native WinUI 3
frontend that talks to the same Python backend JSON protocol as the macOS app.
Release builds use self-contained WinUI deployment, so the Windows App SDK is
shipped with the app instead of being assumed to exist on the user's machine.

## Development

Requirements on a Windows 11 x64 machine:

- Visual Studio 2022 with Windows App SDK tooling
- .NET 8 SDK
- Python 3.12
- `uv`
- PyInstaller
- Inno Setup 6 (only to compile the user-facing installer)

From the repository root:

```powershell
uv sync --frozen --group release --no-editable
dotnet build apps/windows/Atten.Windows/Atten.Windows.csproj -c Debug -r win-x64
```

The Windows shell intentionally covers the features that are implemented in
`apps/windows/Atten.Windows`: Create (Studio and Playground), then Manage
(Voices, Projects, Exports, and Settings & Models). Studio writes through the
existing local backend, Voices uses the shared catalog, Projects and Exports
use the existing local storage/output folder, and Settings & Models exposes
the existing engine and Hugging Face download controls. Home, Library, and
Reader are not Windows features in this port; those are macOS-only surfaces
and are not represented by placeholder Windows navigation items.

The shell follows the Windows appearance setting with semantic light/dark
surfaces, leaves caption colours to Windows in High Contrast mode, and keeps
the window above a usable Studio size at common display scales. `Ctrl+Enter`
starts generation and `Escape` cancels an active generation. The system
animation preference disables the app-owned progress animation; WinUI's
keyboard focus, tab order, text scaling, and built-in control accessibility
remain enabled. Long content scrolls instead of adding unsupported compact
features.

For development, set `ATTEN_BACKEND_ROOT` to the repository root so the app can
launch `cli.py`. Published builds embed the PyInstaller backend and staged
Kokoro model instead.

## Backend diagnostics

The backend exposes a machine-readable capability probe:

```powershell
python cli.py --backend-info --device auto --json
python cli.py "Hello from Windows" --device cpu --json
python cli.py "Hello from CUDA" --device cuda --json
```

Use `--device auto` in the app by default. It selects CUDA on Windows when the
installed PyTorch build can use CUDA, otherwise it falls back to CPU.

## Packaging

Build a CPU package:

```powershell
scripts/build-windows.ps1 -BackendFlavor cpu
```

Build a CUDA-capable package from an environment with a CUDA-enabled PyTorch
wheel:

```powershell
scripts/build-windows.ps1 -BackendFlavor cuda
```

The script publishes the self-contained WinUI app, builds the Windows
PyInstaller backend, stages the Kokoro 82M model, runs the packaged backend's
offline capability check, runs the app's two startup checks
(`--validate-install` for resources and backend, `--validate-launch` for the
main window itself), stages the Visual C++ redistributable, and creates an Inno
Setup installer. Both startup checks use `Start-Process -Wait`: `Atten.Windows.exe`
is a windowed executable, so PowerShell does not wait for it and `$LASTEXITCODE`
would report nothing about how it finished. It produces
`.build/windows-artifacts/Atten-Windows-x64-Setup.exe` for CPU builds or
`.build/windows-artifacts/Atten-Windows-x64-CUDA-Setup.exe` for CUDA builds.
The installer presents the end-user requirements before installation, blocks
unsupported 32-bit systems and computers with less than 8 GB RAM, checks for
4 GB free install space, and warns if less than 4 GB RAM is currently free for
model loading.

## Diagnosing a launch failure

Every launch appends to `%LOCALAPPDATA%\Atten\logs\startup.log`, and a crash
inside the app also shows a message box naming that file. The first line is
written by a module initializer, before any Windows App SDK type is touched, so
the log distinguishes the two ways Atten can fail to start:

- **The log has entries.** The app reached managed code; the logged exception
  says what went wrong.
- **The log is missing or empty after a launch attempt.** The process died in
  the loader before running any of Atten's code, which means a missing runtime
  dependency rather than an app bug. The installer ships the Visual C++
  redistributable for exactly this case.

## Current status

The supported Windows surface includes:

- Studio generation through the Python backend
- Playground, Voices, Projects, Exports, and Settings & Models shell sections
- Shared `resources/voices.json`
- Project/settings storage under `%LOCALAPPDATA%\Atten`
- Backend status probing
- MP3/WAV playback through Windows media APIs
- Explorer reveal for generated output
- Light/dark semantic resources, High Contrast hand-off, keyboard generation
  and cancellation, reduced-motion handling, and a DPI-safe minimum window
  size

The following are deliberately not claimed as Windows parity:

- macOS Home, Library, PDF/EPUB Reader, chapter narration, and reader focus
  mode
- File/folder picker wiring
- CUDA hardware smoke tests
- App icon assets and release signing

## Verification status

The repository authoring environment used for this change is not Windows and
does not have `dotnet` or `pwsh` available, so no Windows UI or packaging check
is being represented as passed. On a Windows 11 x64 machine, run these exact
checks before release:

```powershell
dotnet --info
dotnet build apps/windows/Atten.Windows/Atten.Windows.csproj -c Debug -r win-x64
scripts/build-windows.ps1 -BackendFlavor cpu
```

Then launch the staged executable with `--validate-install` and
`--validate-launch`, and manually check each supported navigation item,
generation/cancel (`Ctrl+Enter`/`Escape`), tab and keyboard focus, light and
dark appearance, Windows High Contrast, 100%/150%/200% display scaling, and
the Windows reduced-motion setting. Repeat the package check with
`-BackendFlavor cuda` only on a machine with a CUDA-enabled PyTorch wheel;
CUDA behavior is otherwise unverified here. These checks are also the exact
remaining evidence needed for the Windows-only portions of this issue.
