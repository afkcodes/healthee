"""The ledger's calendar — which days a window covers and how they group into weeks.

Pure: every function takes the owner's ``today`` as an argument, so nothing here reads a
clock and every boundary is testable. Weeks are ISO Mon to Sun, matching the Coach screen
("12 to 18 Oct"), and a week is always shown whole even when the window starts mid-week.
"""

from __future__ import annotations

from datetime import date, timedelta
from typing import Literal

Window = Literal["week", "month", "all"]

MONTH_DAYS = 28
DAYS_PER_WEEK = 7


def week_start(day: date) -> date:
    """The Monday of ``day``'s ISO week."""
    return day - timedelta(days=day.weekday())


def window_bounds(window: Window, today: date, first_day: date | None) -> tuple[date, date]:
    """``(from, to)`` inclusive for ``window``, as of the owner's ``today``.

    ``week`` is the Mon-Sun week containing today (so ``to`` may be a future Sunday),
    ``month`` is the 28 days ending today, ``all`` runs from ``first_day`` (the first
    idea or challenge; today when there is none) to today.
    """
    if window == "week":
        start = week_start(today)
        return start, start + timedelta(days=DAYS_PER_WEEK - 1)
    if window == "month":
        return today - timedelta(days=MONTH_DAYS - 1), today
    return min(first_day or today, today), today


def week_starts(start: date, end: date) -> list[date]:
    """The Mondays of every ISO week touching ``[start, end]``, newest first."""
    mondays = []
    monday = week_start(start)
    while monday <= end:
        mondays.append(monday)
        monday += timedelta(days=DAYS_PER_WEEK)
    return mondays[::-1]


def review_key(day: date) -> str:
    """The ``kv`` key a weekly review is stored under: ``coach_review:{ISOYEAR}-W{WW}``."""
    iso = day.isocalendar()
    return f"coach_review:{iso.year}-W{iso.week:02d}"
