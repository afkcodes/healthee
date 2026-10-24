"""Zepp's workout JSON, parsed into the two things an import needs: a summary and a track.

Pure functions over decoded JSON. No I/O, no clock, no network — which is what lets the
tests feed them fixtures instead of Zepp.

## The formats, as read off real payloads

A history SUMMARY is a flat object of mostly STRINGS: `trackid` is the start instant in
epoch seconds and doubles as the workout's id; `end_time` is epoch seconds; `run_time` is
ACTIVE seconds (pauses excluded); `dis` is metres; `-1` (number or string) means "not
measured" throughout.

A DETAIL holds the track as parallel, index-aligned, `;`-separated lists:

| field                | cell          | meaning                                          |
|----------------------|---------------|--------------------------------------------------|
| `time`               | `int`         | seconds since the PREVIOUS point (a delta)       |
| `longitude_latitude` | `lat,lon`     | deltas, in degrees x 1e8; the first is absolute. |
|                      |               | Latitude comes FIRST despite the field's name.   |
|                      |               | An empty cell is a point with no fix.            |
| `altitude`           | `int`         | absolute centimetres; `-2000000` = no reading    |
| `accuracy`           | `int`         | metres; often absent entirely                    |

A trailing `;` may or may not be present. Two consecutive points can carry a zero time
delta; Healthee requires strictly increasing timestamps, so the later one is dropped.
"""

from __future__ import annotations

import math
from collections.abc import Iterator, Mapping
from dataclasses import dataclass, field

_COORDINATE_SCALE = 1e8
_NO_ALTITUDE_CM = -2_000_000
# The Healthee recorder skips a fix worse than this (`data/gps/gps_run.dart::maxAccuracyM`).
MAX_ACCURACY_M = 50
# `read/gps_request.py::GpsTrackIn.points` max_length.
MAX_TRACK_POINTS = 28_800
# `ingest/models.py::WorkoutIn.duration_s` upper bound.
_MAX_DURATION_S = 7 * 24 * 3600
_HR_RANGE_BPM = (25, 250)


@dataclass(frozen=True)
class ZeppWorkout:
    """One workout summary, with every "not measured" already turned into None."""

    track_id: int
    source: str
    cloud_type: int
    start_s: int
    end_s: int
    active_s: int | None
    distance_m: float | None
    calories_kcal: int | None
    avg_hr: int | None
    max_hr: int | None
    min_hr: int | None
    auto_detected: bool
    is_child: bool

    @property
    def elapsed_s(self) -> int:
        """Wall-clock seconds from start to end, pauses included."""
        return self.end_s - self.start_s


@dataclass(frozen=True)
class TrackPoint:
    """One GPS fix: epoch seconds, degrees, and metres above sea level when known."""

    ts_s: int
    lat: float
    lng: float
    ele_m: float | None


@dataclass(frozen=True)
class Track:
    """A parsed track. `refused` is set, and `points` empty, when it cannot be trusted."""

    points: tuple[TrackPoint, ...] = ()
    dropped: Mapping[str, int] = field(default_factory=dict)
    refused: str | None = None


def _number(value: object) -> float | None:
    """A finite number from a JSON number or numeric string; None for anything else."""
    if isinstance(value, bool) or value is None:
        return None
    if not isinstance(value, (int, float, str)):
        return None
    try:
        number = float(value)
    except ValueError:
        return None
    return number if math.isfinite(number) else None


def _positive_int(value: object) -> int | None:
    number = _number(value)
    return round(number) if number is not None and number > 0 else None


def _heart_rate(value: object) -> int | None:
    number = _number(value)
    if number is None or not _HR_RANGE_BPM[0] <= number <= _HR_RANGE_BPM[1]:
        return None
    return round(number)


def parse_summary(raw: Mapping[str, object]) -> ZeppWorkout | None:
    """One history record, or None when it has no usable start, end or type."""
    track_id = _positive_int(raw.get("trackid"))
    cloud_type = _number(raw.get("type"))
    if track_id is None or cloud_type is None:
        return None
    active_s = _positive_int(raw.get("run_time"))
    end_s = _positive_int(raw.get("end_time"))
    if end_s is None or end_s <= track_id:
        end_s = track_id + active_s if active_s else None
    if end_s is None or not 0 < end_s - track_id <= _MAX_DURATION_S:
        return None
    distance_m = _number(raw.get("dis"))
    return ZeppWorkout(
        track_id=track_id,
        source=str(raw.get("source") or ""),
        cloud_type=int(cloud_type),
        start_s=track_id,
        end_s=end_s,
        active_s=active_s,
        distance_m=distance_m if distance_m is not None and distance_m > 0 else None,
        calories_kcal=_positive_int(raw.get("calorie")),
        avg_hr=_heart_rate(raw.get("avg_heart_rate")),
        max_hr=_heart_rate(raw.get("max_heart_rate")),
        min_hr=_heart_rate(raw.get("min_heart_rate")),
        auto_detected=raw.get("auto_recognition") in (True, 1, "1", "true"),
        is_child=(_positive_int(raw.get("parent_trackid")) is not None),
    )


def _cells(value: object) -> list[str]:
    """A `;`-separated list as cells, minus the one empty cell a trailing `;` leaves."""
    if not isinstance(value, str) or not value:
        return []
    cells = value.split(";")
    return cells[:-1] if cells[-1] == "" else cells


def _int_cell(cell: str) -> int | None:
    try:
        return int(cell)
    except ValueError:
        return None


def _pair_cell(cell: str) -> tuple[int, int] | None:
    parts = cell.split(",")
    if len(parts) != 2:
        return None
    lat, lng = _int_cell(parts[0]), _int_cell(parts[1])
    return (lat, lng) if lat is not None and lng is not None else None


def _altitude_m(cells: list[str], index: int) -> float | None:
    if index >= len(cells):
        return None
    centimetres = _int_cell(cells[index])
    if centimetres is None or centimetres == _NO_ALTITUDE_CM:
        return None
    return centimetres / 100.0


def _too_inaccurate(cells: list[str], index: int) -> bool:
    if index >= len(cells):
        return False
    accuracy_m = _int_cell(cells[index])
    return accuracy_m is not None and accuracy_m > MAX_ACCURACY_M


def _thinned(points: list[TrackPoint]) -> list[TrackPoint]:
    """`points` sampled down to the server's cap, both ends kept. Real fixes only."""
    last = len(points) - 1
    return [points[round(i * last / (MAX_TRACK_POINTS - 1))] for i in range(MAX_TRACK_POINTS)]


class _TrackRefusedError(Exception):
    """The track cannot be trusted; the message is the reason shown to the owner."""


def _raw_fixes(
    times: list[str], positions: list[str]
) -> Iterator[tuple[int, int, tuple[int, int] | None]]:
    """Each point as (index, seconds since start, absolute (lat, lng) x 1e8 or None).

    The deltas are accumulated here and nowhere else, so a point that is later dropped
    still moves the running position and clock — which is what the encoding requires.
    """
    elapsed_s = lat_e8 = lng_e8 = 0
    for index, (time_cell, position_cell) in enumerate(zip(times, positions, strict=True)):
        delta_s = _int_cell(time_cell)
        if delta_s is None or delta_s < 0:
            raise _TrackRefusedError("a time step in the track is not a number")
        elapsed_s += delta_s
        if position_cell == "":
            yield index, elapsed_s, None
            continue
        pair = _pair_cell(position_cell)
        if pair is None:
            raise _TrackRefusedError("a position in the track is not a number pair")
        lat_e8, lng_e8 = lat_e8 + pair[0], lng_e8 + pair[1]
        yield index, elapsed_s, (lat_e8, lng_e8)


def _drop_reason(
    last: TrackPoint | None, ts_s: int, fix_e8: tuple[int, int], accuracies: list[str], index: int
) -> str | None:
    """Why this fix cannot be sent, or None. Mirrors the server's own point validation."""
    lat_e8, lng_e8 = fix_e8
    if not (abs(lat_e8) <= 90 * _COORDINATE_SCALE and abs(lng_e8) <= 180 * _COORDINATE_SCALE):
        return "out_of_range"
    if _too_inaccurate(accuracies, index):
        return "inaccurate"
    if last is not None and ts_s <= last.ts_s:
        return "not_later"
    return None


def _kept_points(
    detail: Mapping[str, object], start_s: int, times: list[str], positions: list[str]
) -> tuple[list[TrackPoint], dict[str, int]]:
    altitudes = _cells(detail.get("altitude"))
    accuracies = _cells(detail.get("accuracy"))
    points: list[TrackPoint] = []
    dropped: dict[str, int] = {}
    for index, elapsed_s, fix_e8 in _raw_fixes(times, positions):
        ts_s = start_s + elapsed_s
        reason = (
            "no_fix"
            if fix_e8 is None
            else _drop_reason(points[-1] if points else None, ts_s, fix_e8, accuracies, index)
        )
        if reason or fix_e8 is None:
            dropped[reason or "no_fix"] = dropped.get(reason or "no_fix", 0) + 1
            continue
        points.append(
            TrackPoint(
                ts_s=ts_s,
                lat=fix_e8[0] / _COORDINATE_SCALE,
                lng=fix_e8[1] / _COORDINATE_SCALE,
                ele_m=_altitude_m(altitudes, index),
            )
        )
    return points, dropped


def parse_track(detail: Mapping[str, object], start_s: int) -> Track:
    """The GPS track out of one workout detail.

    Refused, rather than repaired, when the time and position lists differ in length:
    they are index-aligned, so a mismatch means every later fix could be paired with the
    wrong instant, and a route drawn from that would be a route that was never run.
    """
    times = _cells(detail.get("time"))
    positions = _cells(detail.get("longitude_latitude"))
    if not positions or not times:
        return Track(refused="no GPS track")
    if len(times) != len(positions):
        return Track(refused=f"track lists do not line up ({len(times)} vs {len(positions)})")
    try:
        points, dropped = _kept_points(detail, start_s, times, positions)
    except _TrackRefusedError as refusal:
        return Track(refused=str(refusal))
    if len(points) > MAX_TRACK_POINTS:
        dropped["thinned"] = len(points) - MAX_TRACK_POINTS
        points = _thinned(points)
    return Track(points=tuple(points), dropped=dropped)
