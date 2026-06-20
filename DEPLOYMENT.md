# Atten deployment

Atten is distributed as one fully offline, Apple Silicon DMG through GitHub
Releases. End users do not install Python, Kokoro, eSpeak NG, Homebrew, `uv`, or
model files. The stable website download target is:

<https://github.com/jashdubal/atten/releases/latest/download/Atten-macOS-arm64.dmg>

## Release architecture

The DMG contains `Atten.app` with four relevant layers:

- `Contents/MacOS/Atten`: the native SwiftUI application.
- `Contents/Resources/Backend/atten-backend/`: a PyInstaller 6 one-directory helper with
  Python 3.12, Kokoro 0.9.4, PyTorch, SoundFile, spaCy, eSpeak NG, and all
  transitive runtime dependencies.
- `Contents/Resources/Models/Kokoro-82M/`: pinned model config and weights,
  plus only the 37 voice packs exposed by Atten.
- `Contents/Resources/Licenses/`: GPL, model attribution, corresponding-source
  information, and Python dependency license files.

The app launches the helper directly. It sets `ATTEN_MODEL_ROOT`,
`HF_HUB_OFFLINE=1`, `PYTHONNOUSERSITE=1`, and
`PYTHONDONTWRITEBYTECODE=1`, and replaces `PATH` with system-only locations.
The packaged backend therefore cannot fall back to a user Python environment or
Hugging Face cache. Repository development still uses `ATTEN_BACKEND_ROOT` and
`cli.py`.

## Maintainer prerequisites

- Apple Silicon Mac running macOS 14 or newer.
- Xcode 16 or newer with the Swift 6 toolchain.
- Python 3.12 and `uv` 0.7.2 or a compatible newer release.
- Internet access while staging locked wheels and the pinned Kokoro snapshot.
- `hdiutil`, `codesign`, `lipo`, `otool`, `sips`, and `iconutil` from macOS.

The release build uses an isolated Python environment under `.build`; it does
not replace the repository `.venv`. Dependencies are resolved exclusively from
`uv.lock`.

## Local release build

Ensure `macOS/Info.plist` has the intended version and the worktree is clean:

```bash
swift test
python3.12 -m unittest discover -s tests -p 'test_*.py' -v
scripts/build-release --version 0.2.0
```

To reuse an already downloaded pinned model snapshot:

```bash
ATTEN_MODEL_SOURCE="$HOME/.cache/huggingface/hub/models--hexgrad--Kokoro-82M/snapshots/f3ff3571791e39611d31c381e3a41a3af07b4987" \
  scripts/build-release --version 0.2.0
```

Set `RUN_SYNTHESIS_SMOKE=1` to generate MP3 and WAV samples for every supported
language from the packaged helper with an empty home directory and offline
environment. `ALLOW_DIRTY=1` is available only for local packaging validation;
never use it for a published build.

Artifacts are written to `.build/release-artifacts/`:

- `Atten-macOS-arm64.dmg`
- `SHA256SUMS.txt`
- `Atten-corresponding-source.tar.gz`
- `Atten-sbom.spdx.json`

The build fails for a missing helper, model, voice, license, non-arm64 Mach-O,
non-portable dynamic-library path, embedded development path, invalid code
signature, or a DMG at or above GitHub's 2 GiB file limit.

## GitHub release process

1. Update `CFBundleShortVersionString` in `macOS/Info.plist` and merge through
   CI. The CI workflow runs all Swift/Python tests and a release Swift build.
2. Create and push a matching annotated tag:

   ```bash
   git tag -a v0.2.0 -m "Atten 0.2.0"
   git push origin v0.2.0
   ```

3. `.github/workflows/release.yml` checks that the tag and plist versions
   match, packages from clean staging directories on `macos-14`, runs the full
   offline synthesis smoke test, creates GitHub provenance attestations, and
   publishes all four assets.
4. Download the published assets, verify the checksum, mount the DMG, drag the
   app to Applications, and complete the manual release checklist below.

Asset names must remain stable. GitHub’s `/releases/latest/download/...` URL
depends on `Atten-macOS-arm64.dmg` being unchanged across releases.

## Manual release checklist

- Inspect the app at 820×600, 1080×700, and 1440×900 in System, Light, and Dark
  appearances, including Reduce Motion and Reduce Transparency.
- Verify keyboard-only sidebar navigation, focus rings, VoiceOver labels, hover,
  selection, disabled, loading, success, error, empty, missing-file, long-text,
  and long-filename states.
- Generate and cancel speech; import and drop text; preview/play audio; persist,
  duplicate, regenerate, export, reveal, rename, and delete projects/files.
- Test with Wi-Fi disabled and no Python executable available through `PATH`.
- Run `codesign --verify --deep --strict --verbose=2 /Applications/Atten.app`.
- Confirm Gatekeeper presents the expected unnotarized-app path described below.

## User installation and Gatekeeper

Atten requires Apple Silicon and macOS 14 or newer. Open the DMG and drag Atten
to Applications. Releases are ad-hoc signed but intentionally not Developer ID
signed or notarized, so first launch can be blocked by Gatekeeper. Control-click
Atten, choose **Open**, then confirm. If that option is unavailable, open
**System Settings → Privacy & Security** and choose **Open Anyway** for Atten.

Never tell users to run `xattr` or remove quarantine metadata. Those commands
weaken a macOS safety boundary and conceal whether the downloaded file is the
one the user intended to open.

Uninstall by quitting Atten and moving it from Applications to Trash. Optional
user data can be removed from `~/Library/Application Support/Atten`; generated
audio stored elsewhere is not removed automatically.

## Integrity and provenance

Verify a download from the directory containing all release assets:

```bash
shasum -a 256 -c SHA256SUMS.txt
gh attestation verify Atten-macOS-arm64.dmg --repo jashdubal/atten
```

`MODEL_MANIFEST.json` inside the app records each bundled model/voice digest and
the pinned upstream revision. The SPDX SBOM records the locked Python graph.

## Website copy

Recommended concise copy:

> Download Atten for Apple Silicon Macs running macOS 14 or newer. The DMG
> includes the complete offline speech engine and voices—no Python, model
> download, account, or internet connection required. This release is not yet
> Apple-notarized; follow the first-launch instructions on the download page.

Use the stable URL at the top of this document. Also link the GitHub Release so
users can access checksums, provenance, source, notices, and release notes.

## Licensing and source obligations

Atten is GPL-3.0-or-later because the distributed helper includes eSpeak NG and
phonemizer-fork. Every release must include the root `LICENSE`, third-party and
model notices, the corresponding-source archive, locked dependency metadata,
and the SPDX SBOM. Do not publish a DMG if any of those assets is absent.

The source archive is generated from the exact release commit. Upstream source
locations and the three-year physical-source offer are documented in
`legal/CORRESPONDING_SOURCE.md`.

## Troubleshooting

- **“Damaged” or cannot be opened:** re-download from the GitHub Release,
  validate `SHA256SUMS.txt`, then use the documented Control-click/Open flow.
- **Backend or model missing:** reinstall from the official DMG. Do not copy the
  helper or model directory between releases.
- **Generation fails offline:** confirm the complete app was copied from the
  mounted DMG and check available disk space and output-folder permissions.
- **Permission denied while exporting:** choose another writable folder in
  Settings → Storage; Atten never requires Full Disk Access.
- **Maintainer build cannot find a voice:** ensure the model source is revision
  `f3ff3571791e39611d31c381e3a41a3af07b4987` and rerun `scripts/prepare-model`.

## Future signed distribution

When an Apple Developer account is available, replace ad-hoc signing with a
Developer ID Application identity, add hardened-runtime entitlements, submit
the DMG or app for notarization, staple the ticket, and validate with `spctl`.
Keep the DMG filename and GitHub stable URL unchanged. Automatic updates can be
added later with a signed update feed; do not ship an updater before Developer
ID signing and release-key management are established.
