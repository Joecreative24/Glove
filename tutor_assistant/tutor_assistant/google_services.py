"""Optional Google plumbing (Drive share links, Gmail drafts, Calendar push).

Only imported when a command actually needs Google. Install with `pip install "tutor-assistant[google]"`,
create an OAuth desktop client in Google Cloud Console, and point GOOGLE_CLIENT_SECRET_FILE at the JSON.
"""

from __future__ import annotations

import base64
from datetime import datetime
from email.message import EmailMessage
from pathlib import Path

from .config import Settings
from .models import Slot

SCOPES = [
    "https://www.googleapis.com/auth/drive",
    "https://www.googleapis.com/auth/gmail.compose",
    "https://www.googleapis.com/auth/calendar.events",
]


def _credentials(settings: Settings):
    try:
        from google.auth.transport.requests import Request
        from google.oauth2.credentials import Credentials
        from google_auth_oauthlib.flow import InstalledAppFlow
    except ImportError as e:  # pragma: no cover - depends on optional extra
        raise RuntimeError('Google support needs the extra: pip install "tutor-assistant[google]"') from e

    token_file = Path(settings.google_token_file)
    creds = None
    if token_file.exists():
        creds = Credentials.from_authorized_user_file(str(token_file), SCOPES)
    if creds and creds.expired and creds.refresh_token:
        creds.refresh(Request())
    elif not creds or not creds.valid:
        if not settings.google_client_secret_file or not settings.google_client_secret_file.exists():
            raise RuntimeError("Set GOOGLE_CLIENT_SECRET_FILE to your OAuth client JSON to log in to Google.")
        flow = InstalledAppFlow.from_client_secrets_file(str(settings.google_client_secret_file), SCOPES)
        creds = flow.run_local_server(port=0)
        token_file.parent.mkdir(parents=True, exist_ok=True)
        token_file.write_text(creds.to_json(), encoding="utf-8")
    return creds


def _build(settings: Settings, api: str, version: str):
    from googleapiclient.discovery import build  # pragma: no cover

    return build(api, version, credentials=_credentials(settings), cache_discovery=False)


def drive_service(settings: Settings):
    return _build(settings, "drive", "v3")


def gmail_service(settings: Settings):
    return _build(settings, "gmail", "v1")


def calendar_service(settings: Settings):
    return _build(settings, "calendar", "v3")


def create_gmail_draft(service, *, to: str, subject: str, body: str) -> str:
    """Create a Gmail draft (never sends). Returns the draft id."""
    msg = EmailMessage()
    msg["To"] = to
    msg["Subject"] = subject
    msg.set_content(body)
    raw = base64.urlsafe_b64encode(msg.as_bytes()).decode()
    draft = service.users().drafts().create(userId="me", body={"message": {"raw": raw}}).execute()
    return draft["id"]


def push_slots_to_calendar(service, slots: list[Slot], *, tz: str, calendar_id: str = "primary",
                           prep_minutes: int = 30, descriptions: dict[int, str] | None = None) -> list[str]:
    """Insert or update one Google Calendar event per slot (idempotent via a stable event id)."""
    ids: list[str] = []
    for slot in slots:
        event_id = "tutor" + (slot.uid or f"slot{slot.id}").lower().replace("@", "").replace("-", "")
        event_id = "".join(ch for ch in event_id if ch in "abcdefghijklmnopqrstuv0123456789")[:1024] or f"tutorslot{slot.id}"
        body = {
            "id": event_id,
            "summary": slot.title,
            "description": (descriptions or {}).get(slot.id, ""),
            "start": {"dateTime": slot.starts_at.isoformat(), "timeZone": tz},
            "end": {"dateTime": slot.ends_at.isoformat(), "timeZone": tz},
            "reminders": {"useDefault": False,
                          "overrides": [{"method": "popup", "minutes": prep_minutes}]},
        }
        try:
            service.events().insert(calendarId=calendar_id, body=body).execute()
        except Exception as e:  # already exists -> update in place
            if "409" not in str(e) and "duplicate" not in str(e).lower():
                raise
            service.events().update(calendarId=calendar_id, eventId=event_id, body=body).execute()
        ids.append(event_id)
    return ids


__all__ = ["drive_service", "gmail_service", "calendar_service", "create_gmail_draft",
           "push_slots_to_calendar", "datetime"]
