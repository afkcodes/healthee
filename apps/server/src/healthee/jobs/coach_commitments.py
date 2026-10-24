"""COMMITMENTS — every job and challenge adopted in the last 8 weeks, day by day.

Reads the stored rows and hands each adopted challenge to ``record_days.challenge_entries``
— the same function the ledger uses — so a verdict here is the ledger's verdict, never a
second opinion. The verdict rule itself is ``challenges.day_verdicts``. Rendering is pure
(:func:`render_commitments`); a day with no reading is written ``no reading``, never 0.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date, timedelta
from uuid import UUID

from healthee.challenges import record_read, series
from healthee.challenges.day_verdicts import Verdict
from healthee.challenges.record_days import challenge_entries, journal_kind
from healthee.challenges.verdict_labels import label_for
from healthee.derive._common import Cur

WINDOW_WEEKS = 8
_DAYS = 7
_KEYS = (
    *("id", "title", "action_text", "metric", "comparator", "target", "floor", "cadence"),
    *("window_days", "days_required", "adopted_day", "ends_day", "completed_day"),
    *("abandoned_day", "status"),
)


@dataclass
class Commitment:
    """One adopted challenge with its per-day verdicts."""

    id: int
    title: str
    metric: str
    target: float
    days_required: int | None
    adopted_day: date
    last_day: date
    status: str
    is_job: bool
    days: list[tuple[date, str, float | None]] = field(default_factory=list)

    @property
    def done_days(self) -> int:
        return sum(1 for _, v, _x in self.days if v == Verdict.DONE)

    @property
    def provable_days(self) -> int:
        judged = (Verdict.DONE, Verdict.PARTIAL, Verdict.MISSED)
        return sum(1 for _, v, _x in self.days if v in judged)


def _rows(cur: Cur, user_id: UUID, tz: str, start: date) -> list[dict]:
    cur.execute(
        "SELECT id, title, action_text, metric, comparator, target_value, floor_value, cadence, "
        "  window_days, days_required, (adopted_at AT TIME ZONE %s)::date, "
        "  (ends_at AT TIME ZONE %s)::date, (completed_at AT TIME ZONE %s)::date, "
        "  (abandoned_at AT TIME ZONE %s)::date, status "
        "FROM challenge WHERE user_id = %s AND adopted_at IS NOT NULL "
        "  AND status = ANY(%s) AND (adopted_at AT TIME ZONE %s)::date >= %s "
        "ORDER BY adopted_at, id",
        (tz, tz, tz, tz, user_id, ["active", "completed", "expired", "abandoned"], tz, start),
    )
    return [dict(zip(_KEYS, row, strict=True)) for row in cur.fetchall()]


def read_commitments(cur: Cur, user_id: UUID, tz: str, today: date) -> list[Commitment]:
    """Every commitment adopted in the 8 weeks to ``today``, with each judged day."""
    out = []
    for ch in _rows(cur, user_id, tz, today - timedelta(weeks=WINDOW_WEEKS)):
        stop = min(today, ch["adopted_day"] + timedelta(days=ch["window_days"] - 1))
        values = series.metric_series(cur, user_id, tz, ch["metric"], ch["adopted_day"], stop)
        kind = journal_kind(ch["metric"])
        journal = (
            record_read.journal_days(cur, user_id, tz, kind, ch["adopted_day"], stop)
            if kind
            else set()
        )
        entries = challenge_entries(ch, values, journal, today, today)
        last = max((e.day for e in entries), default=ch["adopted_day"])
        out.append(
            Commitment(
                id=ch["id"],
                title=ch["action_text"] or ch["title"],
                metric=ch["metric"],
                target=float(ch["target"]),
                days_required=ch["days_required"],
                adopted_day=ch["adopted_day"],
                last_day=last,
                status=ch["status"],
                is_job=ch["days_required"] is not None,
                days=[(e.day, e.verdict.value, e.value) for e in entries],
            )
        )
    return out


def _day_text(metric: str, day: date, verdict: str, value: float | None) -> str:
    measured = label_for(metric, value) if value is not None else None
    detail = f" ({measured})" if measured else (" (no reading)" if verdict == "no_data" else "")
    return f"{day:%a %d %b} {verdict}{detail}"


def render_commitments(items: list[Commitment]) -> str:
    """The COMMITMENTS block."""
    if not items:
        return "COMMITMENTS (last 8 weeks): none adopted."
    lines = ["COMMITMENTS (last 8 weeks; verdicts come from the strap):"]
    for c in items:
        asked = f"{c.days_required} days out of 7" if c.days_required else "daily"
        head = (
            f'- "{c.title}" [{c.metric}] target {label_for(c.metric, c.target)} a day, '
            f"{asked}, started {c.adopted_day:%d %b}, {c.status}; "
            f"done {c.done_days} of {len(c.days)} days:"
        )
        days = "; ".join(_day_text(c.metric, d, v, x) for d, v, x in c.days)
        lines.append(f"{head} {days or 'no days judged yet'}")
    return "\n".join(lines)
