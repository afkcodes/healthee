"""One day's verdict on one promise — pure, so it is testable without a database.

The rule the coach ledger rests on (``design/redesign-2026-10/COACH_TASK.md``, "Product
rules"): a verdict comes from the strap, never from a tap. So a day is only ever ``done``
because a MEASURED value met the target, with exactly one exception — a metric the strap
cannot see at all (light, caffeine) is decided by a journal entry the owner made that day,
and that is ``done`` with no value, because inventing one would be the lie.

========  ===============================================================
done      measured value meets the target (or the journal exception)
partial   target missed, floor met
missed    a reading exists and meets neither
no_data   the strap measures this, but there is no reading that day
uncheckable  the strap cannot measure it and nothing was journalled
========  ===============================================================

``no_data`` and ``missed`` are different states and must never be merged: one says the
owner fell short, the other says we do not know (standards, "no data is not zero").
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date
from enum import StrEnum

from healthee.challenges.metrics import CHALLENGE_METRICS, DerivedSource, WorkoutCountSource


class Verdict(StrEnum):
    """What the strap (or, for unmeasurable things, the journal) says about one day."""

    DONE = "done"
    PARTIAL = "partial"
    MISSED = "missed"
    NO_DATA = "no_data"
    UNCHECKABLE = "uncheckable"


@dataclass(frozen=True)
class DayVerdict:
    """One checked day. ``value`` is ``None`` unless a reading was actually taken."""

    day: date
    verdict: Verdict
    value: float | None
    unit: str | None
    target: float | None
    floor: float | None


def strap_measures(metric: str) -> bool:
    """Whether the strap itself is the sensor for ``metric``.

    Answered from the challenge registry: a device-derived row or a count of detected
    workouts is the strap's; a self-logged total (``ManualEntrySource`` — caffeine,
    alcohol — or its time-windowed slice) is the OWNER's, so the strap has no say.
    A metric the registry does not know is not measured: an unknown rule must never
    be able to produce ``done``.
    """
    entry = CHALLENGE_METRICS.get(metric)
    return entry is not None and isinstance(entry.source, DerivedSource | WorkoutCountSource)


def _meets(value: float, bound: float, comparator: str) -> bool:
    """``value`` satisfies ``bound`` under ``comparator`` (``>=`` or ``<=``)."""
    if comparator == ">=":
        return value >= bound
    if comparator == "<=":
        return value <= bound
    raise ValueError(f"unknown comparator {comparator!r}")


def verdict_for_day(  # noqa: PLR0913 — the rule's inputs, all keyword-only past the value
    value: float | None,
    *,
    target: float,
    comparator: str,
    floor: float | None = None,
    strap_measures: bool = True,
    journal_logged: bool = False,
) -> Verdict:
    """The verdict for one day. See the module docstring for the table."""
    if not strap_measures:
        return Verdict.DONE if journal_logged else Verdict.UNCHECKABLE
    if value is None:
        return Verdict.NO_DATA
    if _meets(value, target, comparator):
        return Verdict.DONE
    if floor is not None and _meets(value, floor, comparator):
        return Verdict.PARTIAL
    return Verdict.MISSED
