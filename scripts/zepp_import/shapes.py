"""The SHAPE of a JSON value — its field names and types — and never a value.

When Zepp changes its API, fixing this tool needs to know what the reply looked like. The
reply itself is the owner's location history, so it cannot be pasted anywhere. Its shape
can: `{code:int,data:{next:int,summary:[{trackid:numstr,type:int}x20]}}` says everything a
parser needs and nothing about where anyone ran.

Three rules keep it that way, and `tests/test_shapes.py` holds each one:

 * a string is described, never quoted — as `str`, as `numstr` when it is a number in
   quotes, or as a list with a cell COUNT and a cell PATTERN in which every digit run is
   `9` and every letter run is `a`;
 * a key is printed only when it looks like a field name; anything else (an id, a date,
   free text used as a key) becomes `<key>`;
 * the whole description is capped, so a reply cannot be exfiltrated by being enormous.

A workout summary has around ninety fields, so `fields` exists beside `shape`: it
describes only the named ones, which is what a failure message has room for.

`layout` is for an instant that would not parse. There the COUNT of digits is the
diagnosis (a two-digit year, seconds left off), so each digit and each letter is masked
one for one instead of run by run, and the string is cut at forty characters.
"""

from __future__ import annotations

import re

MAX_CHARS = 6000
_MAX_DEPTH = 4
_MAX_KEYS = 150
_MAX_KEY_DIGITS = 3
_PATTERN_CHARS = 12
_FIELD_NAME_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_.-]{0,39}")
_DIGITS_RE = re.compile(r"[0-9]+")
_LETTERS_RE = re.compile(r"[A-Za-z]+")
_NOT_PATTERN_RE = re.compile(r"[^9a,.:+-]")
_NUMBER_RE = re.compile(r"-?[0-9]+(\.[0-9]+)?")
_LAYOUT_CHARS = 40
_DIGIT_RE = re.compile(r"[0-9]")
_LETTER_RE = re.compile(r"[^\W\d_]")  # any letter, in any script
_NOT_LAYOUT_RE = re.compile(r"[^9a.:+ -]")
_MISSING = object()


def _pattern(cell: str) -> str:
    """`cell` with every digit run as `9` and every letter run as `a`. No value survives."""
    masked = _LETTERS_RE.sub("a", _DIGITS_RE.sub("9", cell[:64]))
    return _NOT_PATTERN_RE.sub("?", masked)[:_PATTERN_CHARS]


def _string(value: str) -> str:
    if ";" in value:
        cells = value.split(";")
        return f"str[;x{len(cells)} like {_pattern(cells[0]) or 'empty'}]"
    if _NUMBER_RE.fullmatch(value):
        return "numstr"
    return "str" if value else "str(empty)"


def _key(key: object) -> str:
    """`key` when it reads as a field name; an id or a date used as a key is masked."""
    if not isinstance(key, str) or not _FIELD_NAME_RE.fullmatch(key):
        return "<key>"
    return key if len(_DIGITS_RE.findall(key)) <= 1 and _digits(key) <= _MAX_KEY_DIGITS else "<key>"


def _digits(text: str) -> int:
    return sum(character.isdigit() for character in text)


def _describe(value: object, depth: int) -> str:
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "bool"
    if isinstance(value, (int, float)):
        return type(value).__name__
    if isinstance(value, str):
        return _string(value)
    if depth >= _MAX_DEPTH:
        return "..."
    if isinstance(value, list):
        return f"[{_describe(value[0], depth + 1)}x{len(value)}]" if value else "[]"
    if isinstance(value, dict):
        keys = sorted({_key(key) for key in value})[:_MAX_KEYS]
        by_key = {_key(key): item for key, item in value.items()}
        return "{" + ",".join(f"{key}:{_describe(by_key[key], depth + 1)}" for key in keys) + "}"
    return type(value).__name__


def layout(value: object, names: tuple[str, ...]) -> str:
    """The named fields with a string shown as its LAYOUT: `start_iso:9999-99-99a99:99a`.

    For timestamps this tool could not read. Every digit becomes `9` and every letter
    `a`, one for one, so the format is all that is left of the instant.
    """
    if not isinstance(value, dict):
        return shape(value, 80)
    return ",".join(f"{name}:{_layout(value.get(name, _MISSING))}" for name in names)


def _layout(value: object) -> str:
    if value is _MISSING:
        return "missing"
    if not isinstance(value, str):
        return _describe(value, 1)
    masked = _LETTER_RE.sub("a", _DIGIT_RE.sub("9", value[:_LAYOUT_CHARS]))
    return _NOT_LAYOUT_RE.sub("?", masked) or "str(empty)"


def shape(value: object, max_chars: int = MAX_CHARS) -> str:
    """A description of `value` that contains its structure and none of its content."""
    described = _describe(value, 0)
    return described if len(described) <= max_chars else described[: max_chars - 3] + "..."


def fields(value: object, names: tuple[str, ...]) -> str:
    """The shape of just `names` within an object: `trackid:numstr,type:missing`."""
    if not isinstance(value, dict):
        return shape(value, 80)
    return ",".join(
        f"{name}:{_describe(value[name], 1) if name in value else 'missing'}" for name in names
    )
