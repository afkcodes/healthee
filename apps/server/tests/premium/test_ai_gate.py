"""The paywall at the HTTP edge — 402 for a free owner, over real requests (6.6a).

``MULTI_USER.md`` §12.7's invariant: *no AI response bytes ever leave the server for a
request whose owner is not premium.* Two halves are proved here and the third
(``jobs``) in ``test_chain_spend.py``:

* **every AI route refuses a free owner** — asserted by CALLING it, not by inspecting a
  decorator, because §12.7's first loophole is "direct API calls bypassing the locked
  UI" and a direct call is exactly what this makes. Since 2026-08-02 that is every AI
  route on the FIRST call: the free tier has no metered taste left (``test_premium_cap.py``
  owns the tables and the paid cap);
* **no AI route can be added without a gate** — ``test_every_mounted_route_is_gated_or_
  allowlisted`` walks the app's real dependency tree, so a new premium endpoint that
  takes ``CurrentUser`` fails the build rather than shipping open.

The second is the one that will still be working in a year. A hand-written list of
endpoints to probe can only cover what its author remembered; the route walk is driven
off the application object itself, the same way ``test_rls.py`` drives its completeness
check off the database catalog.
"""

from __future__ import annotations

from collections.abc import Callable, Sequence

import pytest
from fastapi.dependencies.models import Dependant
from fastapi.routing import APIRoute
from fastapi.testclient import TestClient
from tests.premium.conftest import AUTH

from healthee.api import gate
from healthee.api.app import create_app
from healthee.api.gate import AIGate

pytestmark = pytest.mark.integration

# (method, path, params, body, expected feature) for every premium route. Since 2026-08-02
# that is ALL of them: `FREE_ALLOWANCE` is zero on every feature, so a free owner is
# refused on the FIRST call and every one after. There is no metered free route left —
# `/api/coach` and `/api/today/action` were the two, and they are in this table now.
#
# The ids are deliberately absurd on the write endpoints: the gate must refuse BEFORE
# the handler looks anything up, so a 404 here would mean the gate ran too late.
#
# The FEATURE is asserted, not just "some feature": it is what the app renders a locked
# card from, so `/api/notable` reporting `insight` would send someone to the wrong
# upsell. Pinning it also makes a swapped gated identity a test failure — a mutation
# that changed `NotableUser` to `InsightUser` was survivable until this column existed,
# because both refuse and only the body differs.
AI_ROUTES: list[tuple[str, str, dict | None, dict | None, str]] = [
    ("GET", "/api/recommendations", None, None, gate.DAILY_ACTION),
    ("POST", "/api/recommendations/999999/adopt", None, None, gate.DAILY_ACTION),
    ("POST", "/api/recommendations/999999/dismiss", None, None, gate.DAILY_ACTION),
    ("POST", "/api/coach", None, {"messages": [{"role": "user", "content": "hi"}]}, gate.COACH),
    (
        "POST",
        "/api/coach/stream",
        None,
        {"messages": [{"role": "user", "content": "hi"}]},
        gate.COACH,
    ),
    ("POST", "/api/coach/review", None, None, gate.COACH),
    ("POST", "/api/today/action", None, None, gate.DAILY_ACTION),
    ("GET", "/api/sleep/insight", None, None, gate.INSIGHT),
    ("GET", "/api/activity/insight", None, None, gate.INSIGHT),
    ("GET", "/api/metric/insight", {"metric": "rhr_daily"}, None, gate.INSIGHT),
    (
        "GET",
        "/api/activity/workout/insight",
        {"start": "2026-01-01T06:00:00+00:00"},
        None,
        gate.INSIGHT,
    ),
    ("GET", "/api/notable", None, None, gate.NOTABLE),
    ("GET", "/api/challenges", None, None, gate.CHALLENGES),
    ("GET", "/api/challenges/outcomes", None, None, gate.CHALLENGES),
    ("POST", "/api/challenges/999999/adopt", None, None, gate.CHALLENGES),
    ("POST", "/api/challenges/999999/abandon", None, None, gate.CHALLENGES),
    ("POST", "/api/challenges/999999/adapt", None, None, gate.CHALLENGES),
    ("PATCH", "/api/challenges/999999/slot", None, {"slot": "After lunch"}, gate.CHALLENGES),
    ("GET", "/api/programs", None, None, gate.CHALLENGES),
    ("POST", "/api/programs/999999/adopt", None, None, gate.CHALLENGES),
    ("POST", "/api/programs/999999/abandon", None, None, gate.CHALLENGES),
    ("POST", "/api/challenges/generate", None, None, gate.CHALLENGES),
    ("POST", "/api/programs/generate", None, None, gate.CHALLENGES),
]

# Routes that are FREE by design, each with the reason it is free. Every mounted path
# must be here or carry a gate — that is the completeness check, and an entry added
# without a reason is an entry somebody should have argued for.
FREE_PATHS: dict[str, str] = {
    "/healthz": "liveness probe — unauthenticated by design",
    "/readyz": "dependency readiness — unauthenticated by design, and it carries no owner data",
    "/ingest/helio": "device push; the tracker is free (PRICING.md §1a)",
    "/api/today": "free metrics; its two AI FIELDS are omitted instead (api.gate)",
    "/api/sleep": "free tier — sleep numbers",
    "/api/sleep/health_score": "free tier — the deterministic 4-dim score",
    "/api/sleep/consistency": "free tier; its `tonight` AI field is omitted instead",
    "/api/activity": "free tier — activity numbers",
    "/api/activity/workout": "free tier — workout detail",
    "/api/history/logs": "free tier — owner-authored history markers",
    "/api/history": "free tier — full history is deliberately never paywalled",
    "/api/profile": "free tier — the owner's own demographics",
    "/api/account": "authenticated identity for durable local data ownership",
    "/api/log": "free tier — manual logging",
    "/api/log/recent": "free tier — manual logging",
    "/api/log/{entry_id}": "free tier — manual logging (undo one entry)",
    "/api/workout/gps": "free tier — GPS routes",
    "/api/workout/gps/{track_id}": "free tier — GPS routes",
    "/api/map": "free tier — the basemap's credit line and zoom range, not owner data",
    "/api/map/tiles/{z}/{x}/{y}": (
        "free tier — a proxied public map tile. It is context, never data or AI output, "
        "and paywalling it would leave a free owner's recorded track drawn on nothing"
    ),
    "/api/coach/ledger": (
        "free tier — nothing here is generated: every verdict is the owner's own strap "
        "data checked by a deterministic rule (challenges.day_verdicts), and the stored "
        "weekly-review `pattern` was written, and paid for, when that review was made"
    ),
    "/api/me": "identity",
    "/api/device": "identity — device pairing, and the list of what is paired",
    "/api/device/{token_id}": (
        "identity — revoking a device credential. Taking back the key to your own "
        "data is never behind a paywall: a lapsed subscriber who cannot revoke a "
        "lost phone is worse off than one who never signed up."
    ),
    "/api/entitlement": "the paywall's own status; a locked-out owner must be able to read it",
    "/api/auth-config": (
        "which identity provider to sign in against. UNAUTHENTICATED, and it cannot be "
        "otherwise: it is the call a client makes in order to learn how to authenticate, "
        "so requiring a credential would be circular. It serves two values that are "
        "public by construction — a project URL and the ANON key, which authorises "
        "nothing on its own — and never the service-role key or the JWT secret, which "
        "`tests/test_auth_config.py` asserts by name."
    ),
}


def _dependants(dependant: Dependant) -> list[Dependant]:
    """``dependant`` and every sub-dependency, flattened."""
    found = [dependant]
    for sub in dependant.dependencies:
        found.extend(_dependants(sub))
    return found


def _is_gated(route: APIRoute) -> bool:
    return any(isinstance(dep.call, AIGate) for dep in _dependants(route.dependant))


def _flatten(routes: Sequence[object]) -> list[APIRoute]:
    """Every ``APIRoute`` reachable from ``routes``, recursing into included routers.

    ``app.routes`` is NOT flat in this FastAPI version: an ``include_router`` leaves an
    ``_IncludedRouter`` wrapper whose real routes hang off ``original_router``. Walking
    only the top level found FOUR routes (the generated /docs ones) and every
    completeness assertion below passed vacuously — which is precisely the failure this
    file exists to prevent, one level up. Hence the recursion, and hence
    `test_the_route_walk_actually_finds_routes` immediately after it.
    """
    found: list[APIRoute] = []
    for route in routes:
        if isinstance(route, APIRoute):
            found.append(route)
        inner = getattr(getattr(route, "original_router", None), "routes", None) or getattr(
            route, "routes", None
        )
        if inner:
            found.extend(_flatten(inner))
    return found


def _api_routes() -> list[APIRoute]:
    """Every mounted route. There is no exclusion list any more, and that is the point.

    This used to drop ``{"/openapi.json", "/docs", "/docs/oauth2-redirect", "/redoc"}``
    by name. The exclusion was reasonable for a PAYWALL completeness check — a docs page
    is not AI output — but it meant the only route-walking guard in the repo had a
    hard-coded blind spot at exactly the four routes that were open by default and had
    never been argued for. There were 44 routes of ours plus those four, and this test
    reasoned about 44.

    ``create_app()`` now passes ``docs_url=None, redoc_url=None, openapi_url=None``
    (AUTH_AUDIT E1), so the routes are gone and the exclusion with them. If someone
    re-enables the docs, they appear here — un-gated and un-allowlisted — and
    ``test_every_mounted_route_is_gated_or_allowlisted`` names them. The blind spot
    closed by deleting the thing it was blind to.
    """
    return _flatten(create_app().routes)


def test_the_route_walk_actually_finds_routes() -> None:
    """The premise of every completeness assertion here — asserted, never assumed.

    A walk that returned nothing would make "no route is ungated" and "no gated route
    is unprobed" both trivially true. This is the same lesson `test_rls.py` records: an
    absence-based assertion needs its search proved non-empty first.
    """
    paths = {r.path for r in _api_routes()}
    assert len(paths) > 25, f"the route walk found only {sorted(paths)}"
    assert "/api/today" in paths and "/api/coach" in paths


# ── completeness: the guard that outlives this file's author ──────────────────


def test_every_mounted_route_is_gated_or_allowlisted() -> None:
    """No route may be premium-by-accident or free-by-accident.

    Driven off the real app object, so an endpoint added next year is covered the day it
    is mounted — and the failure NAMES it. A hand-maintained probe list cannot do that:
    it passes for every route nobody thought to add to it.
    """
    ungated = [
        f"{sorted(r.methods or [])} {r.path}"
        for r in _api_routes()
        if not _is_gated(r) and r.path not in FREE_PATHS
    ]
    assert not ungated, (
        f"these routes are neither gated nor in FREE_PATHS: {ungated}. If it serves AI "
        f"output, take a gated identity from api.gate; if it does not, say why in "
        f"FREE_PATHS."
    )


def test_the_free_allowlist_has_no_stale_entries() -> None:
    """The reverse direction — an allowlisted path that no longer exists is a lie."""
    mounted = {r.path for r in _api_routes()}
    stale = sorted(set(FREE_PATHS) - mounted)
    assert not stale, f"FREE_PATHS names paths that are not mounted: {stale}"


def test_the_probe_list_covers_every_gated_route() -> None:
    """…and the hand-written probe list below must not fall behind the app either."""
    gated = {r.path for r in _api_routes() if _is_gated(r)}
    probed = {path for _, path, _, _, _ in AI_ROUTES}
    # The probe list uses concrete ids where the route has a path parameter.
    probed_templates = {p.replace("999999", "{challenge_id}") for p in probed} | {
        p.replace("999999", "{program_id}") for p in probed
    }
    probed_templates |= {p.replace("999999", "{rec_id}") for p in probed}
    missing = sorted(gated - probed_templates)
    assert not missing, f"gated routes never probed for a 402: {missing}"


# ── the gate itself ───────────────────────────────────────────────────────────


@pytest.mark.parametrize(("method", "path", "params", "body", "feature"), AI_ROUTES)
def test_a_free_owner_is_refused_402_by_every_ai_route(
    bed: TestClient,
    make_free: Callable[[], None],
    stub,  # noqa: ANN001, ARG001 — patched so a leak would be a call, not a network error
    method: str,
    path: str,
    params: dict | None,
    body: dict | None,
    feature: str,
) -> None:
    """A direct call, authenticated and well-formed, still gets 402 (§12.7 loophole 2)."""
    make_free()
    response = bed.request(method, path, params=params, json=body, headers=AUTH)
    assert response.status_code == 402, f"{method} {path} → {response.status_code}"
    detail = response.json()["detail"]
    assert detail["locked"] is True
    assert detail["feature"] == feature  # the app renders THIS feature's locked card
    assert "upgrade" in detail
    # A hard lock is not a spent allowance, and the body must not imply waiting helps.
    assert "resets_at" not in detail


@pytest.mark.parametrize(("method", "path", "params", "body", "feature"), AI_ROUTES)
def test_a_premium_owner_is_never_refused_402(
    bed: TestClient,
    stub,  # noqa: ANN001, ARG001
    method: str,
    path: str,
    params: dict | None,
    body: dict | None,
    feature: str,  # noqa: ARG001 — part of the shared parameter table
) -> None:
    """The other side of the gate. Not `== 200`: several of these legitimately answer
    404/409 for a made-up id, and asserting the happy status would mean seeding six
    preconditions to test one dependency. What must never happen is 402."""
    response = bed.request(method, path, params=params, json=body, headers=AUTH)
    assert response.status_code != 402, f"{method} {path} refused a PREMIUM owner"


def test_the_representative_ai_surfaces_actually_serve_a_premium_owner(
    bed: TestClient,
    stub,  # noqa: ANN001, ARG001
) -> None:
    """…and the ones whose preconditions the seed satisfies really do return 200."""
    for path in ("/api/sleep/insight", "/api/notable", "/api/challenges", "/api/programs"):
        assert bed.get(path, headers=AUTH).status_code == 200, path
    reply = bed.post(
        "/api/coach",
        json={"messages": [{"role": "user", "content": "how am I doing?"}]},
        headers=AUTH,
    )
    assert reply.status_code == 200
    assert reply.json()["reply"]


def test_a_free_owner_spends_no_llm_calls_at_the_endpoint(
    bed: TestClient,
    make_free: Callable[[], None],
    stub,  # noqa: ANN001
) -> None:
    """The endpoint half of §12.7's invariant, measured rather than argued.

    A gate that ran AFTER generation would produce identical 402s while costing exactly
    the tokens the paywall exists to protect — so the assertion is on the model's call
    count, not on the status code.

    Since the free tier lost its AI entirely the invariant is back to its simplest form:
    **zero** calls for a free owner, on every surface including the two that used to be
    metered. The coach is asked five times to make that a measurement rather than a
    coincidence of a single request.
    """
    make_free()
    for path in ("/api/sleep/insight", "/api/activity/insight", "/api/notable"):
        assert bed.get(path, headers=AUTH).status_code == 402
    question = {"messages": [{"role": "user", "content": "how am I doing?"}]}
    for _ in range(5):
        assert bed.post("/api/coach", json=question, headers=AUTH).status_code == 402
    assert bed.post("/api/today/action", headers=AUTH).status_code == 402
    assert stub.calls == 0


# ── the client is never trusted (§12.7 loophole 1) ────────────────────────────


def test_a_client_claiming_premium_is_still_refused(
    bed: TestClient,
    make_free: Callable[[], None],
    stub,  # noqa: ANN001, ARG001
) -> None:
    """Entitlement comes from the table. Headers, query params and bodies do not."""
    make_free()
    lying = {**AUTH, "X-Premium": "true", "X-Entitlement": "active"}
    assert bed.get("/api/notable", params={"premium": "true"}, headers=lying).status_code == 402
    assert (
        bed.get("/api/sleep/insight", params={"premium": "true"}, headers=lying).status_code == 402
    )
    # …and the coach is not persuadable either, however the claim is dressed up.
    question = {"premium": True, "messages": [{"role": "user", "content": "hi"}]}
    assert bed.post("/api/coach", json=question, headers=lying).status_code == 402
