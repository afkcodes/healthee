"""Synthetic Zepp payloads in the real wire shape.

The shapes are the ones real accounts return (README, "Sources"): a summary is a flat
object whose numbers are mostly STRINGS, and a detail carries its track as parallel
`;`-separated lists. The values are invented. The route sits at 10 N, 20 E, in the Sahara,
so nothing here is anybody's run.
"""

from __future__ import annotations

SOURCE = "run.411.huami.com"
START_LAT_E8 = 1_000_000_000  # 10.0 degrees
START_LNG_E8 = 2_000_000_000  # 20.0 degrees
NO_ALTITUDE_CM = -2_000_000


def summary(track_id: int, *, cloud_type: int = 1, minutes: float = 31, **over: object) -> dict:
    """One history record. `over` replaces or adds fields; a value of None removes one."""
    seconds = round(minutes * 60)
    record: dict[str, object] = {
        "trackid": str(track_id),
        "source": SOURCE,
        "type": cloud_type,
        "end_time": str(track_id + seconds),
        "run_time": str(seconds),
        "dis": "2701",
        "calorie": "296.0",
        "avg_heart_rate": "133.0",
        "max_heart_rate": 158,
        "min_heart_rate": 97,
        "parent_trackid": 0,
        "auto_recognition": False,
        "app_name": "com.huami.midong",
        "version": 15,
        "city": "",
    }
    record.update(over)
    return {key: value for key, value in record.items() if value is not None}


def detail(
    track_id: int,
    *,
    points: int = 120,
    step_s: int = 5,
    altitude_cm: int = 41_200,
    trailing: bool = True,
    **over: object,
) -> dict:
    """One workout detail with a straight, evenly sampled track of `points` fixes."""
    end = ";" if trailing else ""
    times = ["0"] + [str(step_s)] * (points - 1)
    positions = [f"{START_LAT_E8},{START_LNG_E8}"] + ["1500,2300"] * (points - 1)
    body: dict[str, object] = {
        "trackid": track_id,
        "source": SOURCE,
        "version": 15,
        "time": ";".join(times) + end,
        "longitude_latitude": ";".join(positions) + end,
        "altitude": ";".join([str(altitude_cm)] * points) + end,
        "accuracy": "",
        "heart_rate": "",
        "pause": "",
    }
    body.update(over)
    return body
