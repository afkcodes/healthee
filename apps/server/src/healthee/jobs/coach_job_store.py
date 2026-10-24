"""The weekly job as a ``challenge`` row — read what is there, write the suggestion.

The job is an ordinary ``suggested`` challenge carrying the ``0023`` coach columns, so the
existing adopt endpoint ("I'm in") starts it and the existing evaluation scores it. Nothing
here decides a size; that is ``coach_sizing``. A coach job is the one whose ``days_required``
is set — the standalone generator never writes it.
"""

from __future__ import annotations

from datetime import date
from typing import Any, LiteralString, cast
from uuid import UUID

from healthee.challenges import store
from healthee.challenges.scales import ROUND_STEP, round_target
from healthee.derive._common import Cur
from healthee.jobs.coach_job import CoachJob
from healthee.jobs.coach_sizing import PrevJob

WINDOW_DAYS = 7
FLOOR_FRACTION = 0.5  # "Half credit, streak survives" (the design's bad-day rule)
_SLEEP_METRICS = frozenset({"tst_min", "sri"})


def _coach_job_query(where: str) -> LiteralString:
    return cast(
        LiteralString,
        f"SELECT {store.SELECT} FROM challenge WHERE user_id = %s AND days_required IS NOT NULL "
        f"{where} ORDER BY created_at DESC, id DESC LIMIT 1",
    )


def latest_job(cur: Cur, user_id: UUID) -> dict[str, Any] | None:
    """The newest coach job in any state (a never-adopted one repeats)."""
    cur.execute(_coach_job_query(""), (user_id,))
    found = cur.fetchone()
    return store.row(found) if found else None


def active_job(cur: Cur, user_id: UUID) -> dict[str, Any] | None:
    """The coach job running now, if any."""
    cur.execute(_coach_job_query("AND status = 'active'"), (user_id,))
    found = cur.fetchone()
    return store.row(found) if found else None


def prev_of(row: dict[str, Any] | None) -> PrevJob | None:
    """The sizing guard's view of a stored job."""
    if row is None:
        return None
    return PrevJob(row["metric"], float(row["target_value"]), int(row["days_required"]))


def job_from_row(row: dict[str, Any]) -> CoachJob:
    """A stored job as a ``CoachJob`` — the model-free repeat."""
    return CoachJob(
        action=row["action_text"] or row["title"],
        metric=row["metric"],
        target=float(row["target_value"]),
        days_required=int(row["days_required"]),
        slot=row["slot_text"] or "same time as last week",
        floor=row["floor_text"] or "half of the target",
        counts_when=row["counts_when"] or "when the strap logs the target",
    )


def floor_value_for(metric: str, target: float) -> float:
    """Half the target on the metric's own step, always below the target."""
    step = float(ROUND_STEP.get(metric, 1))
    floor = max(step, round_target(metric, target * FLOOR_FRACTION))
    return floor if floor < target else max(step / 2, target * FLOOR_FRACTION)


def insert_job(
    cur: Cur, user_id: UUID, day: date, job: CoachJob, *, why: str, note_ids: list[str]
) -> int:
    """Replace the un-adopted suggestion with this week's job; returns the challenge id."""
    store.delete_suggestions(cur, user_id)
    return store.insert_suggested(
        cur,
        user_id,
        day,
        {
            "title": job.action,
            "why": why,
            "category": "sleep" if job.metric in _SLEEP_METRICS else "activity",
            "difficulty": "standard",
            "metric": job.metric,
            "comparator": ">=",
            "target_value": job.target,
            "cadence": "daily",
            "window_days": WINDOW_DAYS,
            "research_note_ids": note_ids,
            "action_text": job.action,
            "slot_text": job.slot,
            "floor_value": floor_value_for(job.metric, job.target),
            "floor_text": job.floor,
            "counts_when": job.counts_when,
            "days_required": job.days_required,
        },
    )
