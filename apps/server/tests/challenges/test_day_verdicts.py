"""The verdict rule, pure — it always runs, with or without a database."""

from __future__ import annotations

import pytest

from healthee.challenges.day_verdicts import Verdict, strap_measures, verdict_for_day

_UP = {"target": 6000.0, "comparator": ">=", "floor": 3000.0}
_DOWN = {"target": 200.0, "comparator": "<=", "floor": 300.0}


@pytest.mark.parametrize(
    ("value", "rule", "expected"),
    [
        (6000.0, _UP, Verdict.DONE),  # exactly the target counts
        (9000.0, _UP, Verdict.DONE),
        (3000.0, _UP, Verdict.PARTIAL),  # exactly the floor counts
        (4500.0, _UP, Verdict.PARTIAL),
        (1578.0, _UP, Verdict.MISSED),
        (200.0, _DOWN, Verdict.DONE),  # a cap: at or under
        (250.0, _DOWN, Verdict.PARTIAL),
        (301.0, _DOWN, Verdict.MISSED),
    ],
)
def test_measured_value_against_target_and_floor(value: float, rule: dict, expected: Verdict):
    assert verdict_for_day(value, **rule) == expected


def test_without_a_floor_a_shortfall_is_missed_never_partial():
    assert verdict_for_day(5999.0, target=6000.0, comparator=">=") == Verdict.MISSED


def test_no_reading_is_no_data_not_missed():
    assert verdict_for_day(None, **_UP) == Verdict.NO_DATA


def test_zero_is_a_reading_and_can_be_missed():
    assert verdict_for_day(0.0, **_UP) == Verdict.MISSED


def test_unmeasured_by_the_strap_is_uncheckable_without_a_journal_entry():
    assert verdict_for_day(None, **_UP, strap_measures=False) == Verdict.UNCHECKABLE


def test_a_journal_entry_decides_for_what_the_strap_cannot_see():
    got = verdict_for_day(None, **_UP, strap_measures=False, journal_logged=True)
    assert got == Verdict.DONE


def test_a_value_the_strap_did_not_take_never_counts_for_an_unmeasured_metric():
    # A stray number (e.g. a zero-filled manual total) must not become a verdict.
    got = verdict_for_day(99999.0, **_UP, strap_measures=False, journal_logged=False)
    assert got == Verdict.UNCHECKABLE


def test_journal_flag_is_ignored_when_the_strap_does_measure():
    # No reading + a journal entry on a strap metric is still no data: a tap is not proof.
    assert verdict_for_day(None, **_UP, strap_measures=True, journal_logged=True) == Verdict.NO_DATA


@pytest.mark.parametrize("value", [None, 0.0, 10.0, 6000.0])
@pytest.mark.parametrize("journal", [True, False])
def test_done_requires_a_measured_value_or_the_journal_exception(value, journal: bool):
    got = verdict_for_day(value, **_UP, strap_measures=True, journal_logged=journal)
    if got == Verdict.DONE:
        assert value is not None and value >= _UP["target"]


def test_unknown_comparator_raises():
    with pytest.raises(ValueError, match="comparator"):
        verdict_for_day(1.0, target=1.0, comparator="==")


@pytest.mark.parametrize("metric", ["steps_total", "mvpa_min", "tst_min", "workouts_week", "sri"])
def test_the_strap_measures_its_own_metrics(metric: str):
    assert strap_measures(metric)


@pytest.mark.parametrize("metric", ["caffeine_mg", "alcohol_units", "not_a_metric"])
def test_the_strap_does_not_measure_what_the_owner_logs_or_what_is_unknown(metric: str):
    assert not strap_measures(metric)
