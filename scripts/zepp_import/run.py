"""One import run, start to finish. The order is the design:

1. **Healthee first.** Its sign-in is checked before a Zepp password is asked for, so a
   wrong server address costs nothing but itself. The owner is shown which host the
   Healthee password goes to before typing it.
2. **Read what Healthee holds.** The plan is a comparison; both sides must be in hand.
3. **Zepp: sign in, read, sign out.** The session is ended before anything is written,
   so it lives for the seconds it is needed.
4. **Show the plan** — every session in the window, and what would happen to it.
5. **Ask.** Summaries and routes are separate questions, because a route feeds the
   fitness estimate and this tool cannot take one back.
6. **Write**, and record what was written (`writer.py`).
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from datetime import date, datetime, time, tzinfo

from zepp_import import failures, report, zepp_wire
from zepp_import.deps import Deps
from zepp_import.gather import Gathered, Stored
from zepp_import.healthee_api import TOKEN_LEFT, TRACK_LIST_LIMIT, HealtheeApi
from zepp_import.healthee_rows import normalise_url
from zepp_import.healthee_session import Account, HealtheeSession
from zepp_import.ledger import Ledger, default_path
from zepp_import.localtime import UTC, label, utc_iso, zone_for
from zepp_import.plan import StoredTracks
from zepp_import.prompts import Settings, load_env_file
from zepp_import.transport import host_of
from zepp_import.weight_run import WeightRun
from zepp_import.writer import Outcome, Writer
from zepp_import.zepp_run import ZeppRun

_DAY_S = 86_400
_DEFAULT_DAYS = 30
_MAX_DAYS = 3650


@dataclass(frozen=True)
class Window:
    """The stretch of time an import looks at, in epoch seconds."""

    since_s: int
    now_s: int


def window_for(days: int | None, since: str | None, now: float, zone: tzinfo) -> Window:
    """`--since` (the owner's local midnight) or `--days`, as a window ending now."""
    now_s = int(now)
    if since is None:
        span_days = _DEFAULT_DAYS if days is None else days
        if not 1 <= span_days <= _MAX_DAYS:
            raise failures.bad_setting("--days", f"expected 1 to {_MAX_DAYS}")
        return Window(now_s - span_days * _DAY_S, now_s)
    try:
        first_day = date.fromisoformat(since)
    except ValueError:
        raise failures.bad_setting("--since", "expected a date like 2026-09-01") from None
    since_s = int(datetime.combine(first_day, time.min, tzinfo=zone).timestamp())
    if since_s >= now_s:
        raise failures.bad_setting("--since", "must be a date in the past")
    return Window(since_s, now_s)


class Run:
    """One invocation. Holds the arguments and the outside world; `go` does the rest."""

    def __init__(self, args: argparse.Namespace, deps: Deps) -> None:
        self._args = args
        self._deps = deps
        self._out = deps.out
        self._take_summaries = False
        self._take_routes = False

    def go(self) -> int:
        args, deps = self._args, self._deps
        self._check_arguments()
        ledger = Ledger.load(args.state_file or default_path(deps.env))
        settings = self._settings(ledger)
        api, account = self._healthee(settings, ledger)
        zone = self._zone(account)
        window = window_for(args.days, args.since, deps.now(), zone)
        stored = self._stored(api, account, window)
        zepp = ZeppRun(args, deps, settings, ledger)
        gathered = zepp.gather(stored, window.since_s, window.now_s)
        ledger.save()
        self._show(gathered, zone, window)
        status = 0
        if self._confirmed_anything(gathered, settings):
            status = self._write(gathered, api, ledger, account, zone)
        weights = WeightRun(args, api.session, ledger, account.user_id, self._out)
        return max(status, weights.go(zepp.weights, zone, settings, deps.terminal.interactive))

    # ── settings and the Healthee side ───────────────────────────────────────

    def _check_arguments(self) -> None:
        """Refuse a malformed argument before a single password is asked for."""
        window_for(self._args.days, self._args.since, self._deps.now(), UTC)
        if self._args.zepp_host:
            try:
                zepp_wire.checked_api_host(self._args.zepp_host)
            except ValueError as error:
                raise failures.bad_setting("--zepp-host", str(error)) from None

    def _settings(self, ledger: Ledger) -> Settings:
        # A variable already in the environment wins over the same name in the file.
        from_file = load_env_file(self._args.env_file) if self._args.env_file else {}
        return Settings({**from_file, **self._deps.env}, ledger.setting, self._deps.terminal)

    def _healthee(self, settings: Settings, ledger: Ledger) -> tuple[HealtheeApi, Account]:
        address = settings.text("healthee_url", "Healthee address", self._args.healthee_url)
        session = HealtheeSession(normalise_url(address), self._deps.send)
        self._out(f"Healthee: {host_of(session.base_url)}")
        self._out(f"  its sign-in goes to {session.sign_in_host()}")
        if self._deps.terminal.interactive and not settings.known("healthee_email"):
            # Asked from nothing: the owner may not know Healthee has a login at all.
            self._out(report.wrapped(report.HEALTHEE_LOGIN_NOTE, indent="  "))
        email = settings.text("healthee_email", "Healthee email")
        account = session.sign_in(email, settings.secret("healthee_password", "Healthee password"))
        ledger.remember({"healthee_url": session.base_url, "healthee_email": email})
        ledger.save()
        self._out("  signed in")
        api = HealtheeApi(session)
        swept = api.revoke_leftovers()
        if swept:
            tokens = report.counted(swept, "temporary token")
            self._out(f"  revoked {tokens} left by an earlier run")
        return api, account

    def _zone(self, account: Account) -> tzinfo:
        zone = zone_for(account.timezone)
        if label(zone) != account.timezone:
            note = f"times below are in UTC: this device has no data for {account.timezone}"
            self._out(report.wrapped(note, indent="  "))
        return zone

    def _stored(self, api: HealtheeApi, account: Account, window: Window) -> Stored:
        # A day further back than the window: a stored session can start before it and
        # still overlap one inside it.
        workouts = api.existing_workouts(window.since_s - _DAY_S)
        tracks = [] if self._args.no_routes else api.existing_tracks()
        return Stored(account.user_id, workouts, StoredTracks.listed(tracks, TRACK_LIST_LIMIT))

    # ── the plan, the question, the write ────────────────────────────────────

    def _show(self, gathered: Gathered, zone: tzinfo, window: Window) -> None:
        found = report.counted(len(gathered.decisions), "Zepp workout")
        since = f"Since {report.day(window.since_s, zone)} ({label(zone)}): {found}"
        self._out("")
        self._out(report.wrapped(since, indent=""))
        report.plan(gathered.decisions, zone, self._out)
        if gathered.unreadable:
            records = report.counted(gathered.unreadable, "Zepp record")
            note = f"{records} could not be read and left out. Run with --verbose for the shape."
            self._out(report.wrapped(note, indent=""))
        if gathered.tracks_asked and not gathered.tracks_found:
            self._out(report.wrapped(report.NO_TRACKS_NOTE, indent=""))

    def _confirmed_anything(self, gathered: Gathered, settings: Settings) -> bool:
        """Say what would be written, then ask. Sets what the owner agreed to."""
        summaries, routes = report.writes(gathered.decisions)
        self._out("")
        if not summaries and not routes:
            self._out("Nothing to import.")
            return False
        self._out(f"To write: {report.to_write(summaries, routes)}.")
        if routes:
            self._out("")
            self._out(report.wrapped(report.ROUTE_NOTE, indent=""))
        if self._args.dry_run:
            self._out("")
            self._out("Dry run: nothing was written.")
            return False
        self._ask(settings, summaries, routes)
        if not (self._take_summaries or self._take_routes):
            self._out("Nothing was written.")
        return self._take_summaries or self._take_routes

    def _ask(self, settings: Settings, summaries: int, routes: int) -> None:
        if self._args.yes:
            self._take_summaries, self._take_routes = summaries > 0, routes > 0
            return
        if not self._deps.terminal.interactive:
            raise failures.unconfirmed()
        self._out("")
        if summaries:
            wanted = report.counted(summaries, "workout")
            self._take_summaries = settings.confirm(f"Import {wanted}?")
            if not self._take_summaries:
                return  # a route follows its session; with no summaries there is no import
        if routes:
            wanted = report.counted(routes, "route")
            self._take_routes = settings.confirm(f"Import {wanted}{' too' if summaries else ''}?")

    def _write(
        self, gathered: Gathered, api: HealtheeApi, ledger: Ledger, account: Account, zone: tzinfo
    ) -> int:
        stamp = utc_iso(self._deps.now())
        writer = Writer(api, ledger, account.user_id, zone, self._out, stamp)
        self._out("")
        try:
            outcome = writer.write(
                gathered.decisions, summaries=self._take_summaries, routes=self._take_routes
            )
        except failures.ZeppImportError:
            if writer.outcome.wrote_anything:
                before = f"Stored before the failure below: {_stored(writer.outcome)}."
                self._out(report.wrapped(before, indent=""))
            raise
        return self._done(outcome)

    def _done(self, outcome: Outcome) -> int:
        if not outcome.token_revoked:
            self._out(report.wrapped(f"Warning: {TOKEN_LEFT}", indent=""))
        self._out("")
        self._out(f"Done: {_stored(outcome)} stored.")
        if outcome.routes_refused:
            refused = report.counted(outcome.routes_refused, "route")
            self._out(f"{refused} refused by Healthee; see above.")
            return 1
        self._out("They show in the Healthee app when it next loads.")
        return 0


def _stored(outcome: Outcome) -> str:
    return report.to_write(outcome.summaries_stored, outcome.routes_stored)
