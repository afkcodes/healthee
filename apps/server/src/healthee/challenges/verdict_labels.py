"""How a measured value reads in one line — presentation only, never a verdict.

Kept apart from :mod:`healthee.challenges.day_verdicts` so the pure rule stays free of
formatting, and so the wording of "9h34" lives in exactly one place.
"""

from __future__ import annotations

from healthee.challenges.metrics import CHALLENGE_METRICS

_MIN_PER_HOUR = 60

# `steps_total` is registered with an empty unit (a count). The wire wants a word.
_COUNT_UNITS = {"steps_total": "steps", "workouts_week": "workouts"}


def unit_for(metric: str) -> str | None:
    """The unit a value of ``metric`` is quoted in, or ``None`` for an unknown metric."""
    if metric in _COUNT_UNITS:
        return _COUNT_UNITS[metric]
    entry = CHALLENGE_METRICS.get(metric)
    return (entry.unit or None) if entry else None


def label_for(metric: str, value: float | None) -> str | None:
    """``"9h34"``, ``"1,578 steps"``, ``"12 min"`` — or ``None`` when nothing was measured."""
    if value is None:
        return None
    if metric == "tst_min":
        hours, minutes = divmod(round(value), _MIN_PER_HOUR)
        return f"{hours}h{minutes:02d}"
    unit = unit_for(metric)
    number = f"{value:,.0f}" if float(value).is_integer() or abs(value) >= 100 else f"{value:g}"  # noqa: PLR2004
    return f"{number} {unit}" if unit else number
