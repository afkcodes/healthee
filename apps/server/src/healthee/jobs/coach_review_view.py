"""The wire payload of ``POST /api/coach/review`` — shaped from the stored review.

The stored row is the weekly job's; the response adds only what is NOT stored with it: the
latest check-in line for today and whether this call was served from storage.
"""

from __future__ import annotations

from datetime import UTC, date, datetime
from uuid import UUID

from healthee.jobs import coach_kv as kv
from healthee.jobs.coach_today import read_today_line

NO_DATA_REVIEW = (
    "There are not enough readings yet to review a week or size a job. "
    "Wear the strap and sync it, and this fills in."
)


def view(stored: dict, user_id: UUID, today: date, *, cached: bool) -> dict:
    """The response for a stored review."""
    return {
        "week": stored["week"],
        "week_from": stored["week_from"],
        "week_to": stored["week_to"],
        "review": stored.get("review"),
        "pattern": stored.get("pattern"),
        "job": stored.get("job"),
        "today_line": read_today_line(user_id, today),
        "rationale": stored.get("rationale"),
        "evidence_grade": stored.get("evidence_grade"),
        "research_note_ids": stored.get("research_note_ids") or [],
        "generated_at": stored["generated_at"],
        "cached": cached,
    }


def no_data_view(user_id: UUID, today: date) -> dict:
    """Nothing honest to write: a plain statement, no job, nothing stored."""
    monday, sunday = kv.week_bounds(today)
    stored = {
        "week": kv.week_label(today),
        "week_from": monday.isoformat(),
        "week_to": sunday.isoformat(),
        "review": NO_DATA_REVIEW,
        "generated_at": datetime.now(tz=UTC).isoformat(),
    }
    return view(stored, user_id, today, cached=False)
