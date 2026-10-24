"""The coach's task text and its output shape (``design/redesign-2026-10/COACH_TASK.md``).

Replaces the daily recommendations task. The choke point's SYSTEM_PROMPT, citation rules,
grade language and guardrails are unchanged — only the task text and output shape live
here. The text is the spec's, verbatim, split by its WEEKLY / DAILY / VOICE parts; the
daily run adds one sentence saying which nulls it must return.
"""

from __future__ import annotations

import re
from typing import Self

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

from healthee.jobs.coach_checks import VALID_GRADES, citation_issue, has_banned_phrase
from healthee.jobs.coach_job import CoachJob

_INTRO = """\
Act as my coach. You are a person who has watched every number above for a month and
wants me fitter. Your job is to get me doing more, starting from where I actually am.
"""

_WEEKLY = """\
WEEKLY (Sunday): write a review and set ONE job for next week.
- Review: what I did, what moved, what didn't. Quote real numbers from WEEKS and
  COMMITMENTS. Name the pattern you see in my yeses and misses. Name what is improving
  as plainly as what is slipping. No pep talk.
- Job: one behaviour, one metric the strap measures, one target, days out of 7.
  Size it from my COMMITMENTS done rate:
  - Done 4+ of last 4 weeks' jobs: step up 20 to 25%.
  - Done 2 to 3: repeat the same job.
  - Done 0 to 1: shrink it until I would finish it on a bad week.
  - A missed week repeats; never silently lower the bar and never reset the ladder.
- Give a time slot taken from when my data shows I already move, and a floor for bad days.
"""

_DAILY = """\
DAILY: at most 2 sentences. Where I stand on this week's job, and the one thing that
gets today counted. If recovery is in the red zone (under 34), swap to the easy version
and say why. If the job is already done this week, say so and stop.
"""

_VOICE = """\
VOICE
- Talk like a coach texting me: short sentences, plain words, real numbers, "you".
- Push. If I'm slipping, say it straight. If I did it, say so in one line and move on.
- No jargon in the text I read: say "brisk minutes", not "MVPA"; "how regular your
  sleep is", not "SRI". Note ids go only in the rationale field.
- No "great job", no emojis, no exclamation marks. Never invent a number.
"""

_OUTPUT = """\
Output ONLY JSON:
{"review": "<=4 sentences, weekly only, else null",
 "pattern": "<=2 sentences about my yes/miss behaviour, weekly only, else null",
 "job": {"action": "<one line, human>", "metric": "<calibration-table metric>",
         "target": <number>, "unit": "<unit>", "days_required": <1-7>,
         "slot": "<when>", "floor": "<bad-day version>",
         "counts_when": "<plain rule the strap checks>"},
 "today": "<=2 sentences",
 "rationale": "<=2 sentences, each interpretive clause ending in [note_id]>",
 "evidence_grade": 2 or 3,
 "research_note_ids": ["<id>"]}
If data coverage is too thin to judge last week, say so in review and repeat the job.
"""

_DAILY_NULLS = "This is the DAILY run: return review, pattern and job as null.\n"

WEEKLY_TASK = "\n".join([_INTRO, _WEEKLY, _VOICE, _OUTPUT])
DAILY_TASK = "\n".join([_INTRO, _DAILY, _VOICE, _OUTPUT, _DAILY_NULLS])

_SENTENCE_SPLIT = re.compile(r"(?<=[.!?])\s+(?=[A-Z0-9\"'])")
_EMOJI = re.compile("[\U0001f300-\U0001faff☀-➿]")
MAX_REVIEW, MAX_PATTERN, MAX_TODAY, MAX_RATIONALE = 4, 2, 2, 2


def sentence_count(text: str) -> int:
    """Sentences in ``text``; a decimal point or a "6h53" does not end one."""
    return len([s for s in _SENTENCE_SPLIT.split(text.strip()) if s.strip()])


def _limited(text: str | None, limit: int, name: str) -> str | None:
    if text is None:
        return None
    text = text.strip()
    if not text:
        raise ValueError(f"{name} is empty — it should be null")
    if sentence_count(text) > limit:
        raise ValueError(f"{name} is longer than {limit} sentences")
    if "!" in text or _EMOJI.search(text):
        raise ValueError(f"{name} uses an exclamation mark or an emoji")
    if has_banned_phrase(text):
        raise ValueError(f"{name} contains a banned safety phrase")
    return text


class CoachWeek(BaseModel):
    """The coach's JSON answer. Weekly fills every field; daily only ``today`` and its cite."""

    model_config = ConfigDict(extra="ignore")

    review: str | None = None
    pattern: str | None = None
    job: CoachJob | None = None
    today: str
    rationale: str
    evidence_grade: int
    research_note_ids: list[str] = Field(min_length=1)

    @field_validator("review")
    @classmethod
    def _review(cls, v: str | None) -> str | None:
        return _limited(v, MAX_REVIEW, "review")

    @field_validator("pattern")
    @classmethod
    def _pattern(cls, v: str | None) -> str | None:
        return _limited(v, MAX_PATTERN, "pattern")

    @field_validator("today")
    @classmethod
    def _today(cls, v: str) -> str:
        return _limited(v, MAX_TODAY, "today") or ""

    @field_validator("rationale")
    @classmethod
    def _rationale(cls, v: str) -> str:
        if sentence_count(v) > MAX_RATIONALE:
            raise ValueError(f"rationale is longer than {MAX_RATIONALE} sentences")
        if has_banned_phrase(v):
            raise ValueError("rationale contains a banned safety phrase")
        return v.strip()

    @field_validator("evidence_grade")
    @classmethod
    def _grade(cls, v: int) -> int:
        if v not in VALID_GRADES:
            raise ValueError("evidence_grade must be 2 or 3")
        return v

    @model_validator(mode="after")
    def _cited(self) -> Self:
        issue = citation_issue(self.research_note_ids, self.rationale)
        if issue:
            raise ValueError(issue)
        return self

    def require_weekly(self) -> Self:
        """A weekly answer must carry the review, the pattern and the job."""
        if self.review is None or self.pattern is None or self.job is None:
            raise ValueError("a weekly answer needs review, pattern and job")
        return self
