"""`PATCH /api/challenges/{id}/slot` — reword WHEN the owner will do a challenge.

The slot is a label. These tests pin that it changes that one column and nothing a
rule reads: the stored row differs only in ``slot_text``, and the live evaluation and
the day verdicts are identical before and after.
"""

from __future__ import annotations

from typing import Any

import pytest
from tests.contracts.seed_owner_b import OWNER_B, seed_owner_b

from healthee.core.db import tenant_transaction

pytestmark = pytest.mark.integration


def _feed(client: Any, headers: dict) -> dict:
    resp = client.get("/api/challenges", headers=headers)
    assert resp.status_code == 200, resp.text[:200]
    return resp.json()


def _active(client: Any, headers: dict) -> dict:
    return next(c for c in _feed(client, headers)["active"] if c["program_id"] is None)


def _patch(client: Any, headers: dict, challenge_id: int, slot: Any) -> Any:
    return client.patch(
        f"/api/challenges/{challenge_id}/slot", json={"slot": slot}, headers=headers
    )


def test_the_slot_changes_and_nothing_else_does(seeded_client: tuple) -> None:
    client, headers = seeded_client
    before = _active(client, headers)
    ledger_before = client.get("/api/coach/ledger", params={"window": "month"}, headers=headers)
    resp = _patch(client, headers, before["id"], "  After lunch  ")
    assert resp.status_code == 200
    assert resp.json()["ok"] is True
    returned = resp.json()["challenge"]
    assert returned["slot_text"] == "After lunch"
    after = _active(client, headers)
    # Row, live progress (the evaluation) and the day verdicts: only slot_text moved.
    assert {**after, "slot_text": None} == {**before, "slot_text": None}
    assert after["slot_text"] == "After lunch"
    assert {k: v for k, v in returned.items() if k != "slot_text"}.items() <= after.items()
    ledger_after = client.get("/api/coach/ledger", params={"window": "month"}, headers=headers)
    assert ledger_after.json() == ledger_before.json()


def test_a_suggested_challenge_can_be_reworded(seeded_client: tuple) -> None:
    client, headers = seeded_client
    suggestion = _feed(client, headers)["suggested"][0]
    resp = _patch(client, headers, suggestion["id"], "Before work")
    assert resp.status_code == 200
    assert resp.json()["challenge"]["status"] == "suggested"
    assert resp.json()["challenge"]["slot_text"] == "Before work"


def test_a_finished_challenge_is_refused_and_unchanged(seeded_client: tuple) -> None:
    client, headers = seeded_client
    finished = next(c for c in _feed(client, headers)["recent"] if c["status"] == "completed")
    resp = _patch(client, headers, finished["id"], "Too late")
    assert resp.status_code == 409
    assert resp.json()["detail"]["reason"] == "not_active"
    again = next(c for c in _feed(client, headers)["recent"] if c["id"] == finished["id"])
    assert again == finished


def test_an_abandoned_challenge_is_refused(seeded_client: tuple) -> None:
    client, headers = seeded_client
    active = _active(client, headers)
    assert (
        client.post(f"/api/challenges/{active['id']}/abandon", headers=headers).status_code == 200
    )
    resp = _patch(client, headers, active["id"], "Nope")
    assert resp.status_code == 409
    assert resp.json()["detail"]["reason"] == "not_active"


def test_unknown_and_foreign_ids_are_404(seeded_client: tuple) -> None:
    client, headers = seeded_client
    seed_owner_b()
    with tenant_transaction(OWNER_B) as cur:
        cur.execute(
            "INSERT INTO challenge (user_id, title, why, category, metric, comparator, "
            "  target_value, cadence, window_days, status, slot_text) "
            "VALUES (%s,'B only','w','activity','steps_total','>=',9000,'daily',7,"
            "  'suggested','B slot') RETURNING id",
            (OWNER_B,),
        )
        row = cur.fetchone()
        assert row is not None
        b_id = int(row[0])
    for missing in (987654, b_id):
        resp = _patch(client, headers, missing, "Mine now")
        assert resp.status_code == 404
        assert resp.json()["detail"]["reason"] == "not_found"
    with tenant_transaction(OWNER_B) as cur:
        cur.execute(
            "SELECT slot_text FROM challenge WHERE user_id = %s AND id = %s", (OWNER_B, b_id)
        )
        stored = cur.fetchone()
        assert stored is not None and stored[0] == "B slot"


@pytest.mark.parametrize(
    "slot",
    ["", "   ", "x" * 81, "bad\nline", "tab\there", "nul\x00", "bell\x07", 5, None],
)
def test_a_bad_slot_is_422(seeded_client: tuple, slot: Any) -> None:
    client, headers = seeded_client
    active = _active(client, headers)
    assert _patch(client, headers, active["id"], slot).status_code == 422
    assert _active(client, headers) == active


def test_the_boundary_lengths_are_accepted(seeded_client: tuple) -> None:
    client, headers = seeded_client
    active = _active(client, headers)
    assert _patch(client, headers, active["id"], "x").status_code == 200
    assert _patch(client, headers, active["id"], "y" * 80).status_code == 200


def test_it_requires_authentication(seeded_client: tuple) -> None:
    client, _ = seeded_client
    resp = client.patch(
        "/api/challenges/1/slot", json={"slot": "x"}, headers={"Authorization": "Bearer nope"}
    )
    assert resp.status_code == 401
