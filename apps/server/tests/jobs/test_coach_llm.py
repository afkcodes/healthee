"""The grounded coach call and the weekly writer, without a database or a network."""

from __future__ import annotations

from collections.abc import Iterator
from contextlib import contextmanager
from datetime import date
from uuid import UUID

import pytest
from tests.jobs._coach_fixtures import TODAY, answer, grounded, prev_job, weeks

from healthee.core.tenancy import SENTINEL_TZ, SENTINEL_USER_ID
from healthee.jobs import coach_llm, coach_weekly
from healthee.jobs.coach_sizing import decide


def _script(monkeypatch: pytest.MonkeyPatch, *results) -> list[str]:
    """``grounded_ask`` replaced by a script; returns the questions it was asked."""
    asked: list[str] = []
    queue = list(results)

    def fake(question: str, *_a, **_k):
        asked.append(question)
        return queue.pop(0) if len(queue) > 1 else queue[0]

    monkeypatch.setattr(coach_llm, "grounded_ask", fake)
    return asked


def _ask(**kw):
    return coach_llm.propose("Q", SENTINEL_USER_ID, SENTINEL_TZ, weekly=True, **kw)


def test_an_oversized_target_is_retried_once_with_the_range_stated(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    allowed = decide(prev_job(20), weeks(True, False, True, False))  # repeat at 20
    asked = _script(monkeypatch, grounded(answer(job={"target": 40})), grounded(answer()))
    week = _ask(allowed=allowed)
    assert week is not None and week.job is not None and week.job.target == 20
    assert len(asked) == 2 and "rejected" in asked[1] and "between 20 and 20" in asked[1]


def test_two_bad_answers_yield_none_so_the_caller_can_fall_back(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    allowed = decide(prev_job(20), weeks(True, False, True, False))
    asked = _script(monkeypatch, grounded(answer(job={"target": 40})))
    assert _ask(allowed=allowed) is None and len(asked) == 2  # never a third try


def test_a_refused_or_ungrounded_answer_is_not_retried(monkeypatch: pytest.MonkeyPatch) -> None:
    asked = _script(monkeypatch, grounded(None))
    assert _ask() is None and len(asked) == 1


def test_a_weekly_answer_without_a_job_is_rejected_and_a_daily_one_is_fine(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    daily = answer(review=None, pattern=None) | {"job": None}
    _script(monkeypatch, grounded(daily))
    assert _ask() is None
    _script(monkeypatch, grounded(daily))
    assert coach_llm.propose("Q", SENTINEL_USER_ID, SENTINEL_TZ, weekly=False) is not None


def test_the_shipped_grade_is_the_provable_one(monkeypatch: pytest.MonkeyPatch) -> None:
    _script(monkeypatch, grounded(answer(evidence_grade=2)))
    week = _ask()
    assert week is not None and week.evidence_grade == 2


def test_an_extra_check_can_reject_an_answer(monkeypatch: pytest.MonkeyPatch) -> None:
    asked = _script(monkeypatch, grounded(answer()))
    got = coach_llm.propose(
        "Q", SENTINEL_USER_ID, SENTINEL_TZ, weekly=True, extra_check=lambda _w: "say why"
    )
    assert got is None and len(asked) == 2


# ── generate_week's once-per-week logic over a fake store ─────────────────────


class _FakeStore:
    def __init__(self) -> None:
        self.review: dict | None = None
        self.claims: list[str] = []
        self.builds = 0
        self.claimable = True


@pytest.fixture
def store(monkeypatch: pytest.MonkeyPatch) -> _FakeStore:
    fake = _FakeStore()

    @contextmanager
    def tx(_user: UUID) -> Iterator[object]:
        yield object()

    def build(*_a, **_k) -> dict:
        fake.builds += 1
        fake.review = {"week": "w", "generated_at": "t"}
        return fake.review

    monkeypatch.setattr(coach_weekly, "tenant_transaction", tx)
    monkeypatch.setattr(coach_weekly, "read_stored", lambda *_a: fake.review)
    monkeypatch.setattr(coach_weekly.kv, "claim", lambda *_a, **_k: fake.claimable)
    monkeypatch.setattr(coach_weekly.kv, "release", lambda _c, _u, key: fake.claims.append(key))
    monkeypatch.setattr(coach_weekly, "_build", build)
    return fake


def test_generation_happens_once_then_the_stored_review_is_served(store: _FakeStore) -> None:
    first = coach_weekly.generate_week(SENTINEL_USER_ID, SENTINEL_TZ, TODAY)
    second = coach_weekly.generate_week(SENTINEL_USER_ID, SENTINEL_TZ, TODAY)
    assert first[1] is False and second == (store.review, True) and store.builds == 1
    assert store.claims  # the claim was released after generating


def test_a_loser_of_the_claim_waits_for_the_winners_review(
    store: _FakeStore, monkeypatch: pytest.MonkeyPatch
) -> None:
    store.claimable = False
    polls = iter([None, None, {"week": "w", "generated_at": "t"}])
    monkeypatch.setattr(coach_weekly, "read_stored", lambda *_a: next(polls))
    monkeypatch.setattr(coach_weekly, "_POLL_SECONDS", 0)
    got, cached = coach_weekly.generate_week(SENTINEL_USER_ID, SENTINEL_TZ, date(2026, 10, 14))
    assert got is not None
    assert cached is True and got["week"] == "w" and store.builds == 0


def test_a_failed_build_releases_the_claim_and_raises(
    store: _FakeStore, monkeypatch: pytest.MonkeyPatch
) -> None:
    def boom(*_a, **_k):
        raise RuntimeError("model down")

    monkeypatch.setattr(coach_weekly, "_build", boom)
    with pytest.raises(RuntimeError, match="model down"):
        coach_weekly.generate_week(SENTINEL_USER_ID, SENTINEL_TZ, TODAY)
    assert store.claims
