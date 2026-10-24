"""Challenges — the feed, the lifecycle writes, and the outcome ledger.

Thin (standards §2): auth dep → one domain call inside one owner-scoped transaction
→ shape the response. There is no business logic and no SQL here; every rule lives in
``healthee.challenges``.

Two things this router deliberately does NOT have:

* **A target in any request.** ``POST …/adapt`` takes no body. The recalibration is
  recomputed server-side from the owner's own rows at the moment of the request
  (CHALLENGES.md §5.2) — a client may ask for one, it can never dictate the number,
  and the way to guarantee that is to give it nowhere to put one.
* **An ungated identity.** Every handler takes ``ChallengeUser`` (``api.gate``), not
  ``CurrentUser``: the whole challenges system is premium per PRICING §1a, so a
  non-premium owner gets **402** here — including on the pure feed reads, because a
  stored challenge is AI-authored content and §12.7's "read pre-generated AI content
  from another path" loophole closes at whichever endpoint serves it. The gate is on
  the identity rather than beside it so an endpoint cannot take the owner without
  taking the gate (6.6a).

## The response models (standards §2 — small, stable payloads are typed)

These five payloads are small and stable, so they are pydantic models rather than
``dict``; the aggregate exception (``/api/today``, ``/api/sleep``) does not apply. The
models below **describe** the wire, they do not reshape it. Three rules keep that
true, and breaking any one of them moves the wire under a client already parsing it:

1. **Field order and optionality mirror the source.** :class:`Challenge` follows
   ``store.COLUMNS`` and ``db/schema.sql``'s NOT NULLs exactly; :class:`Outcome`
   follows ``ledger._READ_COLUMNS``.
2. **A nullable field is required-and-nullable, never defaulted.** ``x: T | None``
   with no ``= None``: the key must be present and its value may be null. A default
   would let a *missing* key serialise as null — and a non-optional field with a
   default (``adherence: float = 0.0``) would turn "this cadence makes no per-day
   commitment" into "they adhered 0 % of the time". This product distinguishes no
   data from zero and from not-applicable; the models have to as well.
3. **``extra="forbid"`` everywhere.** A response model silently DROPS keys it does
   not declare, so a field added to ``evaluate_challenge`` would vanish from the wire
   with nothing failing. Forbidding extras turns that into a loud error in the first
   test that runs — the trade this codebase always makes.
"""

from __future__ import annotations

from datetime import date, datetime
from typing import Annotated, Literal

from fastapi import APIRouter
from pydantic import BaseModel, ConfigDict, Field, field_validator

from healthee.api.gate import ChallengeUser
from healthee.api.validation import require_ok
from healthee.challenges import ledger, lifecycle
from healthee.core.db import tenant_transaction

router = APIRouter(tags=["challenges"])

SLOT_MAX = 80


class _Wire(BaseModel):
    """Base for every challenges response model — an unmodelled key is an error.

    See the module docstring, rule 3: the default (``extra="ignore"``) would drop a
    new domain field from the response silently, which is the one failure mode a
    response model can introduce that returning ``dict`` never could.
    """

    model_config = ConfigDict(extra="forbid")


class Challenge(_Wire):
    """One ``challenge`` row, exactly as ``challenges.store`` reads it.

    Field order is ``store.COLUMNS``; optionality is ``db/schema.sql``'s. Everything
    the schema declares NOT NULL is required here and everything it leaves nullable is
    ``| None`` — including ``research_note_ids``, a nullable ``TEXT[]`` even though
    every row this codebase writes carries one.
    """

    id: int
    created_at: datetime
    gen_date: date | None
    title: str
    why: str
    category: str
    difficulty: str
    metric: str
    comparator: str
    target_value: float
    cadence: str
    window_days: int
    expected_outcome: str | None
    how_to: str | None
    research_note_ids: list[str] | None
    status: str
    adopted_at: datetime | None
    ends_at: datetime | None
    completed_at: datetime | None
    abandoned_at: datetime | None
    baseline_value: float | None
    program_id: int | None
    rung_index: int | None
    # `0010`. `standard` on every standalone challenge and on a designed rung; `deload`
    # only on a rung the ladder inserted after one timed out unmet. On the wire because
    # a client rendering a live rung has to be able to say it is a step BACK — the copy
    # deliberately does not (``program_store.insert_rung`` authors no new prose), so
    # this field is the only thing that can. NOT NULL with a default in the schema, so
    # it is required and non-optional here.
    kind: str
    # `0023`. The weekly coach job's own words and bad-day floor. Required-and-nullable
    # (rule 2): NULL is "not authored", and a challenge from the standalone generator
    # has none of them.
    action_text: str | None
    slot_text: str | None
    floor_value: float | None
    floor_text: str | None
    counts_when: str | None
    days_required: int | None


class Adaptation(_Wire):
    """A pending recalibration (``challenges.adapt.suggest_adaptation``).

    The number never travels without its ``reason``: §5.2's rule is that a commitment
    the owner agreed to may only move for something we can state out loud.

    ``suggested`` is nullable for exactly one direction — ``withheld``, the raise the
    recovery guard refused (``challenges/adapt.py``). There is no number to apply
    then, and the whole point of the shape is that the ``reason`` still reaches the
    owner: "not raising this while your recovery is low" is a better answer than an
    absent banner. Rule 2 of the module docstring applies — required and nullable,
    never defaulted.
    """

    direction: str
    suggested: float | None
    current: float
    reason: str


class _ProgressCommon(_Wire):
    """The part of ``evaluate_challenge``'s result that every cadence carries."""

    target: float
    today_value: float | None  # null on a day with no measurement — never zero
    days_left: int
    elapsed: int
    unit: str
    label: str


class DailyProgress(_ProgressCommon):
    """``cadence='daily'`` — hit the per-day target on each of ``window`` days."""

    cadence: Literal["daily"]
    window: int
    hit_days: int
    progress: float
    complete: bool
    streak: int
    today_hit: bool
    protected_today: bool
    adaptation: Adaptation | None


class CumulativeProgress(_ProgressCommon):
    """``cadence='weekly' | 'total'`` — a running total scored against the target.

    A different shape from :class:`DailyProgress`, not a superset of it: a cumulative
    rule has no hit days and no streak, and ``breached`` (a ``<=`` cap blown
    irrecoverably, #61) exists only here. Modelling the two as one
    optional-everything object would hang six null keys on every daily progress card
    that never had them.
    """

    cadence: Literal["weekly", "total"]
    window: int
    current: float
    progress: float
    complete: bool
    breached: bool
    adaptation: Adaptation | None


# Tagged on `cadence`, which `evaluate._validated` guarantees is one of the three.
Progress = Annotated[DailyProgress | CumulativeProgress, Field(discriminator="cadence")]


class ActiveChallenge(Challenge):
    """An active challenge with live progress attached (``lifecycle._progress_of``).

    ``progress`` is on the active list ONLY. A suggestion has nothing to score yet and
    a finished one is scored in the ledger, so neither carries the key — putting it on
    those two lists as ``null`` would be inventing a field the server never computed.
    """

    progress: Progress


class ChallengeFeed(_Wire):
    """``GET /api/challenges`` — the owner's three lists plus the per-owner cap."""

    active: list[ActiveChallenge]
    suggested: list[Challenge]
    recent: list[Challenge]
    max_active: int


class ChallengeResult(_Wire):
    """``adopt`` / ``abandon`` — the STORED row, so a client renders what landed.

    ``ok`` is ``Literal[True]`` because a refusal never reaches this model:
    :func:`require_ok` has already turned it into a 4xx. A 200 from these endpoints
    means the write happened, and the type says exactly that and nothing more.
    """

    ok: Literal[True]
    challenge: Challenge


class AdaptResult(_Wire):
    """``adapt`` — the applied recalibration plus the row it was applied to.

    A ``withheld`` adaptation never reaches this model: ``lifecycle.apply_adaptation``
    turns it into a 409 with its reason, because there is no number to apply. It can
    only ever arrive on the FEED, inside ``progress.adaptation``.
    """

    ok: Literal[True]
    adaptation: Adaptation
    challenge: Challenge


class Outcome(_Wire):
    """One frozen ``challenge_outcome`` row, in ``ledger._READ_COLUMNS`` order.

    Optionality is the table's: everything but ``confounds``, ``data_confidence`` and
    ``ended_at`` is a nullable column, so it is ``| None`` here even where today's
    writer always fills it — the ledger is a historical record, and rows outlive the
    code that wrote them.

    ``adherence`` is the field this exercise is really about. It is deliberately NULL
    for ``weekly``/``total``: a cumulative rule makes no per-day commitment, so there
    is no rate of keeping it (``ledger._adherence``). Nothing here may default it.

    ``difficulty`` is a WIRE ADDITION (#62). ``ledger._compute`` wrote it on every row
    and ``_READ_COLUMNS`` selected it on none, so it was populated and unreachable. It
    is here rather than deleted because a met ``stretch`` and a met ``gentle`` are not
    the same result, and the rollup that groups outcomes by it is planned (WP-C6's
    Insights tab, which legacy shipped). Nullable because the column is — see
    ``ledger._READ_COLUMNS``.

    ``confounds`` and ``co_occurring`` stay ``dict`` — genuinely dynamic JSONB, where
    a rigid model would both add keys to the wire and reject rows that are already
    legal. ``confounds.regression_to_mean`` has four shapes (assessed, plus three
    unassessed ones carrying different reasons), ``co_occurring.metrics`` is keyed by
    whichever metrics are not this challenge's own, and `0009` both defaults
    ``confounds`` to ``{}`` and rewrites a legacy ``downstream`` string as
    ``{"legacy_note": …}``.
    """

    challenge_id: int
    metric: str | None
    category: str | None
    difficulty: str | None
    cadence: str | None
    target: float | None
    baseline: float | None
    final: float | None
    improvement_pct: float | None
    improved: bool | None
    adherence: float | None
    days_active: int | None
    status: str | None
    confounds: dict
    co_occurring: dict | None
    data_confidence: str
    ended_at: datetime


class OutcomeLedger(_Wire):
    """``GET /api/challenges/outcomes`` — the frozen ledger, newest first."""

    outcomes: list[Outcome]


@router.get("/api/challenges", response_model=ChallengeFeed)
def get_challenges(user: ChallengeUser) -> ChallengeFeed:
    """The owner's feed: suggestions, active challenges with live progress, recent ends.

    A pure read — it never closes a finished challenge (``challenges/lifecycle.py``
    argues why). One that has run out shows here with ``days_left: 0`` until a write
    path freezes it.
    """
    with tenant_transaction(user.id) as cur:
        feed = lifecycle.list_challenges(cur, user.id, user.timezone)
    return ChallengeFeed.model_validate(feed)


@router.post("/api/challenges/{challenge_id}/adopt", response_model=ChallengeResult)
def post_adopt(user: ChallengeUser, challenge_id: int) -> ChallengeResult:
    """Take on a suggested challenge, freezing its baseline at this moment."""
    # `require_ok` stays INSIDE the transaction: a refusal is an exception, and the
    # rollback it triggers is what un-does `adopt`'s `finalize_due` writes.
    with tenant_transaction(user.id) as cur:
        result = require_ok(lifecycle.adopt(cur, user.id, user.timezone, challenge_id))
    return ChallengeResult.model_validate(result)


@router.post("/api/challenges/{challenge_id}/abandon", response_model=ChallengeResult)
def post_abandon(user: ChallengeUser, challenge_id: int) -> ChallengeResult:
    """Stop an active challenge. Its outcome is still frozen — giving up is a result."""
    with tenant_transaction(user.id) as cur:
        result = require_ok(lifecycle.abandon(cur, user.id, user.timezone, challenge_id))
    return ChallengeResult.model_validate(result)


@router.post("/api/challenges/{challenge_id}/adapt", response_model=AdaptResult)
def post_adapt(user: ChallengeUser, challenge_id: int) -> AdaptResult:
    """Apply the pending recalibration — recomputed here, never taken from the client.

    409 when there is nothing to apply, which is the honest answer most of the time:
    performance inside the productive band means the target should be left alone.
    """
    with tenant_transaction(user.id) as cur:
        result = require_ok(lifecycle.apply_adaptation(cur, user.id, user.timezone, challenge_id))
    return AdaptResult.model_validate(result)


class SlotRequest(BaseModel):
    """Body of ``PATCH …/slot``: the one thing a client may say about a live challenge."""

    model_config = ConfigDict(extra="forbid")

    slot: str

    @field_validator("slot")
    @classmethod
    def _a_short_printable_label(cls, slot: str) -> str:
        slot = slot.strip()
        if not 1 <= len(slot) <= SLOT_MAX:
            raise ValueError(f"slot must be 1 to {SLOT_MAX} characters")
        if any(not ch.isprintable() for ch in slot):
            raise ValueError("slot must not contain control characters")
        return slot


@router.patch("/api/challenges/{challenge_id}/slot", response_model=ChallengeResult)
def patch_slot(user: ChallengeUser, challenge_id: int, req: SlotRequest) -> ChallengeResult:
    """Reword when the owner will do it. Touches ``slot_text`` and nothing else."""
    with tenant_transaction(user.id) as cur:
        result = require_ok(lifecycle.set_slot(cur, user.id, challenge_id, req.slot))
    return ChallengeResult.model_validate(result)


@router.get("/api/challenges/outcomes", response_model=OutcomeLedger)
def get_outcomes(user: ChallengeUser, limit: int = 20) -> OutcomeLedger:
    """The frozen ledger, newest first.

    Every row carries its own caveats — ``confounds``, ``data_confidence``, and
    ``co_occurring`` with the concurrency count inside it — so nothing downstream can
    read a delta on another metric as an effect of the challenge (§7 decision 1).
    """
    with tenant_transaction(user.id) as cur:
        outcomes = ledger.recent(cur, user.id, limit)
    return OutcomeLedger.model_validate({"outcomes": outcomes})
