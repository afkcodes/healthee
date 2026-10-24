"""The read endpoints exercised by the contract bed, and a helper that calls every
one against a seeded ``TestClient`` (resolving the two dynamic ids — a workout
start and a GPS track id — from prior responses)."""

from __future__ import annotations

from typing import Any

# name → (method, path, params, json-body). Names are the snapshot filenames.
STATIC_ENDPOINTS: list[tuple[str, str, str, dict | None, dict | None]] = [
    ("today", "GET", "/api/today", None, None),
    ("sleep", "GET", "/api/sleep", {"days": 30}, None),
    ("sleep_health_score", "GET", "/api/sleep/health_score", {"days": 30}, None),
    ("sleep_consistency", "GET", "/api/sleep/consistency", {"days": 28}, None),
    ("activity", "GET", "/api/activity", None, None),
    ("history", "GET", "/api/history", {"metric": "steps_total", "days": 30}, None),
    # The batched form (C1). Pinned separately because it is a DIFFERENT shape,
    # not a longer one: `{days, series: {metric: […]}}` against the single form's
    # `{metric, series: […]}`. Three metrics rather than one, and deliberately
    # one of each kind the read has to handle — a plain `derived_daily` row, a
    # value carried inside another metric's flags, and the weigh-in that comes
    # from `weight_log` — so a snapshot cannot pass while two of the three paths
    # are broken.
    (
        "history_batch",
        "GET",
        "/api/history",
        {"metrics": "steps_total,moderate_min,weight_kg", "days": 30},
        None,
    ),
    ("profile", "GET", "/api/profile", None, None),
    # The paywall's own endpoint is a wire contract like any other: since #116 it carries
    # `included`, the balance left on the coach cap, and a client that mis-parses that
    # renders somebody the wrong number of questions.
    ("entitlement", "GET", "/api/entitlement", None, None),
    ("log_recent", "GET", "/api/log/recent", {"days": 7}, None),
    # The basemap's own contract: what the app must credit on screen, and the zoom
    # range it may ask for. Pinned because the app draws NO basemap when it cannot
    # parse this — a renamed key here is a map that quietly stops appearing, with
    # nothing failing anywhere.
    ("map", "GET", "/api/map", None, None),
    ("gps_list", "GET", "/api/workout/gps", None, None),
    ("challenges", "GET", "/api/challenges", None, None),
    ("challenge_outcomes", "GET", "/api/challenges/outcomes", {"limit": 20}, None),
    ("programs", "GET", "/api/programs", None, None),
    # "Every yes, checked" — the Coach screen and the ledger screen read this one payload.
    ("coach_ledger", "GET", "/api/coach/ledger", {"window": "month"}, None),
    ("log_post", "POST", "/api/log", None, {"type": "caffeine", "amount": 50, "unit": "mg"}),
]


def call_all(client: Any, headers: dict) -> dict[str, Any]:
    """Return {endpoint_name: response_json} for every read endpoint (200s asserted)."""
    out: dict[str, Any] = {}
    for name, method, path, params, body in STATIC_ENDPOINTS:
        resp = client.request(method, path, params=params, json=body, headers=headers)
        assert resp.status_code == 200, f"{name}: {resp.status_code} {resp.text[:200]}"
        out[name] = resp.json()
    out["workout"] = _workout(client, headers, out["activity"])
    out["gps_detail"] = _gps_detail(client, headers, out["gps_list"])
    # LAST, because it mutates: adopting turns the seeded suggestion into an active
    # challenge, which would change the `challenges` feed above if it ran first.
    out["challenge_adopt"] = _adopt(client, headers, out["challenges"])
    out["challenge_slot"] = _slot(client, headers, out["challenge_adopt"])
    return out


def _workout(client: Any, headers: dict, activity: dict) -> Any:
    workouts = activity.get("workouts") or []
    if not workouts:
        return None
    resp = client.get(
        "/api/activity/workout", params={"start": workouts[0]["start_iso"]}, headers=headers
    )
    assert resp.status_code == 200, f"workout: {resp.status_code} {resp.text[:200]}"
    return resp.json()


def _adopt(client: Any, headers: dict, challenges: dict) -> Any:
    """Adopt the seeded suggestion — the one lifecycle WRITE the contract bed pins.

    The app's whole interaction with a suggestion is this call, so its response shape
    (the stored challenge, with the baseline the server froze) is exactly what the
    client will parse to render "you're on".
    """
    suggested = challenges.get("suggested") or []
    if not suggested:
        return None
    resp = client.post(f"/api/challenges/{suggested[0]['id']}/adopt", headers=headers)
    assert resp.status_code == 200, f"challenge_adopt: {resp.status_code} {resp.text[:200]}"
    return resp.json()


def _slot(client: Any, headers: dict, adopted: Any) -> Any:
    """Reword the slot of the challenge `_adopt` just took on — the Coach screen's edit."""
    if adopted is None:
        return None
    path = f"/api/challenges/{adopted['challenge']['id']}/slot"
    resp = client.patch(path, json={"slot": "After lunch"}, headers=headers)
    assert resp.status_code == 200, f"challenge_slot: {resp.status_code} {resp.text[:200]}"
    return resp.json()


def _gps_detail(client: Any, headers: dict, gps_list: dict) -> Any:
    tracks = gps_list.get("tracks") or []
    if not tracks:
        return None
    resp = client.get(f"/api/workout/gps/{tracks[0]['track_id']}", headers=headers)
    assert resp.status_code == 200, f"gps_detail: {resp.status_code} {resp.text[:200]}"
    return resp.json()
