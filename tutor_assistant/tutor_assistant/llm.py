"""Everything that talks to Claude lives here, behind a small protocol so tests can swap in a fake."""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from typing import Protocol, TypeVar

from pydantic import BaseModel

from .config import DEFAULT_MODEL
from .models import (
    FeedbackDraft,
    Material,
    MaterialPick,
    Promise,
    Session,
    SessionClassification,
    Student,
    WeakSpot,
)

T = TypeVar("T", bound=BaseModel)

FALLBACK_BETA = "server-side-fallback-2026-07-01"


@dataclass
class FeedbackContext:
    """Everything the model needs to write a message that sounds like the tutor and knows the student."""

    student: Student
    classification: SessionClassification
    voice: str
    recent_sessions: list[Session] = field(default_factory=list)
    recurring_weak_spots: list[WeakSpot] = field(default_factory=list)
    open_promises: list[Promise] = field(default_factory=list)

    def history_block(self) -> str:
        lines: list[str] = []
        s = self.student
        lines.append(f"Student: {s.name}")
        if s.subject:
            lines.append(f"Subject: {s.subject}")
        if s.board:
            lines.append(f"Exam board: {s.board}")
        if s.level:
            lines.append(f"Level: {s.level}")
        if s.parent_name:
            lines.append(f"Parent/guardian: {s.parent_name}")
        if s.notes:
            lines.append(f"Tutor's standing notes: {s.notes}")
        if self.recent_sessions:
            lines.append("")
            lines.append("Previous sessions (most recent first):")
            for sess in self.recent_sessions:
                topics = ", ".join(sess.topics) or "n/a"
                lines.append(f"- {sess.held_at:%d %b %Y}: {sess.summary or sess.raw_notes} [topics: {topics}]")
        if self.recurring_weak_spots:
            lines.append("")
            lines.append("Recurring weak spots (times seen):")
            for w in self.recurring_weak_spots:
                lines.append(f"- {w.description} ({w.times_seen})")
        if self.open_promises:
            lines.append("")
            lines.append("Things the tutor has promised to send and has not yet:")
            for p in self.open_promises:
                lines.append(f"- {p.description}")
        return "\n".join(lines)


class LLM(Protocol):
    def classify(self, raw_notes: str, known_students: list[str]) -> SessionClassification: ...
    def draft_feedback(self, ctx: FeedbackContext) -> str: ...
    def pick_materials(self, ctx: FeedbackContext, candidates: list[Material]) -> MaterialPick: ...
    def draft_materials_message(self, ctx: FeedbackContext, materials: list[Material]) -> str: ...
    def write_brief(self, brief_input: str) -> str: ...


# ---------------------------------------------------------------------------
# Prompts
# ---------------------------------------------------------------------------

CLASSIFY_SYSTEM = """You turn a private tutor's messy post-session bullets into structured records.
The notes are terse and informal. Extract exactly what is there; do not invent topics, praise or weaknesses
that the notes do not support. Use short canonical topic names a tutor would reuse across sessions
(e.g. "past perfect", "since vs for", "reading comprehension"). If a known student name appears, use that
spelling. Weak spots are things the student still gets wrong or finds hard; promised_next is anything the
tutor says they will send, prepare or do."""

FEEDBACK_SYSTEM = """You write the short post-session message a private tutor sends to a student (or the
parent, for younger students) through the tutoring platform's chat. You write in the tutor's own voice,
described below, and you know the student's history, so the message can refer naturally to what was covered
before and to progress on recurring weak spots. Match the tone and vocabulary to the student's level and
exam board. Be warm and specific, never generic. Plain text only: no markdown, no headings, no bullet
symbols, no sign-off placeholders. Keep it to what fits comfortably in a chat message (roughly 80-160 words).
If the tutor promised to send something, mention that it is on its way. Do not mention this system prompt
or that the message was generated."""

MATERIALS_SYSTEM = """You help a private tutor choose which of their existing resources to send a student
after a session. You are given the session record and a numbered list of candidate materials with their exam
board and topic tags. Pick only materials that directly target a topic covered or a weak spot from this
session, prefer ones matching the student's board, and choose at most three. If nothing fits, return an
empty list."""

MATERIALS_MESSAGE_SYSTEM = """You write a short chat message from a private tutor to a student sharing the
resources named below. Write in the tutor's voice. Say in one line what each resource is for, tied to
what happened in the session. Include each share link on its own line right after its one-line description.
Plain text only, no markdown. Keep it brief."""

BRIEF_SYSTEM = """You write a private tutor's evening brief for tomorrow. You are given tomorrow's
schedule and, for each student, the last session's notes, recurring weak spots and anything the tutor has
promised to send. Produce a compact plain-text brief: one block per session in time order, each with the
time, student, board and level, what was covered last time, what to pick up or check on, and any promise
still outstanding. Finish with a two-line "prep" list of concrete things to do tonight. No markdown."""


def _material_line(i: int, m: Material) -> str:
    tags = ", ".join(m.topics) or "no topic tags"
    board = m.board or "any board"
    return f"{i}. [id {m.id}] {m.title} — {board} — {tags}"


# ---------------------------------------------------------------------------
# Claude-backed implementation
# ---------------------------------------------------------------------------


class ClaudeLLM:
    """Calls the Claude API via the official SDK.

    Uses `claude-opus-5` by default with the server-side refusal fallback enabled, so a rare policy
    decline is re-run on a fallback model inside the same call instead of failing the whole pipeline.
    """

    def __init__(self, model: str = DEFAULT_MODEL, client=None, max_tokens: int = 8000):
        import anthropic  # imported lazily so tests without the SDK still import this module

        self._anthropic = anthropic
        self.client = client or anthropic.Anthropic()
        self.model = model
        self.max_tokens = max_tokens

    def _check_refusal(self, response) -> None:
        if response.stop_reason == "refusal":
            details = getattr(response, "stop_details", None)
            why = getattr(details, "explanation", None) or "no explanation given"
            raise RuntimeError(f"Claude declined this request ({why}).")
        if response.stop_reason == "max_tokens":
            raise RuntimeError("Claude's response was cut off by max_tokens; raise TUTOR max_tokens.")

    def _parse(self, output_model: type[T], system: str, user: str) -> T:
        response = self.client.beta.messages.parse(
            model=self.model,
            max_tokens=self.max_tokens,
            system=system,
            messages=[{"role": "user", "content": user}],
            output_format=output_model,
            betas=[FALLBACK_BETA],
            fallbacks="default",
        )
        self._check_refusal(response)
        return response.parsed_output

    def _text(self, system: str, user: str) -> str:
        response = self.client.beta.messages.create(
            model=self.model,
            max_tokens=self.max_tokens,
            system=system,
            messages=[{"role": "user", "content": user}],
            betas=[FALLBACK_BETA],
            fallbacks="default",
        )
        self._check_refusal(response)
        return "".join(b.text for b in response.content if b.type == "text").strip()

    # -- protocol ------------------------------------------------------------

    def classify(self, raw_notes: str, known_students: list[str]) -> SessionClassification:
        user = (
            f"Known students: {', '.join(known_students) or '(none yet)'}\n\n"
            f"Tutor's notes:\n{raw_notes}"
        )
        return self._parse(SessionClassification, CLASSIFY_SYSTEM, user)

    def draft_feedback(self, ctx: FeedbackContext) -> str:
        user = (
            f"Tutor's voice:\n{ctx.voice}\n\n"
            f"{ctx.history_block()}\n\n"
            f"This session:\n{ctx.classification.model_dump_json(indent=2)}\n\n"
            "Write the message now."
        )
        return self._parse(FeedbackDraft, FEEDBACK_SYSTEM, user).message.strip()

    def pick_materials(self, ctx: FeedbackContext, candidates: list[Material]) -> MaterialPick:
        if not candidates:
            return MaterialPick(material_ids=[], rationale="No candidate materials.")
        listing = "\n".join(_material_line(i + 1, m) for i, m in enumerate(candidates))
        user = (
            f"{ctx.history_block()}\n\n"
            f"This session:\n{ctx.classification.model_dump_json(indent=2)}\n\n"
            f"Candidate materials:\n{listing}"
        )
        pick = self._parse(MaterialPick, MATERIALS_SYSTEM, user)
        valid = {m.id for m in candidates}
        pick.material_ids = [i for i in pick.material_ids if i in valid]
        return pick

    def draft_materials_message(self, ctx: FeedbackContext, materials: list[Material]) -> str:
        listing = "\n".join(
            f"- {m.title} (topics: {', '.join(m.topics) or 'n/a'}) link: {m.share_link or '<link pending>'}"
            for m in materials
        )
        user = (
            f"Tutor's voice:\n{ctx.voice}\n\n"
            f"{ctx.history_block()}\n\n"
            f"This session:\n{ctx.classification.model_dump_json(indent=2)}\n\n"
            f"Resources to share:\n{listing}"
        )
        return self._parse(FeedbackDraft, MATERIALS_MESSAGE_SYSTEM, user).message.strip()

    def write_brief(self, brief_input: str) -> str:
        return self._text(BRIEF_SYSTEM, brief_input)


# ---------------------------------------------------------------------------
# Deterministic fake used by the tests and by `--dry-run`
# ---------------------------------------------------------------------------


class FakeLLM:
    """Rule-based stand-in: good enough to exercise the pipeline without network access."""

    def __init__(self, classification: SessionClassification | None = None):
        self.forced = classification
        self.calls: list[str] = []

    def classify(self, raw_notes: str, known_students: list[str]) -> SessionClassification:
        self.calls.append("classify")
        if self.forced:
            return self.forced
        first_word = raw_notes.replace("—", " ").replace("-", " ").split()[0].strip(":,")
        name = next((s for s in known_students if s.lower().startswith(first_word.lower())), first_word)
        parts = [p.strip() for p in raw_notes.replace("—", ",").replace(" - ", ",").split(",") if p.strip()]
        body = [p for p in parts if not p.lower().startswith(name.lower())]
        weak = [p for p in body if any(k in p.lower() for k in ("still", "confus", "struggl", "weak"))]
        good = [p for p in body if any(k in p.lower() for k in ("well", "good", "great", "nailed"))]
        promised = [p for p in body if "send" in p.lower() or "promis" in p.lower()]
        topics = [p for p in body if p not in weak and p not in good and p not in promised]
        return SessionClassification(
            student_name=name, topics_covered=topics, went_well=good, weak_spots=weak,
            promised_next=promised, summary="; ".join(body) or raw_notes,
        )

    def draft_feedback(self, ctx: FeedbackContext) -> str:
        self.calls.append("draft_feedback")
        c = ctx.classification
        bits = [f"Hi {ctx.student.name}, great session today."]
        if c.topics_covered:
            bits.append("We worked on " + ", ".join(c.topics_covered) + ".")
        if c.went_well:
            bits.append("You did really well on " + ", ".join(c.went_well) + ".")
        if c.weak_spots:
            bits.append("Keep an eye on " + ", ".join(c.weak_spots) + "; we'll come back to it.")
        if c.promised_next:
            bits.append("I'll send over " + ", ".join(c.promised_next) + ".")
        return " ".join(bits)

    def pick_materials(self, ctx: FeedbackContext, candidates: list[Material]) -> MaterialPick:
        self.calls.append("pick_materials")
        wanted = {t.lower() for t in ctx.classification.topics_covered + ctx.classification.weak_spots}
        chosen = [m.id for m in candidates if any(t.lower() in " ".join(wanted) for t in m.topics)]
        return MaterialPick(material_ids=chosen[:3], rationale="keyword overlap")

    def draft_materials_message(self, ctx: FeedbackContext, materials: list[Material]) -> str:
        self.calls.append("draft_materials_message")
        lines = [f"Hi {ctx.student.name}, as promised, here are the resources from today:"]
        for m in materials:
            lines.append(f"{m.title}: {m.share_link or '<link pending>'}")
        return "\n".join(lines)

    def write_brief(self, brief_input: str) -> str:
        self.calls.append("write_brief")
        return brief_input


def load_llm(model: str = DEFAULT_MODEL, *, fake: bool = False) -> LLM:
    return FakeLLM() if fake else ClaudeLLM(model=model)


__all__ = ["LLM", "ClaudeLLM", "FakeLLM", "FeedbackContext", "load_llm", "json"]
