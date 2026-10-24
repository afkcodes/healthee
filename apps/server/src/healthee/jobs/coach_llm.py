"""One grounded coach call: ask, validate, and retry ONCE with the allowed range stated.

The only LLM path of the coach, and it is ``grounded_ask`` — the choke point validates
citations, tone and grade wording of every user-facing string before anything reaches this
module. What is left to check here is structure (``CoachWeek``), the PROVED grade
(``coach_checks.provable_grade``) and, for the weekly job, the sizing rule
(``coach_sizing``). A model that cannot satisfy them in two tries yields ``None`` and the
caller falls back to a model-free text; the week is never left with nothing.
"""

from __future__ import annotations

from collections.abc import Callable
from uuid import UUID

from pydantic import ValidationError

from healthee.core.logging import get_logger
from healthee.insights.client import LLMClient
from healthee.insights.grounded import grounded_ask
from healthee.jobs.coach_checks import provable_grade
from healthee.jobs.coach_sizing import Allowed, violation
from healthee.jobs.coach_task import CoachWeek

log = get_logger(__name__)

COACH_METRICS = [
    "recovery_score",
    "mvpa_min",
    "steps_total",
    "sleep_health_score_4dim",
    "sleep_regularity_index",
    "hrv_sleep_avg",
    "cardio_load",
]
_ATTEMPTS = 2


def _parse(data: dict | None) -> tuple[CoachWeek | None, str | None]:
    """The validated answer with its PROVED grade, or the reason it is unusable."""
    if data is None:
        return None, "no grounded answer"
    try:
        week = CoachWeek.model_validate(data)
    except ValidationError as exc:
        return None, "; ".join(e["msg"] for e in exc.errors())
    grade = provable_grade(week.evidence_grade, week.research_note_ids)
    if grade is None:
        return None, "the cited notes are below Probable"
    return week.model_copy(update={"evidence_grade": grade}), None


def _issue(week: CoachWeek, weekly: bool, allowed: Allowed | None) -> str | None:
    if not weekly:
        return None
    if week.review is None or week.pattern is None or week.job is None:
        return "a weekly answer needs review, pattern and job"
    if allowed is None:
        return None
    job = week.job
    return violation(allowed, job.metric, job.target, job.days_required)


def propose(  # noqa: PLR0913 — one call's whole context, all keyword-only past the question
    question: str,
    user_id: UUID,
    tz: str,
    *,
    weekly: bool,
    allowed: Allowed | None = None,
    extra_check: Callable[[CoachWeek], str | None] | None = None,
    client: LLMClient | None = None,
    model: str | None = None,
) -> CoachWeek | None:
    """The coach's validated answer, or ``None`` after two tries."""
    ask = question
    for attempt in range(1, _ATTEMPTS + 1):
        result = grounded_ask(
            ask,
            user_id,
            tz,
            metrics=COACH_METRICS,
            context_days=14,
            response_format="json",
            client=client,
            model=model,
        )
        if result.refused or not result.validated:
            log.info("coach[%s]: no grounded output (refused=%s)", user_id, result.refused)
            return None
        week, why = _parse(result.data)
        if week is not None:
            why = _issue(week, weekly, allowed) or (extra_check(week) if extra_check else None)
        if why is None and week is not None:
            return week
        log.warning("coach[%s] attempt %d rejected: %s", user_id, attempt, why)
        rule = allowed.statement() if allowed else ""
        ask = f"{question}\n\nYour last answer was rejected: {why}. {rule}".strip()
    return None
