"""Runtime proof that running a JOB for one owner never touches another's rows.

The gap this closes: every other isolation suite covers READS (`test_read_isolation`,
`test_service_leakage`, `test_http_isolation`) or one job's dedup marker. Nothing
asserted that a job run *for one owner* leaves another owner's data alone — and a
cross-tenant WRITE lived in `correlate` through all of Phase 6 because of it
(`persist_cutoff_findings` hardwired the sentinel, so every owner's nightly sweep
DELETEd the sentinel's `personal_cutoff` rows and replaced them with its own).

Why the existing guards could not see it, and why this suite is the one that can:

  * **RLS** (0008) checks that a written row matches the owner DECLARED on the
    transaction. The bad write declared the sentinel and wrote the sentinel's rows —
    internally consistent, just for the wrong person. Consistency is not correctness.
  * **The AST guard** (`test_tenant_read_scoping`) proves `user_id` is BOUND in the
    SQL. It was: to a constant. A bound column says nothing about the value.

Both verify the write against itself. Only running the job for a KNOWN owner and
looking at a DIFFERENT owner's rows can verify it against the request.

Shape: two owners, each with their own caffeine/sleep data seeded IN THEIR OWN
TIMEZONE, so each produces real `personal_cutoff` findings whose `details.cutoff_tz`
names their zone — the distinguishing lever the code already provides, needing no
contrived values. A's chain runs, then B's; A's findings must be byte-identical
after. Then the mirror, so neither direction rests on a one-sided assertion.

Note on the catching direction: the hardwired constant WAS owner A (the sentinel), so
"run A, inspect B" passes even against the bug. "Run B, inspect A" is what fails. Both
directions are asserted anyway — the next such bug need not be hardwired to A.

Auto-skips without a reachable TimescaleDB (same policy as the other integration
tests).
"""

from __future__ import annotations

import json
from collections.abc import Iterator
from datetime import date, datetime, time, timedelta
from uuid import UUID
from zoneinfo import ZoneInfo

import pytest
from tests.contracts import seed
from tests.contracts.seed_owner_b import OWNER_B, OWNER_B_TZ
from tests.insights._stub import StubLLM

from healthee.core.db import admin_connection, tenant_transaction, transaction
from healthee.core.tenancy import SENTINEL_TZ, SENTINEL_USER_ID, user_today
from healthee.jobs import coach_kv
from healthee.jobs.coach_weekly import generate_week
from healthee.jobs.correlate import run_correlate

pytestmark = pytest.mark.integration

# A FIXED far-future window. Nothing in the finding/cutoff path has a recency filter
# (`daily_series` and `_load_sleep_nights` read every row), so anchoring to a constant
# date — instead of `today` — makes this suite identical under TZ=UTC and TZ=IST and
# keeps it off the seeded fixtures' days.
_ANCHOR = date(2999, 6, 15)
_NIGHTS = 30
_CAFFEINE_NIGHTS = 15  # ≥ MIN_INTAKE_NIGHTS (10); the rest are controls (≥ MIN_CONTROL_NIGHTS)
_CAFFEINE_HOUR = 21  # local — above every candidate cutoff hour, so the finder fires

# The realistically-directioned caffeine effect (Drake 2013): caffeine nights sleep
# less, with lower HRV and higher RHR. Mirrors `test_seam_integration`'s proven seed —
# the direction gate accepts it, so both owners yield real `personal_cutoff` findings.
_CAFFEINE_STAGES = (60, 200, 40, 60)  # rem, light, deep, wake → TST 300
_CONTROL_STAGES = (100, 300, 100, 20)  # TST 500
_CAFFEINE_HRV, _CAFFEINE_RHR = 40.0, 60.0
_CONTROL_HRV, _CONTROL_RHR = 55.0, 52.0


def _nights() -> list[date]:
    return [_ANCHOR - timedelta(days=i) for i in range(_NIGHTS - 1, -1, -1)]


def _seed_night(cur, user_id: UUID, zone: ZoneInfo, wake: date, stages: tuple) -> None:
    """One 'main' session ending 07:00 on ``wake`` in the OWNER's zone (onset 23:00 prior).

    Anchored in the owner's own zone so `_load_sleep_nights`'s
    `(end_ts AT TIME ZONE tz)::date` round-trips back to exactly ``wake`` — which is
    what lets the per-night derived_daily join land.
    """
    rem, light, deep, wake_min = stages
    end_ts = datetime.combine(wake, time(7, 0), tzinfo=zone)
    cur.execute(
        "INSERT INTO sleep_session "
        "(user_id, start_ts, end_ts, kind, rem_min, light_min, deep_min, wake_min) "
        "VALUES (%s, %s, %s, 'main', %s, %s, %s, %s) "
        "ON CONFLICT (user_id, start_ts) DO NOTHING",
        (user_id, end_ts - timedelta(hours=8), end_ts, rem, light, deep, wake_min),
    )


def _seed_daily(cur, user_id: UUID, day: date, metric: str, value: float) -> None:
    cur.execute(
        "INSERT INTO derived_daily (user_id, day, metric, value, flags) "
        "VALUES (%s, %s, %s, %s, '{}'::jsonb) "
        "ON CONFLICT (user_id, day, metric) DO UPDATE SET value = EXCLUDED.value",
        (user_id, day, metric, value),
    )


def _seed_caffeine(cur, user_id: UUID, zone: ZoneInfo, wake: date) -> None:
    """A caffeine log at 21:00 the evening before ``wake``, in the owner's zone."""
    ts = datetime.combine(wake - timedelta(days=1), time(_CAFFEINE_HOUR, 0), tzinfo=zone)
    cur.execute(
        "INSERT INTO manual_entry (user_id, kind, ts, amount, unit) "
        "VALUES (%s, 'caffeine', %s, 100, 'mg')",
        (user_id, ts),
    )


def _seed_owner(user_id: UUID, tz: str) -> None:
    """Give one owner a cutoff-eligible history, expressed in THEIR timezone."""
    zone = ZoneInfo(tz)
    nights = _nights()
    caffeine, control = nights[:_CAFFEINE_NIGHTS], nights[_CAFFEINE_NIGHTS:]
    with tenant_transaction(user_id) as cur:
        for wake in caffeine:
            _seed_night(cur, user_id, zone, wake, _CAFFEINE_STAGES)
            _seed_caffeine(cur, user_id, zone, wake)
            _seed_daily(cur, user_id, wake, "hrv_sleep_avg", _CAFFEINE_HRV)
            _seed_daily(cur, user_id, wake, "rhr_daily", _CAFFEINE_RHR)
        for wake in control:
            _seed_night(cur, user_id, zone, wake, _CONTROL_STAGES)
            _seed_daily(cur, user_id, wake, "hrv_sleep_avg", _CONTROL_HRV)
            _seed_daily(cur, user_id, wake, "rhr_daily", _CONTROL_RHR)


@pytest.fixture
def two_owners_with_cutoffs(db: None) -> Iterator[None]:  # noqa: ARG001 — gates on DB
    """Owners A (sentinel) and B, each with data that yields real cutoff findings."""
    seed.reset()  # migrations + TRUNCATE, admin — `app_user` is untouched by it
    # `app_user` is an identity table with no RLS policy (0008); B's tenant rows then
    # need the owner set, or the policy's WITH CHECK denies them.
    with transaction() as cur:
        cur.execute(
            "INSERT INTO app_user (id, email, timezone) VALUES (%s, %s, %s) "
            "ON CONFLICT (id) DO NOTHING",
            (OWNER_B, "owner-b@example.test", OWNER_B_TZ),
        )
    _seed_owner(SENTINEL_USER_ID, SENTINEL_TZ)
    _seed_owner(OWNER_B, OWNER_B_TZ)
    yield
    # The ADMIN: this cleanup spans BOTH owners, which no single RLS-scoped
    # transaction can see (same category as `seed.reset`).
    with admin_connection() as conn, conn.cursor() as cur:
        cur.execute("DELETE FROM app_user WHERE id = %s", (OWNER_B,))  # cascades B's rows


def _findings_of_kind(user_id: UUID, kind: str) -> list[tuple]:
    """One owner's findings of ``kind``, fully materialised for an equality snapshot.

    Read in the owner's OWN `tenant_transaction` — since 0008 that is the only way
    tenant rows are visible at all, and it mirrors the router exactly.
    """
    with tenant_transaction(user_id) as cur:
        cur.execute(
            "SELECT kind, description, metric_a, metric_b, event_kind, lag_days, "
            "effect_size, p_value, n_samples, significant, details "
            "FROM finding WHERE user_id = %s AND kind = %s "
            "ORDER BY metric_a, metric_b, event_kind, lag_days",
            (user_id, kind),
        )
        return cur.fetchall()


def _cutoff_zones(rows: list[tuple]) -> set[str]:
    """The `cutoff_tz` every cutoff row was computed in — the owner's fingerprint."""
    return {row[-1]["cutoff_tz"] for row in rows}


# ── the premise: each owner's chain really does produce their own findings ─────


def test_each_owner_gets_their_own_cutoff_findings(two_owners_with_cutoffs: None) -> None:  # noqa: ARG001
    """The suite's premise — without real per-owner cutoffs the rest proves nothing."""
    run_correlate(SENTINEL_USER_ID, SENTINEL_TZ)
    run_correlate(OWNER_B, OWNER_B_TZ)

    a = _findings_of_kind(SENTINEL_USER_ID, "personal_cutoff")
    b = _findings_of_kind(OWNER_B, "personal_cutoff")
    assert a, "owner A must have real cutoff findings"
    assert b, "owner B's cutoffs never landed under B — they were written to another owner"
    assert _cutoff_zones(a) == {SENTINEL_TZ}, "A's cutoffs were computed in a stranger's zone"
    assert _cutoff_zones(b) == {OWNER_B_TZ}, "B's cutoffs were computed in a stranger's zone"


# ── the bug: correlate for B must not touch A ──────────────────────────────────


def test_correlate_for_b_leaves_as_cutoff_findings_untouched(
    two_owners_with_cutoffs: None,  # noqa: ARG001
) -> None:
    """THE regression. `persist_cutoff_findings` hardwired the sentinel, so B's nightly
    correlate DELETEd A's `personal_cutoff` rows and inserted B's in their place — A was
    then served B's caffeine/alcohol inferences as a claim about A's own body.

    Snapshot-equality, not a count: replacement with the same NUMBER of B's rows is the
    likely shape of this bug, and a count assertion sails straight past it.
    """
    run_correlate(SENTINEL_USER_ID, SENTINEL_TZ)
    before = _findings_of_kind(SENTINEL_USER_ID, "personal_cutoff")
    assert before, "owner A must start with cutoff findings for this test to mean anything"

    run_correlate(OWNER_B, OWNER_B_TZ)  # B's nightly sweep

    after = _findings_of_kind(SENTINEL_USER_ID, "personal_cutoff")
    assert after == before, "owner B's correlate rewrote owner A's cutoff findings"
    assert _cutoff_zones(after) == {SENTINEL_TZ}, "A's cutoffs now carry B's timezone"


def test_correlate_for_b_leaves_as_pairwise_findings_untouched(
    two_owners_with_cutoffs: None,  # noqa: ARG001
) -> None:
    """The sibling persist path (`persist_findings`) — correct today, covered so it stays so.

    It UPSERTs on a natural key that includes `user_id`, so a hardwired owner here would
    overwrite A's rows with B's numbers in place rather than deleting them: same count,
    wrong body. Snapshot-equality is what catches that.
    """
    run_correlate(SENTINEL_USER_ID, SENTINEL_TZ)
    before = _findings_of_kind(SENTINEL_USER_ID, "pairwise_lag")
    assert before, "owner A must start with pairwise findings"

    run_correlate(OWNER_B, OWNER_B_TZ)

    assert _findings_of_kind(SENTINEL_USER_ID, "pairwise_lag") == before, (
        "owner B's correlate rewrote owner A's pairwise findings"
    )


# ── the mirror: correlate for A must not touch B ───────────────────────────────


def test_correlate_for_a_leaves_bs_findings_untouched(
    two_owners_with_cutoffs: None,  # noqa: ARG001
) -> None:
    """The other direction. A one-sided suite passes by luck; this is the both-owners
    -see-their-own pattern the read suites already learned the hard way.

    This direction cannot catch the sentinel hardwiring specifically (the constant IS
    A, so running as A happens to be right) — it is here because the NEXT such bug
    need not be hardwired to A.
    """
    run_correlate(OWNER_B, OWNER_B_TZ)
    before_cutoffs = _findings_of_kind(OWNER_B, "personal_cutoff")
    before_pairwise = _findings_of_kind(OWNER_B, "pairwise_lag")
    assert before_cutoffs and before_pairwise, "owner B must start with findings"

    run_correlate(SENTINEL_USER_ID, SENTINEL_TZ)  # A's nightly sweep

    assert _findings_of_kind(OWNER_B, "personal_cutoff") == before_cutoffs, (
        "owner A's correlate rewrote owner B's cutoff findings"
    )
    assert _findings_of_kind(OWNER_B, "pairwise_lag") == before_pairwise, (
        "owner A's correlate rewrote owner B's pairwise findings"
    )


# ── the sibling chain step with a write path: the weekly coach ────────────────
#
# `briefing`, the third step, is deliberately absent: it has NO database write at
# all (it reads context, calls the choke point, and hands the text to
# `core.notify`), so there is no owner-attributed row to isolate. Asserting
# anything there would be theatre.


def _stored_review(user_id: UUID, tz: str) -> dict | None:
    with tenant_transaction(user_id) as cur:
        return coach_kv.get_json(cur, user_id, coach_kv.key_for_week(user_today(tz)))


def test_weekly_review_for_b_leaves_as_review_untouched(
    two_owners_with_cutoffs: None,  # noqa: ARG001
) -> None:
    """The weekly review is the AI text a person reads as advice about their own body, and
    it is written under a per-owner ``kv`` key and a per-owner challenge row. B's
    generation must not touch A's."""
    from tests.jobs._coach_fixtures import answer

    marker = {"week": "A", "generated_at": "2026-01-01T00:00:00+00:00", "review": "OWNER A"}
    with tenant_transaction(SENTINEL_USER_ID) as cur:
        coach_kv.put_json(
            cur, SENTINEL_USER_ID, coach_kv.key_for_week(user_today(SENTINEL_TZ)), marker
        )

    generate_week(
        OWNER_B,
        OWNER_B_TZ,
        client=StubLLM(json_text=json.dumps(answer())),
    )

    assert _stored_review(SENTINEL_USER_ID, SENTINEL_TZ) == marker, (
        "owner B's weekly review rewrote owner A's"
    )
    assert _stored_review(OWNER_B, OWNER_B_TZ) != marker
