"""The supervised event chain — replaces the legacy shell ``Popen``.

Legacy triggered ``subprocess.Popen("healthee correlate && healthee recs && "
"healthee daily-insight", shell=True)`` from two sites (api/app.py:933,
v2/api.py:74). A failure in any step vanished into the shell — the classic
swallowed-error class the rebuild exists to kill.

The steps themselves live in ``jobs/steps.py`` (this file owns order, supervision and
idempotence; that one owns what each step is). Here they run IN ORDER as in-process
function calls, each wrapped by
``_run_supervised``: a failure is CAUGHT, logged with context through
``core.logging``, and reported to Telegram via ``core.notify`` — never silently
passed (standards §1: "Background/silent contexts … must report failures to their
health surface"). The chain then applies dependency logic:

  * ``illness`` runs FIRST, because it is the only step anything below it READS.
    ``challenges`` consults the flag twice in the very next step — ``advance_due`` via
    ``challenges/recovery_guard.py`` ([[recovery_readiness]] D7: may an adopted target
    be RAISED?) and ``finalize_due`` via ``challenges/confounds.py`` (was the owner ill
    inside this outcome's window?). Written after them, today's flag misses both: the
    adapter ratchets a training target on the morning the owner got sick, and the
    ledger records that day's outcome as unconfounded;
  * ``challenges`` depends on nothing computed here — closing out a commitment that
    ended last night, and moving a program ladder on from it, is not downstream of
    any computation, and an owner whose findings failed still deserves an honest
    outcome for it (WP-C2/WP-C4; the choice to finalize here rather than inside a
    list read is argued in ``challenges/lifecycle.py``);
  * a ``correlate`` failure ABORTS the coach steps AND ``warm`` (both read the findings
    correlate writes, via the choke point's context) — they are marked skipped, not
    run on stale inputs;
  * a ``briefing`` failure does NOT undo the coach lines already stored;
  * a ``warm`` failure costs only the coaching lines — the chain continues.

Non-fatal means "does not abort the run"; it does not mean "counts as done". Any
failed step leaves the day unmarked so the next tick retries it (:func:`_nothing_failed`).

## Which steps a free owner gets (Phase 6.6a, MULTI_USER.md §12.3)

Three of the six steps call a model, and generating output nobody is entitled to see
is the cost hole 6.6a exists to close (``PRICING.md`` §6.1: at 5 % conversion each
premium user carries ~19 free ones, so free-tier cost control is existential). So
the coach steps, ``warm`` and ``briefing`` are SKIPPED for a non-premium owner — named as
``skipped``, never silently absent, because a step that did not run and a step that
ran and produced nothing are different facts (standards §Errors).

The other three run for everyone, and the line between them is *what the step costs and
who the output belongs to*, not "is it in the AI half of the product":

* ``illness`` is the deterministic early-warning flag, and the one step that could never
  be gated on any grounds. ``PRICING.md`` §1a is explicit — "never paywall data or
  safety" — and this is the safety half of that sentence: an unentitled owner still gets
  the pill saying their overnight vitals moved, and their live challenges are still held
  back while it is up. It also spends no tokens.
* ``correlate`` is the **deterministic** FDR correlation + cutoff engine. It spends no
  tokens, and its findings are a FREE-tier feature (``PRICING.md`` §1a: "personal
  findings … ✓ shown as plain stats"). Skipping it would take a free feature away in
  the name of saving money it does not cost.
* ``challenges`` closes out commitments that ended last night and moves a ladder on —
  also deterministic, also free to run. The challenges *system* is premium, but an
  owner whose subscription lapsed with a live commitment still deserves an honest
  outcome for it rather than a challenge frozen mid-window forever. Bookkeeping that
  already-generated content is entitled to is not the same as generating more.

The check is one lookup per owner per chain, from ``core.entitlement`` — the same
function the HTTP gate uses, so the endpoint and the job can never disagree about who
is premium (§12.7's invariant is enforced at both, from one source of truth).

``warm`` is the step that makes the read surfaces' LLM lines exist at all: the
``/api/today`` action and the sleep-tonight line are cache-only on the read path
(``coaching.cached_line`` never generates, standards §Performance), so without an
off-read-path warmer they are null forever. It runs here, once per owner per THEIR
local day, because that is the one place that already knows both.

Since #95 ``warm`` also generates the **briefing body** — one call produces it and the
daily action together (``insights.morning``), so ``briefing`` below usually sends warmed
text and spends nothing. That does NOT make ``briefing`` depend on ``warm``: when ``warm``
was skipped (a ``correlate`` failure) or its merged call could not ship, ``briefing``
generates for itself exactly as it did before. The order of the two steps is unchanged and
still only ``warm`` → ``briefing``, which is the order that lets the second read what the
first wrote.

The chain is deduped per day via the ``kv`` table: once a day's chain has run every
step CLEANLY, a second ``run_chain`` for that day is a no-op (legacy deduped
on last-night's sleep landing). The mark is written after the last step and only when
nothing failed — :func:`_nothing_failed` argues why a partial chain marks not at all.
That marker is what lets the scheduler tick
repeatedly and still run each owner's chain exactly once per their local day
(6.4c) — it is the whole idempotence story, so the scheduler owns no dedup of its
own.

## The marker is a HIGH-WATER MARK — one row per owner, not one per owner per day

It stores the LATEST local day this owner's chain has run for, in the kv **value**;
the key is a constant. It used to put the day in the key (``job:chain_done:<day>``),
which left one row per owner per day in ``kv`` forever with nothing to sweep it —
365 rows/owner/year of pure bookkeeping on a table read on every tick. `0012` folded
the accumulated rows into one per owner and this module stopped making more, the way
``core.rate_limit`` (which documented the divergence rather than copying it) already
does. Standards §Performance: unbounded data is windowed.

The shape carries a semantic, not just a smaller row count. "Has the chain run for
day D" is answered as ``stored >= D`` — *the chain has run THROUGH D* — and the write
is a ``greatest()``, so the mark can never move backwards. Three consequences, all
deliberate:

  * a later day is un-marked and fires; the same day twice is a no-op (idempotence,
    unchanged);
  * a run for an EARLIER day is deduped away rather than re-generating and re-sending
    a briefing for a day already past. ``force=True`` is the escape hatch, and it is
    the only caller that ever wanted one;
  * a forced back-fill cannot regress the mark and so cannot un-dedup today — with a
    plain overwrite it would, and today's chain would run (and spend) twice.

ISO-8601 dates are fixed-width and zero-padded, so lexical order **is** chronological
order — the property that lets both comparisons happen in SQL on a TEXT column.
"""

from __future__ import annotations

from collections.abc import Callable, Sequence
from dataclasses import dataclass, field
from datetime import date
from uuid import UUID

from healthee.core.db import tenant_transaction
from healthee.core.entitlement import is_premium
from healthee.core.logging import get_logger
from healthee.core.notify import send_telegram
from healthee.core.tenancy import user_today
from healthee.insights.client import LLMClient
from healthee.jobs.steps import (
    step_briefing,
    step_challenges,
    step_coach_today,
    step_coach_weekly,
    step_correlate,
    step_illness,
    step_warm,
)

log = get_logger(__name__)

# The kv key of the dedup marker — a CONSTANT: the day lives in the value (see the
# module docstring). The OWNER is deliberately not in it either: 0004 folded user_id
# into the kv PRIMARY KEY and every read of it filters by owner, so two users' markers
# are already distinct rows. Prefixing would state the tenant twice — once in the key
# column, once in the string.
_DONE_KEY = "job:chain_done"

# The steps that call a model, in the order the chain runs them. Named once so the
# skip and the reason can never drift from what is actually gated — and so a sixth
# step added later has to make a deliberate choice about which list it joins.
LLM_STEPS: tuple[str, ...] = ("coach_weekly", "coach_today", "warm", "briefing")

# The weekly review runs on the owner's local Sunday; the daily check-in every day.
_SUNDAY = 6

# What a skipped step says. It is the owner's entitlement, not a failure, and the
# distinction matters on the job health surface: "skipped — not premium" must never
# read like "the coach broke again".
_NOT_PREMIUM = "owner is not premium — the AI steps are skipped (MULTI_USER.md §12.3)"


@dataclass
class StepOutcome:
    """Result of one supervised step: ok / failed / skipped, plus its detail/error."""

    name: str
    status: str  # "ok" | "failed" | "skipped"
    detail: dict | None = None
    error: str | None = None


@dataclass
class ChainResult:
    """Outcome of a whole ``run_chain`` invocation."""

    day: date
    deduped: bool
    steps: list[StepOutcome] = field(default_factory=list)


# ── supervision ────────────────────────────────────────────────────────────────


def _run_supervised(name: str, run: Callable[[], dict]) -> StepOutcome:
    """Run one step; on ANY exception log with context + Telegram-notify, never pass.

    This is the fix for the legacy swallow: the failure is surfaced on the job
    health surface (logs + Telegram) and returned as a ``failed`` outcome — the
    process is not crashed and the error is not hidden (standards §1).
    """
    log.info("chain step '%s' starting", name)
    try:
        detail = run()
    except Exception as exc:  # supervised boundary: report to the health surface, don't swallow
        log.exception("chain step '%s' failed", name)
        send_telegram(f"chain step '{name}' failed: {exc}")
        return StepOutcome(name=name, status="failed", error=str(exc))
    log.info("chain step '%s' ok: %s", name, detail)
    return StepOutcome(name=name, status="ok", detail=detail)


# ── the chain ──────────────────────────────────────────────────────────────────


def run_chain(
    user_id: UUID,
    tz: str,
    day: date | None = None,
    *,
    client: LLMClient | None = None,
    force: bool = False,
) -> ChainResult:
    """Run ONE owner's illness → challenges → correlate → coach → warm → briefing, deduped.

    Dependency: a ``correlate`` failure skips the coach steps and ``warm`` (both consume the
    findings it writes). A ``briefing`` failure never undoes stored coach lines, and a
    ``warm`` failure costs only the coaching lines. A second call for a day this owner's
    chain completed CLEANLY — or for any day at or before it — is a no-op unless
    ``force``; a day on which any step failed stays unmarked and is retried
    (:func:`_nothing_failed`). The dedup marker is per-owner (the folded ``kv`` PK), so
    one owner's chain can never dedup another's. ``day`` defaults to the owner's own
    local today.

    Entitlement (§12.3): a non-premium owner gets the three DETERMINISTIC steps and none
    of the three that call a model. The lookup happens once, before any step, so a free
    owner's chain spends ZERO LLM calls rather than generating and discarding. ``illness``
    is inside that free set by policy, not by accident (``PRICING.md`` §1a: never paywall
    safety) — the flag holds a free owner's training levers back exactly as it does a
    paying one's.
    """
    day = day or user_today(tz)
    if not force and _chain_done(user_id, day):
        log.info("chain[%s] for %s already ran — dedup no-op", user_id, day)
        return ChainResult(day=day, deduped=True)

    premium = is_premium(user_id)
    if not premium:
        log.info("chain[%s] for %s: not premium — skipping %s", user_id, day, ", ".join(LLM_STEPS))

    steps: list[StepOutcome] = []
    # First, because `challenges` reads what it writes: the illness flag is the hard
    # override the adapter and the outcome ledger both consult on the very next line.
    steps.append(_run_supervised("illness", lambda: step_illness(day, user_id, tz, client=client)))
    # Then close out what has already ended. Nothing below depends on it, and it must
    # not be skipped when something below fails.
    steps.append(
        _run_supervised("challenges", lambda: step_challenges(day, user_id, tz, client=client))
    )
    correlate = _run_supervised(
        "correlate", lambda: step_correlate(day, user_id, tz, client=client)
    )
    steps.append(correlate)

    if correlate.status == "ok":
        steps.extend(_after_correlate(day, user_id, tz, client=client, premium=premium))
    else:
        steps.extend(_skipped_after_correlate(day))

    steps.append(_briefing_step(day, user_id, tz, client=client, premium=premium))
    # LAST, and only on a clean run. See `_nothing_failed`: the marker is written after
    # every step so no step can sit outside the rule it encodes.
    if _nothing_failed(steps):
        _mark_chain_done(user_id, day)
    return ChainResult(day=day, deduped=False, steps=steps)


def _nothing_failed(steps: Sequence[StepOutcome]) -> bool:
    """Whether this run may advance the dedup marker: **no step failed**.

    ## A partial chain marks NOT AT ALL, and the shape is why

    The marker is ONE high-water day per owner and `_chain_done` reads it as
    ``value >= day`` — "the chain has run through D". That shape cannot say "steps 1
    and 3 ran and step 2 did not", so there is no partial spelling available; inventing
    one would mean a second definition of "done" that the read cannot see (CLAUDE.md:
    one canonical definition). All or nothing is not the conservative choice here, it is
    the only expressible one.

    It used to advance on ``correlate`` alone, with a comment describing "the generating
    steps" that silently annexed the two steps above it and the one below. So a failed
    ``illness`` was recorded as done and never retried — and that is the failure worth
    naming, because it is the one the ordinary tools cannot undo:
    ``derive_illness_flag`` has a single production call site (``jobs/steps.py``) and is
    NOT part of ``derive_batch``, so ``db/rederive.py`` cannot rebuild it. A transient DB
    blip on step 1 with step 3 green cost that day its flag permanently.

    A ``skipped`` step is deliberately NOT a failure. There are exactly two skips: the
    free owner's three LLM steps, which are their entitlement and not a fault
    (``test_a_free_owners_day_is_still_marked_done`` pins that); and the coach steps/``warm``
    after a ``correlate`` failure, which can only happen when ``correlate`` itself
    failed and therefore already blocks the mark.

    **What this costs, stated rather than discovered.** A ``warm`` or ``briefing``
    failure now leaves the day unmarked, so the next tick re-runs the whole chain —
    re-spending the coach steps and re-sending the briefing. That is not a new behaviour: a
    ``correlate`` failure has always left the day unmarked and done exactly this, and
    ``scheduler._ATTEMPT_BUDGET`` exists to bound it to three attempts per owner per
    day. Every step in the chain is idempotent under a re-run (``illness`` upserts,
    ``challenges`` reads stored statuses, ``correlate`` upserts on its key, the coach steps
    are write-once per week / overwrite per day, ``warm`` rewrites a cache row); only the
    briefing's Telegram message is repeated, and the budget is what caps it. Paying
    three attempts for a day is the price of not silently dropping one.
    """
    return all(step.status != "failed" for step in steps)


def _coach_names(day: date) -> tuple[str, ...]:
    """The coach steps due on ``day``: the weekly review on Sunday, the check-in always."""
    return ("coach_weekly", "coach_today") if day.weekday() == _SUNDAY else ("coach_today",)


def _after_correlate(
    day: date, user_id: UUID, tz: str, *, client: LLMClient | None, premium: bool
) -> list[StepOutcome]:
    """The coach steps + ``warm``, or all skipped when the owner is not entitled to them.

    Warming is NON-FATAL by construction (``_run_supervised`` returns, never raises): a
    missing coaching line is a degraded card, whereas aborting here would cost the owner
    their briefing over a one-liner. The failure is still reported.
    """
    names = (*_coach_names(day), "warm")
    if not premium:
        return [_not_premium(name) for name in names]
    runners = {
        "coach_weekly": lambda: step_coach_weekly(day, user_id, tz, client=client),
        "coach_today": lambda: step_coach_today(day, user_id, tz, client=client),
        "warm": lambda: step_warm(day, user_id, tz, client=client),
    }
    return [_run_supervised(name, runners[name]) for name in names]


def _briefing_step(
    day: date, user_id: UUID, tz: str, *, client: LLMClient | None, premium: bool
) -> StepOutcome:
    """The morning Telegram briefing — a grounded generation, so premium-only."""
    if not premium:
        return _not_premium("briefing")
    return _run_supervised("briefing", lambda: step_briefing(day, user_id, tz, client=client))


def _not_premium(name: str) -> StepOutcome:
    """A step that did not run because the owner is not entitled to its output."""
    return StepOutcome(name=name, status="skipped", error=_NOT_PREMIUM)


def _skipped_after_correlate(day: date) -> list[StepOutcome]:
    """The steps that must NOT run once ``correlate`` failed — both read its findings.

    the coach reads them via ``recs_context``; ``warm`` reads them via the choke point's
    ``findings_section``. Running either on stale findings would ship yesterday's
    correlations as today's advice, which is the honesty contract's exact failure mode.
    """
    return [
        StepOutcome(
            name=name,
            status="skipped",
            error="correlate failed — this step depends on its findings",
        )
        for name in (*_coach_names(day), "warm")
    ]


def _chain_done(user_id: UUID, day: date) -> bool:
    """True if this user's chain has already run its generating steps through ``day``.

    ``>=`` rather than ``=`` because the marker is a high-water mark, not a set of days
    (module docstring): the row says which local day this owner's chain last ran for, so
    an OLDER day is already covered by it. Comparing TEXT is sound here and only here —
    both sides are fixed-width zero-padded ISO-8601, where lexical order is chronological.
    """
    with tenant_transaction(user_id) as cur:
        cur.execute(
            "SELECT 1 FROM kv WHERE user_id = %s AND key = %s AND value >= %s",
            (user_id, _DONE_KEY, day.isoformat()),
        )
        return cur.fetchone() is not None


def _mark_chain_done(user_id: UUID, day: date) -> None:
    """Advance ``user_id``'s dedup marker to ``day`` — one row, upserted, never lowered.

    The marker is per-owner via the folded kv PK, so one user's chain cannot dedup
    another's — which is what makes the 6.3c per-user sweep safe to run.

    ``greatest()`` is the guard, not decoration: a deliberate ``force=True`` re-run for
    an earlier day would otherwise overwrite the mark with that older date and leave
    TODAY reading as un-run, so the next tick would re-generate and re-send a day that
    had already completed. Marking is monotone; nothing in the chain ever needs it to
    move back, and ``force`` already covers the case that wants to re-run a day.
    """
    with tenant_transaction(user_id) as cur:
        cur.execute(
            "INSERT INTO kv (user_id, key, value) VALUES (%s, %s, %s) "
            "ON CONFLICT (user_id, key) DO UPDATE SET value = greatest(kv.value, EXCLUDED.value)",
            (user_id, _DONE_KEY, day.isoformat()),
        )
