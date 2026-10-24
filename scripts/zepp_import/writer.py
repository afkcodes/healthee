"""Writing a confirmed plan to Healthee, and writing down what was written.

## Order

Routes go first, summaries second. A summary push re-derives every day it touches
(`ingest/service.py`), and that pass scores any track the upload itself had to refuse
(`derive/gps_scoring.py::score_day_tracks`). Sending the routes first means the one pass
sees them.

## The record is kept as things land

Each stored route and each accepted chunk of summaries is noted in the ledger when the
server confirms it, and the ledger is saved even when a later step fails. So is
`Writer.outcome`: a failure halfway through is reported together with what had already
been stored, because "it failed" and "it failed after writing two routes" are different
things to be told.

Running the same import again is the recovery for every failure here. The server keys a
summary on its start and a route on a derived id (`plan.py`), so nothing lands twice.
"""

from __future__ import annotations

from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from datetime import tzinfo

from zepp_import import report
from zepp_import.healthee_api import HealtheeApi
from zepp_import.ledger import Ledger
from zepp_import.plan import Decision
from zepp_import.report import Out


@dataclass
class Outcome:
    """What one run stored. Filled in as it goes, so it is right after a failure too."""

    routes_stored: int = 0
    routes_refused: int = 0
    summaries_stored: int = 0
    days_derived: int = 0
    token_revoked: bool = True

    @property
    def wrote_anything(self) -> bool:
        return bool(self.routes_stored or self.summaries_stored)


class Writer:
    """Applies decisions to one Healthee account and keeps the ledger in step."""

    def __init__(
        self, api: HealtheeApi, ledger: Ledger, user_id: str, zone: tzinfo, out: Out, stamp: str
    ) -> None:
        self._api = api
        self._ledger = ledger
        self._user_id = user_id
        self._zone = zone
        self._out = out
        self._stamp = stamp
        self.outcome = Outcome()

    def write(self, decisions: Sequence[Decision], *, summaries: bool, routes: bool) -> Outcome:
        """Store what was confirmed. `decisions` are newest first; writes go oldest first."""
        oldest_first = list(reversed(decisions))
        try:
            if routes:
                for decision in oldest_first:
                    if decision.route.payload is not None:
                        self._route(decision, decision.route.payload)
            wanted = [d for d in oldest_first if d.summary.payload is not None]
            if summaries and wanted:
                self._summaries(wanted)
        finally:
            self._ledger.save()
        return self.outcome

    def _record(self, decision: Decision, entry: Mapping[str, object]) -> None:
        self._ledger.record(self._api.base_url, self._user_id, decision.workout.track_id, entry)

    def _route(self, decision: Decision, payload: dict) -> None:
        verdict = self._api.push_track(payload)
        label = f"{report.when(decision.workout.start_s, self._zone)}  route"
        if verdict.get("ok") is not True:
            self.outcome.routes_refused += 1
            reason = str(verdict.get("reason") or "no reason given")
            self._out(report.wrapped(f"{label} refused: {reason}", indent="  ", hang="    "))
            return
        self.outcome.routes_stored += 1
        self._record(
            decision,
            {
                "route_id": payload["client_id"],
                "route_points": decision.route_points,
                "route_at": self._stamp,
            },
        )
        self._out(f"  {label} stored, {decision.route_points:,} points")
        self._out(report.wrapped(report.fitness_note(verdict.get("vo2max")), hang="  "))

    def _summaries(self, decisions: Sequence[Decision]) -> None:
        by_start = {d.summary.payload["start_ts"]: d for d in decisions if d.summary.payload}

        def stored(chunk: Sequence[Mapping[str, object]]) -> None:
            for row in chunk:
                decision = by_start[row["start_ts"]]
                self._record(
                    decision,
                    {
                        "start_ts": row["start_ts"],
                        "summary": decision.summary.verdict.value,
                        "summary_at": self._stamp,
                    },
                )
            self.outcome.summaries_stored += len(chunk)

        payloads = [d.summary.payload for d in decisions if d.summary.payload]
        result = self._api.push_workouts(payloads, stored=stored)
        self.outcome.days_derived = result.days_derived
        self.outcome.token_revoked = result.token_revoked
        count = report.counted(self.outcome.summaries_stored, "workout")
        days = report.counted(result.days_derived, "day")
        self._out(f"  {count} stored, {days} recalculated")
