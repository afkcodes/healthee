"""The coach ledger end to end against a real database (skips without TimescaleDB).

Dates are relative to the owner's today because ``build_ledger`` reads the clock; every
assertion is on days well inside the 28-day window, so the run date does not matter.
"""

from __future__ import annotations

import json
from collections.abc import Iterator
from datetime import date, datetime, time, timedelta
from zoneinfo import ZoneInfo

import pytest
from tests.challenges import _seed

from healthee.challenges.record import build_ledger
from healthee.challenges.record_window import review_key
from healthee.core.db import admin_connection, tenant_transaction
from healthee.core.tenancy import SENTINEL_TZ, user_today
from healthee.db import migrate

pytestmark = pytest.mark.integration

_TZ = ZoneInfo(SENTINEL_TZ)


def _reset() -> None:
    """``_seed.reset`` plus ``recommendation``, which the shared reset list does not clear.

    Without this, ideas left by an earlier test (or suite) leak into the ledger's counts.
    """
    _seed.reset()
    with admin_connection() as conn, conn.cursor() as cur:
        cur.execute("TRUNCATE recommendation")


@pytest.fixture
def owner(db: None) -> Iterator[None]:  # noqa: ARG001 — gates on DB reachability
    migrate.apply_migrations()
    _reset()
    yield
    _reset()


def _at(day: date) -> datetime:
    return datetime.combine(day, time(7, 0), tzinfo=_TZ)


def _challenge(cur, user, today: date, **kw) -> int:
    ago = kw.pop("days_ago")
    adopted = _at(today - timedelta(days=ago))
    cur.execute(
        "INSERT INTO challenge (user_id, title, why, category, metric, comparator, target_value, "
        "  cadence, window_days, status, adopted_at, ends_at, floor_value, action_text) "
        "VALUES (%s,%s,'w','activity',%s,%s,%s,'daily',%s,%s,%s,%s,%s,%s) RETURNING id",
        (
            user, kw.get("title", "t"), kw["metric"], kw.get("comparator", ">="), kw["target"],
            kw["window_days"], kw.get("status", "active"), adopted,
            adopted + timedelta(days=kw["window_days"]), kw.get("floor"), kw.get("action"),
        ),
    )  # fmt: skip
    return int(cur.fetchone()[0])


def _rec(cur, user, day: date, rank: int, action: str, adopted: bool | None) -> int:
    cur.execute(
        "INSERT INTO recommendation (user_id, date, rank, action, rationale, category, "
        "  evidence_grade, research_note_ids, signal_source, adopted) "
        "VALUES (%s,%s,%s,%s,'r','activity',2,ARRAY['n'],'s',%s) RETURNING id",
        (user, day, rank, action, adopted),
    )
    return int(cur.fetchone()[0])


def _entries(ledger: dict) -> list[dict]:
    return [e for week in ledger["weeks"] for e in week["entries"]]


def test_challenge_days_are_checked_against_the_strap(owner: None) -> None:
    today = user_today(SENTINEL_TZ)
    with tenant_transaction(_seed.OWNER) as cur:
        _seed.seed_metric(
            cur, _seed.OWNER, "steps_total",
            {today - timedelta(days=3): 7000, today - timedelta(days=2): 4000,
             today - timedelta(days=1): 500},
        )  # fmt: skip
        cid = _challenge(
            cur, _seed.OWNER, today, days_ago=3, metric="steps_total", target=6000.0,
            floor=3000.0, window_days=7, action="Walk toward 6,000 steps",
        )  # fmt: skip
        ledger = build_ledger(cur, _seed.OWNER, SENTINEL_TZ, "month")
    mine = sorted((e for e in _entries(ledger) if e["ref_id"] == cid), key=lambda e: e["date"])
    assert [e["verdict"] for e in mine] == ["done", "partial", "missed"]
    assert mine[0]["measured"] == {"value": 7000.0, "unit": "steps", "label": "7,000 steps"}
    assert mine[0]["title"] == "Walk toward 6,000 steps"
    assert ledger["yeses"] == 3 and ledger["done_rate"] == {"done": 1, "provable": 3}


def test_a_day_without_a_reading_is_no_data_and_a_journal_entry_decides_caffeine(
    owner: None,
) -> None:
    today = user_today(SENTINEL_TZ)
    with tenant_transaction(_seed.OWNER) as cur:
        _challenge(cur, _seed.OWNER, today, days_ago=3, metric="steps_total", target=6000.0,
                   window_days=2)  # fmt: skip
        caf = _challenge(cur, _seed.OWNER, today, days_ago=2, metric="caffeine_mg",
                         comparator="<=", target=200.0, window_days=2)  # fmt: skip
        _seed.seed_manual(cur, _seed.OWNER, "caffeine",
                          [(_at(today - timedelta(days=1)), 80.0, "mg")])  # fmt: skip
        ledger = build_ledger(cur, _seed.OWNER, SENTINEL_TZ, "month")
    steps = [e for e in _entries(ledger) if e["ref_id"] != caf]
    assert {e["verdict"] for e in steps} == {"no_data"}
    got = sorted((e for e in _entries(ledger) if e["ref_id"] == caf), key=lambda e: e["date"])
    assert [e["verdict"] for e in got] == ["uncheckable", "done"]
    assert all(e["measured"]["value"] is None for e in got)


def test_legacy_recommendations_and_ideas_given(owner: None) -> None:
    today = user_today(SENTINEL_TZ)
    day = today - timedelta(days=4)
    with tenant_transaction(_seed.OWNER) as cur:
        _seed.seed_metric(cur, _seed.OWNER, "steps_total", {day: 7000})
        walk = _rec(cur, _seed.OWNER, day, 1, "Walk toward 6,000 steps", True)
        bed = _rec(cur, _seed.OWNER, day, 2, "Earlier bedtime tonight", True)
        _rec(cur, _seed.OWNER, day, 3, "Skipped idea", None)
        _rec(cur, _seed.OWNER, day, 4, "Dismissed idea", False)
        ledger = build_ledger(cur, _seed.OWNER, SENTINEL_TZ, "month")
    by_ref = {e["ref_id"]: e for e in _entries(ledger)}
    assert by_ref[walk]["verdict"] == "done" and by_ref[walk]["source"] == "recommendation"
    assert by_ref[bed]["verdict"] == "uncheckable" and by_ref[bed]["measured"]["value"] is None
    assert ledger["ideas_given"] == 4 and ledger["yeses"] == 2


def test_never_done_without_a_measured_value(owner: None) -> None:
    today = user_today(SENTINEL_TZ)
    with tenant_transaction(_seed.OWNER) as cur:
        _rec(cur, _seed.OWNER, today - timedelta(days=2), 1, "Get 8 hours of sleep", True)
        _rec(cur, _seed.OWNER, today - timedelta(days=3), 1, "Hydrate well", True)
        ledger = build_ledger(cur, _seed.OWNER, SENTINEL_TZ, "all")
    assert ledger["totals"]["done"] == 0
    assert sorted(e["verdict"] for e in _entries(ledger)) == ["no_data", "uncheckable"]


def test_the_pattern_is_the_latest_stored_review_or_null(owner: None) -> None:
    today = user_today(SENTINEL_TZ)
    with tenant_transaction(_seed.OWNER) as cur:
        assert build_ledger(cur, _seed.OWNER, SENTINEL_TZ, "week")["pattern"] is None
        for back, text in ((14, "older"), (0, "newest")):
            cur.execute(
                "INSERT INTO kv (user_id, key, value) VALUES (%s, %s, %s)",
                (
                    _seed.OWNER,
                    review_key(today - timedelta(days=back)),
                    json.dumps({"pattern": text}),
                ),
            )
        assert build_ledger(cur, _seed.OWNER, SENTINEL_TZ, "week")["pattern"] == "newest"


def test_another_owners_yeses_never_appear(owner: None) -> None:
    today = user_today(SENTINEL_TZ)
    _seed.ensure_owner_b()
    try:
        with tenant_transaction(_seed.OTHER_OWNER) as cur:
            _challenge(cur, _seed.OTHER_OWNER, today, days_ago=2, metric="steps_total",
                       target=1.0, window_days=3)  # fmt: skip
            _rec(cur, _seed.OTHER_OWNER, today - timedelta(days=2), 1, "Walk 6,000 steps", True)
        with tenant_transaction(_seed.OWNER) as cur:
            ledger = build_ledger(cur, _seed.OWNER, SENTINEL_TZ, "all")
        assert ledger["yeses"] == 0 and ledger["ideas_given"] == 0
    finally:
        _seed.remove_owner_b()


def test_all_window_starts_at_the_first_idea(owner: None) -> None:
    today = user_today(SENTINEL_TZ)
    first = today - timedelta(days=60)
    with tenant_transaction(_seed.OWNER) as cur:
        _rec(cur, _seed.OWNER, first, 1, "Old idea", None)
        ledger = build_ledger(cur, _seed.OWNER, SENTINEL_TZ, "all")
    assert ledger["from"] == first and ledger["to"] == today and ledger["ideas_given"] == 1
    assert _entries(ledger) == []  # an unadopted idea is not a yes
