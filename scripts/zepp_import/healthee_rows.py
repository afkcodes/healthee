"""What Healthee's read endpoints return, reduced to what an import has to know.

Pure functions over decoded JSON, split from `healthee_api.py` so the parsing has tests
that need no HTTP. Two reads matter: the workout list inside `/api/activity`
(`read/fitness.py::workouts_list`) and the route list (`read/gps.py::list_gps_tracks`).

## What the workout list cannot tell us

It reports `duration_min`, a whole number of minutes, so a stored session's end is known
to within thirty seconds; and it leaves out sessions shorter than ten minutes altogether.
`plan.py` is written around both: it never sends a duration back, and it imports nothing
that short.
"""

from __future__ import annotations

import ipaddress
import urllib.parse
from collections.abc import Callable
from dataclasses import dataclass
from datetime import date, datetime, timedelta
from typing import TypeVar

from zepp_import import failures
from zepp_import.localtime import UTC
from zepp_import.shapes import fields, layout, shape

_Row = TypeVar("_Row")

MEASUREMENT_COLUMNS = ("distance_m", "calories", "avg_hr", "max_hr", "min_hr")


@dataclass(frozen=True)
class ExistingWorkout:
    """A workout row Healthee already holds. `start_ms` is its exact primary key.

    `lacks` names the measurements the server reported as NULL — and only those. The
    upsert lets a pushed value replace a stored one (`COALESCE(new, old)`), so "this row
    has no heart rate" must be something the server SAID. A column the reply simply did
    not mention is unknown, not empty, and is never in this set; `sport` is None for the
    same reason.
    """

    start_ms: int
    duration_s: int
    sport: int | None
    lacks: frozenset[str] = frozenset()

    @property
    def start_s(self) -> float:
        return self.start_ms / 1000.0

    @property
    def end_s(self) -> float:
        return self.start_s + self.duration_s


@dataclass(frozen=True)
class ExistingTrack:
    track_id: str
    start_s: float
    end_s: float


def _is_loopback(hostname: str) -> bool:
    if hostname == "localhost":
        return True
    try:
        return ipaddress.ip_address(hostname).is_loopback
    except ValueError:
        return False


def _split(text: str) -> tuple[str, str, int | None, str] | None:
    """(scheme, host, port, path) of an address with nothing else in it, or None."""
    try:
        parts = urllib.parse.urlsplit(text)
        port = parts.port
    except ValueError:
        return None
    host = parts.hostname or ""
    plain = not (parts.query or parts.fragment or parts.username or parts.password)
    named = host == "localhost" or "." in host or ":" in host
    return (parts.scheme, host, port, parts.path.rstrip("/")) if plain and named else None


def normalise_url(value: str, *, what: str = "Healthee address", allow_path: bool = False) -> str:
    """A server address as a base URL. HTTPS is required for anything but loopback."""
    text = value.strip()
    split = _split(text if "://" in text else f"https://{text}")
    if split is None:
        raise failures.bad_setting(what, "expected something like healthee.example.com")
    scheme, host, port, path = split
    if path and not allow_path:
        raise failures.bad_setting(what, "expected only the server's name, with no path")
    if scheme != "https" and not (scheme == "http" and _is_loopback(host)):
        raise failures.bad_setting(what, "must be https, because it carries a password")
    bracketed = f"[{host}]" if ":" in host else host
    return f"{scheme}://{bracketed}{'' if port is None else f':{port}'}{path}"


def _epoch_ms(iso: object) -> int | None:
    """An ISO instant WITH an offset, as epoch milliseconds. Anything else is None."""
    if not isinstance(iso, str):
        return None
    # Python 3.10 reads only what `datetime.isoformat()` writes, which is what the server
    # sends. "Z" is the one other spelling of UTC a JSON encoder commonly produces, so it
    # is read on every Python rather than only on 3.11 and later.
    text = f"{iso[:-1]}+00:00" if iso.endswith(("Z", "z")) else iso
    try:
        moment = datetime.fromisoformat(text)
    except ValueError:
        return None
    return round(moment.timestamp() * 1000) if moment.tzinfo else None


def existing_workout(row: object) -> ExistingWorkout | None:
    if not isinstance(row, dict):
        return None
    start_ms = _epoch_ms(row.get("start_iso"))
    if start_ms is None:
        return None
    minutes, sport = row.get("duration_min"), row.get("sport")
    return ExistingWorkout(
        start_ms=start_ms,
        duration_s=int(minutes * 60) if isinstance(minutes, (int, float)) else 0,
        sport=sport if isinstance(sport, int) and not isinstance(sport, bool) else None,
        lacks=frozenset(c for c in MEASUREMENT_COLUMNS if c in row and row[c] is None),
    )


def existing_track(row: object) -> ExistingTrack | None:
    if not isinstance(row, dict):
        return None
    start_ms, end_ms = _epoch_ms(row.get("start_ts")), _epoch_ms(row.get("end_ts"))
    track_id = row.get("track_id")
    if start_ms is None or end_ms is None or not isinstance(track_id, str):
        return None
    return ExistingTrack(track_id=track_id, start_s=start_ms / 1000.0, end_s=end_ms / 1000.0)


def read_all(
    what: str,
    listed: object,
    parse: Callable[[object], _Row | None],
    times: tuple[str, ...],
    others: tuple[str, ...] = (),
) -> list[_Row]:
    """Every row of a list Healthee returned. One that cannot be read is a failure.

    Never a gap: a stored session this tool cannot read would look absent, absent
    sessions are what it writes, and nothing here can delete the second copy. `times`
    names the instants a row is read by, shown as their layout when one does not parse.
    """
    if not isinstance(listed, list):
        raise failures.healthee_unreadable(what, 0, 0, shape(listed, 80))
    rows: list[_Row] = []
    unread: list[object] = []
    for item in listed:
        row = parse(item)
        if row is None:
            unread.append(item)
        else:
            rows.append(row)
    if unread:
        seen = _seen(unread[0], times, others)
        raise failures.healthee_unreadable(what, len(unread), len(listed), seen)
    return rows


def _seen(row: object, times: tuple[str, ...], others: tuple[str, ...]) -> str:
    """How an unreadable row was written: its instants as layout, the rest as types."""
    if not others or not isinstance(row, dict):
        return layout(row, times)
    return f"{layout(row, times)},{fields(row, others)}"


def next_page_day(oldest_s: float, server_today: object) -> str | None:
    """The `day=` that returns the page of workouts older than `oldest_s`.

    The server answers for the owner's LOCAL day and this tool may be running where that
    zone cannot be loaded (`localtime.py`), so no zone arithmetic is done here. The UTC
    date of `oldest_s` plus one day is on or after its local date in every timezone, so
    asking for it can repeat rows already seen but can never skip one. It is capped at
    the server's own today (the `date` of the previous reply), because a day in the
    owner's future is refused with a 422. None when that reply carried no usable date.
    """
    if not isinstance(server_today, str):
        return None
    try:
        today = date.fromisoformat(server_today)
    except ValueError:
        return None
    covering = datetime.fromtimestamp(oldest_s, tz=UTC).date() + timedelta(days=1)
    return min(covering, today).isoformat()
