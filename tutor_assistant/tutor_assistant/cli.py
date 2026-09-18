"""`tutor` command-line interface."""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
import tempfile
from datetime import date, datetime, timedelta
from pathlib import Path

from . import __version__
from .config import Settings
from .db import Database
from .llm import load_llm
from .materials import DriveMaterials, index_local_folder
from .models import OutboxItem
from .pipeline import DEFAULT_VOICE, get_voice, log_session, mark_sent
from .schedule import brief_input, export_ics, import_ics, slot_description, write_brief
from .senders import append_to_file, copy_to_clipboard


class Cli:
    def __init__(self, args: argparse.Namespace):
        self.args = args
        self.settings = Settings()
        if args.db:
            self.settings.db_path = Path(args.db).expanduser()
        self.settings.ensure_dirs()
        self.db = Database(self.settings.db_path)
        self._llm = None
        self._drive = None

    @property
    def llm(self):
        if self._llm is None:
            self._llm = load_llm(self.settings.model, fake=self.args.fake)
        return self._llm

    @property
    def drive(self) -> DriveMaterials:
        if self._drive is None:
            from .google_services import drive_service

            self._drive = DriveMaterials(drive_service(self.settings))
        return self._drive

    # -- helpers ------------------------------------------------------------

    def student_or_die(self, name: str):
        s = self.db.find_student(name)
        if s is None:
            sys.exit(f"No student called '{name}'. Try: tutor student add \"{name}\"")
        return s

    @staticmethod
    def parse_day(value: str | None) -> date:
        if not value or value == "tomorrow":
            return date.today() + timedelta(days=1)
        if value == "today":
            return date.today()
        return date.fromisoformat(value)

    @staticmethod
    def print_item(item: OutboxItem, student_name: str) -> None:
        print(f"[{item.id}] {item.kind:<9} {item.status:<8} {student_name}  ({item.created_at:%d %b %H:%M})")

    # -- init / voice -------------------------------------------------------

    def cmd_init(self) -> None:
        print(f"Database ready at {self.settings.db_path}")
        print(f"Model: {self.settings.model}   Timezone: {self.settings.timezone}")
        if not self.db.get_setting("voice"):
            print("No voice set yet. Set one with: tutor voice set \"...\"")

    def cmd_voice(self) -> None:
        if self.args.voice_cmd == "set":
            self.db.set_setting("voice", " ".join(self.args.text))
            print("Voice saved.")
        else:
            print(get_voice(self.db))
            if not self.db.get_setting("voice"):
                print("\n(default voice; change with: tutor voice set \"...\")")

    # -- students -----------------------------------------------------------

    def cmd_student(self) -> None:
        a = self.args
        if a.student_cmd == "add":
            s = self.db.add_student(a.name, board=a.board, level=a.level, subject=a.subject,
                                    parent_name=a.parent, notes=a.notes)
            print(f"Added {s.name} (id {s.id}).")
        elif a.student_cmd == "edit":
            s = self.student_or_die(a.name)
            s = self.db.update_student(s.id, board=a.board, level=a.level, subject=a.subject,
                                       parent_name=a.parent, notes=a.notes)
            print(f"Updated {s.name}.")
        elif a.student_cmd == "list":
            for s in self.db.list_students():
                meta = ", ".join(x for x in (s.subject, s.board, s.level) if x)
                print(f"{s.id:>3}  {s.name:<20} {meta}")
        elif a.student_cmd == "show":
            s = self.student_or_die(a.name)
            print(f"{s.name}  —  {', '.join(x for x in (s.subject, s.board, s.level) if x) or 'no details'}")
            if s.parent_name:
                print(f"Parent: {s.parent_name}")
            if s.notes:
                print(f"Notes: {s.notes}")
            topics = self.db.topics_for(s.id)
            if topics:
                print("\nTopics covered:")
                for t in topics:
                    print(f"  - {t.topic} (x{t.times_covered}, last {t.last_covered:%d %b})")
            weak = self.db.weak_spots_for(s.id)
            if weak:
                print("\nWeak spots:")
                for w in weak:
                    print(f"  - [{w.id}] {w.description} (x{w.times_seen}, last {w.last_seen:%d %b})")
            promises = self.db.open_promises(s.id)
            if promises:
                print("\nStill to send:")
                for p in promises:
                    print(f"  - [{p.id}] {p.description}")
            sessions = self.db.recent_sessions(s.id, limit=5)
            if sessions:
                print("\nRecent sessions:")
                for sess in sessions:
                    print(f"  - {sess.held_at:%d %b %Y}: {sess.summary or sess.raw_notes}")
        elif a.student_cmd == "resolve":
            self.db.resolve_weak_spot(a.weak_spot_id)
            print("Marked resolved.")
        elif a.student_cmd == "fulfil":
            self.db.fulfil_promise(a.promise_id)
            print("Promise marked as sent.")

    # -- log ----------------------------------------------------------------

    def cmd_log(self) -> None:
        a = self.args
        raw = " ".join(a.notes).strip()
        if not raw or raw == "-":
            raw = sys.stdin.read().strip()
        if not raw:
            sys.exit("No notes given.")
        held_at = datetime.fromisoformat(a.date) if a.date else None
        drive = None
        if any(m.source == "drive" and not m.share_link for m in self.db.list_materials()) and not a.fake:
            try:
                drive = self.drive
            except Exception as e:  # keep going without links rather than lose the feedback
                print(f"(Drive unavailable, share links will be left pending: {e})", file=sys.stderr)
        result = log_session(self.db, self.llm, raw, student_name=a.student, held_at=held_at,
                             create_missing=not a.strict, drive=drive, with_materials=not a.no_materials)
        c = result.classification
        if result.created_student:
            print(f"New student created: {result.student.name}. Add board/level with `tutor student edit`.")
        print(f"Session {result.session.id} stored for {result.student.name}.")
        print(f"  topics: {', '.join(c.topics_covered) or '-'}")
        print(f"  went well: {', '.join(c.went_well) or '-'}")
        print(f"  weak spots: {', '.join(c.weak_spots) or '-'}")
        if c.promised_next:
            print(f"  promised: {', '.join(c.promised_next)}")
        print(f"\nQueued feedback draft [{result.feedback.id}]:\n")
        print(result.feedback.body)
        if result.materials:
            print(f"\nQueued materials message [{result.materials.id}] with {len(result.picked)} resource(s):\n")
            print(result.materials.body)
        print("\nReview with `tutor queue list`, then `tutor queue send <id>`.")

    # -- queue --------------------------------------------------------------

    def cmd_queue(self) -> None:
        a = self.args
        if a.queue_cmd == "list":
            items = self.db.list_outbox(None if a.all else "pending")
            if not items:
                print("Queue is empty." if not a.all else "No outbox items.")
            for item in items:
                self.print_item(item, self.db.get_student(item.student_id).name)
            return
        item = self.db.get_outbox_item(a.id)
        student = self.db.get_student(item.student_id)
        if a.queue_cmd == "show":
            self.print_item(item, student.name)
            print()
            print(item.body)
        elif a.queue_cmd == "edit":
            editor = os.environ.get("EDITOR", "nano")
            with tempfile.NamedTemporaryFile("w+", suffix=".txt", delete=False, encoding="utf-8") as fh:
                fh.write(item.body)
                path = fh.name
            subprocess.run([editor, path], check=False)
            new_body = Path(path).read_text(encoding="utf-8").strip()
            os.unlink(path)
            self.db.update_outbox_body(item.id, new_body)
            print("Saved.")
        elif a.queue_cmd == "approve":
            self.db.set_outbox_status(item.id, "approved")
            print(f"[{item.id}] approved.")
        elif a.queue_cmd == "reject":
            self.db.set_outbox_status(item.id, "rejected")
            print(f"[{item.id}] rejected.")
        elif a.queue_cmd == "send":
            if item.status in ("sent", "rejected"):
                sys.exit(f"[{item.id}] is already {item.status}.")
            via = a.via
            if via == "clipboard":
                if copy_to_clipboard(item.body):
                    print(f"Copied to clipboard. Paste it into GoChat for {student.name}.")
                else:
                    print("No clipboard tool found; printing instead.\n")
                    print(item.body)
                    via = "stdout"
            elif via == "stdout":
                print(item.body)
            elif via == "file":
                path = Path(a.file or "~/tutor_outbox.txt")
                append_to_file(item.body, path, header=f"{student.name} · {item.kind} · {datetime.now():%d %b %Y %H:%M}")
                print(f"Appended to {path.expanduser()}.")
            elif via == "gmail":
                if not a.to:
                    sys.exit("--to is required for --via gmail")
                from .google_services import create_gmail_draft, gmail_service

                subject = a.subject or f"{student.name}: notes from today's session"
                draft_id = create_gmail_draft(gmail_service(self.settings), to=a.to, subject=subject, body=item.body)
                print(f"Gmail draft created ({draft_id}) for {a.to}. Send it from Gmail.")
            mark_sent(self.db, item, via)
            print(f"[{item.id}] marked sent via {via}.")

    # -- materials ----------------------------------------------------------

    def cmd_materials(self) -> None:
        a = self.args
        if a.materials_cmd == "index":
            items = index_local_folder(self.db, Path(a.folder), default_board=a.board)
            print(f"Indexed {len(items)} file(s).")
        elif a.materials_cmd == "sync-drive":
            items = self.drive.sync(self.db, a.folder_id, default_board=a.board)
            print(f"Synced {len(items)} Drive file(s).")
        elif a.materials_cmd == "list":
            for m in self.db.list_materials(board=a.board):
                tags = ", ".join(m.topics) or "-"
                print(f"{m.id:>3}  {m.title:<40} {m.board or '-':<8} {tags}  [{m.source}]")
        elif a.materials_cmd == "tag":
            m = self.db.get_material(a.id)
            self.db.upsert_material(
                title=a.title or m.title, location=m.location, source=m.source,
                board=a.board or m.board, topics=[t.strip() for t in a.topics.split(",")] if a.topics else m.topics,
                kind=m.kind, share_link=m.share_link,
            )
            print(f"Updated material {m.id}.")
        elif a.materials_cmd == "rm":
            self.db.delete_material(a.id)
            print("Removed.")

    # -- schedule -----------------------------------------------------------

    def cmd_schedule(self) -> None:
        a = self.args
        if a.schedule_cmd == "add":
            s = self.student_or_die(a.student)
            start = datetime.fromisoformat(a.start)
            slot = self.db.upsert_slot(title=a.title or f"Lesson: {s.name}", starts_at=start,
                                       ends_at=start + timedelta(minutes=a.minutes), student_id=s.id)
            print(f"Added slot {slot.id}: {slot.title} {slot.starts_at:%a %d %b %H:%M}.")
        elif a.schedule_cmd == "import":
            text = Path(a.file).read_text(encoding="utf-8")
            slots = import_ics(self.db, text, tz=self.settings.timezone)
            unmatched = [s for s in slots if s.student_id is None]
            print(f"Imported {len(slots)} slot(s); {len(unmatched)} without a matching student.")
            for s in unmatched:
                print(f"  ? {s.starts_at:%a %d %b %H:%M}  {s.title}")
        elif a.schedule_cmd == "list":
            start = datetime.combine(date.today(), datetime.min.time())
            for s in self.db.slots_between(start, start + timedelta(days=a.days)):
                who = self.db.get_student(s.student_id).name if s.student_id else "?"
                print(f"{s.id:>3}  {s.starts_at:%a %d %b %H:%M}-{s.ends_at:%H:%M}  {s.title:<30} {who}")
        elif a.schedule_cmd == "rm":
            self.db.delete_slot(a.id)
            print("Removed.")
        elif a.schedule_cmd == "export":
            start = datetime.combine(date.today(), datetime.min.time())
            slots = self.db.slots_between(start, start + timedelta(days=a.days))
            ics = export_ics(self.db, slots, tz=self.settings.timezone, prep_minutes=a.prep, buffer_minutes=a.buffer)
            Path(a.out).write_text(ics, encoding="utf-8")
            print(f"Wrote {len(slots)} lesson(s) to {a.out}. Import it into Google Calendar (Settings > Import).")
        elif a.schedule_cmd == "push":
            from .google_services import calendar_service, push_slots_to_calendar

            start = datetime.combine(date.today(), datetime.min.time())
            slots = self.db.slots_between(start, start + timedelta(days=a.days))
            descriptions = {s.id: slot_description(self.db, s) for s in slots}
            ids = push_slots_to_calendar(calendar_service(self.settings), slots, tz=self.settings.timezone,
                                         prep_minutes=a.prep, descriptions=descriptions)
            print(f"Pushed {len(ids)} event(s) to Google Calendar.")

    # -- brief --------------------------------------------------------------

    def cmd_brief(self) -> None:
        day = self.parse_day(self.args.date)
        text = brief_input(self.db, day) if self.args.raw else write_brief(self.db, self.llm, day)
        print(text)
        if self.args.file:
            append_to_file(text, Path(self.args.file), header=f"Brief for {day:%A %d %B %Y}")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="tutor", description="Post-session feedback, materials, memory and schedule for tutors.")
    p.add_argument("--db", help="SQLite path (default $TUTOR_DB or ~/.tutor_assistant/tutor.db)")
    p.add_argument("--fake", action="store_true", help="use the offline rule-based stand-in instead of Claude")
    p.add_argument("--version", action="version", version=f"tutor-assistant {__version__}")
    sub = p.add_subparsers(dest="cmd", required=True)

    sub.add_parser("init", help="create the database and show config")

    voice = sub.add_parser("voice", help="describe how you write so drafts sound like you")
    vsub = voice.add_subparsers(dest="voice_cmd", required=True)
    vset = vsub.add_parser("set")
    vset.add_argument("text", nargs="+")
    vsub.add_parser("show")

    st = sub.add_parser("student", help="manage students")
    ssub = st.add_subparsers(dest="student_cmd", required=True)
    for name in ("add", "edit"):
        sp = ssub.add_parser(name)
        sp.add_argument("name")
        sp.add_argument("--board")
        sp.add_argument("--level")
        sp.add_argument("--subject")
        sp.add_argument("--parent")
        sp.add_argument("--notes")
    ssub.add_parser("list")
    ssub.add_parser("show").add_argument("name")
    ssub.add_parser("resolve", help="mark a weak spot as resolved").add_argument("weak_spot_id", type=int)
    ssub.add_parser("fulfil", help="mark a promised resource as sent").add_argument("promise_id", type=int)

    lg = sub.add_parser("log", help="dump your post-session bullets; get drafts queued")
    lg.add_argument("notes", nargs="*", help="the notes (or '-' to read stdin)")
    lg.add_argument("--student", help="override the student name detected from the notes")
    lg.add_argument("--date", help="session date/time ISO 8601 (default now)")
    lg.add_argument("--strict", action="store_true", help="fail instead of creating an unknown student")
    lg.add_argument("--no-materials", action="store_true", help="skip the materials pick")

    q = sub.add_parser("queue", help="review, edit, approve and send drafts")
    qsub = q.add_subparsers(dest="queue_cmd", required=True)
    qsub.add_parser("list").add_argument("--all", action="store_true")
    for name in ("show", "edit", "approve", "reject"):
        qsub.add_parser(name).add_argument("id", type=int)
    qs = qsub.add_parser("send")
    qs.add_argument("id", type=int)
    qs.add_argument("--via", choices=["clipboard", "stdout", "file", "gmail"], default="clipboard")
    qs.add_argument("--to", help="recipient (gmail)")
    qs.add_argument("--subject", help="subject (gmail)")
    qs.add_argument("--file", help="path (file)")

    mt = sub.add_parser("materials", help="index and tag your resources")
    msub = mt.add_subparsers(dest="materials_cmd", required=True)
    mi = msub.add_parser("index", help="index a local folder")
    mi.add_argument("folder")
    mi.add_argument("--board")
    md = msub.add_parser("sync-drive", help="index a Google Drive folder")
    md.add_argument("folder_id")
    md.add_argument("--board")
    msub.add_parser("list").add_argument("--board")
    mtag = msub.add_parser("tag")
    mtag.add_argument("id", type=int)
    mtag.add_argument("--board")
    mtag.add_argument("--topics", help="comma-separated")
    mtag.add_argument("--title")
    msub.add_parser("rm").add_argument("id", type=int)

    sc = sub.add_parser("schedule", help="mirror your lesson slots")
    scsub = sc.add_subparsers(dest="schedule_cmd", required=True)
    sa = scsub.add_parser("add")
    sa.add_argument("student")
    sa.add_argument("start", help="ISO 8601, e.g. 2026-09-19T16:00")
    sa.add_argument("--minutes", type=int, default=60)
    sa.add_argument("--title")
    scsub.add_parser("import").add_argument("file")
    scsub.add_parser("list").add_argument("--days", type=int, default=7)
    scsub.add_parser("rm").add_argument("id", type=int)
    se = scsub.add_parser("export", help="write an .ics with prep reminders and buffers")
    se.add_argument("out")
    se.add_argument("--days", type=int, default=14)
    se.add_argument("--prep", type=int, default=30, help="prep reminder minutes before")
    se.add_argument("--buffer", type=int, default=15, help="buffer block minutes before/after (0 to skip)")
    spush = scsub.add_parser("push", help="push slots straight to Google Calendar (needs google extra)")
    spush.add_argument("--days", type=int, default=14)
    spush.add_argument("--prep", type=int, default=30)

    br = sub.add_parser("brief", help="tomorrow's lessons with what you covered last time")
    br.add_argument("--date", help="tomorrow (default), today, or YYYY-MM-DD")
    br.add_argument("--raw", action="store_true", help="skip Claude; print the dossier as-is")
    br.add_argument("--file", help="also append the brief to this file")

    return p


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    cli = Cli(args)
    try:
        getattr(cli, f"cmd_{args.cmd}")()
    finally:
        cli.db.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
