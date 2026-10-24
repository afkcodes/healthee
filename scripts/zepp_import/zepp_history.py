"""Reading the account's workout feed, and one workout's detail, from Zepp.

## Finding the host is part of reading the feed

Zepp keeps an account's data in one region. A host for a different region does not
refuse the token — it answers with a well-formed EMPTY list, which is indistinguishable
from "this person has never recorded a workout". So an empty answer is not believed until
every candidate host has given it, and the first host that returns a workout wins. The
hosts are tried one at a time, most likely first, so the token goes no further than it
has to. The winner is remembered (`ledger.py`) and tried first next time.

The one empty answer that IS believed is from a host the owner named (`--zepp-host`):
they have said where their data lives, and asking eleven more hosts would only send the
token to places they did not choose.

## The feed

`/v1/sport/run/history.json` is the account-wide workout feed despite its path; the kind
of each workout is its numeric `type`. It is newest-first, and `data.next` is the cursor
for the next, older page. Two parameter styles are in use by independent clients, and
each is sent exactly as its client sends it: a WINDOWED one bounded by track ids, and a
BARE one that takes only a cursor (`ZeppHistory._first_page` says how they are combined).

The request itself — the reply envelope, retries, redirects — is `zepp_api.py`.

## When the reply is not what this expects

Every reply's SHAPE can be traced (`--verbose`), and a reply this cannot read names its
shape in the failure. A shape is field names and types only (`shapes.py`), so it can be
pasted into a bug report; the reply itself is somebody's location history and cannot.
"""

from __future__ import annotations

import re
from collections.abc import Callable
from dataclasses import dataclass

from zepp_import import failures, zepp_wire
from zepp_import.shapes import shape
from zepp_import.transport import Send, host_of
from zepp_import.zepp_api import BUSY, REDIRECTED, REFUSED, TIMEOUT_S, UNREACHABLE, ZeppApi
from zepp_import.zepp_auth import ZeppSession
from zepp_import.zepp_wire import ZeppEndpoints

_PROBE_TIMEOUT_S = 15.0
_MAX_PAGES = 500
_EMPTY = "no workouts"
_SOURCE_RE = re.compile(r"[A-Za-z0-9._-]{1,64}")
_NOTE_SHAPE_CHARS = 200
Notify = Callable[[str], None]
_WINDOWED, _BARE = "windowed", "bare"


@dataclass(frozen=True)
class Feed:
    """The workouts inside the asked-for window, newest first, and where they came from."""

    host: str
    records: tuple[dict, ...]
    tried: tuple[str, ...]


@dataclass(frozen=True)
class _Page:
    records: list[dict]
    next_cursor: int | None


def _cursor(value: object) -> int | None:
    """Zepp's `next`: a positive track id, or None for its "no older page" values."""
    if isinstance(value, bool) or not isinstance(value, int):
        return None
    return value if value > 0 else None


def _track_id(record: dict) -> int:
    try:
        return int(str(record.get("trackid", "")))
    except ValueError:
        return 0


class ZeppHistory:
    """The workout calls for one signed-in session."""

    def __init__(
        self,
        session: ZeppSession,
        endpoints: ZeppEndpoints,
        send: Send,
        notify: Notify = lambda _line: None,
        trace: Notify = lambda _line: None,
        pause: Callable[[float], None] = lambda _seconds: None,
    ) -> None:
        self._session = session
        self._endpoints = endpoints
        self._notify = notify
        self._api = ZeppApi(session, send, pause=pause, trace=trace)

    def feed(
        self, since_s: int, now_s: int, first_host: str | None = None, *, named: bool = False
    ) -> Feed:
        """Every workout that started in `[since_s, now_s]`. Raises a named failure.

        `first_host` is tried before the others: the host that produced this account's
        workouts last time, or the one the owner passed. `named` says it is the latter,
        which makes it the only host asked and its empty answer final.
        """
        tried: list[str] = []
        queue = [first_host] if named and first_host else self._candidates(first_host)
        position = 0
        while position < len(queue):
            host = queue[position]
            position += 1
            self._notify(f"asking {host_of(host)}")
            style, outcome = self._first_page(host, since_s, now_s)
            if isinstance(outcome, _Page) and (outcome.records or named):
                records = self._older_pages(host, style, outcome, since_s, now_s)
                kept = [r for r in records if since_s <= _track_id(r) <= now_s]
                return Feed(host=host, records=tuple(kept), tried=tuple(tried))
            tried.append(f"{host_of(host)}: {_EMPTY if isinstance(outcome, _Page) else outcome}")
            if not named:
                # A host Zepp itself pointed at is the best lead there is: ask it next.
                fresh = [h for h in self._api.redirected_to if h not in queue]
                queue[position:position] = fresh
        raise _feed_failure(tried)

    def detail(self, host: str, track_id: int, source: str) -> dict | str:
        """One workout's detail object, or a short note on why Zepp did not give one.

        A note rather than a failure: one workout whose track cannot be read costs that
        workout its route and nothing else, and the note is shown beside it.
        """
        if not _SOURCE_RE.fullmatch(source):
            return "its record has no usable source id"
        params: dict[str, object] = {"trackid": track_id, "source": source}
        return self._api.get(host, zepp_wire.DETAIL_PATH, params)

    def _candidates(self, first_host: str | None) -> list[str]:
        ordered = [
            *([first_host] if first_host else []),
            *self._session.host_hints,
            *self._endpoints.primary_hosts,
            *self._endpoints.region_hosts,
        ]
        return list(dict.fromkeys(ordered))

    def _first_page(self, host: str, since_s: int, now_s: int) -> tuple[str, _Page | str]:
        """The newest page from `host`, and the parameter style that produced it.

        The windowed style is asked for the window itself, exactly as the client it comes
        from asks. When that does not PRODUCE a workout — an odd reply or an empty one —
        the bare style is asked, because it is account-wide: an empty window on the right
        host and any window on the wrong host look the same, and only a reply that is not
        bounded by the window can tell them apart. A host that is unreachable, refusing or
        rate-limiting is not asked twice: none of those depends on the parameters.
        """
        if self._session.user_id:
            outcome = self._page(host, _WINDOWED, now_s, since_s, _PROBE_TIMEOUT_S)
            if isinstance(outcome, _Page) and outcome.records:
                return _WINDOWED, outcome
            if isinstance(outcome, str) and outcome.startswith((UNREACHABLE, REFUSED, BUSY)):
                return _WINDOWED, outcome
        return _BARE, self._page(host, _BARE, None, since_s, _PROBE_TIMEOUT_S)

    def _older_pages(
        self, host: str, style: str, first: _Page, since_s: int, now_s: int
    ) -> list[dict]:
        """`first` plus every older page until the window's start is passed."""
        records, page, cursor = list(first.records), first, now_s
        for _ in range(_MAX_PAGES):
            if not page.records or page.next_cursor is None or page.next_cursor >= cursor:
                break
            if min(_track_id(r) for r in page.records) < since_s:
                break
            cursor = page.next_cursor
            outcome = self._page(host, style, cursor, since_s, TIMEOUT_S)
            if isinstance(outcome, str):
                raise _page_failure(host, outcome)
            page = outcome
            records.extend(page.records)
        else:
            # Never a quiet stop: a truncated history would read as "nothing older exists".
            raise failures.bad_setting(
                "The window", f"needs more than {_MAX_PAGES} pages of Zepp history; narrow it"
            )
        unique = {(_track_id(r), str(r.get("source"))): r for r in records}
        return sorted(unique.values(), key=_track_id, reverse=True)

    def _page(
        self, host: str, style: str, cursor: int | None, since_s: int, timeout_s: float
    ) -> _Page | str:
        if style == _WINDOWED:
            params: dict[str, object] = {
                "userid": self._session.user_id,
                "startTrackId": since_s,
                "stopTrackId": cursor,
                "need_sub_data": 1,
                "type": "",
            }
        else:
            params = {} if cursor is None else {"trackid": cursor}
        data = self._api.get(host, zepp_wire.HISTORY_PATH, params, timeout_s)
        if isinstance(data, str):
            return data
        summary = data.get("summary")
        if not isinstance(summary, list):
            return f"no data.summary list in {shape(data, _NOTE_SHAPE_CHARS)}"
        return _Page(
            records=[r for r in summary if isinstance(r, dict)],
            next_cursor=_cursor(data.get("next")),
        )


def _page_failure(host: str, note: str) -> failures.ZeppImportError:
    """Why an OLDER page could not be read. Never a short history: that would be silent."""
    if note.startswith(BUSY):
        return failures.zepp_busy()
    if note.startswith(UNREACHABLE):
        return failures.no_network("Zepp for an older page of workouts", host_of(host), note)
    return failures.zepp_api_changed("an older page of workouts", note)


def _feed_failure(tried: list[str]) -> failures.ZeppImportError:
    """The one failure that best explains why no host produced a workout."""
    notes = [line.split(": ", 1)[1] for line in tried]
    if any(note == _EMPTY for note in notes):
        return failures.zepp_no_workouts(tried)
    if notes and all(note.startswith(REFUSED) for note in notes):
        return failures.zepp_token_refused(tried)
    if notes and all(note.startswith(UNREACHABLE) for note in notes):
        return failures.no_network("Zepp", tried[0].split(": ", 1)[0], notes[0])
    if notes and all(note.startswith((BUSY, UNREACHABLE)) for note in notes):
        return failures.zepp_busy()
    moved = next((note for note in notes if note.startswith(REDIRECTED)), None)
    if moved is not None:
        return failures.zepp_elsewhere(moved.removeprefix(REDIRECTED))
    odd = next((n for n in notes if not n.startswith((UNREACHABLE, REFUSED, BUSY))), "no host")
    return failures.zepp_api_changed("the workout list", odd)
