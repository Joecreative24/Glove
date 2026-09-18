from datetime import date, datetime

from tutor_assistant.llm import FakeLLM
from tutor_assistant.schedule import brief_input, export_ics, import_ics, parse_ics, write_brief

ICS = """BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:abc@gostudent
DTSTART:20260919T150000Z
DTEND:20260919T160000Z
SUMMARY:Lesson with Dapo Adeyemi
END:VEVENT
BEGIN:VEVENT
UID:def@gostudent
DTSTART;TZID=Europe/London:20260919T180000
DTEND;TZID=Europe/London:20260919T190000
SUMMARY:Ana \\, maths
  (continued)
END:VEVENT
BEGIN:VEVENT
UID:ghi
DTSTART;VALUE=DATE:20260920
SUMMARY:Unknown kid
END:VEVENT
END:VCALENDAR
"""


def test_parse_ics_handles_utc_tzid_and_folding():
    evs = parse_ics(ICS, tz="Europe/London")
    assert evs[0].start == datetime(2026, 9, 19, 16, 0)  # BST = UTC+1
    assert evs[1].start == datetime(2026, 9, 19, 18, 0)
    assert evs[1].summary == "Ana , maths (continued)"
    assert evs[2].start == datetime(2026, 9, 20) and evs[2].end == datetime(2026, 9, 20, 1)


def test_import_matches_students_and_export_has_alarms_and_buffers(db):
    dapo = db.add_student("Dapo Adeyemi", board="AQA", level="GCSE")
    db.add_student("Ana")
    db.add_session(dapo.id, "past perfect", held_at=datetime(2026, 9, 12, 16), summary="Did past perfect", topics=["past perfect"], weak_spots=["since vs for"])
    db.add_promise(dapo.id, "tense worksheet")
    slots = import_ics(db, ICS)
    assert [s.student_id for s in slots] == [dapo.id, db.find_student("Ana").id, None]

    ics = export_ics(db, slots[:1], prep_minutes=30, buffer_minutes=15)
    assert "TRIGGER:-PT30M" in ics
    assert "SUMMARY:Buffer before: Lesson with Dapo Adeyemi" in ics
    assert "DTSTART;TZID=Europe/London:20260919T154500" in ics
    assert "DTSTART;TZID=Europe/London:20260919T170000" in ics  # buffer after
    assert "Still to send: tense worksheet" in ics
    assert ics.count("BEGIN:VEVENT") == 3


def test_brief(db):
    dapo = db.add_student("Dapo", board="AQA", level="GCSE", subject="English")
    db.add_session(dapo.id, "raw", held_at=datetime(2026, 9, 12, 16), summary="Past perfect; reading comp went well",
                   topics=["past perfect"], weak_spots=["since vs for"], homework=["p.12 ex 3"])
    db.upsert_slot(title="Lesson: Dapo", starts_at=datetime(2026, 9, 19, 16), ends_at=datetime(2026, 9, 19, 17), student_id=dapo.id)
    text = brief_input(db, date(2026, 9, 19))
    assert "16:00-17:00  Lesson: Dapo" in text
    assert "English, AQA, GCSE" in text
    assert "homework set: p.12 ex 3" in text
    assert "since vs for (x1)" in text
    assert write_brief(db, FakeLLM(), date(2026, 9, 19)) == text
    assert brief_input(db, date(2026, 9, 25)).startswith("No lessons")


def test_calendar_event_ids_are_stable_and_distinct(db):
    from tutor_assistant.google_services import calendar_event_id

    a = db.upsert_slot(title="A", starts_at=datetime(2026, 9, 19, 16), ends_at=datetime(2026, 9, 19, 17), uid="wxyz@x")
    b = db.upsert_slot(title="B", starts_at=datetime(2026, 9, 19, 17), ends_at=datetime(2026, 9, 19, 18), uid="wxyz@y")
    ids = {calendar_event_id(a), calendar_event_id(b)}
    assert len(ids) == 2
    assert all(set(i) <= set("abcdefghijklmnopqrstuv0123456789") and 5 <= len(i) <= 1024 for i in ids)
    assert calendar_event_id(a) == calendar_event_id(db.upsert_slot(title="A2", starts_at=a.starts_at, ends_at=a.ends_at, uid="wxyz@x"))
