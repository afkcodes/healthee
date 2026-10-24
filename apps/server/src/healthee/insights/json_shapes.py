"""Which JSON payloads the validator knows how to read, and which of their fields are prose.

Split from :mod:`healthee.insights.validator` on the seam the two already had: that module
owns the RULES (grounding, tone, certainty, grade calibration), this one owns the
per-surface DECLARATION of what user-facing text a payload contains and how each field is
grounded. They change for different reasons — a new honesty rule edits the rules, a new
JSON surface edits this table — and the validator was at the file gate.

## A shape that is not here FAILS CLOSED, and that is the point

Before challenge generation existed, an unrecognised payload produced zero segments,
``validator._run_rules`` then had no text to check, and it returned ``ok=True`` with no
citations — a total validation bypass reachable by any future JSON surface that forgot to
register itself. :func:`segments_for` returns ``None`` for a payload it cannot read, and
the validator blocks on that, which is the only safe reading of "I do not know what this
is".
"""

from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass


@dataclass(frozen=True)
class Segment:
    """One chunk of user-facing text, plus whether its sentences must carry citations."""

    text: str
    require_grounding: bool = True


def _item_segments(
    items: object, grounded_fields: tuple[str, ...], directive_fields: tuple[str, ...]
) -> list[Segment]:
    """Pull the named string fields out of a list of objects, tagged with their rule.

    Shared by every JSON shape so "which fields are prose and which are directives" is a
    per-shape declaration rather than a per-shape loop that could drift.
    """
    if not isinstance(items, list):
        return []
    segments: list[Segment] = []
    for item in items:
        if not isinstance(item, dict):
            continue
        for name in grounded_fields:
            value = item.get(name)
            if isinstance(value, str):
                segments.append(Segment(value))
        for name in directive_fields:
            value = item.get(name)
            if isinstance(value, str):
                segments.append(Segment(value, require_grounding=False))
    return segments


# A rec's `action` is a one-line DIRECTIVE by contract (jobs/recs.py RECS_TASK), and it is
# grounded at the REC level rather than sentence-level. `jobs/recs.py::_rec_ok` gates every
# rec through independent checks and drops it if ANY one fails — so a rec that ships has
# provably ALL of: non-empty `research_note_ids`, EVERY id known to the manifest, AND an
# inline [note_id] in its `rationale`. (Read it as "all required", not "both must fail":
# an exemption justified by a guarantee weaker than the real one is how the next reader
# talks themselves into widening it.)
#
# Requiring a citation inside the imperative would therefore demand grounding the rec
# already carries, and grade-calibrating an imperative is a category error ("You might aim
# for a walk"). So the directive is exempt from the GROUNDING rules only — banned tone,
# certainty and fabricated-id checks still apply here, and `_rec_ok`'s safety-keyword block
# scans the action too. If `_rec_ok` ever loosens, this exemption must be revisited: it is
# the only thing standing under it.
_RECS_GROUNDED_FIELDS = ("rationale", "expected_effect")
_RECS_DIRECTIVE_FIELDS = ("action",)


# A generated challenge's user-facing strings, split the same way a rec's are.
# `why` and `expected_outcome` are the INTERPRETIVE fields — they explain what the
# evidence says and must carry it. `title` and `how_to` are DIRECTIVES ("Walk more";
# "3× 25-min walks Mon/Wed/Fri"), grounded at the challenge level exactly as a rec's
# `action` is: `challenges.screen._citation_issue` drops any challenge whose
# `research_note_ids` is empty, names an unknown id, or whose `why` carries no inline
# `[note_id]`, so a challenge that ships has provably ALL of those. Grade-calibrating an
# imperative is the same category error it is for a rec ("You might do 3 sessions"), and
# requiring a citation inside one would demand grounding the challenge already carries.
# If that screen ever loosens, this exemption must be revisited — it is the only thing
# standing under it.
_CHALLENGE_GROUNDED_FIELDS = ("why", "expected_outcome")
_CHALLENGE_DIRECTIVE_FIELDS = ("title", "how_to")


def _challenge_segments(payload: dict) -> list[Segment]:
    """The user-facing strings of a generated-challenges payload, each with its rule."""
    return _item_segments(
        payload.get("challenges"), _CHALLENGE_GROUNDED_FIELDS, _CHALLENGE_DIRECTIVE_FIELDS
    )


# A generated ladder's own copy (WP-C4b). Its RUNGS are challenges and reuse the split
# above verbatim; the program's `why` is the interpretive sentence explaining the climb and
# its `title` is a directive. The same exemption argument stands under the directive half:
# `challenges.program_screen` runs EVERY rung through `screen.proposal_issue`, so a ladder
# that ships has provably real note ids and an inline `[note_id]` in every rung's `why`.
_PROGRAM_GROUNDED_FIELDS = ("why",)
_PROGRAM_DIRECTIVE_FIELDS = ("title",)


def _program_segments(payload: dict) -> list[Segment]:
    """The user-facing strings of a generated ladder: its own copy plus every rung's."""
    program = payload.get("program")
    if not isinstance(program, dict):
        return []
    return _item_segments(
        [program], _PROGRAM_GROUNDED_FIELDS, _PROGRAM_DIRECTIVE_FIELDS
    ) + _item_segments(
        program.get("rungs"), _CHALLENGE_GROUNDED_FIELDS, _CHALLENGE_DIRECTIVE_FIELDS
    )


def _recs_segments(payload: object) -> list[Segment]:
    """The USER-FACING strings of a recs payload, each tagged with its grounding rule.

    Only ``rationale`` / ``action`` / ``expected_effect`` are user-facing prose; keys and
    constrained-vocab fields (``category``, ``signal_source``, ``evidence_grade``,
    ``research_note_ids``) are NOT validated as prose — they are structurally checked
    per-rec in ``jobs/recs.py``. This is why an interpretive-looking word in a KEY or a
    category value cannot false-trip or false-satisfy the rules.
    """
    return _item_segments(
        payload.get("recommendations") if isinstance(payload, dict) else None,
        _RECS_GROUNDED_FIELDS,
        _RECS_DIRECTIVE_FIELDS,
    )


# The ONE morning generation (#95, `insights/morning.py`): the Telegram briefing body and
# today's daily action, returned as two fields of ONE answer. Both are INTERPRETIVE prose
# and neither takes the directive exemption a rec's `action` does — before #95 each of these
# two texts was validated sentence-by-sentence by the PROSE validator, and merging the calls
# may not quietly loosen what either is held to. So both fields are grounded segments, and
# the rules that applied to two answers now apply to one.
#
# There is no per-field verdict, deliberately: the two are one candidate, so an ungrounded
# sentence in `action` withholds the briefing too. `morning.py` handles that by letting each
# surface fall back to its own independent generation, rather than by shipping half a judged
# answer.
_MORNING_GROUNDED_FIELDS = ("briefing", "action")


def _morning_segments(payload: dict) -> list[Segment]:
    """The morning answer's two user-facing strings, both held to the grounding rules.

    A missing or non-string field yields no segment — which is why `morning._fields` makes
    the structural check separately. This function's job is "what text is in here", not
    "is the payload well-formed"; conflating them is how a shape ends up validating a
    payload it does not actually understand.
    """
    return [
        Segment(value)
        for name in _MORNING_GROUNDED_FIELDS
        if isinstance(value := payload.get(name), str)
    ]


# The weekly/daily COACH answer (jobs/coach_task.py). Its coach-voice prose (`review`,
# `pattern`, `today`) and the job's directive lines are NOT grounded sentence-by-sentence:
# the spec keeps note ids out of the text the owner reads ("Note ids go only in the
# rationale field"), and the review mostly quotes the owner's own numbers. They still face
# banned tone, certainty, fabricated-id and the hard guardrails. The `rationale` is the one
# interpretive field and is grounded and grade-calibrated like any other; `coach_checks`
# additionally requires an inline citation and PROVES the grade. If that loosens, this
# exemption must be revisited.
_COACH_VOICE_FIELDS = ("review", "pattern", "today")
_COACH_JOB_FIELDS = ("action", "slot", "floor", "counts_when")


def _coach_segments(payload: dict) -> list[Segment]:
    """The coach answer's user-facing strings, each with its grounding rule."""
    segments = [
        Segment(value, require_grounding=False)
        for name in _COACH_VOICE_FIELDS
        if isinstance(value := payload.get(name), str)
    ]
    job = payload.get("job")
    if isinstance(job, dict):
        segments += _item_segments([job], (), _COACH_JOB_FIELDS)
    if isinstance(rationale := payload.get("rationale"), str):
        segments.append(Segment(rationale))
    return segments


# The JSON shapes this codebase knows how to read, keyed by a top-level key. A shape that
# is NOT here fails closed (module docstring).
JSON_SHAPES: dict[str, Callable[[dict], list[Segment]]] = {
    "recommendations": _recs_segments,
    "challenges": _challenge_segments,
    "program": _program_segments,
    "briefing": _morning_segments,
    "today": _coach_segments,
}


def segments_for(payload: dict) -> list[Segment] | None:
    """The user-facing text of ``payload``, or ``None`` when its shape is unregistered.

    ``None`` and ``[]`` are deliberately different answers. An EMPTY known array
    (``{"challenges": []}``, ``{"program": null}``) is a valid "nothing meaningful
    applies" — both surfaces are built to give it — and yields ``[]``. An unknown shape
    yields ``None``, which the validator turns into a refusal.
    """
    shape = next((key for key in JSON_SHAPES if key in payload), None)
    return None if shape is None else JSON_SHAPES[shape](payload)
