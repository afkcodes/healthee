"""The verified coach ledger — every yes the owner gave, checked against the strap.

``build_ledger`` reads what was stored and hands it to :func:`assemble`, which is pure.
The sources of a yes:

* every day of every challenge adopted in the window (``record_days.challenge_entries``);
* every adopted LEGACY recommendation, checked only when its sentence states one metric
  and one number (``rec_rules``), otherwise ``uncheckable``.

``yeses`` is the number of listed entries (one per checked day), ``ideas_given`` the
recommendation rows dated in the window. Nothing here can make a day ``done`` — that is
``day_verdicts.verdict_for_day``'s one rule, reached through ``record_days``.
"""

from __future__ import annotations

from collections import Counter
from datetime import date, timedelta
from typing import Any
from uuid import UUID

from healthee.challenges import record_read, series
from healthee.challenges.day_verdicts import Verdict
from healthee.challenges.rec_rules import parse_rule
from healthee.challenges.record_days import (
    LedgerEntry,
    challenge_entries,
    journal_kind,
    recommendation_entry,
)
from healthee.challenges.record_window import (
    DAYS_PER_WEEK,
    Window,
    week_start,
    week_starts,
    window_bounds,
)
from healthee.core.tenancy import user_today
from healthee.derive._common import Cur

_PROVABLE = (Verdict.DONE, Verdict.PARTIAL, Verdict.MISSED)


def _wire(entry: LedgerEntry) -> dict[str, Any]:
    return {
        "date": entry.day,
        "title": entry.title,
        "verdict": entry.verdict.value,
        "measured": {"value": entry.value, "unit": entry.unit, "label": entry.label},
        "source": entry.source,
        "ref_id": entry.ref_id,
    }


def _week(monday: date, entries: list[LedgerEntry], ideas: dict[date, int]) -> dict[str, Any]:
    sunday = monday + timedelta(days=DAYS_PER_WEEK - 1)
    mine = sorted(
        (e for e in entries if week_start(e.day) == monday),
        key=lambda e: (e.day, e.ref_id),
        reverse=True,
    )
    return {
        "from": monday,
        "to": sunday,
        "ideas_given": sum(n for d, n in ideas.items() if monday <= d <= sunday),
        "yeses": len(mine),
        "entries": [_wire(e) for e in mine],
    }


def assemble(
    window: str,
    start: date,
    end: date,
    entries: list[LedgerEntry],
    ideas: dict[date, int],
    pattern: str | None,
) -> dict[str, Any]:
    """The ledger payload from already-checked entries. Pure."""
    counts = Counter(e.verdict for e in entries)
    totals = {v.value: counts.get(v, 0) for v in Verdict}
    return {
        "window": window,
        "from": start,
        "to": end,
        "ideas_given": sum(ideas.values()),
        "yeses": len(entries),
        "totals": totals,
        "done_rate": {"done": counts[Verdict.DONE], "provable": sum(counts[v] for v in _PROVABLE)},
        "weeks": [_week(m, entries, ideas) for m in week_starts(start, end)],
        "pattern": pattern,
    }


def _challenge_entries(
    cur: Cur, user_id: UUID, tz: str, start: date, end: date, today: date
) -> list[LedgerEntry]:
    out: list[LedgerEntry] = []
    for ch in record_read.challenges_adopted(cur, user_id, tz, start, end):
        stop = min(today, end)
        values = series.metric_series(cur, user_id, tz, ch["metric"], ch["adopted_day"], stop)
        kind = journal_kind(ch["metric"])
        journal = (
            record_read.journal_days(cur, user_id, tz, kind, ch["adopted_day"], stop)
            if kind
            else set()
        )
        out += challenge_entries(ch, values, journal, today, end)
    return out


def _rec_series(
    cur: Cur, user_id: UUID, tz: str, recs: list[dict], rules: dict, today: date
) -> dict[str, dict[date, float]]:
    """One daily series per metric a parsed rule needs, from its earliest rec day."""
    since: dict[str, date] = {}
    for rec in recs:
        rule = rules[rec["id"]]
        if rule:
            held = since.get(rule.metric)
            since[rule.metric] = rec["day"] if held is None else min(rec["day"], held)
    return {
        metric: series.metric_series(cur, user_id, tz, metric, day, today)
        for metric, day in since.items()
    }


def _recommendation_entries(
    cur: Cur, user_id: UUID, tz: str, start: date, end: date, today: date
) -> list[LedgerEntry]:
    recs = record_read.recommendations_adopted(cur, user_id, start, min(end, today))
    rules = {r["id"]: parse_rule(r["action"]) for r in recs}
    by_metric = _rec_series(cur, user_id, tz, recs, rules, today)
    out = []
    for rec in recs:
        rule = rules[rec["id"]]
        values = by_metric[rule.metric] if rule else {}
        entry = recommendation_entry(rec, rule, values, today)
        if entry is not None:
            out.append(entry)
    return out


def build_ledger(cur: Cur, user_id: UUID, tz: str, window: Window) -> dict[str, Any]:
    """The ledger for ``window``, as the owner's own local calendar sees it."""
    today = user_today(tz)
    first = record_read.first_day(cur, user_id, tz) if window == "all" else None
    start, end = window_bounds(window, today, first)
    entries = _challenge_entries(cur, user_id, tz, start, end, today)
    entries += _recommendation_entries(cur, user_id, tz, start, end, today)
    ideas = record_read.ideas_by_day(cur, user_id, start, min(end, today))
    return assemble(window, start, end, entries, ideas, record_read.latest_pattern(cur, user_id))
