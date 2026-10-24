"""The challenges router's typed responses: the schema they publish, and the nulls.

``test_contracts`` pins the wire against the committed snapshots and
``test_challenge_endpoints`` pins the behaviour. This file pins the two things that
only exist because the handlers are now pydantic models rather than ``dict``:

* **the published schema.** A ``-> dict`` handler documents its 200 as a bare
  ``{"type": "object", "additionalProperties": true}`` — an OpenAPI generator, a
  client codegen or a reviewer reading the docs learns nothing from it. That was the
  whole reason to type these five, so it is asserted rather than assumed;
* **the honest nulls.** The models are the last thing to touch a value before it goes
  on the wire, so they are the last place a ``NULL`` could be quietly turned into a
  ``0``. ``adherence`` is the case that matters — deliberately null for a cumulative
  cadence (``ledger._adherence``), because a rule with no per-day commitment has no
  rate of keeping it. A model that defaulted it would ship "they adhered 0 % of the
  time" about someone who was never asked to do anything daily.

The last two tests go through HTTP against a real weekly challenge, because the
model-level assertions above cannot see a serializer or a FastAPI response filter.
"""

from __future__ import annotations

import json
from typing import Any

import pytest
from fastapi.testclient import TestClient
from tests.contracts.seed import today_local

from healthee.api.app import create_app
from healthee.api.routers.challenges import (
    ChallengeFeed,
    CumulativeProgress,
    DailyProgress,
    Outcome,
    OutcomeLedger,
)
from healthee.core.db import tenant_transaction
from healthee.core.tenancy import SENTINEL_USER_ID

# (operation, path, response-model component) for every endpoint this router serves.
_ENDPOINTS = [
    ("get", "/api/challenges", "ChallengeFeed"),
    ("post", "/api/challenges/{challenge_id}/adopt", "ChallengeResult"),
    ("post", "/api/challenges/{challenge_id}/abandon", "ChallengeResult"),
    ("post", "/api/challenges/{challenge_id}/adapt", "AdaptResult"),
    ("get", "/api/challenges/outcomes", "OutcomeLedger"),
]

# One frozen outcome for a WEEKLY challenge, as `ledger.recent` returns it: a
# cumulative cadence, so `adherence` is null and `improvement_pct` could not be
# computed from a zero baseline. Both nulls are the honest answer, not missing data.
# `difficulty` is null here on purpose — `_seed_weekly` below writes the row without
# it, which is the pre-#62 shape the nullable column still legitimately holds.
_WEEKLY_OUTCOME: dict[str, Any] = {
    "challenge_id": 99,
    "metric": "alcohol_units",
    "category": "recovery",
    "difficulty": None,
    "cadence": "weekly",
    "target": 5.0,
    "baseline": 0.0,
    "final": 2.0,
    "improvement_pct": None,
    "improved": None,
    "adherence": None,  # a cumulative rule makes no per-day commitment
    "days_active": 7,
    "status": "met",
    "confounds": {"illness_days": 0, "concurrent_challenges": 0},
    "co_occurring": None,
    "data_confidence": "insufficient_data",
    "ended_at": "2026-07-30T00:00:00Z",
}


def test_the_openapi_schema_describes_every_challenge_response() -> None:
    """Each endpoint's 200 body resolves to its own named component, not `object`.

    This is the concrete thing typing bought. `-> dict` published an unconstrained
    object for all five, so the schema could not tell a client that `/api/challenges`
    returns three lists and a cap — or that any field exists at all.
    """
    schema = create_app().openapi()
    for method, path, component in _ENDPOINTS:
        body = schema["paths"][path][method]["responses"]["200"]["content"]["application/json"]
        assert body["schema"] == {"$ref": f"#/components/schemas/{component}"}, (
            f"{method.upper()} {path} does not publish a typed response"
        )


def test_the_published_feed_schema_names_its_fields() -> None:
    """The component is not an empty shell: it carries the real field set."""
    components = create_app().openapi()["components"]["schemas"]
    assert set(components["ChallengeFeed"]["properties"]) == {
        "active",
        "suggested",
        "recent",
        "max_active",
    }
    # progress is a tagged union, so the schema can say WHICH shape a cadence yields
    # rather than collapsing the two into one optional-everything object.
    progress = components["ActiveChallenge"]["properties"]["progress"]
    assert progress["discriminator"]["propertyName"] == "cadence"
    assert set(progress["discriminator"]["mapping"]) == {"daily", "weekly", "total"}
    assert "hit_days" in components["DailyProgress"]["properties"]
    assert "hit_days" not in components["CumulativeProgress"]["properties"]
    assert "breached" in components["CumulativeProgress"]["properties"]


def test_the_published_outcome_schema_marks_the_honest_nulls() -> None:
    """`adherence` is documented as nullable AND required — present, possibly null.

    Required-and-nullable is the whole contract: the client always gets the key, and a
    null means "this cadence has no adherence rate", never "the field was omitted".
    """
    outcome = create_app().openapi()["components"]["schemas"]["Outcome"]
    assert outcome["properties"]["adherence"]["anyOf"] == [{"type": "number"}, {"type": "null"}]
    assert "adherence" in outcome["required"]
    for field in ("improvement_pct", "improved", "baseline", "final"):
        assert field in outcome["required"], f"{field} must be present even when null"


def test_a_cumulative_outcome_serialises_adherence_as_null_not_zero() -> None:
    """The null survives validation AND serialisation, and no key is added or lost."""
    dumped = Outcome.model_validate(_WEEKLY_OUTCOME).model_dump(mode="json")
    assert dumped["adherence"] is None, "a cumulative cadence has no adherence rate"
    assert not isinstance(dumped["adherence"], float)
    assert '"adherence":null' in json.dumps(dumped, separators=(",", ":"))
    assert set(dumped) == set(_WEEKLY_OUTCOME), "the model changed the key set"


def test_an_insufficient_data_outcome_round_trips_its_label() -> None:
    """`insufficient_data` is a value the client renders, so it must survive as one."""
    ledger = OutcomeLedger.model_validate({"outcomes": [_WEEKLY_OUTCOME]})
    assert ledger.outcomes[0].data_confidence == "insufficient_data"
    assert ledger.model_dump(mode="json")["outcomes"][0]["data_confidence"] == "insufficient_data"


def test_an_absent_nullable_key_is_an_error_not_a_null() -> None:
    """No field is defaulted: a key the domain forgot must fail loudly, not go null.

    This is the mutation guard for rule 2 in the router's docstring — the moment any
    of these gains a ``= None``, a dropped field starts serialising as "no data".
    """
    for field in ("adherence", "improvement_pct", "co_occurring", "improved"):
        missing = {k: v for k, v in _WEEKLY_OUTCOME.items() if k != field}
        with pytest.raises(ValueError, match=field):
            Outcome.model_validate(missing)


def test_an_unmodelled_key_is_rejected_rather_than_dropped() -> None:
    """`extra="forbid"`: a response model must never silently shrink the wire.

    The probe used to be `difficulty`, which is exactly how #62 was found: the model
    correctly refused a key the ledger was writing but never selecting. It is a real
    field now, so the probe moved to `downstream` — the TEXT column 0009 replaced with
    `co_occurring`, i.e. a name that must never come back.
    """
    with pytest.raises(ValueError, match="downstream"):
        Outcome.model_validate(_WEEKLY_OUTCOME | {"downstream": "sleep improved"})


def test_difficulty_is_modelled_as_the_nullable_column_it_is() -> None:
    """Required-and-nullable: present on every row, null where the writer left it so.

    `challenge.difficulty` is NOT NULL, so `_compute` always fills it — but
    `challenge_outcome.difficulty` is nullable and rows predate the writer. Defaulting
    it to `'standard'` here would invent a commitment level nobody was ever set.
    """
    outcome = create_app().openapi()["components"]["schemas"]["Outcome"]
    assert outcome["properties"]["difficulty"]["anyOf"] == [{"type": "string"}, {"type": "null"}]
    assert "difficulty" in outcome["required"]
    dumped = Outcome.model_validate(_WEEKLY_OUTCOME).model_dump(mode="json")
    assert dumped["difficulty"] is None
    with pytest.raises(ValueError, match="difficulty"):
        Outcome.model_validate({k: v for k, v in _WEEKLY_OUTCOME.items() if k != "difficulty"})


def test_the_two_progress_shapes_stay_distinct() -> None:
    """A daily result is not a cumulative one with nulls — the union keeps them apart."""
    feed = ChallengeFeed.model_validate(_feed_fixture())
    daily, cumulative = feed.active[0].progress, feed.active[1].progress
    assert isinstance(daily, DailyProgress)
    assert isinstance(cumulative, CumulativeProgress)
    dumped = feed.model_dump(mode="json")["active"]
    assert "breached" not in dumped[0]["progress"], "a daily card gained a cap's field"
    assert "hit_days" not in dumped[1]["progress"], "a cumulative card gained a streak field"


def _challenge_fixture(cadence: str) -> dict[str, Any]:
    """A `store.row` mapping — every column, exactly as the reader returns it."""
    return {
        "id": 1,
        "created_at": "2026-07-01T00:00:00Z",
        "gen_date": None,
        "title": "t",
        "why": "w",
        "category": "activity",
        "difficulty": "standard",
        "metric": "steps_total",
        "comparator": ">=",
        "target_value": 9000.0,
        "cadence": cadence,
        "window_days": 7,
        "expected_outcome": None,
        "how_to": None,
        "research_note_ids": ["steps_mortality"],
        "status": "active",
        "adopted_at": "2026-07-01T00:00:00Z",
        "ends_at": "2026-07-08T00:00:00Z",
        "completed_at": None,
        "abandoned_at": None,
        "baseline_value": 8200.0,
        "program_id": None,
        "rung_index": None,
        "kind": "standard",
        "action_text": None,
        "slot_text": None,
        "floor_value": None,
        "floor_text": None,
        "counts_when": None,
        "days_required": None,
    }


def _feed_fixture() -> dict[str, Any]:
    """A feed carrying one of each progress shape — `evaluate_challenge`'s two branches."""
    common = {"target": 9000.0, "today_value": None, "days_left": 0, "elapsed": 7}
    common |= {"unit": "", "label": "Steps", "window": 7, "progress": 1.0, "complete": True}
    daily = common | {"cadence": "daily", "hit_days": 7, "streak": 7}
    daily |= {"today_hit": True, "protected_today": False, "adaptation": None}
    cumulative = common | {"cadence": "weekly", "current": 63000.0}
    cumulative |= {"breached": False, "adaptation": None}
    return {
        "active": [
            _challenge_fixture("daily") | {"progress": daily},
            _challenge_fixture("weekly") | {"progress": cumulative},
        ],
        "suggested": [],
        "recent": [],
        "max_active": 3,
    }


@pytest.mark.integration
def test_a_weekly_challenge_reaches_the_wire_in_its_own_shape(seeded_client: tuple) -> None:
    """End-to-end: the union survives FastAPI's response serialisation, both branches."""
    client, headers = seeded_client
    _seed_weekly(active=True)
    active = client.get("/api/challenges", headers=headers).json()["active"]
    shapes = {c["progress"]["cadence"]: c["progress"] for c in active}
    assert set(shapes) == {"daily", "weekly"}
    assert "current" in shapes["weekly"] and "breached" in shapes["weekly"]
    assert "hit_days" not in shapes["weekly"]
    assert "hit_days" in shapes["daily"] and "breached" not in shapes["daily"]


@pytest.mark.integration
def test_a_null_adherence_reaches_the_wire_as_null(seeded_client: tuple) -> None:
    """The NULL column arrives as JSON null — asserted on the raw body, not the parse.

    `resp.json()` would read a missing key and a null key the same way; the response
    TEXT cannot.
    """
    client, headers = seeded_client
    _seed_weekly(active=False)
    resp = client.get("/api/challenges/outcomes", headers=headers)
    assert resp.status_code == 200, resp.text[:200]
    weekly = [o for o in resp.json()["outcomes"] if o["cadence"] == "weekly"]
    assert len(weekly) == 1 and weekly[0]["adherence"] is None
    assert weekly[0]["data_confidence"] == "insufficient_data"
    assert '"adherence":null' in resp.text  # FastAPI's JSON is compact-separated


@pytest.mark.integration
def test_difficulty_reaches_the_wire(seeded_client: tuple) -> None:
    """#62 end-to-end: the column the writer always filled is now actually served.

    Both rows are asserted because the claim is that the field TRAVELS, not that it is
    always populated: the seeded daily outcome carries `'standard'`, and `_seed_weekly`
    writes a row without it, which the nullable column still legitimately holds. The
    raw body is checked for the null so a *missing* key cannot pass as one.
    """
    client, headers = seeded_client
    _seed_weekly(active=False)
    resp = client.get("/api/challenges/outcomes", headers=headers)
    assert resp.status_code == 200, resp.text[:200]
    by_cadence = {o["cadence"]: o for o in resp.json()["outcomes"]}
    assert by_cadence["daily"]["difficulty"] == "standard"
    assert by_cadence["weekly"]["difficulty"] is None
    assert '"difficulty":null' in resp.text  # FastAPI's JSON is compact-separated


def _seed_weekly(active: bool) -> None:
    """One weekly challenge for the sentinel — active, or finished with an outcome.

    Written straight to the tables rather than through the lifecycle: the point is the
    shape the READER produces for a cumulative cadence, and driving a real week of
    weekly data through `adopt`/`finalize_due` would test the engine instead.
    """
    status, adopted = ("active", today_local()) if active else ("completed", today_local())
    with tenant_transaction(SENTINEL_USER_ID) as cur:
        cur.execute(
            "INSERT INTO challenge (user_id, title, why, category, metric, comparator, "
            "  target_value, cadence, window_days, status, adopted_at, ends_at, baseline_value) "
            "VALUES (%s,'Weekly steps','w','activity','steps_total','>=',50000,'weekly',7,%s,"
            "  %s::date, %s::date + 7, 45000) RETURNING id",
            (SENTINEL_USER_ID, status, adopted, adopted),
        )
        row = cur.fetchone()
        assert row is not None
        if active:
            return
        cur.execute(
            "INSERT INTO challenge_outcome (user_id, challenge_id, metric, category, cadence, "
            "  target, baseline, final, improvement_pct, improved, adherence, days_active, "
            "  status, confounds, co_occurring, data_confidence) "
            "VALUES (%s,%s,'steps_total','activity','weekly',50000,45000,52000,15.6,true,"
            "  NULL,7,'met','{}'::jsonb,NULL,'insufficient_data')",
            (SENTINEL_USER_ID, int(row[0])),
        )


def test_the_app_still_builds_with_the_models_mounted() -> None:
    """Guard against a model that only fails when FastAPI resolves the schema.

    Resolving the schema IN-PROCESS is the check; it used to be `GET /openapi.json`,
    and that route is deliberately gone (`api/app.py` sets `openapi_url=None`, because
    a machine-readable map of a health API was being served to anybody). `app.openapi()`
    runs the same resolution — every response model, every reference — which is the
    property this test is about, and it does not depend on the schema being PUBLISHED.
    """
    app = create_app()
    schema = app.openapi()
    assert schema["paths"], "the schema resolved to no paths at all"
    # …and the routes that were serving it are not mounted any more.
    client = TestClient(create_app())
    for generated in ("/openapi.json", "/docs", "/redoc"):
        assert client.get(generated).status_code == 404, generated
