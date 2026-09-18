"""SQLite persistence: the student memory that makes feedback feel personal months later."""

from __future__ import annotations

import json
import sqlite3
from contextlib import contextmanager
from datetime import datetime, timedelta
from pathlib import Path
from typing import Iterator

from .models import (
    Material,
    OutboxItem,
    OutboxKind,
    OutboxStatus,
    Promise,
    Session,
    Slot,
    Student,
    Topic,
    WeakSpot,
)

SCHEMA = """
CREATE TABLE IF NOT EXISTS settings (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS students (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL UNIQUE COLLATE NOCASE,
    board TEXT,
    level TEXT,
    subject TEXT,
    parent_name TEXT,
    notes TEXT,
    created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS sessions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    student_id INTEGER NOT NULL REFERENCES students(id) ON DELETE CASCADE,
    held_at TEXT NOT NULL,
    raw_notes TEXT NOT NULL,
    summary TEXT,
    topics TEXT NOT NULL DEFAULT '[]',
    went_well TEXT NOT NULL DEFAULT '[]',
    weak_spots TEXT NOT NULL DEFAULT '[]',
    homework TEXT NOT NULL DEFAULT '[]',
    created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_sessions_student ON sessions(student_id, held_at DESC);

CREATE TABLE IF NOT EXISTS topics (
    student_id INTEGER NOT NULL REFERENCES students(id) ON DELETE CASCADE,
    topic TEXT NOT NULL COLLATE NOCASE,
    times_covered INTEGER NOT NULL DEFAULT 1,
    first_covered TEXT NOT NULL,
    last_covered TEXT NOT NULL,
    PRIMARY KEY (student_id, topic)
);

CREATE TABLE IF NOT EXISTS weak_spots (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    student_id INTEGER NOT NULL REFERENCES students(id) ON DELETE CASCADE,
    description TEXT NOT NULL COLLATE NOCASE,
    times_seen INTEGER NOT NULL DEFAULT 1,
    first_seen TEXT NOT NULL,
    last_seen TEXT NOT NULL,
    resolved_at TEXT,
    UNIQUE (student_id, description)
);

CREATE TABLE IF NOT EXISTS promises (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    student_id INTEGER NOT NULL REFERENCES students(id) ON DELETE CASCADE,
    session_id INTEGER REFERENCES sessions(id) ON DELETE SET NULL,
    description TEXT NOT NULL,
    created_at TEXT NOT NULL,
    fulfilled_at TEXT
);

CREATE TABLE IF NOT EXISTS materials (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    location TEXT NOT NULL UNIQUE,
    source TEXT NOT NULL DEFAULT 'local',
    board TEXT,
    topics TEXT NOT NULL DEFAULT '[]',
    kind TEXT,
    share_link TEXT,
    created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS outbox (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    student_id INTEGER NOT NULL REFERENCES students(id) ON DELETE CASCADE,
    session_id INTEGER REFERENCES sessions(id) ON DELETE SET NULL,
    kind TEXT NOT NULL,
    body TEXT NOT NULL,
    material_ids TEXT NOT NULL DEFAULT '[]',
    status TEXT NOT NULL DEFAULT 'pending',
    created_at TEXT NOT NULL,
    sent_at TEXT,
    sent_via TEXT
);

CREATE TABLE IF NOT EXISTS slots (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    student_id INTEGER REFERENCES students(id) ON DELETE SET NULL,
    title TEXT NOT NULL,
    starts_at TEXT NOT NULL,
    ends_at TEXT NOT NULL,
    source TEXT NOT NULL DEFAULT 'manual',
    uid TEXT UNIQUE
);
CREATE INDEX IF NOT EXISTS idx_slots_start ON slots(starts_at);
"""


def _now() -> str:
    return datetime.now().replace(microsecond=0).isoformat()


def _dt(value: str | None) -> datetime | None:
    return datetime.fromisoformat(value) if value else None


def _loads(value: str | None) -> list:
    return json.loads(value) if value else []


class Database:
    """Thin repository over SQLite. One instance per process; safe for the CLI's needs."""

    def __init__(self, path: Path | str):
        self.path = Path(path)
        if str(self.path) != ":memory:":
            self.path.parent.mkdir(parents=True, exist_ok=True)
        self._conn = sqlite3.connect(str(self.path))
        self._conn.row_factory = sqlite3.Row
        self._conn.execute("PRAGMA foreign_keys = ON")
        self._conn.executescript(SCHEMA)

    def close(self) -> None:
        self._conn.close()

    @contextmanager
    def tx(self) -> Iterator[sqlite3.Connection]:
        try:
            yield self._conn
            self._conn.commit()
        except Exception:
            self._conn.rollback()
            raise

    # -- settings -----------------------------------------------------------

    def get_setting(self, key: str, default: str | None = None) -> str | None:
        row = self._conn.execute("SELECT value FROM settings WHERE key = ?", (key,)).fetchone()
        return row["value"] if row else default

    def set_setting(self, key: str, value: str) -> None:
        with self.tx() as c:
            c.execute(
                "INSERT INTO settings(key, value) VALUES (?, ?) "
                "ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                (key, value),
            )

    # -- students -----------------------------------------------------------

    @staticmethod
    def _student(row: sqlite3.Row) -> Student:
        return Student(
            id=row["id"], name=row["name"], board=row["board"], level=row["level"],
            subject=row["subject"], parent_name=row["parent_name"], notes=row["notes"],
            created_at=_dt(row["created_at"]),
        )

    def add_student(self, name: str, *, board: str | None = None, level: str | None = None,
                    subject: str | None = None, parent_name: str | None = None,
                    notes: str | None = None) -> Student:
        with self.tx() as c:
            cur = c.execute(
                "INSERT INTO students(name, board, level, subject, parent_name, notes, created_at) "
                "VALUES (?, ?, ?, ?, ?, ?, ?)",
                (name.strip(), board, level, subject, parent_name, notes, _now()),
            )
        return self.get_student(cur.lastrowid)

    def update_student(self, student_id: int, **fields) -> Student:
        allowed = {"name", "board", "level", "subject", "parent_name", "notes"}
        updates = {k: v for k, v in fields.items() if k in allowed and v is not None}
        if updates:
            sets = ", ".join(f"{k} = ?" for k in updates)
            with self.tx() as c:
                c.execute(f"UPDATE students SET {sets} WHERE id = ?", (*updates.values(), student_id))
        return self.get_student(student_id)

    def get_student(self, student_id: int) -> Student:
        row = self._conn.execute("SELECT * FROM students WHERE id = ?", (student_id,)).fetchone()
        if row is None:
            raise KeyError(f"No student with id {student_id}")
        return self._student(row)

    def find_student(self, name: str) -> Student | None:
        """Case-insensitive match on the full name, then on the first word of the name."""
        name = name.strip()
        row = self._conn.execute("SELECT * FROM students WHERE name = ? COLLATE NOCASE", (name,)).fetchone()
        if row is None:
            first = name.split()[0] if name else ""
            row = self._conn.execute(
                "SELECT * FROM students WHERE name = ? COLLATE NOCASE OR name LIKE ? COLLATE NOCASE",
                (first, first + " %"),
            ).fetchone()
        return self._student(row) if row else None

    def list_students(self) -> list[Student]:
        rows = self._conn.execute("SELECT * FROM students ORDER BY name COLLATE NOCASE").fetchall()
        return [self._student(r) for r in rows]

    # -- sessions -----------------------------------------------------------

    @staticmethod
    def _session(row: sqlite3.Row) -> Session:
        return Session(
            id=row["id"], student_id=row["student_id"], held_at=_dt(row["held_at"]),
            raw_notes=row["raw_notes"], summary=row["summary"], topics=_loads(row["topics"]),
            went_well=_loads(row["went_well"]), weak_spots=_loads(row["weak_spots"]),
            homework=_loads(row["homework"]), created_at=_dt(row["created_at"]),
        )

    def add_session(self, student_id: int, raw_notes: str, *, held_at: datetime | None = None,
                    summary: str | None = None, topics: list[str] | None = None,
                    went_well: list[str] | None = None, weak_spots: list[str] | None = None,
                    homework: list[str] | None = None) -> Session:
        held = (held_at or datetime.now()).replace(microsecond=0)
        with self.tx() as c:
            cur = c.execute(
                "INSERT INTO sessions(student_id, held_at, raw_notes, summary, topics, went_well, "
                "weak_spots, homework, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (student_id, held.isoformat(), raw_notes, summary, json.dumps(topics or []),
                 json.dumps(went_well or []), json.dumps(weak_spots or []),
                 json.dumps(homework or []), _now()),
            )
            session_id = cur.lastrowid
            for topic in topics or []:
                c.execute(
                    "INSERT INTO topics(student_id, topic, times_covered, first_covered, last_covered) "
                    "VALUES (?, ?, 1, ?, ?) ON CONFLICT(student_id, topic) DO UPDATE SET "
                    "times_covered = times_covered + 1, last_covered = excluded.last_covered",
                    (student_id, topic.strip(), held.isoformat(), held.isoformat()),
                )
            for spot in weak_spots or []:
                c.execute(
                    "INSERT INTO weak_spots(student_id, description, times_seen, first_seen, last_seen) "
                    "VALUES (?, ?, 1, ?, ?) ON CONFLICT(student_id, description) DO UPDATE SET "
                    "times_seen = times_seen + 1, last_seen = excluded.last_seen, resolved_at = NULL",
                    (student_id, spot.strip(), held.isoformat(), held.isoformat()),
                )
        return self.get_session(session_id)

    def get_session(self, session_id: int) -> Session:
        row = self._conn.execute("SELECT * FROM sessions WHERE id = ?", (session_id,)).fetchone()
        if row is None:
            raise KeyError(f"No session with id {session_id}")
        return self._session(row)

    def recent_sessions(self, student_id: int, limit: int = 5) -> list[Session]:
        rows = self._conn.execute(
            "SELECT * FROM sessions WHERE student_id = ? ORDER BY held_at DESC, id DESC LIMIT ?",
            (student_id, limit),
        ).fetchall()
        return [self._session(r) for r in rows]

    def topics_for(self, student_id: int) -> list[Topic]:
        rows = self._conn.execute(
            "SELECT * FROM topics WHERE student_id = ? ORDER BY last_covered DESC", (student_id,)
        ).fetchall()
        return [
            Topic(student_id=r["student_id"], topic=r["topic"], times_covered=r["times_covered"],
                  first_covered=_dt(r["first_covered"]), last_covered=_dt(r["last_covered"]))
            for r in rows
        ]

    def weak_spots_for(self, student_id: int, include_resolved: bool = False) -> list[WeakSpot]:
        sql = "SELECT * FROM weak_spots WHERE student_id = ?"
        if not include_resolved:
            sql += " AND resolved_at IS NULL"
        rows = self._conn.execute(sql + " ORDER BY times_seen DESC, last_seen DESC", (student_id,)).fetchall()
        return [
            WeakSpot(id=r["id"], student_id=r["student_id"], description=r["description"],
                     times_seen=r["times_seen"], first_seen=_dt(r["first_seen"]),
                     last_seen=_dt(r["last_seen"]), resolved_at=_dt(r["resolved_at"]))
            for r in rows
        ]

    def resolve_weak_spot(self, weak_spot_id: int) -> None:
        with self.tx() as c:
            c.execute("UPDATE weak_spots SET resolved_at = ? WHERE id = ?", (_now(), weak_spot_id))

    # -- promises -----------------------------------------------------------

    @staticmethod
    def _promise(row: sqlite3.Row) -> Promise:
        return Promise(id=row["id"], student_id=row["student_id"], session_id=row["session_id"],
                       description=row["description"], created_at=_dt(row["created_at"]),
                       fulfilled_at=_dt(row["fulfilled_at"]))

    def add_promise(self, student_id: int, description: str, session_id: int | None = None) -> Promise:
        with self.tx() as c:
            cur = c.execute(
                "INSERT INTO promises(student_id, session_id, description, created_at) VALUES (?, ?, ?, ?)",
                (student_id, session_id, description.strip(), _now()),
            )
        row = self._conn.execute("SELECT * FROM promises WHERE id = ?", (cur.lastrowid,)).fetchone()
        return self._promise(row)

    def open_promises(self, student_id: int) -> list[Promise]:
        rows = self._conn.execute(
            "SELECT * FROM promises WHERE student_id = ? AND fulfilled_at IS NULL ORDER BY created_at",
            (student_id,),
        ).fetchall()
        return [self._promise(r) for r in rows]

    def fulfil_promise(self, promise_id: int) -> None:
        with self.tx() as c:
            c.execute("UPDATE promises SET fulfilled_at = ? WHERE id = ?", (_now(), promise_id))

    def fulfil_promises_for_session(self, session_id: int) -> int:
        """Mark every open promise attached to a session as fulfilled (called when materials are sent)."""
        with self.tx() as c:
            cur = c.execute(
                "UPDATE promises SET fulfilled_at = ? WHERE session_id = ? AND fulfilled_at IS NULL",
                (_now(), session_id),
            )
        return cur.rowcount

    # -- materials ----------------------------------------------------------

    @staticmethod
    def _material(row: sqlite3.Row) -> Material:
        return Material(id=row["id"], title=row["title"], location=row["location"], source=row["source"],
                        board=row["board"], topics=_loads(row["topics"]), kind=row["kind"],
                        share_link=row["share_link"], created_at=_dt(row["created_at"]))

    def upsert_material(self, *, title: str, location: str, source: str = "local",
                        board: str | None = None, topics: list[str] | None = None,
                        kind: str | None = None, share_link: str | None = None) -> Material:
        with self.tx() as c:
            c.execute(
                "INSERT INTO materials(title, location, source, board, topics, kind, share_link, created_at) "
                "VALUES (?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT(location) DO UPDATE SET "
                "title = excluded.title, source = excluded.source, board = excluded.board, "
                "topics = excluded.topics, kind = excluded.kind, "
                "share_link = COALESCE(excluded.share_link, materials.share_link)",
                (title, location, source, board, json.dumps(topics or []), kind, share_link, _now()),
            )
        row = self._conn.execute("SELECT * FROM materials WHERE location = ?", (location,)).fetchone()
        return self._material(row)

    def set_share_link(self, material_id: int, share_link: str) -> None:
        with self.tx() as c:
            c.execute("UPDATE materials SET share_link = ? WHERE id = ?", (share_link, material_id))

    def get_material(self, material_id: int) -> Material:
        row = self._conn.execute("SELECT * FROM materials WHERE id = ?", (material_id,)).fetchone()
        if row is None:
            raise KeyError(f"No material with id {material_id}")
        return self._material(row)

    def list_materials(self, board: str | None = None) -> list[Material]:
        if board:
            rows = self._conn.execute(
                "SELECT * FROM materials WHERE board IS NULL OR board = '' OR board = ? COLLATE NOCASE "
                "ORDER BY title COLLATE NOCASE", (board,),
            ).fetchall()
        else:
            rows = self._conn.execute("SELECT * FROM materials ORDER BY title COLLATE NOCASE").fetchall()
        return [self._material(r) for r in rows]

    def delete_material(self, material_id: int) -> None:
        with self.tx() as c:
            c.execute("DELETE FROM materials WHERE id = ?", (material_id,))

    # -- outbox -------------------------------------------------------------

    @staticmethod
    def _outbox(row: sqlite3.Row) -> OutboxItem:
        return OutboxItem(id=row["id"], student_id=row["student_id"], session_id=row["session_id"],
                          kind=row["kind"], body=row["body"], material_ids=_loads(row["material_ids"]),
                          status=row["status"], created_at=_dt(row["created_at"]),
                          sent_at=_dt(row["sent_at"]), sent_via=row["sent_via"])

    def queue(self, student_id: int, kind: OutboxKind, body: str, *, session_id: int | None = None,
              material_ids: list[int] | None = None) -> OutboxItem:
        with self.tx() as c:
            cur = c.execute(
                "INSERT INTO outbox(student_id, session_id, kind, body, material_ids, status, created_at) "
                "VALUES (?, ?, ?, ?, ?, 'pending', ?)",
                (student_id, session_id, kind, body, json.dumps(material_ids or []), _now()),
            )
        return self.get_outbox_item(cur.lastrowid)

    def get_outbox_item(self, item_id: int) -> OutboxItem:
        row = self._conn.execute("SELECT * FROM outbox WHERE id = ?", (item_id,)).fetchone()
        if row is None:
            raise KeyError(f"No outbox item with id {item_id}")
        return self._outbox(row)

    def list_outbox(self, status: OutboxStatus | None = "pending") -> list[OutboxItem]:
        if status:
            rows = self._conn.execute("SELECT * FROM outbox WHERE status = ? ORDER BY id", (status,)).fetchall()
        else:
            rows = self._conn.execute("SELECT * FROM outbox ORDER BY id").fetchall()
        return [self._outbox(r) for r in rows]

    def update_outbox_body(self, item_id: int, body: str) -> OutboxItem:
        with self.tx() as c:
            c.execute("UPDATE outbox SET body = ? WHERE id = ?", (body, item_id))
        return self.get_outbox_item(item_id)

    def set_outbox_status(self, item_id: int, status: OutboxStatus, *, via: str | None = None) -> OutboxItem:
        with self.tx() as c:
            if status == "sent":
                c.execute("UPDATE outbox SET status = 'sent', sent_at = ?, sent_via = ? WHERE id = ?",
                          (_now(), via, item_id))
            else:
                c.execute("UPDATE outbox SET status = ? WHERE id = ?", (status, item_id))
        return self.get_outbox_item(item_id)

    # -- schedule -----------------------------------------------------------

    @staticmethod
    def _slot(row: sqlite3.Row) -> Slot:
        return Slot(id=row["id"], student_id=row["student_id"], title=row["title"],
                    starts_at=_dt(row["starts_at"]), ends_at=_dt(row["ends_at"]),
                    source=row["source"], uid=row["uid"])

    def upsert_slot(self, *, title: str, starts_at: datetime, ends_at: datetime,
                    student_id: int | None = None, source: str = "manual", uid: str | None = None) -> Slot:
        with self.tx() as c:
            if uid:
                c.execute(
                    "INSERT INTO slots(student_id, title, starts_at, ends_at, source, uid) "
                    "VALUES (?, ?, ?, ?, ?, ?) ON CONFLICT(uid) DO UPDATE SET student_id = excluded.student_id, "
                    "title = excluded.title, starts_at = excluded.starts_at, ends_at = excluded.ends_at",
                    (student_id, title, starts_at.isoformat(), ends_at.isoformat(), source, uid),
                )
                row = self._conn.execute("SELECT * FROM slots WHERE uid = ?", (uid,)).fetchone()
            else:
                cur = c.execute(
                    "INSERT INTO slots(student_id, title, starts_at, ends_at, source, uid) "
                    "VALUES (?, ?, ?, ?, ?, NULL)",
                    (student_id, title, starts_at.isoformat(), ends_at.isoformat(), source),
                )
                row = self._conn.execute("SELECT * FROM slots WHERE id = ?", (cur.lastrowid,)).fetchone()
        return self._slot(row)

    def slots_between(self, start: datetime, end: datetime) -> list[Slot]:
        rows = self._conn.execute(
            "SELECT * FROM slots WHERE starts_at >= ? AND starts_at < ? ORDER BY starts_at",
            (start.isoformat(), end.isoformat()),
        ).fetchall()
        return [self._slot(r) for r in rows]

    def slots_on(self, day: datetime) -> list[Slot]:
        start = day.replace(hour=0, minute=0, second=0, microsecond=0)
        return self.slots_between(start, start + timedelta(days=1))

    def delete_slot(self, slot_id: int) -> None:
        with self.tx() as c:
            c.execute("DELETE FROM slots WHERE id = ?", (slot_id,))
