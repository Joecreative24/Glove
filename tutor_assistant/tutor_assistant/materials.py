"""Materials index: tag HTML/Word resources by board + topic, then let the pipeline pick from them.

Two sources are supported:

* a local folder (files tagged via a `tags.json` sidecar or the filename convention
  `BOARD - topic one, topic two - Title.ext`), and
* a Google Drive folder (files tagged via the same name convention, or via `appProperties`
  `board` / `topics` set on the file).
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass
from pathlib import Path

from .db import Database
from .models import Material, SessionClassification, Student

SUPPORTED_SUFFIXES = {".html", ".htm", ".docx", ".doc", ".pdf", ".pptx", ".txt", ".md"}
NAME_PATTERN = re.compile(r"^\s*(?P<board>[^-]+?)\s*-\s*(?P<topics>[^-]+?)\s*-\s*(?P<title>.+?)\s*$")


@dataclass
class ParsedName:
    title: str
    board: str | None
    topics: list[str]


def parse_material_name(stem: str) -> ParsedName:
    """`AQA - past perfect, since vs for - Tense worksheet` -> board/topics/title."""
    m = NAME_PATTERN.match(stem)
    if not m:
        return ParsedName(title=stem.strip(), board=None, topics=[])
    topics = [t.strip() for t in m.group("topics").split(",") if t.strip()]
    return ParsedName(title=m.group("title"), board=m.group("board").strip() or None, topics=topics)


def _split_topics(value) -> list[str]:
    if value is None:
        return []
    if isinstance(value, list):
        return [str(t).strip() for t in value if str(t).strip()]
    return [t.strip() for t in str(value).split(",") if t.strip()]


# ---------------------------------------------------------------------------
# Local folder
# ---------------------------------------------------------------------------


def index_local_folder(db: Database, folder: Path, *, default_board: str | None = None) -> list[Material]:
    """Walk a folder and upsert every supported file into the materials table."""
    folder = Path(folder).expanduser().resolve()
    if not folder.is_dir():
        raise FileNotFoundError(f"{folder} is not a directory")
    sidecar: dict = {}
    tags_file = folder / "tags.json"
    if tags_file.exists():
        sidecar = json.loads(tags_file.read_text(encoding="utf-8"))

    indexed: list[Material] = []
    for path in sorted(folder.rglob("*")):
        if not path.is_file() or path.suffix.lower() not in SUPPORTED_SUFFIXES:
            continue
        rel = path.relative_to(folder).as_posix()
        parsed = parse_material_name(path.stem)
        tags = sidecar.get(rel) or sidecar.get(path.name) or {}
        material = db.upsert_material(
            title=tags.get("title") or parsed.title,
            location=str(path),
            source="local",
            board=tags.get("board") or parsed.board or default_board,
            topics=_split_topics(tags.get("topics")) or parsed.topics,
            kind=path.suffix.lower().lstrip("."),
            share_link=path.as_uri(),
        )
        indexed.append(material)
    return indexed


# ---------------------------------------------------------------------------
# Google Drive folder
# ---------------------------------------------------------------------------


class DriveMaterials:
    """Reads a Drive folder and creates 'anyone with the link can view' share links on demand.

    Requires the `google` extra and a one-off OAuth login (see google_services.py).
    """

    FIELDS = "nextPageToken, files(id, name, mimeType, webViewLink, appProperties, description)"

    def __init__(self, drive_service):
        self.drive = drive_service

    def sync(self, db: Database, folder_id: str, *, default_board: str | None = None) -> list[Material]:
        indexed: list[Material] = []
        page_token = None
        while True:
            resp = self.drive.files().list(
                q=f"'{folder_id}' in parents and trashed = false",
                fields=self.FIELDS,
                pageToken=page_token,
                pageSize=200,
            ).execute()
            for f in resp.get("files", []):
                if f["mimeType"] == "application/vnd.google-apps.folder":
                    indexed.extend(self.sync(db, f["id"], default_board=default_board))
                    continue
                props = f.get("appProperties") or {}
                stem = re.sub(r"\.[A-Za-z0-9]+$", "", f["name"])
                parsed = parse_material_name(stem)
                indexed.append(db.upsert_material(
                    title=props.get("title") or parsed.title,
                    location=f["id"],
                    source="drive",
                    board=props.get("board") or parsed.board or default_board,
                    topics=_split_topics(props.get("topics")) or parsed.topics,
                    kind=f["mimeType"].rsplit("/", 1)[-1],
                    share_link=None,  # created lazily when the material is actually sent
                ))
            page_token = resp.get("nextPageToken")
            if not page_token:
                break
        return indexed

    def ensure_share_link(self, db: Database, material: Material) -> str:
        if material.share_link:
            return material.share_link
        self.drive.permissions().create(
            fileId=material.location,
            body={"type": "anyone", "role": "reader"},
            fields="id",
        ).execute()
        meta = self.drive.files().get(fileId=material.location, fields="webViewLink").execute()
        link = meta["webViewLink"]
        db.set_share_link(material.id, link)
        return link


# ---------------------------------------------------------------------------
# Candidate pre-filter (cheap, before asking Claude)
# ---------------------------------------------------------------------------


def _tokens(text: str) -> set[str]:
    return {w for w in re.findall(r"[a-z0-9]+", text.lower()) if len(w) > 2}


def candidate_materials(db: Database, student: Student, classification: SessionClassification,
                        limit: int = 12) -> list[Material]:
    """Rank indexed materials by board match + topic-word overlap with this session; return the top few."""
    wanted = _tokens(" ".join(classification.topics_covered + classification.weak_spots
                              + classification.promised_next))
    scored: list[tuple[float, Material]] = []
    for m in db.list_materials(board=student.board):
        overlap = len(wanted & _tokens(" ".join(m.topics) + " " + m.title))
        if overlap == 0:
            continue
        board_bonus = 0.5 if (m.board and student.board and m.board.lower() == student.board.lower()) else 0.0
        scored.append((overlap + board_bonus, m))
    scored.sort(key=lambda t: (-t[0], t[1].title.lower()))
    return [m for _, m in scored[:limit]]
