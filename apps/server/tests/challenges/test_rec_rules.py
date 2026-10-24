"""Legacy recommendation text -> a rule, only when the sentence is unambiguous."""

from __future__ import annotations

import pytest

from healthee.challenges.rec_rules import RecRule, parse_rule


@pytest.mark.parametrize(
    ("action", "expected"),
    [
        ("Walk toward 6,000 steps", RecRule("steps_total", ">=", 6000.0)),
        ("Aim for 8k steps today", RecRule("steps_total", ">=", 8000.0)),
        ("20 min brisk walk", RecRule("mvpa_min", ">=", 20.0)),
        ("15 to 20 minutes of brisk walking", RecRule("mvpa_min", ">=", 15.0)),
        ("Get 8 hours of sleep tonight", RecRule("tst_min", ">=", 480.0)),
        ("Sleep 7.5 hrs", RecRule("tst_min", ">=", 450.0)),
    ],
)
def test_clear_metric_and_number_parses(action: str, expected: RecRule):
    assert parse_rule(action) == expected


@pytest.mark.parametrize(
    "action",
    [
        "Earlier bedtime tonight",
        "Keep today easy, no hard session",
        "Morning light within 2 h of waking",  # a number, but not a metric the strap sees
        "20 min easy walk",  # easy is not MVPA
        "Walk 6,000 steps and 20 min brisk",  # two metrics: ambiguous
        "Keep caffeine under 200 mg",
        "No more than 4,000 steps of pottering",  # a cap is never inferred as >=
        "",
    ],
)
def test_anything_less_than_clear_is_none(action: str):
    assert parse_rule(action) is None
