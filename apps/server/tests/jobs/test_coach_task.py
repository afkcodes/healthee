"""The coach's output model, task text, shared checks, history and rendering — all pure."""

from __future__ import annotations

import re
from datetime import date
from pathlib import Path

import pytest
from pydantic import ValidationError
from tests.insights._ids import CONTESTED_ID, ESTABLISHED_ID
from tests.jobs._coach_fixtures import answer

from healthee.jobs import coach_checks, coach_kv, coach_task
from healthee.jobs.coach_commitments import Commitment, render_commitments
from healthee.jobs.coach_inputs import job_history
from healthee.jobs.coach_review_view import NO_DATA_REVIEW, no_data_view
from healthee.jobs.coach_task import CoachWeek, sentence_count
from healthee.jobs.coach_weeks import (
    WeekFacts,
    render_current,
    render_recovery,
    render_weeks,
    week_mondays,
    zone_for,
)

_SPEC = Path(__file__).resolve().parents[4] / "design/redesign-2026-10/COACH_TASK.md"


def test_the_task_text_is_the_specs_verbatim() -> None:
    spec = re.search(r"## Task text\n\n```\n(.*?)\n```", _SPEC.read_text(), re.S)
    assert spec is not None
    for part in (coach_task._INTRO, coach_task._WEEKLY, coach_task._VOICE, coach_task._OUTPUT):
        assert part.strip() in spec.group(1) and part.strip() in coach_task.WEEKLY_TASK
    assert coach_task._DAILY.strip() in spec.group(1) and coach_task._DAILY in coach_task.DAILY_TASK
    assert "WEEKLY (Sunday)" not in coach_task.DAILY_TASK


def test_a_valid_answer_parses_and_a_daily_one_needs_no_job() -> None:
    week = CoachWeek.model_validate(answer())
    assert week.job is not None and week.job.metric == "mvpa_min"
    daily = CoachWeek.model_validate(answer(review=None, pattern=None, job=None) | {"job": None})
    assert daily.job is None and daily.review is None


@pytest.mark.parametrize(
    ("field", "text"),
    [
        ("review", "One. Two. Three. Four. Five."),
        ("pattern", "One. Two. Three."),
        ("today", "One. Two. Three."),
        ("rationale", f"One [{ESTABLISHED_ID}]. Two [{ESTABLISHED_ID}]. Three [{ESTABLISHED_ID}]."),
        ("today", "Go now!"),
        ("review", "Nice work \U0001f600 today."),
        ("review", "Ask about your dose of caffeine."),
        ("review", "   "),
    ],
)
def test_sentence_limits_tone_and_safety_are_enforced(field: str, text: str) -> None:
    with pytest.raises(ValidationError):
        CoachWeek.model_validate(answer(**{field: text}))


def test_decimals_and_clock_times_do_not_split_sentences() -> None:
    assert sentence_count("You slept 6.5 hours. Last week 4.2.") == 2


@pytest.mark.parametrize(
    "bad",
    [
        {"research_note_ids": []},
        {"research_note_ids": ["no_such_note_anywhere"]},
        {"rationale": "Walking helps fitness."},  # no inline [note_id]
        {"evidence_grade": 1},
        {"job": {"metric": "not_a_metric"}},
        {"job": {"metric": "caffeine_mg"}},  # the strap cannot check it
        {"job": {"days_required": 8}},
        {"job": {"target": 0}},
        {"job": {"slot": "take a supplement first"}},
    ],
)
def test_citation_grade_metric_and_job_rules(bad: dict) -> None:
    with pytest.raises(ValidationError):
        CoachWeek.model_validate(answer(**bad))


def test_the_grade_is_proved_from_the_notes_not_believed() -> None:
    assert coach_checks.provable_grade(3, [ESTABLISHED_ID]) == 3
    assert coach_checks.provable_grade(2, [ESTABLISHED_ID]) == 2
    assert coach_checks.provable_grade(3, [CONTESTED_ID]) is None  # below Probable: never ships
    assert coach_checks.provable_grade(3, ["no_such_note_anywhere"]) is None  # unknown = rank 0
    assert coach_checks.citation_issue([], "x") and coach_checks.has_banned_phrase("a dose")


def test_recovery_zones_follow_the_spec() -> None:
    assert [zone_for(s) for s in (100, 67, 66, 34, 33, 0)] == [
        "high", "high", "moderate", "moderate", "low", "low",
    ]  # fmt: skip
    assert "41/100, zone moderate" in render_recovery((41, "moderate"))
    assert "no reading" in render_recovery(None) and "0/100" not in render_recovery(None)


def test_week_keys_target_next_week_on_sunday() -> None:
    wed, sun, mon = date(2026, 10, 14), date(2026, 10, 18), date(2026, 10, 19)
    assert coach_kv.week_label(wed) == "2026-W42" and coach_kv.week_label(sun) == "2026-W43"
    assert coach_kv.week_label(mon) == "2026-W43"
    assert coach_kv.key_for_week(sun) == "coach_review:2026-W43"  # the key the ledger reads
    assert coach_kv.week_bounds(sun) == (date(2026, 10, 19), date(2026, 10, 25))
    assert coach_kv.today_key(wed) == "coach_today:2026-10-14"
    assert [m.isoformat() for m in week_mondays(sun)] == [
        "2026-09-21", "2026-09-28", "2026-10-05", "2026-10-12",
    ]  # fmt: skip
    assert week_mondays(wed)[-1] == date(2026, 10, 12)


def _commitment(done: int, provable: int, required: int = 4, status: str = "expired") -> Commitment:
    days: list[tuple[date, str, float | None]] = [
        (date(2026, 10, 1 + i), "done", 9.0) for i in range(done)
    ]
    days += [(date(2026, 10, 1 + done + i), "missed", 1.0) for i in range(provable - done)]
    return Commitment(1, "Walk", "mvpa_min", 10.0, required, date(2026, 10, 1), date(2026, 10, 7),
                      status, True, days)  # fmt: skip


def test_job_history_counts_done_weeks_and_flags_a_thin_last_week() -> None:
    today = date(2026, 10, 18)
    weeks, thin = job_history([_commitment(4, 7), _commitment(1, 7)], today)
    assert [w.done for w in weeks] == [True, False] and not thin
    # 2 judged days of 4 asked, none done: the strap could not tell, so it is not a miss
    weeks, thin = job_history([_commitment(4, 7), _commitment(0, 2)], today)
    assert [w.done for w in weeks] == [True] and thin
    running = _commitment(1, 3, status="active")
    running.adopted_day = date(2026, 10, 15)
    assert job_history([running], today) == ([], False)  # a running job is CURRENT, not history


def test_blocks_say_no_reading_never_zero() -> None:
    monday = date(2026, 10, 12)
    week = WeekFacts(monday, {monday: 3000.0}, {}, {}, 21, 3)
    text = render_weeks([week], date(2026, 10, 14))
    assert "Mon 3,000" in text and "Tue no reading" in text and "Wed no reading" in text
    assert "brisk minutes total no reading" in text and "no reading (0 nights recorded)" in text
    assert "ideas given 21, yeses 3" in text
    job = _commitment(2, 3, status="active")
    assert "no reading" in render_current(job, None, date(2026, 10, 3))
    assert "Days done so far: 2 of 4" in render_current(job, 12.0, date(2026, 10, 3))
    assert "no active job" in render_current(None, None, date(2026, 10, 3))
    assert "no reading" in render_commitments([_commitment(0, 0)]).replace(
        "no days judged", "no reading"
    )


def test_no_data_view_is_a_plain_statement_with_no_job(monkeypatch: pytest.MonkeyPatch) -> None:
    from uuid import UUID

    from healthee.jobs import coach_review_view as view_mod

    monkeypatch.setattr(view_mod, "read_today_line", lambda *_a: None)
    body = no_data_view(UUID(int=1), date(2026, 10, 14))
    assert body["job"] is None and body["review"] == NO_DATA_REVIEW and body["cached"] is False
