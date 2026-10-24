"""The structural checks every generated coach text shares — cite, grade, safety words.

Moved here from the daily-recommendations job when that job was replaced by the weekly
coach: these three rules were never about recommendations, they are what any generated
directive must pass before it ships, and the coach is now their only caller.

* **Cite.** An inline ``[note_id]`` in the rationale, and every cited id real.
* **Grade is PROVED, not believed.** ``evidence_grade`` is a number the model writes about
  itself; the shipped grade is the strictest cited note's, so a Contested note can never
  ship labelled Established (honesty contract rule 2). Evidence below Probable does not
  get to drive an instruction at all.
* **Safety words.** No dosing, medication, supplement, diagnosis or symptom talk.
"""

from __future__ import annotations

import re
from collections.abc import Sequence

from healthee.insights import manifest

VALID_GRADES = frozenset({2, 3})

BANNED_RE = re.compile(
    r"\bmg\b|\bdose|\bdosing\b|\bprescri|\bdiagnos|\bsymptom|\bmedication\b|"
    r"\bsupplement\b|\bmedicine\b|\bdrug\b|\bpill\b|\btablet\b",
    re.IGNORECASE,
)
INLINE_CITE_RE = re.compile(r"\[[a-z0-9_]+(?:\s*,\s*[a-z0-9_]+)*\]")


def has_banned_phrase(*texts: str | None) -> bool:
    """Whether any text trips the safety-keyword block."""
    return any(BANNED_RE.search(text) for text in texts if text)


def citation_issue(note_ids: Sequence[str], rationale: str) -> str | None:
    """Why the citations are unusable, or ``None``."""
    if not note_ids:
        return "research_note_ids is empty"
    known = manifest.note_ids()
    unknown = [nid for nid in note_ids if nid not in known]
    if unknown:
        return f"unknown note ids {unknown}"
    if not INLINE_CITE_RE.search(rationale):
        return "the rationale has no inline [note_id]"
    return None


def provable_grade(declared: int, note_ids: Sequence[str]) -> int | None:
    """The grade the citations support, or ``None`` when they may not drive an action.

    Overclaiming is corrected down, not dropped: the prose was grade-calibrated against
    these same notes by the blocking validator, so only the label overreached. An unknown
    grade ranks 0 (fail-closed). The floor rule is ``manifest.MIN_ACTIONABLE_RANK``.
    """
    ranks = [manifest.GRADE_RANK.get(manifest.grade_of(nid) or "", 0) for nid in note_ids]
    if not ranks or min(ranks) < manifest.MIN_ACTIONABLE_RANK:
        return None
    return min(declared, min(ranks))
