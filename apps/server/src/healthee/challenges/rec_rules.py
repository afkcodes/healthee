"""A best-effort rule for a LEGACY recommendation, parsed from its action text.

Recommendations predate challenges: they carry prose and no metric, so the only way to
check one against the strap is to read a rule out of the sentence — and only when the
sentence states one unambiguously. The bar is deliberately high; everything below it is
``None`` and the ledger shows the yes as ``uncheckable`` rather than guess:

* one metric and one number ("Walk toward 6,000 steps", "20 min brisk walk",
  "Full 8 hours of sleep") — two different metrics in one sentence is a refusal;
* never a cap ("under", "no more than", "at most"): the direction is then not ``>=`` and
  inferring it from prose is how a ledger invents a verdict;
* a range ("15 to 20 min") reads as its LOWER bound, the number the owner was asked to
  reach at minimum.
"""

from __future__ import annotations

import re
from dataclasses import dataclass


@dataclass(frozen=True)
class RecRule:
    """The metric rule a recommendation's text states."""

    metric: str
    comparator: str
    target: float


_CAP_WORDS = re.compile(
    r"\b(under|below|less than|fewer than|no more than|at most|max(imum)?|cap)\b"
)
_STEPS = re.compile(r"(\d[\d,]*(?:\.\d+)?)\s*(k)?\s*steps\b")
_BRISK = re.compile(r"\b(brisk|vigorous|moderate|mvpa|cardio|run|jog)")
_MINUTES = re.compile(r"(\d+)\s*(?:(?:-|to)\s*\d+\s*)?(?:min|mins|minutes)\b")
_SLEEPY = re.compile(r"\b(sleep|asleep|bed)")
_HOURS = re.compile(r"(\d+(?:\.\d+)?)\s*(?:h|hr|hrs|hours?)\b")
_MIN_PER_HOUR = 60
_THOUSAND = 1000


def _steps(text: str) -> RecRule | None:
    found = _STEPS.search(text)
    if not found:
        return None
    number = float(found.group(1).replace(",", ""))
    return RecRule("steps_total", ">=", number * _THOUSAND if found.group(2) else number)


def _brisk_minutes(text: str) -> RecRule | None:
    found = _MINUTES.search(text)
    if not found or not _BRISK.search(text):
        return None
    return RecRule("mvpa_min", ">=", float(found.group(1)))


def _sleep_hours(text: str) -> RecRule | None:
    found = _HOURS.search(text)
    if not found or not _SLEEPY.search(text):
        return None
    return RecRule("tst_min", ">=", float(found.group(1)) * _MIN_PER_HOUR)


def parse_rule(action: str) -> RecRule | None:
    """The rule ``action`` states, or ``None`` when it does not state exactly one."""
    text = action.lower()
    if _CAP_WORDS.search(text):
        return None
    rules = [r for r in (_steps(text), _brisk_minutes(text), _sleep_hours(text)) if r]
    return rules[0] if len(rules) == 1 else None
