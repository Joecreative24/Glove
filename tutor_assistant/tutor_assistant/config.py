"""Configuration resolved from environment variables with sensible defaults."""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from pathlib import Path

DEFAULT_MODEL = "claude-opus-5"


def _expand(value: str | None) -> Path | None:
    if not value:
        return None
    return Path(os.path.expanduser(value))


@dataclass
class Settings:
    db_path: Path = field(
        default_factory=lambda: _expand(os.environ.get("TUTOR_DB"))
        or Path.home() / ".tutor_assistant" / "tutor.db"
    )
    model: str = field(default_factory=lambda: os.environ.get("TUTOR_MODEL", DEFAULT_MODEL))
    timezone: str = field(default_factory=lambda: os.environ.get("TUTOR_TIMEZONE", "Europe/London"))
    google_client_secret_file: Path | None = field(
        default_factory=lambda: _expand(os.environ.get("GOOGLE_CLIENT_SECRET_FILE"))
    )
    google_token_file: Path = field(
        default_factory=lambda: _expand(os.environ.get("GOOGLE_TOKEN_FILE"))
        or Path.home() / ".tutor_assistant" / "google_token.json"
    )

    def ensure_dirs(self) -> None:
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
