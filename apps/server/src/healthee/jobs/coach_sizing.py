"""How big next week's job may be — a deterministic guard over the model's proposal.

The coach task tells the model how to size the job; this module is the rule IN CODE, so
the number that ships is never the model's say-so. The rule (``COACH_TASK.md``), over the
jobs of the last four weeks the strap could judge:

========================  ===============================================================
done 4 of 4               step up 20 to 25 %
done 2 or 3               repeat the same job (same metric, target, days)
done 0 or 1               shrink to a size a bad week could still finish: 50 to 80 % of it
a missed week repeats     a repeat is the floor of every band but a full step-up
thin data last week       repeat — "not enough data" beats a guess in either direction
========================  ===============================================================

Fewer than four judged weeks cannot earn a step up (it is a repeat) and only shrinks after
two or more weeks with nothing done. Shrinking is bounded below at 50 %: the bar is lowered
in the open and by a stated amount, never silently and never back to zero (the ladder is not
reset). No history at all leaves the size to the model, still bounded by the metric.
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from enum import StrEnum

from healthee.challenges.scales import ROUND_STEP

STEP_UP_LOW = 1.20
STEP_UP_HIGH = 1.25
SHRINK_LOW = 0.50
SHRINK_HIGH = 0.80
FULL_HISTORY = 4
_EPS = 1e-6


class Sizing(StrEnum):
    FIRST = "first"
    STEP_UP = "step_up"
    SAME = "same"
    SHRINK = "shrink"


@dataclass(frozen=True)
class JobWeek:
    """One past job week: days the strap said done, days asked, days it could judge."""

    done_days: int
    days_required: int
    provable_days: int

    @property
    def done(self) -> bool:
        return self.done_days >= self.days_required


@dataclass(frozen=True)
class PrevJob:
    metric: str
    target: float
    days_required: int


@dataclass(frozen=True)
class Allowed:
    """What the model may propose. ``low``/``high`` None means unconstrained (FIRST)."""

    sizing: Sizing
    metric: str | None
    low: float | None
    high: float | None
    days_max: int | None
    reason: str

    def statement(self) -> str:
        """The range, in words, for the retry prompt."""
        if self.sizing is Sizing.FIRST or self.low is None:
            return "No earlier job: choose a target you would finish on a bad week."
        return (
            f"The job must keep metric {self.metric}, with a target between "
            f"{self.low:g} and {self.high:g} and at most {self.days_max} days out of 7. "
            f"Reason: {self.reason}."
        )


def _step(metric: str) -> float:
    return float(ROUND_STEP.get(metric, 1))


def _up(value: float, step: float) -> float:
    return math.ceil(value / step - _EPS) * step


def _down(value: float, step: float) -> float:
    return math.floor(value / step + _EPS) * step


def _band(prev: PrevJob, lo_f: float, hi_f: float) -> tuple[float, float]:
    """Both ends on the metric's human step; never empty, never past the raw ends by a step."""
    step = _step(prev.metric)
    low, high = _up(prev.target * lo_f, step), _down(prev.target * hi_f, step)
    if low > high:
        low = high = round(prev.target * (lo_f + hi_f) / 2 / step) * step
    return low, high


def decide(
    prev: PrevJob | None,
    weeks: list[JobWeek],
    *,
    thin_last_week: bool = False,
    hold: str | None = None,
) -> Allowed:
    """The allowed range for next week's job from the last four judged job weeks."""
    if prev is None:
        return Allowed(Sizing.FIRST, None, None, None, None, "no earlier job")
    recent = weeks[-FULL_HISTORY:]
    done = sum(1 for w in recent if w.done)
    same = Allowed(
        Sizing.SAME, prev.metric, prev.target, prev.target, prev.days_required, "repeat the job"
    )
    if hold:
        return _with_reason(same, hold)
    if thin_last_week:
        return _with_reason(same, "last week had too few readings to judge, so it repeats")
    if len(recent) == FULL_HISTORY and done == FULL_HISTORY:
        low, high = _band(prev, STEP_UP_LOW, STEP_UP_HIGH)
        return Allowed(Sizing.STEP_UP, prev.metric, low, high, prev.days_required,
                       "4 of the last 4 jobs were done: step up 20 to 25 percent")  # fmt: skip
    shrinks = done <= 1 if len(recent) == FULL_HISTORY else (done == 0 and len(recent) >= 2)  # noqa: PLR2004
    if shrinks:
        low, high = _band(prev, SHRINK_LOW, SHRINK_HIGH)
        return Allowed(Sizing.SHRINK, prev.metric, low, high, prev.days_required,
                       f"{done} of the last {len(recent)} jobs were done: shrink it")  # fmt: skip
    return _with_reason(same, f"{done} of the last {len(recent)} jobs were done, so it repeats")


def _with_reason(allowed: Allowed, reason: str) -> Allowed:
    return Allowed(
        allowed.sizing, allowed.metric, allowed.low, allowed.high, allowed.days_max, reason
    )


def violation(allowed: Allowed, metric: str, target: float, days_required: int) -> str | None:
    """Why the proposal is outside ``allowed``, or ``None`` when it fits."""
    if allowed.low is None or allowed.high is None or allowed.days_max is None:
        return None
    if metric != allowed.metric:
        return f"metric {metric} is not the earlier job's {allowed.metric}"
    if target < allowed.low - _EPS or target > allowed.high + _EPS:
        return f"target {target:g} is outside {allowed.low:g} to {allowed.high:g}"
    if allowed.sizing is Sizing.SHRINK:
        too_many = days_required > allowed.days_max
    else:
        too_many = days_required != allowed.days_max
    return f"{days_required} days is not allowed (max {allowed.days_max})" if too_many else None
