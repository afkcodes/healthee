"""Row access for `challenge` — the standalone lifecycle's half of the challenge SQL.

Split from :mod:`healthee.challenges.lifecycle` so the *rules* (when may a
challenge be adopted, what ends it, what does the owner see) read as rules rather
than as SQL with rules mixed in. Everything here is owner-scoped: every statement
carries ``AND user_id = %s`` even though `0008`'s RLS would also filter it, because
the explicit predicate is the clarity and the index use, and RLS is the backstop
(ENGINEERING_STANDARDS §2; the AST guard in ``tests/db`` fails the build without it).

Nothing here decides anything. A function that answers "should this happen" belongs
in ``lifecycle``; a function that answers "what is stored" belongs here.

## The one other place challenge SQL lives, and why it is not here (WP-C4)

``program_store`` writes ``challenge`` rows too — the rungs of a ladder. That is a
deliberate exception to "one place", taken because the alternative is worse: every
ladder operation spans BOTH tables in one breath (activate a rung *and* clear the
program's hold; insert a deload *and* renumber the rungs after it), so splitting by
table would put one logical write in two modules and leave neither readable.

What must NOT be duplicated is the row SHAPE, and it is not: :data:`COLUMNS`,
:data:`SELECT` and :func:`row` are public for that module alone, so a column added by
a future migration reaches both readers or neither.
"""

from __future__ import annotations

from datetime import date, datetime
from typing import Any, LiteralString, cast
from uuid import UUID

from healthee.derive._common import Cur

# The row shape the engine and the API both work in. Named explicitly rather than
# `SELECT *` so a column added by a future migration cannot silently change the
# shape of an API response. Public because ``program_store`` reads rungs with the
# SAME shape (module docstring) — one definition, two readers.
COLUMNS = (
    "id",
    "created_at",
    "gen_date",
    "title",
    "why",
    "category",
    "difficulty",
    "metric",
    "comparator",
    "target_value",
    "cadence",
    "window_days",
    "expected_outcome",
    "how_to",
    "research_note_ids",
    "status",
    "adopted_at",
    "ends_at",
    "completed_at",
    "abandoned_at",
    "baseline_value",
    "program_id",
    "rung_index",
    # `0010`. `standard` on every standalone challenge; `deload` only on a rung the
    # ladder inserted after one timed out unmet (``challenges.ladder``).
    "kind",
    # `0023`. The weekly coach job's own words and bad-day floor; every one nullable
    # ("not authored"), and none of them changes how the rule is scored.
    "action_text",
    "slot_text",
    "floor_value",
    "floor_text",
    "counts_when",
    "days_required",
)

SELECT = ", ".join(COLUMNS)  # a module constant of column names, never input


def row(values: tuple) -> dict[str, Any]:
    """One ``challenge`` row as the mapping ``evaluate``/``adapt`` already take."""
    return dict(zip(COLUMNS, values, strict=True))


def fetch(cur: Cur, user_id: UUID, challenge_id: int) -> dict[str, Any] | None:
    """One of ``user_id``'s challenges, or ``None``.

    ``None`` covers both "no such challenge" and "someone else's challenge", and
    the caller must not distinguish them: a 404 that becomes a 403 for the rows
    that exist confirms another tenant's ids (MULTI_USER.md §10).
    """
    # `SELECT` is the module's own column-name constant, never caller input — the
    # only interpolation this codebase allows (standards §2). Bounds stay `%s`.
    query = cast(LiteralString, f"SELECT {SELECT} FROM challenge WHERE user_id = %s AND id = %s")
    cur.execute(query, (user_id, challenge_id))
    found = cur.fetchone()
    return row(found) if found else None


def list_by_status(
    cur: Cur, user_id: UUID, statuses: tuple[str, ...], limit: int = 50
) -> list[dict[str, Any]]:
    """``user_id``'s challenges in any of ``statuses``, newest first.

    ``limit`` is not optional in spirit: every list read is windowed
    (standards §Performance, "unbounded data is windowed"), and a finished-challenge
    list grows without bound over a life of use.

    ``id DESC`` breaks the tie, and it is not decoration. ``created_at`` defaults to
    ``now()``, which in Postgres is the TRANSACTION's start time — so every challenge
    written in one transaction carries the identical timestamp and their relative order
    was previously whatever the planner felt like. Two identical requests could return
    the same list in two orders, and a client's feed would reshuffle under the owner's
    thumb. Found when a program's rungs and a standalone challenge first shared a
    transaction (WP-C4's contract bed).
    """
    query = cast(  # `SELECT` is a module constant — see `fetch`
        LiteralString,
        f"SELECT {SELECT} FROM challenge WHERE user_id = %s AND status = ANY(%s) "
        "ORDER BY created_at DESC, id DESC LIMIT %s",
    )
    cur.execute(query, (user_id, list(statuses), limit))
    return [row(found) for found in cur.fetchall()]


def count_active(cur: Cur, user_id: UUID) -> int:
    """How many challenges ``user_id`` currently has running — the cap's input."""
    cur.execute(
        "SELECT count(*) FROM challenge WHERE user_id = %s AND status = 'active'", (user_id,)
    )
    row = cur.fetchone()
    return int(row[0]) if row else 0


def metrics_in_status(cur: Cur, user_id: UUID, statuses: tuple[str, ...]) -> set[str]:
    """The distinct metrics ``user_id`` has a challenge on in any of ``statuses``."""
    cur.execute(
        "SELECT DISTINCT metric FROM challenge WHERE user_id = %s AND status = ANY(%s)",
        (user_id, list(statuses)),
    )
    return {row[0] for row in cur.fetchall()}


def active_metrics(cur: Cur, user_id: UUID) -> set[str]:
    """The metrics ``user_id`` is ALREADY running a challenge on — the dedup input.

    A second live challenge on the same metric is not a second commitment, it is the
    same commitment scored twice: both would read the same ``derived_daily`` rows, and
    the outcome ledger would record two before/afters over one behaviour change.

    A thin wrapper on :func:`metrics_in_status` rather than its own statement, because
    generation asks the same question of a different status set when it is ADDING to
    the feed instead of replacing it (``generate``'s ``replace_feed``) — and two
    near-identical SELECTs is how the two answers come to disagree.
    """
    return metrics_in_status(cur, user_id, ("active",))


def delete_suggestions(cur: Cur, user_id: UUID) -> int:
    """Clear ``user_id``'s un-adopted standalone suggestions; returns how many went.

    A regeneration REPLACES the suggestion feed rather than appending to it (legacy did
    the same): suggestions are a menu computed from a baseline that has since moved, and
    keeping the stale ones would offer targets calibrated against a person who no longer
    exists. Rows belonging to a program are left alone — a rung is part of a ladder
    somebody adopted, not a loose suggestion (WP-C4 owns those).
    """
    cur.execute(
        "DELETE FROM challenge WHERE user_id = %s AND status = 'suggested' AND program_id IS NULL",
        (user_id,),
    )
    return cur.rowcount


# The optional `0023` fields `insert_suggested` accepts, in the order the INSERT lists them.
_COACH_FIELDS = (
    "action_text",
    "slot_text",
    "floor_value",
    "floor_text",
    "counts_when",
    "days_required",
)


def insert_suggested(cur: Cur, user_id: UUID, gen_date: date, challenge: dict) -> int:
    """Persist one generated challenge as ``suggested``; returns its id.

    Every value written here has already passed both gates — this function decides
    nothing. In particular ``target_value`` is stored exactly as proposed: no code path
    in this package rewrites it (``bounds`` argues why), which is what keeps the stored
    number and the shipped copy from disagreeing.
    """
    cur.execute(
        "INSERT INTO challenge (user_id, gen_date, title, why, category, difficulty, "
        "  metric, comparator, target_value, cadence, window_days, expected_outcome, "
        "  how_to, research_note_ids, action_text, slot_text, floor_value, floor_text, "
        "  counts_when, days_required, status) "
        "VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,'suggested') "
        "RETURNING id",
        (
            user_id,
            gen_date,
            challenge["title"],
            challenge["why"],
            challenge["category"],
            challenge["difficulty"],
            challenge["metric"],
            challenge["comparator"],
            float(challenge["target_value"]),
            challenge["cadence"],
            int(challenge["window_days"]),
            challenge.get("expected_outcome"),
            challenge.get("how_to"),
            list(challenge["research_note_ids"]),
            *(challenge.get(field) for field in _COACH_FIELDS),
        ),
    )
    row = cur.fetchone()
    if row is None:
        raise RuntimeError("INSERT ... RETURNING id produced no row")
    return int(row[0])


def mark_adopted(
    cur: Cur,
    user_id: UUID,
    challenge_id: int,
    adopted_at: datetime,
    ends_at: datetime,
    baseline_value: float | None,
) -> bool:
    """Move a suggestion to ``active``. False ⇒ it was not still ``suggested``.

    The status predicate is IN THE STATEMENT, not a read-then-write in the caller:
    two adopt requests racing on the same suggestion would both pass a prior check
    and the second would reset the first's baseline — the anchor the whole
    before/after rests on. Here the loser updates zero rows and is told so.
    """
    cur.execute(
        "UPDATE challenge SET status = 'active', adopted_at = %s, ends_at = %s, "
        "  baseline_value = %s "
        "WHERE user_id = %s AND id = %s AND status = 'suggested'",
        (adopted_at, ends_at, baseline_value, user_id, challenge_id),
    )
    return cur.rowcount == 1


def set_target(cur: Cur, user_id: UUID, challenge_id: int, target_value: float) -> bool:
    """Move a live challenge's target. False ⇒ it was not active.

    The VALUE is never a caller's: ``lifecycle.apply_adaptation`` recomputes it from
    the owner's own rows before calling here (CHALLENGES.md §5.2 — a client may
    *request* an adaptation, it can never dictate the number). This function is one
    step away from that rule, which is why it says so.
    """
    cur.execute(
        "UPDATE challenge SET target_value = %s "
        "WHERE user_id = %s AND id = %s AND status = 'active'",
        (target_value, user_id, challenge_id),
    )
    return cur.rowcount == 1


def set_slot_text(cur: Cur, user_id: UUID, challenge_id: int, slot_text: str) -> bool:
    """Rewrite ONLY ``slot_text`` on a suggested or active challenge. False ⇒ neither.

    A label for when the owner will do it; it feeds no rule, target or verdict.
    """
    cur.execute(
        "UPDATE challenge SET slot_text = %s "
        "WHERE user_id = %s AND id = %s AND status IN ('suggested', 'active')",
        (slot_text, user_id, challenge_id),
    )
    return cur.rowcount == 1


def mark_abandoned(cur: Cur, user_id: UUID, challenge_id: int, at: datetime) -> bool:
    """End an active challenge at the owner's request. False ⇒ it was not active."""
    cur.execute(
        "UPDATE challenge SET status = 'abandoned', abandoned_at = %s "
        "WHERE user_id = %s AND id = %s AND status = 'active'",
        (at, user_id, challenge_id),
    )
    return cur.rowcount == 1


def mark_finished(cur: Cur, user_id: UUID, challenge_id: int, status: str, at: datetime) -> bool:
    """Close an active challenge as ``completed`` or ``expired``. False ⇒ not active.

    ``completed_at`` is stamped ONLY for ``completed``. An expired challenge was
    never completed, and writing the completion timestamp anyway is precisely the
    small confident lie `0009` added the status for — when it ended is already
    exact in ``ends_at``, and the freeze instant is the outcome row's ``ended_at``.
    """
    completed_at = at if status == "completed" else None
    cur.execute(
        "UPDATE challenge SET status = %s, completed_at = %s "
        "WHERE user_id = %s AND id = %s AND status = 'active'",
        (status, completed_at, user_id, challenge_id),
    )
    return cur.rowcount == 1
