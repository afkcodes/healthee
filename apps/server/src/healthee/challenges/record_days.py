"""Turn stored promises into checked days — pure, fed by already-read rows and series.

A challenge yields one entry per day it ran; a legacy recommendation yields one on the
day it was given. Both go through :func:`day_verdicts.verdict_for_day`, so there is
exactly one place a day becomes ``done``.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date, timedelta

from healthee.challenges.day_verdicts import Verdict, strap_measures, verdict_for_day
from healthee.challenges.metrics import CHALLENGE_METRICS, ManualEntrySource
from healthee.challenges.rec_rules import RecRule
from healthee.challenges.verdict_labels import label_for, unit_for

_DAILY = "daily"
# A day that is not over cannot be a miss: a verdict of these on TODAY is withheld.
_UNSETTLED_TODAY = frozenset({Verdict.MISSED, Verdict.NO_DATA})


@dataclass(frozen=True)
class LedgerEntry:
    """One checked day of one yes, as the ledger lists it."""

    day: date
    title: str
    verdict: Verdict
    value: float | None
    unit: str | None
    label: str | None
    source: str  # 'challenge' | 'recommendation'
    ref_id: int


def last_day(ch: dict, today: date, window_end: date) -> date:
    """The last local day this challenge is judged on.

    Capped by the window, by today, by the ``window_days`` it ran for (and its stored
    ``ends_at``), and by the day it stopped early — completed or abandoned: days after
    that were not part of the promise, so they are not misses.
    """
    caps = [today, window_end, ch["adopted_day"] + timedelta(days=ch["window_days"] - 1)]
    caps += [d for d in (ch["ends_day"], ch["completed_day"], ch["abandoned_day"]) if d]
    return min(caps)


def journal_kind(metric: str) -> str | None:
    """The ``manual_entry.kind`` that stands in for the strap on ``metric``, if any."""
    entry = CHALLENGE_METRICS.get(metric)
    return entry.source.kind if entry and isinstance(entry.source, ManualEntrySource) else None


def _entry(  # noqa: PLR0913 — one checked day states each field it carries
    day: date, title: str, verdict: Verdict, metric: str, value: float | None, source: str, ref: int
) -> LedgerEntry:
    shown = value if verdict != Verdict.UNCHECKABLE else None
    unit = unit_for(metric) if shown is not None else None
    return LedgerEntry(day, title, verdict, shown, unit, label_for(metric, shown), source, ref)


def challenge_entries(
    ch: dict, values: dict[date, float], journal: set[date], today: date, window_end: date
) -> list[LedgerEntry]:
    """Every judged day of one adopted challenge.

    Only a ``daily`` cadence has a per-day promise. A ``weekly``/``total`` target is a
    period sum, so comparing one day against it would call every day a miss; those days
    are ``uncheckable`` here rather than scored against a number they were never asked to
    reach (the period's verdict lives in the outcome ledger).
    """
    title = ch["action_text"] or ch["title"]
    measured = strap_measures(ch["metric"])
    daily = ch["cadence"] == _DAILY
    out = []
    day = ch["adopted_day"]
    while day <= last_day(ch, today, window_end):
        value = values.get(day) if measured and daily else None
        if daily:
            verdict = verdict_for_day(
                value,
                target=ch["target"],
                comparator=ch["comparator"],
                floor=ch["floor"],
                strap_measures=measured,
                journal_logged=day in journal,
            )
        else:
            verdict = Verdict.UNCHECKABLE
        if not (day == today and verdict in _UNSETTLED_TODAY):
            out.append(_entry(day, title, verdict, ch["metric"], value, "challenge", ch["id"]))
        day += timedelta(days=1)
    return out


def recommendation_entry(
    rec: dict, rule: RecRule | None, values: dict[date, float], today: date
) -> LedgerEntry | None:
    """The one checked day of an adopted legacy recommendation (``None`` while unsettled).

    Without a parseable ``rule`` the yes is ``uncheckable`` — never ``done``.
    """
    if rule is None:
        return LedgerEntry(
            rec["day"], rec["action"], Verdict.UNCHECKABLE, None, None, None, "recommendation",
            rec["id"],
        )  # fmt: skip
    value = values.get(rec["day"])
    verdict = verdict_for_day(value, target=rule.target, comparator=rule.comparator)
    if rec["day"] == today and verdict in _UNSETTLED_TODAY:
        return None
    return _entry(
        rec["day"], rec["action"], verdict, rule.metric, value, "recommendation", rec["id"]
    )
