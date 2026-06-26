# Windows port

The Windows app lives in `apps/windows/Atten.Windows` and is a native WinUI 3
frontend that talks to the same Python backend JSON protocol as the macOS app.

## Development

Requirements on a Windows 11 x64 machine:

- Visual Studio 2022 with Windows App SDK tooling
- .NET 10 SDK
- Python 3.12
- `uv`
- PyInstaller

From the repository root:

```powershell
uv sync --frozen --group release --no-editable
dotnet build apps/windows/Atten.Windows/Atten.Windows.csproj -c Debug -r win-x64
```

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

The script publishes the WinUI app, builds the Windows PyInstaller backend,
stages the Kokoro 82M model, copies the shared voice catalog, and produces
`.build/windows-artifacts/Atten-Windows-x64.zip` for CPU builds or
`.build/windows-artifacts/Atten-Windows-x64-CUDA.zip` for CUDA builds.

## Current status

The first Windows scaffold includes:

- Studio generation through the Python backend
- Shared `resources/voices.json`
- Project/settings storage under `%LOCALAPPDATA%\Atten`
- Backend status probing
- MP3/WAV playback through Windows media APIs
- Explorer reveal for generated output

Still required before a production Windows release:

- Full parity polish for Playground, Voices, Projects, Exports, and Settings
- File/folder picker wiring
- MSIX or signed installer generation
- Windows CI and CUDA hardware smoke tests
- App icon assets and release signing
