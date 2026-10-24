"""GET /api/coach/ledger without a database: auth, window validation, wire shape.

The DB is stubbed at the router's two seams (``tenant_transaction`` and
``record.build_ledger``) so this always runs; ``test_record_db`` and the contract bed
cover the real reads.
"""

from __future__ import annotations

from collections.abc import Iterator
from contextlib import contextmanager
from datetime import date
from uuid import UUID

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from healthee.api.routers import coach_ledger
from healthee.challenges.day_verdicts import Verdict
from healthee.challenges.record import assemble
from healthee.challenges.record_days import LedgerEntry
from healthee.core.request_auth import request_user
from healthee.core.supabase_auth import RequestUser

_USER = RequestUser(id=UUID("11111111-1111-1111-1111-111111111111"), timezone="Asia/Kolkata")


@pytest.fixture
def client(monkeypatch: pytest.MonkeyPatch) -> Iterator[tuple[TestClient, list]]:
    calls: list = []

    @contextmanager
    def _tx(user_id: UUID) -> Iterator[object]:
        calls.append(("tx", user_id))
        yield object()

    def _build(cur: object, user_id: UUID, tz: str, window: str) -> dict:
        calls.append(("build", user_id, tz, window))
        entry = LedgerEntry(
            date(2026, 10, 8), "Full sleep window tonight", Verdict.DONE, 574.0, "min", "9h34",
            "challenge", 7,
        )  # fmt: skip
        return assemble(window, date(2026, 9, 20), date(2026, 10, 18), [entry], {}, "a pattern")

    monkeypatch.setattr(coach_ledger, "tenant_transaction", _tx)
    monkeypatch.setattr(coach_ledger.record, "build_ledger", _build)
    app = FastAPI()
    app.include_router(coach_ledger.router)
    app.dependency_overrides[request_user] = lambda: _USER
    yield TestClient(app), calls


def test_the_wire_shape_and_aliases(client: tuple[TestClient, list]) -> None:
    http, calls = client
    resp = http.get("/api/coach/ledger", params={"window": "month"})
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert set(body) == {
        "window", "from", "to", "ideas_given", "yeses", "totals", "done_rate", "weeks", "pattern",
    }  # fmt: skip
    assert body["from"] == "2026-09-20" and body["pattern"] == "a pattern"
    assert body["done_rate"] == {"done": 1, "provable": 1}
    week = next(w for w in body["weeks"] if w["entries"])
    assert set(week) == {"from", "to", "ideas_given", "yeses", "entries"}
    assert week["entries"][0] == {
        "date": "2026-10-08", "title": "Full sleep window tonight", "verdict": "done",
        "measured": {"value": 574.0, "unit": "min", "label": "9h34"},
        "source": "challenge", "ref_id": 7,
    }  # fmt: skip
    assert ("build", _USER.id, "Asia/Kolkata", "month") in calls  # the owner's own id and zone


def test_window_defaults_to_week(client: tuple[TestClient, list]) -> None:
    http, calls = client
    assert http.get("/api/coach/ledger").status_code == 200
    assert calls[-1][-1] == "week"


@pytest.mark.parametrize("window", ["year", "", "WEEK"])
def test_an_unknown_window_is_422(client: tuple[TestClient, list], window: str) -> None:
    assert client[0].get("/api/coach/ledger", params={"window": window}).status_code == 422


def test_it_needs_a_signed_in_owner_not_the_ai_gate() -> None:
    from healthee.api.app import create_app

    resp = TestClient(create_app()).get("/api/coach/ledger")
    assert resp.status_code == 401
