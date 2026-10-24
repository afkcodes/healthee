"""The Zepp half of one run: sign in, find the account's host, read the window, sign out.

The session this opens is ended in a `finally`, before anything is written to Healthee
and whether or not the read worked. It lives for the seconds it is needed.

## Which hosts can receive the token

Only Zepp's own: the hosts this tool ships with, a host the login reply named (and
`zepp_wire.api_hosts_in` keeps only Zepp API names from that), a `--zepp-host` that passes
the same pattern, or the host an earlier run recorded — which is read back from a FILE,
and so is put through the same pattern before it is trusted.
"""

from __future__ import annotations

import argparse

from zepp_import import failures, zepp_auth, zepp_wire
from zepp_import.deps import Deps
from zepp_import.gather import Gathered, Gatherer, Stored
from zepp_import.ledger import Ledger
from zepp_import.prompts import Settings
from zepp_import.transport import host_of
from zepp_import.weight_run import ZeppWeights
from zepp_import.zepp_api import ZeppApi
from zepp_import.zepp_auth import ZeppSession
from zepp_import.zepp_history import ZeppHistory
from zepp_import.zepp_weights import read_weights


class ZeppRun:
    """Everything one run asks of Zepp. `gather` is the only entry point."""

    def __init__(
        self, args: argparse.Namespace, deps: Deps, settings: Settings, ledger: Ledger
    ) -> None:
        self._args = args
        self._deps = deps
        self._settings = settings
        self._ledger = ledger
        self.weights: ZeppWeights = None

    def gather(self, stored: Stored, since_s: int, now_s: int) -> Gathered:
        """The plan for every Zepp workout that started in `[since_s, now_s]`."""
        deps = self._deps
        session, opened_here = self._session()
        try:
            history = ZeppHistory(
                session,
                deps.endpoints,
                deps.send,
                notify=self._note,
                trace=self._trace,
                pause=deps.pause,
            )
            first_host, named = self._first_host(session)
            feed = history.feed(since_s, now_s, first_host, named=named)
            self._ledger.remember_zepp_host(session.user_id, feed.host)
            self._note(f"your workouts are on {host_of(feed.host)}")
            gatherer = Gatherer(
                history,
                stored,
                want_routes=not self._args.no_routes,
                notify=self._note,
                pause=deps.pause,
            )
            gathered = gatherer.gather(feed)
            if not self._args.no_weight and not session.user_id:
                self._note("weight left out: the weight log needs ZEPP_USER_ID")
            elif not self._args.no_weight:
                api = ZeppApi(session, deps.send, pause=deps.pause, trace=self._trace)
                self.weights = read_weights(api, feed.host, session.user_id)
            return gathered
        finally:
            if opened_here:
                ended = zepp_auth.sign_out(session, deps.endpoints, deps.send)
                self._note("signed out" if ended else "sign-out not confirmed; it expires")

    def _note(self, line: str) -> None:
        self._deps.out(f"  Zepp: {line}")

    def _trace(self, line: str) -> None:
        if self._args.verbose:
            self._deps.out(f"  [shape] {line}")

    def _session(self) -> tuple[ZeppSession, bool]:
        """(session, whether this run opened it). An app token in the environment is used as is."""
        settings = self._settings
        token = settings.from_env("zepp_app_token")
        if token:
            self._note("using ZEPP_APP_TOKEN from the environment")
            return ZeppSession(user_id=settings.from_env("zepp_user_id"), app_token=token), False
        email = settings.text("zepp_email", "Zepp email")
        password = settings.secret("zepp_password", "Zepp password")
        session = zepp_auth.sign_in(email, password, self._deps.endpoints, self._deps.send)
        self._ledger.remember({"zepp_email": email})
        self._ledger.save()
        self._note("signed in")
        return session, True

    def _first_host(self, session: ZeppSession) -> tuple[str | None, bool]:
        """(the Zepp host to ask first, whether the owner named it)."""
        if self._args.zepp_host:
            try:
                return zepp_wire.checked_api_host(self._args.zepp_host), True
            except ValueError as error:
                raise failures.bad_setting("--zepp-host", str(error)) from None
        remembered = self._ledger.zepp_host(session.user_id)
        endpoints = self._deps.endpoints
        if remembered in (*endpoints.primary_hosts, *endpoints.region_hosts):
            return remembered, False
        return (remembered if remembered and zepp_wire.is_api_host(remembered) else None), False
