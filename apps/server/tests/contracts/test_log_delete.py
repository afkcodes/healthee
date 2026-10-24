"""`DELETE /api/log/{entry_id}` — the app's "tap a full glass to undo".

What it must do: remove exactly one of the CALLER's manual entries, answer 404 for an
id that does not exist and for one that belongs to someone else (indistinguishably),
and leave every other row alone. The feed is how the app learns the id, so that the
feed carries it is pinned here too.
"""

from __future__ import annotations

from typing import Any
from uuid import uuid4

import pytest
from tests.contracts.seed_owner_b import OWNER_B, seed_owner_b

from healthee.core.db import tenant_transaction

pytestmark = pytest.mark.integration


def _entries(client: Any, headers: dict) -> list[dict]:
    resp = client.get("/api/log/recent", params={"days": 7}, headers=headers)
    assert resp.status_code == 200, resp.text[:200]
    return resp.json()["entries"]


def _caffeine(client: Any, headers: dict) -> dict:
    found = [e for e in _entries(client, headers) if e["type"] == "caffeine"]
    assert len(found) == 1
    return found[0]


def test_the_feed_gives_every_stored_entry_an_id(seeded_client: tuple) -> None:
    client, headers = seeded_client
    entries = _entries(client, headers)
    stored = [e for e in entries if e["type"] != "weight"]
    assert stored and all(isinstance(e["id"], str) and e["id"] for e in stored)
    assert len({e["id"] for e in stored}) == len(stored)
    # The weigh-in lives in `weight_log`, keyed by time; there is nothing to delete by id.
    assert all("id" not in e for e in entries if e["type"] == "weight")


def test_deleting_removes_that_one_entry_and_nothing_else(seeded_client: tuple) -> None:
    client, headers = seeded_client
    before = _entries(client, headers)
    target = _caffeine(client, headers)
    resp = client.delete(f"/api/log/{target['id']}", headers=headers)
    assert resp.status_code == 200
    assert resp.json() == {"ok": True}
    after = _entries(client, headers)
    assert target["id"] not in {e.get("id") for e in after}
    assert after == [e for e in before if e.get("id") != target["id"]]


def test_deleting_twice_is_404(seeded_client: tuple) -> None:
    client, headers = seeded_client
    entry_id = _caffeine(client, headers)["id"]
    assert client.delete(f"/api/log/{entry_id}", headers=headers).status_code == 200
    assert client.delete(f"/api/log/{entry_id}", headers=headers).status_code == 404


def test_an_unknown_id_is_404(seeded_client: tuple) -> None:
    client, headers = seeded_client
    assert client.delete(f"/api/log/{uuid4()}", headers=headers).status_code == 404


def test_another_owners_entry_is_404_and_survives(seeded_client: tuple) -> None:
    client, headers = seeded_client
    seed_owner_b()
    with tenant_transaction(OWNER_B) as cur:
        cur.execute("SELECT id FROM manual_entry WHERE user_id = %s LIMIT 1", (OWNER_B,))
        row = cur.fetchone()
        assert row is not None
        b_id = row[0]
    resp = client.delete(f"/api/log/{b_id}", headers=headers)
    assert resp.status_code == 404
    assert resp.json() == client.delete(f"/api/log/{uuid4()}", headers=headers).json()
    with tenant_transaction(OWNER_B) as cur:
        cur.execute(
            "SELECT count(*) FROM manual_entry WHERE user_id = %s AND id = %s", (OWNER_B, b_id)
        )
        count = cur.fetchone()
        assert count is not None and count[0] == 1


def test_a_deleted_entry_no_longer_counts_in_the_derived_view(seeded_client: tuple) -> None:
    """The history markers read `manual_entry` too; an undone log must leave them."""
    client, headers = seeded_client
    entry_id = _caffeine(client, headers)["id"]
    before = client.get("/api/history/logs", headers=headers)
    assert before.status_code == 200
    assert client.delete(f"/api/log/{entry_id}", headers=headers).status_code == 200
    after = client.get("/api/history/logs", headers=headers)
    assert after.status_code == 200
    assert "caffeine" in before.text
    assert "caffeine" not in after.text


def test_it_requires_authentication(seeded_client: tuple) -> None:
    client, _ = seeded_client
    resp = client.delete(f"/api/log/{uuid4()}", headers={"Authorization": "Bearer nope"})
    assert resp.status_code == 401
