"""The ledger's reads — every statement is owner-scoped (``AND user_id = %s``).

Nothing here decides a verdict; it answers "what was stored". Local days are computed in
SQL with ``AT TIME ZONE %s`` bound to the owner's zone, because ``adopted_at`` and
``manual_entry.ts`` are instants and the ledger speaks in the owner's calendar days.
"""

from __future__ import annotations

import json
import logging
from datetime import date
from typing import Any
from uuid import UUID

from healthee.derive._common import Cur

log = logging.getLogger(__name__)

_REVIEW_KEY_PREFIX = "coach_review:"
_CHALLENGE_STATUSES = ["active", "completed", "expired", "abandoned"]
# The column order of `challenges_adopted`'s SELECT, as the keys of each row's mapping.
_CHALLENGE_KEYS = (
    *("id", "title", "action_text", "metric", "comparator", "target", "floor", "cadence"),
    *("window_days", "adopted_day", "ends_day", "completed_day", "abandoned_day"),
)


def challenges_adopted(cur: Cur, user_id: UUID, tz: str, start: date, end: date) -> list[dict]:
    """Challenges adopted on a local day in ``[start, end]``, with their local-day bounds."""
    cur.execute(
        "SELECT id, title, action_text, metric, comparator, target_value, floor_value, cadence, "
        "  window_days, (adopted_at AT TIME ZONE %s)::date, (ends_at AT TIME ZONE %s)::date, "
        "  (completed_at AT TIME ZONE %s)::date, (abandoned_at AT TIME ZONE %s)::date "
        "FROM challenge WHERE user_id = %s AND status = ANY(%s) AND adopted_at IS NOT NULL "
        "  AND (adopted_at AT TIME ZONE %s)::date BETWEEN %s AND %s "
        "ORDER BY adopted_at, id",
        (tz, tz, tz, tz, user_id, _CHALLENGE_STATUSES, tz, start, end),
    )
    return [dict(zip(_CHALLENGE_KEYS, row, strict=True)) for row in cur.fetchall()]


def recommendations_adopted(cur: Cur, user_id: UUID, start: date, end: date) -> list[dict]:
    """Recommendations the owner said yes to, dated ``[start, end]``."""
    cur.execute(
        "SELECT id, date, action FROM recommendation "
        "WHERE user_id = %s AND adopted IS TRUE AND date BETWEEN %s AND %s "
        "ORDER BY date, rank, id",
        (user_id, start, end),
    )
    return [dict(id=i, day=d, action=a) for i, d, a in cur.fetchall()]


def ideas_by_day(cur: Cur, user_id: UUID, start: date, end: date) -> dict[date, int]:
    """Recommendation rows created per day in ``[start, end]`` — the "ideas given"."""
    cur.execute(
        "SELECT date, count(*) FROM recommendation "
        "WHERE user_id = %s AND date BETWEEN %s AND %s GROUP BY date",
        (user_id, start, end),
    )
    return {day: int(n) for day, n in cur.fetchall()}


def first_day(cur: Cur, user_id: UUID, tz: str) -> date | None:
    """The owner's first idea or adopted challenge, as a local day (``all``'s start)."""
    cur.execute(
        "SELECT least("
        "  (SELECT min(date) FROM recommendation WHERE user_id = %s), "
        "  (SELECT min((adopted_at AT TIME ZONE %s)::date) FROM challenge "
        "     WHERE user_id = %s AND adopted_at IS NOT NULL))",
        (user_id, tz, user_id),
    )
    found = cur.fetchone()
    return found[0] if found else None


def journal_days(cur: Cur, user_id: UUID, tz: str, kind: str, start: date, end: date) -> set[date]:
    """Local days on which the owner journalled an entry of ``kind``."""
    cur.execute(
        "SELECT DISTINCT (ts AT TIME ZONE %s)::date FROM manual_entry "
        "WHERE user_id = %s AND kind = %s AND (ts AT TIME ZONE %s)::date BETWEEN %s AND %s",
        (tz, user_id, kind, tz, start, end),
    )
    return {row[0] for row in cur.fetchall()}


def latest_pattern(cur: Cur, user_id: UUID) -> str | None:
    """The ``pattern`` of the newest stored weekly review, or ``None``.

    The review is written by the weekly job under ``coach_review:{ISOYEAR}-W{WW}``, a key
    that sorts chronologically. A review that is not valid JSON, or has no string
    ``pattern``, reads as absent — and is logged, because a stored review nobody can read
    is a bug in the writer, not a reason to fail the owner's ledger.
    """
    cur.execute(
        "SELECT key, value FROM kv WHERE user_id = %s AND key LIKE %s ORDER BY key DESC LIMIT 1",
        (user_id, _REVIEW_KEY_PREFIX + "%"),
    )
    found = cur.fetchone()
    if found is None:
        return None
    key, raw = found
    try:
        review: Any = json.loads(raw)
    except json.JSONDecodeError:
        log.warning("weekly review %s is not valid JSON; ledger pattern omitted", key)
        return None
    pattern = review.get("pattern") if isinstance(review, dict) else None
    return pattern if isinstance(pattern, str) and pattern.strip() else None
