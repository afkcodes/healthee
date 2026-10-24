"""WEEKS, CURRENT and RECOVERY — the other three input blocks of the weekly coach.

* WEEKS: the last four Mon-Sun weeks (the fourth is this week so far) — steps per day,
  brisk minutes, sleep average with nights recorded, ideas given and yeses. Ideas and
  yeses are read from the ledger's own weeks, so the Coach screen and this prompt quote
  the same numbers.
* CURRENT: the active job, days done so far, and today's value.
* RECOVERY: today's score and zone (67-100 high, 34-66 moderate, 0-33 low).

Every missing value is the words ``no reading`` — never 0. Rendering is pure.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date, timedelta
from uuid import UUID

from healthee.challenges import record, series
from healthee.challenges.record_window import week_start
from healthee.challenges.verdict_labels import label_for
from healthee.derive._common import Cur
from healthee.jobs.coach_commitments import Commitment
from healthee.read.recovery import recovery_freshness, recovery_score_payload
from healthee.read.recovery_guidance import recovery_band

WEEKS_SHOWN = 4
_DAYS = 7
NO_READING = "no reading"
ZONE_LOW = "low"


@dataclass(frozen=True)
class WeekFacts:
    monday: date
    steps: dict[date, float]
    brisk: dict[date, float]
    sleep: dict[date, float]
    ideas: int
    yeses: int


def week_mondays(today: date) -> list[date]:
    """The four Mondays, oldest first, the last being this week's."""
    this = week_start(today)
    return [this - timedelta(weeks=n) for n in range(WEEKS_SHOWN - 1, -1, -1)]


def _in_week(values: dict[date, float], monday: date) -> dict[date, float]:
    return {d: v for d, v in values.items() if monday <= d <= monday + timedelta(days=_DAYS - 1)}


def read_weeks(cur: Cur, user_id: UUID, tz: str, today: date) -> list[WeekFacts]:
    """The four weeks' facts, straight from the owner's series and the ledger's weeks."""
    mondays = week_mondays(today)
    since = mondays[0]
    steps = series.metric_series(cur, user_id, tz, "steps_total", since, today)
    brisk = series.metric_series(cur, user_id, tz, "mvpa_min", since, today)
    sleep = series.metric_series(cur, user_id, tz, "tst_min", since, today)
    ledger = {w["from"]: w for w in record.build_ledger(cur, user_id, tz, "month")["weeks"]}
    return [
        WeekFacts(
            m,
            _in_week(steps, m),
            _in_week(brisk, m),
            _in_week(sleep, m),
            ledger.get(m, {}).get("ideas_given", 0),
            ledger.get(m, {}).get("yeses", 0),
        )
        for m in mondays
    ]


def _week_text(w: WeekFacts, today: date) -> str:
    days = [w.monday + timedelta(days=i) for i in range(_DAYS)]
    shown = [d for d in days if d <= today]
    steps = ", ".join(
        f"{d:%a} {w.steps[d]:,.0f}" if d in w.steps else f"{d:%a} {NO_READING}" for d in shown
    )
    brisk = (
        f"{sum(w.brisk.values()):.0f} min over {len(w.brisk)} days read" if w.brisk else NO_READING
    )
    sleep = (
        f"{label_for('tst_min', sum(w.sleep.values()) / len(w.sleep))} average, "
        f"{len(w.sleep)} nights recorded"
        if w.sleep
        else f"{NO_READING} (0 nights recorded)"
    )
    state = "complete" if shown[-1] == days[-1] and today > days[-1] else f"so far, to {today:%a}"
    return (
        f"- {days[0]:%d %b} to {days[-1]:%d %b} ({state}): steps per day {steps}; "
        f"brisk minutes total {brisk}; sleep {sleep}; ideas given {w.ideas}, yeses {w.yeses}."
    )


def render_weeks(weeks: list[WeekFacts], today: date) -> str:
    """The WEEKS block."""
    return "\n".join(["WEEKS (Mon to Sun):", *(_week_text(w, today) for w in weeks)])


def zone_for(score: float) -> str:
    """The recovery zone: 67-100 high, 34-66 moderate, 0-33 low. The ONE mapping."""
    return recovery_band(score)


def read_recovery(cur: Cur, user_id: UUID, tz: str) -> tuple[int, str] | None:
    """Today's recovery score and zone, or ``None`` when there is no reading for today."""
    payload = recovery_score_payload(cur, user_id, tz)
    if not payload or recovery_freshness(payload, tz):
        return None
    return int(payload["recovery"]), zone_for(payload["recovery"])


def render_recovery(found: tuple[int, str] | None) -> str:
    """The RECOVERY block."""
    if found is None:
        return f"RECOVERY today: {NO_READING} (no score for today yet)."
    score, zone = found
    return f"RECOVERY today: {score}/100, zone {zone} (67-100 high, 34-66 moderate, 0-33 low)."


def render_current(job: Commitment | None, today_value: float | None, today: date) -> str:
    """The CURRENT block: the active job, days done so far, today's value."""
    if job is None:
        return "CURRENT: no active job."
    asked = job.days_required or _DAYS
    value = label_for(job.metric, today_value) if today_value is not None else NO_READING
    return (
        f'CURRENT: "{job.title}" [{job.metric}], target {label_for(job.metric, job.target)} a '
        f"day, {asked} days out of 7; started {job.adopted_day:%a %d %b}. Days done so far: "
        f"{job.done_days} of {asked}. Today ({today:%a %d %b}) so far: {value}."
    )
