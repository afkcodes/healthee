"""Shared coach test fixtures: a valid answer, and fakes for the owner-state reads."""

from __future__ import annotations

import json
from datetime import date
from typing import Any

from tests.insights._ids import ESTABLISHED_ID

from healthee.insights.grounded import GroundedResult
from healthee.jobs.coach_inputs import CoachInputs
from healthee.jobs.coach_sizing import JobWeek, PrevJob

TODAY = date(2026, 10, 14)  # a Wednesday: the review is for this ISO week (2026-W42)
SUNDAY = date(2026, 10, 18)

JOB: dict[str, Any] = {
    "action": "Walk briskly for 20 minutes",
    "metric": "mvpa_min",
    "target": 20,
    "unit": "min",
    "days_required": 4,
    "slot": "after 10 pm, once your evening block ends",
    "floor": "10 minutes counts as half",
    "counts_when": "when the strap logs 20 brisk minutes",
}


def answer(**over: Any) -> dict[str, Any]:
    """A valid weekly answer; ``over`` replaces top-level keys, ``job=`` merges into the job."""
    base: dict[str, Any] = {
        "review": "Straight talk. You walked 3 days last week. Brisk minutes fell to 66.",
        "pattern": "You say yes on Mondays and miss by Thursday.",
        "job": dict(JOB),
        "today": "Start tonight after 10. Twenty minutes gets today counted.",
        "rationale": f"Regular brisk walking supports fitness [{ESTABLISHED_ID}].",
        "evidence_grade": 3,
        "research_note_ids": [ESTABLISHED_ID],
    }
    job = over.pop("job", None)
    base.update(over)
    if isinstance(job, dict):
        base["job"] = {**JOB, **job}
    return base


def grounded(data: dict[str, Any] | None) -> GroundedResult:
    """What ``grounded_ask`` returns for a validated JSON answer."""
    if data is None:
        return GroundedResult(text="fallback", validated=False)
    return GroundedResult(text=json.dumps(data), data=data)


def inputs(**over: Any) -> CoachInputs:
    """Owner state with readings, no earlier job."""
    base: dict[str, Any] = {
        "text": "SIGNALS",
        "prev": None,
        "prev_row": None,
        "job_weeks": [],
        "thin_last_week": False,
        "active": None,
        "active_row": None,
        "today_value": None,
        "recovery": (72, "high"),
        "has_data": True,
    }
    return CoachInputs(**{**base, **over})


def prev_job(target: float = 20, days: int = 4) -> PrevJob:
    return PrevJob("mvpa_min", float(target), days)


def weeks(*done: bool, days: int = 4) -> list[JobWeek]:
    return [JobWeek(days if d else 1, days, 7) for d in done]
