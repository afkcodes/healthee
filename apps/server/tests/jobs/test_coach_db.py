"""The weekly coach against a real database (skips without TimescaleDB).

The model is a scripted stub behind the real choke point; everything else is real: the
context reads, the claim, the challenge insert, the stored review and the ledger that reads
it back. Dates are relative to the owner's today, and assertions hold for any weekday
(the review week is whatever ``coach_kv`` says it is, never a literal).
"""

from __future__ import annotations

import json
from collections.abc import Iterator
from datetime import date, datetime, timedelta
from zoneinfo import ZoneInfo

import pytest
from tests.challenges import _seed
from tests.insights._stub import StubLLM
from tests.jobs._coach_fixtures import answer

from healthee.challenges.record import build_ledger
from healthee.core.db import admin_connection, tenant_transaction
from healthee.core.tenancy import SENTINEL_TZ, SENTINEL_USER_ID, user_today
from healthee.db import migrate
from healthee.jobs import coach_inputs, coach_kv, coach_today, coach_weekly

pytestmark = pytest.mark.integration

_TZ = ZoneInfo(SENTINEL_TZ)
_USER = SENTINEL_USER_ID


@pytest.fixture
def owner(db: None) -> Iterator[date]:  # noqa: ARG001 — gates on DB reachability
    migrate.apply_migrations()
    _reset()
    today = user_today(SENTINEL_TZ)
    with tenant_transaction(_USER) as cur:
        days = [today - timedelta(days=i) for i in range(1, 31)]
        _seed.seed_metric(
            cur, _USER, "steps_total", {d: 4000.0 + 10 * i for i, d in enumerate(days)}
        )
        _seed.seed_metric(cur, _USER, "mvpa_min", {d: 12.0 for d in days})
        _seed.seed_metric(cur, _USER, "recovery_score", {today: 60.0})
        _seed.seed_sleep(cur, _USER, {d: 420.0 for d in days[:10]})
    yield today
    _reset()


def _reset() -> None:
    _seed.reset()
    with admin_connection() as conn, conn.cursor() as cur:
        cur.execute("TRUNCATE recommendation")


def _stub(**over) -> StubLLM:
    return StubLLM(json_text=json.dumps(answer(**over)))


def _jobs() -> list[dict]:
    with tenant_transaction(_USER) as cur:
        cur.execute(
            "SELECT id, status, metric, target_value, cadence, window_days, action_text, "
            "slot_text, floor_value, floor_text, counts_when, days_required "
            "FROM challenge WHERE user_id = %s ORDER BY id",
            (_USER,),
        )
        keys = (
            "id status metric target cadence window action slot floor_value floor_text counts days"
        )
        return [dict(zip(keys.split(), row, strict=True)) for row in cur.fetchall()]


def _adopted_job(cur, today: date, *, target: float, ago: int, status: str, days_required=4) -> int:
    adopted = datetime.combine(today - timedelta(days=ago), datetime.min.time(), tzinfo=_TZ)
    cur.execute(
        "INSERT INTO challenge (user_id, title, why, category, metric, comparator, target_value, "
        "  cadence, window_days, status, adopted_at, ends_at, floor_value, action_text, slot_text, "
        "  floor_text, counts_when, days_required) "
        "VALUES (%s,'Walk','w','activity','mvpa_min','>=',%s,'daily',7,%s,%s,%s,%s,'Walk', "
        "  'evening','10 min','20 brisk min',%s) RETURNING id",
        (_USER, target, status, adopted, adopted + timedelta(days=7), target / 2, days_required),
    )
    return int(cur.fetchone()[0])


# ── the context ───────────────────────────────────────────────────────────────


def test_the_four_blocks_read_the_owners_own_numbers(owner: date) -> None:
    with tenant_transaction(_USER) as cur:
        _adopted_job(cur, owner, target=10.0, ago=3, status="active")
    got = coach_inputs.read_inputs(_USER, SENTINEL_TZ, owner)

    assert "COMMITMENTS (last 8 weeks" in got.text and "[mvpa_min]" in got.text
    assert "4 days out of 7" in got.text
    assert "WEEKS (Mon to Sun):" in got.text and "no reading" in got.text  # the missing days
    assert "CURRENT:" in got.text and "Days done so far" in got.text
    assert "RECOVERY today: 60/100, zone moderate" in got.text
    assert got.recovery == (60, "moderate") and got.active is not None and got.has_data


def test_a_missing_recovery_is_no_reading_not_zero(owner: date) -> None:  # noqa: ARG001
    with admin_connection() as conn, conn.cursor() as cur:
        cur.execute("DELETE FROM derived_daily WHERE metric = 'recovery_score'")
    got = coach_inputs.read_inputs(_USER, SENTINEL_TZ, user_today(SENTINEL_TZ))
    assert "RECOVERY today: no reading" in got.text and got.recovery is None


# ── one generation per ISO week ───────────────────────────────────────────────


def test_the_second_call_in_a_week_is_the_stored_review_and_costs_no_model_call(
    owner: date,
) -> None:
    stub = _stub()
    first, cached_first = coach_weekly.generate_week(_USER, SENTINEL_TZ, owner, client=stub)
    spent = stub.calls
    second, cached_second = coach_weekly.generate_week(_USER, SENTINEL_TZ, owner, client=stub)

    assert (cached_first, cached_second) == (False, True)
    assert stub.calls == spent and spent >= 1
    assert first is not None and second is not None
    assert second == first and first["week"] == coach_kv.week_label(owner)
    assert first["job"]["challenge_id"] > 0


def test_the_job_is_a_suggested_challenge_with_the_coach_fields(owner: date) -> None:
    review, _ = coach_weekly.generate_week(_USER, SENTINEL_TZ, owner, client=_stub())
    (job,) = _jobs()
    assert review is not None
    assert job["id"] == review["job"]["challenge_id"] and job["status"] == "suggested"
    assert (job["metric"], job["target"], job["cadence"], job["window"]) == (
        "mvpa_min", 20.0, "daily", 7,
    )  # fmt: skip
    assert job["days"] == 4 and job["action"] == "Walk briskly for 20 minutes"
    assert (
        job["slot"].startswith("after 10 pm") and job["floor_text"] == "10 minutes counts as half"
    )
    assert job["counts"] == "when the strap logs 20 brisk minutes"
    assert job["floor_value"] == 10.0  # half credit, from the target


def test_the_ledger_pattern_is_the_pattern_the_writer_stored(owner: date) -> None:
    review, _ = coach_weekly.generate_week(_USER, SENTINEL_TZ, owner, client=_stub())
    with tenant_transaction(_USER) as cur:
        ledger = build_ledger(cur, _USER, SENTINEL_TZ, "month")
        cur.execute(
            "SELECT key FROM kv WHERE user_id = %s AND key LIKE 'coach_review:%%'", (_USER,)
        )
        keys = [r[0] for r in cur.fetchall()]
    assert review is not None
    assert keys == [coach_kv.key_for_week(owner)] and ledger["pattern"] == review["pattern"]


def test_a_live_claim_makes_the_second_caller_wait_then_time_out(
    owner: date, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr(coach_weekly, "WAIT_SECONDS", 0.2)
    monkeypatch.setattr(coach_weekly, "_POLL_SECONDS", 0.05)
    with tenant_transaction(_USER) as cur:
        assert coach_kv.claim(cur, _USER, coach_kv.claim_key(owner))
    stub = _stub()
    with pytest.raises(coach_weekly.ReviewBusyError):
        coach_weekly.generate_week(_USER, SENTINEL_TZ, owner, client=stub)
    assert stub.calls == 0  # it did not generate a second time


def test_a_stale_claim_is_taken_over_and_a_failure_releases_the_claim(
    owner: date, monkeypatch: pytest.MonkeyPatch
) -> None:
    old = datetime.now(tz=_TZ) - coach_kv.CLAIM_TTL - timedelta(minutes=1)
    with tenant_transaction(_USER) as cur:
        assert coach_kv.claim(cur, _USER, coach_kv.claim_key(owner), now=old)
    boom = RuntimeError("model down")
    monkeypatch.setattr(coach_weekly, "propose", lambda *a, **k: (_ for _ in ()).throw(boom))
    with pytest.raises(RuntimeError, match="model down"):
        coach_weekly.generate_week(_USER, SENTINEL_TZ, owner, client=_stub())
    with tenant_transaction(_USER) as cur:  # released: a retry may claim at once
        assert coach_kv.claim(cur, _USER, coach_kv.claim_key(owner))
    assert coach_weekly.read_stored(_USER, owner) is None


def test_an_oversized_proposal_is_retried_once_then_the_previous_job_repeats(owner: date) -> None:
    with tenant_transaction(_USER) as cur:
        _adopted_job(cur, owner, target=20.0, ago=20, status="expired")
    stub = _stub(job={"target": 200})  # far outside the allowed repeat
    review, _ = coach_weekly.generate_week(_USER, SENTINEL_TZ, owner, client=stub)

    assert stub.calls == 2  # one try plus ONE retry with the range stated
    assert review is not None
    assert review["job"]["target"] == 20.0  # the previous rule, never the model's 200
    assert review["rationale"] is None and "repeats unchanged" in review["review"]
    assert any(j["status"] == "suggested" and j["target"] == 20.0 for j in _jobs())


def test_no_readings_and_no_earlier_job_writes_nothing(owner: date) -> None:
    with admin_connection() as conn, conn.cursor() as cur:
        cur.execute("TRUNCATE derived_daily")
    stub = _stub()
    review, cached = coach_weekly.generate_week(_USER, SENTINEL_TZ, owner, client=stub)
    assert (review, cached, stub.calls) == (None, False, 0)
    assert coach_weekly.read_stored(_USER, owner) is None and _jobs() == []


# ── the daily check-in ────────────────────────────────────────────────────────


def test_no_active_job_means_no_check_in_and_no_model_call(owner: date) -> None:
    stub = _stub()
    assert coach_today.generate_today(_USER, SENTINEL_TZ, owner, client=stub) == {
        "ok": True, "skipped": "no active job",
    }  # fmt: skip
    assert stub.calls == 0


def test_a_job_already_done_says_so_without_asking_the_model(owner: date) -> None:
    with tenant_transaction(_USER) as cur:
        _adopted_job(cur, owner, target=10.0, ago=5, status="active")  # mvpa 12 >= 10 each day
    stub = _stub()
    out = coach_today.generate_today(_USER, SENTINEL_TZ, owner, client=stub)
    assert out["source"] == "rule" and stub.calls == 0
    assert "done" in (coach_today.read_today_line(_USER, owner) or "")


def test_a_job_in_play_asks_the_model_and_stores_the_line(owner: date) -> None:
    with tenant_transaction(_USER) as cur:
        _adopted_job(cur, owner, target=50.0, ago=2, status="active")  # 12 < 50: not done
    stub = _stub(job=None, review=None, pattern=None)
    out = coach_today.generate_today(_USER, SENTINEL_TZ, owner, client=stub)
    assert out["source"] == "model" and stub.calls == 1
    assert coach_today.read_today_line(_USER, owner) == answer()["today"]
