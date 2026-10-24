"""The weekly coach: one review and ONE job per ISO week, written once and stored.

``generate_week`` is the single writer — the Sunday sweep and ``POST /api/coach/review``
both call it, so the Coach screen, the ledger's ``pattern`` and the job card all read one
stored review. The first caller in a week generates (a ``kv`` claim keeps a concurrent
second caller from generating again); everyone after reads the stored row.

The model words the job; the size is the guard's (``coach_sizing``). When the model cannot
give an allowed size in two tries, or cannot be grounded at all, the previous job repeats
with model-free text — and with no previous job and no readings there is nothing honest to
say, so nothing is written.
"""

from __future__ import annotations

import time
from datetime import UTC, date, datetime
from typing import Any
from uuid import UUID

from healthee.core.db import tenant_transaction
from healthee.core.logging import get_logger
from healthee.core.tenancy import user_today
from healthee.insights.client import LLMClient
from healthee.jobs import coach_kv as kv
from healthee.jobs.coach_inputs import CoachInputs, read_inputs
from healthee.jobs.coach_job import CoachJob
from healthee.jobs.coach_job_store import insert_job, job_from_row
from healthee.jobs.coach_llm import propose
from healthee.jobs.coach_sizing import Allowed, decide
from healthee.jobs.coach_task import WEEKLY_TASK

log = get_logger(__name__)

WAIT_SECONDS = 90
_POLL_SECONDS = 1.0


class ReviewBusyError(RuntimeError):
    """Another request is generating this week's review and did not finish in time."""


def _question(inputs: CoachInputs, allowed: Allowed) -> str:
    """The task, the guard's range in words, then the owner's signals."""
    thin = (
        "COVERAGE: last week has too few readings to judge. "
        "Say so in the review and repeat the job.\n"
        if inputs.thin_last_week
        else ""
    )
    return (
        f"{WEEKLY_TASK}\n{thin}SIZE RULE (enforced in code): {allowed.statement()}\n\n"
        f"# SIGNALS (anchor every number to these)\n\n{inputs.text}"
    )


def _allowed(inputs: CoachInputs) -> Allowed:
    hold = "a job is already running, so it stays" if inputs.active_row else None
    prev = inputs.prev
    return decide(prev, inputs.job_weeks, thin_last_week=inputs.thin_last_week, hold=hold)


def _job_dict(job: CoachJob, challenge_id: int) -> dict[str, Any]:
    return job.model_dump() | {"challenge_id": challenge_id}


def _payload(today: date, job: dict, texts: dict, grounding: dict) -> dict[str, Any]:
    monday, sunday = kv.week_bounds(today)
    return {
        "week": kv.week_label(today),
        "week_from": monday.isoformat(),
        "week_to": sunday.isoformat(),
        "job": job,
        **texts,
        **grounding,
        "generated_at": datetime.now(tz=UTC).isoformat(),
    }


def _fallback_texts(job: CoachJob) -> tuple[dict, dict]:
    texts = {
        "review": (
            "I could not write a full review this time, so last week's job repeats unchanged."
        ),
        "pattern": None,
        "today": f"This week's job: {job.action}. On a bad day: {job.floor}.",
    }
    return texts, {"rationale": None, "evidence_grade": None, "research_note_ids": []}


def _build(
    user_id: UUID, tz: str, today: date, *, client: LLMClient | None, model: str | None
) -> dict | None:
    inputs = read_inputs(user_id, tz, today)
    if not inputs.has_data and inputs.prev is None:
        log.info("coach week[%s]: no readings and no earlier job — nothing to write", user_id)
        return None
    allowed = _allowed(inputs)
    week = propose(
        _question(inputs, allowed),
        user_id,
        tz,
        weekly=True,
        allowed=allowed,
        client=client,
        model=model,
    )
    if week is None and inputs.prev_row is None:
        return None
    job = week.job if week and week.job else job_from_row(inputs.prev_row or {})
    texts = (
        {"review": week.review, "pattern": week.pattern, "today": week.today}
        if week
        else _fallback_texts(job)[0]
    )
    grounding = (
        {
            "rationale": week.rationale,
            "evidence_grade": week.evidence_grade,
            "research_note_ids": week.research_note_ids,
        }
        if week
        else _fallback_texts(job)[1]
    )
    return _commit(user_id, today, inputs, job, texts, grounding)


def _commit(
    user_id: UUID, today: date, inputs: CoachInputs, job: CoachJob, texts: dict, grounding: dict
) -> dict:
    """Write the job (unless one is running) and the review in ONE transaction."""
    with tenant_transaction(user_id) as cur:
        if inputs.active_row:
            job = job_from_row(inputs.active_row)
            cid = int(inputs.active_row["id"])
        else:
            cid = insert_job(
                cur,
                user_id,
                today,
                job,
                why=grounding["rationale"] or "The same job as last week.",
                note_ids=grounding["research_note_ids"],
            )
        payload = _payload(today, _job_dict(job, cid), texts, grounding)
        kv.put_json(cur, user_id, kv.key_for_week(today), payload)
        if texts.get("today"):
            line = {
                "text": texts["today"],
                "source": "weekly",
                "generated_at": payload["generated_at"],
            }
            kv.put_json(cur, user_id, kv.today_key(kv.target_day(today)), line)
    return payload


def read_stored(user_id: UUID, today: date) -> dict | None:
    """The stored review for the week ``today`` belongs to, or ``None``."""
    with tenant_transaction(user_id) as cur:
        return kv.get_json(cur, user_id, kv.key_for_week(today))


def _await_other(user_id: UUID, today: date) -> dict:
    deadline = time.monotonic() + WAIT_SECONDS
    while time.monotonic() < deadline:
        stored = read_stored(user_id, today)
        if stored is not None:
            return stored
        time.sleep(_POLL_SECONDS)
    raise ReviewBusyError("this week's review is still being written — try again shortly")


def generate_week(
    user_id: UUID,
    tz: str,
    today: date | None = None,
    *,
    client: LLMClient | None = None,
    model: str | None = None,
) -> tuple[dict | None, bool]:
    """``(review, cached)`` for the owner's current review week; ``None`` when nothing can
    honestly be written (no readings and no earlier job). Generates at most once a week."""
    today = today or user_today(tz)
    stored = read_stored(user_id, today)
    if stored is not None:
        return stored, True
    with tenant_transaction(user_id) as cur:
        won = kv.claim(cur, user_id, kv.claim_key(today))
    if not won:
        return _await_other(user_id, today), True
    try:
        stored = read_stored(user_id, today)  # a winner may have finished before our claim
        if stored is not None:
            return stored, True
        return _build(user_id, tz, today, client=client, model=model), False
    finally:
        with tenant_transaction(user_id) as cur:
            kv.release(cur, user_id, kv.claim_key(today))
