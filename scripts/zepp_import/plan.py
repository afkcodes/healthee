"""What an import WOULD do — decided before anything is written, and shown first.

Pure functions: a Zepp workout, what Healthee already holds, and a verdict. No network
and no clock, so every rule below has a test that states it.

## The rules, and the defect each one prevents

**A summary and a route are decided separately.** They are two rows in two tables
(`workout`, `gps_track`) and either can already exist without the other.

Summaries:

 * *Auto-detected bouts are never imported.* The strap already reports them over BLE;
   the cloud copy would add the same minutes and calories a second time.
 * *An unknown sport is not imported.* `sports.py` says why: a cloud type written as a
   device code is filed under the wrong sport's name.
 * *Under ten minutes is not imported.* `read/fitness.py::_MIN_WORKOUT_S` hides those
   from every list, so the row would change the day's calories and be visible nowhere.
 * *The same session is never written twice.* A row starting within two minutes is the
   same session; it is only UPDATED. What it lacks is filled in — distance, heart
   rate, calories — and nothing it already measured is replaced.
 * *A sport label is corrected only on evidence.* A stored "Activity" becomes the sport
   Zepp recorded. And a stored code that is exactly Zepp's CLOUD type for that same
   session, where the right device code is a different number, was written in the wrong
   enum (`sports.py`): it is the "Pool swim" that was a treadmill run. It is fixed, and
   the plan names the label it had so the owner can see what is being changed.
 * *An overlapping session keeps its calories and the import brings none.*
   `derive/energy.py` SUMS workout calories, so two rows over the same minutes would
   count them twice. The server's own `workout_without_device_calories` caveat then says
   the import carried none.

Routes:

 * *A route follows its session.* It is sent only when the session's summary is in
   Healthee once this run is done — imported now, or already there. A session this tool
   declines to import does not half-exist as a route.
 * *One route per run.* If Healthee already holds a track over the same minutes — the
   owner recorded it in both apps — the import leaves it alone. A second track would
   list the run twice and score it twice, and which of the two then owns the day's one
   measured-fitness cell is decided by precedence, not by which was the better recording
   (`derive/gps.py::_store`).
 * *No duplicate check, no import.* Healthee lists only its newest hundred tracks. A
   session older than the oldest of a full list cannot be checked against what is
   stored, so its route is left out rather than risked.
 * *A route id is derived from the workout, not generated.* Re-running the import sends
   the same id, and `read/gps.py::ingest_gps_track` answers with the stored track.

## Why updating a stored row is safe

An update sends `start_ts` and only the fields being added. The server's upsert
COALESCEs every other column (`ingest/upsert.py::upsert_workouts`), so what the strap
measured is untouched. `healthee_session.py` says why a server too old for that is never
reached.

The same upsert lets a value that IS sent replace the stored one. So a field is added
only when the server reported it as null (`healthee_rows.ExistingWorkout.lacks`), never
because a reply happened not to mention it.
"""

from __future__ import annotations

import uuid
from collections.abc import Sequence
from dataclasses import dataclass
from enum import Enum

from zepp_import import sports
from zepp_import.healthee_rows import ExistingTrack, ExistingWorkout
from zepp_import.localtime import utc_iso
from zepp_import.sports import HealtheeSport
from zepp_import.zepp_parse import Track, ZeppWorkout

SAME_SESSION_S = 120
MIN_LISTED_S = 600  # `read/fitness.py::_MIN_WORKOUT_S`
MIN_ROUTE_POINTS = 10  # `read/gps.py::ingest_gps_track`
# Device codes that say nothing about the sport: unset, and the auto-detected bout.
_GENERIC_SPORT_CODES = (0, 44)
_ROUTE_NAMESPACE = uuid.UUID("29ac2e53-a283-4e8c-97b6-55ffe8b7e3fe")


class Verdict(str, Enum):
    """What happens to one summary or one route.

    `enum.StrEnum` is Python 3.11 and this tool runs on 3.10. `__str__` is written out
    because the two disagree about what a `str`-mixin member formats as: its value
    before 3.11, its name from 3.11 on.
    """

    IMPORT = "import"
    UPDATE = "update"
    PRESENT = "already there"
    SKIP = "skip"

    def __str__(self) -> str:
        return self.value


@dataclass(frozen=True)
class Step:
    """One decision: the verdict, why, and the request body when there is one to send.

    `shown` is False for a route verdict that says nothing the summary's has not already
    said — a strength session has no route to skip — so the plan stays readable.
    """

    verdict: Verdict
    reason: str = ""
    payload: dict | None = None
    shown: bool = True

    @property
    def writes(self) -> bool:
        return self.payload is not None


@dataclass(frozen=True)
class Decision:
    """Everything decided about one Zepp workout."""

    workout: ZeppWorkout
    sport: HealtheeSport | None
    summary: Step
    route: Step
    route_points: int = 0


def route_id(healthee_user_id: str, track_id: int) -> str:
    """The id a Zepp workout's route always gets on this account.

    The owner is in the name because `gps_track.id` is a global primary key: without it,
    two Healthee accounts importing from one Zepp account would collide on the id and the
    second would be refused as an "identity conflict".
    """
    return str(uuid.uuid5(_ROUTE_NAMESPACE, f"{healthee_user_id}/zepp/{track_id}"))


def _overlaps(start_s: float, end_s: float, other_start_s: float, other_end_s: float) -> bool:
    return start_s < other_end_s and other_start_s < end_s


def _same_session(
    workout: ZeppWorkout, existing: Sequence[ExistingWorkout]
) -> ExistingWorkout | None:
    near = [row for row in existing if abs(row.start_s - workout.start_s) <= SAME_SESSION_S]
    return min(near, key=lambda row: abs(row.start_s - workout.start_s)) if near else None


def _not_importable(workout: ZeppWorkout) -> str | None:
    """Why this workout's summary is not written at all, or None."""
    if workout.is_child:
        return "one leg of a multi-sport session"
    if workout.auto_detected or sports.is_auto_detected(workout.cloud_type):
        return "auto-detected; the strap reports it"
    if sports.healthee_sport(workout.cloud_type) is None:
        return f"Zepp type {workout.cloud_type} has no Healthee sport"
    if workout.elapsed_s < MIN_LISTED_S:
        return "under 10 min; Healthee lists none"
    return None


_SHOWN_AS = {
    "distance_m": "distance",
    "calories": "calories",
    "avg_hr": "heart rate",
    "max_hr": "heart rate",
    "min_hr": "heart rate",
}


def _missing_measurements(
    workout: ZeppWorkout, row: ExistingWorkout, shares_minutes: bool
) -> dict[str, object]:
    """The columns the stored row lacks and Zepp measured.

    Calories are held back when the row shares minutes with another stored session:
    `derive/energy.py` sums them, and the overlap rule above is what left them out.
    """
    measured = {
        "distance_m": workout.distance_m,
        "calories": None if shares_minutes else workout.calories_kcal,
        "avg_hr": workout.avg_hr,
        "max_hr": workout.max_hr,
        "min_hr": workout.min_hr,
    }
    return {c: v for c, v in measured.items() if c in row.lacks and v is not None}


def _completion(
    workout: ZeppWorkout, sport: HealtheeSport, row: ExistingWorkout, shares_minutes: bool
) -> Step:
    """Fill what an existing row of the same session lacks; replace nothing it measured."""
    missing = _missing_measurements(workout, row, shares_minutes)
    payload: dict = {"start_ts": row.start_ms, **missing}
    added = list(dict.fromkeys(_SHOWN_AS[column] for column in missing))
    said: list[str] = []
    if row.sport in _GENERIC_SPORT_CODES:
        payload["sport"] = sport.code
        added.append("sport")
    elif row.sport is not None and row.sport == workout.cloud_type != sport.code:
        payload["sport"] = sport.code
        said.append(f"sport was filed as {sports.device_sport_name(row.sport)}")
    if added:
        said.insert(0, "adds " + ", ".join(added))
    if not said:
        return Step(Verdict.PRESENT)
    return Step(Verdict.UPDATE, "; ".join(said), payload)


def plan_summary(workout: ZeppWorkout, existing: Sequence[ExistingWorkout]) -> Step:
    """The verdict for one workout's summary row."""
    refusal = _not_importable(workout)
    sport = sports.healthee_sport(workout.cloud_type)
    if refusal or sport is None:
        return Step(Verdict.SKIP, refusal or "")
    same = _same_session(workout, existing)
    if same is not None:
        others = [row for row in existing if row is not same]
        shares = any(_overlaps(same.start_s, same.end_s, r.start_s, r.end_s) for r in others)
        return _completion(workout, sport, same, shares)
    payload: dict = {
        "start_ts": workout.start_s * 1000,
        "sport": sport.code,
        "duration_s": workout.elapsed_s,
        "calories": workout.calories_kcal,
        "distance_m": workout.distance_m,
        "avg_hr": workout.avg_hr,
        "max_hr": workout.max_hr,
        "min_hr": workout.min_hr,
    }
    if any(_overlaps(workout.start_s, workout.end_s, r.start_s, r.end_s) for r in existing):
        payload["calories"] = None
        return Step(
            Verdict.IMPORT,
            "overlaps a stored session; calories left out",
            payload,
        )
    return Step(Verdict.IMPORT, "", payload)


def wants_track(workout: ZeppWorkout) -> bool:
    """Whether a workout can have a GPS route worth one more request to Zepp."""
    if workout.auto_detected or workout.is_child or workout.distance_m is None:
        return False
    return sports.can_have_route(workout.cloud_type)


@dataclass(frozen=True)
class StoredTracks:
    """The routes Healthee listed, and how far back that list can be trusted.

    `horizon_s` is the start of the oldest listed track when the list came back FULL —
    there may be older tracks it did not show. None when the list is complete.
    """

    tracks: Sequence[ExistingTrack] = ()
    horizon_s: float | None = None

    @classmethod
    def listed(cls, tracks: Sequence[ExistingTrack], list_limit: int) -> StoredTracks:
        full = len(tracks) >= list_limit
        return cls(tuple(tracks), min(t.start_s for t in tracks) if full else None)


def route_precheck(
    workout: ZeppWorkout, summary: Step, stored: StoredTracks, healthee_user_id: str
) -> Step | None:
    """A route verdict that needs no detail from Zepp, or None when the detail is needed."""
    if not wants_track(workout):
        return Step(Verdict.SKIP, "no GPS for this kind of session", shown=False)
    if summary.verdict is Verdict.SKIP:
        return Step(Verdict.SKIP, "its session is not imported", shown=False)
    mine = route_id(healthee_user_id, workout.track_id)
    if any(track.track_id == mine for track in stored.tracks):
        return Step(Verdict.PRESENT)
    if any(_overlaps(workout.start_s, workout.end_s, t.start_s, t.end_s) for t in stored.tracks):
        return Step(Verdict.PRESENT, "Healthee has one for these minutes")
    if stored.horizon_s is not None and workout.start_s < stored.horizon_s:
        return Step(Verdict.SKIP, "older than the routes Healthee lists")
    return None


def plan_route(workout: ZeppWorkout, track: Track, healthee_user_id: str) -> Step:
    """The verdict for a route whose detail has been fetched and parsed."""
    if track.refused:
        return Step(Verdict.SKIP, track.refused)
    if len(track.points) < MIN_ROUTE_POINTS:
        return Step(Verdict.SKIP, f"only {len(track.points)} usable GPS points")
    end_s = max(workout.end_s, track.points[-1].ts_s)
    payload = {
        "client_id": route_id(healthee_user_id, workout.track_id),
        "start_iso": utc_iso(workout.start_s),
        "end_iso": utc_iso(end_s),
        "points": [[p.ts_s, p.lat, p.lng, p.ele_m] for p in track.points],
    }
    return Step(Verdict.IMPORT, "", payload)
