# -*- mode: python ; coding: utf-8 -*-

from pathlib import Path
from PyInstaller.utils.hooks import collect_all, copy_metadata


ROOT = Path(SPECPATH).resolve().parent
if not (ROOT / "cli.py").is_file():
    raise SystemExit(f"Could not locate Atten repository root from spec path: {SPECPATH}")
datas = []
binaries = []
hiddenimports = []

for package in (
    "espeakng_loader",
    "phonemizer",
    "misaki",
    "language_tags",
    "en_core_web_sm",
):
    package_datas, package_binaries, package_hiddenimports = collect_all(package)
    datas += package_datas
    binaries += package_binaries
    hiddenimports += package_hiddenimports

for distribution in ("en-core-web-sm", "espeakng-loader", "phonemizer-fork"):
    datas += copy_metadata(distribution, recursive=True)

a = Analysis(
    [str(ROOT / "cli.py")],
    pathex=[str(ROOT)],
    binaries=binaries,
    datas=datas,
    hiddenimports=hiddenimports,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=["tkinter", "pytest"],
    noarchive=False,
    optimize=1,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name="atten-backend",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,
    console=True,
    target_arch="arm64",
)

coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=False,
    name="atten-backend",
)
