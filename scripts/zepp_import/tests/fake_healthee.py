"""A stand-in for a Healthee server and its identity provider.

Each handler restates the server rule it stands in for, by file, because a fake that is
kinder than the server proves nothing:

 * `/ingest/helio` upserts on the start instant and COALESCEs every column, new value
   first (`ingest/upsert.py::upsert_workouts`); it takes a LIVE device token and nothing
   else (`core/request_auth.py::ingest_user`).
 * `/api/activity` lists sessions of ten minutes or more that start before the end of the
   asked-for local day, newest first, a hundred at most, and refuses a future day with a
   422 (`read/fitness.py::workouts_list`, `api/validation.py`).
 * `/api/workout/gps` validates a route the way `read/gps_request.py::GpsTrackIn` does,
   and treats a repeated id as the stored recording only when the window is the same
   (`read/gps.py::ingest_gps_track`).
 * `/api/device` mints, lists and revokes, with a cap (`api/routers/auth.py`).
"""

from __future__ import annotations

import json
import uuid
from dataclasses import dataclass, field
from datetime import date, datetime, time, timedelta

from zepp_import.localtime import UTC, zone_for
from zepp_import.tests.support import NOW_S, Request, json_reply, sentinel
from zepp_import.transport import Response

ORIGIN = "https://healthee.test"
AUTH_ORIGIN = "https://auth.healthee.test"
ANON_KEY = "anon-key-public-by-design"
JWT = sentinel("healthee-jwt")
USER_ID = "0b1e6f0e-58d5-4b2f-9b56-1f1f6e2f8a11"
_COLUMNS = ("sport", "duration_s", "calories", "distance_m", "avg_hr", "max_hr", "min_hr")
_MAX_LIVE_TOKENS = 10
_MAX_POINTS = 28_800
_LIST_ROWS = 100
_MIN_LISTED_S = 600
_WEEK_S = 7 * 24 * 3600


@dataclass
class FakeHealthee:
    email: str
    password: str
    timezone: str = "Asia/Kolkata"
    now_s: int = NOW_S
    workouts: dict[int, dict] = field(default_factory=dict)
    tracks: dict[str, dict] = field(default_factory=dict)
    tokens: dict[str, dict] = field(default_factory=dict)
    weights: dict[int, float] = field(default_factory=dict)  # epoch s -> kg
    pushes: list[dict] = field(default_factory=list)
    scoring: object = None
    forced: dict[tuple[str, str], Response] = field(default_factory=dict)
    auth_config: dict | None = None
    # `read/fitness.py::workouts_list` returns every measurement, null when unset.
    listed_columns: tuple[str, ...] = _COLUMNS[2:]

    def owns(self, origin: str) -> bool:
        return origin in (ORIGIN, AUTH_ORIGIN)

    # ── seeding, for tests ───────────────────────────────────────────────────

    def store_workout(self, start_s: int, **columns: object) -> None:
        row = {"sport": 0, "duration_s": 0, **dict.fromkeys(_COLUMNS[2:])}
        self.workouts[start_s * 1000] = {**row, **columns}

    def store_track(self, start_s: int, end_s: int, track_id: str | None = None) -> str:
        track_id = track_id or str(uuid.uuid4())
        self.tracks[track_id] = {"start_s": start_s, "end_s": end_s, "points": 10}
        return track_id

    def live_tokens(self) -> list[dict]:
        return [token for token in self.tokens.values() if token["live"]]

    # ── routing ──────────────────────────────────────────────────────────────

    def handle(self, request: Request) -> Response:
        forced = self.forced.get((request.method, request.path))
        if forced is not None:
            return forced
        if request.origin == AUTH_ORIGIN:
            return self._password_grant(request)
        if request.path == "/api/auth-config":
            config = {"supabase_url": AUTH_ORIGIN, "supabase_anon_key": ANON_KEY}
            return json_reply(200, config if self.auth_config is None else self.auth_config)
        if request.path == "/ingest/helio":
            return self._ingest(request)
        if request.headers.get("authorization") != f"Bearer {JWT}":
            return json_reply(401, {"detail": "Invalid token"})
        return self._api(request)

    def _api(self, request: Request) -> Response:
        key = (request.method, request.path)
        if key == ("GET", "/api/me"):
            return json_reply(200, {"id": USER_ID, "timezone": self.timezone})
        if key == ("GET", "/api/activity"):
            return self._activity(request.query.get("day"))
        if key == ("GET", "/api/workout/gps"):
            return self._track_list(int(request.query.get("limit", "30")))
        if key == ("POST", "/api/workout/gps"):
            return self._track_upload(json.loads(request.body or b"{}"))
        if key == ("GET", "/api/history") and request.query.get("metric") == "weight_kg":
            return self._weight_history()
        if key == ("GET", "/api/log/recent"):
            return self._weight_recent()
        if key == ("POST", "/api/log"):
            return self._log(json.loads(request.body or b"{}"))
        if request.path.startswith("/api/device"):
            return self._device(request)
        return json_reply(404, {"detail": "Not Found"})

    # `read/history.py::_weight_points`: the last weigh-in of each local day.
    def _weight_history(self) -> Response:
        days: dict[str, float] = {}
        for stamp in sorted(self.weights):
            days[self._local_day(stamp).isoformat()] = self.weights[stamp]
        series = [{"day": day, "value": kg} for day, kg in sorted(days.items())]
        return json_reply(200, {"metric": "weight_kg", "series": series})

    # `read/logs.py::recent_logs`: the newest weigh-in, its instant in ms.
    def _weight_recent(self) -> Response:
        entries = []
        if self.weights:
            stamp = max(self.weights)
            weight = {"type": "weight", "ts": stamp * 1000, "amount": self.weights[stamp]}
            entries.append({**weight, "unit": "kg"})
        return json_reply(200, {"entries": entries, "fast": None})

    # `read/logs.py::record_log`: upsert on the instant; `core/bounds.py` bounds the mass.
    def _log(self, body: dict) -> Response:
        amount, at = body.get("amount"), body.get("at")
        if body.get("type") != "weight" or not isinstance(at, int):
            return json_reply(422, {"detail": "unsupported in this fake"})
        if not isinstance(amount, (int, float)) or not 20 <= amount <= 300:
            return json_reply(422, {"detail": "implausible weight"})
        self.weights[at // 1000] = float(amount)
        return json_reply(200, {"ok": True})

    def _password_grant(self, request: Request) -> Response:
        body = json.loads(request.body or b"{}")
        right = body.get("email") == self.email and body.get("password") == self.password
        if not right or request.headers.get("apikey") != ANON_KEY:
            return json_reply(400, {"error_code": "invalid_credentials", "msg": "Invalid login"})
        return json_reply(200, {"access_token": JWT, "token_type": "bearer"})

    # ── device tokens ────────────────────────────────────────────────────────

    def _device(self, request: Request) -> Response:
        if request.method == "GET":
            return json_reply(
                200, [{"id": i, "label": t["label"]} for i, t in self.tokens.items() if t["live"]]
            )
        if request.method == "POST":
            if len(self.live_tokens()) >= _MAX_LIVE_TOKENS:
                return json_reply(409, {"detail": "too many device tokens"})
            token_id = str(uuid.uuid4())
            raw = sentinel(f"device-token-{len(self.tokens)}")
            label = json.loads(request.body or b"{}").get("label")
            self.tokens[token_id] = {"token": raw, "label": label, "live": True}
            return json_reply(200, {"device_token": raw, "id": token_id})
        token = self.tokens.get(request.path.rsplit("/", 1)[-1])
        if token is None or not token["live"]:
            return json_reply(404, {"detail": "No live device token with that id"})
        token["live"] = False
        return Response(204, {}, b"")

    # ── workouts ─────────────────────────────────────────────────────────────

    def _ingest(self, request: Request) -> Response:
        bearer = request.headers.get("authorization", "").removeprefix("Bearer ")
        if bearer not in [token["token"] for token in self.live_tokens()]:
            return json_reply(401, {"detail": "Invalid token"})
        payload = json.loads(request.body or b"{}")
        rows = payload.get("workouts", [])
        for index, row in enumerate(rows):
            problem = _workout_problem(row)
            if problem:
                where = ["body", "workouts", index, problem[0]]
                return json_reply(422, {"detail": [{"loc": where, "msg": problem[1]}]})
        self.pushes.append(payload)
        days = set()
        for row in rows:
            stored = self.workouts.setdefault(row["start_ts"], {"sport": 0, "duration_s": 0})
            for column in _COLUMNS:
                if row.get(column) is not None:
                    stored[column] = row[column]
                stored.setdefault(column, None)
            days.add(self._local_day(row["start_ts"] / 1000))
        summary = {"workouts": len(rows), "days_derived": len(days), "samples_accepted": 0}
        return json_reply(200, summary)

    def _local_day(self, epoch_s: float) -> date:
        return datetime.fromtimestamp(epoch_s, tz=zone_for(self.timezone)).date()

    def _activity(self, day: str | None) -> Response:
        today = self._local_day(self.now_s)
        as_of = date.fromisoformat(day) if day else today
        if as_of > today:
            return json_reply(422, {"detail": f"'day' {as_of} is in the future"})
        midnight = datetime.combine(as_of + timedelta(days=1), time.min, zone_for(self.timezone))
        listed = [
            (start_ms, row)
            for start_ms, row in sorted(self.workouts.items(), reverse=True)
            if (row["duration_s"] or 0) >= _MIN_LISTED_S and start_ms / 1000 < midnight.timestamp()
        ][:_LIST_ROWS]
        workouts = [
            {
                "start_iso": datetime.fromtimestamp(start_ms / 1000, tz=UTC).isoformat(),
                "sport": row["sport"],
                "duration_min": round(row["duration_s"] / 60),
                **{column: row.get(column) for column in self.listed_columns},
            }
            for start_ms, row in listed
        ]
        return json_reply(200, {"date": as_of.isoformat(), "workouts": workouts})

    # ── routes ───────────────────────────────────────────────────────────────

    def _track_list(self, limit: int) -> Response:
        newest = sorted(self.tracks.items(), key=lambda item: item[1]["start_s"], reverse=True)
        tracks = [
            {
                "track_id": track_id,
                "start_ts": datetime.fromtimestamp(track["start_s"], tz=UTC).isoformat(),
                "end_ts": datetime.fromtimestamp(track["end_s"], tz=UTC).isoformat(),
            }
            for track_id, track in newest[: max(1, min(limit, _LIST_ROWS))]
        ]
        return json_reply(200, {"tracks": tracks})

    def _track_upload(self, body: dict) -> Response:
        problem = _route_problem(body)
        if problem:
            return json_reply(422, {"detail": [{"loc": ["body"], "msg": problem}]})
        start_s = datetime.fromisoformat(body["start_iso"]).timestamp()
        end_s = datetime.fromisoformat(body["end_iso"]).timestamp()
        points = body["points"]
        if len(points) < 10:
            return json_reply(200, {"ok": False, "reason": f"too few valid points ({len(points)})"})
        track_id = body.get("client_id") or str(uuid.uuid4())
        stored = self.tracks.get(track_id)
        if stored is not None:
            if (stored["start_s"], stored["end_s"]) != (start_s, end_s):
                return json_reply(200, {"ok": False, "reason": "recording identity conflict"})
            reply = {"ok": True, "track_id": track_id, "points": stored["points"], "vo2max": None}
            return json_reply(200, reply)
        self.tracks[track_id] = {"start_s": start_s, "end_s": end_s, "points": len(points)}
        self.tracks[track_id]["body"] = body
        scoring = self.scoring or {"ok": False, "reason": "no HR for this window"}
        reply = {"ok": True, "track_id": track_id, "points": len(points), "vo2max": scoring}
        return json_reply(200, reply)


def _workout_problem(row: dict) -> tuple[str, str] | None:
    """`ingest/models.py::WorkoutIn`, as far as an import can violate it."""
    if not isinstance(row.get("start_ts"), int):
        return "start_ts", "Input should be a valid integer"
    duration = row.get("duration_s")
    if duration is not None and not (isinstance(duration, int) and 0 <= duration <= _WEEK_S):
        return "duration_s", "Input should be between 0 and a week"
    distance = row.get("distance_m")
    if distance is not None and not (isinstance(distance, (int, float)) and distance >= 0):
        return "distance_m", "Input should be greater than or equal to 0"
    for column in ("sport", "calories", "avg_hr", "max_hr", "min_hr"):
        if row.get(column) is not None and not isinstance(row[column], int):
            return column, "Input should be a valid integer"
    return None


def _route_problem(body: dict) -> str | None:
    """`read/gps_request.py::GpsTrackIn.valid_route`, rule for rule."""
    start, end = datetime.fromisoformat(body["start_iso"]), datetime.fromisoformat(body["end_iso"])
    if start.tzinfo is None or end.tzinfo is None or end <= start:
        return "route requires an ordered window with timezone offsets"
    if len(body["points"]) > _MAX_POINTS:
        return "List should have at most 28800 items"
    previous = float("-inf")
    for point in body["points"]:
        if len(point) not in (3, 4) or any(value is None for value in point[:3]):
            return "points require timestamp, latitude, longitude, optional elevation"
        timestamp, lat, lng = point[:3]
        if not (-90 <= lat <= 90 and -180 <= lng <= 180):
            return "invalid GPS coordinates"
        if not start.timestamp() <= timestamp <= end.timestamp() or timestamp <= previous:
            return "GPS timestamps must increase within the recording window"
        previous = timestamp
    return None
