"""Ways to get an approved message out of the outbox and in front of the student."""

from __future__ import annotations

import shutil
import subprocess
from pathlib import Path


def copy_to_clipboard(text: str) -> bool:
    """Best-effort clipboard copy on macOS / Linux / Windows. Returns False if no tool is available."""
    for cmd in (["pbcopy"], ["wl-copy"], ["xclip", "-selection", "clipboard"], ["xsel", "--clipboard", "--input"], ["clip"]):
        if shutil.which(cmd[0]):
            try:
                subprocess.run(cmd, input=text.encode("utf-8"), check=True)
                return True
            except (OSError, subprocess.CalledProcessError):
                continue
    return False


def append_to_file(text: str, path: Path, header: str = "") -> None:
    path = Path(path).expanduser()
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as fh:
        if header:
            fh.write(f"--- {header}\n")
        fh.write(text.rstrip() + "\n\n")
