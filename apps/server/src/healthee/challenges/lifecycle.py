"""The challenge state machine: ``suggested → active → completed | expired | abandoned``.

WP-C2 (CHALLENGES.md §4). WP-C1 made a challenge *scoreable*; this makes it a thing
an owner can take on, be measured against, and have honestly closed out.

## Four decisions worth reading before changing anything here

**0. Two rules bound what may be adopted, and they are different rules.** The cap
(:data:`MAX_ACTIVE`) is about how many commitments one owner can hold; the duplicate
check (#72, ``challenges.commitment``) is about whether the thing being adopted is a
*separate* commitment at all. They refuse under different reasons because a surface has
to be able to tell an owner "you are full" from "you are already doing that".

**1. The cap is per OWNER.** Legacy's `_MAX_ACTIVE = 3` was global because legacy
had one user; here it counts the caller's own active rows and nobody else's
(MULTI_USER.md §2). A cap that leaked across tenants would let one owner's
enthusiasm lock every other owner out of adopting anything.

**2. A challenge ends early only on an IRREVOCABLE outcome; otherwise it ends when
its window does.** A `>=` total, once reached, cannot be un-reached, so it closes
the moment it is met. A cap, once blown, cannot be un-blown, so it closes then too.
But a cap that is merely *un-blown so far* proves nothing until the period is over
— the owner still has the rest of the day — so it waits for the window. This is the
one place that distinction matters: ``evaluate``'s ``complete`` answers "is the rule
satisfied right now", which is the right thing for a progress card and the wrong
thing to freeze a ledger on.

**3. A window that ran out UNMET is `expired`, never `completed`.** Legacy marked a
timed-out program rung "completed" (CHALLENGES.md §2.3). A system that records
failures as successes cannot learn from either.

## Auto-completion runs on WRITE paths, never on a read — deliberately

Legacy auto-completed lazily inside its list read (`challenges.py:635`). That works,
and it is the reason we do not do it:

* a GET that writes is not idempotent and not cacheable, it takes the read path's
  budget (standards: p95 < 100 ms) into an UPDATE, and two concurrent list requests
  race to close the same challenge;
* a challenge only closes if somebody *looks*. The owner who stops opening the app —
  precisely the one whose challenge is quietly expiring — never gets an outcome,
  so the ledger silently under-records exactly the cases it most needs.

So finalization runs in two places, both of which are already writes:

* :func:`finalize_due` as a step in the nightly chain (``jobs/chain.py``), once per
  owner per THEIR local day, so it happens whether or not anyone looked; and
* at the start of :func:`adopt`, because the ``MAX_ACTIVE`` cap is computed from the
  active count — a challenge that finished but has not been closed yet would block
  the owner from starting a new one, with no way for them to fix it.

Reads (:func:`list_challenges`) stay pure.
"""

from __future__ import annotations

from datetime import UTC, date, datetime, time, timedelta
from typing import Any
from uuid import UUID
from zoneinfo import ZoneInfo

from healthee.challenges import commitment, ledger, store
from healthee.challenges.adapt import suggest_adaptation
from healthee.challenges.evaluate import evaluate_challenge, start_date
from healthee.challenges.metrics import allows_cadence
from healthee.challenges.series import recent_value
from healthee.core.logging import get_logger
from healthee.core.tenancy import user_today
from healthee.derive._common import Cur

log = get_logger(__name__)

# How many challenges one OWNER may have running at once. Verbatim from legacy
# (`_MAX_ACTIVE`), per-owner rather than global (see the module docstring). Three is
# the number legacy chose to stop the feed becoming a to-do list nobody can hold.
MAX_ACTIVE = 3

# How many finished challenges a list read carries back. Every list is windowed
# (standards §Performance); the ledger endpoint is where history is paged.
_RECENT_FINISHED = 10

_FINISHED = ("completed", "expired", "abandoned")


def adopt(cur: Cur, user_id: UUID, tz: str, challenge_id: int, today: date | None = None) -> dict:
    """Take on a suggested challenge: freeze its baseline and start its window.

    The baseline is captured HERE, from the owner's own trailing data strictly
    before today (``recent_value``), and never again. It is the anchor the entire
    before/after rests on, so a re-adopt or a concurrent request must not be able
    to move it — :func:`store.mark_adopted` makes that structural. The challenge's
    ``window_days`` goes into that read because a ``total`` baseline spans the whole
    window (``series.baseline_span``, #65): the frozen number has to be in the same
    unit as the target it will be judged against.

    Returns ``{"ok": True, "challenge": …}``, or ``{"ok": False, "error": …,
    "reason": …}`` for a rule outcome. A rule outcome is a legitimate answer and
    says which rule; a genuine failure propagates (standards §Errors).
    """
    today = today or user_today(tz)
    finalize_due(cur, user_id, tz, today)  # so a stale active row cannot block the cap
    challenge = store.fetch(cur, user_id, challenge_id)
    if challenge is None:
        return _refused("not_found", "no such challenge")
    if challenge["status"] != "suggested":
        return _refused("not_suggested", f"challenge is {challenge['status']}, not suggested")
    if not allows_cadence(challenge["metric"], challenge["cadence"]):
        # #67 — the door this reaches through. A stored row is not proof the pair is
        # expressible, so it is refused as a rule outcome here rather than left to
        # raise out of `evaluate` on the next feed read.
        return _refused(
            "not_expressible",
            f"{challenge['metric']} cannot be a {challenge['cadence']} challenge",
        )
    # #72 — the check generation always had and adopt never did. Reported BEFORE the cap
    # because it is the more specific and more fundamental refusal: the cap says the
    # owner has no room for another commitment, this says THIS one is not another
    # commitment at all (``challenges.commitment`` argues the rule and its width).
    duplicate = commitment.clashing(challenge["metric"], store.active_metrics(cur, user_id))
    if duplicate is not None:
        return _refused(
            "duplicate_commitment",
            f"already running a challenge on {duplicate} — the same behaviour scored "
            "twice would put two before/afters in the ledger over one change",
        )
    active = store.count_active(cur, user_id)
    if active >= MAX_ACTIVE:
        return _refused("too_many_active", f"already running {active} of {MAX_ACTIVE} challenges")
    adopted_at = datetime.now(tz=UTC)
    window_days = int(challenge["window_days"])
    baseline = recent_value(
        cur, user_id, tz, challenge["metric"], challenge["cadence"], today, window_days
    )
    start = start_date(adopted_at, tz, today)
    ends_at = window_end(start, tz, window_days)
    if not store.mark_adopted(cur, user_id, challenge_id, adopted_at, ends_at, baseline):
        return _refused("not_suggested", "challenge was adopted by another request")
    log.info("challenge %s adopted by %s (baseline=%s)", challenge_id, user_id, baseline)
    return {"ok": True, "challenge": store.fetch(cur, user_id, challenge_id)}


def abandon(cur: Cur, user_id: UUID, tz: str, challenge_id: int, today: date | None = None) -> dict:
    """Stop an active challenge at the owner's request. Its outcome is still frozen.

    Giving up is a result, not an absence of one — an abandoned challenge is exactly
    the kind of thing WP-C3 must learn to route around, and it can only do that if
    the ledger records it (``status: 'abandoned'``, honestly, with however far the
    owner got).
    """
    today = today or user_today(tz)
    challenge = store.fetch(cur, user_id, challenge_id)
    if challenge is None:
        return _refused("not_found", "no such challenge")
    if not store.mark_abandoned(cur, user_id, challenge_id, datetime.now(tz=UTC)):
        return _refused("not_active", f"challenge is {challenge['status']}, not active")
    _freeze(cur, user_id, tz, challenge, "abandoned", today)
    log.info("challenge %s abandoned by %s", challenge_id, user_id)
    return {"ok": True, "challenge": store.fetch(cur, user_id, challenge_id)}


def set_slot(cur: Cur, user_id: UUID, challenge_id: int, slot: str) -> dict:
    """Change the owner's own words for WHEN they will do a challenge. Nothing else moves.

    Allowed on a suggested or an active challenge; a finished one is a record. No
    evaluation runs and no outcome is touched: the slot is a label, not a rule.
    """
    challenge = store.fetch(cur, user_id, challenge_id)
    if challenge is None:
        return _refused("not_found", "no such challenge")
    if not store.set_slot_text(cur, user_id, challenge_id, slot):
        return _refused(
            "not_active", f"challenge is {challenge['status']}, not suggested or active"
        )
    return {"ok": True, "challenge": store.fetch(cur, user_id, challenge_id)}


def apply_adaptation(
    cur: Cur, user_id: UUID, tz: str, challenge_id: int, today: date | None = None
) -> dict:
    """Recompute the recalibration SERVER-SIDE and apply it. Takes no target from anyone.

    §5.2's second property, made structural: there is no parameter here through which
    a new target could arrive. The client's whole role is to say "yes, adapt it"; the
    number is recomputed from the owner's own rows at the moment of the request, so a
    stale or tampered figure from a client cannot become their commitment.

    A refusal when nothing is due is a real answer, not a failure — the honest state
    most of the time is that the target should be left alone.

    Two of those refusals are different states and are named differently. "Nothing is
    due" is the ordinary one. ``adaptation_withheld`` is the recovery guard: the
    owner's performance DID earn a raise and their recovery data refuses it
    (``adapt``'s module docstring), so the endpoint carries that reason out rather
    than reporting the same shrug it gives a challenge running normally.
    """
    today = today or user_today(tz)
    challenge = store.fetch(cur, user_id, challenge_id)
    if challenge is None:
        return _refused("not_found", "no such challenge")
    if challenge["status"] != "active":
        return _refused("not_active", f"challenge is {challenge['status']}, not active")
    progress = evaluate_challenge(cur, user_id, tz, challenge, today=today)
    adaptation = suggest_adaptation(cur, user_id, tz, challenge, progress, today=today)
    if adaptation is None:
        return _refused("no_adaptation", "performance is inside the productive band")
    if adaptation["suggested"] is None:
        return _refused("adaptation_withheld", adaptation["reason"])
    if not store.set_target(cur, user_id, challenge_id, float(adaptation["suggested"])):
        return _refused("not_active", "challenge stopped being active")
    log.info(
        "challenge %s target %s -> %s for %s",
        challenge_id,
        adaptation["current"],
        adaptation["suggested"],
        user_id,
    )
    adapted = store.fetch(cur, user_id, challenge_id)
    return {"ok": True, "adaptation": adaptation, "challenge": adapted}


def finalize_due(cur: Cur, user_id: UUID, tz: str, today: date | None = None) -> list[dict]:
    """Close every one of ``user_id``'s active challenges that has ended.

    Returns one ``{"challenge_id", "status"}`` per challenge closed (empty is the
    normal answer). Bounded work by construction: at most :data:`MAX_ACTIVE` rows,
    each costing the same reads a progress card already does.
    """
    today = today or user_today(tz)
    closed: list[dict] = []
    at = datetime.now(tz=UTC)
    for challenge in store.list_by_status(cur, user_id, ("active",), limit=MAX_ACTIVE):
        progress = evaluate_challenge(cur, user_id, tz, challenge, today=today)
        status = terminal_status(challenge, progress)
        if status is None:
            continue
        if store.mark_finished(cur, user_id, int(challenge["id"]), status, at):
            _freeze(cur, user_id, tz, challenge, status, today, progress)
            closed.append({"challenge_id": int(challenge["id"]), "status": status})
            log.info("challenge %s closed as %s for %s", challenge["id"], status, user_id)
    return closed


def _freeze(
    cur: Cur,
    user_id: UUID,
    tz: str,
    challenge: dict,
    status: str,
    today: date,
    progress: dict | None = None,
) -> None:
    """Write the challenge's outcome, in the SAME transaction that closed it.

    Not a separate step and not best-effort: a challenge closed without an outcome is
    a week of someone's life that the ledger — and therefore every later suggestion —
    has no record of. If the freeze fails, the close rolls back with it and the next
    run tries again, which is the only honest failure mode available.
    """
    progress = progress or evaluate_challenge(cur, user_id, tz, challenge, today=today)
    start = start_date(challenge.get("adopted_at"), tz, today)
    ledger.freeze(cur, user_id, tz, challenge, progress, status, start, today)


def terminal_status(challenge: dict[str, Any], progress: dict) -> str | None:
    """``completed`` / ``expired`` / ``None`` (still running) for a live challenge.

    ``None`` is the answer whenever the rule could still go either way. Freezing a
    ledger entry on a verdict that today could still overturn is how a system
    starts recording things that did not happen.
    """
    if progress["elapsed"] > int(challenge["window_days"]):
        return "completed" if progress["complete"] else "expired"
    # Still inside the window: only an outcome that cannot be reversed ends it now.
    if challenge["comparator"] == ">=" and progress["complete"]:
        return "completed"  # a total, once reached, cannot be un-reached
    if progress.get("breached"):
        return "expired"  # a cap, once blown, cannot be un-blown
    return None


def window_end(start: date, tz: str, window_days: int) -> datetime:
    """The instant a challenge's window closes — the END of its last local day.

    Derived from the same two inputs ``evaluate`` counts from (the start day in the
    OWNER's zone, via ``start_date``, and ``window_days``), so the stored timestamp
    and the ``elapsed > window`` rule can never disagree about when it is over. ONE
    definition (CLAUDE.md), expressed twice for two audiences — a timestamp for the
    client, day arithmetic for the engine.

    Midnight OPENING the day after the last one, in the owner's zone: a window of 7
    days adopted on the 1st runs through the end of the 7th, so it closes at 00:00
    on the 8th, local. Building it from a UTC instant instead would end an owner's
    window in the middle of their afternoon.
    """
    day_after_last = start + timedelta(days=max(1, window_days))
    return datetime.combine(day_after_last, time.min, tzinfo=ZoneInfo(tz))


def list_challenges(cur: Cur, user_id: UUID, tz: str, today: date | None = None) -> dict:
    """The owner's feed: suggestions, live progress, and what recently ended.

    A PURE READ — it never closes a challenge (module docstring). A challenge whose
    window has run out therefore still appears as active here until the nightly step
    or the next adopt closes it, carrying ``days_left: 0``; that is a true statement
    about a row that has not been frozen yet, whereas writing from a GET is not.
    """
    today = today or user_today(tz)
    active = [
        challenge | {"progress": progress_of(cur, user_id, tz, challenge, today)}
        for challenge in store.list_by_status(cur, user_id, ("active",), limit=MAX_ACTIVE)
    ]
    return {
        "active": active,
        "suggested": store.list_by_status(cur, user_id, ("suggested",)),
        "recent": store.list_by_status(cur, user_id, _FINISHED, limit=_RECENT_FINISHED),
        "max_active": MAX_ACTIVE,
    }


def progress_of(cur: Cur, user_id: UUID, tz: str, challenge: dict, today: date) -> dict:
    """Live progress plus any pending recalibration, for one active challenge.

    The adaptation is SUGGESTED, never applied: §5.2 keeps a raise behind the
    owner's one tap, because a commitment they agreed to should not move under them.

    Public because WP-C4's program read shows the same thing for a live RUNG, and a
    rung is an ordinary active challenge. Rendering it from a second function would be
    two surfaces free to disagree about what an owner's commitment is doing — the fork
    this track keeps having to un-write.
    """
    progress = evaluate_challenge(cur, user_id, tz, challenge, today=today)
    adaptation = suggest_adaptation(cur, user_id, tz, challenge, progress, today=today)
    return progress | {"adaptation": adaptation}


def _refused(reason: str, message: str) -> dict:
    """A rule outcome — explicit and named, never an empty success (standards §Errors)."""
    return {"ok": False, "reason": reason, "error": message}
