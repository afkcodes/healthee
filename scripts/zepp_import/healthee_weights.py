"""Healthee's side of the weight sync: read its weigh-ins, write one through `/api/log`.

`POST /api/log` with `type: weight` is the app's own path for a weigh-in
(`read/logs.py::record_log`, called by the profile editor through `read/profile_edit.py`).
It upserts on the instant, so writing at an instant Healthee already holds corrects that
row. The server bounds the mass (`core/bounds.py`), so a write cannot store what the app
could not.
"""

from __future__ import annotations

from zepp_import import failures
from zepp_import.healthee_session import HealtheeSession
from zepp_import.weights import HealtheeWeights, Weighing

_HISTORY_DAYS = 1825  # `read/history.py::MAX_DAYS`
_MS = 1000


def _number(value: object) -> float | None:
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        return float(value)
    return None


def existing_weights(session: HealtheeSession) -> HealtheeWeights:
    """The last weigh-in of each local day, and the newest one with its instant."""
    step = "the weight history"
    body = session.object(
        step, session.call(step, "GET", f"/api/history?metric=weight_kg&days={_HISTORY_DAYS}")
    )
    series = body.get("series")
    if not isinstance(series, list):
        raise failures.healthee_refused(step, 200, "no series list in the reply")
    by_day: dict[str, float] = {}
    for point in series:
        kg = _number(point.get("value")) if isinstance(point, dict) else None
        day = point.get("day") if isinstance(point, dict) else None
        if kg is None or not isinstance(day, str):
            raise failures.healthee_refused(step, 200, "a point without a day and a value")
        by_day[day] = kg
    step = "the newest weigh-in"
    recent = session.object(step, session.call(step, "GET", "/api/log/recent"))
    entries = recent.get("entries")
    if not isinstance(entries, list):
        raise failures.healthee_refused(step, 200, "no entries list in the reply")
    newest = None
    for entry in entries:
        if isinstance(entry, dict) and entry.get("type") == "weight":
            stamp, kg = _number(entry.get("ts")), _number(entry.get("amount"))
            if stamp is None or kg is None:
                raise failures.healthee_refused(step, 200, "a weight without a time and a value")
            newest = Weighing(ts_s=int(stamp) // _MS, kg=kg)
    return HealtheeWeights(by_day=by_day, newest=newest)


def push_weight(session: HealtheeSession, ts_s: int, kg: float) -> None:
    """Write one weigh-in at `ts_s`. A refusal is a named failure."""
    step = "a weight"
    reply = session.call(
        step, "POST", "/api/log", {"type": "weight", "amount": kg, "at": ts_s * _MS}
    )
    verdict = session.object(step, reply)
    if verdict.get("ok") is not True:
        raise failures.healthee_refused(step, reply.status, "the server did not store it")
