# Corresponding source

Atten releases are GPL-3.0-or-later. The complete Atten source, release scripts,
dependency lock, and build configuration for a binary release are provided in
the `Atten-corresponding-source.tar.gz` asset attached to that GitHub Release.
The same revision is available at <https://github.com/jashdubal/atten>.

Rebuild the distributed application with `scripts/build-release` on Apple
Silicon macOS 14 or newer. `DEPLOYMENT.md` documents the exact toolchain and
release process. `uv.lock` identifies every Python source distribution and
wheel by URL and SHA-256 digest; `Atten-sbom.spdx.json` inventories the resolved
dependency graph.

Upstream source for GPL components is available from:

- eSpeak NG: <https://github.com/espeak-ng/espeak-ng>
- espeakng-loader 0.2.4: <https://pypi.org/project/espeakng-loader/0.2.4/>
- phonemizer-fork 3.3.2 source archive:
  <https://files.pythonhosted.org/packages/42/fa/9294d2f11890ca49d0bdac7a4da60cbe5686629bfd4987cae0ad75e051cc/phonemizer_fork-3.3.2.tar.gz>
- PyInstaller 6.14.2: <https://github.com/pyinstaller/pyinstaller/tree/v6.14.2>

To request a physical copy of corresponding source where required by the GPL,
open an issue at <https://github.com/jashdubal/atten/issues>. This offer is valid
for at least three years after the associated binary release.
