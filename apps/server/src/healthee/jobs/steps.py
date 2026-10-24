"""The chain's steps — thin adapters onto the modules that do the work.

Split out of ``jobs/chain.py`` when the illness producer made it a sixth step and
pushed that file past the 400-line gate. The seam is a real one rather than a size
dodge: this module answers *what each step is and what it costs*, ``chain`` answers
*supervision, order and idempotence*. A seventh step lands here and only its name and
entitlement class touch ``chain``.

Every adapter takes the same ``(day, user_id, tz, *, client)`` shape so ``chain`` can
supervise them uniformly, and each names ``_day``/``client`` with a leading underscore
or an ``ARG001`` waiver where it genuinely does not use one — an unused parameter that
is deliberate must look deliberate.

``chain`` imports these by name into its own namespace, so a test that stubs
``chain.step_coach_today`` still stubs what the chain calls.
"""

from __future__ import annotations

from datetime import date
from uuid import UUID

from healthee.challenges import ladder, lifecycle
from healthee.core.db import tenant_transaction
from healthee.derive.illness import derive_illness_flag
from healthee.insights import coaching as coaching_mod
from healthee.insights.client import LLMClient
from healthee.jobs import briefing as briefing_mod
from healthee.jobs import coach_today as coach_today_mod
from healthee.jobs import coach_weekly as coach_weekly_mod
from healthee.jobs import correlate as correlate_mod


def step_illness(
    day: date,
    user_id: UUID,
    tz: str,
    *,
    client: LLMClient | None = None,  # noqa: ARG001
) -> dict:
    """Compute one owner's illness early-warning flag for their local day (no LLM).

    Deterministic and ungated — it is the safety signal, and ``PRICING.md`` §1a never
    paywalls safety. It runs before ``challenges`` because the adapter and the outcome
    ledger both read the row it writes (``chain``'s module docstring argues the order).
    """
    with tenant_transaction(user_id) as cur:
        return derive_illness_flag(cur, user_id, tz, day)


def step_challenges(
    day: date,
    user_id: UUID,
    tz: str,
    *,
    client: LLMClient | None = None,  # noqa: ARG001
) -> dict:
    """Close out one owner's challenges that have ended, then move their ladder on (no LLM).

    This is where auto-completion lives, rather than inside the challenges list read
    the way legacy did it (``challenges/lifecycle.py`` argues the choice). It depends on
    nothing the chain computes: closing a finished commitment is not downstream of
    correlate, and an owner whose chain failed on findings should still get an honest
    outcome for the challenge that ended last night.

    Advancement (WP-C4) is the same step and the same transaction, deliberately. A
    program rung IS one of the challenges ``finalize_due`` just closed, so its terminal
    status and whatever the ladder does about it — promote, deload, hold, stop — are one
    fact about one night. Splitting them would let a rung be recorded ``expired`` while
    the ladder's answer to that failure rolled back, which is the half-state the freeze
    is written in-transaction to avoid.

    The ORDER here is the useful one, not a required one: ``advance_due`` reads the
    rungs' stored statuses rather than re-scoring them, so running it before the close
    would simply find an active rung and do nothing (``challenges/ladder.py``).
    """
    with tenant_transaction(user_id) as cur:
        closed = lifecycle.finalize_due(cur, user_id, tz, day)
        advanced = ladder.advance_due(cur, user_id, tz, day)
    return {"closed": closed, "advanced": advanced}


def step_correlate(
    _day: date,
    user_id: UUID,
    tz: str,
    *,
    client: LLMClient | None = None,  # noqa: ARG001
) -> dict:
    """Recompute one owner's personal findings (no LLM — ``client`` is unused here)."""
    return correlate_mod.run_correlate(user_id, tz)


def step_coach_weekly(
    day: date, user_id: UUID, tz: str, *, client: LLMClient | None = None
) -> dict:
    """Write the owner's weekly review and set next week's job (once per ISO week)."""
    review, cached = coach_weekly_mod.generate_week(user_id, tz, day, client=client)
    return {"written": review is not None, "cached": cached}


def step_coach_today(day: date, user_id: UUID, tz: str, *, client: LLMClient | None = None) -> dict:
    """Write the owner's daily check-in on this week's job."""
    return coach_today_mod.generate_today(user_id, tz, day, client=client)


def step_warm(
    _day: date,
    user_id: UUID,
    tz: str,
    *,
    client: LLMClient | None = None,
) -> dict:
    """Warm one owner's generated lines for their local day (off the read path).

    Since #95 that includes the BRIEFING body: one merged call produces it and the daily
    action together, so the ``briefing`` step below usually sends warmed text instead of
    generating. Which lines exist is ``insights.coaching``'s business, not this module's —
    this adapter did not change when a third one appeared.

    ``_day`` is unused deliberately: a coaching line is advice for the owner's day as
    it is NOW, and its cache freshness is stamped from ``tz`` (``cache.today_iso``).
    So a chain re-run for an explicit past ``day`` still warms today's lines rather
    than caching yesterday's advice under today's key.
    """
    return coaching_mod.warm_lines(user_id, tz, client=client)


def step_briefing(day: date, user_id: UUID, tz: str, *, client: LLMClient | None = None) -> dict:
    """Send one owner's morning Telegram briefing (usually warmed by ``step_warm``, #95).

    ``day`` is used here, unlike in ``step_warm``: it date-stamps the message that goes
    out, and a briefing presented undated is the staleness failure the honesty contract
    names by name.
    """
    return briefing_mod.send_briefing(user_id, tz, day, client=client)
