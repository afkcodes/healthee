"""The metric catalogue — ONE table of what an AI tool may ask for, and what each key means.

`analytics.metrics` is the registry of which keys exist; it says nothing about units or
meaning, because the server never needed to. A model reading a bare `sleep_dim_timing`
series has to guess whether 1 is good, so every key carries a unit and a one-line
definition here, and `note_id` names the research note that defines or grades it.

**The names agree with the app.** `note_id` is the first note the app's own explainer for
that metric cites (`apps/mobile/lib/shared/metric_info/explainers_*.dart`), so a model and
the owner reading the same metric are pointed at the same evidence. `None` means the app
names no note for it — absent, not guessed (citations are real or absent).

`tests/mcp/test_catalogue.py` pins the two ways this table rots: a key added to
`analytics.metrics` and not here, and a `note_id` that is not in the manifest.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass
from typing import Literal

from healthee.analytics.metrics import EVENT_KINDS, FLAG_DERIVED_METRICS, KNOWN_METRICS

Kind = Literal["series", "derived", "event"]


@dataclass(frozen=True)
class CatalogueEntry:
    """One askable key: a daily series, a series carried inside another, or a logged event."""

    key: str
    kind: Kind
    unit: str
    definition: str
    note_id: str | None


def _series(key: str, unit: str, definition: str, note_id: str | None) -> CatalogueEntry:
    kind: Kind = "derived" if key in FLAG_DERIVED_METRICS else "series"
    return CatalogueEntry(key, kind, unit, definition, note_id)


def _event(key: str, definition: str, note_id: str | None) -> CatalogueEntry:
    return CatalogueEntry(key, "event", "logged occurrence", definition, note_id)


_PASS = "0 or 1 (1 = the check passed)"

CATALOGUE: tuple[CatalogueEntry, ...] = (
    _series(
        "rhr_daily", "bpm", "Resting heart rate, taken from the sleep window.", "resting_heart_rate"
    ),
    _series(
        "hrv_sleep_avg",
        "ms",
        "Mean overnight heart-rate variability (RMSSD).",
        "heart_rate_variability",
    ),
    _series(
        "spo2_overnight",
        "%",
        "Mean overnight blood oxygen from the strap; not a cleared oximeter.",
        "wearable_spo2_validity",
    ),
    _series(
        "spo2_overnight_min",
        "%",
        "Lowest overnight blood oxygen reading.",
        "wearable_spo2_validity",
    ),
    _series(
        "respiratory_rate_sleep",
        "breaths/min",
        "Mean breathing rate during sleep.",
        "respiratory_rate_normal",
    ),
    _series(
        "sleep_health_score_4dim",
        "0-4 checks passed",
        "Sleep health: how many of four "
        "checks (duration, efficiency, timing, regularity) the night passed.",
        "sleep_health_score_multidim",
    ),
    _series(
        "sleep_regularity_index",
        "0-100",
        "Sleep Regularity Index: how closely sleep and wake times repeat from day to day.",
        "sleep_regularity_index",
    ),
    _series(
        "sleep_dim_duration",
        _PASS,
        "Sleep health check: slept within the target duration range.",
        "sleep_health_score_multidim",
    ),
    _series(
        "sleep_dim_efficiency",
        _PASS,
        "Sleep health check: time asleep over time in bed met the minimum.",
        "sleep_health_score_multidim",
    ),
    _series(
        "sleep_dim_timing",
        _PASS,
        "Sleep health check: the night's midpoint fell in the target window.",
        "sleep_health_score_multidim",
    ),
    _series(
        "sleep_dim_regularity",
        _PASS,
        "Sleep health check: the Sleep Regularity Index met the good threshold.",
        "sleep_health_score_multidim",
    ),
    _series("sleep_need_min", "min", "Estimated sleep need for the night.", "sleep_need_debt"),
    _series(
        "sleep_debt_min",
        "min",
        "Accumulated shortfall of sleep against the estimated need.",
        "sleep_need_debt",
    ),
    _series("steps_total", "steps", "Total steps for the local day.", "steps_mortality"),
    _series("distance_m_daily", "m", "Distance covered in the local day.", None),
    _series(
        "total_calories",
        "kcal",
        "Total energy expenditure for the day (MET-by-state model).",
        "energy_expenditure_derivation",
    ),
    _series(
        "active_calories",
        "kcal",
        "Energy expenditure above resting for the day.",
        "energy_expenditure_derivation",
    ),
    _series(
        "basal_calories",
        "kcal",
        "Resting energy expenditure for the day.",
        "energy_expenditure_derivation",
    ),
    _series(
        "mvpa_min",
        "min",
        "Moderate-to-vigorous physical activity minutes in the day.",
        "mvpa_minutes_mortality",
    ),
    _series(
        "moderate_min",
        "min",
        "Moderate-intensity minutes (carried inside mvpa_min).",
        "mvpa_minutes_mortality",
    ),
    _series(
        "vigorous_min",
        "min",
        "Vigorous-intensity minutes (carried inside mvpa_min).",
        "mvpa_minutes_mortality",
    ),
    _series(
        "cardio_load",
        "TRIMP",
        "Banister TRIMP: heart-rate-based training load for the day.",
        "training_stress_score",
    ),
    _series(
        "recovery_score",
        "0-100",
        "Estimated recovery from overnight HRV and resting HR "
        "against the owner's own baseline, sleep and breathing. An estimate, not a "
        "validated score.",
        "recovery_readiness",
    ),
    _series(
        "vo2max_estimate",
        "ml/kg/min",
        "Cardio fitness estimate; its method is named on "
        "the value (graded fit, heart-rate reserve, or non-exercise).",
        "vo2max",
    ),
    _series("weight_kg", "kg", "Last weigh-in of the local day.", "weight_bmi_body_composition"),
    _event("alcohol", "Logged alcohol (units).", "alcohol_sleep"),
    _event("caffeine", "Logged caffeine (mg).", "caffeine_sleep"),
    _event("meditation", "Logged meditation session.", None),
    _event("exercise", "Logged exercise session.", "exercise_mortality"),
    _event("fasting", "Logged fast.", "fasting_metrics"),
)

BY_KEY: dict[str, CatalogueEntry] = {entry.key: entry for entry in CATALOGUE}

# Every key the catalogue must carry, derived from the registry so the two cannot drift.
REQUIRED_KEYS: frozenset[str] = KNOWN_METRICS | EVENT_KINDS.keys()


def catalogue_payload() -> dict:
    """The catalogue as `list_metrics` and `healthee://metrics` serve it."""
    return {"metrics": [asdict(entry) for entry in CATALOGUE]}
