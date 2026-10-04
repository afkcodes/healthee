"""Ingest attribution over HTTP — who a push is written under (6.4b, §7).

Ingest is the one place a wrong owner is not a leak but *corruption*: a push
attributed to the wrong tenant writes another person's heart rate into your health
record, silently and permanently. So attribution is proven at the HTTP boundary, on
the real rows, with the real dependency — never inferred.

The matrix:
  * owner B's device token  → rows owned by B (not the sentinel, not A)
  * the legacy shared token → rows owned by the sentinel (TRANSITIONAL, §4)
  * an unknown device token → 401, and nothing written at all

Auto-skips without a reachable TimescaleDB (same policy as the other DB tests).
"""

from __future__ import annotations

from collections.abc import Iterator
from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

import jwt
import psycopg
import pytest
from fastapi.testclient import TestClient
from httpx2 import Response

from healthee.api.app import create_app
from healthee.core import db as db_module
from healthee.core.config import get_settings
from healthee.core.db import admin_connection, transaction
from healthee.core.device_token import mint_device_token
from healthee.core.tenancy import SENTINEL_USER_ID
from healthee.db import migrate

pytestmark = [
    pytest.mark.integration,
    # This module provisions owners — explicitly, JIT on the first authenticated
    # request, or via `seed_owner_b` — and removed none of them. `--user`-less ops
    # tooling walks every active owner it finds, so the strays are not free (#119).
    pytest.mark.usefixtures("owner_sweep"),
]

_SECRET = "ingest-attribution-supabase-secret-0123456789abcdef"
_AUD = "authenticated"

# A second real owner for this file (the leakage suite's OWNER_B is a read fixture;
# this one exists to receive writes, so it is created and torn down here).
OWNER_B = UUID("cccccccc-cccc-cccc-cccc-cccccccccccc")
OWNER_B_TZ = "America/Chicago"

# One unmistakable sample: an HR no seeded owner has, at a fixed instant, so the
# `user_id` on the stored row is the only thing under test.
_HR_VALUE = 123.0


def _push_body(ts: datetime) -> dict:
    return {"samples": [{"metric": "hr", "ts": int(ts.timestamp() * 1000), "value": _HR_VALUE}]}


def _db_reachable() -> bool:
    try:
        with psycopg.connect(get_settings().admin_db_url, connect_timeout=3) as conn:
            conn.execute("SELECT 1")
    except Exception:
        return False
    return True


@pytest.fixture
def client(monkeypatch: pytest.MonkeyPatch) -> Iterator[TestClient]:
    """A migrated DB with owner B present and Supabase auth configured."""
    monkeypatch.setenv("SUPABASE_JWT_SECRET", _SECRET)
    monkeypatch.setenv("SUPABASE_JWT_AUD", _AUD)
    get_settings.cache_clear()
    db_module.close_pool()
    if not _db_reachable():
        pytest.skip("no reachable TimescaleDB — attribution test skipped")
    migrate.apply_migrations()
    # The marker-row cleanup spans owners (that is the whole subject here), so it goes
    # to the ADMIN; `app_user` is identity and has no RLS policy either way.
    with admin_connection() as conn, conn.cursor() as cur:
        cur.execute("DELETE FROM sample WHERE value = %s", (_HR_VALUE,))
    with transaction() as cur:
        cur.execute(
            "INSERT INTO app_user (id, email, timezone) VALUES (%s, %s, %s) "
            "ON CONFLICT (id) DO UPDATE SET timezone = EXCLUDED.timezone",
            (OWNER_B, "ingest-b@example.test", OWNER_B_TZ),
        )
    yield TestClient(create_app())
    with admin_connection() as conn, conn.cursor() as cur:
        cur.execute("DELETE FROM sample WHERE value = %s", (_HR_VALUE,))
        cur.execute("DELETE FROM device_token WHERE user_id = %s", (OWNER_B,))
    db_module.close_pool()
    get_settings.cache_clear()


def _owners_of_the_pushed_sample(ts: datetime) -> list[UUID]:
    """WHICH owner the pushed row landed under — asked of the ADMIN, across owners.

    The question this whole file exists to answer is "was it attributed correctly?",
    and an RLS-scoped connection can only ever answer "yes" for the owner it is scoped
    to. The independent observer is the point (6.5b-2).
    """
    with admin_connection() as conn, conn.cursor() as cur:
        cur.execute(
            "SELECT user_id FROM sample WHERE metric = 'hr' AND value = %s AND ts = %s",
            (_HR_VALUE, ts),
        )
        return [row[0] for row in cur.fetchall()]


def _post(client: TestClient, token: str, ts: datetime) -> Response:
    return client.post(
        "/ingest/helio", json=_push_body(ts), headers={"Authorization": f"Bearer {token}"}
    )


def test_a_device_token_push_is_written_under_that_tokens_owner(client: TestClient) -> None:
    ts = datetime.now(tz=UTC).replace(microsecond=0) - timedelta(hours=3)
    resp = _post(client, mint_device_token(OWNER_B, label="b's strap")[0], ts)
    assert resp.status_code == 200

    owners = _owners_of_the_pushed_sample(ts)
    assert owners == [OWNER_B], "the push was not attributed to the device token's owner"
    assert SENTINEL_USER_ID not in owners  # explicitly NOT the transitional default


def test_the_removed_shared_token_writes_NOTHING_now(client: TestClient) -> None:  # noqa: N802
    """The transition, asserted as an absence — and on the path where it matters most.

    A shared bearer used to be written under the sentinel. Ingest is the write side,
    so the wrong answer here is not a leaked read: it is health data appearing in
    somebody's history that they did not measure. It is a 401 and it stores nothing.
    """
    ts = datetime.now(tz=UTC).replace(microsecond=0) - timedelta(hours=4)
    assert _post(client, "ingest-attribution-legacy-token", ts).status_code == 401
    assert _owners_of_the_pushed_sample(ts) == []


def test_two_owners_pushes_at_the_same_instant_stay_separate(client: TestClient) -> None:
    """The corruption case: same metric, same instant, two owners — two rows, not one.

    0004 folded `user_id` into the sample key, so B's push cannot overwrite the
    sentinel's reading of the same instant. Both owners keep their own number.
    """
    ts = datetime.now(tz=UTC).replace(microsecond=0) - timedelta(hours=5)
    sentinel_token = mint_device_token(SENTINEL_USER_ID, label="the sentinel's strap")[0]
    assert _post(client, sentinel_token, ts).status_code == 200
    assert _post(client, mint_device_token(OWNER_B, label="b's strap")[0], ts).status_code == 200
    assert sorted(str(o) for o in _owners_of_the_pushed_sample(ts)) == sorted(
        [str(SENTINEL_USER_ID), str(OWNER_B)]
    )


def test_an_unknown_device_token_is_401_and_writes_nothing(client: TestClient) -> None:
    ts = datetime.now(tz=UTC).replace(microsecond=0) - timedelta(hours=6)
    resp = _post(client, "this-token-was-never-minted", ts)
    assert resp.status_code == 401
    assert _owners_of_the_pushed_sample(ts) == [], "a rejected push still wrote rows"


def test_a_supabase_jwt_is_not_an_ingest_credential(client: TestClient) -> None:
    """`/ingest/*` takes device tokens only (§4.3) — an access JWT is just unknown.

    Access tokens are short-lived and unusable for background BLE sync, so ingest
    deliberately has no JWT branch; presenting one must be a 401, never a fall-through
    to the sentinel.
    """
    ts = datetime.now(tz=UTC).replace(microsecond=0) - timedelta(hours=7)
    token = jwt.encode(
        {"sub": str(uuid4()), "aud": _AUD, "exp": datetime.now(tz=UTC) + timedelta(hours=1)},
        _SECRET,
        algorithm="HS256",
    )
    assert _post(client, token, ts).status_code == 401
    assert _owners_of_the_pushed_sample(ts) == []
