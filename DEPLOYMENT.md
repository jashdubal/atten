# Atten deployment

Atten is distributed through GitHub Releases as a fully offline Apple Silicon
DMG and a fully offline Windows x64 installer. End users do not install Python,
Kokoro, eSpeak NG, Homebrew, `uv`, model files, .NET, or the Windows App SDK.
The stable download targets are:

<https://github.com/jashdubal/atten/releases/latest/download/Atten-macOS-arm64.dmg>

<https://github.com/jashdubal/atten/releases/latest/download/Atten-Windows-x64-Setup.exe>

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

### The persistent engine

Since 0.4.0 the app keeps one `atten-backend serve` process running rather than
starting the helper for every generation, so Kokoro loads once. It reads one
JSON request per line on stdin and answers with the same events as before, each
tagged with its request id, one request at a time.

- It starts with the first generation, preview or sample, and must print
  `ready` within 30 seconds.
- It exits when its stdin closes: after 10 minutes with no request, or when
  Atten quits. It finishes the segment it is on first.
- A cancel it has not honoured within 2 seconds gets it terminated. The next
  request, or a crash, starts a new one.
- A helper too old to serve is run once per generation, as before.
- MP3 export runs `atten-backend transcode` as a separate short-lived process.

Keeping the process alive needs no entitlements. Atten is not sandboxed, and
the helper is an ordinary child process signed with the hardened runtime and
no entitlements, like every other Mach-O in the bundle. For 0.4.0 an ad-hoc
build was re-signed with the hardened runtime and passed the smoke test below
with library validation relaxed and nothing else. That relaxation is only
needed because ad-hoc signatures carry no Team ID; a Developer ID signing
gives every file one Team ID, which satisfies library validation.

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

Ensure `macOS/Info.plist` has the intended version and the worktree is clean.
Store notarization credentials outside the repository using `xcrun notarytool
store-credentials`; pass only the profile name to the build:

```bash
export ATTEN_SIGNING_IDENTITY='Developer ID Application: Jashraj Dubal (BK6ZPY7AD9)'
export ATTEN_NOTARY_PROFILE='your-keychain-profile-name'
```

Then run:

```bash
swift test
python3.12 -m unittest discover -s tests -p 'test_*.py' -v
scripts/build-release --version 0.4.0
```

To reuse an already downloaded pinned model snapshot:

```bash
ATTEN_MODEL_SOURCE="$HOME/.cache/huggingface/hub/models--hexgrad--Kokoro-82M/snapshots/f3ff3571791e39611d31c381e3a41a3af07b4987" \
  scripts/build-release --version 0.4.0
```

Every build runs `scripts/smoke-packaged-backend --quick` against the packaged
helper with an empty home directory and offline environment. It starts
`serve`, sends two generate requests and cancels the second, checks each
event's request id and that the model loads once, runs a long-pause
generation, and transcodes an M4A to MP3. Set `RUN_SYNTHESIS_SMOKE=1` to also
generate MP3 and WAV samples for every supported language.

`ALLOW_DIRTY=1` is available only for local packaging validation; never use it
for a published build. Dirty candidates archive the actual working
source, including new nonignored files. `ATTEN_LOCAL_VALIDATION=1` explicitly
selects ad-hoc signing and skips notarization; never distribute those artifacts.
A normal release build signs all nested Mach-O components with hardened runtime
and timestamps, notarizes/staples the app, then signs/notarizes/staples the DMG.
Signing and notarization failures stop the build.

Artifacts are written to `.build/release-artifacts/`:

- `Atten-macOS-arm64.dmg`
- `SHA256SUMS.txt`
- `Atten-corresponding-source.tar.gz`
- `Atten-sbom.spdx.json`

The Windows job writes `.build/windows-artifacts/Atten-Windows-x64-Setup.exe`.
It embeds the self-contained WinUI runtime, PyInstaller speech backend, Kokoro
model, voice files, and notices. Its installer displays system requirements
before installation, requires 64-bit Windows 10 version 1809+ or Windows 11,
requires 8 GB installed RAM and 4 GB free disk, and warns when less than 4 GB
RAM is currently available for the model.

The build fails for a missing helper, model, voice, license, non-arm64 Mach-O,
non-portable dynamic-library path, embedded development path, invalid code
signature, or a DMG at or above GitHub's 2 GiB file limit.

## CI signing configuration

Configure these GitHub Actions secrets before tagging: `MACOS_CERTIFICATE_P12`
(base64 Developer ID certificate and private key), `MACOS_CERTIFICATE_PASSWORD`,
`APPLE_ID`, `APPLE_APP_PASSWORD`, and `APPLE_TEAM_ID`. The Mac job uses a temporary
keychain, imports the certificate, stores the `atten-ci` notarytool profile, and
removes the keychain after the job. Credentials must never enter source archives.
The workflow config is implemented; this local work did not configure remote secrets.

## GitHub release process

1. Update `CFBundleShortVersionString` in `macOS/Info.plist` and merge through
   CI. The CI workflow runs all Swift/Python tests and a release Swift build.
2. Create and push a matching annotated tag:

   ```bash
   git tag -a v0.4.0 -m "Atten 0.4.0"
   git push origin v0.4.0
   ```

3. `.github/workflows/release.yml` checks that the tag and plist versions
   match, packages from clean staging directories on `macos-14`, runs the full
   offline synthesis smoke test, creates GitHub provenance attestations, and
   publishes all four assets.
4. Download the published assets, verify the checksum, mount the DMG, drag the
   app to Applications, and complete the manual release checklist below. On a
   clean supported Windows VM, run the Windows installer and make one offline
   CPU generation before publishing.

Asset names must remain stable. GitHub’s `/releases/latest/download/...` URL
depends on `Atten-macOS-arm64.dmg` being unchanged across releases.

## Manual release checklist

- Inspect the app at its minimum 960×700, 1080×700, and 1440×900 in System, Light, and Dark
  appearances, including Reduce Motion and Reduce Transparency.
- Verify keyboard-only sidebar navigation, focus rings, VoiceOver labels, hover,
  selection, disabled, loading, success, error, empty, missing-file, long-text,
  and long-filename states.
- Generate and cancel speech; import and drop text; preview/play audio; persist,
  duplicate, regenerate, export, reveal, rename, and delete projects/files.
- Test with Wi-Fi disabled and no Python executable available through `PATH`.
- Run `codesign --verify --deep --strict --verbose=2 /Applications/Atten.app`.
- Run `xcrun stapler validate /Applications/Atten.app` and
  `spctl --assess --type execute --verbose=2 /Applications/Atten.app`.
- Verify a quarantined browser download on a clean Mac, then test the update
  path from the previous release. Signing verification alone does not cover this.
- Verify cancellation during synthesis and assembly, relaunch/resume, missing
  audio repair, regeneration, chapter seeking, and restored paused position.
- Complete VoiceOver, keyboard-only, media-key, reduced-motion, and sleep/wake
  playback checks. Record the host and results in the acceptance report.

## User installation and Gatekeeper

Atten requires Apple Silicon and macOS 14 or newer. Open the DMG and drag Atten
to Applications. New releases must pass Developer ID signing, notarization,
stapling, and downloaded-installation checks before publication. A signed but
unnotarized candidate does not satisfy this gate.

Previously published ad-hoc releases can require approval in **System Settings →
Privacy & Security → Open Anyway** after the first blocked launch. Keep that
legacy guidance attached to the specific old release, not to a verified
notarized release. Never instruct users to remove quarantine metadata.

The legacy app's self-quarantine repair is skipped when `AttenDistributionSigned`
is true. Signed update candidates must match `com.jashdubal.Atten`, team
`BK6ZPY7AD9`, and Apple's Developer ID requirement, and pass Gatekeeper assessment.
Pending metadata saves finish before an update swap is scheduled.

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

For a verified notarized release:

> Download Atten for Apple Silicon Macs running macOS 14 or newer. Add a book,
> prepare its audio, and listen offline. The DMG includes the speech engine and
> voices—no Python, account, or internet connection required after installation.

Do not describe the current local candidate as notarized until submission,
stapling, and downloaded-installation verification have passed.

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
  validate `SHA256SUMS.txt`, and verify the release signature; report the failure before bypassing Gatekeeper.
- **Backend or model missing:** reinstall from the official DMG. Do not copy the
  helper or model directory between releases.
- **Generation fails offline:** confirm the complete app was copied from the
  mounted DMG and check available disk space and output-folder permissions.
- **Permission denied while exporting:** choose another writable folder in
  Settings → Storage; Atten never requires Full Disk Access.
- **Maintainer build cannot find a voice:** ensure the model source is revision
  `f3ff3571791e39611d31c381e3a41a3af07b4987` and rerun `scripts/prepare-model`.

## Isolated interface validation

Set `ATTEN_DATA_DIRECTORY` to an empty directory before launching a development
bundle. Books, projects, and listening state use that directory; settings use
`Atten.Validation.<directory-name>`. Use a unique final directory name per test
run and a separate validation bundle identifier to isolate window restoration.
Never point a test reset at a real user's library.

## Candidate status

The September 2026 candidate uses the installed Developer ID identity and passes
deep signature verification and packaged offline synthesis. The notarytool
Keychain profile name is still needed to submit it. No candidate was published.
See [the acceptance report](docs/REDESIGN_ACCEPTANCE.md) for remaining gates.
