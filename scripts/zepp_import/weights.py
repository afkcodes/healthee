"""Body weight: what Zepp's scale log holds, and what to do so Healthee matches it.

The owner's rule, applied per local day: **Zepp is the reference.**

* A day Zepp weighed and Healthee did not gets Zepp's reading, at Zepp's own time.
* A day both weighed, with different numbers, ends on Zepp's number. When Healthee's
  reading is its newest one and later than Zepp's, that row is corrected in place (the
  server upserts a weight on its instant, `read/logs.py::record_log`); otherwise Zepp's
  reading is added and, being later, becomes the day's.
* A day only Healthee weighed is left alone, so a weight typed into the app after the
  last weigh-in on the scale stays the newest.

One reading per day is compared: the LAST of each local day on both sides, because that
is all Healthee's history read answers with (`read/history.py::_weight_points`).
Pure: nothing here touches the network.
"""

from __future__ import annotations

from collections.abc import Iterable, Mapping
from dataclasses import dataclass
from datetime import datetime, tzinfo

WEIGHT_PATH = "/users/{user_id}/members/-1/weightRecords"
# `core/bounds.py::assert_plausible_weight_kg` refuses outside this; a scale reading
# outside it is a misread, not a person.
KG_LO, KG_HI = 20.0, 300.0
SAME_KG = 0.05  # Zepp stores one decimal; Healthee two
_MS_THRESHOLD = 10**11  # an epoch above this is in milliseconds

ADD, CORRECT, THERE, SENT = "add", "correct", "already there", "sent before"


@dataclass(frozen=True)
class Weighing:
    ts_s: int
    kg: float


@dataclass(frozen=True)
class HealtheeWeights:
    """Healthee's last reading of each local day, and its newest reading with its instant."""

    by_day: Mapping[str, float]
    newest: Weighing | None


@dataclass(frozen=True)
class WeightStep:
    zepp: Weighing
    day: str
    verdict: str
    write_ts_s: int  # where the reading is written: Zepp's instant, or the row it corrects
    healthee_kg: float | None


def read_weighing(item: object) -> Weighing | None:
    """One `weightRecords` item, or None when it is not a readable body weight."""
    if not isinstance(item, dict):
        return None
    stamp, summary = item.get("generatedTime"), item.get("summary")
    if not isinstance(stamp, int) or isinstance(stamp, bool) or not isinstance(summary, dict):
        return None
    kg = summary.get("weight")
    if not isinstance(kg, (int, float)) or isinstance(kg, bool) or not KG_LO <= kg <= KG_HI:
        return None
    ts_s = stamp // 1000 if stamp > _MS_THRESHOLD else stamp
    return Weighing(ts_s=ts_s, kg=round(float(kg), 2)) if ts_s > 0 else None


def local_day(ts_s: int, zone: tzinfo) -> str:
    return datetime.fromtimestamp(ts_s, zone).date().isoformat()


def last_of_each_day(weighings: Iterable[Weighing], zone: tzinfo) -> dict[str, Weighing]:
    days: dict[str, Weighing] = {}
    for weighing in sorted(weighings, key=lambda w: w.ts_s):
        days[local_day(weighing.ts_s, zone)] = weighing
    return days


def plan(
    zepp: Iterable[Weighing],
    healthee: HealtheeWeights,
    zone: tzinfo,
    sent: Mapping[int, float],
) -> list[WeightStep]:
    """One step per day Zepp weighed, newest first. `sent` is what earlier runs wrote."""
    newest = healthee.newest
    newest_day = local_day(newest.ts_s, zone) if newest else None
    steps: list[WeightStep] = []
    for day, last in sorted(last_of_each_day(zepp, zone).items(), reverse=True):
        stored = healthee.by_day.get(day)
        if stored is not None and abs(stored - last.kg) < SAME_KG:
            verdict, at = THERE, last.ts_s
        elif newest and day == newest_day and newest.ts_s > last.ts_s:
            verdict, at = CORRECT, newest.ts_s
        elif sent.get(last.ts_s) is not None and abs(sent[last.ts_s] - last.kg) < SAME_KG:
            # Written before and still not the day's last: Healthee holds a later reading
            # that day which this tool cannot address. Writing again would change nothing.
            verdict, at = SENT, last.ts_s
        else:
            verdict, at = ADD, last.ts_s
        steps.append(WeightStep(last, day, verdict, at, stored))
    return steps


def to_write(steps: Iterable[WeightStep]) -> list[WeightStep]:
    return [step for step in steps if step.verdict in (ADD, CORRECT)]


def describe(step: WeightStep) -> str:
    """One plan line, such as `26 Sep  80.5 kg  add`."""
    when = datetime.fromisoformat(step.day).strftime("%d %b")
    reading = f"{step.zepp.kg:.1f} kg"
    if step.verdict == CORRECT:
        return f"{when}  {reading}  correct (Healthee has {step.healthee_kg:.1f})"
    if step.verdict == ADD and step.healthee_kg is not None:
        return f"{when}  {reading}  add (Healthee has {step.healthee_kg:.1f})"
    if step.verdict == SENT:
        return f"{when}  {reading}  sent before; Healthee has a later reading that day"
    return f"{when}  {reading}  {step.verdict}"
