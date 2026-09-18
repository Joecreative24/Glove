"""notes in -> classify -> store -> feedback draft + materials pick -> queue for approval -> send."""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime

from .db import Database
from .llm import LLM, FeedbackContext
from .materials import DriveMaterials, candidate_materials
from .models import Material, OutboxItem, Session, SessionClassification, Student

DEFAULT_VOICE = (
    "Friendly, encouraging and direct. First names, contractions, no exclamation-mark pile-ups. "
    "Specific praise before specific next steps. British English."
)


@dataclass
class LogResult:
    student: Student
    session: Session
    classification: SessionClassification
    feedback: OutboxItem
    materials: OutboxItem | None = None
    picked: list[Material] = field(default_factory=list)
    created_student: bool = False


def get_voice(db: Database) -> str:
    return db.get_setting("voice") or DEFAULT_VOICE


def build_context(db: Database, student: Student, classification: SessionClassification,
                  *, exclude_session_id: int | None = None) -> FeedbackContext:
    recent = [s for s in db.recent_sessions(student.id, limit=6) if s.id != exclude_session_id][:5]
    return FeedbackContext(
        student=student,
        classification=classification,
        voice=get_voice(db),
        recent_sessions=recent,
        recurring_weak_spots=[w for w in db.weak_spots_for(student.id) if w.times_seen > 1][:5],
        open_promises=db.open_promises(student.id),
    )


def log_session(db: Database, llm: LLM, raw_notes: str, *, student_name: str | None = None,
                held_at: datetime | None = None, create_missing: bool = True,
                drive: DriveMaterials | None = None, with_materials: bool = True) -> LogResult:
    """Run the whole loop for one session's notes. Nothing is sent: results land in the outbox."""
    known = [s.name for s in db.list_students()]
    classification = llm.classify(raw_notes, known)
    if student_name:
        classification.student_name = student_name

    created = False
    student = db.find_student(classification.student_name)
    if student is None:
        if not create_missing:
            raise LookupError(f"Unknown student '{classification.student_name}'. Add them first or pass --student.")
        student = db.add_student(classification.student_name, subject=classification.subject)
        created = True
    elif classification.subject and not student.subject:
        student = db.update_student(student.id, subject=classification.subject)

    # Context is built *before* this session's promises are stored, so "still to send" means older ones.
    prior_promises = db.open_promises(student.id)

    session = db.add_session(
        student.id, raw_notes, held_at=held_at, summary=classification.summary,
        topics=classification.topics_covered, went_well=classification.went_well,
        weak_spots=classification.weak_spots, homework=classification.homework,
    )
    for promise in classification.promised_next:
        db.add_promise(student.id, promise, session_id=session.id)

    ctx = build_context(db, student, classification, exclude_session_id=session.id)
    ctx.open_promises = prior_promises

    feedback_text = llm.draft_feedback(ctx)
    feedback_item = db.queue(student.id, "feedback", feedback_text, session_id=session.id)
    result = LogResult(student=student, session=session, classification=classification,
                       feedback=feedback_item, created_student=created)

    if with_materials:
        candidates = candidate_materials(db, student, classification)
        if candidates:
            pick = llm.pick_materials(ctx, candidates)
            chosen = [m for m in candidates if m.id in pick.material_ids]
            chosen.sort(key=lambda m: pick.material_ids.index(m.id))
            if chosen:
                for m in chosen:
                    if m.source == "drive" and not m.share_link and drive is not None:
                        m.share_link = drive.ensure_share_link(db, m)
                body = llm.draft_materials_message(ctx, chosen)
                result.materials = db.queue(student.id, "materials", body, session_id=session.id,
                                            material_ids=[m.id for m in chosen])
                result.picked = chosen
    return result


def mark_sent(db: Database, item: OutboxItem, via: str) -> OutboxItem:
    """Record a send. Sending a materials message fulfils the promises made in that session."""
    updated = db.set_outbox_status(item.id, "sent", via=via)
    if item.kind == "materials" and item.session_id is not None:
        db.fulfil_promises_for_session(item.session_id)
    return updated
