"""The Zepp half of a run: read the window, fetch what each route needs, decide.

Reads only. Everything this returns is a plan (`plan.py`); nothing is written to Healthee
until the owner has seen it.

## Order

Summaries are decided oldest first, and each one this run WILL import is added to what
the later ones are checked against. Two Zepp sessions over the same minutes would
otherwise both arrive with their calories, and `derive/energy.py` sums them.

Details are fetched only for sessions whose route can still be imported once the cheap
checks have passed — one request each, with a pause between them. This is somebody
else's unofficial API and the politest client is the one that keeps working.
"""

from __future__ import annotations

from collections.abc import Callable, Sequence
from dataclasses import dataclass

from zepp_import import failures, plan, sports
from zepp_import.healthee_rows import MEASUREMENT_COLUMNS, ExistingWorkout
from zepp_import.plan import Decision, Step, StoredTracks, Verdict
from zepp_import.shapes import fields
from zepp_import.zepp_history import Feed, ZeppHistory
from zepp_import.zepp_parse import ZeppWorkout, parse_summary, parse_track

# The fields `zepp_parse.parse_summary` cannot do without.
_NEEDED_FIELDS = ("trackid", "type", "end_time", "run_time", "source")
_PAUSE_S = 0.25
NO_ROUTES_ASKED = "routes were not asked for"


@dataclass(frozen=True)
class Stored:
    """What Healthee already holds for the owner."""

    user_id: str
    workouts: Sequence[ExistingWorkout]
    tracks: StoredTracks


@dataclass(frozen=True)
class Gathered:
    """The plan, and enough about how it was reached to say when something looks wrong."""

    host: str
    decisions: tuple[Decision, ...]
    unreadable: int
    tracks_asked: int
    tracks_found: int


def read_workouts(feed: Feed) -> tuple[list[ZeppWorkout], int]:
    """The feed's records as workouts, oldest first, and how many could not be read.

    Records that all fail to parse are an API change, not an empty history: reporting
    "nothing to import" for a feed full of unreadable workouts is the silent failure.
    """
    by_id: dict[int, ZeppWorkout] = {}
    unreadable = 0
    for record in feed.records:
        workout = parse_summary(record)
        if workout is None:
            unreadable += 1
        else:
            by_id.setdefault(workout.track_id, workout)
    if feed.records and not by_id:
        raise failures.zepp_api_changed(
            "the workout list",
            f"{len(feed.records)} records, none readable: "
            f"{fields(feed.records[0], _NEEDED_FIELDS)}",
        )
    return sorted(by_id.values(), key=lambda w: w.start_s), unreadable


def _as_stored(workout: ZeppWorkout, payload: dict) -> ExistingWorkout:
    """A summary this run will import, as the row later decisions must not collide with."""
    return ExistingWorkout(
        start_ms=int(payload["start_ts"]),
        duration_s=workout.elapsed_s,
        sport=payload.get("sport"),
        lacks=frozenset(c for c in MEASUREMENT_COLUMNS if payload.get(c) is None),
    )


def plan_summaries(
    workouts: Sequence[ZeppWorkout], existing: Sequence[ExistingWorkout]
) -> list[tuple[ZeppWorkout, Step]]:
    """One summary verdict per workout, oldest first (see the module docstring)."""
    known = list(existing)
    planned: list[tuple[ZeppWorkout, Step]] = []
    for workout in workouts:
        step = plan.plan_summary(workout, known)
        if step.verdict is Verdict.IMPORT and step.payload is not None:
            known.append(_as_stored(workout, step.payload))
        planned.append((workout, step))
    return planned


class Gatherer:
    """Turns one Zepp feed into decisions, fetching a detail only where a route needs it."""

    def __init__(
        self,
        history: ZeppHistory,
        stored: Stored,
        *,
        want_routes: bool,
        notify: Callable[[str], None],
        pause: Callable[[float], None],
    ) -> None:
        self._history = history
        self._stored = stored
        self._want_routes = want_routes
        self._notify = notify
        self._pause = pause

    def gather(self, feed: Feed) -> Gathered:
        workouts, unreadable = read_workouts(feed)
        planned = plan_summaries(workouts, self._stored.workouts)
        early = [(w, summary, self._early_route(w, summary)) for w, summary in planned]
        asked = sum(1 for _w, _s, route in early if route is None)
        if asked:
            self._notify(f"reading {asked} route{'s' if asked != 1 else ''}")
        decisions = [
            self._decision(feed.host, workout, summary, route) for workout, summary, route in early
        ]
        found = sum(1 for d in decisions if d.route_points > 0)
        return Gathered(feed.host, tuple(reversed(decisions)), unreadable, asked, found)

    def _early_route(self, workout: ZeppWorkout, summary: Step) -> Step | None:
        if not self._want_routes:
            return Step(Verdict.SKIP, NO_ROUTES_ASKED)
        return plan.route_precheck(workout, summary, self._stored.tracks, self._stored.user_id)

    def _decision(
        self, host: str, workout: ZeppWorkout, summary: Step, route: Step | None
    ) -> Decision:
        points = 0
        if route is None:
            route, points = self._fetched_route(host, workout)
        sport = sports.healthee_sport(workout.cloud_type)
        return Decision(workout, sport, summary, route, points)

    def _fetched_route(self, host: str, workout: ZeppWorkout) -> tuple[Step, int]:
        self._pause(_PAUSE_S)
        detail = self._history.detail(host, workout.track_id, workout.source)
        if isinstance(detail, str):
            return Step(Verdict.SKIP, f"Zepp returned no track: {detail}"), 0
        track = parse_track(detail, workout.start_s)
        return plan.plan_route(workout, track, self._stored.user_id), len(track.points)
