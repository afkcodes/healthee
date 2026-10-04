"""Cross-tenant leakage proof at the HTTP boundary (Phase 6.4b, MULTI_USER.md §10).

This is the proof 6.3c could not write. Until the 6.4b flip every router hardwired
the sentinel, so there was no second identity to authenticate AS and the guarantee
could only be asserted one layer down (`test_service_leakage.py`, still green and
still the service-layer proof). Now the routers take the owner from the request, so
the question the product actually rests on — "can a request signed by B ever see A's
health data?" — is answerable over real HTTP.

Two owners are seeded at the SAME natural keys (`seed_all` = A = the sentinel,
`seed_owner_b` = B), so only `user_id` separates their rows and B's values are
impossible for A (22k steps, 88 rhr, 12 recovery, name "OwnerB"). Each owner
authenticates with their own self-signed Supabase-shaped JWT.

**Both owners must see their own** — every assertion here is two-sided by design.
A one-sided "A sees A" passes by luck against an unscoped `SELECT` that happens to
return the newest row (the trap that silently hollowed out four 6.3c tests), so each
test asserts A gets A's number AND B gets B's, over the same endpoint and the same
seeded day.

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
from tests.contracts.seed import seed_all
from tests.contracts.seed_owner_b import B_NAME, B_RECOVERY, B_RHR, B_STEPS, OWNER_B

from healthee.api.app import create_app
from healthee.core import db as db_module
from healthee.core.config import get_settings
from healthee.core.request_auth import request_user
from healthee.core.supabase_auth import RequestUser
from healthee.core.tenancy import SENTINEL_TZ, SENTINEL_USER_ID

pytestmark = [
    pytest.mark.integration,
    # This module provisions owners — explicitly, JIT on the first authenticated
    # request, or via `seed_owner_b` — and removed none of them. `--user`-less ops
    # tooling walks every active owner it finds, so the strays are not free (#119).
    pytest.mark.usefixtures("owner_sweep"),
]

# >= 32 bytes: PyJWT warns (InsecureKeyLengthWarning) on shorter HMAC keys.
_SECRET = "http-isolation-supabase-secret-0123456789abcdef"
_AUD = "authenticated"
_LEGACY_TOKEN = "http-isolation-legacy-token"

# Owner A is the sentinel — `seed_all` writes every row under it, so A is reachable
# by a real JWT whose `sub` is the sentinel UUID (no data is moved; that re-key is
# 6.4c). A's seeded values, the counterparts to B's impossible ones.
A_STEPS = 8200.0
A_RHR = 55.0
A_RECOVERY = 72
A_NAME = "Test"


def _token(sub: UUID) -> str:
    """A self-signed Supabase-shaped access JWT for `sub` (never a live Supabase)."""
    return jwt.encode(
        {
            "sub": str(sub),
            "aud": _AUD,
            "exp": datetime.now(tz=UTC) + timedelta(hours=1),
        },
        _SECRET,
        algorithm="HS256",
    )


def _auth(sub: UUID) -> dict[str, str]:
    return {"Authorization": f"Bearer {_token(sub)}"}


def _db_reachable() -> bool:
    try:
        with psycopg.connect(get_settings().admin_db_url, connect_timeout=3) as conn:
            conn.execute("SELECT 1")
    except Exception:
        return False
    return True


@pytest.fixture
def client(monkeypatch: pytest.MonkeyPatch) -> Iterator[TestClient]:
    """Both owners seeded, Supabase verification configured, one real app."""
    monkeypatch.setenv("SUPABASE_JWT_SECRET", _SECRET)
    monkeypatch.setenv("SUPABASE_JWT_AUD", _AUD)
    monkeypatch.delenv("SUPABASE_PROJECT_REF", raising=False)
    # Isolation is what this file proves, not the signup gate (`tests/test_signup_gate.py`):
    # `test_a_brand_new_user_sees_no_one_elses_data` needs a brand-new owner to actually
    # get provisioned, so signups are open for its fixture.
    monkeypatch.setenv("SIGNUPS_OPEN", "true")
    # Signups open ⇒ NO legacy shared token: `core.config` refuses that pair, because
    # one never-expiring secret that authenticates as a real tenant must not exist in a
    # deployment strangers can join. Cleared here rather than inherited from the shell,
    # which is what a hosted deployment with open signups actually looks like.
    monkeypatch.setenv("REALTIME_INGEST_TOKEN", "")
    get_settings.cache_clear()
    db_module.close_pool()
    if not _db_reachable():
        pytest.skip("no reachable TimescaleDB — isolation test skipped")
    seed_all()
    from tests.contracts.seed_owner_b import seed_owner_b

    seed_owner_b()
    yield TestClient(create_app())
    db_module.close_pool()
    get_settings.cache_clear()


def _json(client: TestClient, path: str, sub: UUID, **params: str | int) -> dict:
    resp = client.get(path, params=params or None, headers=_auth(sub))
    assert resp.status_code == 200, f"{path} as {sub}: {resp.status_code} {resp.text[:200]}"
    return resp.json()


# --- both owners see their own, over the main read surface -------------------


def test_history_returns_each_owners_own_series(client: TestClient) -> None:
    a = _json(client, "/api/history", SENTINEL_USER_ID, metric="steps_total", days=30)
    b = _json(client, "/api/history", OWNER_B, metric="steps_total", days=30)
    a_values = {point["value"] for point in a["series"]}
    b_values = {point["value"] for point in b["series"]}
    assert a_values == {A_STEPS}, "A's history leaked another owner's steps"
    assert b_values == {B_STEPS}, "B's history leaked another owner's steps"
    assert not a_values & b_values  # the two owners share not one value


def test_history_rhr_is_per_owner(client: TestClient) -> None:
    a = _json(client, "/api/history", SENTINEL_USER_ID, metric="rhr_daily", days=30)
    b = _json(client, "/api/history", OWNER_B, metric="rhr_daily", days=30)
    assert {p["value"] for p in a["series"]} == {A_RHR}
    assert {p["value"] for p in b["series"]} == {B_RHR}


def test_profile_returns_each_owners_own_row(client: TestClient) -> None:
    assert _json(client, "/api/profile", SENTINEL_USER_ID)["name"] == A_NAME
    assert _json(client, "/api/profile", OWNER_B)["name"] == B_NAME


def test_today_recovery_is_per_owner(client: TestClient) -> None:
    a = _json(client, "/api/today", SENTINEL_USER_ID)
    b = _json(client, "/api/today", OWNER_B)
    assert a["recovery_score"]["recovery"] == A_RECOVERY
    assert b["recovery_score"]["recovery"] == B_RECOVERY


def test_today_metrics_carry_each_owners_own_numbers(client: TestClient) -> None:
    def steps_of(payload: dict) -> float | None:
        return next((m["value"] for m in payload["metrics"] if m["metric"] == "steps_total"), None)

    assert steps_of(_json(client, "/api/today", SENTINEL_USER_ID)) == A_STEPS
    assert steps_of(_json(client, "/api/today", OWNER_B)) == B_STEPS


def test_activity_steps_are_per_owner(client: TestClient) -> None:
    assert _json(client, "/api/activity", SENTINEL_USER_ID)["steps"]["value"] == A_STEPS
    assert _json(client, "/api/activity", OWNER_B)["steps"]["value"] == B_STEPS


def test_manual_logs_are_per_owner(client: TestClient) -> None:
    a = _json(client, "/api/log/recent", SENTINEL_USER_ID, days=7)
    b = _json(client, "/api/log/recent", OWNER_B, days=7)
    a_caffeine = {e["amount"] for e in a["entries"] if e["type"] == "caffeine"}
    b_caffeine = {e["amount"] for e in b["entries"] if e["type"] == "caffeine"}
    assert 999.0 not in a_caffeine, "A's log surfaced B's 999 mg entry"
    assert b_caffeine == {999.0}, "B's log did not return B's own entry"


def test_sleep_nights_carry_each_owners_own_physiology(client: TestClient) -> None:
    """A's and B's nights sit on the same dates — only the owner filter separates them."""
    a = _json(client, "/api/sleep", SENTINEL_USER_ID, days=30)
    b = _json(client, "/api/sleep", OWNER_B, days=30)
    assert a["nights"] and b["nights"], "a sleep fixture did not seed"
    # Per-night rhr/hrv are physiologically impossible for the other owner.
    assert {n["rhr"] for n in a["nights"]} == {A_RHR}
    assert {n["rhr"] for n in b["nights"]} == {B_RHR}
    assert {n["hrv_sleep_avg"] for n in a["nights"]} == {45.0}
    assert {n["hrv_sleep_avg"] for n in b["nights"]} == {12.0}


def test_gps_list_is_per_owner(client: TestClient) -> None:
    a_tracks = _json(client, "/api/workout/gps", SENTINEL_USER_ID)["tracks"]
    b_tracks = _json(client, "/api/workout/gps", OWNER_B)["tracks"]
    assert a_tracks and b_tracks, "a GPS fixture did not seed"
    # A's seeded route is 4.2 km; B's is an impossible 100 km.
    assert {t["distance_km"] for t in a_tracks} == {4.2}
    assert {t["distance_km"] for t in b_tracks} == {100.0}
    assert not {t["track_id"] for t in a_tracks} & {t["track_id"] for t in b_tracks}


def test_gps_track_of_another_owner_is_404_not_403(client: TestClient) -> None:
    """A's own track id resolves for A and is invisible to B — a 404, never a 403.

    404 is the correct answer, not a nicety: the owner filter lives inside
    ``gps_detail``, so another tenant's id simply does not resolve. B is never told
    the track exists, which is what stops the endpoint being an id oracle (§10).
    """
    a_tracks = _json(client, "/api/workout/gps", SENTINEL_USER_ID)["tracks"]
    track_id = a_tracks[0]["track_id"]
    mine = client.get(f"/api/workout/gps/{track_id}", headers=_auth(SENTINEL_USER_ID))
    assert mine.status_code == 200
    assert mine.json()["track_id"] == track_id
    theirs = client.get(f"/api/workout/gps/{track_id}", headers=_auth(OWNER_B))
    assert theirs.status_code == 404
    assert theirs.json()["detail"] == "track not found"  # the same body a real miss gives


def test_a_brand_new_user_sees_no_one_elses_data(client: TestClient) -> None:
    """JIT-provisioning must yield an EMPTY tenant, not a view of the seeded owner."""
    newcomer = uuid4()
    series = _json(client, "/api/history", newcomer, metric="steps_total", days=30)["series"]
    assert series == [], "a brand-new user was handed another owner's history"
    assert _json(client, "/api/profile", newcomer).get("name") in (None, "")


# --- the mutation test: prove the assertions above can actually fail ---------


def test_routers_act_on_the_injected_owner_not_a_hardwired_one(client: TestClient) -> None:
    """The mutation proof: force the dependency to resolve to B, authenticate as A.

    If a router still hardwired `SENTINEL_USER_ID` (the 6.3 state) — or ignored the
    injected user in any other way — this request would return A's 8200 steps and the
    assertion below would fail. It returning B's impossible 22000 is what proves the
    isolation tests above are load-bearing rather than passing by luck: the response
    tracks the owner the router was handed, and nothing else.
    """
    app = create_app()
    app.dependency_overrides[request_user] = lambda: RequestUser(id=OWNER_B, timezone=SENTINEL_TZ)
    with TestClient(app) as mutated:
        resp = mutated.get(
            "/api/history",
            params={"metric": "steps_total", "days": 30},
            headers=_auth(SENTINEL_USER_ID),  # A's credential — deliberately ignored
        )
    assert resp.status_code == 200
    assert {p["value"] for p in resp.json()["series"]} == {B_STEPS}
