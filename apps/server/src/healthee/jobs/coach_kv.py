"""Where the coach's output lives: ``kv`` rows keyed by ISO week and by day.

* ``coach_review:{ISOYEAR}-W{WW}`` — the stored review (the ledger reads ``pattern`` from
  it; the key is ``record_window.review_key``, the ONE definition).
* ``coach_today:{date}`` — that day's check-in line.
* ``coach_review_claim:{ISOYEAR}-W{WW}`` — a short-lived claim so two first callers in a
  week cannot both generate (and both spend a model call). A claim older than
  ``CLAIM_TTL`` is taken over: its holder died.

Every statement is owner-scoped. The week a review is FOR is :func:`target_day`: on Sunday
it is next week (the Sunday review sets next week's job), otherwise this one.
"""

from __future__ import annotations

import json
from datetime import UTC, date, datetime, timedelta
from typing import Any
from uuid import UUID

from healthee.challenges.record_window import review_key, week_start
from healthee.derive._common import Cur

CLAIM_TTL = timedelta(minutes=5)
_SUNDAY = 6


def target_day(today: date) -> date:
    """A day inside the week the review is for: tomorrow on Sunday, else today."""
    return today + timedelta(days=1) if today.weekday() == _SUNDAY else today


def week_bounds(today: date) -> tuple[date, date]:
    """Monday and Sunday of the week the review is for."""
    monday = week_start(target_day(today))
    return monday, monday + timedelta(days=6)


def week_label(today: date) -> str:
    """``2026-W43``."""
    return review_key(target_day(today)).removeprefix("coach_review:")


def key_for_week(today: date) -> str:
    return review_key(target_day(today))


def claim_key(today: date) -> str:
    return "coach_review_claim:" + week_label(today)


def today_key(day: date) -> str:
    return f"coach_today:{day.isoformat()}"


def get_json(cur: Cur, user_id: UUID, key: str) -> dict[str, Any] | None:
    """The stored JSON object under ``key``, or ``None``."""
    cur.execute("SELECT value FROM kv WHERE user_id = %s AND key = %s", (user_id, key))
    found = cur.fetchone()
    if found is None:
        return None
    loaded = json.loads(found[0])
    return loaded if isinstance(loaded, dict) else None


def put_json(cur: Cur, user_id: UUID, key: str, payload: dict[str, Any]) -> None:
    """Upsert a JSON object under ``key``."""
    cur.execute(
        "INSERT INTO kv (user_id, key, value) VALUES (%s, %s, %s) "
        "ON CONFLICT (user_id, key) DO UPDATE SET value = EXCLUDED.value",
        (user_id, key, json.dumps(payload, default=str)),
    )


def claim(cur: Cur, user_id: UUID, key: str, now: datetime | None = None) -> bool:
    """Take the generation claim. False means somebody else holds a live one."""
    now = (now or datetime.now(tz=UTC)).astimezone(UTC)  # one zone: the compare is textual
    cur.execute(
        "INSERT INTO kv (user_id, key, value) VALUES (%s, %s, %s) "
        "ON CONFLICT (user_id, key) DO UPDATE SET value = EXCLUDED.value "
        "WHERE kv.value < %s",
        (user_id, key, now.isoformat(), (now - CLAIM_TTL).isoformat()),
    )
    return cur.rowcount == 1


def release(cur: Cur, user_id: UUID, key: str) -> None:
    """Drop the claim (always — success has stored the review, failure must allow a retry)."""
    cur.execute("DELETE FROM kv WHERE user_id = %s AND key = %s", (user_id, key))
