"""Contract tests: every read endpoint's live response must CONFORM to its committed
snapshot (same keys + value types), and a set of deterministic derived numbers must
match exactly. This is the regression bed guarding the mobile app's expectations.
"""

from __future__ import annotations

import json
from pathlib import Path

import pytest
from tests.contracts.endpoints import call_all
from tests.contracts.shape import assert_conforms

pytestmark = pytest.mark.integration

_SNAPSHOT_DIR = Path(__file__).resolve().parents[4] / "packages" / "contracts" / "snapshots"


def _snapshot(name: str) -> dict:
    return json.loads((_SNAPSHOT_DIR / f"{name}.json").read_text())


@pytest.fixture
def responses(seeded_client: tuple) -> dict:
    client, headers = seeded_client
    return call_all(client, headers)


_ENDPOINTS = [
    "today",
    "sleep",
    "sleep_health_score",
    "sleep_consistency",
    "activity",
    "history",
    "history_batch",
    "profile",
    "entitlement",
    "log_recent",
    "gps_list",
    "log_post",
    "workout",
    "gps_detail",
    "challenges",
    "challenge_outcomes",
    "challenge_adopt",
    "challenge_slot",
    "coach_ledger",
]


@pytest.mark.parametrize("name", _ENDPOINTS)
def test_response_conforms_to_snapshot(responses: dict, name: str) -> None:
    """The live response has the same nested key set + value types as the snapshot."""
    assert_conforms(responses[name], _snapshot(name), name)


def test_deterministic_derived_values(responses: dict) -> None:
    """Numbers computed deterministically from the seed match exactly (guards the
    computed-on-read formulas + the v2-native reads, not just the shape)."""
    today = responses["today"]
    # 43.0, the day's GRADED session — not the 41.5 Jurca number the other 29 seeded days
    # carry. `vo2max_estimate` is tiered since #117 and a measured session inside the
    # freshness horizon IS the estimate, so the wire must show the measurement and name
    # the instrument that took it ([[hr_reserve_vo2max]] D4).
    assert today["vo2max"]["estimate"] == 43.0
    assert today["vo2max"]["method"] == "gps_graded"
    assert today["vo2max"]["research_notes"] == ["vo2max", "submaximal_vo2max"]
    # Biological age end to end, and by VALUE: since #86 it is chronological + fitness +
    # sleep duration ONLY, and since #97 the sleep term is read at the QUESTIONNAIRE
    # equivalent of the seeded 380 min (6.333 h → 7.0 h, exactly Yin's nadir, so HR = 1.0
    # and the term contributes nothing). Since #101 the fitness reference is FRIEND's
    # published 39.7 for a 30–39 male, so the tiered 43.0 estimate is +0.9429 MET:
    # HR = 0.85^0.9429 = 0.858, ΔAge = ln(0.858)·7.7/ln(2) = −1.7024, and
    # 36 − 1.7024 + 0 = 34.30. A snapshot comparison is keys-and-types, so re-adding a
    # term — or re-anchoring one — would sail through it while changing the headline
    # number the app renders. [[biological_age_estimate]].
    assert today["biological_age"]["biological_age"] == 34.3
    assert [c["term"] for c in today["biological_age"]["contributions"]] == [
        "fitness",
        "sleep duration",
    ]
    assert [e["reason"] for e in today["biological_age"]["excluded"]] == [
        "sri_hazard_not_transportable"
    ]
    # …and the footing of the two terms that ARE priced reaches the app, not just the
    # note. `excluded` and `caveats` answer different owner questions and both ship.
    # Three since #108: the fitness term's footing is its anchor AND what the number on
    # OUR side of the comparison rests on. Since #117 that second entry moves with the
    # instrument — here the estimate is measured from a session, so the entry says so
    # rather than citing a self-reported activity category the measurement never used.
    assert [c["reason"] for c in today["biological_age"]["caveats"]] == [
        "vo2max_reference_clinical_cohort",
        "vo2max_measured_from_session",
        "sleep_duration_self_report_scale",
    ]
    assert [c["method"] for c in today["biological_age"]["contributions"]] == ["gps_graded", None]
    assert today["sleep_debt"]["performance_pct"] == 79  # 100·380/480, capped
    assert today["cardio_load"]["strain"] == 21.0  # every day is P95 → full strain
    assert today["mvpa"]["week_moderate_min"] >= 24  # from mvpa_min flags (seam fix)
    assert responses["activity"]["acwr"]["ratio"] == 1.0  # flat 30-day load
    assert responses["profile"]["weight_kg"] == 72.5
    # dob goes out as epoch ms at OWNER-LOCAL midnight (seed: 1990-05-01,
    # Asia/Kolkata). Asserted by VALUE, not just shape: `assert_conforms` compares
    # keys and types only, so the snapshot number alone guards nothing. This is the
    # end-to-end guard for the anchor bug — 641_520_000_000 here means the encoder
    # went back to UTC midnight and negative-offset owners' birthdays will walk.
    assert responses["profile"]["dob"] == 641_500_200_000
    # #116: the coach meter, whole. A client renders "N of 20 left" from this and
    # `assert_conforms` compares keys and types only, so the snapshot alone would not
    # catch a wrong N — nor `resets_at`/`retry_after_s` becoming non-null, since both are
    # legitimately null for an owner with questions in hand. 20 and 30 are PRICING.md §0's
    # decided numbers, pinned here on the wire exactly as `test_premium_cap` pins them in
    # the table they are read from.
    assert responses["entitlement"]["included"] == [
        {
            "feature": "coach",
            "limit": 20,
            "used": 0,
            "remaining": 20,
            "window_days": 30,
            "resets_at": None,
            "retry_after_s": None,
        }
    ]


def test_today_has_every_legacy_key(responses: dict) -> None:
    """Every top-level Today key the installed app reads is present (wire-compat)."""
    expected = set(_snapshot("today"))
    assert set(responses["today"]) == expected
