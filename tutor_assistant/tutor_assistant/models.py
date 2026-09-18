"""Pydantic models shared between the database layer, the Claude calls and the CLI."""

from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field


# ---------------------------------------------------------------------------
# Structured outputs returned by Claude
# ---------------------------------------------------------------------------


class SessionClassification(BaseModel):
    """What Claude extracts from a tutor's messy post-session bullets."""

    student_name: str = Field(description="The student's first name exactly as it appears in the notes.")
    subject: str | None = Field(default=None, description="Subject if it can be inferred, e.g. 'English', 'Maths'.")
    topics_covered: list[str] = Field(default_factory=list, description="Short canonical topic names, e.g. 'past perfect'.")
    went_well: list[str] = Field(default_factory=list, description="Things the student did well.")
    weak_spots: list[str] = Field(default_factory=list, description="Things the student still struggles with.")
    promised_next: list[str] = Field(default_factory=list, description="Resources or actions the tutor promised for next time.")
    homework: list[str] = Field(default_factory=list, description="Homework or practice set for the student.")
    summary: str = Field(description="One or two sentences summarising the session for the tutor's own records.")


class MaterialPick(BaseModel):
    """Which indexed materials fit this session, and why."""

    material_ids: list[int] = Field(default_factory=list, description="IDs of the chosen materials, best first.")
    rationale: str = Field(description="One sentence per chosen material explaining the fit.")


class FeedbackDraft(BaseModel):
    """The message the tutor pastes into the platform chat."""

    message: str = Field(description="The full message, ready to paste. Plain text, no markdown.")


# ---------------------------------------------------------------------------
# Database records
# ---------------------------------------------------------------------------


class Student(BaseModel):
    id: int
    name: str
    board: str | None = None
    level: str | None = None
    subject: str | None = None
    parent_name: str | None = None
    notes: str | None = None
    created_at: datetime


class Session(BaseModel):
    id: int
    student_id: int
    held_at: datetime
    raw_notes: str
    summary: str | None = None
    topics: list[str] = Field(default_factory=list)
    went_well: list[str] = Field(default_factory=list)
    weak_spots: list[str] = Field(default_factory=list)
    homework: list[str] = Field(default_factory=list)
    created_at: datetime


class Topic(BaseModel):
    student_id: int
    topic: str
    times_covered: int
    first_covered: datetime
    last_covered: datetime


class WeakSpot(BaseModel):
    id: int
    student_id: int
    description: str
    times_seen: int
    first_seen: datetime
    last_seen: datetime
    resolved_at: datetime | None = None


class Promise(BaseModel):
    id: int
    student_id: int
    session_id: int | None
    description: str
    created_at: datetime
    fulfilled_at: datetime | None = None


class Material(BaseModel):
    id: int
    title: str
    location: str  # local path or Drive file id
    source: Literal["local", "drive"] = "local"
    board: str | None = None
    topics: list[str] = Field(default_factory=list)
    kind: str | None = None  # html, docx, pdf ...
    share_link: str | None = None
    created_at: datetime


OutboxKind = Literal["feedback", "materials"]
OutboxStatus = Literal["pending", "approved", "sent", "rejected"]


class OutboxItem(BaseModel):
    id: int
    student_id: int
    session_id: int | None
    kind: OutboxKind
    body: str
    material_ids: list[int] = Field(default_factory=list)
    status: OutboxStatus = "pending"
    created_at: datetime
    sent_at: datetime | None = None
    sent_via: str | None = None


class Slot(BaseModel):
    id: int
    student_id: int | None
    title: str
    starts_at: datetime
    ends_at: datetime
    source: Literal["manual", "ics"] = "manual"
    uid: str | None = None
