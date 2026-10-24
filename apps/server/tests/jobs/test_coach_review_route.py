"""POST /api/coach/review without a database: the cache-and-refund contract and the wire shape."""

from __future__ import annotations

import json
from collections.abc import Iterator
from pathlib import Path
from typing import get_args
from uuid import UUID

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from tests.contracts.shape import assert_conforms

from healthee.api import gate
from healthee.api.routers import coach_review
from healthee.core.supabase_auth import RequestUser
from healthee.jobs.coach_weekly import ReviewBusyError

_USER = RequestUser(id=UUID("11111111-1111-1111-1111-111111111111"), timezone="Asia/Kolkata")
_SNAPSHOT = Path(__file__).resolve().parents[4] / "packages/contracts/snapshots/coach_review.json"

_STORED = {
    "week": "2026-W43",
    "week_from": "2026-10-19",
    "week_to": "2026-10-25",
    "review": "Straight talk. Brisk minutes fell to 66.",
    "pattern": "You say yes on Mondays and miss by Thursday.",
    "job": {
        "action": "Walk briskly for 20 minutes",
        "metric": "mvpa_min",
        "target": 20.0,
        "unit": "min",
        "days_required": 4,
        "slot": "after 10 pm",
        "floor": "10 minutes counts as half",
        "counts_when": "when the strap logs 20 minutes",
        "challenge_id": 12,
    },  # fmt: skip
    "today": "Start tonight after 10.",
    "rationale": "Regular brisk walking supports fitness [note].",
    "evidence_grade": 3,
    "research_note_ids": ["note"],
    "generated_at": "2026-10-18T09:30:00+00:00",
}


@pytest.fixture
def http(monkeypatch: pytest.MonkeyPatch) -> Iterator[tuple[TestClient, dict]]:
    state: dict = {"refunds": 0, "result": (dict(_STORED), False), "calls": 0}

    def generate(*_a, **_k):
        state["calls"] += 1
        if isinstance(state["result"], Exception):
            raise state["result"]
        return state["result"]

    monkeypatch.setattr(coach_review, "generate_week", generate)
    monkeypatch.setattr(
        coach_review.gate, "refund_ai_use", lambda *_a: state.update(refunds=state["refunds"] + 1)
    )
    monkeypatch.setattr(coach_review.shape, "read_today_line", lambda *_a: "Today: 20 minutes.")
    app = FastAPI()
    app.include_router(coach_review.router)
    guard = get_args(gate.CoachUser)[1].dependency  # the route's own AIGate instance
    app.dependency_overrides[guard] = lambda: _USER
    yield TestClient(app), state


def test_the_first_call_generates_and_is_charged(http: tuple[TestClient, dict]) -> None:
    client, state = http
    body = client.post("/api/coach/review").json()
    assert body["cached"] is False and state["refunds"] == 0
    assert body["week"] == "2026-W43" and body["job"]["challenge_id"] == 12
    assert body["today_line"] == "Today: 20 minutes."


def test_a_cached_read_refunds_the_allowance(http: tuple[TestClient, dict]) -> None:
    client, state = http
    state["result"] = (dict(_STORED), True)
    body = client.post("/api/coach/review").json()
    assert body["cached"] is True and state["refunds"] == 1


def test_nothing_to_write_refunds_and_says_so_with_no_job(http: tuple[TestClient, dict]) -> None:
    client, state = http
    state["result"] = (None, False)
    body = client.post("/api/coach/review").json()
    assert body["job"] is None and "not enough readings" in body["review"]
    assert state["refunds"] == 1 and body["cached"] is False


def test_a_busy_week_is_503_and_refunds(http: tuple[TestClient, dict]) -> None:
    client, state = http
    state["result"] = ReviewBusyError("still being written")
    resp = client.post("/api/coach/review")
    assert resp.status_code == 503 and resp.headers["Retry-After"] == "5"
    assert state["refunds"] == 1


def test_a_failure_refunds_and_propagates(http: tuple[TestClient, dict]) -> None:
    client, state = http
    state["result"] = RuntimeError("model down")
    with pytest.raises(RuntimeError, match="model down"):
        client.post("/api/coach/review")
    assert state["refunds"] == 1


def test_the_response_conforms_to_the_committed_snapshot(http: tuple[TestClient, dict]) -> None:
    client, _ = http
    assert_conforms(
        client.post("/api/coach/review").json(), json.loads(_SNAPSHOT.read_text()), "coach_review"
    )


def test_it_is_gated_like_the_coach() -> None:
    from healthee.api.app import create_app

    assert TestClient(create_app()).post("/api/coach/review").status_code == 401
    assert get_args(gate.CoachUser)[1].dependency.feature == gate.COACH
