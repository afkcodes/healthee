"""The sizing guard — all four bands, bounded, and never silently lower the bar."""

from __future__ import annotations

import pytest
from tests.jobs._coach_fixtures import prev_job, weeks

from healthee.jobs.coach_sizing import Sizing, decide, violation


def test_four_of_four_steps_up_twenty_to_twenty_five_percent() -> None:
    allowed = decide(prev_job(20), weeks(True, True, True, True))
    assert allowed.sizing is Sizing.STEP_UP
    assert (allowed.low, allowed.high) == (25.0, 25.0)  # 20 to 25 % of 20, on the 5-minute step
    assert violation(allowed, "mvpa_min", 25, 4) is None
    assert violation(allowed, "mvpa_min", 20, 4)  # a repeat is not a step up
    assert violation(allowed, "mvpa_min", 26, 4)  # nor is a leap


@pytest.mark.parametrize("done", [(True, True, False, False), (True, True, True, False)])
def test_two_or_three_of_four_repeats_exactly(done: tuple[bool, ...]) -> None:
    allowed = decide(prev_job(20), weeks(*done))
    assert allowed.sizing is Sizing.SAME and allowed.low == allowed.high == 20.0
    assert violation(allowed, "mvpa_min", 20, 4) is None
    assert violation(allowed, "mvpa_min", 18, 4)  # lowering the bar silently is refused
    assert violation(allowed, "mvpa_min", 20, 3)  # and so is changing the days


@pytest.mark.parametrize("done", [(False, False, False, False), (True, False, False, False)])
def test_zero_or_one_of_four_shrinks_but_never_below_half(done: tuple[bool, ...]) -> None:
    allowed = decide(prev_job(20), weeks(*done))
    assert allowed.sizing is Sizing.SHRINK and (allowed.low, allowed.high) == (10.0, 15.0)
    assert violation(allowed, "mvpa_min", 15, 3) is None  # fewer days is allowed when shrinking
    assert violation(allowed, "mvpa_min", 5, 4)  # collapsing the ladder is not
    assert violation(allowed, "mvpa_min", 20, 4)  # and a shrink must shrink


def test_a_missed_week_repeats_when_history_is_short() -> None:
    assert decide(prev_job(), weeks(True, False)).sizing is Sizing.SAME
    assert decide(prev_job(), weeks(False)).sizing is Sizing.SAME  # one miss is a repeat
    assert decide(prev_job(), weeks(False, False)).sizing is Sizing.SHRINK  # two is not
    assert decide(prev_job(), weeks(True, True, True)).sizing is Sizing.SAME  # no step up on 3


def test_thin_data_or_a_running_job_repeats_whatever_the_history() -> None:
    assert (
        decide(prev_job(), weeks(True, True, True, True), thin_last_week=True).sizing is Sizing.SAME
    )
    held = decide(prev_job(), weeks(False, False, False, False), hold="a job is running")
    assert held.sizing is Sizing.SAME and held.reason == "a job is running"


def test_no_history_leaves_the_size_to_the_model_but_a_metric_change_is_refused_later() -> None:
    first = decide(None, [])
    assert first.sizing is Sizing.FIRST and violation(first, "steps_total", 3000, 5) is None
    other = decide(prev_job(), weeks(True, True))
    assert violation(other, "steps_total", 20, 4)  # a different metric is not a repeat


def test_the_band_snaps_to_the_metrics_own_step_and_is_never_empty() -> None:
    from healthee.jobs.coach_sizing import PrevJob

    steps = decide(PrevJob("steps_total", 4000.0, 5), weeks(True, True, True, True))
    assert steps.low is not None and steps.high is not None
    assert 4000 < steps.low <= steps.high <= 5000 and steps.low % 250 == 0
    tiny = decide(PrevJob("mvpa_min", 5.0, 3), weeks(True, True, True, True))
    assert tiny.low is not None and tiny.low >= 5.0
