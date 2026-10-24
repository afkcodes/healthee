"""The weight half of a run: show what would change, ask, write, and say what happened.

It runs after the workouts, with Zepp already signed out (the readings were taken while
the session was open, `zepp_run.py`). A failure here is reported and makes the exit
status 1, but it never undoes or blocks the workout import before it: they are separate
records and either is useful without the other.
"""

from __future__ import annotations

import argparse
from collections.abc import Callable
from datetime import tzinfo

from zepp_import import failures, report
from zepp_import.healthee_session import HealtheeSession
from zepp_import.healthee_weights import existing_weights, push_weight
from zepp_import.ledger import Ledger
from zepp_import.prompts import Settings
from zepp_import.weights import Weighing, describe, plan, to_write

ZeppWeights = tuple[list[Weighing], int] | str | None  # None: not asked for


class WeightRun:
    def __init__(
        self,
        args: argparse.Namespace,
        session: HealtheeSession,
        ledger: Ledger,
        user_id: str,
        out: Callable[[str], None],
    ) -> None:
        self._args = args
        self._session = session
        self._ledger = ledger
        self._user_id = user_id
        self._out = out

    def go(self, zepp: ZeppWeights, zone: tzinfo, settings: Settings, interactive: bool) -> int:
        if zepp is None:
            return 0
        self._out("")
        if isinstance(zepp, str):
            self._out(report.wrapped(f"Weight: Zepp's weight log could not be read ({zepp}).", ""))
            self._out("  No weight was changed.")
            return 1
        weighings, unreadable = zepp
        server = self._session.base_url
        sent = self._ledger.weights_sent(server, self._user_id)
        steps = plan(weighings, existing_weights(self._session), zone, sent)
        self._out(f"Weight: {report.counted(len(steps), 'day')} weighed in Zepp")
        for step in steps:
            self._out(f"  {describe(step)}")
        if unreadable:
            self._out(f"  {report.counted(unreadable, 'Zepp reading')} could not be read")
        writes = to_write(steps)
        if not writes:
            self._out("Weight: nothing to change.")
            return 0
        wanted = report.counted(len(writes), "weight")
        if not self._agreed(wanted, settings, interactive):
            return 0
        for step in writes:
            push_weight(self._session, step.write_ts_s, step.zepp.kg)
            self._ledger.record_weight(server, self._user_id, step.write_ts_s, step.zepp.kg)
            self._ledger.save()
        self._out(f"Weight: {wanted} stored.")
        return 0

    def _agreed(self, wanted: str, settings: Settings, interactive: bool) -> bool:
        if self._args.dry_run:
            self._out(f"Weight: would write {wanted}. Dry run: nothing was written.")
            return False
        if self._args.yes:
            return True
        if not interactive:
            raise failures.unconfirmed()
        if settings.confirm(f"Write {wanted} to Healthee?"):
            return True
        self._out("Weight: nothing was written.")
        return False
