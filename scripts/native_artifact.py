"""Locate Moon's native artifact by what was built, not by the host OS."""
from pathlib import Path


def processlens_executable(root: Path) -> Path:
    folder = root / "_build/native/debug/build/cmd/processlens"
    # Moon 0.10.16 emits a .exe suffix on Linux too; older versions may not.
    for name in ("processlens.exe", "processlens"):
        candidate = folder / name
        if candidate.is_file():
            return candidate
    raise FileNotFoundError(f"Moon native processlens artifact not found in {folder}")
