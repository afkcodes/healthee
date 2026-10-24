"""The daily check-in: at most two sentences on where the owner stands on this week's job.

Cheap by construction: no active job means there is nothing to check in on, and a job
already done this week is answered from the numbers with no model call ("say so and stop").
Only a job still in play asks the model, and an unusable answer falls back to a model-free
line built from the stored job and today's recovery — a red zone (score under 34) swaps to
the easy version and says why, whichever way the line was written.
"""

from __future__ import annotations

from datetime import UTC, date, datetime
from uuid import UUID

from healthee.core.db import tenant_transaction
from healthee.core.tenancy import user_today
from healthee.insights.client import LLMClient
from healthee.jobs import coach_kv as kv
from healthee.jobs.coach_inputs import CoachInputs, read_inputs
from healthee.jobs.coach_llm import propose
from healthee.jobs.coach_task import DAILY_TASK, CoachWeek
from healthee.jobs.coach_weeks import ZONE_LOW


def done_line(done: int, asked: int) -> str:
    """The "already done" line — numbers only, no model."""
    return f"This week's job is done: {done} of {asked} days. Nothing more to do."


def fallback_line(job: dict, done: int, recovery: tuple[int, str] | None) -> str:
    """The model-free line. Red recovery gives the floor and says why."""
    asked = int(job["days_required"])
    if recovery and recovery[1] == ZONE_LOW:
        return (
            f"Recovery is {recovery[0]} out of 100, so take the easy version today: "
            f"{job['floor_text']}. {done} of {asked} days done."
        )
    return f"{done} of {asked} days done. Today: {job['action_text']}, {job['slot_text']}."


def _red_must_say_why(recovery: tuple[int, str] | None):
    def check(week: CoachWeek) -> str | None:
        if recovery and recovery[1] == ZONE_LOW and "recover" not in week.today.lower():
            return "recovery is in the red zone: swap to the easy version and say why"
        return None

    return check


def _line(inputs: CoachInputs, user_id: UUID, tz: str, client, model) -> tuple[str, str]:
    job, active = inputs.active_row, inputs.active
    assert job is not None and active is not None  # noqa: S101 — the caller checked
    asked = int(job["days_required"])
    if active.done_days >= asked:
        return done_line(active.done_days, asked), "rule"
    question = f"{DAILY_TASK}\n# SIGNALS (anchor every number to these)\n\n{inputs.text}"
    week = propose(
        question,
        user_id,
        tz,
        weekly=False,
        extra_check=_red_must_say_why(inputs.recovery),
        client=client,
        model=model,
    )
    if week is None:
        return fallback_line(job, active.done_days, inputs.recovery), "rule"
    return week.today, "model"


def generate_today(
    user_id: UUID,
    tz: str,
    today: date | None = None,
    *,
    client: LLMClient | None = None,
    model: str | None = None,
) -> dict:
    """Write today's check-in line. Returns a small status dict for the job surface."""
    today = today or user_today(tz)
    inputs = read_inputs(user_id, tz, today)
    if inputs.active_row is None or inputs.active is None:
        return {"ok": True, "skipped": "no active job"}
    text, source = _line(inputs, user_id, tz, client, model)
    payload = {"text": text, "source": source, "generated_at": datetime.now(tz=UTC).isoformat()}
    with tenant_transaction(user_id) as cur:
        kv.put_json(cur, user_id, kv.today_key(today), payload)
    return {"ok": True, "source": source}


def read_today_line(user_id: UUID, today: date) -> str | None:
    """The stored check-in for ``today``, or ``None``."""
    with tenant_transaction(user_id) as cur:
        found = kv.get_json(cur, user_id, kv.today_key(today))
    text = found.get("text") if found else None
    return text if isinstance(text, str) else None
