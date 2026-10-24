"""Nothing secret reaches the screen or the disk, and each secret goes to one place only.

Every credential in these tests is a sentinel (`support.sentinel`), so a leak is findable
by searching for one word. Each scenario runs the real command — success, every kind of
failure, `--verbose` — and then searches everything a person could see and everything
left on disk.

The second half is about direction: the Zepp password goes to Zepp and the Healthee
password to Healthee's sign-in, and neither side ever receives the other's.
"""

from __future__ import annotations

import unittest
from collections.abc import Callable

from zepp_import.tests.fake_healthee import AUTH_ORIGIN, JWT, ORIGIN
from zepp_import.tests.fake_zepp import ACCESS, APP_TOKEN, LOGIN_TOKEN
from zepp_import.tests.support import json_reply, sentinel
from zepp_import.tests.terminal import CliResult
from zepp_import.tests.world import HEALTHEE_PASSWORD, ZEPP_PASSWORD, World
from zepp_import.transport import Response
from zepp_import.zepp_wire import HISTORY_PATH, LOGOUT_URL

YES = {"Import": "y"}
MARK = "SENTINEL"
COORDINATES = ("1000000000", "2000000000", "10.0000", "20.0000")


def _echoing(world: World) -> None:
    """A server that quotes the caller's own credentials back in its refusals."""
    real = world.healthee.handle

    def handle(request: object) -> Response:
        bearer = request.headers.get("authorization", "")  # type: ignore[attr-defined]
        if request.path in ("/ingest/helio", "/api/workout/gps") and request.method == "POST":  # type: ignore[attr-defined]
            return json_reply(422, {"detail": f"rejected {bearer} for {HEALTHEE_PASSWORD}"})
        return real(request)  # type: ignore[arg-type]

    world.healthee.handle = handle  # type: ignore[method-assign]


def _odd_login(world: World) -> None:
    world.zepp.forced["/v2/client/login"] = json_reply(200, {"oops": sentinel("login-body")})


def _odd_feed(world: World) -> None:
    body = {"code": 1, "data": {"rows": [{"owner": sentinel("feed-body"), "trackid": "1"}]}}
    world.zepp.forced[HISTORY_PATH] = json_reply(200, body)


def _feed_error_message(world: World) -> None:
    world.zepp.forced[HISTORY_PATH] = json_reply(200, {"code": 0, "message": sentinel("message")})


def _no_revoke(world: World) -> None:
    real = world.healthee.handle

    def handle(request: object) -> Response:
        if request.method == "DELETE":  # type: ignore[attr-defined]
            return json_reply(500, {"detail": request.headers.get("authorization")})  # type: ignore[attr-defined]
        return real(request)  # type: ignore[arg-type]

    world.healthee.handle = handle  # type: ignore[method-assign]


SCENARIOS: dict[str, tuple[Callable[[World], None] | None, tuple[str, ...], dict[str, str]]] = {
    "a full import": (None, (), YES),
    "a full import, verbose": (None, ("--verbose",), YES),
    "a dry run, verbose": (None, ("--dry-run", "--verbose"), {}),
    "a wrong Zepp password": (None, (), {"Zepp password": sentinel("wrong-zepp-pw")}),
    "a wrong Healthee password": (None, (), {"Healthee password": sentinel("wrong-h-pw")}),
    "a Zepp login reply nobody expected": (_odd_login, ("--verbose",), YES),
    "a Zepp feed nobody expected": (_odd_feed, ("--verbose",), YES),
    "a Zepp error with a message": (_feed_error_message, ("--verbose",), YES),
    "a server that echoes credentials": (_echoing, ("--verbose",), YES),
    "a token that will not revoke": (_no_revoke, (), YES),
}


class NothingLeaks(unittest.TestCase):
    def run_scenario(self, name: str) -> tuple[World, CliResult]:
        prepare, argv, answers = SCENARIOS[name]
        world = World()
        if prepare is not None:
            prepare(world)
        return world, world.run(*argv, answers=answers)

    def test_no_credential_is_ever_printed(self) -> None:
        for name in SCENARIOS:
            _world, result = self.run_scenario(name)
            with self.subTest(scenario=name):
                self.assertNotIn(MARK, result.text)
                self.assertNotIn(MARK, " ".join(result.script.asked))

    def test_no_credential_is_ever_written_to_disk(self) -> None:
        for name in SCENARIOS:
            world, _result = self.run_scenario(name)
            if world.state.exists():
                with self.subTest(scenario=name):
                    self.assertNotIn(MARK, world.state.read_text())
            leftovers = [path.name for path in world.state.parent.iterdir()]
            self.assertLessEqual(set(leftovers), {"ledger.json"})

    def test_no_location_is_printed_or_stored(self) -> None:
        for name in ("a full import, verbose", "a dry run, verbose", "a Zepp feed nobody expected"):
            world, result = self.run_scenario(name)
            stored = world.state.read_text() if world.state.exists() else ""
            for digits in COORDINATES:
                with self.subTest(scenario=name, digits=digits):
                    self.assertNotIn(digits, result.text)
                    self.assertNotIn(digits, stored)

    def test_the_scenarios_do_exercise_the_failures_they_name(self) -> None:
        expected = {
            "a full import": 0,
            "a dry run, verbose": 0,
            "a wrong Zepp password": 1,
            "a wrong Healthee password": 1,
            "a Zepp login reply nobody expected": 1,
            "a Zepp feed nobody expected": 1,
            "a Zepp error with a message": 1,
            "a server that echoes credentials": 1,
            "a token that will not revoke": 0,
        }
        for name, status in expected.items():
            with self.subTest(scenario=name):
                self.assertEqual(self.run_scenario(name)[1].status, status)

    def test_an_echoed_credential_is_cut_out_of_the_servers_reason(self) -> None:
        _world, result = self.run_scenario("a server that echoes credentials")
        said = " ".join(result.text.split())  # the reason is wrapped to the phone's width
        self.assertIn("rejected Bearer [redacted] for [redacted]", said)


class EachSecretGoesToOnePlace(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.world = World()
        cls.world.run("--verbose", answers=YES)
        cls.requests = cls.world.net.requests

    def holders(self, secret: str) -> set[str]:
        return {request.origin for request in self.requests if secret in request.everything()}

    def test_the_zepp_password_is_never_sent_in_the_clear_to_anyone(self) -> None:
        self.assertEqual(self.holders(ZEPP_PASSWORD), set())

    def test_the_healthee_password_goes_only_to_healthees_sign_in(self) -> None:
        self.assertEqual(self.holders(HEALTHEE_PASSWORD), {AUTH_ORIGIN})

    def test_the_zepp_tokens_go_only_to_zepp(self) -> None:
        for token in (APP_TOKEN, LOGIN_TOKEN, ACCESS):
            for origin in self.holders(token):
                with self.subTest(origin=origin):
                    self.assertRegex(origin, r"^https://api-mifit[a-z0-9-]*\.(zepp|huami)\.com$")
        self.assertEqual(
            {r.url for r in self.requests if LOGIN_TOKEN in r.everything()}, {LOGOUT_URL}
        )

    def test_healthees_tokens_go_only_to_healthee(self) -> None:
        self.assertEqual(self.holders(JWT), {ORIGIN})
        device_token = next(iter(self.world.healthee.tokens.values()))["token"]
        users = {(r.origin, r.path) for r in self.requests if device_token in r.everything()}
        self.assertEqual(users, {(ORIGIN, "/ingest/helio")})

    def test_the_route_goes_to_healthee_and_only_there(self) -> None:
        carriers = {
            r.origin for r in self.requests if r.method == "POST" and b"10.0000" in (r.body or b"")
        }
        self.assertEqual(carriers, {ORIGIN})

    def test_nothing_from_healthee_is_sent_to_zepp(self) -> None:
        to_zepp = " ".join(r.everything() for r in self.requests if "healthee" not in r.origin)
        for secret in (HEALTHEE_PASSWORD, JWT, "owner@healthee.example", "healthee.test"):
            with self.subTest(secret=secret[:12]):
                self.assertNotIn(secret, to_zepp)

    def test_the_zepp_email_is_sent_to_zepp_only_inside_the_encrypted_body(self) -> None:
        self.assertEqual(self.holders("runner@zepp.example"), set())
        self.assertEqual(self.holders("runner%40zepp.example"), set())


if __name__ == "__main__":
    unittest.main()
