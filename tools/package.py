#!/usr/bin/env python3
"""Assembles a Frequency release zip with the correct install layout.

Usage:
    python tools/package.py <build_output_dir>

<build_output_dir> is the directory containing the compiled Frequency.dll
(e.g. native/build/Release). fmod.dll is expected next to it (the CMake
build copies it there automatically).
"""

from __future__ import annotations

import shutil
import sys
import zipfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent

CET_FILES = [
    "init.lua",
    "config.json",
    "groups.json",
    "metadata.v1.template.json",
    "metadata.v2.template.json",
    "README.md",
    "LICENSE",
]
CET_DIRS = ["modules", "docs", "radios"]


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 1

    build_dir = Path(sys.argv[1])
    dll = build_dir / "Frequency.dll"
    fmod = build_dir / "fmod.dll"

    for required in (dll, fmod):
        if not required.is_file():
            print(f"error: {required} not found")
            return 1

    out_zip = REPO_ROOT / "Frequency-release.zip"
    if out_zip.exists():
        out_zip.unlink()

    with zipfile.ZipFile(out_zip, "w", zipfile.ZIP_DEFLATED) as zf:
        cet_root = f"bin/x64/plugins/cyber_engine_tweaks/mods/Frequency"
        native_root = "red4ext/plugins/Frequency"

        for name in CET_FILES:
            zf.write(REPO_ROOT / name, f"{cet_root}/{name}")

        for dirname in CET_DIRS:
            for path in sorted((REPO_ROOT / dirname).rglob("*")):
                if path.is_file():
                    rel = path.relative_to(REPO_ROOT).as_posix()
                    zf.write(path, f"{cet_root}/{rel}")

        zf.write(dll, f"{native_root}/Frequency.dll")
        zf.write(fmod, f"{native_root}/fmod.dll")

    print(f"wrote {out_zip}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
