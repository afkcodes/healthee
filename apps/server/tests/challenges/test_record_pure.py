"""The ledger's calendar, entry building and assembly — pure, always runs."""

from __future__ import annotations

from datetime import date

import pytest

from healthee.challenges.day_verdicts import Verdict
from healthee.challenges.rec_rules import RecRule
from healthee.challenges.record import assemble
from healthee.challenges.record_days import (
    LedgerEntry,
    challenge_entries,
    last_day,
    recommendation_entry,
)
from healthee.challenges.record_window import review_key, week_start, week_starts, window_bounds
from healthee.challenges.verdict_labels import label_for

TODAY = date(2026, 10, 18)  # a Sunday


def _ch(**kw) -> dict:
    base = {
        "id": 1, "title": "Walk", "action_text": None, "metric": "steps_total",
        "comparator": ">=", "target": 6000.0, "floor": 3000.0, "cadence": "daily",
        "window_days": 7, "adopted_day": date(2026, 10, 12), "ends_day": date(2026, 10, 19),
        "completed_day": None, "abandoned_day": None,
    } | kw  # fmt: skip
    return base


def test_windows():
    assert window_bounds("week", TODAY, None) == (date(2026, 10, 12), date(2026, 10, 18))
    mid = date(2026, 10, 14)
    assert window_bounds("week", mid, None) == (date(2026, 10, 12), date(2026, 10, 18))
    assert window_bounds("month", TODAY, None) == (date(2026, 9, 21), TODAY)
    assert window_bounds("all", TODAY, date(2026, 8, 3)) == (date(2026, 8, 3), TODAY)
    assert window_bounds("all", TODAY, None) == (TODAY, TODAY)


def test_weeks_are_whole_mon_sun_newest_first():
    got = week_starts(date(2026, 9, 21), TODAY)
    assert got[0] == date(2026, 10, 12)
    assert got[-1] == week_start(date(2026, 9, 21)) == date(2026, 9, 21)
    assert len(got) == 4
    assert week_starts(date(2026, 9, 20), TODAY)[-1] == date(2026, 9, 14)


def test_review_key_uses_the_iso_year():
    assert review_key(date(2026, 10, 18)) == "coach_review:2026-W42"
    assert review_key(date(2027, 1, 1)) == "coach_review:2026-W53"


def test_challenge_days_one_per_day_and_verdicts_from_values():
    values = {date(2026, 10, 12): 7000.0, date(2026, 10, 13): 3500.0, date(2026, 10, 14): 100.0}
    got = challenge_entries(_ch(), values, set(), TODAY, TODAY)
    assert [e.day.day for e in got] == [
        12,
        13,
        14,
        15,
        16,
        17,
    ]  # 18 is today, unfinished, no reading yet
    assert [e.verdict for e in got[:4]] == [
        Verdict.DONE, Verdict.PARTIAL, Verdict.MISSED, Verdict.NO_DATA,
    ]  # fmt: skip
    assert got[0].label == "7,000 steps" and got[3].value is None


def test_todays_unfinished_day_is_not_called_a_miss():
    ch = _ch(adopted_day=TODAY, ends_day=None)
    assert challenge_entries(ch, {TODAY: 100.0}, set(), TODAY, TODAY) == []
    done = challenge_entries(ch, {TODAY: 9000.0}, set(), TODAY, TODAY)
    assert [e.verdict for e in done] == [Verdict.DONE]


def test_days_stop_at_abandon_completion_or_the_window_length():
    assert last_day(_ch(abandoned_day=date(2026, 10, 14)), TODAY, TODAY) == date(2026, 10, 14)
    assert last_day(_ch(completed_day=date(2026, 10, 16)), TODAY, TODAY) == date(2026, 10, 16)
    assert last_day(_ch(ends_day=None), date(2026, 11, 30), date(2026, 11, 30)) == date(
        2026, 10, 18
    )


def test_unmeasured_metric_is_uncheckable_unless_journalled_and_never_has_a_value():
    ch = _ch(metric="caffeine_mg", comparator="<=", target=200.0, floor=None, window_days=2)
    got = challenge_entries(ch, {date(2026, 10, 12): 999.0}, {date(2026, 10, 13)}, TODAY, TODAY)
    assert [e.verdict for e in got] == [Verdict.UNCHECKABLE, Verdict.DONE]
    assert all(e.value is None and e.label is None for e in got)


def test_a_non_daily_cadence_is_not_scored_per_day():
    got = challenge_entries(
        _ch(cadence="weekly"), {date(2026, 10, 12): 99999.0}, set(), TODAY, TODAY
    )
    assert {e.verdict for e in got} == {Verdict.UNCHECKABLE}


def test_recommendation_without_a_rule_is_uncheckable():
    rec = {"id": 5, "day": date(2026, 10, 8), "action": "Earlier bedtime tonight"}
    entry = recommendation_entry(rec, None, {date(2026, 10, 8): 1.0}, TODAY)
    assert entry is not None and entry.verdict == Verdict.UNCHECKABLE and entry.value is None


def test_recommendation_with_a_rule_is_checked_against_the_strap():
    rec = {"id": 5, "day": date(2026, 10, 8), "action": "Get 8 hours of sleep"}
    rule = RecRule("tst_min", ">=", 480.0)
    hit = recommendation_entry(rec, rule, {date(2026, 10, 8): 574.0}, TODAY)
    assert hit is not None and hit.verdict == Verdict.DONE and hit.label == "9h34"
    miss = recommendation_entry(rec, rule, {date(2026, 10, 8): 343.0}, TODAY)
    assert miss is not None and miss.verdict == Verdict.MISSED
    none = recommendation_entry(rec, rule, {}, TODAY)
    assert none is not None and none.verdict == Verdict.NO_DATA


@pytest.mark.parametrize(("value", "text"), [(574.0, "9h34"), (60.0, "1h00")])
def test_sleep_label(value: float, text: str):
    assert label_for("tst_min", value) == text


def test_assemble_counts_groups_and_rates():
    def e(day: int, verdict: Verdict, ref: int) -> LedgerEntry:
        return LedgerEntry(date(2026, 10, day), "t", verdict, None, None, None, "challenge", ref)

    entries = [
        e(14, Verdict.DONE, 1), e(15, Verdict.MISSED, 1), e(8, Verdict.PARTIAL, 2),
        e(9, Verdict.NO_DATA, 2), e(10, Verdict.UNCHECKABLE, 3),
    ]  # fmt: skip
    out = assemble("month", date(2026, 9, 20), TODAY, entries, {date(2026, 10, 13): 3}, "p")
    assert out["yeses"] == 5 and out["ideas_given"] == 3 and out["pattern"] == "p"
    assert out["totals"] == {"done": 1, "partial": 1, "missed": 1, "no_data": 1, "uncheckable": 1}
    assert out["done_rate"] == {"done": 1, "provable": 3}
    newest, older = out["weeks"][0], out["weeks"][1]
    assert (newest["from"], newest["to"]) == (date(2026, 10, 12), date(2026, 10, 18))
    assert newest["yeses"] == 2 and newest["ideas_given"] == 3
    assert [x["date"].day for x in newest["entries"]] == [15, 14]  # newest day first
    assert older["yeses"] == 3
    assert len(out["weeks"]) == 5  # empty weeks are listed too ("No yeses this week")


def test_assemble_empty_is_honest_zeroes():
    out = assemble("week", date(2026, 10, 12), TODAY, [], {}, None)
    assert out["yeses"] == 0 and out["done_rate"] == {"done": 0, "provable": 0}
    assert out["pattern"] is None and len(out["weeks"]) == 1
