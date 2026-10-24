"""What an import reads from and writes to Healthee, through the app's own endpoints.

Nothing here is privileged. It reads what is already stored, and writes through
`POST /ingest/helio` and `POST /api/workout/gps` — the two calls
`apps/mobile/lib/data/push/push_client.dart` and `data/gps/gps_repository.dart` make. The
server validates and derives exactly as it does for the app, which is the point: an import
that bypassed the API would bypass the bounds in `ingest/models.py` and the derive pass
that follows a push.

## The ingest credential is minted and revoked per run

`/ingest/helio` takes a device token, and a device token is long-lived
(`core/device_token.py`). This tool is not a device, so it mints one, pushes, and revokes
it in the same breath; nothing is left on the account or on disk. A run that was killed
between the two leaves a token behind under a label only this tool uses, and the next run
revokes it before doing anything else (`revoke_leftovers`).
"""

from __future__ import annotations

from collections.abc import Callable, Mapping, Sequence
from dataclasses import dataclass

from zepp_import import failures
from zepp_import.healthee_rows import (
    ExistingTrack,
    ExistingWorkout,
    existing_track,
    existing_workout,
    next_page_day,
    read_all,
)
from zepp_import.healthee_session import HealtheeSession

# A push re-derives every day it touches and a route is scored on arrival. The reverse
# proxy gives up at 180 s (`infra/nginx`), so this waits a little longer than it does.
_WRITE_TIMEOUT_S = 200.0
_ACTIVITY_PAGE_ROWS = 100  # `read/fitness.py::workouts_list` limit
_MAX_ACTIVITY_PAGES = 40
TRACK_LIST_LIMIT = 100  # `read/gps.py::list_gps_tracks` ceiling
# Small on purpose: a push re-derives every day it touches before it answers, and a
# hundred days in one request is how an import meets the proxy's timeout. The server's own
# cap (`ingest/models.py::_MAX_WORKOUTS`, 500) is far above this.
_PUSH_CHUNK = 25
_TOKEN_LABEL = "zepp-import (temporary)"
_ROUTE_REFUSAL_STATUSES = (400, 409, 413, 422)
TOKEN_LEFT = (
    "The temporary ingest token could not be revoked. Run this tool again: it revokes "
    "what an earlier run left behind before it does anything else."
)
Stored = Callable[[Sequence[Mapping[str, object]]], None]


@dataclass(frozen=True)
class PushResult:
    """What a summary push stored, and whether its throwaway credential is gone again."""

    workouts: int
    days_derived: int
    token_revoked: bool


def _count(value: object) -> int:
    return value if isinstance(value, int) and not isinstance(value, bool) else 0


class HealtheeApi:
    """The reads and writes of an import, over a signed-in `HealtheeSession`."""

    def __init__(self, session: HealtheeSession) -> None:
        self._session = session
        self.session = session
        self.base_url = session.base_url

    def _get(self, step: str, path: str) -> dict:
        return self._session.object(step, self._session.call(step, "GET", path))

    # ── reads ────────────────────────────────────────────────────────────────

    def existing_workouts(self, since_s: float) -> list[ExistingWorkout]:
        """Every listed workout that starts at or after `since_s`, oldest first.

        `/api/activity` returns the newest hundred ending at a day, so older ones are
        reached by asking again for an earlier day. A full page that adds nothing new is a
        named failure, not a quiet stop: stopping early would make stored sessions look
        absent, and absent sessions are what this tool writes.
        """
        found: dict[int, ExistingWorkout] = {}
        day: str | None = None
        for _ in range(_MAX_ACTIVITY_PAGES):
            body = self._get("the workout list", "/api/activity" + (f"?day={day}" if day else ""))
            listed = body.get("workouts")
            rows = read_all("the workout list", listed, existing_workout, ("start_iso",))
            fresh = [w for w in rows if w.start_ms not in found]
            found.update({w.start_ms: w for w in fresh})
            if len(rows) < _ACTIVITY_PAGE_ROWS or min(w.start_s for w in rows) < since_s:
                return sorted(found.values(), key=lambda w: w.start_ms)
            day = next_page_day(min(w.start_s for w in rows), body.get("date"))
            if not fresh or day is None:
                break
        raise failures.healthee_refused("the workout list", 200, "paging made no progress")

    def existing_tracks(self) -> list[ExistingTrack]:
        """The newest GPS tracks already stored (the server caps the list at 100)."""
        body = self._get("the route list", f"/api/workout/gps?limit={TRACK_LIST_LIMIT}")
        times = ("start_ts", "end_ts")
        return read_all("the route list", body.get("tracks"), existing_track, times, ("track_id",))

    # ── writes ───────────────────────────────────────────────────────────────

    def push_track(self, body: Mapping[str, object]) -> dict:
        """Send one route and return the server's verdict on it.

        A refusal of THIS route (a 4xx about its content) comes back as a verdict, so one
        bad track does not end the run; anything else is a named failure.
        """
        reply = self._session.call(
            "a route", "POST", "/api/workout/gps", dict(body), timeout_s=_WRITE_TIMEOUT_S
        )
        if reply.status in _ROUTE_REFUSAL_STATUSES:
            return {"ok": False, "reason": f"HTTP {reply.status}: {self._session.reason(reply)}"}
        return self._session.object("a route", reply)

    def push_workouts(
        self, workouts: Sequence[Mapping[str, object]], stored: Stored = lambda _chunk: None
    ) -> PushResult:
        """Send workout summaries through `/ingest/helio` under a throwaway device token.

        `stored` is called with each chunk the server has accepted, so the caller's record
        of what was written is right even when a later chunk fails.
        """
        device_token, token_id = self._mint()
        count = derived = 0
        try:
            for offset in range(0, len(workouts), _PUSH_CHUNK):
                chunk = list(workouts[offset : offset + _PUSH_CHUNK])
                summary = self._push_chunk(chunk, device_token)
                stored(chunk)
                count += _count(summary.get("workouts"))
                derived += _count(summary.get("days_derived"))
        except failures.ZeppImportError as failure:
            if not self._revoke(token_id):
                failure.remedy = f"{failure.remedy} {TOKEN_LEFT}"
            raise
        return PushResult(count, derived, token_revoked=self._revoke(token_id))

    def _push_chunk(self, chunk: list[Mapping[str, object]], device_token: str) -> dict:
        step = "the workouts"
        reply = self._session.call(
            step,
            "POST",
            "/ingest/helio",
            {"workouts": chunk},
            bearer=device_token,
            timeout_s=_WRITE_TIMEOUT_S,
        )
        return self._session.object(step, reply)

    # ── the throwaway ingest token ───────────────────────────────────────────

    def _mint(self) -> tuple[str, str]:
        step = "an ingest token"
        minted = self._session.call(step, "POST", "/api/device", {"label": _TOKEN_LABEL})
        if minted.status == 409:
            raise failures.healthee_too_many_tokens()
        row = self._session.object(step, minted)
        device_token, token_id = row.get("device_token"), row.get("id")
        if not isinstance(device_token, str) or not device_token or not isinstance(token_id, str):
            raise failures.healthee_refused(step, 200, "no token in the reply")
        return device_token, token_id

    def _revoke(self, token_id: str) -> bool:
        """Revoke one device token. False means it is still live, and the owner is told."""
        step = "revoking the ingest token"
        try:
            reply = self._session.call(step, "DELETE", f"/api/device/{token_id}")
        except failures.ZeppImportError:
            return False  # not swallowed: surfaced as `PushResult.token_revoked` / `TOKEN_LEFT`
        return reply.status in (204, 404)

    def revoke_leftovers(self) -> int:
        """Revoke tokens an interrupted earlier run left behind. Returns how many.

        Called once per run, straight after sign-in, so "run it again" is always a
        complete answer to a token this tool failed to revoke.
        """
        step = "the device-token list"
        rows = self._session.decoded(step, self._session.call(step, "GET", "/api/device"))
        if not isinstance(rows, list):
            raise failures.healthee_refused(step, 200, "a reply that is not a list")
        mine = [r.get("id") for r in rows if isinstance(r, dict) and r.get("label") == _TOKEN_LABEL]
        return sum(1 for token_id in mine if isinstance(token_id, str) and self._revoke(token_id))
