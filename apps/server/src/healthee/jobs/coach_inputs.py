"""Everything the coach is shown, read once: the prompt text and the facts the guard needs.

``build_recs_signals`` (profile, MVPA gap, findings) stays the base; the four blocks the
spec adds — COMMITMENTS, WEEKS, CURRENT, RECOVERY — are appended. The job history the
sizing guard needs is derived from the same COMMITMENTS rows, by a pure function, so the
prompt and the guard can never disagree about what was done.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date, timedelta
from uuid import UUID

from healthee.challenges import series
from healthee.core.db import tenant_transaction
from healthee.jobs import coach_commitments as cc
from healthee.jobs import coach_weeks as cw
from healthee.jobs.coach_job_store import active_job, latest_job, prev_of
from healthee.jobs.coach_sizing import JobWeek, PrevJob
from healthee.jobs.recs_context import build_recs_signals


@dataclass
class CoachInputs:
    """One read of the owner's state for a coach run."""

    text: str
    prev: PrevJob | None
    prev_row: dict | None
    job_weeks: list[JobWeek]
    thin_last_week: bool
    active: cc.Commitment | None
    active_row: dict | None
    today_value: float | None
    recovery: tuple[int, str] | None
    has_data: bool


def settled_jobs(commitments: list[cc.Commitment], today: date) -> list[cc.Commitment]:
    """Coach jobs whose week is over (or that ended early), oldest first."""
    return [
        c
        for c in commitments
        if c.is_job and (c.status != "active" or c.adopted_day + timedelta(days=6) < today)
    ]


def _fairly_judged(c: cc.Commitment) -> bool:
    """Whether the strap could have judged this job — missing readings could have made it done."""
    return c.provable_days >= (c.days_required or 0) or c.done_days >= (c.days_required or 0)


def job_history(commitments: list[cc.Commitment], today: date) -> tuple[list[JobWeek], bool]:
    """``(judged job weeks, last week too thin to judge)`` — pure."""
    settled = settled_jobs(commitments, today)
    judged = [
        JobWeek(c.done_days, c.days_required or 0, c.provable_days)
        for c in settled
        if _fairly_judged(c)
    ]
    thin = bool(settled) and not _fairly_judged(settled[-1])
    return judged, thin


def _has_data(weeks: list[cw.WeekFacts]) -> bool:
    return any(w.steps or w.brisk or w.sleep for w in weeks)


def read_inputs(user_id: UUID, tz: str, today: date) -> CoachInputs:
    """Read the prompt's context and the guard's facts in one owner-scoped transaction."""
    with tenant_transaction(user_id) as cur:
        commitments = cc.read_commitments(cur, user_id, tz, today)
        weeks = cw.read_weeks(cur, user_id, tz, today)
        recovery = cw.read_recovery(cur, user_id, tz)
        row_now = active_job(cur, user_id)
        latest = latest_job(cur, user_id)
        active = next((c for c in commitments if row_now and c.id == row_now["id"]), None)
        value = (
            series.metric_series(cur, user_id, tz, active.metric, today, today).get(today)
            if active
            else None
        )
    judged, thin = job_history(commitments, today)
    blocks = [
        cc.render_commitments(commitments),
        cw.render_weeks(weeks, today),
        cw.render_current(active, value, today),
        cw.render_recovery(recovery),
    ]
    text = "\n".join([build_recs_signals(user_id, tz), *blocks])
    return CoachInputs(
        text,
        prev_of(latest),
        latest,
        judged,
        thin,
        active,
        row_now,
        value,
        recovery,
        _has_data(weeks),
    )
