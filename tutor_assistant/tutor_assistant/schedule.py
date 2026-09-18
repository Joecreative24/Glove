"""Schedule mirroring: GoStudent slots -> local table -> Google Calendar (ICS or API), plus the nightly brief."""

from __future__ import annotations

import re
from dataclasses import dataclass
from datetime import date, datetime, timedelta
from zoneinfo import ZoneInfo

from .db import Database
from .models import Slot, Student

PRODID = "-//tutor-assistant//EN"


# ---------------------------------------------------------------------------
# ICS parsing (only what a calendar export from GoStudent / Google needs)
# ---------------------------------------------------------------------------


@dataclass
class IcsEvent:
    uid: str | None
    summary: str
    start: datetime
    end: datetime


def _unfold(text: str) -> list[str]:
    lines: list[str] = []
    for raw in text.replace("\r\n", "\n").split("\n"):
        if raw.startswith((" ", "\t")) and lines:
            lines[-1] += raw[1:]
        else:
            lines.append(raw)
    return lines


def _parse_dt(value: str, params: dict[str, str], local_tz: ZoneInfo) -> datetime:
    value = value.strip()
    if params.get("VALUE") == "DATE" or re.fullmatch(r"\d{8}", value):
        return datetime.strptime(value, "%Y%m%d")
    if value.endswith("Z"):
        aware = datetime.strptime(value[:-1], "%Y%m%dT%H%M%S").replace(tzinfo=ZoneInfo("UTC"))
        return aware.astimezone(local_tz).replace(tzinfo=None)
    naive = datetime.strptime(value, "%Y%m%dT%H%M%S")
    tzid = params.get("TZID")
    if tzid:
        try:
            return naive.replace(tzinfo=ZoneInfo(tzid)).astimezone(local_tz).replace(tzinfo=None)
        except Exception:  # unknown TZID: treat as local
            return naive
    return naive


def parse_ics(text: str, tz: str = "Europe/London") -> list[IcsEvent]:
    local_tz = ZoneInfo(tz)
    events: list[IcsEvent] = []
    current: dict | None = None
    for line in _unfold(text):
        if line == "BEGIN:VEVENT":
            current = {}
            continue
        if line == "END:VEVENT" and current is not None:
            if "DTSTART" in current:
                start = current["DTSTART"]
                end = current.get("DTEND") or start + timedelta(hours=1)
                events.append(IcsEvent(uid=current.get("UID"), summary=current.get("SUMMARY", "(no title)"),
                                       start=start, end=end))
            current = None
            continue
        if current is None or ":" not in line:
            continue
        head, _, value = line.partition(":")
        name, *param_parts = head.split(";")
        params = dict(p.split("=", 1) for p in param_parts if "=" in p)
        name = name.upper()
        if name in ("DTSTART", "DTEND"):
            current[name] = _parse_dt(value, params, local_tz)
        elif name in ("SUMMARY", "UID"):
            current[name] = value.replace("\\,", ",").replace("\\;", ";").replace("\\n", " ").strip()
    return events


def match_student(db: Database, title: str) -> Student | None:
    """Find the student whose name appears in an event title (longest name wins)."""
    title_l = title.lower()
    best: Student | None = None
    for s in db.list_students():
        if s.name.lower() in title_l and (best is None or len(s.name) > len(best.name)):
            best = s
    if best:
        return best
    for word in re.findall(r"[A-Za-z][A-Za-z'\-]+", title):
        s = db.find_student(word)
        if s:
            return s
    return None


def import_ics(db: Database, text: str, tz: str = "Europe/London") -> list[Slot]:
    slots: list[Slot] = []
    for ev in parse_ics(text, tz):
        student = match_student(db, ev.summary)
        slots.append(db.upsert_slot(
            title=ev.summary, starts_at=ev.start, ends_at=ev.end,
            student_id=student.id if student else None, source="ics", uid=ev.uid,
        ))
    return slots


# ---------------------------------------------------------------------------
# ICS export (import this file into Google Calendar)
# ---------------------------------------------------------------------------


def _fmt(dt: datetime) -> str:
    return dt.strftime("%Y%m%dT%H%M%S")


def _escape(text: str) -> str:
    return text.replace("\\", "\\\\").replace(";", "\\;").replace(",", "\\,").replace("\n", "\\n")


def _fold(line: str) -> str:
    out, chunk = [], line
    while len(chunk.encode("utf-8")) > 72:
        out.append(chunk[:70])
        chunk = " " + chunk[70:]
    out.append(chunk)
    return "\r\n".join(out)


def slot_description(db: Database, slot: Slot) -> str:
    if slot.student_id is None:
        return ""
    student = db.get_student(slot.student_id)
    lines = [f"{student.name}" + (f" ({student.board}, {student.level})" if student.board or student.level else "")]
    last = db.recent_sessions(student.id, limit=1)
    if last:
        s = last[0]
        lines.append(f"Last time ({s.held_at:%d %b}): {s.summary or s.raw_notes}")
    weak = db.weak_spots_for(student.id)[:3]
    if weak:
        lines.append("Watch: " + "; ".join(w.description for w in weak))
    promises = db.open_promises(student.id)
    if promises:
        lines.append("Still to send: " + "; ".join(p.description for p in promises))
    return "\n".join(lines)


def export_ics(db: Database, slots: list[Slot], *, tz: str = "Europe/London",
               prep_minutes: int = 30, buffer_minutes: int = 15) -> str:
    """Build an ICS calendar with a prep reminder per lesson and optional buffer blocks around it."""
    lines = ["BEGIN:VCALENDAR", "VERSION:2.0", f"PRODID:{PRODID}", "CALSCALE:GREGORIAN", "METHOD:PUBLISH"]
    stamp = datetime.now().strftime("%Y%m%dT%H%M%SZ")
    for slot in slots:
        uid = slot.uid or f"slot-{slot.id}@tutor-assistant"
        lines += [
            "BEGIN:VEVENT",
            f"UID:{uid}",
            f"DTSTAMP:{stamp}",
            f"DTSTART;TZID={tz}:{_fmt(slot.starts_at)}",
            f"DTEND;TZID={tz}:{_fmt(slot.ends_at)}",
            f"SUMMARY:{_escape(slot.title)}",
        ]
        desc = slot_description(db, slot)
        if desc:
            lines.append(f"DESCRIPTION:{_escape(desc)}")
        if prep_minutes > 0:
            lines += [
                "BEGIN:VALARM",
                "ACTION:DISPLAY",
                f"DESCRIPTION:Prep for {_escape(slot.title)}",
                f"TRIGGER:-PT{prep_minutes}M",
                "END:VALARM",
            ]
        lines.append("END:VEVENT")
        if buffer_minutes > 0:
            for label, start, end in (
                ("before", slot.starts_at - timedelta(minutes=buffer_minutes), slot.starts_at),
                ("after", slot.ends_at, slot.ends_at + timedelta(minutes=buffer_minutes)),
            ):
                lines += [
                    "BEGIN:VEVENT",
                    f"UID:{uid}-buffer-{label}",
                    f"DTSTAMP:{stamp}",
                    f"DTSTART;TZID={tz}:{_fmt(start)}",
                    f"DTEND;TZID={tz}:{_fmt(end)}",
                    f"SUMMARY:{_escape('Buffer ' + label + ': ' + slot.title)}",
                    "TRANSP:OPAQUE",
                    "END:VEVENT",
                ]
    lines.append("END:VCALENDAR")
    return "\r\n".join(_fold(l) for l in lines) + "\r\n"


# ---------------------------------------------------------------------------
# Nightly brief
# ---------------------------------------------------------------------------


def brief_input(db: Database, day: date) -> str:
    """Plain-text dossier for one day's lessons: the raw material for the brief (readable on its own)."""
    slots = db.slots_on(datetime.combine(day, datetime.min.time()))
    if not slots:
        return f"No lessons scheduled for {day:%A %d %B %Y}."
    out = [f"Lessons for {day:%A %d %B %Y}:", ""]
    for slot in slots:
        out.append(f"{slot.starts_at:%H:%M}-{slot.ends_at:%H:%M}  {slot.title}")
        if slot.student_id is None:
            out.append("  (no student on file for this slot)")
            out.append("")
            continue
        student = db.get_student(slot.student_id)
        meta = ", ".join(x for x in (student.subject, student.board, student.level) if x)
        if meta:
            out.append(f"  {meta}")
        for s in db.recent_sessions(student.id, limit=2):
            out.append(f"  Last time ({s.held_at:%d %b}): {s.summary or s.raw_notes}")
            if s.topics:
                out.append(f"    topics: {', '.join(s.topics)}")
            if s.homework:
                out.append(f"    homework set: {', '.join(s.homework)}")
        weak = db.weak_spots_for(student.id)[:4]
        if weak:
            out.append("  Recurring weak spots: " + "; ".join(f"{w.description} (x{w.times_seen})" for w in weak))
        promises = db.open_promises(student.id)
        if promises:
            out.append("  Still to send: " + "; ".join(p.description for p in promises))
        out.append("")
    return "\n".join(out).rstrip()


def write_brief(db: Database, llm, day: date) -> str:
    dossier = brief_input(db, day)
    if dossier.startswith("No lessons"):
        return dossier
    return llm.write_brief(dossier)
