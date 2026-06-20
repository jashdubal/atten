# Third-party notices

Atten is distributed under GPL-3.0-or-later. The release bundle contains the
following major third-party components. Exact resolved versions and download
locations are recorded in `Atten-sbom.spdx.json` and `uv.lock`.

- **Kokoro 0.9.4** — Apache-2.0; Copyright (c) Kokoro contributors.
- **Kokoro-82M model and voices** — Apache-2.0; created by the Kokoro model
  contributors and distributed from `hexgrad/Kokoro-82M`.
- **eSpeak NG** (through `espeakng-loader` 0.2.4) — GPL-3.0-or-later.
- **phonemizer-fork 3.3.2** — GPL-3.0-or-later.
- **PyInstaller 6.14.2** — GPL-2.0-or-later with the PyInstaller bootloader
  exception.
- **Python 3.12** — Python Software Foundation License.
- **PyTorch 2.8.0** — BSD-3-Clause.
- **spaCy and en_core_web_sm 3.8.0** — MIT.
- **Swift and SwiftUI runtime components** — Apple and Swift project licenses.

License files discovered in the locked Python environment are copied into
`Atten.app/Contents/Resources/Licenses/Python`. Nothing in this notice changes
the license terms granted by an upstream project.

Source and rebuild information are in `CORRESPONDING_SOURCE.md` and the
`Atten-corresponding-source.tar.gz` asset published with each release.
